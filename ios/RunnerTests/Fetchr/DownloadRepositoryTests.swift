import XCTest
@testable import Runner

// Stands in for Python's download handler: writes the run's files into outDir and emits events the way the
// real bridge does, through the repository's emit entry point.
final class FakeDownloads: PythonCalling, @unchecked Sendable {
  struct Run {
    // The run key, "<taskId>#<attempt>".
    let task: String
    let outDir: URL
    let argv: [String]
    let url: String

    var taskId: String { String(task.split(separator: "#").first ?? "") }
  }

  typealias Script = @Sendable (Run, FakeDownloads) async throws -> Void

  private let lock = NSLock()
  private var started: [Run] = []
  private var running = 0
  private var peak = 0
  private var cancelled: [String] = []
  var script: Script = { _, _ in }
  // How long a cancel takes to reach "Python", so a test can make it land late.
  var cancelDelay: UInt64 = 0
  weak var repository: DownloadRepository?

  var runs: [Run] { lock.withLock { started } }
  var peakRunning: Int { lock.withLock { peak } }
  var cancels: [String] { lock.withLock { cancelled } }

  func isCancelled(_ key: String) -> Bool { lock.withLock { cancelled.contains(key) } }

  func call(_ name: String, _ payload: [String: Any]) async throws -> Any {
    if name == "cancel" {
      let key = payload["task"] as! String
      if cancelDelay > 0 { try? await Task.sleep(nanoseconds: cancelDelay) }
      lock.withLock { cancelled.append(key) }
      return NSNull()
    }
    guard name == "download" else { return NSNull() }
    let run = Run(
      task: payload["task"] as! String, outDir: URL(fileURLWithPath: payload["outDir"] as! String),
      argv: payload["argv"] as! [String], url: payload["url"] as! String)
    lock.withLock {
      started.append(run)
      running += 1
      peak = max(peak, running)
    }
    defer { lock.withLock { running -= 1 } }
    try await script(run, self)
    let files = try FileManager.default.contentsOfDirectory(atPath: run.outDir.path).sorted()
    return ["files": files]
  }

  func emit(_ run: Run, _ event: [String: Any]) {
    let data = try! JSONSerialization.data(withJSONObject: event)
    repository?.receive(taskId: run.task, json: String(data: data, encoding: .utf8)!)
  }

  static func write(_ name: String, bytes: Int = 16, in run: Run) throws {
    try Data(repeating: 7, count: bytes).write(to: run.outDir.appendingPathComponent(name))
  }
}

// A one-shot gate a fake run waits on until the test opens it.
final class Gate: @unchecked Sendable {
  private let lock = NSLock()
  private var open = false
  private var waiting: [CheckedContinuation<Void, Never>] = []

  func wait() async {
    await withCheckedContinuation { continuation in
      let now = lock.withLock {
        if open { return true }
        waiting.append(continuation)
        return false
      }
      if now { continuation.resume() }
    }
  }

  func release() {
    let resumed = lock.withLock {
      open = true
      defer { waiting = [] }
      return waiting
    }
    resumed.forEach { $0.resume() }
  }
}

func downloadRequest(_ url: String = "https://example.com/v", quality: Quality = .best, playlist: String? = nil) -> DownloadRequest {
  DownloadRequest(
    url: url, title: "Clip", quality: quality, folder: "Fetchr", useAria2c: false, playlistTitle: playlist)
}

// Polls the repository until its list matches, so a test never depends on event timing.
func waitFor(
  _ repository: DownloadRepository, timeout: TimeInterval = 5, file: StaticString = #filePath, line: UInt = #line,
  _ predicate: ([DownloadTask]) -> Bool
) async throws -> [DownloadTask] {
  let deadline = Date().addingTimeInterval(timeout)
  while true {
    let tasks = await repository.tasks
    if predicate(tasks) { return tasks }
    if Date() > deadline {
      XCTFail("timed out; tasks: \(tasks.map { "\($0.status) \($0.stage) \($0.progress)" })", file: file, line: line)
      throw CancellationError()
    }
    try await Task.sleep(nanoseconds: 10_000_000)
  }
}

struct EmptyList: Error {}

func firstOf<T>(_ items: [T]) throws -> T {
  guard let first = items.first else { throw EmptyList() }
  return first
}

final class DownloadRepositoryTests: XCTestCase {
  private var root: URL!
  private var documents: URL { root.appendingPathComponent("Documents") }
  private var caches: URL { root.appendingPathComponent("Caches") }
  private let fake = FakeDownloads()

