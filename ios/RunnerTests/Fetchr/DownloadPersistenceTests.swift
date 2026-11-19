import XCTest
@testable import Runner

// Forwards to a real store and counts the saves the repository asks for (the store coalesces the writes).
final class CountingStore: TaskPersisting, @unchecked Sendable {
  let inner: TaskStore
  private let lock = NSLock()
  private var count = 0

  init(_ inner: TaskStore) { self.inner = inner }

  var saves: Int { lock.withLock { count } }

  func load() -> [StoredTask] { inner.load() }

  func save(_ tasks: [StoredTask]) {
    lock.withLock { count += 1 }
    inner.save(tasks)
  }
}

final class DownloadPersistenceTests: XCTestCase {
  private var root: URL!
  private var caches: URL { root.appendingPathComponent("Caches") }
  private var storeURL: URL { root.appendingPathComponent("Application Support/downloads.json") }
  private let fake = FakeDownloads()
  private let gates = RunGates()
  private var repos: [DownloadRepository] = []

  override func setUpWithError() throws {
    root = FileManager.default.temporaryDirectory.appendingPathComponent("persist-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: documents(), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
  }

  override func tearDown() async throws {
    gates.releaseAll()
    for repo in repos { await repo.waitUntilIdle() }
    repos = []
    try? FileManager.default.removeItem(at: root)
  }

  private func documents(_ name: String = "Documents") -> URL { root.appendingPathComponent(name) }

  private func repository(
    documents: URL? = nil, store: TaskPersisting? = nil, stallCheck: TimeInterval = 5, stallAfter: TimeInterval = 30,
    conversionPoll: TimeInterval = 0.5
  ) -> DownloadRepository {
    let repo = DownloadRepository(
      python: fake, documents: documents ?? self.documents(), cachesDir: caches,
      store: store ?? TaskStore(url: storeURL), stallCheck: stallCheck, stallAfter: stallAfter,
      conversionPoll: conversionPoll)
    fake.repository = repo
    repos.append(repo)
    return repo
  }

  private func dir(_ id: String) -> URL { caches.appendingPathComponent("tasks/\(id)") }

  private func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

  private func task(_ repo: DownloadRepository, _ id: String) async -> DownloadTask? {
    await repo.tasks.first { $0.id == id }
  }

  private func storedBytes() -> Data? { try? Data(contentsOf: storeURL) }

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

  private func progress(_ downloaded: Int, of total: Int) -> [String: Any] {
    ["type": "progress", "stage": "downloading", "downloaded": downloaded, "total": total, "speed": 1, "eta": 9]
  }

  func testTasksSurviveARestart() async throws {
    fake.script = { [gates] run, _ in
      await gates.wait(run.task)
      try FakeDownloads.write("a.mp4", in: run)
    }
    let store = TaskStore(url: storeURL)
    let first = repository(store: store)
    let ids = await first.enqueue([downloadRequest(), downloadRequest(playlist: "Mix")])
    _ = try await waitFor(first) { $0.filter { $0.status == .running }.count == 2 }
    gates.release("\(ids[1])#1")
    let done = try await waitFor(first) { $0.first { $0.id == ids[1] }?.status == .completed }
    let completed = try XCTUnwrap(done.first { $0.id == ids[1] })
    await first.pause(ids[0])
    gates.release("\(ids[0])#1")
    await first.waitUntilIdle()
    store.waitForPendingWrites()

    let moved = documents("Documents-reinstalled")
    try FileManager.default.moveItem(at: documents(), to: moved)
    let second = repository(documents: moved, store: TaskStore(url: storeURL))
    let tasks = await second.tasks
    XCTAssertEqual(tasks.map(\.id), ids)
    XCTAssertEqual(tasks.map(\.status), [.paused, .completed])
    let restored = tasks[1]
    XCTAssertEqual(restored.savedPath, completed.savedPath)
    XCTAssertEqual(restored.savedPath, "Movies/Fetchr/Mix")
    let uri = try XCTUnwrap(restored.savedUri)
    XCTAssertEqual(uri, moved.appendingPathComponent("Movies/Fetchr/Mix/a.mp4").absoluteString)
    XCTAssertNotEqual(uri, completed.savedUri)
    XCTAssertTrue(exists(try XCTUnwrap(URL(string: uri))))
    XCTAssertTrue(fake.runs.allSatisfy { $0.task.hasSuffix("#1") }, "nothing auto-starts after the restart")
    XCTAssertEqual(fake.runs.count, 2)
  }

  func testRestartLoadsLiveTasksAsPausedAndKeepsTheirDirs() async throws {
    let running = TaskFixtures.task(
      id: "run", status: .running, progress: 0.3, downloadedBytes: 30, totalBytes: 100, createdAtMs: 3)
    let queued = TaskFixtures.task(
      id: "queue", status: .queued, progress: -1, downloadedBytes: nil, totalBytes: nil, createdAtMs: 2)
    let canceled = TaskFixtures.task(id: "gone", status: .canceled, progress: 0.2, createdAtMs: 1)
    let failed = TaskFixtures.task(id: "fail", status: .failed, progress: 0.5, errorCode: "network", createdAtMs: 0)
    let seed = TaskStore(url: storeURL)
    seed.save([running, queued, canceled, failed].map { StoredTask(task: $0, savedFile: nil) })
    seed.waitForPendingWrites()
    for name in ["run", "fail", "gone", "unknown"] {
      try FileManager.default.createDirectory(at: dir(name), withIntermediateDirectories: true)
      try Data("x".utf8).write(to: dir(name).appendingPathComponent("a.mp4.part"))
    }

    let repo = repository()
    let tasks = await repo.tasks
    XCTAssertEqual(tasks.map(\.id), ["run", "queue", "gone", "fail"])
    XCTAssertEqual(tasks.map(\.status), [.paused, .paused, .canceled, .failed])
    XCTAssertEqual(tasks[0].progress, 0.3)
    XCTAssertEqual(tasks[1].progress, 0)
    try await eventually { !exists(dir("unknown")) && !exists(dir("gone")) }
    XCTAssertTrue(exists(dir("run").appendingPathComponent("a.mp4.part")))
    XCTAssertTrue(exists(dir("fail").appendingPathComponent("a.mp4.part")))
    XCTAssertTrue(fake.runs.isEmpty, "nothing auto-starts")
  }

  func testResumeAfterRestartUsesTheKeptDir() async throws {
    let paused = TaskFixtures.task(id: "p", request: downloadRequest(), status: .running, progress: 0.4)
    let seed = TaskStore(url: storeURL)
    seed.save([StoredTask(task: paused, savedFile: nil)])
    seed.waitForPendingWrites()
    try FileManager.default.createDirectory(at: dir("p"), withIntermediateDirectories: true)
    try Data("x".utf8).write(to: dir("p").appendingPathComponent("a.mp4.part"))
    let seenPart = Recorded<Bool>()
    fake.script = { run, _ in
      seenPart.set(FileManager.default.fileExists(atPath: run.outDir.appendingPathComponent("a.mp4.part").path))
      try FakeDownloads.write("a.mp4", in: run)
    }

    let repo = repository()
    await repo.resume("p")
    _ = try await waitFor(repo) { $0.first?.status == .completed }
    let run = try firstOf(fake.runs)
    XCTAssertEqual(run.outDir.standardizedFileURL.path, dir("p").standardizedFileURL.path)
    XCTAssertEqual(run.task, "p#1")
    XCTAssertEqual(seenPart.value, true)
  }

  func testProgressTicksDoNotWriteTheStoreButPauseDoes() async throws {
    fake.script = { [gates] run, fake in
      fake.emit(run, ["type": "progress", "stage": "downloading", "downloaded": 1, "total": 100, "speed": 1, "eta": 99])
      await gates.wait(run.task)
    }
    let store = TaskStore(url: storeURL)
    let repo = repository(store: store)
    let id = try firstOf(await repo.enqueue([downloadRequest()]))
    _ = try await waitFor(repo) { $0.first?.progress == 0.01 }
    store.waitForPendingWrites()
    let beforeTicks = try XCTUnwrap(storedBytes())

    let run = try firstOf(fake.runs)
    for downloaded in [20, 40, 60] {
      fake.emit(run, progress(downloaded, of: 100))
      _ = try await waitFor(repo) { $0.first?.progress == Double(downloaded) / 100 }
    }
    store.waitForPendingWrites()
    XCTAssertEqual(storedBytes(), beforeTicks, "progress ticks alone never write")

    await repo.pause(id)
    store.waitForPendingWrites()
    let afterPause = try XCTUnwrap(storedBytes())
    XCTAssertNotEqual(afterPause, beforeTicks)
    let stored = try firstOf(TaskCodec.decode(afterPause))
    XCTAssertEqual(stored.task.status, .paused)
    XCTAssertEqual(stored.task.progress, 0.6, "the pause records the progress")
  }

  func testPauseAllAndResumeAllWriteTheStoreOnce() async throws {
    fake.script = { [gates] run, _ in await gates.wait(run.task) }
    let store = CountingStore(TaskStore(url: storeURL))
    let repo = repository(store: store)
    _ = await repo.enqueue([downloadRequest(), downloadRequest(), downloadRequest()])
    _ = try await waitFor(repo) { $0.filter { $0.status == .running }.count == 2 }

    let beforePause = store.saves
    await repo.pauseAll()
    XCTAssertEqual(store.saves, beforePause + 1)
    store.inner.waitForPendingWrites()
    let paused = TaskCodec.decode(try XCTUnwrap(storedBytes()))
    XCTAssertEqual(paused.map(\.task.status), [.paused, .paused, .paused])

    let beforeResume = store.saves
    await repo.resumeAll()
    XCTAssertEqual(store.saves, beforeResume + 1)
    store.inner.waitForPendingWrites()
    let resumed = TaskCodec.decode(try XCTUnwrap(storedBytes()))
    XCTAssertEqual(resumed.count, 3)
  }

  func testStalledAfterSilenceAndClearedByTheNextEvent() async throws {
    fake.script = { [gates] run, _ in await gates.wait(run.task) }
    let repo = repository(stallCheck: 0.05, stallAfter: 0.5)
    _ = await repo.enqueue([downloadRequest()])
    let running = try await waitFor(repo) { $0.first?.status == .running }
    XCTAssertEqual(running.first?.stalled, false)
    try await eventually { fake.runs.count == 1 }

    _ = try await waitFor(repo, timeout: 3) { $0.first?.stalled == true }
    fake.emit(try firstOf(fake.runs), progress(10, of: 100))
    let cleared = try await waitFor(repo) { $0.first?.progress == 0.1 }
    XCTAssertEqual(cleared.first?.stalled, false, "the event that moved the bar cleared the flag")
    _ = try await waitFor(repo, timeout: 3) { $0.first?.stalled == true }
  }

  func testNoStallWhileWaitingForTheOldAttempt() async throws {
    fake.script = { [gates] run, _ in await gates.wait(run.task) }
    let repo = repository(stallCheck: 0.05, stallAfter: 0.5)
    let id = try firstOf(await repo.enqueue([downloadRequest()]))
    try await eventually { fake.runs.count == 1 }
    await repo.pause(id)
    await repo.resume(id)
    try await Task.sleep(nanoseconds: 1_000_000_000)
    let waiting = await task(repo, id)
    XCTAssertEqual(waiting?.status, .queued, "#2 waits for #1 to unwind")
    XCTAssertEqual(waiting?.stalled, false)

    gates.release("\(id)#1")
    try await eventually { fake.runs.count == 2 }
    try await Task.sleep(nanoseconds: 100_000_000)
    let started = await task(repo, id)
    XCTAssertEqual(started?.stalled, false, "the silence before the real start does not count")
  }

  func testNoStallWhilePostProcessing() async throws {
    fake.script = { [gates] run, fake in
      fake.emit(run, ["type": "stage", "stage": "postProcessing", "pp": "Merger"])
      await gates.wait(run.task)
    }
    let repo = repository(stallCheck: 0.05, stallAfter: 0.2)
    _ = await repo.enqueue([downloadRequest()])
    _ = try await waitFor(repo) { $0.first?.stage == .postProcessing }
    try await Task.sleep(nanoseconds: 600_000_000)
    let tasks = await repo.tasks
    XCTAssertEqual(tasks.first?.stalled, false)
    XCTAssertEqual(tasks.first?.status, .running)
  }

  func testMp3ConversionProgressComesFromTheReport() async throws {
    fake.script = { [gates] run, fake in
      fake.emit(run, ["type": "stage", "stage": "postProcessing", "pp": "FFmpegExtractAudio"])
      await gates.wait("\(run.task)-report")
      try Data("frame=1\nout_time_us=60000000\nprogress=continue\n".utf8)
        .write(to: run.outDir.appendingPathComponent(RequestBuilder.conversionReport))
      await gates.wait(run.task)
      try FakeDownloads.write("a.mp3", in: run)
    }
    var request = downloadRequest(quality: .mp3)
    request.durationSeconds = 120
    let repo = repository(conversionPoll: 0.02)
    let id = try firstOf(await repo.enqueue([request]))
    _ = try await waitFor(repo) { $0.first?.stage == .postProcessing }
    let before = await task(repo, id)
    XCTAssertEqual(before?.progress, -1)

    gates.release("\(id)#1-report")
    _ = try await waitFor(repo, timeout: 2) { $0.first?.progress == 0.5 }
    gates.release("\(id)#1")
    _ = try await waitFor(repo) { $0.first?.status == .completed }
  }
}
