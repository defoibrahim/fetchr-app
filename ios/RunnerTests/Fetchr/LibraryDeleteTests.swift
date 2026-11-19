import XCTest
@testable import Runner

final class LibraryDeleteTests: XCTestCase {
  private var root: URL!
  private var documents: URL { root.appendingPathComponent("Documents") }
  private var caches: URL { root.appendingPathComponent("Caches") }
  private var storeURL: URL { root.appendingPathComponent("Application Support/downloads.json") }
  private let fake = FakeDownloads()
  private var repo: DownloadRepository?

  override func setUpWithError() throws {
    root = FileManager.default.temporaryDirectory.appendingPathComponent("libdelete-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
  }

  override func tearDown() async throws {
    await repo?.waitUntilIdle()
    repo = nil
    try? FileManager.default.removeItem(at: root)
  }

  private func library() -> Library { Library(documents: documents, caches: caches) }

  private func exists(_ rel: String) -> Bool {
    FileManager.default.fileExists(atPath: documents.appendingPathComponent(rel).path)
  }

  private func uri(_ rel: String) -> String { documents.appendingPathComponent(rel, isDirectory: false).absoluteString }

  @discardableResult
  private func write(_ rel: String) throws -> URL {
    let target = documents.appendingPathComponent(rel)
    try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("x".utf8).write(to: target)
    return target
  }

  // Completed downloads through the real repository, saved by its own save path, persisted to a real store.
  private func completed(_ requests: [DownloadRequest], store: TaskStore) async throws -> (DownloadRepository, [DownloadTask]) {
    let repo = DownloadRepository(python: fake, documents: documents, cachesDir: caches, store: store)
    fake.repository = repo
    self.repo = repo
    fake.script = { run, _ in try FakeDownloads.write("a.mp4", in: run) }
    for request in requests {
      _ = await repo.enqueue([request])
      _ = try await waitFor(repo) { $0.allSatisfy { $0.status == .completed } }
    }
    await repo.waitUntilIdle()
    return (repo, await repo.tasks)
  }

  func testDeleteRemovesTheFile() throws {
    try write("Movies/Fetchr/a b.mp4")

    try library().delete(uri: uri("Movies/Fetchr/a b.mp4"))

    XCTAssertFalse(exists("Movies/Fetchr/a b.mp4"))
    XCTAssertTrue(exists("Movies/Fetchr"))
  }

  func testDeleteOfAFileAlreadyGoneSucceeds() async throws {
    try FileManager.default.createDirectory(
      at: documents.appendingPathComponent("Movies/Fetchr"), withIntermediateDirectories: true)

    try library().delete(uri: uri("Movies/Fetchr/gone.mp4"))
    try library().delete(uri: uri("Movies/Fetchr/Gone playlist/gone.mp4"))
    let api = HostApi(python: FakePython(), library: library())
    let deleted = try await api.deleteFromLibrary(uri: uri("Movies/Fetchr/gone.mp4"))

    XCTAssertTrue(deleted)
    XCTAssertTrue(exists("Movies/Fetchr"))
  }

  func testDeleteLastPlaylistFilePrunesFolderAndForgetsTheTask() async throws {
    let store = TaskStore(url: storeURL)
    let (repo, tasks) = try await completed(
      [downloadRequest(playlist: "Road trip"), downloadRequest("https://example.com/other")], store: store)
    let playlistTask = try XCTUnwrap(tasks.first { $0.request.playlistTitle == "Road trip" })
    let otherTask = try XCTUnwrap(tasks.first { $0.request.playlistTitle == nil })
    XCTAssertTrue(exists("Movies/Fetchr/Road trip/a.mp4"))
    let listed = await library().list(folder: "Fetchr")
    let item = try XCTUnwrap(listed.first { $0.relativePath == "Movies/Fetchr/Road trip/" })
    XCTAssertEqual(item.uri, playlistTask.savedUri)

    let published = Recorded<[String]>()
    let snapshots = await repo.snapshots
    let watcher = Task {
      for await list in snapshots { published.set(list.map(\.id)) }
    }
    defer { watcher.cancel() }
    let api = HostApi(python: fake, downloads: repo, library: library())
    let deleted = try await api.deleteFromLibrary(uri: item.uri)

    XCTAssertTrue(deleted)
    XCTAssertFalse(exists("Movies/Fetchr/Road trip/a.mp4"))
    XCTAssertFalse(exists("Movies/Fetchr/Road trip"))
    XCTAssertTrue(exists("Movies/Fetchr"), "the user's folder stays")
    XCTAssertTrue(exists("Movies/Fetchr/a.mp4"), "the other download's file stays")
    let left = await repo.tasks.map(\.id)
    XCTAssertEqual(left, [otherTask.id])
    let deadline = Date().addingTimeInterval(5)
    while published.value != [otherTask.id], Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
    XCTAssertEqual(published.value, [otherTask.id], "Downloads and Home's Recent get the list without it")
    store.waitForPendingWrites()
    XCTAssertEqual(TaskStore(url: storeURL).load().map(\.task.id), [otherTask.id])
  }

  func testDeleteKeepsANonEmptyPlaylistFolder() throws {
    try write("Movies/Fetchr/Road trip/a.mp4")
    try write("Movies/Fetchr/Road trip/b.mp4")

    try library().delete(uri: uri("Movies/Fetchr/Road trip/a.mp4"))

    XCTAssertFalse(exists("Movies/Fetchr/Road trip/a.mp4"))
    XCTAssertTrue(exists("Movies/Fetchr/Road trip/b.mp4"))
  }

  func testDeleteOfTheLastFileOutsideAPlaylistKeepsTheUserFolder() throws {
    try write("Music/Fetchr/song.mp3")

    try library().delete(uri: uri("Music/Fetchr/song.mp3"))

    XCTAssertFalse(exists("Music/Fetchr/song.mp3"))
    XCTAssertTrue(exists("Music/Fetchr"))
  }

  // A folder uri would otherwise take everything in it.
  func testDeleteRefusesAFolderAndAnythingOutsideDocuments() async throws {
    try write("Movies/Fetchr/Road trip/a.mp4")
    let outside = root.appendingPathComponent("outside.mp4")
    try Data("x".utf8).write(to: outside)
    let api = HostApi(python: FakePython(), library: library())

    for target in [
      uri("Movies/Fetchr/Road trip"), documents.appendingPathComponent("Movies", isDirectory: true).absoluteString,
      outside.absoluteString, uri("Movies/../../outside.mp4"),
    ] {
      do {
        _ = try await api.deleteFromLibrary(uri: target)
        XCTFail("deleted \(target)")
      } catch {
        XCTAssertEqual((error as? FetchrError)?.code, "invalid_url", target)
      }
    }
    XCTAssertTrue(exists("Movies/Fetchr/Road trip/a.mp4"))
    XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
  }

  // Documents is also the user's own space in the Files app: only what Fetchr saves can be deleted from the library.
  func testDeleteRefusesAFileOutsideTheMediaFolders() async throws {
    try write("notes.txt")
    try write("Other/a.mp4")
    try write("Movies/Fetchr/a.mp4")
    let api = HostApi(python: FakePython(), library: library())

    for rel in ["notes.txt", "Other/a.mp4", "movies.mp4"] {
      do {
        _ = try await api.deleteFromLibrary(uri: uri(rel))
        XCTFail("deleted \(rel)")
      } catch {
        XCTAssertEqual((error as? FetchrError)?.code, "invalid_url", rel)
      }
    }
    XCTAssertTrue(exists("notes.txt"))
    XCTAssertTrue(exists("Other/a.mp4"))
    for rel in ["Movies/Fetchr/a.mp4", "Music/Fetchr/gone.mp3", "Pictures/Fetchr/gone.jpg"] {
      try library().delete(uri: uri(rel))
    }
    XCTAssertFalse(exists("Movies/Fetchr/a.mp4"))
  }

  // Nothing deleted, nothing forgotten: the error reaches Dart classified.
  func testDeleteThatFailsKeepsTheTaskAndThrowsAClassifiedError() async throws {
    let store = TaskStore(url: storeURL)
    let (repo, tasks) = try await completed([downloadRequest(playlist: "Road trip")], store: store)
    let task = try firstOf(tasks)
    let folder = documents.appendingPathComponent("Movies/Fetchr/Road trip")
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) }
    let api = HostApi(python: fake, downloads: repo, library: library())