  override func setUpWithError() throws {
    root = FileManager.default.temporaryDirectory.appendingPathComponent("repo-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: root)
  }

  private func repository() -> DownloadRepository {
    let repository = DownloadRepository(python: fake, documents: documents, cachesDir: caches)
    fake.repository = repository
    return repository
  }

  func testStartupRemovesLeftoverTaskDirs() async throws {
    let old = caches.appendingPathComponent("tasks/old")
    try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
    try Data("x".utf8).write(to: old.appendingPathComponent("v.mp4.part"))
    let repository = repository()
    let deadline = Date().addingTimeInterval(2)
    while FileManager.default.fileExists(atPath: old.path), Date() < deadline {
      try await Task.sleep(nanoseconds: 20_000_000)
    }
    XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
    _ = repository
  }

  private func allDone(_ tasks: [DownloadTask]) -> Bool {
    !tasks.isEmpty && tasks.allSatisfy { $0.status == .completed || $0.status == .failed }
  }

  func testEnqueueQueuesThenRunsAtMostTwo() async throws {
    let gate = Gate()
    fake.script = { run, _ in
      await gate.wait()
      try FakeDownloads.write("\(run.task).mp4", in: run)
    }
    let repository = repository()
    let ids = await repository.enqueue([downloadRequest(), downloadRequest(), downloadRequest()])

    let tasks = try await waitFor(repository) { tasks in tasks.filter { $0.status == .running }.count == 2 }
    XCTAssertEqual(tasks.filter { $0.status == .queued }.map(\.id), [ids[2]], "the third waits, FIFO")
    XCTAssertEqual(Set(tasks.map(\.id)), Set(ids))
    XCTAssertEqual(Set(tasks.map(\.createdAtMs)).count, 1)
    gate.release()

    let done = try await waitFor(repository, allDone)
    XCTAssertEqual(done.map(\.status), [.completed, .completed, .completed])
    XCTAssertEqual(fake.peakRunning, 2)
    let order = fake.runs.map(\.taskId)
    XCTAssertEqual(fake.runs.map(\.task), order.map { "\($0)#1" })
    XCTAssertEqual(Set(order.prefix(2)), Set(ids.prefix(2)))
    XCTAssertEqual(order.last, ids[2])
  }

  func testNewTasksStartQueuedAtTheHead() async throws {
    let gate = Gate()
    fake.script = { _, _ in await gate.wait() }
    let repository = repository()
    let first = await repository.enqueue([downloadRequest(), downloadRequest()])
    let second = await repository.enqueue([downloadRequest()])
    let tasks = await repository.tasks
    XCTAssertEqual(tasks.map(\.id), second + first)
    let added = try XCTUnwrap(tasks.first)
    XCTAssertEqual(added.status, .queued)
    XCTAssertEqual(added.stage, .preparing)
    XCTAssertEqual(added.progress, -1)
    XCTAssertEqual(added.etaSeconds, -1)
    gate.release()
    _ = try await waitFor(repository, allDone)
  }

  func testCompletedTaskHasRelativePathAndFileUri() async throws {
    fake.script = { run, _ in try FakeDownloads.write("a.mp4", in: run) }
    let repository = repository()
    _ = await repository.enqueue([downloadRequest(playlist: "Road trip")])

    let task = try firstOf(try await waitFor(repository, allDone))
    XCTAssertEqual(task.status, .completed)
    XCTAssertEqual(task.progress, 1)
    XCTAssertEqual(task.savedPath, "Movies/Fetchr/Road trip")
    XCTAssertNotNil(task.finishedAtMs)
    let uri = try XCTUnwrap(task.savedUri)
    XCTAssertTrue(uri.hasPrefix("file://"), uri)
    let saved = try XCTUnwrap(URL(string: uri))
    XCTAssertEqual(saved.standardizedFileURL.path,
      documents.appendingPathComponent("Movies/Fetchr/Road trip/a.mp4").standardizedFileURL.path)
    XCTAssertTrue(FileManager.default.fileExists(atPath: saved.path))
  }

  func testRunGetsArgvUrlAndTaskDir() async throws {
    fake.script = { run, _ in try FakeDownloads.write("a.mp4", in: run) }
    let repository = repository()
    let req = downloadRequest(quality: .p720)
    let id = try firstOf(await repository.enqueue([req]))
    _ = try await waitFor(repository, allDone)

    let run = try XCTUnwrap(fake.runs.first)
    let dir = caches.appendingPathComponent("tasks/\(id)")
    XCTAssertEqual(run.outDir.standardizedFileURL.path, dir.standardizedFileURL.path)
    XCTAssertEqual(run.url, req.url)
    XCTAssertEqual(run.argv, RequestBuilder.downloadArgv(req, outDir: dir, cacheDir: caches))
  }

  func testMp3SavesOnlyTheMp3() async throws {
    fake.script = { run, _ in
      try FakeDownloads.write("x.webm", bytes: 4096, in: run)
      try FakeDownloads.write("x.mp3", bytes: 64, in: run)
      try FakeDownloads.write(RequestBuilder.conversionReport, bytes: 8192, in: run)
    }
    let repository = repository()
    _ = await repository.enqueue([downloadRequest(quality: .mp3)])

    let task = try firstOf(try await waitFor(repository, allDone))
    XCTAssertEqual(task.status, .completed, task.errorMessage ?? "")
    XCTAssertEqual(task.savedPath, "Music/Fetchr")
    XCTAssertTrue(task.savedUri?.hasSuffix("/Music/Fetchr/x.mp3") == true, task.savedUri ?? "nil")
    let music = documents.appendingPathComponent("Music/Fetchr")
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: music.path), ["x.mp3"])
  }

  func testSaveDeduplicatesNames() async throws {
    fake.script = { run, _ in try FakeDownloads.write("a.mp4", in: run) }
    let repository = repository()
    _ = await repository.enqueue([downloadRequest(), downloadRequest()])

    let tasks = try await waitFor(repository, allDone)
    XCTAssertEqual(tasks.map(\.status), [.completed, .completed])
    let names = tasks.compactMap { $0.savedUri.flatMap(URL.init(string:))?.lastPathComponent }
    XCTAssertEqual(Set(names), ["a.mp4", "a (1).mp4"])
    let movies = documents.appendingPathComponent("Movies/Fetchr")
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: movies.path).sorted(), ["a (1).mp4", "a.mp4"])
  }

  func testProgressAndPostProcessingStage() async throws {
    let downloaded = Gate()
    let merged = Gate()
    fake.script = { run, fake in
      fake.emit(run, ["type": "progress", "stage": "downloading", "downloaded": 50, "total": 100, "speed": 25.5, "eta": 2])
      await downloaded.wait()
      fake.emit(run, ["type": "stage", "stage": "postProcessing", "pp": "Merger"])
      await merged.wait()
      try FakeDownloads.write("a.mp4", in: run)
    }
    let repository = repository()
    _ = await repository.enqueue([downloadRequest()])

    let halfway = try firstOf(try await waitFor(repository) { $0.first?.progress == 0.5 })
    XCTAssertEqual(halfway.status, .running)
    XCTAssertEqual(halfway.stage, .downloading)
    XCTAssertEqual(halfway.downloadedBytes, 50)
    XCTAssertEqual(halfway.totalBytes, 100)
    XCTAssertEqual(halfway.speedBytesPerSec, 25)
    XCTAssertEqual(halfway.etaSeconds, 2)
    downloaded.release()

    let merging = try firstOf(try await waitFor(repository) { $0.first?.stage == .postProcessing })
    XCTAssertEqual(merging.progress, -1)
    XCTAssertEqual(merging.status, .running)
    merged.release()
    let finished = try await waitFor(repository, allDone)
    XCTAssertEqual(finished.first?.status, .completed)
  }

  func testUnknownTotalGivesUnknownProgress() async throws {
    let gate = Gate()
    fake.script = { run, fake in
      fake.emit(run, ["type": "progress", "stage": "downloading", "downloaded": 50, "total": NSNull(), "speed": NSNull(), "eta": NSNull()])
      await gate.wait()
    }
    let repository = repository()
    _ = await repository.enqueue([downloadRequest()])
    let task = try firstOf(try await waitFor(repository) { $0.first?.downloadedBytes == 50 })
    XCTAssertEqual(task.progress, -1)
    XCTAssertEqual(task.stage, .downloading)
    XCTAssertNil(task.totalBytes)
    XCTAssertEqual(task.etaSeconds, -1)
    gate.release()
    _ = try await waitFor(repository, allDone)
  }

  func testFailedRunKeepsTempDir() async throws {
    fake.script = { run, _ in
      try FakeDownloads.write("a.mp4.part", in: run)
      throw BridgeError(hint: "network", message: "ERROR: timed out")
    }
    let repository = repository()
    let id = try firstOf(await repository.enqueue([downloadRequest()]))

    let task = try firstOf(try await waitFor(repository, allDone))
    XCTAssertEqual(task.status, .failed)
    XCTAssertEqual(task.errorCode, "network")
    XCTAssertEqual(task.errorMessage, "timed out")
    XCTAssertNotNil(task.finishedAtMs)
    XCTAssertNil(task.savedUri)
    await repository.waitUntilIdle()
    let part = caches.appendingPathComponent("tasks/\(id)/a.mp4.part")
    XCTAssertTrue(FileManager.default.fileExists(atPath: part.path), "a Retry goes on from the partial file")
  }

  func testCompletedRunCleansTempDir() async throws {
    fake.script = { run, _ in
      try FakeDownloads.write("a.mp4", in: run)
      try FakeDownloads.write("a.f137.mp4.part", in: run)
    }
    let repository = repository()
    let id = try firstOf(await repository.enqueue([downloadRequest()]))
    let finished = try await waitFor(repository, allDone)
    XCTAssertEqual(finished.first?.status, .completed)
    await repository.waitUntilIdle()
    XCTAssertFalse(FileManager.default.fileExists(atPath: caches.appendingPathComponent("tasks/\(id)").path))
  }

  func testRunWithoutAFileFails() async throws {
    fake.script = { run, _ in try FakeDownloads.write("a.mp4.part", in: run) }
    let repository = repository()
    _ = await repository.enqueue([downloadRequest()])
    let task = try firstOf(try await waitFor(repository, allDone))
    XCTAssertEqual(task.status, .failed)
    XCTAssertEqual(task.errorCode, "unknown")
    XCTAssertEqual(task.errorMessage, "No file was saved.")
  }

  func testEventsAfterTheRunAreIgnored() async throws {
    fake.script = { run, _ in try FakeDownloads.write("a.mp4", in: run) }
    let repository = repository()
    let id = try firstOf(await repository.enqueue([downloadRequest()]))
    _ = try await waitFor(repository, allDone)
    repository.receive(taskId: "\(id)#1", json: #"{"type":"stage","stage":"postProcessing","pp":"Merger"}"#)
    try await Task.sleep(nanoseconds: 100_000_000)
    let task = try firstOf(await repository.tasks)
    XCTAssertEqual(task.status, .completed)
    XCTAssertEqual(task.progress, 1)
  }

  func testSnapshotsSendTheListOnListenAndEveryChange() async throws {
    let gate = Gate()
    fake.script = { _, _ in await gate.wait() }
    let repository = repository()
    let id = try firstOf(await repository.enqueue([downloadRequest()]))
    var iterator = await repository.snapshots.makeAsyncIterator()
    let first = await iterator.next()
    XCTAssertEqual(first?.map(\.id), [id])
    gate.release()
    var last = first
    while let next = await iterator.next() {
      last = next
      if next.first?.status == .failed || next.first?.status == .completed { break }
    }
    XCTAssertEqual(last?.first?.status, .failed, "the fake wrote no file")
  }

  func testStreamSendsOnListenThenConflates() async throws {
    let gate = Gate()
    fake.script = { run, fake in
      for step in 1...20 {
        fake.emit(run, ["type": "progress", "stage": "downloading", "downloaded": step, "total": 20, "speed": 1, "eta": 1])
      }
      await gate.wait()
    }
    let repository = repository()
    let lock = NSLock()
    var sent: [(Date, DownloadsSnapshot)] = []
    let sink = PigeonEventSink<DownloadsSnapshot> { value in
      lock.withLock { sent.append((Date(), value as! DownloadsSnapshot)) }
    }
    let stream = DownloadsStream(repository: repository)
    let listened = Date()
    await MainActor.run { stream.onListen(withArguments: nil, sink: sink) }
    var received: [(Date, DownloadsSnapshot)] { lock.withLock { sent } }
    while received.isEmpty { try await Task.sleep(nanoseconds: 5_000_000) }
    XCTAssertEqual(received.first?.1.tasks, [], "the current list goes out on listen")
    XCTAssertLessThan(received[0].0.timeIntervalSince(listened), 0.2)

    _ = await repository.enqueue([downloadRequest()])
    _ = try await waitFor(repository) { $0.first?.progress == 1 }
    try await Task.sleep(nanoseconds: 600_000_000)
    let all = received
    XCTAssertEqual(all.last?.1.tasks.first?.progress, 1, "the newest list is never dropped")
    XCTAssertLessThan(all.count, 6, "21 changes conflate into a few snapshots: \(all.count)")
    for (earlier, later) in zip(all, all.dropFirst()) {
      XCTAssertGreaterThanOrEqual(later.0.timeIntervalSince(earlier.0), 0.24)
    }
    await MainActor.run { stream.onCancel(withArguments: nil) }
    gate.release()
    _ = try await waitFor(repository, allDone)
    try await Task.sleep(nanoseconds: 300_000_000)
    XCTAssertEqual(received.count, all.count, "nothing is sent after cancel")
  }

  func testEnqueueRejectsBatchWithBadUrl() async throws {
    let repository = repository()
    let api = HostApi(python: fake, downloads: repository, cacheDir: caches)
    XCTAssertThrowsError(try api.enqueue(requests: [downloadRequest(), downloadRequest("-o x")])) { error in
      XCTAssertEqual((error as? FetchrError)?.code, "invalid_url")
    }
    try await Task.sleep(nanoseconds: 200_000_000)
    let tasks = await repository.tasks
    XCTAssertTrue(tasks.isEmpty)
    XCTAssertTrue(fake.runs.isEmpty)
  }

  func testEnqueueThroughHostApiAddsTrimmedTasks() async throws {
    fake.script = { run, _ in try FakeDownloads.write("a.mp4", in: run) }
    let repository = repository()
    let api = HostApi(python: fake, downloads: repository, cacheDir: caches)
    try api.enqueue(requests: [downloadRequest("  https://example.com/a  "), downloadRequest("https://example.com/b")])
    let tasks = try await waitFor(repository, allDone)
    XCTAssertEqual(Set(tasks.map(\.request.url)), ["https://example.com/a", "https://example.com/b"])
    XCTAssertEqual(Set(fake.runs.map(\.url)), ["https://example.com/a", "https://example.com/b"])
  }
}

