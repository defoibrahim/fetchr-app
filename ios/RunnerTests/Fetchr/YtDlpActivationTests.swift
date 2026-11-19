import XCTest
@testable import Runner

// Review Focus 2: an installed yt-dlp that fails at launch gives way to the previous good one, then the bundled copy,
// and the record says why.
final class YtDlpActivationTests: XCTestCase {
  private var tmp: URL!
  private var root: URL { tmp.appendingPathComponent("yt-dlp", isDirectory: true) }
  private let suite = "fetchr.tests.\(UUID().uuidString)"
  private lazy var defaults = UserDefaults(suiteName: suite)!
  private let gate = RunGate()
  private let bundled = "2026.10.26"

  override func setUpWithError() throws {
    tmp = FileManager.default.temporaryDirectory.appendingPathComponent("activation-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    StubProtocol.serve { _ in (404, Data()) }
    UserDefaults().removePersistentDomain(forName: suite)
    try? FileManager.default.removeItem(at: tmp)
  }

  private func updater() -> YtDlpUpdater {
    YtDlpUpdater(root: root, session: StubProtocol.session(), gate: gate, defaults: defaults)
  }

  // A version dir as the updater leaves one; `ejs: false` is an update that would mix in the bundled yt_dlp_ejs.
  private func install(_ version: String, ejs: Bool = true, complete: Bool = true, extra: [String] = []) throws {
    let dir = root.appendingPathComponent(version, isDirectory: true)
    var files = ["yt_dlp/__init__.py": "", "yt_dlp/version.py": "__version__ = '\(version)'\n", "__main__.py": ""]
    for path in extra { files[path] = "" }
    if ejs { files["yt_dlp_ejs/__init__.py"] = "" }
    if complete { files[YtDlpUpdater.completeMarker] = "" }
    for (path, text) in files {
      let file = dir.appendingPathComponent(path)
      try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
      try Data(text.utf8).write(to: file)
    }
  }

  private func choose(_ updater: YtDlpUpdater, bundled: String? = nil) -> String? {
    updater.launchChoice(bundled: bundled ?? self.bundled)?.lastPathComponent
  }

  private func passed(_ version: String) -> SelftestResult { SelftestResult(ok: true, version: version, reason: "") }

  private func failed(_ version: String, _ reason: String) -> SelftestResult {
    SelftestResult(ok: false, version: version, reason: reason)
  }

  func testNewestGoodVersionIsChosen() throws {
    try install("2026.11.08")
    try install("2026.11.12")
    let updater = updater()
    XCTAssertEqual(choose(updater), "2026.11.12", "the newest, unproven")
    XCTAssertEqual(updater.launchRecord().attempt, "2026.11.12", "recorded before Python boots")
    updater.recordLaunch(passed("2026.11.12"))
    var record = updater.launchRecord()
    XCTAssertEqual(record.good, ["2026.11.12"])
    XCTAssertNil(record.attempt)
    XCTAssertEqual(record.last?.ok, true)
    XCTAssertEqual(record.last?.version, "2026.11.12")

    XCTAssertEqual(choose(updater), "2026.11.12", "good stays chosen")
    updater.recordLaunch(passed("2026.11.12"))
    XCTAssertEqual(updater.launchRecord().good, ["2026.11.12"], "listed once")

    XCTAssertEqual(choose(updater, bundled: "2026.11.12"), "2026.11.12", "an update equal to the bundled copy runs")
    updater.recordLaunch(passed("2026.11.12"))
    XCTAssertNil(choose(updater, bundled: "2026.12.01"), "a bundled copy newer than every update runs instead")
    record = updater.launchRecord()
    XCTAssertNil(record.attempt, "the bundled copy is never an attempt")
    XCTAssertEqual(record.bad, [])

    try install("2026.11.20", ejs: false)
    try install("2026.11.22", complete: false)
    XCTAssertEqual(choose(updater), "2026.11.12", "without its own yt_dlp_ejs, or cut short, an update never runs")
    updater.recordLaunch(passed("2026.11.12"))
    XCTAssertEqual(
      updater.launchChoice(bundled: bundled), root.appendingPathComponent("2026.11.12", isDirectory: true))
  }

  func testUnprovenVersionThatFailedIsSkippedNextLaunch() throws {
    try install("2026.11.08")
    let updater = updater()
    XCTAssertEqual(choose(updater), "2026.11.08")
    updater.recordLaunch(passed("2026.11.08"))

    try install("2026.11.12")
    XCTAssertEqual(choose(updater), "2026.11.12")
    // No verdict: the launch crashed or was killed before its selftest.
    XCTAssertEqual(choose(updater), "2026.11.08")
    var record = updater.launchRecord()
    XCTAssertEqual(record.bad, ["2026.11.12"])
    XCTAssertEqual(record.last?.ok, false)
    XCTAssertEqual(record.last?.version, "2026.11.12")
    XCTAssertTrue(record.last?.reason.contains("did not finish starting") == true, record.last?.reason ?? "")
    updater.recordLaunch(passed("2026.11.08"))

    try install("2026.11.20")
    XCTAssertEqual(choose(updater), "2026.11.20")
    updater.recordLaunch(failed("2026.11.20", "the in-process ffmpeg shim is not active"))
    record = updater.launchRecord()
    XCTAssertEqual(record.bad, ["2026.11.12", "2026.11.20"])
    XCTAssertEqual(record.last?.reason, "the in-process ffmpeg shim is not active")
    XCTAssertEqual(choose(updater), "2026.11.08")
    updater.recordLaunch(passed("2026.11.08"))

    try install("2026.11.22")
    XCTAssertEqual(choose(updater), "2026.11.22")
    // It passed, but Python ran another copy (the update failed to import and boot fell back in-process).
    updater.recordLaunch(passed(bundled))
    record = updater.launchRecord()
    XCTAssertTrue(record.bad.contains("2026.11.22"))
    XCTAssertEqual(record.last?.ok, false)
    XCTAssertTrue(record.last?.reason.contains("2026.10.26") == true, record.last?.reason ?? "")
    XCTAssertEqual(choose(updater), "2026.11.08")
  }

  func testBrokenNewestFallsBackToPreviousThenBundled() throws {
    try install("2026.11.08")
    let updater = updater()
    XCTAssertEqual(choose(updater), "2026.11.08")
    updater.recordLaunch(passed("2026.11.08"))
    try install("2026.11.12")

    XCTAssertEqual(choose(updater), "2026.11.12")
    // After an import failure Python reports the bundled copy it fell back to.
    updater.recordLaunch(failed(bundled, "yt-dlp 2026.11.12 failed to import: SyntaxError: invalid syntax"))
    XCTAssertEqual(choose(updater), "2026.11.08", "the previous good one")
    updater.recordLaunch(SelftestResult(ok: false, version: nil, reason: "Python failed to start: boom"))
    XCTAssertNil(choose(updater), "then the bundled copy")
    updater.recordLaunch(passed(bundled))

    let record = updater.launchRecord()
    XCTAssertEqual(record.bad, ["2026.11.12", "2026.11.08"])
    XCTAssertEqual(record.good, [], "a good version that later fails is no longer good")
    XCTAssertNil(record.attempt)
    XCTAssertEqual(record.last, LaunchResult(version: bundled, ok: true, reason: "", atMs: record.last?.atMs ?? 0))
    XCTAssertNil(choose(updater), "and it stays there")

    let file = root.appendingPathComponent(YtDlpUpdater.launchFile)
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
    XCTAssertEqual(json["bad"] as? [String], ["2026.11.12", "2026.11.08"])
  }

  // Review Focus 2 follow-up: a version that failed here is never offered as "installed for the next launch".
  func testBadVersionStillOnDiskIsNeverReportedAsInstalled() async throws {
    try install("2026.11.12")
    let updater = updater()
    XCTAssertEqual(choose(updater), "2026.11.12")
    updater.recordLaunch(failed(bundled, "yt-dlp 2026.11.12 failed to import: SyntaxError: x"))
    XCTAssertTrue(exists("2026.11.12"), "kept while this launch may still import from it")

    let python = FakePython()
    python.reply = { _ in ["ytDlpVersion": "2026.10.26"] }
    let api = HostApi(python: python, defaults: defaults, gate: gate, updater: updater)
    StubProtocol.serve(FakeRelease("2026.11.12").handler())
    let status = try await api.updateYtDlp()
    XCTAssertEqual(status.version, bundled, "the running version, never the bad one")
    XCTAssertEqual(StubProtocol.requests, [FakeRelease.api])

    let unknown = await code { try await updater.update(running: nil) }
    XCTAssertEqual(unknown, "unknown", "with nothing running to report, a bad release is no answer")

    XCTAssertNil(choose(updater))
    XCTAssertFalse(exists("2026.11.12"), "deleted before the next boot, when nothing runs it")
    XCTAssertEqual(updater.launchRecord().bad, ["2026.11.12"], "still remembered, so never downloaded again")
  }

  // A good version is not demoted by one launch that was killed before its verdict; two in a row it is.
  func testGoodVersionSurvivesOneMissingVerdictButNotTwo() throws {
    try install("2026.11.12")
    let updater = updater()
    XCTAssertEqual(choose(updater), "2026.11.12")
    updater.recordLaunch(passed("2026.11.12"))

    XCTAssertEqual(choose(updater), "2026.11.12")
    // Killed before the verdict, once.
    XCTAssertEqual(choose(updater), "2026.11.12", "one strike")
    var record = updater.launchRecord()
    XCTAssertEqual(record.good, ["2026.11.12"])
    XCTAssertEqual(record.bad, [])
    XCTAssertEqual(record.last?.ok, false)
    updater.recordLaunch(passed("2026.11.12"))

    XCTAssertEqual(choose(updater), "2026.11.12")
    XCTAssertEqual(choose(updater), "2026.11.12", "a pass reset the strikes")
    XCTAssertNil(choose(updater), "two missing verdicts in a row")
    record = updater.launchRecord()
    XCTAssertEqual(record.bad, ["2026.11.12"])
    XCTAssertEqual(record.good, [])
    XCTAssertTrue(record.last?.reason.contains("did not finish starting") == true, record.last?.reason ?? "")

    try install("2026.11.20")
    XCTAssertEqual(choose(updater), "2026.11.20")
    updater.recordLaunch(passed("2026.11.20"))
    XCTAssertEqual(choose(updater), "2026.11.20")
    updater.recordLaunch(failed("2026.11.20", "the JS challenge provider is not available"))
    XCTAssertEqual(updater.launchRecord().bad, ["2026.11.12", "2026.11.20"], "a reported failure demotes at once")
  }

  // Only yt-dlp's own top-level names go ahead of app_packages and the stdlib.
  func testVersionWithOtherTopLevelEntriesIsNeverRunOrInstalled() async throws {
    try install("2026.11.08")
    try install("2026.11.12", extra: ["json/__init__.py"])
    try install("2026.11.14", extra: ["__pycache__/__main__.cpython-315.pyc"])
    let updater = updater()
    XCTAssertEqual(choose(updater), "2026.11.14", "bytecode next to __main__.py is fine")
    updater.recordLaunch(passed("2026.11.14"))
    try FileManager.default.removeItem(at: root.appendingPathComponent("2026.11.14"))
    XCTAssertEqual(choose(updater), "2026.11.08", "a json package would shadow the stdlib")
    updater.recordLaunch(passed("2026.11.08"))

    var zip = ZipBuilder.zipapp(version: "2026.11.20")
    zip.add("json/__init__.py", "")
    StubProtocol.serve(FakeRelease("2026.11.20", zipapp: zip.build()).handler())
    let refused = await code { try await updater.update(running: "2026.11.08") }
    XCTAssertEqual(refused, "unknown")
    XCTAssertFalse(updater.installed().contains("2026.11.20"))
  }

  private func exists(_ path: String) -> Bool {
    FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path)
  }

