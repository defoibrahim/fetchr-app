import XCTest
@testable import Runner

final class ErrorClassifierTests: XCTestCase {
  private func classify(_ message: String?) -> (code: String, message: String) {
    ErrorClassifier.classify(BridgeError(hint: nil, message: message ?? ""))
  }

  private func assertClassified(
    _ result: (code: String, message: String), _ code: String, _ message: String,
    file: StaticString = #filePath, line: UInt = #line
  ) {
    XCTAssertEqual(result.code, code, file: file, line: line)
    XCTAssertEqual(result.message, message, file: file, line: line)
  }

  func testDiskFullIsNoStorage() {
    assertClassified(
      classify("ERROR: unable to write data: [Errno 28] No space left on device"),
      "no_storage", "unable to write data: [Errno 28] No space left on device")
  }

  func testSecurityExceptionIsNoStorageWithFriendlyMessage() {
    assertClassified(
      ErrorClassifier.classify(BridgeError(hint: "no_storage", message: "denied")),
      "no_storage", "Couldn't save the file. Free up space or allow storage access, then retry.")
  }

  func testEnospcIsNoStorage() {
    XCTAssertEqual("no_storage", classify("ERROR: write failed (ENOSPC)").code)
  }

  func testUrlopenErrorIsNetwork() {
    assertClassified(
      classify("ERROR: [generic] Unable to download webpage: <urlopen error [Errno 111] Connection refused>"),
      "network", "[generic] Unable to download webpage: <urlopen error [Errno 111] Connection refused>")
  }

  func testNameResolutionFailureIsNetwork() {
    XCTAssertEqual(
      "network", classify("ERROR: unable to download video data: Temporary failure in name resolution").code)
  }

  func testTimeoutAndResetAndUnreachableAreNetwork() {
    XCTAssertEqual("network", classify("ERROR: read timed out").code)
    XCTAssertEqual("network", classify("ERROR: Connection reset by peer").code)
    XCTAssertEqual("network", classify("ERROR: [Errno 101] Network is unreachable").code)
    XCTAssertEqual("network", classify("ERROR: [Errno 110] Connection timed out").code)
  }

  func testErrnoMatchesWholeNumberOnly() {
    XCTAssertEqual("unknown", classify("ERROR: [Errno 1101] something odd").code)
  }

  func testNetworkExceptionTypesAreNetworkWithFriendlyMessage() {
    let expected = "No internet connection. Check your connection and try again."
    assertClassified(ErrorClassifier.classify(BridgeError(hint: "network", message: "youtube.com")), "network", expected)
    assertClassified(ErrorClassifier.classify(BridgeError(hint: "network", message: "timeout")), "network", expected)
  }

  func testUnsupportedUrl() {
    assertClassified(
      classify("ERROR: Unsupported URL: https://example.com/foo"),
      "unsupported_site", "Unsupported URL: https://example.com/foo")
  }

  func testPrivateVideoVariants() {
    XCTAssertEqual(
      "private_video", classify("ERROR: [youtube] abc: Private video. Sign in if you've been granted access").code)
    XCTAssertEqual("private_video", classify("ERROR: [youtube] abc: Sign in to confirm your age").code)
    XCTAssertEqual("private_video", classify("ERROR: [youtube] abc: This video is members-only content").code)
    XCTAssertEqual(
      "private_video", classify("ERROR: [youtube] abc: Join this channel to get access to members-only content").code)
  }

  func testUnavailableVariants() {
    assertClassified(classify("ERROR: [youtube] abc: Video unavailable"), "unavailable", "[youtube] abc: Video unavailable")
    XCTAssertEqual("unavailable", classify("ERROR: [youtube] abc: This video is unavailable").code)
    XCTAssertEqual("unavailable", classify("ERROR: [vimeo] 1: This video has been removed").code)
    XCTAssertEqual(
      "unavailable", classify("ERROR: [youtube] abc: The uploader has not made this video available in your country").code)
    XCTAssertEqual("unavailable", classify("ERROR: [youtube] abc: This video is not available in your country").code)
    XCTAssertEqual("unavailable", classify("ERROR: Unable to download: HTTP Error 404: Not Found").code)
  }

  func testUnknownPassesLastErrorLineThrough() {
    assertClassified(
      classify("WARNING: first\nERROR: first failure\nWARNING: retrying\nERROR: something odd happened\n"),
      "unknown", "something odd happened")
  }

  func testUnknownWithoutErrorLineUsesLastNonBlankLine() {
    assertClassified(classify("Traceback\n  boom\nValueError: bad thing\n\n"), "unknown", "ValueError: bad thing")
  }

  func testUnknownWithoutMessageIsFriendly() {
    assertClassified(
      classify(nil), "unknown", "Something went wrong. If it keeps happening, update yt-dlp in Settings.")
  }

  func testChecksRunInContractOrder() {
    XCTAssertEqual("no_storage", classify("ERROR: urlopen error: [Errno 28] No space left on device").code)
    XCTAssertEqual("network", classify("ERROR: urlopen error while fetching Unsupported URL page").code)
    XCTAssertEqual("unsupported_site", classify("ERROR: Unsupported URL: https://example.com/private video").code)
    XCTAssertEqual("private_video", classify("ERROR: Private video, Video unavailable").code)
  }

