import XCTest
@testable import Runner

// The M2 gate: YouTube's JS challenges solved in JavaScriptCore. Opt in with FETCHR_NETWORK_TESTS=1.
final class YouTubeIntegrationTests: XCTestCase {
  private static let video = "https://www.youtube.com/watch?v=aqz-KE-bpKQ"
  private static let short = "https://www.youtube.com/shorts/YX-6NbnG5hQ"

  private func requireNetwork() throws {
    try XCTSkipUnless(ProcessInfo.processInfo.environment["FETCHR_NETWORK_TESTS"] == "1", "network tests are opt-in")
  }

  private func solveTimes() async throws -> (plan: String, ms: [Int]) {
    let value = try await PythonRuntime.shared.call("debug_jsc", [:]) as? [String: Any]
    return (value?["plan"] as? String ?? "?", value?["solveMs"] as? [Int] ?? [])
  }

  // Returns the info and the JS solve times this fetch added.
  private func fetch(_ url: String, api: HostApi) async throws -> (VideoInfo, [Int], Int) {
    let before = try await solveTimes().ms.count
    let began = Date()
    let info: VideoInfo
    do {
      info = try await api.fetchInfo(url: url)
    } catch let error as FetchrError {
      XCTFail("\(error.code): \(error.message ?? "")")
      throw error
    }
    let total = Int(Date().timeIntervalSince(began) * 1000)
    let solves = Array(try await solveTimes().ms.dropFirst(before))
    return (info, solves, total)
  }

  func testYouTubeVideoInfo() async throws {
    try requireNetwork()
    let (info, solves, total) = try await fetch(Self.video, api: HostApi(python: PythonRuntime.shared))
    let plan = try await solveTimes().plan
    print("M2 youtube: plan \(plan), JS solve \(solves) ms, fetchInfo \(total) ms,", info.title,
      info.options.map { "\($0.quality)=\($0.sizeBytes.map(String.init) ?? "nil")" })
    XCTAssertFalse(solves.isEmpty, "no JS challenge went through JavaScriptCore")
    XCTAssertTrue(info.options.contains { $0.quality == .p1080 || $0.quality == .p720 })
    XCTAssertTrue(info.options.contains { $0.sizeBytes != nil })
  }

  func testYouTubeShortsInfo() async throws {
    try requireNetwork()
    let (info, solves, total) = try await fetch(Self.short, api: HostApi(python: PythonRuntime.shared))
    print("M2 short: JS solve \(solves) ms, fetchInfo \(total) ms,", info.title, info.options.map { "\($0.quality)" })
    XCTAssertFalse(info.options.isEmpty)
  }

  // A fresh cache dir makes the first fetch download the player; the second reads it from the cache.
  func testYouTubeSolveTimeColdAndWarm() async throws {
    try requireNetwork()
    let cache = FileManager.default.temporaryDirectory.appendingPathComponent("m2-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: cache) }
    let api = HostApi(python: PythonRuntime.shared, cacheDir: cache)
    let (_, cold, coldTotal) = try await fetch(Self.video, api: api)
    let (_, warm, warmTotal) = try await fetch(Self.video, api: api)
    let jit = ProcessInfo.processInfo.environment["JSC_useJIT"] ?? "default"
    print("M2 timing (JSC_useJIT=\(jit)): cold JS solve \(cold) ms, fetchInfo \(coldTotal) ms;",
      "warm JS solve \(warm) ms, fetchInfo \(warmTotal) ms")
    XCTAssertFalse(cold.isEmpty)
    XCTAssertFalse(warm.isEmpty)
  }
}