  private func code(of body: () async throws -> Any) async -> String? {
    do {
      _ = try await body()
      return nil
    } catch {
      return (error as? FetchrError)?.code ?? "\(error)"
    }
  }

  func testUnreadableLaunchRecordStartsOver() throws {
    try install("2026.11.12")
    try Data("{not json".utf8).write(to: root.appendingPathComponent(YtDlpUpdater.launchFile))
    let updater = updater()
    XCTAssertEqual(choose(updater), "2026.11.12")
    XCTAssertEqual(updater.launchRecord().attempt, "2026.11.12")
  }

  func testNoRootChoosesTheBundledCopy() throws {
    try FileManager.default.removeItem(at: root)
    let updater = updater()
    XCTAssertNil(choose(updater))
    updater.recordLaunch(passed(bundled))
    XCTAssertEqual(updater.launchRecord().last?.ok, true)
  }

  func testBadReleaseIsNeverDownloadedAgain() async throws {
    try install("2026.11.12")
    let updater = updater()
    XCTAssertEqual(choose(updater), "2026.11.12")
    updater.recordLaunch(failed("2026.11.12", "the JS challenge provider is not registered"))
    try FileManager.default.removeItem(at: root.appendingPathComponent("2026.11.12"))

    StubProtocol.serve(FakeRelease("2026.11.12").handler())
    let installed = try await updater.update(running: bundled)
    XCTAssertEqual(installed, bundled, "nothing new for the next launch")
    XCTAssertEqual(StubProtocol.requests, [FakeRelease.api])
    XCTAssertEqual(updater.installed(), [])
    XCTAssertNotNil(updater.checkedAtMs, "the check itself succeeded")
  }

