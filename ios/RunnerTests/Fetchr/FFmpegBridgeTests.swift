import XCTest
@testable import Runner

final class FFmpegBridgeTests: XCTestCase {
  // -re paces the input in real time; without it testsrc to the null muxer finishes "600 s" in about a second.
  private static let endless = ["-re", "-f", "lavfi", "-i", "testsrc=duration=600:size=320x240:rate=30", "-f", "null", "-"]

  private var dir: URL!

  override func setUpWithError() throws {
    dir = FileManager.default.temporaryDirectory.appendingPathComponent("ffmpeg-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: dir)
  }

  private func path(_ name: String) -> String { dir.appendingPathComponent(name).path }

  // A failed assertion must not leave a 600 s run holding the serialize gate for every later test.
  private func cancelOnTeardown(_ tasks: String...) {
    addTeardownBlock {
      for task in tasks {
        _ = try? await PythonRuntime.shared.call("debug_ffmpeg_cancel", ["task": task])
        _ = try? await PythonRuntime.shared.call("debug_ffmpeg_forget", ["task": task])
      }
    }
  }

  private func run(_ argv: [String], probe: Bool = false, task: String = "test") async throws -> (rc: Int, out: String) {
    let reply = try await PythonRuntime.shared.call("debug_ffmpeg", ["probe": probe, "argv": argv, "task": task])
    let value = try XCTUnwrap(reply as? [String: Any], "\(reply)")
    return (try XCTUnwrap(value["rc"] as? Int), try XCTUnwrap(value["out"] as? String))
  }

  @discardableResult
  private func generate(_ name: String = "a.mp4", seconds: Int = 2) async throws -> String {
    let out = path(name)
    let result = try await run([
      "-f", "lavfi", "-i", "testsrc=duration=\(seconds):size=320x240:rate=30", "-f", "lavfi", "-i", "sine=duration=\(seconds)",
      "-c:v", "mpeg4", "-c:a", "aac", "-shortest", out,
    ])
    XCTAssertEqual(result.rc, 0, result.out)
    return out
  }

  private func split(_ source: String, prefix: String = "") async throws -> (video: String, audio: String) {
    let video = path("\(prefix)v.mp4")
    let audio = path("\(prefix)a.m4a")
    let v = try await run(["-i", source, "-an", "-c", "copy", video])
    XCTAssertEqual(v.rc, 0, v.out)
    let a = try await run(["-i", source, "-vn", "-c", "copy", audio])
    XCTAssertEqual(a.rc, 0, a.out)
    return (video, audio)
  }

  private func merge(_ parts: (video: String, audio: String), into out: String, task: String = "test") async throws -> Int {
    try await run(
      ["-y", "-i", parts.video, "-i", parts.audio, "-c", "copy", "-map", "0:v:0", "-map", "1:a:0", "-movflags", "+faststart", out],
      task: task
    ).rc
  }

  // Catches the lost first log only when it is the process's first session, as when this test runs alone.
  func testEverySessionKeepsItsLog() async throws {
    for _ in 0..<2 {
      let result = try await run(["-nostdin", "-bsfs"])
      XCTAssertEqual(result.rc, 0)
      XCTAssertTrue(result.out.contains("ffmpeg version"), result.out)
    }
  }

  func testGeneratesVideoAndAudio() async throws {
    let out = try await generate()
    XCTAssertTrue(FileManager.default.fileExists(atPath: out))
  }

  func testMergeCopyToMp4() async throws {
    let parts = try await split(try await generate())
    let out = path("m.mp4")
    let rc = try await merge(parts, into: out)
    XCTAssertEqual(rc, 0)
    XCTAssertTrue(FileManager.default.fileExists(atPath: out))
  }

  func testMp3WithProgressFile() async throws {
    let source = try await generate()
    let progress = path("ffmpeg.progress")
    let out = path("out.mp3")
    let result = try await run(["-i", source, "-vn", "-acodec", "libmp3lame", "-q:a", "0", "-progress", progress, out])
    XCTAssertEqual(result.rc, 0, result.out)
    XCTAssertTrue(FileManager.default.fileExists(atPath: out))
    let report = try String(contentsOfFile: progress, encoding: .utf8)
    XCTAssertTrue(report.contains("out_time_us="), report)
    XCTAssertTrue(report.contains("progress=end"), report)
  }

  func testProbeJson() async throws {
    let source = try await generate()
    let result = try await run(["-hide_banner", "-show_format", "-show_streams", "-print_format", "json", source], probe: true)
    XCTAssertEqual(result.rc, 0, result.out)
    let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(result.out.utf8)) as? [String: Any], result.out)
    let streams = try XCTUnwrap(json["streams"] as? [[String: Any]])
    XCTAssertEqual(streams.count, 2)
    XCTAssertEqual(Set(streams.compactMap { $0["codec_type"] as? String }), ["video", "audio"])
  }

  func testCancelReturns255() async throws {
    cancelOnTeardown("t1")
    let long = Task { try await run(Self.endless, task: "t1") }
    try await Task.sleep(nanoseconds: 500_000_000)
    let cancelled = Date()
    _ = try await PythonRuntime.shared.call("debug_ffmpeg_cancel", ["task": "t1"])
    let result = try await long.value
    XCTAssertEqual(result.rc, 255, result.out)
    XCTAssertLessThan(Date().timeIntervalSince(cancelled), 2)
  }

  func testCancelWhileWaitingForTheLock() async throws {
    XCTAssertTrue(fetchr_ff_serialize)
    cancelOnTeardown("holder", "queued")
    let holder = Task { try await run(Self.endless, task: "holder") }
    try await Task.sleep(nanoseconds: 300_000_000)
    let queued = Task { try await run(Self.endless, task: "queued") }
    try await Task.sleep(nanoseconds: 300_000_000)
    let cancelled = Date()
    _ = try await PythonRuntime.shared.call("debug_ffmpeg_cancel", ["task": "queued"])
    let result = try await queued.value
    XCTAssertEqual(result.rc, 255, result.out)
    XCTAssertLessThan(Date().timeIntervalSince(cancelled), 2)
    _ = try await PythonRuntime.shared.call("debug_ffmpeg_cancel", ["task": "holder"])
    let held = try await holder.value
    XCTAssertEqual(held.rc, 255, held.out)
  }

  // yt-dlp finds ffprobe by its `-bsfs` output, which ffprobe prints to the log rather than through its writer.
  func testProbeBsfsPrintsVersionAndList() async throws {
    let result = try await run(["-bsfs"], probe: true)
    XCTAssertEqual(result.rc, 0, result.out)
    XCTAssertTrue(result.out.contains("ffprobe version"), result.out)
    XCTAssertTrue(result.out.contains("aac_adtstoasc"), result.out)
  }

  func testProbeWithItsOwnOutputPrintsNothing() async throws {
    let source = try await generate()
    let report = path("probe.json")
    let result = try await run(["-show_streams", "-print_format", "json", "-o", report, source], probe: true)
    XCTAssertEqual(result.rc, 0)
    XCTAssertEqual(result.out, "")
    let json = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: report))) as? [String: Any]
    XCTAssertEqual((json?["streams"] as? [Any])?.count, 2)
  }

  // A cancel that lands before the next session registers must still stop it, until the task is forgotten.
  func testCancelStopsLaterRunsUntilForgotten() async throws {
    cancelOnTeardown("s1")
    _ = try await PythonRuntime.shared.call("debug_ffmpeg_cancel", ["task": "s1"])
    let stopped = try await run(["-version"], task: "s1")
    XCTAssertEqual(stopped.rc, 255, stopped.out)
    _ = try await PythonRuntime.shared.call("debug_ffmpeg_forget", ["task": "s1"])
    let again = try await run(["-version"], task: "s1")
    XCTAssertEqual(again.rc, 0, again.out)
  }

  func testCancelOtherTaskLeavesRunAlone() async throws {
    let source = try await generate()
    _ = try await PythonRuntime.shared.call("debug_ffmpeg_cancel", ["task": "nobody"])
    _ = try await PythonRuntime.shared.call("debug_ffmpeg_forget", ["task": "nobody"])
    let result = try await run(["-i", source, "-f", "null", "-"], task: "t2")
    XCTAssertEqual(result.rc, 0, result.out)
  }

  func testStringArgvIsRejected() async throws {
    do {
      let reply = try await PythonRuntime.shared.call("debug_ffmpeg", ["probe": false, "argv": "-version", "task": "test"])
      XCTFail("a str argv ran: \(reply)")
    } catch {
      XCTAssertTrue("\(error)".contains("not a str"), "\(error)")
    }
  }

  func testVersionBanner() async throws {
    let result = try await run(["-version"])
    XCTAssertEqual(result.rc, 0, result.out)
    XCTAssertTrue(result.out.hasPrefix("ffmpeg version"), result.out)
  }

  func testConcurrentSessionsWithSerializeOff() async throws {
    // Long enough that the two merges overlap instead of finishing one after the other.
    let source = try await generate(seconds: 60)
    let first = try await split(source, prefix: "1")
    let second = try await split(source, prefix: "2")
    let saved = fetchr_ff_serialize
    fetchr_ff_serialize = false
    defer { fetchr_ff_serialize = saved }
    for round in 0..<10 {
      async let one = merge(first, into: path("m1.mp4"), task: "c1")
      async let two = merge(second, into: path("m2.mp4"), task: "c2")
      let codes = try await [one, two]
      XCTAssertEqual(codes, [0, 0], "round \(round)")
    }
  }
}
