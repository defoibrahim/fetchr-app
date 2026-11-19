import XCTest
@testable import Runner

final class FileActionsTests: XCTestCase {
  private var documents: URL!

  override func setUpWithError() throws {
    documents = FileManager.default.temporaryDirectory
      .appendingPathComponent("actions-\(UUID().uuidString)", isDirectory: true)
      .appendingPathComponent("Documents", isDirectory: true)
    try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: documents.deletingLastPathComponent())
  }

  @discardableResult
  private func file(_ rel: String) throws -> URL {
    let target = documents.appendingPathComponent(rel, isDirectory: false)
    try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("x".utf8).write(to: target)
    return target
  }

  private func uri(_ rel: String) -> String { documents.appendingPathComponent(rel, isDirectory: false).absoluteString }

  func testFolderUrlIsSharedDocumentsOfTheParentFolder() throws {
    let video = try file("Movies/Fetchr/Road trip： #1/a b.mp4")

    let url = try XCTUnwrap(FileActions.folderURL(of: video))

    let folder = video.deletingLastPathComponent().path
    XCTAssertEqual(url.scheme, "shareddocuments")
    XCTAssertTrue(url.absoluteString.hasPrefix("shareddocuments:///"), url.absoluteString)
    XCTAssertTrue(url.absoluteString.hasSuffix("/Road%20trip%EF%BC%9A%20%231/"), url.absoluteString)
    XCTAssertFalse(url.absoluteString.contains("a%20b.mp4"), "the folder, not the file")
    XCTAssertEqual(url.path(percentEncoded: false), folder + "/")
  }

  // `;` survives .urlPathAllowed and older URL parsers cut a path there; `?` and `%` must not start a query or an escape.
  func testFolderUrlEncodesSemicolonQuestionMarkAndPercent() throws {
    let video = try file("Movies/Fetchr/a;b?c%d/x.mp4")

    let url = try XCTUnwrap(FileActions.folderURL(of: video))

    XCTAssertTrue(url.absoluteString.hasSuffix("/a%3Bb%3Fc%25d/"), url.absoluteString)
    XCTAssertNil(url.query)
    XCTAssertEqual(url.path(percentEncoded: false), video.deletingLastPathComponent().path + "/")
  }

  func testFolderUrlIsNilWhenTheFolderIsGone() {
    let gone = documents.appendingPathComponent("Movies/Fetchr/Gone/a.mp4", isDirectory: false)
    XCTAssertNil(FileActions.folderURL(of: gone))
  }

  @MainActor
  func testOpenFolderOpensTheFolderUrl() async throws {
    let video = try file("Movies/Fetchr/a.mp4")
    var opened: [URL] = []

    try await FileActions.openFolder(of: video) { url in
      opened.append(url)
      return true
    }

    XCTAssertEqual(opened, [try XCTUnwrap(FileActions.folderURL(of: video))])
  }

  @MainActor
  func testOpenFolderThrowsNoFolderAppWhenNothingOpensIt() async throws {
    let video = try file("Movies/Fetchr/a.mp4")
    let gone = documents.appendingPathComponent("Movies/Gone/a.mp4", isDirectory: false)
    var calls = 0

    for (target, answer) in [(video, false), (gone, true)] {
      do {
        try await FileActions.openFolder(of: target) { _ in
          calls += 1
          return answer
        }
        XCTFail("opened \(target)")
      } catch {
        XCTAssertEqual((error as? FetchrError)?.code, "no_folder_app", target.path)
      }
    }
    XCTAssertEqual(calls, 1, "a folder that is gone is never handed to the opener")
  }

  private func api(opener: @escaping @MainActor (URL) async -> Bool = { _ in true }) -> HostApi {
    HostApi(
      python: FakePython(), library: Library(documents: documents, caches: documents.deletingLastPathComponent()),
      opener: opener)
  }

  private let outsideUris = [
    "file:///etc/hosts", "file:///private/var/mobile/x.mp4", "https://x/a.mp4", "",
  ]

  private func rejections() -> [String] {
    outsideUris + [uri("../outside.mp4"), documents.absoluteString + "Movies/%2e%2e/%2e%2e/outside.mp4"]
  }

  func testShareRejectsAUriOutsideDocuments() throws {
    try file("../outside.mp4")
    for target in rejections() {
      XCTAssertThrowsError(try api().share(uri: target, mimeType: "video/mp4"), target) { error in
        XCTAssertEqual((error as? FetchrError)?.code, "invalid_url", target)
      }
      XCTAssertThrowsError(try api().openFile(uri: target, mimeType: "video/mp4"), target) { error in
        XCTAssertEqual((error as? FetchrError)?.code, "invalid_url", target)
      }
    }
  }

  func testOpenFolderRejectsAUriOutsideDocuments() async throws {
    try file("../outside.mp4")
    var opened: [URL] = []
    let api = api { url in
      opened.append(url)
      return true
    }

    for target in rejections() {
      do {
        try await api.openFolder(uri: target)
        XCTFail("opened \(target)")
      } catch {
        XCTAssertEqual((error as? FetchrError)?.code, "invalid_url", target)
      }
    }
    XCTAssertEqual(opened, [])

    let video = try file("Movies/Fetchr/Road trip/a b.mp4")
    try await api.openFolder(uri: uri("Movies/Fetchr/Road trip/a b.mp4"))
    let folder = try await MainActor.run { try XCTUnwrap(FileActions.folderURL(of: video)) }
    XCTAssertEqual(opened, [folder])
  }
}
