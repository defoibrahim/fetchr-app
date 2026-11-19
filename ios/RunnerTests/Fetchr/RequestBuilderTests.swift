import XCTest
@testable import Runner

final class RequestBuilderTests: XCTestCase {
  private let url = "https://example.com/watch?v=abc&list=xyz"
  private let outDir = URL(fileURLWithPath: "/out")
  private let cacheDir = URL(fileURLWithPath: "/cache")
  private let template = "/out/%(title).150B [%(id)s].%(ext)s"
  private var common: [String] {
    ["--no-playlist", "--no-mtime", "--cache-dir", "/cache/yt-dlp", "-o", template, "-N", "4"]
  }
  private let videoFormat = ["-f", "bv*+ba/b"]
  private let mergeTail = ["--merge-output-format", "mp4"]
  private let allQualities: [Quality] = [.best, .p1080, .p720, .p480, .mp3, .cover]

  private func sort(_ res: String) -> [String] { ["-S", "\(res),vcodec:h264,acodec:aac"] }

  private func request(_ quality: Quality, link: String? = nil) -> DownloadRequest {
    DownloadRequest(
      url: link ?? url, title: "A title", thumbnail: nil, quality: quality, folder: "Fetchr", useAria2c: false)
  }

  private func command(_ quality: Quality) -> [String] {
    RequestBuilder.downloadArgv(request(quality), outDir: outDir, cacheDir: cacheDir)
  }

  private func output(of argv: [String]) -> String? {
    argv.firstIndex(of: "-o").map { argv[$0 + 1] }
  }

  private func assertInvalidUrl(_ candidate: String, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertThrowsError(try RequestBuilder.requireHttpUrl(candidate), "for \(candidate.debugDescription)", file: file, line: line) {
      let error = $0 as? FetchrError
      XCTAssertEqual(error?.code, "invalid_url", file: file, line: line)
      XCTAssertEqual(error?.message, "That is not a valid web link.", file: file, line: line)
    }
  }

  func testRequireHttpUrlAcceptsHttpAndHttps() throws {
    XCTAssertEqual("http://example.com/a", try RequestBuilder.requireHttpUrl("http://example.com/a"))
    XCTAssertEqual(url, try RequestBuilder.requireHttpUrl(url))
    XCTAssertEqual("HTTPS://Example.com/a", try RequestBuilder.requireHttpUrl("HTTPS://Example.com/a"))
    XCTAssertEqual("https://[::1]:8080/a", try RequestBuilder.requireHttpUrl("https://[::1]:8080/a"))
  }

  func testRequireHttpUrlTrimsSurroundingWhitespace() throws {
    XCTAssertEqual(url, try RequestBuilder.requireHttpUrl("  \(url)\n"))
    XCTAssertEqual("https://a.b/x", try RequestBuilder.requireHttpUrl("  https://a.b/x  "))
  }

  func testRequireHttpUrlRejectsEverythingElse() {
    let bad = [
      "",
      "   ",
      "example.com/watch?v=1",
      "ftp://example.com/a",
      "file:///etc/passwd",
      "content://media/external/video/1",
      "javascript:alert(1)",
      "https://",
      "http:///no-host",
      "http:example.com",
      "--exec https://example.com",
      "-J",
      "https://exa mple.com",
      "https://example.com/a\nb",
      "https://example.com/a\u{0}b",
      "-o x",
      "ftp://a.b",
      "https://a.b/x y",
      "https://a.b/\u{7}",
    ]
    for candidate in bad {
      assertInvalidUrl(candidate)
    }
  }

  func testRequireHttpUrlKeepsCharactersJavaUrlAccepts() throws {
    XCTAssertEqual("https://a.b/x|y", try RequestBuilder.requireHttpUrl("https://a.b/x|y"))
    XCTAssertEqual("https://a.b/x?q={1}^`", try RequestBuilder.requireHttpUrl("https://a.b/x?q={1}^`"))
  }

  func testInfoArgvIsAFlatDumpWithTheCacheDir() {
    XCTAssertEqual(
      ["--flat-playlist", "--cache-dir", "/c/yt-dlp"], RequestBuilder.infoArgv(cacheDir: URL(fileURLWithPath: "/c")))
  }

  func testShortSideCapIsTheOnlyCapTable() {
    XCTAssertEqual(1080, Quality.p1080.shortSideCap)
    XCTAssertEqual(720, Quality.p720.shortSideCap)
    XCTAssertEqual(480, Quality.p480.shortSideCap)
    XCTAssertNil(Quality.best.shortSideCap)
    XCTAssertNil(Quality.mp3.shortSideCap)
    XCTAssertNil(Quality.cover.shortSideCap)
  }

