import XCTest
@testable import Runner

// One gate per run key, opened by the test: a fake download blocks on its own run until released. After
// `releaseAll` every gate is open, so a run that starts later (tearDown) never blocks.
final class RunGates: @unchecked Sendable {
  private let lock = NSLock()
  private var gates: [String: Gate] = [:]
  private var allOpen = false

  private func gate(_ key: String) -> Gate {
    let (gate, open) = lock.withLock { () -> (Gate, Bool) in
      if let gate = gates[key] { return (gate, allOpen) }
      let gate = Gate()
      gates[key] = gate
      return (gate, allOpen)
    }
    if open { gate.release() }
    return gate
  }

  func wait(_ key: String) async { await gate(key).wait() }
  func release(_ key: String) { gate(key).release() }

  func releaseAll() {
    let all = lock.withLock {
      allOpen = true
      return Array(gates.values)
    }
    all.forEach { $0.release() }
  }
}

struct FakeCancelled: Error {}

final class Recorded<T>: @unchecked Sendable {
  private let lock = NSLock()
  private var stored: T?

  var value: T? { lock.withLock { stored } }
  func set(_ value: T) { lock.withLock { stored = value } }
}

final class DownloadLifecycleTests: XCTestCase {
  private var root: URL!
  private var documents: URL { root.appendingPathComponent("Documents") }
  private var caches: URL { root.appendingPathComponent("Caches") }
  private let fake = FakeDownloads()
  private let gates = RunGates()
  private var repo: DownloadRepository!