  func testPruneDropsBadVersionsBeforeGoodOnes() async throws {
    try install("2026.11.01")
    try install("2026.11.08")
    let updater = updater()
    XCTAssertEqual(choose(updater), "2026.11.08")
    updater.recordLaunch(failed("2026.11.08", "broken"))
    XCTAssertEqual(choose(updater), "2026.11.01")
    updater.recordLaunch(passed("2026.11.01"))

    StubProtocol.serve(FakeRelease("2026.11.12").handler())
    _ = try await updater.update(running: "2026.11.01")
    XCTAssertEqual(updater.installed(), ["2026.11.12", "2026.11.01"], "the bad one goes, the previous good stays")
    XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(YtDlpUpdater.launchFile).path))
  }

  // Bytecode is written once, at install: the bundle's stays read-only and Python never writes it at import.
  func testInstallCompilesBeforeMarkingTheVersionComplete() async throws {
    let seen = Seen()
    let compiling = YtDlpUpdater(
      root: root, session: StubProtocol.session(), gate: gate, defaults: defaults,
      compile: { [root] dir in
        let marked = FileManager.default.fileExists(atPath: dir.appendingPathComponent(YtDlpUpdater.completeMarker).path)
        let unpacked = FileManager.default.fileExists(atPath: dir.appendingPathComponent("yt_dlp/version.py").path)
        seen.add("\(dir.path.replacingOccurrences(of: root.path + "/", with: "")) marked=\(marked) unpacked=\(unpacked)")
      })
    StubProtocol.serve(FakeRelease("2026.11.12").handler())
    _ = try await compiling.update(running: bundled)
    XCTAssertEqual(seen.all, ["2026.11.12 marked=false unpacked=true"])
    XCTAssertEqual(compiling.installed(), ["2026.11.12"])

    // Source imports still work, so a failed compile installs anyway.
    let failing = YtDlpUpdater(
      root: root, session: StubProtocol.session(), gate: gate, defaults: defaults,
      compile: { _ in throw BridgeError(hint: nil, message: "compile failed") })
    StubProtocol.serve(FakeRelease("2026.11.20").handler())
    _ = try await failing.update(running: bundled)
    XCTAssertEqual(failing.installed(), ["2026.11.20", "2026.11.12"])
  }

  func testBundledVersionIsReadFromTheBundle() throws {
    let bundle = tmp.appendingPathComponent("Runner.app", isDirectory: true)
    let file = bundle.appendingPathComponent("app_packages/yt_dlp/version.py")
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("# Autogenerated\n\n__version__ = '2026.10.26'\n".utf8).write(to: file)
    XCTAssertEqual(YtDlpUpdater.bundledVersion(in: bundle), "2026.10.26")
    XCTAssertNil(YtDlpUpdater.bundledVersion(in: tmp))
    XCTAssertEqual(YtDlpUpdater.bundledVersion(in: Bundle.main.bundleURL), "2026.10.26", "the copy this build ships")
  }

  // The real bridge: the bundled copy imports, its Popen is the in-process shim and JavaScriptCore is registered.
  func testBundledCopyPassesTheRealSelftest() async throws {
    let reply = try await PythonRuntime.shared.call("selftest", [:])
    XCTAssertEqual(SelftestResult(reply: reply), passed(bundled))
  }

  func testSelftestResultReadsTheBridgeReply() {
    XCTAssertEqual(
      SelftestResult(reply: ["ok": true, "version": "2026.11.12", "reason": ""]), passed("2026.11.12"))
    XCTAssertEqual(SelftestResult(reply: "nonsense").ok, false)
  }
}

