import UIKit

final class HostApi: FetchrHostApi {
  private let python: PythonCalling
  private let downloads: DownloadRepository?
  private let cacheDir: URL
  private let defaults: UserDefaults
  private let library: Library
  private let pickedDir: URL
  private let gate: RunGate
  private let updater: YtDlpUpdater?
  private let startup: YtDlpStartup?
  private let startupWait: TimeInterval
  private let opener: @MainActor (URL) async -> Bool

  init(
    python: PythonCalling, downloads: DownloadRepository? = nil, cacheDir: URL = Paths.cachesDir,
    defaults: UserDefaults = .standard,
    library: Library = Library(documents: Paths.documentsDir, caches: Paths.cachesDir),
    pickedDir: URL = Paths.pickedDir, gate: RunGate = RunGate(), updater: YtDlpUpdater? = nil,
    startup: YtDlpStartup? = nil, startupWait: TimeInterval = 5,
    opener: @escaping @MainActor (URL) async -> Bool = { await UIApplication.shared.open($0) }
  ) {
    self.python = python
    self.downloads = downloads
    self.cacheDir = cacheDir
    self.defaults = defaults
    self.library = library
    self.pickedDir = pickedDir
    self.gate = gate
    self.updater = updater
    self.startup = startup
    self.startupWait = startupWait
    self.opener = opener
  }

  // AppDelegate always passes the repository and the updater; only a test builds a host without them.
  private static let misconfigured = FetchrError(
    code: "unknown", message: "Fetchr was set up without its download engine.", details: nil)

  func awaitLaunchSplash() async throws {}

  func setAccentColor(argb: Int64) throws {
    defaults.set(Int(argb), forKey: "fetchr.accentColor")
  }

  // Android detaches tracked libmpv players before its Activity's engine goes (MpvGuard.kt); iOS has no such
  // teardown, so there is nothing to track.
  func trackPlayer(handle: Int64) throws {}

  func untrackPlayer(handle: Int64) throws {}

  // Dart asks only on Android (AppInitializer); 0 is "not Android".
  func androidSdkInt() throws -> Int64 { 0 }

  func setYtDlpAutoUpdate(enabled: Bool) throws {
    defaults.set(enabled, forKey: YtDlpUpdater.autoUpdateKey)
  }

  func fetchInfo(url: String) async throws -> VideoInfo {
    try await mapErrors {
      let safe = try RequestBuilder.requireHttpUrl(url)
      let value = try await python.call(
        "info", ["argv": RequestBuilder.infoArgv(cacheDir: cacheDir), "url": safe], gate: gate)
      guard let info = value as? [String: Any] else {
        throw BridgeError(hint: nil, message: "The info call returned something that is not a JSON object.")
      }
      return InfoParser.parse(JSONObject(info), url: safe)
    }
  }

  // The trust boundary for download URLs: one bad link fails the whole batch before any task is added, as on
  // Android.
  func enqueue(requests: [DownloadRequest]) throws {
    guard let downloads else { throw Self.misconfigured }
    let checked = try requests.map { req -> DownloadRequest in
      var safe = req
      safe.url = try RequestBuilder.requireHttpUrl(req.url)
      return safe
    }
    downloads.submit(checked)
  }

  func cancel(id: String) throws { try send(.cancel(id)) }

  func retry(id: String) throws { try send(.retry(id)) }

  func reorder(ids: [String]) throws { try send(.reorder(ids)) }

  func pause(id: String) throws { try send(.pause(id)) }

  func resume(id: String) throws { try send(.resume(id)) }

  func pauseAll() throws { try send(.pauseAll) }

  func resumeAll() throws { try send(.resumeAll) }

  func remove(id: String) async throws -> Bool {
    guard let downloads else { throw Self.misconfigured }
    return try await mapErrors { try await downloads.remove(id) }
  }

  // Through the repository's ordered inbox: a pause then a resume tapped quickly arrive in that order.
  private func send(_ command: DownloadRepository.Command) throws {
    guard let downloads else { throw Self.misconfigured }
    downloads.send(command)
  }

  func listLibrary(folder: String) async throws -> [LibraryItem] {
    await library.list(folder: folder)
  }

  // No consent dialog on iOS, so this is true once the file is gone.
  func deleteFromLibrary(uri: String) async throws -> Bool {
    try await mapErrors {
      let library = library
      if let downloads {
        try await downloads.deleteFromLibrary { try library.delete(uri: uri) }
      } else {
        try library.delete(uri: uri)
      }
      return true
    }
  }

  // The uri is checked here, then the sheet is presented on the next main-actor turn, so this returns at once.
  func share(uri: String, mimeType: String) throws {
    let file = try Paths.documentFile(fromUri: uri, documents: library.documents)
    present { FileActions.share(file, from: $0) }
  }

  func openFile(uri: String, mimeType: String) throws {
    let file = try Paths.documentFile(fromUri: uri, documents: library.documents)
    present { FileActions.preview(file, from: $0) }
  }

  private func present(_ action: @escaping @MainActor (UIViewController) -> Void) {
    Task { @MainActor in
      guard let presenter = FileActions.presenter() else { return }
      action(presenter)
    }
  }

  // Also called by Downloads with a completed task's savedUri.
  func openFolder(uri: String) async throws {
    let file = try Paths.documentFile(fromUri: uri, documents: library.documents)
    try await FileActions.openFolder(of: file, opener: opener)
  }

  func freeSpaceBytes() async throws -> Int64 {
    try await mapErrors { try library.freeSpaceBytes() }
  }

  // Nil when the user backs out, as on Android.
  func pickVideo() async throws -> String? {
    try await mapErrors {
      guard let presenter = await FileActions.presenter() else { return nil }
      return try await VideoPicker.pick(from: presenter, into: pickedDir)?.absoluteString
    }
  }

  // The trust boundary for convert sources: a picked copy or a library file, checked before any task is added.
  func convertToMp3(uri: String, folder: String) async throws {
    guard let downloads else { throw Self.misconfigured }
    try await mapErrors {
      let file = try LocalVideo.convertible(uri, documents: library.documents, picked: pickedDir)
      downloads.submit([await LocalVideo.request(for: file, folder: folder)])
    }
  }

  func thumbnail(uri: String, widthPx: Int64, heightPx: Int64) async throws -> String? {
    try await mapErrors {
      try await library.thumbnail(uri: uri, widthPx: Int(clamping: widthPx), heightPx: Int(clamping: heightPx))
    }
  }

  // `version` is the yt-dlp running now; `updateYtDlp`'s is the one installed for the next launch.
  func ytDlpStatus() async throws -> YtDlpStatus {
    try await mapErrors {
      let version = try await runningYtDlp()
      // As on Android: a startup update in progress may be about to stamp its check.
      await startup?.wait(timeout: startupWait)
      return status(version: version)
    }
  }

  func updateYtDlp() async throws -> YtDlpStatus {
    guard let updater else { throw Self.misconfigured }
    return try await mapErrors {
      // The version installed for the next launch, or the running one when nothing newer came.
      let installed = try await updater.update(running: try await runningYtDlp())
      return status(version: installed)
    }
  }

  private func runningYtDlp() async throws -> String? {
    (try await python.call("ping", [:]) as? [String: Any])?["ytDlpVersion"] as? String
  }

  private func status(version: String?) -> YtDlpStatus {
    YtDlpStatus(
      version: version, checkedAtMs: YtDlpUpdater.checkedAtMs(in: defaults),
      autoUpdate: YtDlpUpdater.autoUpdate(in: defaults))
  }
}