  override func setUpWithError() throws {
    root = FileManager.default.temporaryDirectory.appendingPathComponent("life-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
    repo = DownloadRepository(python: fake, documents: documents, cachesDir: caches)
    fake.repository = repo
  }

  override func tearDown() async throws {
    gates.releaseAll()
    await repo?.waitUntilIdle()
    repo = nil
    try? FileManager.default.removeItem(at: root)
  }

  private func dir(_ id: String) -> URL { caches.appendingPathComponent("tasks/\(id)") }

  private func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

  private func task(_ id: String) async -> DownloadTask? { await repo.tasks.first { $0.id == id } }

  private func progress(_ downloaded: Int, of total: Int) -> [String: Any] {
    ["type": "progress", "stage": "downloading", "downloaded": downloaded, "total": total, "speed": 1, "eta": 9]
  }

  // Polls a condition that is not the task list (fake calls, files).
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

  // Each run writes a partial file, then blocks until released; a released run whose key was cancelled throws
  // as Python's would, else it leaves a whole file.
  private func blockingScript() {
    fake.script = { [gates] run, fake in
      try FakeDownloads.write("a.mp4.part", in: run)
      await gates.wait(run.task)
      if fake.isCancelled(run.task) { throw FakeCancelled() }
      try FakeDownloads.write("a.mp4", in: run)
    }
  }

  func testCancelRunningSettlesAtOnceStartsTheNextAndDeletesTheDir() async throws {
    blockingScript()
    let ids = await repo.enqueue([downloadRequest(), downloadRequest(), downloadRequest()])
    _ = try await waitFor(repo) { $0.filter { $0.status == .running }.count == 2 }
    try await eventually { exists(dir(ids[0])) }

    await repo.cancel(ids[0])
    let canceledTask = await task(ids[0])
    let canceled = try XCTUnwrap(canceledTask)
    XCTAssertEqual(canceled.status, .canceled)
    XCTAssertNotNil(canceled.finishedAtMs)
    try await eventually { fake.runs.contains { $0.task == "\(ids[2])#1" } }
    XCTAssertEqual(fake.runs.count, 3, "the third started while the first is still in Python")
    try await eventually { fake.cancels == ["\(ids[0])#1"] }

    gates.release("\(ids[0])#1")
    try await eventually { !exists(dir(ids[0])) }
    gates.releaseAll()
    await repo.waitUntilIdle()
    let statusAfterRelease = await task(ids[0])?.status
    XCTAssertEqual(statusAfterRelease, .canceled)
    XCTAssertFalse(exists(dir(ids[0])))
  }

  func testPauseDuringExtractionWinsOverTheLateReply() async throws {
    fake.script = { [gates] run, _ in
      await gates.wait(run.task)
      try FakeDownloads.write("a.mp4", in: run)
    }
    let id = try firstOf(await repo.enqueue([downloadRequest()]))
    try await eventually { fake.runs.count == 1 }

    await repo.pause(id)
    let statusAtOnce = await task(id)?.status
    XCTAssertEqual(statusAtOnce, .paused)
    gates.release("\(id)#1")
    await repo.waitUntilIdle()

    let pausedTask = await task(id)
    let paused = try XCTUnwrap(pausedTask)
    XCTAssertEqual(paused.status, .paused)
    XCTAssertNil(paused.savedUri)
    let movies = documents.appendingPathComponent("Movies/Fetchr")
    XCTAssertEqual((try? FileManager.default.contentsOfDirectory(atPath: movies.path)) ?? [], [])
    XCTAssertTrue(exists(dir(id).appendingPathComponent("a.mp4")), "the next attempt goes on from it")
  }

  func testPauseKeepsDirAndProgressResumeContinuesInTheSameDir() async throws {
    fake.script = { [gates] run, fake in
      if run.task.hasSuffix("#1") {
        try FakeDownloads.write("a.mp4.part", in: run)
        fake.emit(run, ["type": "progress", "stage": "downloading", "downloaded": 40, "total": 100, "speed": 1, "eta": 9])
        await gates.wait(run.task)
        throw FakeCancelled()
      }
      try FakeDownloads.write("a.mp4", in: run)
    }
    let id = try firstOf(await repo.enqueue([downloadRequest()]))
    _ = try await waitFor(repo) { $0.first?.progress == 0.4 }

    await repo.pause(id)
    let pausedTask = await task(id)
    let paused = try XCTUnwrap(pausedTask)
    XCTAssertEqual(paused.status, .paused)
    XCTAssertEqual(paused.progress, 0.4)
    gates.release("\(id)#1")
    await repo.waitUntilIdle()
    XCTAssertTrue(exists(dir(id).appendingPathComponent("a.mp4.part")))
    let keptProgress = await task(id)?.progress
    XCTAssertEqual(keptProgress, 0.4)

    await repo.resume(id)
    let done = try await waitFor(repo) { $0.first?.status == .completed }
    XCTAssertEqual(fake.runs.map(\.task), ["\(id)#1", "\(id)#2"])
    XCTAssertEqual(fake.runs[1].outDir.standardizedFileURL.path, fake.runs[0].outDir.standardizedFileURL.path)
    XCTAssertEqual(done.first?.savedPath, "Movies/Fetchr")
  }

  // ffmpeg writes the MP3 under its final name; a conversion cut short leaves a partial x.mp3 that yt-dlp would take
  // as already downloaded on the next attempt and save truncated as completed.
  func testResumedMp3NeverFindsTheCutShortConversion() async throws {
    fake.script = { [gates] run, fake in
      if run.task.hasSuffix("#1") {
        try FakeDownloads.write("x.webm", bytes: 64, in: run)
        try FakeDownloads.write("x.mp3", bytes: 8, in: run)
        try FakeDownloads.write(RequestBuilder.conversionReport, in: run)
        fake.emit(run, ["type": "stage", "stage": "postProcessing", "pp": "ExtractAudio"])
        await gates.wait(run.task)
        throw FakeCancelled()
      }
      let left = try FileManager.default.contentsOfDirectory(atPath: run.outDir.path)
      XCTAssertFalse(left.contains("x.mp3"), "\(left)")
      XCTAssertFalse(left.contains(RequestBuilder.conversionReport), "\(left)")
      XCTAssertTrue(left.contains("x.webm"), "\(left)")
      try FakeDownloads.write("x.mp3", bytes: 32, in: run)
    }
    let id = try firstOf(await repo.enqueue([downloadRequest(quality: .mp3)]))
    _ = try await waitFor(repo) { $0.first?.stage == .postProcessing }

    await repo.pause(id)
    gates.release("\(id)#1")
    await repo.waitUntilIdle()
    XCTAssertTrue(exists(dir(id).appendingPathComponent("x.mp3")))

    await repo.resume(id)
    let done = try await waitFor(repo) { $0.first?.status == .completed }
    XCTAssertEqual(done.first?.totalBytes, 32)
  }

  func testResumeWhileTheOldAttemptUnwindsWaitsAndIsNotCancelled() async throws {
    fake.cancelDelay = 300_000_000
    fake.script = { [gates] run, fake in
      if run.task.hasSuffix("#1") {
        try FakeDownloads.write("a.mp4.part", in: run)
        await gates.wait(run.task)
        throw FakeCancelled()
      }
      XCTAssertTrue(
        FileManager.default.fileExists(atPath: run.outDir.appendingPathComponent("a.mp4.part").path),
        "attempt 1 left its partial file")
      await gates.wait(run.task)
      if fake.isCancelled(run.task) { throw FakeCancelled() }
      try FakeDownloads.write("a.mp4", in: run)
    }
    let id = try firstOf(await repo.enqueue([downloadRequest()]))
    try await eventually { fake.runs.count == 1 }

    await repo.pause(id)
    await repo.resume(id)
    let resumed = await task(id)?.isLive == true
    XCTAssertTrue(resumed)
    try await Task.sleep(nanoseconds: 150_000_000)
    XCTAssertEqual(fake.runs.count, 1, "attempt 2 waits for attempt 1 to return")

    gates.release("\(id)#1")
    try await eventually { fake.runs.count == 2 }
    XCTAssertEqual(fake.runs[1].task, "\(id)#2")
    try await eventually { fake.cancels == ["\(id)#1"] }
    gates.release("\(id)#2")

    let done = try await waitFor(repo) { $0.first?.status == .completed || $0.first?.status == .failed }
    XCTAssertEqual(done.first?.status, .completed, done.first?.errorMessage ?? "")
    XCTAssertEqual(fake.cancels, ["\(id)#1"])
    let movies = documents.appendingPathComponent("Movies/Fetchr")
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: movies.path), ["a.mp4"], "saved once")
  }

  func testResumeWaitsQueuedWithoutASlotWhileTheOldAttemptUnwinds() async throws {
    blockingScript()
    let ids = await repo.enqueue([downloadRequest(), downloadRequest(), downloadRequest()])
    let (a, c) = (ids[0], ids[2])
    _ = try await waitFor(repo) { $0.filter { $0.status == .running }.count == 2 }

    await repo.pause(a)
    await repo.resume(a)
    let resumed = await task(a)?.status
    XCTAssertEqual(resumed, .queued)
    try await eventually { fake.runs.contains { $0.task == "\(c)#1" } }

    // A slot frees while A's old attempt is still in Python: A waits for it without taking the slot.
    gates.release("\(c)#1")
    _ = try await waitFor(repo) { tasks in tasks.first { $0.id == c }?.status == .completed }
    await Task.yield()
    let waiting = await task(a)
    XCTAssertEqual(waiting?.status, .queued)
    XCTAssertFalse(fake.runs.contains { $0.task == "\(a)#2" })

    gates.release("\(a)#1")
    _ = try await waitFor(repo) { tasks in tasks.first { $0.id == a }?.status == .running }
    try await eventually { fake.runs.contains { $0.task == "\(a)#2" } }
  }

  func testRetryCanceledWhileTheOldAttemptUnwindsStartsFromAnEmptyDir() async throws {
    let seenAtStart = Recorded<[String]>()
    fake.script = { [gates] run, fake in
      if run.task.hasSuffix("#2") {
        seenAtStart.set((try? FileManager.default.contentsOfDirectory(atPath: run.outDir.path)) ?? [])
        try FakeDownloads.write("a.mp4", in: run)
        return
      }
      try FakeDownloads.write("a.mp4.part", in: run)
      await gates.wait(run.task)
      if fake.isCancelled(run.task) { throw FakeCancelled() }
    }
    let id = try firstOf(await repo.enqueue([downloadRequest()]))
    try await eventually { fake.runs.count == 1 }

    await repo.cancel(id)
    await repo.retry(id)
    gates.release("\(id)#1")
    let done = try await waitFor(repo) { $0.first?.status == .completed }
    XCTAssertEqual(fake.runs.map(\.task), ["\(id)#1", "\(id)#2"])
    XCTAssertEqual(seenAtStart.value, [], "the canceled attempt's .part is gone")
    XCTAssertNotNil(done.first?.savedUri)
  }

  func testRetryFailedKeepsBytesRetryCanceledStartsFromZero() async throws {
    fake.script = { [gates] run, fake in
      if run.task.hasSuffix("#2") {
        // A failed task's retry goes on from its partial file; a canceled one's starts over.
        let part = FileManager.default.fileExists(atPath: run.outDir.appendingPathComponent("a.mp4.part").path)
        await gates.wait(run.task)
        try FakeDownloads.write(part ? "kept.mp4" : "fresh.mp4", in: run)
        return
      }
      try FakeDownloads.write("a.mp4.part", in: run)
      fake.emit(run, ["type": "progress", "stage": "downloading", "downloaded": 40, "total": 100, "speed": 1, "eta": 9])
      await gates.wait(run.task)
      if fake.isCancelled(run.task) { throw FakeCancelled() }
      throw BridgeError(hint: "network", message: "ERROR: timed out")
    }
    let ids = await repo.enqueue([downloadRequest(), downloadRequest()])
    let (failing, canceling) = (ids[0], ids[1])
    _ = try await waitFor(repo) { $0.allSatisfy { $0.progress == 0.4 } }

    await repo.cancel(canceling)
    gates.release("\(failing)#1")
    gates.release("\(canceling)#1")
    _ = try await waitFor(repo) { tasks in tasks.first { $0.id == failing }?.status == .failed }
    await repo.waitUntilIdle()
    let failedProgress = await task(failing)?.progress
    XCTAssertEqual(failedProgress, 0.4)

    await repo.retry(failing)
    let retriedTask = await task(failing)
    let retried = try XCTUnwrap(retriedTask)
    XCTAssertTrue(retried.isLive)
    XCTAssertEqual(retried.progress, 0.4, "keeps the bytes it had")
    XCTAssertNil(retried.errorCode)
    await repo.retry(canceling)
    let restartedTask = await task(canceling)
    let restarted = try XCTUnwrap(restartedTask)
    XCTAssertTrue(restarted.isLive)
    XCTAssertLessThanOrEqual(restarted.progress, 0)
    XCTAssertNil(restarted.downloadedBytes)
    XCTAssertNil(restarted.finishedAtMs)
    gates.releaseAll()

    let done = try await waitFor(repo) { $0.allSatisfy { $0.status == .completed } }
    XCTAssertEqual(Set(fake.runs.map(\.task)), ["\(failing)#1", "\(canceling)#1", "\(failing)#2", "\(canceling)#2"])
    let names = Dictionary(uniqueKeysWithValues: done.map { ($0.id, URL(string: $0.savedUri ?? "")?.lastPathComponent) })
    XCTAssertEqual(names[failing], "kept.mp4")
    XCTAssertEqual(names[canceling], "fresh.mp4")
  }

  func testEventsFromAnAbandonedAttemptAreIgnored() async throws {
    blockingScript()
    let id = try firstOf(await repo.enqueue([downloadRequest()]))
    try await eventually { fake.runs.count == 1 }
    let first = fake.runs[0]
    await repo.pause(id)
    await repo.resume(id)
    gates.release("\(id)#1")
    try await eventually { fake.runs.count == 2 }
    let second = fake.runs[1]
    fake.emit(second, progress(10, of: 100))
    _ = try await waitFor(repo) { $0.first?.progress == 0.1 }

    fake.emit(first, progress(90, of: 100))
    repo.receive(taskId: id, json: #"{"type":"stage","stage":"postProcessing","pp":"Merger"}"#)
    try await Task.sleep(nanoseconds: 150_000_000)
    let currentTask = await task(id)
    let current = try XCTUnwrap(currentTask)
    XCTAssertEqual(current.progress, 0.1)
    XCTAssertEqual(current.stage, .downloading)
    XCTAssertEqual(current.downloadedBytes, 10)
  }

  func testReorderChangesWhichQueuedTaskStartsNextAndTheListOrder() async throws {
    blockingScript()
    let ids = await repo.enqueue([downloadRequest(), downloadRequest(), downloadRequest(), downloadRequest()])
    _ = try await waitFor(repo) { $0.filter { $0.status == .running }.count == 2 }
    let queued = await repo.tasks.filter { $0.status == .queued }.map(\.id)
    XCTAssertEqual(queued, [ids[2], ids[3]])

    await repo.reorder([ids[3], ids[2]])
    let order = await repo.tasks.map(\.id)
    XCTAssertEqual(order, [ids[0], ids[1], ids[3], ids[2]])
    gates.release("\(ids[0])#1")
    try await eventually { fake.runs.count == 3 }
    XCTAssertEqual(fake.runs[2].task, "\(ids[3])#1")
    let skipped = await task(ids[2])?.status
    XCTAssertEqual(skipped, .queued)
  }

  func testPauseAllAndResumeAll() async throws {
    blockingScript()
    let ids = await repo.enqueue([downloadRequest(), downloadRequest(), downloadRequest()])
    _ = try await waitFor(repo) { $0.filter { $0.status == .running }.count == 2 }

    await repo.pauseAll()
    let paused = await repo.tasks.map(\.status)
    XCTAssertEqual(paused, [.paused, .paused, .paused])
    try await eventually { Set(fake.cancels) == ["\(ids[0])#1", "\(ids[1])#1"] }
    XCTAssertEqual(fake.runs.count, 2, "pausing the running ones started no queued one")
    gates.release("\(ids[0])#1")
    gates.release("\(ids[1])#1")
    await repo.waitUntilIdle()
    let stillPaused = await repo.tasks.map(\.status)
    XCTAssertEqual(stillPaused, [.paused, .paused, .paused])

    await repo.resumeAll()
    let resumed = await repo.tasks
    XCTAssertEqual(resumed.filter { $0.status == .running }.map(\.id), [ids[0], ids[1]])
    XCTAssertEqual(resumed.filter { $0.status == .queued }.map(\.id), [ids[2]])
    gates.releaseAll()
    _ = try await waitFor(repo) { $0.allSatisfy { $0.status == .completed } }
  }

  func testRemoveRunningStopsItAndDropsTheTask() async throws {
    blockingScript()
    let id = try firstOf(await repo.enqueue([downloadRequest()]))
    try await eventually { exists(dir(id)) && fake.runs.count == 1 }

    let removed = try await repo.remove(id)
    XCTAssertTrue(removed)
    let goneAtOnce = await repo.tasks.isEmpty
    XCTAssertTrue(goneAtOnce)
    try await eventually { fake.cancels == ["\(id)#1"] }
    gates.releaseAll()
    await repo.waitUntilIdle()
    let goneAfter = await repo.tasks.isEmpty
    XCTAssertTrue(goneAfter)
    XCTAssertFalse(exists(dir(id)))
  }

  private func completed(_ requests: [DownloadRequest]) async throws -> [DownloadTask] {
    fake.script = { run, _ in try FakeDownloads.write("a.mp4", in: run) }
    _ = await repo.enqueue(requests)
    let tasks = try await waitFor(repo) { $0.allSatisfy { $0.status == .completed } }
    await repo.waitUntilIdle()
    return tasks
  }

  private func savedFile(_ task: DownloadTask) throws -> URL { try XCTUnwrap(URL(string: task.savedUri ?? "")) }

  func testRemoveCompletedDeletesFileAndEmptyPlaylistFolder() async throws {
    let task = try firstOf(try await completed([downloadRequest(playlist: "Road trip")]))
    let file = try savedFile(task)
    let playlist = documents.appendingPathComponent("Movies/Fetchr/Road trip")
    XCTAssertTrue(exists(file))

    let removed = try await repo.remove(task.id)
    XCTAssertTrue(removed)
    let empty = await repo.tasks.isEmpty
    XCTAssertTrue(empty)
    XCTAssertFalse(exists(file))
    XCTAssertFalse(exists(playlist))
    XCTAssertTrue(exists(documents.appendingPathComponent("Movies/Fetchr")), "the user's folder stays")
  }

  func testRemoveKeepsANonEmptyPlaylistFolder() async throws {
    let tasks = try await completed([downloadRequest(playlist: "Road trip"), downloadRequest(playlist: "Road trip")])
    let gone = try savedFile(tasks[0])
    let kept = try savedFile(tasks[1])

    let removed = try await repo.remove(tasks[0].id)
    XCTAssertTrue(removed)
    XCTAssertFalse(exists(gone))
    XCTAssertTrue(exists(kept))
    let left = await repo.tasks.map(\.id)
    XCTAssertEqual(left, [tasks[1].id])
  }

  func testRemoveOfANonPlaylistFileKeepsTheEmptyUserFolder() async throws {
    let task = try firstOf(try await completed([downloadRequest()]))
    let removed = try await repo.remove(task.id)
    XCTAssertTrue(removed)
    XCTAssertFalse(exists(try savedFile(task)))
    XCTAssertTrue(exists(documents.appendingPathComponent("Movies/Fetchr")))
  }

  func testRemoveOfAFileAlreadyGoneStillSucceeds() async throws {
    let task = try firstOf(try await completed([downloadRequest(playlist: "Road trip")]))
    try FileManager.default.removeItem(at: try savedFile(task))

    let removed = try await repo.remove(task.id)
    XCTAssertTrue(removed)
    let empty = await repo.tasks.isEmpty
    XCTAssertTrue(empty)
  }

  func testRemovePausedDeletesItsDir() async throws {
    blockingScript()
    let id = try firstOf(await repo.enqueue([downloadRequest()]))
    try await eventually { exists(dir(id)) }
    await repo.pause(id)
    gates.releaseAll()
    await repo.waitUntilIdle()
    XCTAssertTrue(exists(dir(id)))

    let removed = try await repo.remove(id)
    XCTAssertTrue(removed)
    await repo.waitUntilIdle()
    XCTAssertFalse(exists(dir(id)))
  }

  func testHostApiCommandsReachTheRepositoryInOrder() async throws {
    blockingScript()
    let api = HostApi(python: fake, downloads: repo, cacheDir: caches)
    let id = try firstOf(await repo.enqueue([downloadRequest()]))
    try await eventually { fake.runs.count == 1 }

    try api.pause(id: id)
    try api.resume(id: id)
    // Only a pause reaching #1 in Python cancels it, and only a resume after it starts #2: in the other order the
    // resume is a no-op and the task stays paused.
    try await eventually { fake.cancels == ["\(id)#1"] }
    gates.releaseAll()
    _ = try await waitFor(repo) { $0.first?.status == .completed }
    XCTAssertEqual(fake.runs.map(\.task), ["\(id)#1", "\(id)#2"])
  }

  func testHostApiRemoveDropsTheTask() async throws {
    let api = HostApi(python: fake, downloads: repo, cacheDir: caches)
    let task = try firstOf(try await completed([downloadRequest()]))
    let removed = try await api.remove(id: task.id)
    XCTAssertTrue(removed)
    let empty = await repo.tasks.isEmpty
    XCTAssertTrue(empty)
  }
}
