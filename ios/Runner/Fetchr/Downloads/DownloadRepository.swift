import Foundation

// Owns the task list. Every attempt of a task runs under its own run key "<taskId>#<attempt>", which is the
// Python task id, the emit id and the owner token: only the task's current attempt may change it.
actor DownloadRepository {
  enum Command {
    case cancel(String), pause(String), resume(String), retry(String), pauseAll, resumeAll, reorder([String])
  }

  private enum Inbox {
    case enqueue([DownloadRequest])
    case event(runKey: String, json: String)
    case command(Command)
  }

  private enum Work {
    case attempt(runKey: String, DownloadRequest)
    case discardDir
  }

  let python: PythonCalling
  let documents: URL
  let cachesDir: URL
  // Where the picker's copies live; nil accepts library files only as convert sources.
  let pickedDir: URL?
  // Held across every Python download call, so a yt-dlp update never swaps yt-dlp under one.
  let gate: RunGate
  private let store: TaskPersisting?
  private let stallAfter: TimeInterval
  let conversionPoll: TimeInterval
  let now: () -> Date
  // Deletes the task dirs no loaded task goes on from; every work on a task waits for it.
  private let cleanup: Task<Void, Never>?
  // One ordered channel into the actor for callers that cannot await: separate Tasks would not keep the order.
  private nonisolated let inbox: AsyncStream<Inbox>.Continuation

  private var list: [DownloadTask] = []
  // A completed task's file relative to Documents. Its absolute URL is set on the task, never stored, because the
  // app container's path changes between installs.
  var savedFiles: [String: String] = [:]
  private var queue = StartQueue(max: 2)
  private var attempts: [String: Int] = [:]
  // The attempt that owns each task; absent once it ended or was abandoned.
  private var current: [String: String] = [:]
  // Run keys whose download call is in Python, the only ones a Python cancel can reach, with when each last showed
  // a sign of life (the call itself, then every event): the stall check reads it.
  var inPython: [String: Date] = [:]
  // The newest work on each task; the next one awaits it, so two attempts never share the task dir at once.
  private var tails: [String: (token: UUID, task: Task<Void, Never>)] = [:]
  private var subscribers: [UUID: AsyncStream<[DownloadTask]>.Continuation] = [:]

  // `store` nil keeps the list in memory only. Loaded tasks come back as their restart state, and none starts.
  init(
    python: PythonCalling, documents: URL, cachesDir: URL, store: TaskPersisting? = nil, pickedDir: URL? = nil,
    gate: RunGate = RunGate(),
    stallCheck: TimeInterval = 5, stallAfter: TimeInterval = 30, conversionPoll: TimeInterval = 0.5,
    now: @escaping () -> Date = Date.init
  ) {
    self.python = python
    self.documents = documents
    self.cachesDir = cachesDir
    self.pickedDir = pickedDir
    self.gate = gate
    self.store = store
    self.stallAfter = stallAfter
    self.conversionPoll = conversionPoll
    self.now = now
    let loaded = store?.load() ?? []
    let restored = loaded.map { stored in
      var task = stored.task
      if task.status == .completed { task.savedUri = stored.savedFile.map { Self.uri(of: $0, in: documents) } }
      return task
    }
    list = restored
    savedFiles = Dictionary(
      loaded.compactMap { stored in stored.savedFile.map { (stored.task.id, $0) } }, uniquingKeysWith: { a, _ in a })
    // A killed process leaves dirs behind. Only the dirs listed now are candidates, and a paused or failed task keeps
    // its own: Resume and Retry go on from its partial files.
    let tasksDir = cachesDir.appendingPathComponent("tasks", isDirectory: true)
    let orphans = TempDirs.orphans(
      (try? FileManager.default.contentsOfDirectory(atPath: tasksDir.path)) ?? [], tasks: restored)
    let pickedOrphans = (pickedDir.map { picked in
      LocalVideo.orphans(in: picked, tasks: restored, documents: documents).map { picked.appendingPathComponent($0) }
    }) ?? []
    cleanup = orphans.isEmpty && pickedOrphans.isEmpty ? nil : Task.detached(priority: .utility) {
      for name in orphans { try? FileManager.default.removeItem(at: tasksDir.appendingPathComponent(name)) }
      for entry in pickedOrphans { try? FileManager.default.removeItem(at: entry) }
    }
    let (stream, continuation) = AsyncStream<Inbox>.makeStream()
    inbox = continuation
    Task { [weak self] in
      for await item in stream {
        await self?.handle(item)
      }
    }
    let interval = UInt64(stallCheck * 1e9)
    Task { [weak self] in
      while true {
        try? await Task.sleep(nanoseconds: interval)
        guard let self else { return }
        await self.checkStalls()
      }
    }
  }

  deinit {
    inbox.finish()
  }

  var tasks: [DownloadTask] { list }

  // Newest first. Each subscriber gets the list at once, then the latest list after every change.
  var snapshots: AsyncStream<[DownloadTask]> {
    let (stream, continuation) = AsyncStream<[DownloadTask]>.makeStream(bufferingPolicy: .bufferingNewest(1))
    let id = UUID()
    subscribers[id] = continuation
    continuation.onTermination = { [weak self] _ in
      Task { await self?.unsubscribe(id) }
    }
    continuation.yield(tasks)
    return stream
  }

  @discardableResult
  func enqueue(_ requests: [DownloadRequest]) -> [String] {
    guard !requests.isEmpty else { return [] }
    let createdAt = now().epochMs
    let added = requests.map {
      DownloadTask(
        id: UUID().uuidString, request: $0, status: .queued, progress: -1, etaSeconds: -1, createdAtMs: createdAt,
        stage: .preparing, stalled: false)
    }
    list = added + list
    publish()
    persist()
    added.forEach { newAttempt($0.id) }
    pump()
    return added.map(\.id)
  }

  nonisolated func submit(_ requests: [DownloadRequest]) {
    inbox.yield(.enqueue(requests))
  }

  nonisolated func send(_ command: Command) {
    inbox.yield(.command(command))
  }

  // The emit handler: called on Python's thread with the run key, so it only queues the event.
  nonisolated func receive(taskId runKey: String, json: String) {
    inbox.yield(.event(runKey: runKey, json: json))
  }

  func cancel(_ id: String) {
    let canceledAt = now().epochMs
    guard settle(id, { TaskTransitions.cancel($0, nowMs: canceledAt) }) else { return }
    abandon(id)
    chain(id, .discardDir)
  }

  func pause(_ id: String) {
    guard settle(id, TaskTransitions.pause) else { return }
    abandon(id)
  }

  func resume(_ id: String) { relaunch(id, TaskTransitions.resume) }

  func retry(_ id: String) { relaunch(id, TaskTransitions.retry) }

  // Every task is paused before any attempt gives its slot up, so no queued task starts on the way, and a playlist
  // writes the list once instead of once per video.
  func pauseAll() {
    let paused = settleAll(TaskTransitions.pause)
    paused.forEach(abandon)
  }

  func resumeAll() {
    let resumed = settleAll(TaskTransitions.resume)
    resumed.forEach(newAttempt)
    pump()
  }

  // The queued tasks of `ids` start in that order, and the list shows them so: they swap the places they hold.
  func reorder(_ ids: [String]) {
    queue.reorder(taskIds: ids, taskOf: Self.taskId(of:))
    let before = list
    list.swapSlots(ids, id: \.id) { $0.status == .queued }
    if list != before { publish() }
  }

  // No consent dialog on iOS, so this never returns false; a file that cannot be deleted throws and keeps the task.
  func remove(_ id: String) throws -> Bool {
    guard let task = list.first(where: { $0.id == id }) else { return true }
    // On the actor, like every save, so a playlist folder is never pruned while a save moves a file into it.
    if task.status == .completed, let file = savedFiles[id] {
      try SaveLocation.deleteSaved(file, documents: documents)
    }
    list.removeAll { $0.id == id }
    savedFiles[id] = nil
    attempts[id] = nil
    discardPicked(task.request)
    abandon(id)
    chain(id, .discardDir)
    publish()
    persist()
    return true
  }

  // A picked copy goes when the task converting it completes or is removed, unless another task still to finish
  // converts the same copy. A library source is never touched.
  func discardPicked(_ req: DownloadRequest) {
    guard let picked = pickedDir, LocalVideo.isLocal(req.url),
      let source = LocalVideo.resolve(req.url, documents: documents, picked: picked), source.isPicked
    else { return }
    let needed = list.contains { task in
      task.status != .completed && LocalVideo.isLocal(task.request.url)
        && LocalVideo.resolve(task.request.url, documents: documents, picked: picked)?.file.path == source.file.path
    }
    if !needed { LocalVideo.deletePicked(source, picked: picked) }
  }

  // A file deleted from the library: the completed tasks that saved it go too, as on Android.
  func forgetSaved(relativeFile: String) {
    let ids = Set(list.filter { $0.status == .completed && savedFiles[$0.id] == relativeFile }.map(\.id))
    guard !ids.isEmpty else { return }
    list.removeAll { ids.contains($0.id) }
    for id in ids {
      savedFiles[id] = nil
      attempts[id] = nil
    }
    publish()
    persist()
  }

  // `delete` runs on the actor for the same reason as `remove`'s, and returns the file it deleted, relative to
  // Documents. A delete that throws forgets nothing.
  func deleteFromLibrary(_ delete: @Sendable () throws -> String) throws {
    forgetSaved(relativeFile: try delete())
  }

  // Awaits every attempt and dir cleanup started so far, including the abandoned ones still unwinding.
  func waitUntilIdle() async {
    while let tail = tails.values.first {
      await tail.task.value
    }
  }

  private func handle(_ item: Inbox) {
    switch item {
    case .enqueue(let requests): enqueue(requests)
    case .event(let key, let json): apply(key, json)
    case .command(let command):
      switch command {
      case .cancel(let id): cancel(id)
      case .pause(let id): pause(id)
      case .resume(let id): resume(id)
      case .retry(let id): retry(id)
      case .pauseAll: pauseAll()
      case .resumeAll: resumeAll()
      case .reorder(let ids): reorder(ids)
      }
    }
  }

  private func relaunch(_ id: String, _ rule: (DownloadTask) -> DownloadTask?) {
    guard settle(id, rule) else { return }
    newAttempt(id)
    pump()
  }

  private func newAttempt(_ id: String) {
    let attempt = (attempts[id] ?? 0) + 1
    attempts[id] = attempt
    let key = "\(id)#\(attempt)"
    current[id] = key
    queue.add(key)
  }

  // The attempt stops owning the task and gives its slot up now; its Python call unwinds in the background.
  private func abandon(_ id: String) {
    guard let key = current.removeValue(forKey: id) else { return }
    queue.remove(key)
    if inPython[key] != nil {
      let python = self.python
      Task.detached {
        _ = try? await python.call("cancel", ["task": key])
      }
    }
    pump()
  }

  // A run whose task still has work in progress (an abandoned attempt unwinding, its dir being discarded) stays
  // queued at its place without a slot; the end of that work pumps again.
  private func pump() {
    while true {
      let busy = tails
      guard let key = queue.next(where: { busy[Self.taskId(of: $0)] == nil }) else { return }
      let id = Self.taskId(of: key)
      guard current[id] == key, let req = list.first(where: { $0.id == id })?.request,
        transition(id, TaskTransitions.start)
      else {
        queue.remove(key)
        if current[id] == key { current[id] = nil }
        continue
      }
      chain(id, .attempt(runKey: key, req))
    }
  }

  private func chain(_ id: String, _ work: Work) {
    let previous = tails[id]?.task
    let token = UUID()
    let task = Task {
      await cleanup?.value
      await previous?.value
      switch work {
      case .attempt(let key, let req): await execute(key, req)
      case .discardDir: await removeDir(id)
      }
      if tails[id]?.token == token {
        tails[id] = nil
        pump()
      }
    }
    tails[id] = (token, task)
  }

  func task(_ id: String) -> DownloadTask? { list.first { $0.id == id } }

  func owns(_ key: String) -> Bool { current[Self.taskId(of: key)] == key }

  // The attempt's own end; a no-op for an attempt that was abandoned, so a slot is freed once.
  func release(_ key: String) {
    let id = Self.taskId(of: key)
    guard current[id] == key else { return }
    current[id] = nil
    queue.remove(key)
    pump()
  }

  // A paused or failed task, or one queued again, goes on from the files left in its dir.
  func keepsDir(_ id: String) -> Bool {
    guard let task = list.first(where: { $0.id == id }) else { return false }
    return TaskTransitions.keepsPartialFiles(task.status) || task.status == .queued
  }

  func taskDir(_ id: String) -> URL {
    cachesDir.appendingPathComponent("tasks/\(id)", isDirectory: true)
  }

  func removeDir(_ id: String) async {
    let dir = taskDir(id)
    await Task.detached(priority: .utility) {
      try? FileManager.default.removeItem(at: dir)
    }.value
  }

  private func apply(_ key: String, _ json: String) {
    guard owns(key) else { return }
    if inPython[key] != nil { inPython[key] = now() }
    guard let event = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] else { return }
    transition(Self.taskId(of: key)) { task in
      // The run's reply can reach the actor before Python's last emits, so only a running task takes them.
      guard task.status == .running else { return nil }
      var next = task
      next.stalled = false
      switch event["type"] as? String {
      case "progress":
        let downloaded = Self.int64(event["downloaded"])
        let total = Self.int64(event["total"])
        next.stage = .downloading
        next.downloadedBytes = downloaded
        next.totalBytes = total
        if let downloaded, let total, total > 0 {
          next.progress = min(1, Double(downloaded) / Double(total))
        } else {
          next.progress = -1
        }
        next.speedBytesPerSec = Self.int64(event["speed"])
        next.etaSeconds = Self.int64(event["eta"]) ?? -1
      case "stage" where event["stage"] as? String == "postProcessing":
        next.stage = .postProcessing
        next.progress = -1
        next.etaSeconds = -1
        next.speedBytesPerSec = nil
      default:
        break
      }
      return TaskProgress.changed(task, next) ? next : nil
    }
  }

  // A running attempt silent for `stallAfter` is flagged, except while ffmpeg post-processes: it prints nothing then.
  private func checkStalls() {
    let at = now()
    for (key, last) in inPython where owns(key) {
      let silent = at.timeIntervalSince(last) >= stallAfter
      transition(Self.taskId(of: key)) { task in
        let stalled = silent && task.stage != .postProcessing
        guard task.status == .running, stalled != task.stalled else { return nil }
        var next = task
        next.stalled = stalled
        return next
      }
    }
  }

  // `rule` applied to every task it fits, published and persisted once; the ids it changed, in list order.
  private func settleAll(_ rule: (DownloadTask) -> DownloadTask?) -> [String] {
    var changed: [String] = []
    for index in list.indices {
      guard let next = rule(list[index]) else { continue }
      list[index] = next
      changed.append(next.id)
    }
    if !changed.isEmpty {
      publish()
      persist()
    }
    return changed
  }

  // A status change, persisted. A rule returns nil when it does not apply to the task as it now is.
  @discardableResult
  func settle(_ id: String, _ rule: (DownloadTask) -> DownloadTask?) -> Bool {
    guard transition(id, rule) else { return false }
    persist()
    return true
  }

  // Not for a start or a progress tick: a restart loads a running task as paused, at the progress the list held
  // at its last write.
  private func persist() {
    store?.save(list.map { StoredTask(task: $0, savedFile: $0.status == .completed ? savedFiles[$0.id] : nil) })
  }

  @discardableResult
  func transition(_ id: String, _ rule: (DownloadTask) -> DownloadTask?) -> Bool {
    guard let index = list.firstIndex(where: { $0.id == id }), let next = rule(list[index]) else { return false }
    list[index] = next
    publish()
    return true
  }

  private func publish() {
    guard !subscribers.isEmpty else { return }
    let snapshot = tasks
    for subscriber in subscribers.values {
      subscriber.yield(snapshot)
    }
  }

  private func unsubscribe(_ id: UUID) {
    subscribers[id] = nil
  }

  func withUri(_ task: DownloadTask) -> DownloadTask {
    guard task.status == .completed, let file = savedFiles[task.id] else { return task }
    var copy = task
    copy.savedUri = Self.uri(of: file, in: documents)
    return copy
  }

  private static func uri(of file: String, in documents: URL) -> String {
    documents.appendingPathComponent(file, isDirectory: false).absoluteString
  }

  static func taskId(of runKey: String) -> String {
    guard let mark = runKey.lastIndex(of: "#") else { return runKey }
    return String(runKey[..<mark])
  }

  private static func int64(_ value: Any?) -> Int64? {
    guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
    let double = number.doubleValue
    guard double.isFinite, abs(double) < 9e18 else { return nil }
    return Int64(double)
  }
}
