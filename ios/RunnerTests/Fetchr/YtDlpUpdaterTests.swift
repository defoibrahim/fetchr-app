import XCTest
@testable import Runner

// Review Focus 1 and 4: an update is verified before it is installed, a damaged one installs nothing, and an update
// never overlaps a yt-dlp run.
final class YtDlpUpdaterTests: XCTestCase {
  private var tmp: URL!
  private var root: URL { tmp.appendingPathComponent("yt-dlp", isDirectory: true) }
  private var documents: URL { tmp.appendingPathComponent("Documents") }
  private var caches: URL { tmp.appendingPathComponent("Caches") }
  private let suite = "fetchr.tests.\(UUID().uuidString)"
  private lazy var defaults = UserDefaults(suiteName: suite)!
  private let gate = RunGate()

  override func setUpWithError() throws {
    tmp = FileManager.default.temporaryDirectory.appendingPathComponent("updater-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    StubProtocol.serve { _ in (404, Data()) }
    UserDefaults().removePersistentDomain(forName: suite)
    try? FileManager.default.removeItem(at: tmp)
  }

  private func updater(session: URLSession = StubProtocol.session(), deadline: TimeInterval = 120) -> YtDlpUpdater {
    YtDlpUpdater(root: root, session: session, gate: gate, defaults: defaults, deadline: deadline)
  }

  private func exists(_ path: String) -> Bool {
    FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path)
  }

