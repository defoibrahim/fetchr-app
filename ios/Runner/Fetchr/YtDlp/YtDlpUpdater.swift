import CryptoKit
import Foundation

// Installs the latest official yt-dlp zipapp under `<root>/<version>/` for the next launch to run: Python cannot be
// re-initialised in-process, and the bundle is read-only. Only pure Python ever comes this way; the bundled Python
// and ffmpeg change only with an app build.
actor YtDlpUpdater {
  static let latestRelease = URL(string: "https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest")!
  static let checkedAtKey = "fetchr.ytDlpCheckedAt"
  static let autoUpdateKey = "fetchr.ytDlpAutoUpdate"
  // Written last into a version dir: a dir without it was cut short and is never run.
  static let completeMarker = ".complete"
  private static let keep = 2
  private static let asset = "yt-dlp"
  private static let sumsAsset = "SHA2-256SUMS"

  private static let offline = FetchrError(
    code: "network", message: ErrorClassifier.networkMessage, details: nil)
  private static let unreachable = FetchrError(
    code: "network", message: "Couldn't reach GitHub to update yt-dlp. Try again later.", details: nil)
  private static let damaged = FetchrError(
    code: "unknown", message: "The yt-dlp update could not be verified. Try again later.", details: nil)
  private static let untrusted = FetchrError(
    code: "unknown", message: "The yt-dlp update did not come from GitHub.", details: nil)
  private static let failedHere = FetchrError(
    code: "unknown", message: "This yt-dlp release failed to start on this iPhone. Fetchr will wait for the next one.",
    details: nil)
  private static let tooSlow = FetchrError(
    code: "network", message: "Updating yt-dlp took too long. Check your connection and try again.", details: nil)

  // Release assets are github.com links, which redirect to GitHub's asset CDN; every answer must come from these.
  private static let assetHost = "github.com"
  private static let trustedHosts: Set<String> = [
    "api.github.com", "github.com", "objects.githubusercontent.com", "release-assets.githubusercontent.com",
  ]

  let root: URL
  private let session: URLSession
  private let gate: RunGate
  // UserDefaults is thread-safe; the SDK just does not mark it Sendable.
  private nonisolated(unsafe) let defaults: UserDefaults
  // For the whole update, API, sums and zipapp together: runs wait while it holds the gate.
  private let deadline: TimeInterval
  private let compile: Compile?

  typealias Compile = @Sendable (URL) async throws -> Void

  init(
    root: URL, session: URLSession, gate: RunGate, defaults: UserDefaults, deadline: TimeInterval = 120,
    compile: Compile? = nil
  ) {
    self.root = root
    self.session = session
    self.gate = gate
    self.defaults = defaults
    self.deadline = deadline
    self.compile = compile
  }

  static func makeSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = 30
    config.timeoutIntervalForResource = 120
    config.waitsForConnectivity = false
    return URLSession(configuration: config)
  }

  nonisolated var checkedAtMs: Int64? { Self.checkedAtMs(in: defaults) }

  nonisolated var autoUpdate: Bool { Self.autoUpdate(in: defaults) }

  static func checkedAtMs(in defaults: UserDefaults) -> Int64? {
    (defaults.object(forKey: checkedAtKey) as? NSNumber).map(\.int64Value).flatMap { $0 > 0 ? $0 : nil }
  }

  static func autoUpdate(in defaults: UserDefaults) -> Bool {
    defaults.object(forKey: autoUpdateKey) as? Bool ?? true
  }

  // Complete versions, newest first.
  nonisolated func installed() -> [String] {
    let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
    return names.filter { name in
      YtDlpVersion.isValid(name)
        && FileManager.default.fileExists(atPath: root.appendingPathComponent("\(name)/\(Self.completeMarker)").path)
    }.sorted { YtDlpVersion.newer($0, than: $1) }
  }

  // The latest release's version once it is installed, or `running` when that is already the latest. Busy while
  // any yt-dlp run is active; runs started meanwhile wait until it ends, as on Android.
  func update(running: String? = nil) async throws -> String {
    try await gate.beginSwap()
    do {
      let version = try await withDeadline { try await self.install(running: running) }
      await gate.endSwap()
      defaults.set(NSNumber(value: Date().epochMs), forKey: Self.checkedAtKey)
      return version
    } catch {
      await gate.endSwap()
      Log.ytdlp.error("yt-dlp update failed: \(String(describing: error), privacy: .public)")
      throw error
    }
  }

  // The body is canceled when the deadline passes, and the update fails once it has unwound. A deadline that passes
  // after install's last cancellation check still fails the update, though `.complete` is then written: that
  // version is verified and whole, and runs at the next launch like any other.
  private func withDeadline<T: Sendable>(_ body: @escaping @Sendable () async throws -> T) async throws -> T {
    let nanoseconds = UInt64(deadline * 1e9)
    return try await withThrowingTaskGroup(of: T.self) { group in
      group.addTask { try await body() }
      group.addTask {
        try await Task.sleep(nanoseconds: nanoseconds)
        throw Self.tooSlow
      }
      defer { group.cancelAll() }
      guard let first = try await group.next() else { throw Self.tooSlow }
      return first
    }
  }

  private func install(running: String?) async throws -> String {
    let fm = FileManager.default
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    root.excludeFromBackup()
    clearLeftovers()

    let release = try await latest()
    // It failed a launch here: never offered again, even while its files wait for the next launch to delete them.
    if launchRecord().bad.contains(release.version) {
      Log.ytdlp.notice("yt-dlp \(release.version, privacy: .public) failed a launch before; not installed again")
      guard let running else { throw Self.failedHere }
      return running
    }
    if let running, !YtDlpVersion.newer(release.version, than: running) { return running }
    if installed().contains(release.version) { return release.version }

    let downloads = root.appendingPathComponent(".download", isDirectory: true)
    try fm.createDirectory(at: downloads, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: downloads) }
    let sums = try String(contentsOf: try await fetch(release.sums, as: Self.sumsAsset, into: downloads), encoding: .utf8)
    guard let expected = Self.sum(of: Self.asset, in: sums) else {
      Log.ytdlp.error("\(Self.sumsAsset, privacy: .public) lists no \(Self.asset, privacy: .public)")
      throw Self.damaged
    }
    let zipapp = try await fetch(release.zipapp, as: Self.asset, into: downloads)
    // Hashing and unpacking a few MB, off the actor's cooperative thread.
    guard try await Task.detached(priority: .utility, operation: { try Self.sha256(of: zipapp) }).value == expected else {
      Log.ytdlp.error("yt-dlp \(release.version, privacy: .public) does not match its checksum")
      throw Self.damaged
    }

    let dir = root.appendingPathComponent(release.version, isDirectory: true)
    do {
      let version = release.version
      try await Task.detached(priority: .utility) {
        try ZipExtractor.extract(zipapp, to: dir)
        let source = try? String(contentsOf: dir.appendingPathComponent("yt_dlp/version.py"), encoding: .utf8)
        guard let source, YtDlpVersion.declared(in: source) == version else {
          throw ZipExtractor.Refused(description: "yt_dlp/version.py is not \(version)")
        }
        if let problem = YtDlpUpdater.layoutProblem(in: dir) { throw ZipExtractor.Refused(description: problem) }
      }.value
      try await compileBytecode(dir)
      // The deadline passed while it unpacked: the update has failed, so it must not become a version.
      try Task.checkCancellation()
    } catch {
      try? fm.removeItem(at: dir)
      Log.ytdlp.error("yt-dlp \(release.version, privacy: .public) refused: \(String(describing: error), privacy: .public)")
      throw error is ZipExtractor.Refused ? Self.damaged : error
    }
    guard fm.createFile(atPath: dir.appendingPathComponent(Self.completeMarker).path, contents: Data()) else {
      try? fm.removeItem(at: dir)
      throw CocoaError(.fileWriteUnknown)
    }
    prune(keeping: running)
    Log.ytdlp.notice("yt-dlp \(release.version, privacy: .public) installed")
    return release.version
  }

  // Saves each launch compiling the whole package from source (about 175 ms of boot on the simulator). A failure
  // costs only that: the sources still import.
  private func compileBytecode(_ dir: URL) async throws {
    guard let compile else { return }
    let began = Date()
    let version = dir.lastPathComponent
    do {
      try await compile(dir)
      let elapsed = Int(Date().timeIntervalSince(began) * 1000)
      Log.ytdlp.notice("yt-dlp \(version, privacy: .public) compiled in \(elapsed) ms")
    } catch {
      Log.ytdlp.error("yt-dlp \(version, privacy: .public) not compiled: \(String(describing: error), privacy: .public)")
    }
  }

  // What a kill can leave: a download, a `.partial` extraction, a version dir without its marker.
  private func clearLeftovers() {
    let fm = FileManager.default
    for name in (try? fm.contentsOfDirectory(atPath: root.path)) ?? [] {
      let entry = root.appendingPathComponent(name)
      let unfinished = YtDlpVersion.isValid(name)
        && !fm.fileExists(atPath: entry.appendingPathComponent(Self.completeMarker).path)
      if name == ".download" || name.hasSuffix(".partial") || unfinished {
        try? fm.removeItem(at: entry)
      }
    }
  }

  // The newest two that never failed a launch stay, and so does the one running now: its modules are still imported
  // lazily.
  private func prune(keeping running: String?) {
    let bad = Set(launchRecord().bad)
    let kept = installed().filter { !bad.contains($0) }.prefix(Self.keep)
    for version in installed() where version != running && !kept.contains(version) {
      try? FileManager.default.removeItem(at: root.appendingPathComponent(version, isDirectory: true))
    }
  }

  private struct Release {
    let version: String
    let zipapp: URL
    let sums: URL
  }

  private func latest() async throws -> Release {
    var request = URLRequest(url: Self.latestRelease)
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    let (data, response) = try await network { try await self.session.data(for: request) }
    try Self.requireTrusted(response)
    try Self.requireOk(response)
    guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
      let tag = json["tag_name"] as? String, YtDlpVersion.isValid(tag),
      let assets = json["assets"] as? [[String: Any]]
    else {
      Log.ytdlp.error("The latest yt-dlp release could not be read")
      throw Self.damaged
    }
    func url(_ name: String) -> URL? {
      let link = assets.first { $0["name"] as? String == name }?["browser_download_url"] as? String
      return link.flatMap(URL.init(string:)).flatMap { $0.scheme == "https" && $0.host == Self.assetHost ? $0 : nil }
    }
    guard let zipapp = url(Self.asset), let sums = url(Self.sumsAsset) else {
      Log.ytdlp.error("yt-dlp \(tag, privacy: .public) has no GitHub link for \(Self.asset, privacy: .public) or its sums")
      throw Self.untrusted
    }
    return Release(version: tag, zipapp: zipapp, sums: sums)
  }

  // Saved under a fixed name: the link's last component is GitHub's to choose, and could be "..".
  private func fetch(_ url: URL, as name: String, into dir: URL) async throws -> URL {
    let (file, response) = try await network { try await self.session.download(for: URLRequest(url: url)) }
    let target = dir.appendingPathComponent(name, isDirectory: false)
    defer { try? FileManager.default.removeItem(at: file) }
    try Self.requireTrusted(response)
    try Self.requireOk(response)
    try? FileManager.default.removeItem(at: target)
    try FileManager.default.moveItem(at: file, to: target)
    return target
  }

  private func network<T>(_ body: () async throws -> T) async throws -> T {
    do {
      return try await body()
    } catch let error as URLError {
      Log.ytdlp.error("yt-dlp update request failed: \(error.code.rawValue)")
      throw Self.offline
    }
  }

  // Where the answer came from after any redirects.
  private static func requireTrusted(_ response: URLResponse) throws {
    guard let url = response.url, url.scheme == "https", let host = url.host, trustedHosts.contains(host) else {
      Log.ytdlp.error("yt-dlp update answered from \(response.url?.host ?? "nowhere", privacy: .public)")
      throw untrusted
    }
  }

  private static func requireOk(_ response: URLResponse) throws {
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard status == 200 else {
      Log.ytdlp.error("yt-dlp update got HTTP \(status)")
      throw unreachable
    }
  }

  // A `sha256sum` line: "<hex>  <name>", or "<hex> *<name>" in binary mode.
  static func sum(of name: String, in sums: String) -> String? {
    for line in sums.split(whereSeparator: \.isNewline) {
      let parts = line.split(separator: " ", maxSplits: 1)
      guard parts.count == 2 else { continue }
      var file = parts[1].trimmingCharacters(in: .whitespaces)
      if file.hasPrefix("*") { file.removeFirst() }
      let hex = parts[0].lowercased()
      if file == name, hex.count == 64, hex.allSatisfy(\.isHexDigit) { return hex }
    }
    return nil
  }

  static func sha256(of file: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: file)
    defer { try? handle.close() }
    var hash = SHA256()
    while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
      hash.update(data: chunk)
    }
    return hash.finalize().hex
  }
}

// yt-dlp's versions are dates, with a counter for a second release the same day: 2026.10.26, 2026.10.26.1.
enum YtDlpVersion {
  static func isValid(_ text: String) -> Bool {
    let parts = text.split(separator: ".", omittingEmptySubsequences: false)
    return (3...4).contains(parts.count) && parts[0].count == 4
      && parts.allSatisfy { !$0.isEmpty && $0.count <= 8 && $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }
  }

  static func newer(_ a: String, than b: String) -> Bool {
    let x = a.split(separator: ".").map { Int($0) ?? 0 }
    let y = b.split(separator: ".").map { Int($0) ?? 0 }
    for i in 0..<max(x.count, y.count) {
      let l = i < x.count ? x[i] : 0
      let r = i < y.count ? y[i] : 0
      if l != r { return l > r }
    }
    return false
  }

  // `__version__ = '2026.10.26'` in yt_dlp/version.py.
  static func declared(in source: String) -> String? {
    for line in source.split(whereSeparator: \.isNewline) where line.hasPrefix("__version__") {
      let value = line.split(separator: "=", maxSplits: 1).last?.trimmingCharacters(in: .whitespaces) ?? ""
      return value.trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
    }
    return nil
  }
}