  func testWarningsAreIgnoredWhenAnErrorLineExists() {
    XCTAssertEqual(
      "unavailable",
      classify("WARNING: Unable to download webpage: timed out. Retrying\nERROR: [youtube] abc: Video unavailable").code)
  }

  func testPermissionDeniedErrnoIsPermissionDenied() {
    assertClassified(
      classify("ERROR: [Errno 13] Permission denied: '/storage/emulated/0/Movies/Fetchr'"),
      "permission_denied", "[Errno 13] Permission denied: '/storage/emulated/0/Movies/Fetchr'")
  }

  func testEaccesIsPermissionDenied() {
    XCTAssertEqual("permission_denied", classify("ERROR: unable to open for writing: EACCES").code)
    XCTAssertEqual("permission_denied", classify("open failed: EACCES (Permission denied)").code)
  }

  func testPermissionDeniedHasAFriendlyFallbackMessage() {
    assertClassified(
      classify("Permission denied"), "permission_denied",
      "Fetchr can't save files. Allow storage access in the app settings, then retry.")
  }

  func testACodedPermissionErrorPassesThrough() {
    let error = FetchrError(code: "permission_denied", message: ErrorClassifier.permissionDeniedMessage, details: nil)
    assertClassified(ErrorClassifier.classify(error), "permission_denied", ErrorClassifier.permissionDeniedMessage)
  }

  func testNoSpaceAndNetworkStillWinOverPermissionDenied() {
    XCTAssertEqual("no_storage", classify("ERROR: [Errno 28] No space left on device, Permission denied").code)
    XCTAssertEqual("network", classify("ERROR: <urlopen error [Errno 13] Permission denied>").code)
  }

  // Codes from Android's table that no text rule covers still pass through when Python names them.
  func testBridgeHintFromTheCodeTablePassesThrough() {
    let busy = ErrorClassifier.classify(BridgeError(hint: "busy", message: "yt-dlp is updating"))
    XCTAssertEqual(busy.code, "busy")
    XCTAssertEqual(busy.message, "yt-dlp is updating")
    XCTAssertEqual(ErrorClassifier.classify(BridgeError(hint: "made_up", message: "x")).code, "unknown")
  }

  func testFetchrErrorKeepsItsCode() {
    assertClassified(
      ErrorClassifier.classify(FetchrError(code: "invalid_url", message: "Not a web link", details: nil)),
      "invalid_url", "Not a web link")
  }

  func testDarwinNameResolutionFailureIsNetwork() {
    XCTAssertEqual(
      "network",
      classify(
        "ERROR: [generic] Unable to download webpage: <urlopen error [Errno 8] nodename nor servname provided, or not known>"
      ).code)
    XCTAssertEqual("network", classify("nodename nor servname provided, or not known").code)
  }

  func testDarwinErrnosAreNetwork() {
    XCTAssertEqual("network", classify("[Errno 54] Connection reset by peer").code)
    XCTAssertEqual("network", classify("[Errno 60] Operation timed out").code)
    XCTAssertEqual("network", classify("[Errno 65] No route to host").code)
    XCTAssertEqual("network", classify("[Errno 50] Network is down").code)
    XCTAssertEqual("network", classify("[Errno 61] Connection refused").code)
  }

  func testCodedErrorWithAMessagePassesThrough() {
    assertClassified(ErrorClassifier.classify(FetchrError(code: "busy", message: "x", details: nil)), "busy", "x")
  }

  func testCodedErrorWithoutAMessageGetsTheUnknownMessage() {
    assertClassified(
      ErrorClassifier.classify(FetchrError(code: "busy", message: nil, details: nil)), "busy",
      "Something went wrong. If it keeps happening, update yt-dlp in Settings.")
  }

  // A file error from saving must not show the user an NSError description with the container's absolute path.
  func testFileErrorsAreClassifiedWithoutTheirPath() {
    let path = "/var/mobile/Containers/Data/Application/X/Documents/Movies/Fetchr/a.mp4"
    let full = ErrorClassifier.classify(CocoaError(.fileWriteOutOfSpace, userInfo: [NSFilePathErrorKey: path]))
    XCTAssertEqual(full.code, "no_storage")
    let denied = ErrorClassifier.classify(CocoaError(.fileWriteNoPermission, userInfo: [NSFilePathErrorKey: path]))
    XCTAssertEqual(denied.code, "permission_denied")
    let posix = ErrorClassifier.classify(NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC)))
    XCTAssertEqual(posix.code, "no_storage")
    let other = ErrorClassifier.classify(CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: path]))
    XCTAssertEqual(other.code, "unknown")
    for result in [full, denied, posix, other] { XCTAssertFalse(result.message.contains("/var/"), result.message) }
  }

  func testAnyOtherErrorIsClassifiedFromItsDescription() {
    struct Plain: Error, CustomStringConvertible { var description: String { "ERROR: Unsupported URL: x" } }
    assertClassified(ErrorClassifier.classify(Plain()), "unsupported_site", "Unsupported URL: x")
  }

  func testMapErrorsClassifiesUncodedErrors() async {
    do {
      _ = try await mapErrors { () async throws -> Int in throw BridgeError(hint: nil, message: "ERROR: Video unavailable") }
      XCTFail("expected a failure")
    } catch {
      XCTAssertEqual((error as? FetchrError)?.code, "unavailable")
      XCTAssertEqual((error as? FetchrError)?.message, "Video unavailable")
    }
  }
}
