import XCTest
@testable import Runner

final class FakePython: PythonCalling, @unchecked Sendable {
  private let lock = NSLock()
  private var recorded: [(name: String, payload: [String: Any])] = []
  var reply: @Sendable (String) throws -> Any = { _ in "" }
  // Awaited before the reply, so a test can keep a call in "Python".
  var hold: @Sendable (String) async -> Void = { _ in }

  var calls: [(name: String, payload: [String: Any])] { lock.withLock { recorded } }

  func call(_ name: String, _ payload: [String: Any]) async throws -> Any {
    lock.withLock { recorded.append((name, payload)) }
    await hold(name)
    return try reply(name)
  }
}

final class HostApiTests: XCTestCase {
  private let cache = URL(fileURLWithPath: "/tmp/fetchr-cache", isDirectory: true)
  private let fake = FakePython()

  private let suite = "fetchr.tests.\(UUID().uuidString)"
  private lazy var defaults = UserDefaults(suiteName: suite)!

  override func tearDown() {
    UserDefaults().removePersistentDomain(forName: suite)
    super.tearDown()
  }

  private func api() -> HostApi { HostApi(python: fake, cacheDir: cache, defaults: defaults) }

  func testAwaitLaunchSplashCompletesAtOnce() async throws {
    let start = Date()
    try await api().awaitLaunchSplash()
    XCTAssertLessThan(Date().timeIntervalSince(start), 0.1)
  }

  // Every method works on the iPhone now; only a host built without its repository (a test) has none to call.
  func testAHostWithoutItsRepositorySaysItIsMisconfigured() {
    XCTAssertThrowsError(try api().cancel(id: "x")) { error in
      let fetchr = error as? FetchrError
      XCTAssertEqual(fetchr?.code, "unknown")
      XCTAssertEqual(fetchr?.message, "Fetchr was set up without its download engine.")
    }
  }

  func testAccentColorIsStored() throws {
    try api().setAccentColor(argb: 0xFF112233)
    XCTAssertEqual(defaults.integer(forKey: "fetchr.accentColor"), 0xFF112233)
  }

  func testFetchInfoRejectsBadUrlWithoutCallingPython() async {
    do {
      _ = try await api().fetchInfo(url: "-o x")
      XCTFail("expected a failure")
    } catch {
      XCTAssertEqual((error as? FetchrError)?.code, "invalid_url")
    }
    XCTAssertTrue(fake.calls.isEmpty)
  }

  func testFetchInfoParsesBridgeJson() async throws {
    let reply = try JSONSerialization.jsonObject(with: Data(infoFixture("video").utf8))
    fake.reply = { _ in reply }
    let info = try await api().fetchInfo(url: "  https://example.com/v  ")

    XCTAssertEqual(info.title, "Big Buck Bunny 60fps 4K - Official Blender Foundation Short Film")
    XCTAssertEqual(info.options.first?.quality, .best)
    let call = try XCTUnwrap(fake.calls.first)
    XCTAssertEqual(call.name, "info")
    XCTAssertEqual(call.payload["argv"] as? [String], ["--flat-playlist", "--cache-dir", cache.path + "/yt-dlp"])
    XCTAssertEqual(call.payload["url"] as? String, "https://example.com/v")
  }

  func testFetchInfoMapsBridgeErrors() async {
    fake.reply = { _ in throw BridgeError(hint: "network", message: "ERROR: boom") }
    do {
      _ = try await api().fetchInfo(url: "https://example.com/v")
      XCTFail("expected a failure")
    } catch let error as FetchrError {
      XCTAssertEqual(error.code, "network")
      XCTAssertEqual(error.message, "boom")
    } catch {
      XCTFail("unexpected \(error)")
    }
  }

  func testYtDlpStatusReportsVersion() async throws {
    fake.reply = { _ in ["ytDlpVersion": "2026.10.26"] }
    let status = try await api().ytDlpStatus()
    XCTAssertEqual(status.version, "2026.10.26")
    XCTAssertTrue(status.autoUpdate)
  }

  func testYtDlpStatusSurfacesBootFailure() async {
    fake.reply = { _ in throw BridgeError(hint: nil, message: "Python failed to start: x") }
    do {
      _ = try await api().ytDlpStatus()
      XCTFail("expected a failure")
    } catch {
      XCTAssertEqual((error as? FetchrError)?.code, "unknown")
    }
  }
}