final class YtDlpStartupTests: XCTestCase {
  private var tmp: URL!
  private var root: URL { tmp.appendingPathComponent("yt-dlp", isDirectory: true) }
  private let suite = "fetchr.tests.\(UUID().uuidString)"
  private lazy var defaults = UserDefaults(suiteName: suite)!
  private let gate = RunGate()
  private let python = FakePython()

  override func setUpWithError() throws {
    tmp = FileManager.default.temporaryDirectory.appendingPathComponent("startup-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    StubProtocol.serve { _ in (404, Data()) }
    UserDefaults().removePersistentDomain(forName: suite)
    try? FileManager.default.removeItem(at: tmp)
  }

  private func updater() -> YtDlpUpdater {
    YtDlpUpdater(root: root, session: StubProtocol.session(), gate: gate, defaults: defaults)
  }

  private func selftestReplies(_ version: String, ok: Bool = true) {
    python.reply = { name in
      name == "selftest"
        ? ["ok": ok, "version": version, "reason": ok ? "" : "the JS challenge provider is not registered"]
        : ["ytDlpVersion": version]
    }
  }

  private static func nowMs() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

  func testStartupRecordsTheSelftestThenUpdatesWhenDue() async throws {
    let updater = updater()
    selftestReplies("2026.10.26")
    StubProtocol.serve(FakeRelease("2026.11.12").handler())
    await YtDlpStartup.run(python: python, updater: updater)
    XCTAssertEqual(python.calls.map(\.name), ["selftest"])
    XCTAssertEqual(updater.launchRecord().last?.ok, true)
    XCTAssertEqual(updater.installed(), ["2026.11.12"], "due: never checked, auto-update on by default")
    XCTAssertNotNil(updater.checkedAtMs)
  }

  func testStartupSkipsTheUpdateWhenNotDueOrOff() async throws {
    let updater = updater()
    selftestReplies("2026.10.26")
    StubProtocol.serve(FakeRelease("2026.11.12").handler())

    defaults.set(NSNumber(value: Self.nowMs() - 60_000), forKey: YtDlpUpdater.checkedAtKey)
    await YtDlpStartup.run(python: python, updater: updater)
    XCTAssertEqual(StubProtocol.requests, [], "checked a minute ago")

    defaults.set(NSNumber(value: Self.nowMs() - 25 * 3_600_000), forKey: YtDlpUpdater.checkedAtKey)
    defaults.set(false, forKey: YtDlpUpdater.autoUpdateKey)
    await YtDlpStartup.run(python: python, updater: updater)
    XCTAssertEqual(StubProtocol.requests, [], "auto-update off")

    defaults.set(true, forKey: YtDlpUpdater.autoUpdateKey)
    await YtDlpStartup.run(python: python, updater: updater)
    XCTAssertEqual(updater.installed(), ["2026.11.12"], "a day later")
  }

  func testFailedBootIsAFailedLaunchAndUpdatesNothing() async throws {
    let dir = root.appendingPathComponent("2026.11.12", isDirectory: true)
    for path in ["yt_dlp/__init__.py", "yt_dlp/version.py", "yt_dlp_ejs/__init__.py", YtDlpUpdater.completeMarker] {
      let file = dir.appendingPathComponent(path)
      try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
      try Data().write(to: file)
    }
    let updater = updater()
    XCTAssertEqual(updater.launchChoice(bundled: "2026.10.26"), dir)
    python.reply = { _ in throw BridgeError(hint: nil, message: "Python failed to start: SyntaxError") }
    StubProtocol.serve(FakeRelease("2026.11.20").handler())
    await YtDlpStartup.run(python: python, updater: updater)
    let record = updater.launchRecord()
    XCTAssertEqual(record.bad, ["2026.11.12"])
    XCTAssertEqual(record.last?.reason, "Python failed to start: SyntaxError")
    XCTAssertEqual(StubProtocol.requests, [], "Android skips the update when init fails")
    XCTAssertNil(updater.launchChoice(bundled: "2026.10.26"))
  }

  func testStatusWaitsForAStartupUpdateAtMostItsTimeout() async throws {
    let updater = updater()
    selftestReplies("2026.10.26")
    let release = Flag()
    StubProtocol.serve(FakeRelease("2026.11.12").handler(hold: {
      while !release.value { try? await Task.sleep(nanoseconds: 10_000_000) }
    }))
    let startup = YtDlpStartup()
    startup.begin { [python] in await YtDlpStartup.run(python: python, updater: updater) }
    let api = HostApi(
      python: python, defaults: defaults, gate: gate, updater: updater, startup: startup, startupWait: 0.4)

    let began = Date()
    let held = try await api.ytDlpStatus()
    let waited = Date().timeIntervalSince(began)
    XCTAssertGreaterThanOrEqual(waited, 0.35, "waits for the startup update")
    XCTAssertLessThan(waited, 2, "but only until its timeout")
    XCTAssertNil(held.checkedAtMs)
    XCTAssertEqual(held.version, "2026.10.26")

    release.set()
    await startup.wait(timeout: 10)
    let done = try await api.ytDlpStatus()
    XCTAssertNotNil(done.checkedAtMs, "the update finished and was stamped")

    let quick = YtDlpStartup()
    quick.begin {}
    let api2 = HostApi(python: python, defaults: defaults, startup: quick, startupWait: 5)
    let start = Date()
    _ = try await api2.ytDlpStatus()
    XCTAssertLessThan(Date().timeIntervalSince(start), 1, "a finished startup costs nothing")
  }
}

private final class Seen: @unchecked Sendable {
  private let lock = NSLock()
  private var items: [String] = []
  var all: [String] { lock.withLock { items } }
  func add(_ item: String) { lock.withLock { items.append(item) } }
}