  func testSafeFolderKeepsPlainNames() {
    XCTAssertEqual("Fetchr", RequestBuilder.safeFolder("Fetchr"))
    XCTAssertEqual("My Videos", RequestBuilder.safeFolder("My Videos"))
    XCTAssertEqual("a.b", RequestBuilder.safeFolder("a.b"))
  }

  func testSafeFolderStripsReservedCharacters() {
    XCTAssertEqual("abcdefghij", RequestBuilder.safeFolder("a\\b/c:d*e?f\"g<h>i|j"))
    XCTAssertEqual("ab", RequestBuilder.safeFolder("a\u{0}\nb"))
  }

  func testSafeFolderStripsLeadingDots() {
    XCTAssertEqual("hidden", RequestBuilder.safeFolder("..hidden"))
    XCTAssertEqual("etc", RequestBuilder.safeFolder("../../etc"))
    XCTAssertEqual("x", RequestBuilder.safeFolder(". . x"))
  }

  func testSafeFolderTrimsWhitespace() {
    XCTAssertEqual("Clips", RequestBuilder.safeFolder("  Clips "))
  }

  func testSafeFolderBlankFallsBackToFetchr() {
    for blank in ["", "   ", ".", "...", "///", ".\\.", "*?", "\t"] {
      XCTAssertEqual("Fetchr", RequestBuilder.safeFolder(blank), "for '\(blank)'")
    }
  }

  func testSaveFolderIsTheUserFolderOutsideAPlaylist() {
    XCTAssertEqual("Fetchr", RequestBuilder.saveFolder(request(.best)))
    var escaping = request(.best)
    escaping.folder = "../"
    XCTAssertEqual("Fetchr", RequestBuilder.saveFolder(escaping))
  }

  func testSaveFolderPutsAPlaylistInASafeSubfolder() {
    func folderFor(_ title: String) -> String {
      var req = request(.mp3)
      req.playlistTitle = title
      return RequestBuilder.saveFolder(req)
    }

    XCTAssertEqual("Fetchr/Road trip", folderFor("Road trip"))
    XCTAssertEqual("Fetchr/ACDC Live", folderFor("AC/DC: Live"))
    XCTAssertEqual("Fetchr/etc", folderFor("../../etc"))
    XCTAssertEqual("Fetchr/" + String(repeating: "a", count: 150), folderFor(String(repeating: "a", count: 200)))
    for blank in ["", "  ", "..", "/|\\"] {
      XCTAssertEqual("Fetchr", folderFor(blank), "for '\(blank)'")
    }
  }

  func testDownloadBest() {
    XCTAssertEqual(common + videoFormat + sort("res") + mergeTail, command(.best))
  }

  func testDownloadP1080() {
    XCTAssertEqual(common + videoFormat + sort("res:1080") + mergeTail, command(.p1080))
  }

  func testDownloadP720() {
    XCTAssertEqual(common + videoFormat + sort("res:720") + mergeTail, command(.p720))
  }

  func testDownloadP480() {
    XCTAssertEqual(common + videoFormat + sort("res:480") + mergeTail, command(.p480))
  }

  func testDownloadCapsTheShortSideNotTheHeight() {
    for quality in [Quality.p1080, .p720, .p480] {
      let cmd = command(quality)
      XCTAssertFalse(cmd.contains { $0.contains("height") })
      let f = cmd.firstIndex(of: "-f")!
      XCTAssertEqual(videoFormat, Array(cmd[f..<f + 2]))
    }
  }

  func testDownloadMp3() {
    let cmd = command(.mp3)
    XCTAssertEqual(
      common + ["-f", "ba/b", "-x", "--audio-format", "mp3", "--audio-quality", "0"]
        + ["--postprocessor-args", "ExtractAudio+ffmpeg:-progress \"/out/ffmpeg.progress\""],
      cmd)
    XCTAssertFalse(cmd.contains("-S"))
    XCTAssertFalse(cmd.contains("--merge-output-format"))
  }

  func testDownloadCover() {
    let cmd = command(.cover)
    XCTAssertEqual(common + ["--skip-download", "--write-thumbnail", "--convert-thumbnails", "jpg"], cmd)
    XCTAssertFalse(cmd.contains("-f"))
    XCTAssertFalse(cmd.contains("-S"))
    XCTAssertFalse(cmd.contains("--merge-output-format"))
    XCTAssertFalse(cmd.contains("-x"))
  }

