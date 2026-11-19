import XCTest
@testable import Runner

// yt-dlp's own postprocessors driving the in-process ffmpeg and ffprobe through InProcPopen (milestone M3).
final class FFmpegShimTests: XCTestCase {
  private var dir: URL!

  override func setUpWithError() throws {
    dir = FileManager.default.temporaryDirectory.appendingPathComponent("shim-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: dir)
  }

  private func path(_ name: String) -> String { dir.appendingPathComponent(name).path }

  private func ffmpeg(_ argv: [String]) async throws {
    let reply = try await PythonRuntime.shared.call("debug_ffmpeg", ["probe": false, "argv": argv, "task": "shim"])
    let value = try XCTUnwrap(reply as? [String: Any], "\(reply)")
    XCTAssertEqual(value["rc"] as? Int, 0, "\(value["out"] ?? "")")
  }

  private func streams(_ file: String) async throws -> (format: String, codecs: [String: String]) {
    let reply = try await PythonRuntime.shared.call(
      "debug_ffmpeg",
      ["probe": true, "argv": ["-hide_banner", "-show_format", "-show_streams", "-print_format", "json", file], "task": "shim"]
    )
    let out = try XCTUnwrap((reply as? [String: Any])?["out"] as? String, "\(reply)")
    let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: Any], out)
    var codecs: [String: String] = [:]
    for stream in json["streams"] as? [[String: Any]] ?? [] {
      if let type = stream["codec_type"] as? String { codecs[type] = stream["codec_name"] as? String }
    }
    return (((json["format"] as? [String: Any])?["format_name"] as? String) ?? "", codecs)
  }

  private func postprocess(_ kind: String, _ payload: [String: Any] = [:]) async throws -> String {
    let reply = try await PythonRuntime.shared.call("debug_pp", payload.merging(["kind": kind]) { a, _ in a })
    let out = try XCTUnwrap(reply as? String, "\(reply)")
    XCTAssertTrue(FileManager.default.fileExists(atPath: out), out)
    return out
  }

  private func clip(_ name: String, _ extra: [String] = []) async throws -> String {
    let out = path(name)
    try await ffmpeg([
      "-f", "lavfi", "-i", "testsrc=duration=2:size=320x240:rate=30", "-f", "lavfi", "-i", "sine=duration=2",
      "-c:v", "mpeg4", "-c:a", "aac", "-shortest",
    ] + extra + [out])
    return out
  }

  func testYtDlpFindsFfmpegAndFfprobe() async throws {
    let reply = try await PythonRuntime.shared.call("debug_pp", ["kind": "versions"])
    let value = try XCTUnwrap(reply as? [String: Any], "\(reply)")
    let versions = try XCTUnwrap(value["versions"] as? [String: String], "\(value)")
    XCTAssertNotNil(versions["ffmpeg"], "\(value)")
    XCTAssertNotNil(versions["ffprobe"], "\(value)")
    XCTAssertEqual(value["popen"] as? Bool, true)
    XCTAssertEqual(value["ffmpegFd"] as? Bool, false)
  }

  func testMergerJoinsVideoAndAudio() async throws {
    let source = try await clip("a.mp4")
    let video = path("v.mp4")
    let audio = path("a.m4a")
    try await ffmpeg(["-i", source, "-an", "-c", "copy", video])
    try await ffmpeg(["-i", source, "-vn", "-c", "copy", audio])
    let out = try await postprocess("merge", ["path": path("merged.mp4"), "video": video, "audio": audio])
    let probed = try await streams(out)
    XCTAssertEqual(probed.codecs["video"], "mpeg4")
    XCTAssertEqual(probed.codecs["audio"], "aac")
  }

  func testExtractAudioMakesMp3() async throws {
    let out = try await postprocess("mp3", ["path": try await clip("song.mp4")])
    XCTAssertTrue(out.hasSuffix(".mp3"), out)
    let probed = try await streams(out)
    XCTAssertEqual(probed.codecs["audio"], "mp3")
    XCTAssertNil(probed.codecs["video"])
  }

  func testThumbnailConvertsToJpg() async throws {
    let png = path("cover.png")
    try await ffmpeg(["-f", "lavfi", "-i", "testsrc=size=160x90", "-frames:v", "1", png])
    let out = try await postprocess("thumbnail", ["path": png])
    XCTAssertTrue(out.hasSuffix(".jpg"), out)
    let probed = try await streams(out)
    XCTAssertEqual(probed.codecs["video"], "mjpeg")
  }

  func testFixupM3u8RemuxesMpegTs() async throws {
    let file = try await clip("hls.mp4", ["-f", "mpegts"])
    let before = try await streams(file)
    XCTAssertEqual(before.format, "mpegts")
    let out = try await postprocess("fixup_m3u8", ["path": file])
    let after = try await streams(out)
    XCTAssertTrue(after.format.contains("mp4"), after.format)
    XCTAssertEqual(after.codecs["audio"], "aac")
  }
}