  private func rootEntries() -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []).sorted()
  }

  private func code(of body: () async throws -> Any) async -> String? {
    do {
      _ = try await body()
      return nil
    } catch {
      return (error as? FetchrError)?.code ?? "\(error)"
    }
  }

  func testUpdateInstallsAndKeepsTwoVersions() async throws {
    let updater = updater()
    for tag in ["2026.11.01", "2026.11.08", "2026.11.12"] {
      StubProtocol.serve(FakeRelease(tag).handler())
      let installed = try await updater.update(running: "2026.10.26")
      XCTAssertEqual(installed, tag)
    }
    XCTAssertEqual(updater.installed(), ["2026.11.12", "2026.11.08"])
    XCTAssertFalse(exists("2026.11.01"), "the oldest is deleted")
    XCTAssertTrue(exists("2026.11.12/yt_dlp/version.py"))
    XCTAssertTrue(exists("2026.11.12/yt_dlp_ejs/yt/solver/core.min.js"))
    XCTAssertTrue(exists("2026.11.12/.complete"))
    XCTAssertEqual(rootEntries(), ["2026.11.08", "2026.11.12"], "no download or partial left behind")
    let script = root.appendingPathComponent("2026.11.12/yt_dlp_ejs/yt/solver/core.min.js")
    let text = try String(contentsOf: script, encoding: .utf8)
    XCTAssertEqual(text, String(repeating: "var a=1;", count: 200))
    let backup = try root.resourceValues(forKeys: [.isExcludedFromBackupKey])
    XCTAssertEqual(backup.isExcludedFromBackup, true)
  }

  func testPruneNeverDeletesTheRunningVersion() async throws {
    let updater = updater()
    StubProtocol.serve(FakeRelease("2026.11.01").handler())
    _ = try await updater.update(running: "2026.10.26")
    // After a restart onto 2026.11.01.
    for tag in ["2026.11.08", "2026.11.12"] {
      StubProtocol.serve(FakeRelease(tag).handler())
      _ = try await updater.update(running: "2026.11.01")
    }
    XCTAssertEqual(updater.installed(), ["2026.11.12", "2026.11.08", "2026.11.01"])
  }

  func testUpToDateInstallsNothingButCountsAsAChecked() async throws {
    let updater = updater()
    StubProtocol.serve(FakeRelease("2026.10.26").handler())
    let version = try await updater.update(running: "2026.10.26")
    XCTAssertEqual(version, "2026.10.26")
    XCTAssertEqual(updater.installed(), [])
    XCTAssertFalse(StubProtocol.requests.contains { $0.lastPathComponent == "yt-dlp" }, "the zipapp is not fetched")
    XCTAssertNotNil(updater.checkedAtMs)
  }

  func testAnInstalledLatestIsNotFetchedAgain() async throws {
    let updater = updater()
    StubProtocol.serve(FakeRelease("2026.11.12").handler())
    _ = try await updater.update(running: "2026.10.26")
    StubProtocol.serve(FakeRelease("2026.11.12").handler())
    _ = try await updater.update(running: "2026.10.26")
    XCTAssertFalse(StubProtocol.requests.contains { $0.lastPathComponent == "yt-dlp" })
    XCTAssertEqual(updater.installed(), ["2026.11.12"])
  }

  func testChecksumMismatchInstallsNothing() async throws {
    let updater = updater()
    let wrong = FakeRelease("2026.11.12", sums: "\(String(repeating: "0", count: 64))  yt-dlp\n")
    StubProtocol.serve(wrong.handler())
    let mismatch = await code { try await updater.update(running: "2026.10.26") }
    XCTAssertEqual(mismatch, "unknown")

    // Truncated in transit: the sums are for the whole file.
    let whole = ZipBuilder.zipapp(version: "2026.11.12").build()
    let truncated = FakeRelease(
      "2026.11.12", zipapp: whole.prefix(whole.count / 2), sums: "\(whole.sha256Hex)  yt-dlp\n")
    StubProtocol.serve(truncated.handler())
    let cut = await code { try await updater.update(running: "2026.10.26") }
    XCTAssertEqual(cut, "unknown")

    let missing = FakeRelease("2026.11.12", sums: "\(whole.sha256Hex)  yt-dlp.exe\n")
    StubProtocol.serve(missing.handler())
    let unlisted = await code { try await updater.update(running: "2026.10.26") }
    XCTAssertEqual(unlisted, "unknown")

    XCTAssertEqual(updater.installed(), [])
    XCTAssertEqual(rootEntries(), [])
    XCTAssertNil(updater.checkedAtMs)
  }

  func testZipSlipEntryIsRefused() async throws {
    let out = tmp.appendingPathComponent("out/2026.11.12", isDirectory: true)
    let evil: [(String, UInt32)] = [
      ("../escaped.py", 0o100644), ("/absolute.py", 0o100644), ("yt_dlp/../../escaped.py", 0o100644),
      ("yt_dlp\\..\\escaped.py", 0o100644), ("yt_dlp/link", 0o120777), ("yt_dlp//x.py", 0o100644),
    ]
    for (name, mode) in evil {
      var zip = ZipBuilder.zipapp(version: "2026.11.12")
      zip.add(name, "../../../../etc", mode: mode)
      let file = tmp.appendingPathComponent("evil.zip")
      try zip.build().write(to: file)
      XCTAssertThrowsError(try ZipExtractor.extract(file, to: out), name)
      XCTAssertFalse(FileManager.default.fileExists(atPath: out.path), name)
      XCTAssertFalse(FileManager.default.fileExists(atPath: out.path + ".partial"), name)
      XCTAssertFalse(FileManager.default.fileExists(atPath: tmp.appendingPathComponent("escaped.py").path), name)
      XCTAssertFalse(FileManager.default.fileExists(atPath: tmp.appendingPathComponent("out/escaped.py").path), name)
    }

    // Through the updater, with sums that match: the archive itself is refused.
    var zip = ZipBuilder.zipapp(version: "2026.11.12")
    zip.add("../escaped.py", "x")
    let updater = updater()
    StubProtocol.serve(FakeRelease("2026.11.12", zipapp: zip.build()).handler())
    let refused = await code { try await updater.update(running: "2026.10.26") }
    XCTAssertEqual(refused, "unknown")
    XCTAssertEqual(updater.installed(), [])
    XCTAssertEqual(rootEntries(), [])
    XCTAssertFalse(FileManager.default.fileExists(atPath: tmp.appendingPathComponent("escaped.py").path))
  }

  func testExtractsAPlainZipAndAZipapp() throws {
    for prefix in [Data(), Data("#!/usr/bin/env python3\n".utf8)] {
      var zip = ZipBuilder.zipapp(version: "2026.11.12")
      zip.prefix = prefix
      let file = tmp.appendingPathComponent("app.zip")
      try zip.build().write(to: file)
      let out = tmp.appendingPathComponent("out-\(prefix.count)", isDirectory: true)
      try ZipExtractor.extract(file, to: out)
      let version = try String(contentsOf: out.appendingPathComponent("yt_dlp/version.py"), encoding: .utf8)
      XCTAssertTrue(version.contains("__version__ = '2026.11.12'"))
      let empty = try Data(contentsOf: out.appendingPathComponent("yt_dlp/extractor/__init__.py"))
      XCTAssertTrue(empty.isEmpty)
      XCTAssertFalse(FileManager.default.fileExists(atPath: out.path + ".partial"))
    }
  }

  private func refuses(_ zip: ZipBuilder, limits: ZipExtractor.Limits = .standard, _ why: String) throws {
    let file = tmp.appendingPathComponent("zip-\(UUID().uuidString).zip")
    try zip.build().write(to: file)
    let out = tmp.appendingPathComponent("out-\(UUID().uuidString)", isDirectory: true)
    XCTAssertThrowsError(try ZipExtractor.extract(file, to: out, limits: limits), why)
    XCTAssertFalse(FileManager.default.fileExists(atPath: out.path), why)
    XCTAssertFalse(FileManager.default.fileExists(atPath: out.path + ".partial"), why)
  }

  func testZipOverItsBoundsOrWithClashingNamesIsRefused() throws {
    let app = ZipBuilder.zipapp(version: "2026.11.12")
    let total = app.entries.reduce(0) { $0 + $1.data.count }
    try refuses(app, limits: .init(maxEntries: app.entries.count - 1, maxTotalBytes: .max), "too many entries")
    try refuses(app, limits: .init(maxEntries: .max, maxTotalBytes: total - 1), "too many bytes")

    var twice = app
    twice.add("yt_dlp/version.py", "__version__ = '2020.01.01'\n")
    try refuses(twice, "a duplicate name")

    var fileThenChild = app
    fileThenChild.add("yt_dlp/version.py/x.py", "")
    try refuses(fileThenChild, "a file under a path another entry writes as a file")

    // At the bounds exactly, it extracts.
    let file = tmp.appendingPathComponent("fits.zip")
    try app.build().write(to: file)
    try ZipExtractor.extract(
      file, to: tmp.appendingPathComponent("fits"), limits: .init(maxEntries: app.entries.count, maxTotalBytes: total))
  }

  func testCorruptEntryIsRefused() throws {
    var data = ZipBuilder.zipapp(version: "2026.11.12").build()
    // A byte inside the first entry's compressed data: its CRC no longer matches.
    let at = data.count / 4
    data[at] ^= 0xFF
    let file = tmp.appendingPathComponent("bad.zip")
    try data.write(to: file)
    let out = tmp.appendingPathComponent("out", isDirectory: true)
    XCTAssertThrowsError(try ZipExtractor.extract(file, to: out))
    XCTAssertFalse(FileManager.default.fileExists(atPath: out.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: out.path + ".partial"))
  }

  func testVersionThatIsNotTheTagIsRefused() async throws {
    let updater = updater()
    let liar = FakeRelease("2026.11.12", zipapp: ZipBuilder.zipapp(version: "2026.11.12", declaring: "2020.01.01").build())
    StubProtocol.serve(liar.handler())
    let refused = await code { try await updater.update(running: "2026.10.26") }
    XCTAssertEqual(refused, "unknown")
    XCTAssertEqual(rootEntries(), [])
  }

  func testTagThatIsNotAVersionIsRefusedBeforeAnyDownload() async throws {
    let updater = updater()
    for tag in ["../2026.11.12", "nightly", "2026.11.12/..", ""] {
      StubProtocol.serve(FakeRelease(tag).handler())
      let refused = await code { try await updater.update(running: "2026.10.26") }
      XCTAssertEqual(refused, "unknown", tag)
      XCTAssertEqual(StubProtocol.requests, [FakeRelease.api], tag)
    }
    XCTAssertEqual(rootEntries(), [])
    XCTAssertFalse(FileManager.default.fileExists(atPath: tmp.appendingPathComponent("2026.11.12").path))
  }

  func testInterruptedExtractionIsNeverSelected() async throws {
    let fm = FileManager.default
    for dir in ["2026.11.12.partial/yt_dlp", "2026.11.10/yt_dlp", "2026.11.08/yt_dlp", "not-a-version", ".download"] {
      try fm.createDirectory(at: root.appendingPathComponent(dir), withIntermediateDirectories: true)
    }
    for dir in ["2026.11.12.partial", "2026.11.08", "not-a-version"] {
      try Data().write(to: root.appendingPathComponent("\(dir)/.complete"))
    }
    let updater = updater()
    XCTAssertEqual(updater.installed(), ["2026.11.08"], "a .partial or a dir without .complete is never chosen")

    // The next update clears what a kill left behind.
    StubProtocol.serve(FakeRelease("2026.11.13").handler())
    _ = try await updater.update(running: "2026.10.26")
    XCTAssertEqual(updater.installed(), ["2026.11.13", "2026.11.08"])
    XCTAssertEqual(rootEntries(), ["2026.11.08", "2026.11.13", "not-a-version"])
  }

  func testUpdateIsBusyWhileARunIsActive() async throws {
    // An info call in Python.
    let python = FakePython()
    let info = Gate()
    python.hold = { name in if name == "info" { await info.wait() } }
    python.reply = { name in
      if name == "ping" { return ["ytDlpVersion": "2026.10.26"] }
      return try JSONSerialization.jsonObject(with: Data(infoFixture("video").utf8))
    }
    let updater = updater()
    let api = HostApi(python: python, cacheDir: caches, defaults: defaults, gate: gate, updater: updater)
    StubProtocol.serve(FakeRelease("2026.11.12").handler())
    let fetch = Task { try await api.fetchInfo(url: "https://example.com/v") }
    try await waitUntil { python.calls.contains { $0.name == "info" } }
    let duringInfo = await code { try await api.updateYtDlp() }
    XCTAssertEqual(duringInfo, "busy")
    XCTAssertEqual(StubProtocol.requests, [], "nothing fetched")
    XCTAssertEqual(rootEntries(), [])
    XCTAssertNil(updater.checkedAtMs)
    info.release()
    _ = try await fetch.value

    // A download in Python, then the same download abandoned while its call is still unwinding.
    let downloads = FakeDownloads()
    let hold = Gate()
    downloads.script = { run, _ in
      await hold.wait()
      try FakeDownloads.write("clip.mp4", in: run)
    }
    let repository = DownloadRepository(python: downloads, documents: documents, cachesDir: caches, gate: gate)
    downloads.repository = repository
    let id = try firstOf(await repository.enqueue([downloadRequest()]))
    try await waitUntil { downloads.runs.count == 1 }
    let duringDownload = await code { try await updater.update(running: "2026.10.26") }
    XCTAssertEqual(duringDownload, "busy")
    await repository.pause(id)
    _ = try await waitFor(repository) { $0.first?.status == .paused }
    let whileUnwinding = await code { try await updater.update(running: "2026.10.26") }
    XCTAssertEqual(whileUnwinding, "busy", "an abandoned attempt still in Python is still a run")
    XCTAssertEqual(rootEntries(), [])

    hold.release()
    await repository.waitUntilIdle()
    let status = try await api.updateYtDlp()
    XCTAssertEqual(status.version, "2026.11.12", "the version installed for the next launch")
    XCTAssertNotNil(status.checkedAtMs)
    XCTAssertEqual(updater.installed(), ["2026.11.12"])
  }

  func testRunWaitsWhileASwapInstalls() async throws {
    let serve = Gate()
    let asked = Flag()
    StubProtocol.serve(FakeRelease("2026.11.12").handler(hold: {
      asked.set()
      await serve.wait()
    }))
    let updater = updater()
    let update = Task { try await updater.update(running: "2026.10.26") }
    try await waitUntil { asked.value }

    let downloads = FakeDownloads()
    downloads.script = { run, _ in try FakeDownloads.write("clip.mp4", in: run) }
    let repository = DownloadRepository(python: downloads, documents: documents, cachesDir: caches, gate: gate)
    downloads.repository = repository
    await repository.enqueue([downloadRequest()])
    let python = FakePython()
    python.reply = { _ in try JSONSerialization.jsonObject(with: Data(infoFixture("video").utf8)) }
    let api = HostApi(python: python, cacheDir: caches, defaults: defaults, gate: gate, updater: updater)
    let fetch = Task { try await api.fetchInfo(url: "https://example.com/v") }

    try await Task.sleep(nanoseconds: 300_000_000)
    XCTAssertEqual(downloads.runs.count, 0, "the download waits for the install")
    XCTAssertTrue(python.calls.isEmpty, "so does an info call")

    serve.release()
    _ = try await update.value
    _ = try await fetch.value
    let done = try await waitFor(repository) { $0.first?.status == .completed }
    XCTAssertEqual(done.count, 1)
    XCTAssertEqual(downloads.runs.count, 1)
    XCTAssertEqual(updater.installed(), ["2026.11.12"])
  }

  func testCheckedAtIsWrittenOnlyOnSuccess() async throws {
    let updater = updater()
    StubProtocol.serve { _ in (500, Data()) }
    let failed = await code { try await updater.update(running: "2026.10.26") }
    XCTAssertEqual(failed, "network")
    XCTAssertNil(updater.checkedAtMs)

    StubProtocol.serve { _ in throw URLError(.notConnectedToInternet) }
    let offline = await code { try await updater.update(running: "2026.10.26") }
    XCTAssertEqual(offline, "network")
    XCTAssertNil(updater.checkedAtMs)

    let before = Int64(Date().timeIntervalSince1970 * 1000)
    StubProtocol.serve(FakeRelease("2026.11.12").handler())
    _ = try await updater.update(running: "2026.10.26")
    let checked = try XCTUnwrap(updater.checkedAtMs)
    XCTAssertGreaterThanOrEqual(checked, before)

    StubProtocol.serve { _ in (500, Data()) }
    _ = await code { try await updater.update(running: "2026.10.26") }
    XCTAssertEqual(updater.checkedAtMs, checked)
  }

  func testStatusReportsTheRunningVersionCheckedAtAndAutoUpdate() async throws {
    let python = FakePython()
    python.reply = { _ in ["ytDlpVersion": "2026.10.26"] }
    let updater = updater()
    let api = HostApi(python: python, cacheDir: caches, defaults: defaults, gate: gate, updater: updater)
    var status = try await api.ytDlpStatus()
    XCTAssertEqual(status.version, "2026.10.26")
    XCTAssertNil(status.checkedAtMs)
    XCTAssertTrue(status.autoUpdate)

    try api.setYtDlpAutoUpdate(enabled: false)
    StubProtocol.serve(FakeRelease("2026.11.12").handler())
    let updated = try await api.updateYtDlp()
    XCTAssertEqual(updated.version, "2026.11.12", "the version installed for the next launch")
    XCTAssertFalse(updated.autoUpdate)
    status = try await api.ytDlpStatus()
    XCTAssertEqual(status.version, "2026.10.26", "the running one until a restart")
    XCTAssertEqual(status.checkedAtMs, updated.checkedAtMs)
    XCTAssertNotNil(status.checkedAtMs)
    XCTAssertFalse(status.autoUpdate)

    StubProtocol.serve(FakeRelease("2026.10.26").handler())
    let upToDate = try await api.updateYtDlp()
    XCTAssertEqual(upToDate.version, "2026.10.26", "nothing newer: the running one")
  }

  func testAssetOffGitHubIsRefusedBeforeAnyDownload() async throws {
    let updater = updater()
    for (asset, sums) in [
      ("https://evil.example.test/yt-dlp", nil), (nil, "https://objects.githubusercontent.com/SHA2-256SUMS"),
      ("http://github.com/yt-dlp/yt-dlp/releases/download/2026.11.12/yt-dlp", nil),
    ] as [(String?, String?)] {
      var release = FakeRelease("2026.11.12")
      if let asset { release.assetUrl = asset }
      if let sums { release.sumsUrl = sums }
      StubProtocol.serve(release.handler())
      let refused = await code { try await updater.update(running: "2026.10.26") }
      XCTAssertEqual(refused, "unknown", "\(asset ?? sums ?? "")")
      XCTAssertEqual(StubProtocol.requests, [FakeRelease.api])
    }
    XCTAssertEqual(rootEntries(), [])
  }

  func testRedirectToAnotherHostIsRefused() async throws {
    let updater = updater()
    for name in ["yt-dlp", "SHA2-256SUMS"] {
      let release = FakeRelease("2026.11.12")
      let from = name == "yt-dlp" ? release.assetUrl : release.sumsUrl
      StubProtocol.serve(
        redirects: [from: URL(string: "https://evil.example.test/\(name)")!], release.handler())
      let refused = await code { try await updater.update(running: "2026.10.26") }
      XCTAssertEqual(refused, "unknown", name)
      XCTAssertTrue(StubProtocol.requests.contains { $0.host == "evil.example.test" }, "the redirect was followed")
      XCTAssertEqual(updater.installed(), [], name)
      XCTAssertEqual(rootEntries(), [], name)
      XCTAssertNil(updater.checkedAtMs)
    }
  }

  func testRedirectToGitHubsCdnIsFollowed() async throws {
    let updater = updater()
    let release = FakeRelease("2026.11.12")
    StubProtocol.serve(
      redirects: [
        release.assetUrl: URL(string: "https://release-assets.githubusercontent.com/github-production-release-asset/1/yt-dlp")!,
        release.sumsUrl: URL(string: "https://objects.githubusercontent.com/github-production-release-asset/1/SHA2-256SUMS")!,
      ], release.handler())
    _ = try await updater.update(running: "2026.10.26")
    XCTAssertEqual(updater.installed(), ["2026.11.12"])
  }

  func testAssetUrlEndingInDotDotCannotTouchTheRoot() async throws {
    let updater = updater()
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data("{}".utf8).write(to: root.appendingPathComponent("launch.json"))
    var release = FakeRelease("2026.11.12")
    release.assetUrl = "https://github.com/yt-dlp/yt-dlp/releases/download/2026.11.12/yt-dlp/.."
    StubProtocol.serve(release.handler())
    _ = try? await updater.update(running: "2026.10.26")
    XCTAssertTrue(exists("launch.json"), "the root and what is in it stay")
    XCTAssertEqual(updater.installed(), ["2026.11.12"], "saved under its fixed name, then installed")
  }

  func testUpdateGivesUpAtItsDeadline() async throws {
    let stall = Gate()
    defer { stall.release() }
    let updater = updater(deadline: 0.5)
    StubProtocol.serve(FakeRelease("2026.11.12").handler(hold: { await stall.wait() }))
    let began = Date()
    let expired = await code { try await updater.update(running: "2026.10.26") }
    XCTAssertEqual(expired, "network")
    XCTAssertLessThan(Date().timeIntervalSince(began), 5)
    XCTAssertEqual(updater.installed(), [])
    XCTAssertEqual(rootEntries(), [], "the download is cleared")
    XCTAssertNil(updater.checkedAtMs)
    try await gate.beginSwap()
    await gate.endSwap()
  }

  // Each request is under the deadline; together they are over it.
  func testDeadlineCoversTheWholeUpdate() async throws {
    let updater = updater(deadline: 0.6)
    StubProtocol.serve(FakeRelease("2026.11.12").handler(delay: 0.25))
    let expired = await code { try await updater.update(running: "2026.10.26") }
    XCTAssertEqual(expired, "network")
    XCTAssertEqual(rootEntries(), [])
    try await gate.beginSwap()
    await gate.endSwap()
  }

  // Downloads and verifies the real latest release into a temp root; nothing is activated.
  func testRealLatestReleaseVerifies() async throws {
    try XCTSkipUnless(ProcessInfo.processInfo.environment["FETCHR_NETWORK_TESTS"] == "1", "network tests are opt-in")
    // The app's own compile step, through the real bridge.
    let compiled = Flag()
    let updater = YtDlpUpdater(
      root: root, session: .shared, gate: gate, defaults: defaults,
      compile: { dir in
        let began = Date()
        let reply = try await PythonRuntime.shared.call("compile", ["dir": dir.path]) as? [String: Any]
        print("yt-dlp compiled in \(Int(Date().timeIntervalSince(began) * 1000)) ms: \(reply ?? [:])")
        if reply?["compiled"] as? Bool == true { compiled.set() }
      })
    let began = Date()
    let version = try await updater.update(running: nil)
    print("yt-dlp \(version) installed in \(Int(Date().timeIntervalSince(began) * 1000)) ms")
    XCTAssertEqual(updater.installed(), [version])
    XCTAssertTrue(exists("\(version)/yt_dlp/__init__.py"))
    XCTAssertTrue(exists("\(version)/yt_dlp_ejs/__init__.py"), "the zipapp carries yt_dlp_ejs")
    XCTAssertTrue(compiled.value, "every module compiled")
    let tag = "cpython-\(try XCTUnwrap(Self.pythonTag()))"
    XCTAssertTrue(exists("\(version)/yt_dlp/__pycache__/__init__.\(tag).pyc"))
    XCTAssertTrue(exists("\(version)/yt_dlp_ejs/__pycache__/__init__.\(tag).pyc"))
  }

  // "315" from the bundle's python3.15 stdlib folder.
  private static func pythonTag() -> String? {
    let libs = Bundle.main.bundleURL.appendingPathComponent("python/lib").path
    let name = (try? FileManager.default.contentsOfDirectory(atPath: libs))?.first { $0.hasPrefix("python3.") }
    return name.map { $0.dropFirst("python".count).replacingOccurrences(of: ".", with: "") }
  }
}
