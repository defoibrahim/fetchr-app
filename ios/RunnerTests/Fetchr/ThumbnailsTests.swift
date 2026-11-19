import ImageIO
import XCTest
@testable import Runner

final class ThumbnailsTests: XCTestCase {
  private var root: URL!
  private var documents: URL!
  private var caches: URL!
  private var scratch: URL!
  private var thumbs: URL { caches.appendingPathComponent("thumbs", isDirectory: true) }

  override func setUpWithError() throws {
    root = FileManager.default.temporaryDirectory.appendingPathComponent("thumbs-\(UUID().uuidString)")
    documents = root.appendingPathComponent("Documents", isDirectory: true)
    caches = root.appendingPathComponent("Caches", isDirectory: true)
    scratch = root.appendingPathComponent("scratch", isDirectory: true)
    for dir in [documents!, caches!, scratch!] {
      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: root)
  }

  private func library() -> Library { Library(documents: documents, caches: caches) }

  private func uri(_ rel: String) -> String { documents.appendingPathComponent(rel, isDirectory: false).absoluteString }

  private func ffmpeg(_ argv: [String]) async throws {
    let reply = try await PythonRuntime.shared.call("debug_ffmpeg", ["probe": false, "argv": argv, "task": "thumbs"])
    let value = try XCTUnwrap(reply as? [String: Any], "\(reply)")
    XCTAssertEqual(value["rc"] as? Int, 0, value["out"] as? String ?? "")
  }

  private func scratchFile(_ ext: String) -> URL { scratch.appendingPathComponent("\(UUID().uuidString).\(ext)") }

  @discardableResult
  private func video(_ rel: String, size: String = "320x240") async throws -> URL {
    let tmp = scratchFile("mp4")
    try await ffmpeg([
      "-y", "-f", "lavfi", "-i", "testsrc=duration=2:size=\(size):rate=30", "-c:v", "mpeg4", tmp.path,
    ])
    return try place(tmp, at: rel)
  }

  private func plainMp3() async throws -> URL {
    let tmp = scratchFile("mp3")
    try await ffmpeg(["-y", "-f", "lavfi", "-i", "sine=duration=2", "-c:a", "libmp3lame", "-q:a", "2", tmp.path])
    return tmp
  }

  // An MP3 with an attached picture, as yt-dlp's --embed-thumbnail writes it.
  private func mp3WithCover() async throws -> URL {
    let cover = scratchFile("png")
    try await ffmpeg(["-y", "-f", "lavfi", "-i", "color=c=red:size=200x200", "-frames:v", "1", cover.path])
    let plain = try await plainMp3()
    let out = scratchFile("mp3")
    try await ffmpeg([
      "-y", "-i", plain.path, "-i", cover.path, "-map", "0", "-map", "1", "-c", "copy", "-id3v2_version", "3",
      "-metadata:s:v", "title=Album cover", "-metadata:s:v", "comment=Cover (front)", out.path,
    ])
    return out
  }

