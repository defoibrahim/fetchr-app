import AVFoundation
import XCTest
@testable import Runner

// Records the order the download calls reach Python, by run key.
final class RecordingPython: PythonCalling, @unchecked Sendable {
  private let inner: PythonCalling
  private let lock = NSLock()
  private var keys: [String] = []

  init(_ inner: PythonCalling) { self.inner = inner }

  var downloads: [String] { lock.withLock { keys } }

  func call(_ name: String, _ payload: [String: Any]) async throws -> Any {
    if name == "download", let key = payload["task"] as? String { lock.withLock { keys.append(key) } }
    return try await inner.call(name, payload)
  }
}

// Python's events go to the repository of the moment (a restart swaps it), held weakly so dropping it is real.
// Records each task's first progress event since the last reset, and can run a step on Python's thread at the next
// one (the emit releases the GIL, so the step may wait for the actor).
final class EmitRouter: @unchecked Sendable {
  private let lock = NSLock()
  private weak var target: DownloadRepository?
  private var first: [String: Int64] = [:]
  private var next: (@Sendable (String) -> Void)?

  func route(to repository: DownloadRepository) {
    lock.withLock {
      target = repository
      first = [:]
    }
  }

  func reset() { lock.withLock { first = [:] } }

  func firstDownloaded(_ id: String) -> Int64? { lock.withLock { first[id] } }

  func onNextProgress(_ step: @escaping @Sendable (_ taskId: String) -> Void) { lock.withLock { next = step } }

  func receive(_ runKey: String, _ json: String) {
    let id = DownloadRepository.taskId(of: runKey)
    let event = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any]
    let downloaded = event?["type"] as? String == "progress" ? (event?["downloaded"] as? NSNumber)?.int64Value : nil
    let (repository, step): (DownloadRepository?, (@Sendable (String) -> Void)?) = lock.withLock {
      guard let downloaded else { return (self.target, nil) }
      if first[id] == nil { first[id] = downloaded }
      defer { next = nil }
      return (self.target, next)
    }
    repository?.receive(taskId: runKey, json: json)
    step?(id)
  }
}

// The M4 and M5 gates: real downloads through the embedded yt-dlp and ffmpeg, each test on its own Documents,
// Caches and store. Opt in with FETCHR_NETWORK_TESTS=1.
final class DownloadIntegrationTests: XCTestCase {
  private static let flower = "https://interactive-examples.mdn.mozilla.net/media/cc0-videos/flower.mp4"
  private static let youtube = "https://www.youtube.com/watch?v=aqz-KE-bpKQ"
  private static let timeout: TimeInterval = 900
  private static let megabyte: Int64 = 1024 * 1024

  private var root: URL!
  private var documents: URL { root.appendingPathComponent("Documents", isDirectory: true) }
  private var caches: URL { root.appendingPathComponent("Caches", isDirectory: true) }
  private var storeURL: URL { root.appendingPathComponent("Application Support/downloads.json") }
  private var python: RecordingPython!
  private let router = EmitRouter()
  private var store: TaskStore!
  private var repository: DownloadRepository!
  private var retried: Set<String> = []

