import XCTest
@testable import Runner

// A video on the phone turned into an MP3: the convert boundary, the staged copy, and the picked copy's life.
final class LocalVideoTests: XCTestCase {
  private var root: URL!
  private var documents: URL { root.appendingPathComponent("Documents", isDirectory: true) }
  private var caches: URL { root.appendingPathComponent("Caches", isDirectory: true) }
  private var picked: URL { root.appendingPathComponent("Application Support/picked", isDirectory: true) }
  private var outside: URL { root.appendingPathComponent("outside", isDirectory: true) }
  private var storeURL: URL { root.appendingPathComponent("Application Support/downloads.json") }
  private let fake = FakeDownloads()
  private let gates = RunGates()
  private var repo: DownloadRepository!
  private var store: TaskStore?

  override func setUpWithError() throws {
    root = FileManager.default.temporaryDirectory.appendingPathComponent("local-\(UUID().uuidString)")
    for dir in [documents, caches, picked, outside] {
      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
  }

  override func tearDown() async throws {
    gates.releaseAll()
    await repo?.waitUntilIdle()
    repo = nil
    try? FileManager.default.removeItem(at: root)
  }

  private func makeRepository(store: Bool = false) -> DownloadRepository {
    self.store = store ? TaskStore(url: storeURL) : nil
    let repository = DownloadRepository(
      python: fake, documents: documents, cachesDir: caches, store: self.store, pickedDir: picked)
    fake.repository = repository
    repo = repository
    return repository
  }

  private func api(_ repository: DownloadRepository? = nil) -> HostApi {
    HostApi(
      python: fake, downloads: repository, cacheDir: caches,
      library: Library(documents: documents, caches: caches), pickedDir: picked)
  }

  private func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

  @discardableResult
  private func file(_ url: URL, _ text: String = "video") throws -> URL {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url)
    return url
  }

  // A copy the picker made: picked/<uuid>/<name>.<ext>.
  private func pickedCopy(_ name: String = "Clip.mov") throws -> URL {
    try file(picked.appendingPathComponent("\(UUID().uuidString)/\(name)"))
  }

  private func mp3(_ source: URL, title: String = "Clip") -> DownloadRequest {
    DownloadRequest(url: source.absoluteString, title: title, quality: .mp3, folder: "Fetchr", useAria2c: false)
  }