final class SaveLocationTests: XCTestCase {
  private var dir: URL!

  override func setUpWithError() throws {
    dir = FileManager.default.temporaryDirectory.appendingPathComponent("save-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: dir)
  }

  private func file(_ name: String, bytes: Int) throws -> URL {
    let url = dir.appendingPathComponent(name)
    try Data(repeating: 1, count: bytes).write(to: url)
    return url
  }

  func testMediaKindOfEveryQuality() {
    XCTAssertEqual(Quality.allCases.map { MediaKind.of($0).root }, ["Movies", "Movies", "Movies", "Movies", "Music", "Pictures"])
  }

  func testRelativeFolder() {
    XCTAssertEqual(SaveLocation.relativeFolder(downloadRequest(quality: .mp3)), "Music/Fetchr")
    XCTAssertEqual(SaveLocation.relativeFolder(downloadRequest(quality: .cover)), "Pictures/Fetchr")
    XCTAssertEqual(SaveLocation.relativeFolder(downloadRequest(playlist: "a/b: c")), "Movies/Fetchr/ab c")
  }

  func testPickResultTakesTheLargestMediaFile() throws {
    _ = try file("big.mp4.part", bytes: 900)
    _ = try file("x.ytdl", bytes: 800)
    _ = try file(RequestBuilder.conversionReport, bytes: 700)
    _ = try file("small.jpg", bytes: 10)
    let picked = try file("clip.mp4", bytes: 100)
    try FileManager.default.createDirectory(at: dir.appendingPathComponent("sub"), withIntermediateDirectories: true)
    XCTAssertEqual(try SaveLocation.pickResult(in: dir, quality: .best).lastPathComponent, picked.lastPathComponent)
  }

  func testPickResultForMp3TakesOnlyMp3() throws {
    _ = try file("x.webm", bytes: 900)
    _ = try file("x.MP3", bytes: 10)
    XCTAssertEqual(try SaveLocation.pickResult(in: dir, quality: .mp3).lastPathComponent, "x.MP3")
  }

  func testPickResultThrowsWhenNothingWasSaved() throws {
    _ = try file("x.webm", bytes: 900)
    XCTAssertThrowsError(try SaveLocation.pickResult(in: dir, quality: .mp3)) { error in
      XCTAssertEqual((error as? FetchrError)?.code, "unknown")
      XCTAssertEqual((error as? FetchrError)?.message, "No file was saved.")
    }
  }

  func testSaveDeduplicatesWithCounter() throws {
    let documents = dir.appendingPathComponent("Documents")
    var names: [String] = []
    for _ in 0..<3 {
      let source = try file("a.mp4", bytes: 5)
      names.append(try SaveLocation.save(source, toRelativeFolder: "Movies/Fetchr", documents: documents).lastPathComponent)
      XCTAssertFalse(FileManager.default.fileExists(atPath: source.path), "moved, not copied")
    }
    XCTAssertEqual(names, ["a.mp4", "a (1).mp4", "a (2).mp4"])
    let noExt = try file("README", bytes: 1)
    _ = try SaveLocation.save(noExt, toRelativeFolder: "Movies/Fetchr", documents: documents)
    let again = try file("README", bytes: 1)
    XCTAssertEqual(try SaveLocation.save(again, toRelativeFolder: "Movies/Fetchr", documents: documents).lastPathComponent, "README (1)")
  }
}