    do {
      _ = try await api.deleteFromLibrary(uri: try XCTUnwrap(task.savedUri))
      XCTFail("deleted a file in a read-only folder")
    } catch let error as FetchrError {
      XCTAssertEqual(error.code, "permission_denied")
      XCTAssertFalse((error.message ?? "").contains(root.path), "no path in the message")
    }
    XCTAssertTrue(exists("Movies/Fetchr/Road trip/a.mp4"))
    let left = await repo.tasks.map(\.id)
    XCTAssertEqual(left, [task.id])
  }

  func testForgetSavedDropsOnlyCompletedTasksOfThatFile() async throws {
    let store = TaskStore(url: storeURL)
    let (repo, tasks) = try await completed(
      [downloadRequest(playlist: "Road trip"), downloadRequest("https://example.com/other")], store: store)
    let kept = try XCTUnwrap(tasks.first { $0.request.playlistTitle == nil })

    await repo.forgetSaved(relativeFile: "Movies/Fetchr/Road trip/a.mp4")
    await repo.forgetSaved(relativeFile: "Movies/Fetchr/nothing.mp4")

    let left = await repo.tasks.map(\.id)
    XCTAssertEqual(left, [kept.id])
    store.waitForPendingWrites()
    XCTAssertEqual(TaskStore(url: storeURL).load().map(\.task.id), [kept.id])
  }
}
