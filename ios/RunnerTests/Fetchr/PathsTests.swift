import XCTest
@testable import Runner

final class PathsTests: XCTestCase {
  private var root: URL!
  private var documents: URL!
  private var outside: URL!

  override func setUpWithError() throws {
    root = FileManager.default.temporaryDirectory.appendingPathComponent("paths-\(UUID().uuidString)")
    documents = root.appendingPathComponent("Documents", isDirectory: true)
    outside = root.appendingPathComponent("outside", isDirectory: true)
    for dir in [documents!, outside!] {
      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: root)
  }

  // Documents' own file URL, without its trailing slash, so a test can append any raw text to it.
  private var docs: String {
    var text = documents.absoluteString
    if text.hasSuffix("/") { text.removeLast() }
    return text
  }

  private func assertInvalid(_ uri: String, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertThrowsError(try Paths.documentFile(fromUri: uri, documents: documents), uri, file: file, line: line) {
      XCTAssertEqual(($0 as? FetchrError)?.code, "invalid_url", uri, file: file, line: line)
    }
  }

  func testDocumentFileRejectsEverythingOutsideDocuments() throws {
    let secret = outside.appendingPathComponent("secret.mp4")
    try Data("x".utf8).write(to: secret)
    let fetchr = documents.appendingPathComponent("Movies/Fetchr", isDirectory: true)
    try FileManager.default.createDirectory(at: fetchr, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: fetchr.appendingPathComponent("link.mp4"), withDestinationURL: secret)
    try FileManager.default.createSymbolicLink(at: fetchr.appendingPathComponent("Evil"), withDestinationURL: outside)
    try FileManager.default.createSymbolicLink(
      at: fetchr.appendingPathComponent("dangling.mp4"), withDestinationURL: outside.appendingPathComponent("gone.mp4"))
    let sibling = root.appendingPathComponent("DocumentsEvil/x.mp4")

    for uri in [
      "file:///etc/hosts",
      "\(docs)/../x",
      "\(docs)/Movies/%2e%2e/%2e%2e/x",
      "\(docs)/Movies/%2E%2E/%2E%2E/outside/secret.mp4",
      "\(docs)/Movies/Fetchr/link.mp4",
      "\(docs)/Movies/Fetchr/Evil/secret.mp4",
      "\(docs)/Movies/Fetchr/dangling.mp4",
      sibling.absoluteString,
      secret.absoluteString,
      "\(docs)",
      "\(docs)/",
      "\(docs)/Movies/Fetchr/a.mp4?x=1",
      "\(docs)/Movies/Fetchr/a.mp4#x",
      "\(docs)/Movies/Fetchr/a%00.mp4",
      "file://other-host\(documents.path)/Movies/Fetchr/a.mp4",
      "https://x",
      "Movies/Fetchr/a.mp4",
      "",
    ] {
      assertInvalid(uri)
    }
  }

  func testDocumentFileDecodesAPathInsideDocuments() throws {
    let file = try Paths.documentFile(fromUri: "\(docs)/Movies/Fetchr/a%20b.mp4", documents: documents)
    XCTAssertEqual(file.path, documents.appendingPathComponent("Movies/Fetchr/a b.mp4").path)
    XCTAssertTrue(file.isFileURL)
  }

  // A file the list built its uri from, and one already deleted (with its folder): both are still inside.
  func testDocumentFileAcceptsTheListUriAndAFileAlreadyGone() throws {
    let rel = "Movies/Fetchr/Road trip/01 - é?#.mp4"
    let listed = documents.appendingPathComponent(rel, isDirectory: false)
    XCTAssertEqual(try Paths.documentFile(fromUri: listed.absoluteString, documents: documents).path, listed.path)
    XCTAssertEqual(try Paths.documentRelativePath(fromUri: listed.absoluteString, documents: documents), rel)

    try FileManager.default.createDirectory(at: listed.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("x".utf8).write(to: listed)
    XCTAssertEqual(try Paths.documentRelativePath(fromUri: listed.absoluteString, documents: documents), rel)
  }

  // A symlink that stays inside Documents is followed: the file it names is the one acted on.
  func testDocumentFileFollowsASymlinkThatStaysInside() throws {
    let real = documents.appendingPathComponent("Movies/Fetchr/real.mp4")
    try FileManager.default.createDirectory(at: real.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("x".utf8).write(to: real)
    try FileManager.default.createSymbolicLink(
      at: documents.appendingPathComponent("Movies/Fetchr/alias.mp4"), withDestinationURL: real)

    let rel = try Paths.documentRelativePath(fromUri: "\(docs)/Movies/Fetchr/alias.mp4", documents: documents)

    XCTAssertEqual(rel, "Movies/Fetchr/real.mp4")
  }
}