  @discardableResult
  private func place(_ file: URL, at rel: String, modified: Date? = nil) throws -> URL {
    let target = documents.appendingPathComponent(rel)
    try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? FileManager.default.removeItem(at: target)
    try FileManager.default.moveItem(at: file, to: target)
    if let modified {
      try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: target.path)
    }
    return target
  }

  private func write(_ rel: String, _ data: Data) throws {
    let target = documents.appendingPathComponent(rel)
    try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: target)
  }

  private func pixelSize(_ path: String) throws -> (Int, Int) {
    let source = try XCTUnwrap(CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil))
    XCTAssertEqual(CGImageSourceGetType(source) as String?, "public.jpeg")
    let props = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    let width = try XCTUnwrap(props[kCGImagePropertyPixelWidth] as? Int)
    return (width, try XCTUnwrap(props[kCGImagePropertyPixelHeight] as? Int))
  }

  private func centrePixel(_ path: String) throws -> (Int, Int, Int) {
    let source = try XCTUnwrap(CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil))
    let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    var pixel = [UInt8](repeating: 0, count: 4)
    let context = try XCTUnwrap(
      CGContext(
        data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
    context.draw(image, in: CGRect(x: -image.width / 2, y: -image.height / 2, width: image.width, height: image.height))
    return (Int(pixel[0]), Int(pixel[1]), Int(pixel[2]))
  }

  private func thumbFiles() -> [String] {
    (try? FileManager.default.contentsOfDirectory(atPath: thumbs.path)) ?? []
  }

  func testVideoThumbnailIsACachedJpegOfTheRequestedSize() async throws {
    try await video("Movies/Fetchr/Road trip/a b.mp4")

    let first = try await library().thumbnail(uri: uri("Movies/Fetchr/Road trip/a b.mp4"), widthPx: 160, heightPx: 90)

    let path = try XCTUnwrap(first)
    XCTAssertTrue(path.hasPrefix(thumbs.path + "/") || path.hasPrefix(thumbs.resolvingSymlinksInPath().path + "/"), path)
    XCTAssertTrue(path.hasSuffix(".jpg"), path)
    let (width, height) = try pixelSize(path)
    XCTAssertLessThanOrEqual(width, 160)
    XCTAssertLessThanOrEqual(height, 90)
    XCTAssertTrue(width >= 159 || height >= 89, "fits the box: \(width)x\(height)")
    XCTAssertEqual(thumbFiles(), [(path as NSString).lastPathComponent], "no temp file left behind")
    let written = try FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date

    let second = try await library().thumbnail(uri: uri("Movies/Fetchr/Road trip/a b.mp4"), widthPx: 160, heightPx: 90)

    XCTAssertEqual(second, path)
    XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date, written)
    let other = try await library().thumbnail(uri: uri("Movies/Fetchr/Road trip/a b.mp4"), widthPx: 480, heightPx: 300)
    XCTAssertNotEqual(try XCTUnwrap(other), path, "another size is another file")
  }

  func testMp3WithCoverArtHasAThumbnailAndPlainMp3HasNone() async throws {
    try place(try await mp3WithCover(), at: "Music/Fetchr/cover.mp3")
    try place(try await plainMp3(), at: "Music/Fetchr/plain.mp3")

    let covered = try await library().thumbnail(uri: uri("Music/Fetchr/cover.mp3"), widthPx: 160, heightPx: 90)
    let plain = try await library().thumbnail(uri: uri("Music/Fetchr/plain.mp3"), widthPx: 160, heightPx: 90)

    let path = try XCTUnwrap(covered)
    XCTAssertEqual(try pixelSize(path).0, 90, "a square cover fits the box's height")
    XCTAssertEqual(try pixelSize(path).1, 90)
    let (red, green, blue) = try centrePixel(path)
    XCTAssertTrue(red > 200 && green < 60 && blue < 60, "the red cover, not a placeholder: \(red),\(green),\(blue)")
    XCTAssertNil(plain)
  }

  func testCorruptFileHasNoThumbnail() async throws {
    try write("Movies/Fetchr/corrupt.mp4", Data(repeating: 0x42, count: 4096))
    try write("Movies/Fetchr/empty.mp4", Data())

    for rel in ["Movies/Fetchr/corrupt.mp4", "Movies/Fetchr/empty.mp4", "Movies/Fetchr/gone.mp4"] {
      let thumb = try await library().thumbnail(uri: uri(rel), widthPx: 160, heightPx: 90)
      XCTAssertNil(thumb, rel)
    }
    XCTAssertEqual(thumbFiles(), [], "nothing written, no temp file left")
  }

  func testReplacedFileGetsANewThumbnail() async throws {
    let rel = "Movies/Fetchr/a.mp4"
    let landscape = try await video("Movies/Fetchr/a.mp4", size: "320x240")
    try FileManager.default.setAttributes(
      [.modificationDate: Date(timeIntervalSince1970: 1_700_000_000)], ofItemAtPath: landscape.path)
    let first = try await library().thumbnail(uri: uri(rel), widthPx: 160, heightPx: 160)
    let before = try XCTUnwrap(first)
    XCTAssertGreaterThan(try pixelSize(before).0, try pixelSize(before).1)

    try await video(rel, size: "240x320")
    let second = try await library().thumbnail(uri: uri(rel), widthPx: 160, heightPx: 160)
    let after = try XCTUnwrap(second)

    XCTAssertNotEqual(after, before)
    let (width, height) = try pixelSize(after)
    XCTAssertLessThan(width, height, "the new, portrait file")
  }

  // The fallback for a video QuickLook cannot draw, called directly because QuickLook draws every test video.
  func testFrameFallbackGivesAFrameThatFitsTheBox() async throws {
    let tmp = scratchFile("mp4")
    try await ffmpeg(["-y", "-f", "lavfi", "-i", "color=c=red:size=320x240:duration=2:rate=30", "-c:v", "mpeg4", tmp.path])
    let corrupt = scratchFile("mp4")
    try Data(repeating: 0x42, count: 4096).write(to: corrupt)

    let frame = await Thumbnails.frame(of: tmp, fitting: CGSize(width: 160, height: 90))
    let none = await Thumbnails.frame(of: corrupt, fitting: CGSize(width: 160, height: 90))

    let image = try XCTUnwrap(frame)
    XCTAssertLessThanOrEqual(image.width, 160)
    XCTAssertLessThanOrEqual(image.height, 90)
    XCTAssertEqual(image.height, 90, "a 4:3 frame fills the box's height")
    var pixel = [UInt8](repeating: 0, count: 4)
    let context = try XCTUnwrap(
      CGContext(
        data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
    context.draw(image, in: CGRect(x: -image.width / 2, y: -image.height / 2, width: image.width, height: image.height))
    XCTAssertTrue(pixel[0] > 200 && pixel[1] < 60 && pixel[2] < 60, "a red frame: \(pixel)")
    XCTAssertNil(none)
  }

  func testThumbnailRejectsAUriOutsideDocuments() async throws {
    let outside = try place(try await plainMp3(), at: "../outside.mp4").standardizedFileURL
    try await video("Movies/Fetchr/a.mp4")
    let api = HostApi(python: FakePython(), library: library())

    for target in [
      outside.absoluteString, uri("../outside.mp4"), uri("Movies/../../outside.mp4"), "file:///etc/hosts",
      "https://x/a.mp4",
    ] {
      do {
        _ = try await api.thumbnail(uri: target, widthPx: 160, heightPx: 90)
        XCTFail("thumbnailed \(target)")
      } catch {
        XCTAssertEqual((error as? FetchrError)?.code, "invalid_url", target)
      }
    }
    XCTAssertEqual(thumbFiles(), [])
    let inside = try await api.thumbnail(uri: uri("Movies/Fetchr/a.mp4"), widthPx: 160, heightPx: 90)
    XCTAssertNotNil(inside)
  }
}