  override func setUpWithError() throws {
    try XCTSkipUnless(ProcessInfo.processInfo.environment["FETCHR_NETWORK_TESTS"] == "1", "network tests are opt-in")
    root = FileManager.default.temporaryDirectory.appendingPathComponent("downloads-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
    python = RecordingPython(PythonRuntime.shared)
    repository = makeRepository()
    let router = self.router
    PythonRuntime.setEmitHandler { task, json in router.receive(task, json) }
  }

  override func tearDown() async throws {
    // A skipped run never installed a handler; clearing it would drop the one AppDelegate set in the test host.
    guard let repository else { return }
    await repository.pauseAll()
    await repository.waitUntilIdle()
    PythonRuntime.setEmitHandler(nil)
    self.repository = nil
    // FETCHR_KEEP_DOWNLOADS=1 moves the test's Documents into the app's, for a look in the Files app.
    if ProcessInfo.processInfo.environment["FETCHR_KEEP_DOWNLOADS"] == "1" {
      let kept = Paths.documentsDir.appendingPathComponent("Tests/\(name.filter { $0.isLetter || $0.isNumber })")
      try? FileManager.default.createDirectory(
        at: kept.deletingLastPathComponent(), withIntermediateDirectories: true)
      try? FileManager.default.removeItem(at: kept)
      try? FileManager.default.moveItem(at: documents, to: kept)
      print("M5 kept \(kept.path)")
    }
    try? FileManager.default.removeItem(at: root)
  }

  // A new repository on the same store and dirs, as a relaunch builds it.
  private func makeRepository() -> DownloadRepository {
    store = TaskStore(url: storeURL)
    let repository = DownloadRepository(python: python, documents: documents, cachesDir: caches, store: store)
    router.route(to: repository)
    return repository
  }

  private func request(_ url: String, _ quality: Quality) -> DownloadRequest {
    DownloadRequest(url: url, title: "M4", quality: quality, folder: "Fetchr", useAria2c: false)
  }

  // On this Mac a connection can leave from another IPv6 address than the one YouTube signed the media URL for
  // (403), and MDN's IPv6 front resets the first connection of a process. Any other failure is a regression the
  // gate must show.
  private static func retryable(_ task: DownloadTask) -> Bool {
    task.status == .failed && (task.errorCode == "network" || (task.errorMessage ?? "").contains("HTTP Error 403"))
  }

  // Polls until every task has finished; returns them with the stages each one went through. `whileRunning` runs
  // once, when every task is downloading.
  private func finish(
    _ ids: [String], whileRunning: inout (([DownloadTask]) async throws -> Void)?
  ) async throws -> (tasks: [DownloadTask], stages: [String: Set<TaskStage>]) {
    let deadline = Date().addingTimeInterval(Self.timeout)
    var stages: [String: Set<TaskStage>] = [:]
    while true {
      let tasks = await repository.tasks.filter { ids.contains($0.id) }
      for task in tasks { stages[task.id, default: []].insert(task.stage) }
      if let run = whileRunning, tasks.count == ids.count,
        tasks.allSatisfy({ $0.status == .running && ($0.downloadedBytes ?? 0) > 0 })
      {
        whileRunning = nil
        try await run(tasks)
      }
      if tasks.count == ids.count, tasks.allSatisfy({ $0.status == .completed || $0.status == .failed }) {
        return (ids.compactMap { id in tasks.first { $0.id == id } }, stages)
      }
      if Date() > deadline {
        XCTFail("timed out: \(tasks.map { "\($0.status) \($0.stage) \($0.progress)" })")
        throw CancellationError()
      }
      try await Task.sleep(nanoseconds: 100_000_000)
    }
  }

  // Downloads the requests and enqueues a failed one again once, as a user would; the first failure is printed.
  private func download(
    _ requests: [DownloadRequest], whileRunning: (([DownloadTask]) async throws -> Void)? = nil
  ) async throws -> (tasks: [DownloadTask], stages: [Set<TaskStage>]) {
    var hook = whileRunning
    let ids = await repository.enqueue(requests)
    let first = try await finish(ids, whileRunning: &hook)
    var tasks = first.tasks
    var stagesByRequest = ids.map { first.stages[$0] ?? [] }
    let failed = tasks.indices.filter { Self.retryable(tasks[$0]) }
    if !failed.isEmpty {
      for index in failed {
        print("M4 retry \(requests[index].quality) after \(tasks[index].errorCode ?? ""): \(tasks[index].errorMessage ?? "")")
      }
      let retried = await repository.enqueue(failed.map { requests[$0] })
      let again = try await finish(retried, whileRunning: &hook)
      for (slot, index) in failed.enumerated() {
        tasks[index] = again.tasks[slot]
        stagesByRequest[index] = again.stages[retried[slot]] ?? []
      }
    }
    for task in tasks {
      XCTAssertEqual(task.status, .completed, "\(task.request.quality): \(task.errorCode ?? "") \(task.errorMessage ?? "")")
    }
    XCTAssertNil(hook, "the downloads finished before they were all seen running")
    return (tasks, stagesByRequest)
  }

  // Polls until `done` holds for the tasks of `ids`. A task that fails retryably is retried once (Retry keeps a
  // failed task's partial files) and its first failure printed; any other failure ends the test.
  @discardableResult
  private func until(
    _ ids: [String], file: StaticString = #filePath, line: UInt = #line, _ done: ([DownloadTask]) -> Bool
  ) async throws -> [DownloadTask] {
    let deadline = Date().addingTimeInterval(Self.timeout)
    while true {
      let all = await repository.tasks
      let tasks = ids.compactMap { id in all.first { $0.id == id } }
      if tasks.count == ids.count, done(tasks) { return tasks }
      for task in tasks where task.status == .failed {
        guard Self.retryable(task), !retried.contains(task.id) else {
          XCTFail("failed: \(task.errorCode ?? "") \(task.errorMessage ?? "")", file: file, line: line)
          throw CancellationError()
        }
        print("M5 retry \(task.request.quality) after \(task.errorCode ?? ""): \(task.errorMessage ?? "")")
        retried.insert(task.id)
        await repository.retry(task.id)
      }
      if Date() > deadline {
        XCTFail("timed out: \(tasks.map { "\($0.status) \($0.stage) \($0.progress)" })", file: file, line: line)
        throw CancellationError()
      }
      try await Task.sleep(nanoseconds: 100_000_000)
    }
  }

  private func task(_ id: String) async -> DownloadTask? { await repository.tasks.first { $0.id == id } }

  private func taskDir(_ id: String) -> URL { caches.appendingPathComponent("tasks/\(id)", isDirectory: true) }

  private func names(in dir: URL) -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).sorted()
  }

  private func partBytes(_ id: String) -> Int64 {
    names(in: taskDir(id)).filter { $0.hasSuffix(".part") }.reduce(0) { sum, name in
      let path = taskDir(id).appendingPathComponent(name).path
      return sum + ((try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64) ?? 0)
    }
  }

  private static func ms(since start: Date) -> Int { Int(Date().timeIntervalSince(start) * 1000) }

  private func file(_ task: DownloadTask?) throws -> URL {
    let uri = try XCTUnwrap(task?.savedUri.flatMap(URL.init(string:)), "no saved file")
    XCTAssertTrue(FileManager.default.fileExists(atPath: uri.path), uri.path)
    XCTAssertTrue(uri.path.hasPrefix(documents.path), uri.path)
    return uri
  }

  private func streams(_ file: URL) async throws -> [[String: Any]] {
    let reply = try await PythonRuntime.shared.call(
      "debug_ffmpeg",
      ["probe": true, "argv": ["-hide_banner", "-show_streams", "-print_format", "json", file.path], "task": "m4-probe"])
    let out = try XCTUnwrap((reply as? [String: Any])?["out"] as? String, "\(reply)")
    let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: Any], out)
    return json["streams"] as? [[String: Any]] ?? []
  }

  private func assertMp4At720(_ task: DownloadTask?) async throws {
    let mp4 = try file(task)
    XCTAssertEqual(mp4.pathExtension, "mp4")
    XCTAssertEqual(task?.savedPath, "Movies/Fetchr")
    let streams = try await streams(mp4)
    let video = streams.filter { $0["codec_type"] as? String == "video" }
    let audio = streams.filter { $0["codec_type"] as? String == "audio" }
    XCTAssertEqual(video.count, 1, "\(streams)")
    XCTAssertEqual(video.first?["codec_name"] as? String, "h264")
    XCTAssertEqual(video.first?["height"] as? Int, 720)
    XCTAssertEqual(audio.count, 1, "\(streams)")
    XCTAssertEqual(audio.first?["codec_name"] as? String, "aac")
  }

  private func assertMp3(_ task: DownloadTask?, stages: Set<TaskStage>?) async throws {
    let mp3 = try file(task)
    XCTAssertEqual(mp3.pathExtension, "mp3")
    XCTAssertEqual(task?.savedPath, "Music/Fetchr")
    XCTAssertTrue(mp3.path.contains("/Documents/Music/Fetchr/"), mp3.path)
    XCTAssertTrue(stages?.contains(.postProcessing) == true, "stages seen: \(stages ?? [])")
    let streams = try await streams(mp3)
    XCTAssertEqual(streams.compactMap { $0["codec_name"] as? String }, ["mp3"])
  }

  func testDirectMp4Downloads() async throws {
    let began = Date()
    let (tasks, _) = try await download([request(Self.flower, .best)])
    print("M4 direct mp4: \(Self.ms(since: began)) ms")
    let mp4 = try file(tasks.first)
    XCTAssertTrue(mp4.path.contains("/Documents/Movies/Fetchr/"), mp4.path)
    let duration = try await AVURLAsset(url: mp4).load(.duration)
    XCTAssertGreaterThan(duration.seconds, 0)
  }

  func testYouTube720MergesToMp4() async throws {
    let began = Date()
    let (tasks, stages) = try await download([request(Self.youtube, .p720)])
    print("M4 youtube 720p: \(Self.ms(since: began)) ms, stages \(stages.first ?? [])")
    try await assertMp4At720(tasks.first)
  }

  func testYouTubeMp3() async throws {
    let began = Date()
    let (tasks, stages) = try await download([request(Self.youtube, .mp3)])
    print("M4 youtube mp3: \(Self.ms(since: began)) ms")
    try await assertMp3(tasks.first, stages: stages.first)
  }

  func testInfoWhileTwoDownloadsRun() async throws {
    let began = Date()
    var infoMs = -1
    let (tasks, stages) = try await download([request(Self.youtube, .p720), request(Self.youtube, .mp3)]) { _ in
      let asked = Date()
      let info = try await HostApi(python: PythonRuntime.shared, cacheDir: self.caches).fetchInfo(url: Self.flower)
      infoMs = Self.ms(since: asked)
      XCTAssertFalse(info.options.isEmpty)
    }
    print("M4 info while two downloads run: fetchInfo \(infoMs) ms; both downloads \(Self.ms(since: began)) ms")
    XCTAssertGreaterThanOrEqual(infoMs, 0)
    XCTAssertLessThan(infoMs, 10_000)
    try await assertMp4At720(tasks.first)
    try await assertMp3(tasks.last, stages: stages.last)
  }

  func testPauseResumeAcrossRestartContinuesThePartFile() async throws {
    let began = Date()
    let id = try firstOf(await repository.enqueue([request(Self.youtube, .p720)]))
    let atPause = try firstOf(
      try await until([id]) { $0[0].status == .running && ($0[0].downloadedBytes ?? 0) >= 5 * Self.megabyte })
    await repository.pause(id)
    let pausedTask = await task(id)
    let paused = try XCTUnwrap(pausedTask)
    XCTAssertEqual(paused.status, .paused)
    let pausedBytes = try XCTUnwrap(paused.downloadedBytes)
    XCTAssertGreaterThanOrEqual(pausedBytes, atPause.downloadedBytes ?? 0)
    print("M5 paused at \(pausedBytes) bytes after \(Self.ms(since: began)) ms")

    // The restart: the pause sent Python a cancel, so the old attempt unwinds; then the repository goes.
    let unwind = Date()
    await repository.waitUntilIdle()
    let partBefore = partBytes(id)
    XCTAssertGreaterThan(partBefore, 0, "no .part in the task dir: \(names(in: taskDir(id)))")
    print("M5 old attempt unwound in \(Self.ms(since: unwind)) ms; .part holds \(partBefore) bytes")
    store.waitForPendingWrites()
    weak var dropped = repository
    repository = makeRepository()
    let gone = Date().addingTimeInterval(5)
    while dropped != nil, Date() < gone { try await Task.sleep(nanoseconds: 10_000_000) }
    XCTAssertNil(dropped, "the first repository outlived the restart")

    let loadedTask = await task(id)
    let loaded = try XCTUnwrap(loadedTask)
    XCTAssertEqual(loaded.status, .paused)
    XCTAssertEqual(loaded.progress, paused.progress)
    XCTAssertEqual(loaded.downloadedBytes, pausedBytes)

    router.reset()
    let resumed = Date()
    await repository.resume(id)
    let done = try firstOf(try await until([id]) { $0[0].status == .completed })
    let firstBytes = try XCTUnwrap(router.firstDownloaded(id), "no progress event after the resume")
    print(
      "M5 resume: first event at \(firstBytes) bytes (paused at \(pausedBytes)); completed \(Self.ms(since: resumed)) ms"
        + " after the resume, \(Self.ms(since: began)) ms in all; Python runs \(python.downloads)")
    XCTAssertGreaterThanOrEqual(firstBytes, pausedBytes - Self.megabyte, "the resume started the file again")
    try await assertMp4At720(done)
  }

  func testCancelThenRetryStartsFromZeroAndCompletes() async throws {
    let began = Date()
    // The cancel lands while the run is mid-download: Python waits on its first progress event until it is settled.
    let canceledAt = Recorded<Int64>()
    router.onNextProgress { [repository = repository!] id in
      let settled = DispatchSemaphore(value: 0)
      Task {
        await repository.cancel(id)
        if let at = await repository.tasks.first(where: { $0.id == id })?.finishedAtMs { canceledAt.set(at) }
        settled.signal()
      }
      _ = settled.wait(timeout: .now() + 10)
    }
    let id = try firstOf(await repository.enqueue([request(Self.flower, .best)]))
    let canceled = try firstOf(try await until([id]) { [.canceled, .completed].contains($0[0].status) })
    XCTAssertEqual(canceled.status, .canceled)
    XCTAssertNotNil(canceledAt.value, "not canceled from its first progress event")
    await repository.waitUntilIdle()
    XCTAssertFalse(FileManager.default.fileExists(atPath: taskDir(id).path), "the canceled task's dir is left")
    let folder = documents.appendingPathComponent("Movies/Fetchr", isDirectory: true)
    XCTAssertEqual(names(in: folder), [], "a canceled run saved a file")
    print("M5 canceled mid-download after \(Self.ms(since: began)) ms")

    router.reset()
    await repository.retry(id)
    let requeuedTask = await task(id)
    let requeued = try XCTUnwrap(requeuedTask)
    XCTAssertTrue(requeued.isLive)
    XCTAssertNil(requeued.downloadedBytes)
    XCTAssertLessThanOrEqual(requeued.progress, 0)
    let done = try firstOf(try await until([id]) { $0[0].status == .completed })
    let firstBytes = try XCTUnwrap(router.firstDownloaded(id), "no progress event after the retry")
    let total = try XCTUnwrap(done.totalBytes)
    print("M5 cancel then retry: \(Self.ms(since: began)) ms; first event after retry at \(firstBytes) of \(total) bytes")
    // The cancel landed at the first block, so a retry that kept that .part would still be tiny; the bound is set
    // well under the file size to catch a retry that found the file, and the dir-gone check above catches the rest.
    XCTAssertLessThanOrEqual(firstBytes, 64 * 1024, "the retry did not start from zero (\(firstBytes) of \(total))")
    XCTAssertEqual(python.downloads.filter { $0.hasPrefix(id) }.prefix(2), ["\(id)#1", "\(id)#2"])
    let mp4 = try file(done)
    XCTAssertEqual(names(in: folder), [mp4.lastPathComponent])
    let duration = try await AVURLAsset(url: mp4).load(.duration)
    XCTAssertGreaterThan(duration.seconds, 0)
  }

  func testTenQueuedRespectReorder() async throws {
    let began = Date()
    let ids = await repository.enqueue((0..<10).map { _ in request(Self.flower, .best) })
    let waiting = Array(ids[2...])
    let before = await repository.tasks
    XCTAssertEqual(before.filter { waiting.contains($0.id) }.map(\.status), Array(repeating: .queued, count: 8))
    await repository.reorder(waiting.reversed())
    let reordered = await repository.tasks.map(\.id)
    XCTAssertEqual(reordered, Array(ids[..<2]) + waiting.reversed())

    let tasks = try await until(ids) { $0.allSatisfy { $0.status == .completed } }
    print("M5 ten queued: \(Self.ms(since: began)) ms; \(retried.count) retried")
    let firstStarts = python.downloads.filter { $0.hasSuffix("#1") }.map(DownloadRepository.taskId(of:))
    XCTAssertEqual(firstStarts.count, 10, "\(python.downloads)")
    XCTAssertEqual(Set(firstStarts.prefix(2)), Set(ids[..<2]))
    XCTAssertEqual(Array(firstStarts.dropFirst(2)), waiting.reversed(), "the 8 queued did not start in the new order")

    let saved = try tasks.map { try file($0).lastPathComponent }
    let first = try XCTUnwrap(tasks.compactMap { $0.savedUri.flatMap(URL.init(string:)) }.first)
    let stem = first.deletingPathExtension().lastPathComponent.replacingOccurrences(
      of: #" \(\d+\)$"#, with: "", options: .regularExpression)
    XCTAssertTrue(stem.hasPrefix("flower"), stem)
    let expected = ["\(stem).mp4"] + (1...9).map { "\(stem) (\($0)).mp4" }
    print("M5 ten queued saved \(expected.first ?? "") to \(expected.last ?? "")")
    XCTAssertEqual(Set(saved), Set(expected))
    XCTAssertEqual(names(in: documents.appendingPathComponent("Movies/Fetchr")), expected.sorted())
  }
}