  private func eventually(
    timeout: TimeInterval = 5, file: StaticString = #filePath, line: UInt = #line, _ condition: () async -> Bool
  ) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while !(await condition()) {
      if Date() > deadline {
        XCTFail("timed out", file: file, line: line)
        throw CancellationError()
      }
      try await Task.sleep(nanoseconds: 10_000_000)
    }
  }

  // yt-dlp's part: finds the staged copy where -o points, converts it to <stem>.mp3 and deletes the copy. A run
  // blocks on its gate first; a cancelled one throws as Python's would.
  private func convertingScript(block: Bool = true) {
    fake.script = { [gates] run, fake in
      let staged = try XCTUnwrap(URL(string: run.url))
      XCTAssertEqual(staged.deletingLastPathComponent().standardizedFileURL.path, run.outDir.standardizedFileURL.path)
      guard FileManager.default.fileExists(atPath: staged.path) else { throw FakeCancelled() }
      if block { await gates.wait(run.task) }
      if fake.isCancelled(run.task) { throw FakeCancelled() }
      try FakeDownloads.write(staged.deletingPathExtension().lastPathComponent + ".mp3", in: run)
      try FileManager.default.removeItem(at: staged)
    }
  }

  func testIsLocalIsTheFileScheme() {
    XCTAssertTrue(LocalVideo.isLocal("file:///var/a.mov"))
    XCTAssertFalse(LocalVideo.isLocal("https://example.com/a.mov"))
    XCTAssertFalse(LocalVideo.isLocal("content://media/1"))
  }

  func testRequestTakesTheNameAndDuration() async throws {
    let source = picked.appendingPathComponent("u1/Clip one.mov")
    try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
    try await ffmpeg([
      "-y", "-f", "lavfi", "-i", "testsrc=duration=2:size=320x240:rate=30", "-f", "lavfi", "-i", "sine=duration=2",
      "-c:v", "mpeg4", "-c:a", "aac", "-shortest", source.path,
    ])
    let req = await LocalVideo.request(for: source, folder: "Mine")
    XCTAssertEqual(req.title, "Clip one")
    XCTAssertEqual(req.durationSeconds, 2)
    XCTAssertEqual(req.quality, .mp3)
    XCTAssertEqual(req.folder, "Mine")
    XCTAssertFalse(req.useAria2c)
    XCTAssertEqual(req.url, source.absoluteString)
  }

  func testRequestWithoutANameOrADurationFallsBack() async throws {
    let source = try file(picked.appendingPathComponent("u1/.mov"))
    let req = await LocalVideo.request(for: source, folder: "Fetchr")
    XCTAssertEqual(req.title, "video")
    XCTAssertNil(req.durationSeconds)
  }

  func testStageCopiesUnderTheOutputNameAndReusesAWholeCopy() throws {
    let source = try file(picked.appendingPathComponent("u1/My: clip.MOV"), "original")
    let dir = caches.appendingPathComponent("tasks/t1", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    // A copy a killed attempt left half-written.
    try file(dir.appendingPathComponent("My clip.mov.copying"), "half")

    let staged = try LocalVideo.stage(mp3(source, title: "My: clip"), into: dir)
    XCTAssertEqual(staged.lastPathComponent, "My clip.mov")
    XCTAssertEqual(try String(contentsOf: staged, encoding: .utf8), "original")
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path), ["My clip.mov"])
    XCTAssertTrue(exists(source), "the source is copied, never moved")

    try Data("whole".utf8).write(to: staged)
    let again = try LocalVideo.stage(mp3(source, title: "My: clip"), into: dir)
    XCTAssertEqual(again, staged)
    XCTAssertEqual(try String(contentsOf: again, encoding: .utf8), "whole", "a whole copy is reused")
  }

  func testStageNeverNamesAVideoMp3() throws {
    let source = try file(picked.appendingPathComponent("u1/clip"))
    let dir = caches.appendingPathComponent("tasks/t1", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    XCTAssertEqual(try LocalVideo.stage(mp3(source), into: dir).lastPathComponent, "Clip.mp4")
  }

  func testGoneSourceIsUnavailable() throws {
    let source = picked.appendingPathComponent("u1/Clip.mov")
    let dir = caches.appendingPathComponent("tasks/t1", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    XCTAssertThrowsError(try LocalVideo.stage(mp3(source), into: dir)) {
      XCTAssertEqual(($0 as? FetchrError)?.code, "unavailable")
      XCTAssertEqual(($0 as? FetchrError)?.message, "The video is gone")
    }
  }

  // The app container's path changes between installs; a stored source is found again under today's roots.
  func testSourceIsFoundAfterTheContainerMoved() throws {
    let old = "file:///private/var/mobile/Containers/Data/Application/0A1B2C3D-4E5F-6071-8293-A4B5C6D7E8F9"
    let pick = try XCTUnwrap(
      LocalVideo.resolve(
        old + "/Library/Application%20Support/picked/u1/Clip%20one.mov", documents: documents, picked: picked))
    XCTAssertEqual(pick.file.lastPathComponent, "Clip one.mov")
    XCTAssertTrue(pick.isPicked)
    XCTAssertEqual(
      pick.file.standardizedFileURL.path, picked.appendingPathComponent("u1/Clip one.mov").standardizedFileURL.path)

    let lib = try XCTUnwrap(
      LocalVideo.resolve(old + "/Documents/Movies/Fetchr/a.mp4", documents: documents, picked: picked))
    XCTAssertFalse(lib.isPicked)
    XCTAssertEqual(lib.file.lastPathComponent, "a.mp4")

    XCTAssertNil(LocalVideo.resolve(old + "/Documents/notes/a.mp4", documents: documents, picked: picked))
    XCTAssertNil(LocalVideo.resolve(old + "/Library/Preferences/x.plist", documents: documents, picked: picked))
    XCTAssertNil(
      LocalVideo.resolve(old + "/Library/Application%20Support/picked/../downloads.json", documents: documents, picked: picked))
  }

  func testConvertRejectsAUriOutsideLibraryAndPicked() async throws {
    let repository = makeRepository()
    let host = api(repository)
    let secret = try file(outside.appendingPathComponent("secret.mov"))
    let notes = try file(documents.appendingPathComponent("notes/a.mov"))
    try FileManager.default.createSymbolicLink(
      at: picked.appendingPathComponent("link.mov"), withDestinationURL: secret)
    let folder = picked.appendingPathComponent("u1", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let bad = [
      "https://example.com/a.mov", secret.absoluteString, notes.absoluteString,
      picked.appendingPathComponent("link.mov").absoluteString, "file:///etc/hosts",
      picked.absoluteString + "../downloads.json", folder.absoluteString, "-o x", "",
    ]
    for uri in bad {
      do {
        try await host.convertToMp3(uri: uri, folder: "Fetchr")
        XCTFail("accepted \(uri)")
      } catch {
        XCTAssertEqual((error as? FetchrError)?.code, "invalid_url", uri)
      }
    }
    do {
      try await host.convertToMp3(uri: picked.appendingPathComponent("u2/gone.mov").absoluteString, folder: "Fetchr")
      XCTFail("accepted a missing file")
    } catch {
      XCTAssertEqual((error as? FetchrError)?.code, "unavailable")
    }
    await repository.waitUntilIdle()
    let none = await repository.tasks
    XCTAssertTrue(none.isEmpty)

    convertingScript()
    let video = try pickedCopy("Holiday.mov")
    try await host.convertToMp3(uri: video.absoluteString, folder: "Mine")
    let tasks = try await waitFor(repository) { $0.count == 1 }
    let task = try firstOf(tasks)
    XCTAssertEqual(task.request.quality, .mp3)
    XCTAssertEqual(task.request.title, "Holiday")
    XCTAssertEqual(task.request.folder, "Mine")
    XCTAssertTrue(LocalVideo.isLocal(task.request.url))
  }

  func testConvertWithoutARepositoryIsUnknown() async throws {
    let video = try pickedCopy()
    do {
      try await api().convertToMp3(uri: video.absoluteString, folder: "Fetchr")
      XCTFail("accepted")
    } catch {
      XCTAssertEqual((error as? FetchrError)?.code, "unknown")
    }
  }

  func testPickedCopyLivesUntilTheTaskEnds() async throws {
    convertingScript()
    let repository = makeRepository()
    let video = try pickedCopy()
    let id = try firstOf(await repository.enqueue([mp3(video)]))
    try await eventually { fake.runs.count == 1 }

    await repository.pause(id)
    gates.release("\(id)#1")
    await repository.waitUntilIdle()
    XCTAssertTrue(exists(video), "a pause keeps the picked copy")

    await repository.resume(id)
    try await eventually { fake.runs.count == 2 }
    XCTAssertTrue(exists(video))
    gates.release("\(id)#2")
    let done = try await waitFor(repository) { $0.first?.status == .completed }
    XCTAssertEqual(try firstOf(done).savedPath, "Music/Fetchr")
    XCTAssertTrue(exists(documents.appendingPathComponent("Music/Fetchr/Clip.mp3")))
    await repository.waitUntilIdle()
    XCTAssertFalse(exists(video), "completion deletes the picked copy")
    XCTAssertFalse(exists(video.deletingLastPathComponent()), "and its folder")
    XCTAssertTrue(exists(picked))

    // Two plain downloads hold both slots, so the convert below never starts.
    fake.script = { [gates] run, _ in await gates.wait(run.task) }
    let busy = await repository.enqueue([downloadRequest(), downloadRequest()])
    try await eventually { fake.runs.count == 4 }
    let second = try pickedCopy("Second.mov")
    let queued = try firstOf(await repository.enqueue([mp3(second, title: "Second")]))
    let waiting = await repository.task(queued)
    XCTAssertEqual(waiting?.status, .queued)
    _ = try await repository.remove(queued)
    XCTAssertFalse(exists(second), "removing the task deletes its picked copy")
    XCTAssertEqual(fake.runs.count, 4)
    for key in busy { gates.release("\(key)#1") }
  }

  func testCancelAndFailureKeepThePickedCopyForARetry() async throws {
    convertingScript()
    let repository = makeRepository()
    let video = try pickedCopy()
    let id = try firstOf(await repository.enqueue([mp3(video)]))
    try await eventually { fake.runs.count == 1 }
    await repository.cancel(id)
    gates.release("\(id)#1")
    await repository.waitUntilIdle()
    XCTAssertTrue(exists(video), "a canceled task can be retried")

    fake.script = { _, _ in throw BridgeError(hint: nil, message: "ERROR: boom") }
    await repository.retry(id)
    _ = try await waitFor(repository) { $0.first?.status == .failed }
    await repository.waitUntilIdle()
    XCTAssertTrue(exists(video), "a failed task can be retried")
  }

  // Review Focus 3: a retry after a restart still finds the picked copy, and a copy no task names is deleted.
  func testRetryAfterARestartFindsThePickedCopy() async throws {
    fake.script = { _, _ in throw BridgeError(hint: nil, message: "ERROR: boom") }
    let first = makeRepository(store: true)
    let video = try pickedCopy()
    let stray = try pickedCopy("Stray.mov")
    let id = try firstOf(await first.enqueue([mp3(video)]))
    _ = try await waitFor(first) { $0.first?.status == .failed }
    await first.waitUntilIdle()
    store?.waitForPendingWrites()
    repo = nil

    convertingScript(block: false)
    let second = makeRepository(store: true)
    await second.waitUntilIdle()
    try await eventually { !exists(stray) }
    XCTAssertTrue(exists(video))
    await second.retry(id)
    _ = try await waitFor(second) { $0.first?.status == .completed }
    await second.waitUntilIdle()
    XCTAssertFalse(exists(video))
  }

  func testAPickedCopySharedByTwoTasksStaysUntilBothEnd() async throws {
    convertingScript()
    let repository = makeRepository()
    let video = try pickedCopy()
    let ids = await repository.enqueue([mp3(video), mp3(video)])
    try await eventually { fake.runs.count == 2 }
    gates.release("\(ids[0])#1")
    _ = try await waitFor(repository) { $0.first { $0.id == ids[0] }?.status == .completed }
    XCTAssertTrue(exists(video), "the other task still converts it")
    gates.release("\(ids[1])#1")
    _ = try await waitFor(repository) { $0.allSatisfy { $0.status == .completed } }
    await repository.waitUntilIdle()
    XCTAssertFalse(exists(video))
  }

  func testLibrarySourceIsNeverDeleted() async throws {
    convertingScript(block: false)
    let repository = makeRepository()
    let host = api(repository)
    let video = try file(documents.appendingPathComponent("Movies/Fetchr/Trip.mp4"))
    try await host.convertToMp3(uri: video.absoluteString, folder: "Fetchr")
    let done = try await waitFor(repository) { $0.first?.status == .completed }
    await repository.waitUntilIdle()
    XCTAssertTrue(exists(video), "completing keeps a library source")
    XCTAssertTrue(exists(documents.appendingPathComponent("Music/Fetchr/Trip.mp3")))

    fake.script = { [gates] run, _ in await gates.wait(run.task) }
    _ = await repository.enqueue([downloadRequest(), downloadRequest()])
    try await eventually { fake.runs.count == 3 }
    let queued = try firstOf(await repository.enqueue([mp3(video, title: "Trip")]))
    _ = try await repository.remove(queued)
    _ = try await repository.remove(try firstOf(done).id)
    XCTAssertTrue(exists(video), "removing keeps a library source")
    gates.releaseAll()
  }

  // The real bridge, offline: yt-dlp reads the staged copy through a file URL and ffmpeg converts it.
  func testConvertsALocalVideoToMp3() async throws {
    // Built first, as at launch: its cleanup deletes the picked copies no task names.
    let repository = DownloadRepository(
      python: PythonRuntime.shared, documents: documents, cachesDir: caches, pickedDir: picked)
    repo = repository
    let source = picked.appendingPathComponent("u1/Clip one.mov")
    try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
    try await ffmpeg([
      "-y", "-f", "lavfi", "-i", "testsrc=duration=2:size=320x240:rate=30", "-f", "lavfi", "-i", "sine=duration=2",
      "-c:v", "mpeg4", "-c:a", "aac", "-shortest", source.path,
    ])
    let host = HostApi(
      python: PythonRuntime.shared, downloads: repository, cacheDir: caches,
      library: Library(documents: documents, caches: caches), pickedDir: picked)
    do {
      try await host.convertToMp3(uri: source.absoluteString, folder: "Fetchr")
    } catch let error as FetchrError {
      return XCTFail("\(error.code): \(error.message ?? "")")
    }
    let tasks = try await waitFor(repository, timeout: 120) { $0.first.map { !$0.isLive } ?? false }
    let task = try firstOf(tasks)
    XCTAssertEqual(task.status, .completed, "\(task.errorCode ?? "") \(task.errorMessage ?? "")")
    await repository.waitUntilIdle()

    let saved = documents.appendingPathComponent("Music/Fetchr/Clip one.mp3")
    XCTAssertTrue(exists(saved))
    let probe = try await PythonRuntime.shared.call(
      "debug_ffmpeg",
      [
        "probe": true, "task": "local",
        "argv": ["-v", "error", "-show_entries", "stream=codec_type,codec_name", "-of", "csv=p=0", saved.path],
      ])
    let out = try XCTUnwrap((probe as? [String: Any])?["out"] as? String)
    XCTAssertEqual(out.trimmingCharacters(in: .whitespacesAndNewlines), "mp3,audio")
    XCTAssertFalse(exists(source), "the picked copy is deleted")
    XCTAssertFalse(exists(caches.appendingPathComponent("tasks/\(task.id)")))
  }

  private func ffmpeg(_ argv: [String]) async throws {
    let reply = try await PythonRuntime.shared.call("debug_ffmpeg", ["probe": false, "argv": argv, "task": "local"])
    let value = try XCTUnwrap(reply as? [String: Any], "\(reply)")
    XCTAssertEqual(value["rc"] as? Int, 0, value["out"] as? String ?? "")
  }
}