  func testConversionReportIsTheMp3ProgressFile() {
    XCTAssertEqual("ffmpeg.progress", RequestBuilder.conversionReport)
  }

  // Android's download_keepsUrlAsSingleFinalArgument: the URL goes to Python next to the argv, as for info.
  func testDownloadArgvHasNoUrl() {
    for quality in allQualities {
      let cmd = command(quality)
      XCTAssertFalse(cmd.contains { $0.contains("example.com") }, "\(quality)")
    }
  }

  func testDownloadWritesOnlyUnderOutDirAndIgnoresFolder() {
    var evil = request(.best)
    evil.folder = "../../evil"
    let cmd = RequestBuilder.downloadArgv(evil, outDir: outDir, cacheDir: cacheDir)
    XCTAssertFalse(cmd.contains { $0.contains("evil") })
    XCTAssertEqual(template, output(of: cmd))
  }

  func testDownloadNumbersPlaylistEntriesPaddedToThePlaylistWidth() {
    func outputFor(_ index: Int64?, _ count: Int64?) -> String? {
      var req = request(.best)
      req.playlistTitle = "P"
      req.playlistIndex = index
      req.playlistCount = count
      return output(of: RequestBuilder.downloadArgv(req, outDir: outDir, cacheDir: cacheDir))
    }
    func numbered(_ prefix: String) -> String { "/out/\(prefix) - %(title).150B [%(id)s].%(ext)s" }

    XCTAssertEqual(numbered("03"), outputFor(3, 9))
    XCTAssertEqual(numbered("07"), outputFor(7, 18))
    XCTAssertEqual(numbered("042"), outputFor(42, 150))
    XCTAssertEqual(numbered("05"), outputFor(5, nil))
    XCTAssertEqual(template, outputFor(nil, nil))
  }

  // downloadArgv never sees the URL; requireHttpUrl is the check every download goes through.
  func testDownloadRejectsNonHttpUrl() {
    for bad in ["", "file:///etc/passwd", "--exec x", "example.com"] {
      assertInvalidUrl(request(.best, link: bad).url)
    }
  }

  func testSafeFileNameDropsWhatAFileSystemOrTheTemplateWouldMisread() {
    XCTAssertEqual("My clip [x]", RequestBuilder.safeFileName("My clip [x]"))
    XCTAssertEqual("ab 100 done", RequestBuilder.safeFileName("a/b 100% done"))
    XCTAssertEqual("rm", RequestBuilder.safeFileName("--rm"))
    XCTAssertEqual("hidden", RequestBuilder.safeFileName("..hidden"))
    XCTAssertEqual("video", RequestBuilder.safeFileName("///"))
    XCTAssertEqual(150, RequestBuilder.safeFileName(String(repeating: "x", count: 300)).count)
  }

  // Android's convert_pointsYtDlpAtTheCopyAndSavesTheMp3BesideIt. The URL goes to Python next to the argv.
  func testConvertArgvMatchesAndroid() throws {
    let dir = URL(fileURLWithPath: "/caches/tasks/t1", isDirectory: true)
    let source = dir.appendingPathComponent("My clip [x] #1.mp4", isDirectory: false)
    let argv = RequestBuilder.convertArgv(source: source, cacheDir: cacheDir)
    XCTAssertEqual(
      [
        "--enable-file-urls", "--no-mtime", "--cache-dir", "/cache/yt-dlp",
        "-o", "/caches/tasks/t1/My clip [x] #1.%(ext)s",
        "-f", "ba/b", "-x", "--audio-format", "mp3", "--audio-quality", "0",
        "--postprocessor-args", "ExtractAudio+ffmpeg:-progress \"/caches/tasks/t1/ffmpeg.progress\"",
      ],
      argv)
    XCTAssertFalse(argv.contains { $0.hasPrefix("file:") })
    // Percent-encoded, so the space, brackets and # stay part of the path.
    let link = RequestBuilder.convertUrl(source: source)
    XCTAssertTrue(link.hasPrefix("file:///"), link)
    XCTAssertTrue(link.hasSuffix("/My%20clip%20%5Bx%5D%20%231.mp4"), link)
    XCTAssertEqual(source.path, try XCTUnwrap(URL(string: link)).path(percentEncoded: false))
  }
}
