import XCTest
@testable import Runner

// Hits the network through the real embedded yt-dlp; opt in with FETCHR_NETWORK_TESTS=1.
final class FetchInfoIntegrationTests: XCTestCase {
  private func api() throws -> HostApi {
    try XCTSkipUnless(ProcessInfo.processInfo.environment["FETCHR_NETWORK_TESTS"] == "1", "network tests are opt-in")
    return HostApi(python: PythonRuntime.shared)
  }

  private func fetch(_ url: String) async throws -> VideoInfo {
    do {
      return try await api().fetchInfo(url: url)
    } catch let error as FetchrError {
      XCTFail("\(error.code): \(error.message ?? "")")
      throw error
    }
  }

  func testGenericMp4() async throws {
    // The Blender mp4 named in the plan is gone (404), and Vimeo now wants a login.
    let info = try await fetch(
      "https://interactive-examples.mdn.mozilla.net/media/cc0-videos/flower.mp4")
    print("M1 generic:", info.title, info.options.map { "\($0.quality)" })
    XCTAssertFalse(info.options.isEmpty)
  }

  func testDailymotion() async throws {
    let info = try await fetch("https://www.dailymotion.com/video/xbnvc92")
    print("M1 dailymotion:", info.title, info.options.map { "\($0.quality)" })
    let tiers: Set<Quality> = [.p1080, .p720, .p480]
    XCTAssertFalse(tiers.isDisjoint(with: info.options.map(\.quality)))
  }

  func testUnreachableHost() async throws {
    let api = try api()
    do {
      _ = try await api.fetchInfo(url: "https://nonexistent.invalid/x")
      XCTFail("expected a failure")
    } catch let error as FetchrError {
      print("M1 invalid host:", error.code, error.message ?? "")
      XCTAssertTrue(["network", "unavailable"].contains(error.code), error.code)
    }
  }
}
