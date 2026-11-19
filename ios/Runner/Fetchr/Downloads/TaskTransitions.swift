extension DownloadTask {
  var isLive: Bool { status == .queued || status == .running }

  // A paused or re-queued task shows its percent, so an unknown one (-1) reads as 0.
  fileprivate var knownProgress: Double { max(0, progress) }

  // Nothing is transferring any more.
  fileprivate func halted() -> DownloadTask {
    var t = self
    t.etaSeconds = -1
    t.speedBytesPerSec = nil
    t.stalled = false
    return t
  }
}

// Each rule returns nil when the task is not in a status it applies to.
enum TaskTransitions {
  static func isUnfinished(_ t: DownloadTask) -> Bool { t.isLive || t.status == .paused }

  // A resumed task keeps the percent it stopped at until the first event moves it.
  static func start(_ t: DownloadTask) -> DownloadTask? {
    guard t.status == .queued else { return nil }
    var next = t.halted()
    next.status = .running
    next.progress = t.progress > 0 ? t.progress : -1
    next.stage = .preparing
    return next
  }

  // A pause or a resume may have moved the task while the file was saved; a cancel or a remove keeps its outcome.
  // No savedUri: the repository sets it from the stored relative file.
  static func complete(_ t: DownloadTask, savedPath: String, bytes: Int64, nowMs: Int64) -> DownloadTask? {
    guard isUnfinished(t) else { return nil }
    var next = t.halted()
    next.status = .completed
    next.progress = 1
    next.etaSeconds = 0
    next.downloadedBytes = bytes
    next.totalBytes = bytes
    next.errorCode = nil
    next.errorMessage = nil
    next.savedUri = nil
    next.savedPath = savedPath
    next.finishedAtMs = nowMs
    return next
  }

  static func fail(_ t: DownloadTask, code: String, message: String?, finishedAtMs: Int64?) -> DownloadTask? {
    guard t.isLive else { return nil }
    var next = t.halted()
    next.status = .failed
    next.errorCode = code
    next.errorMessage = message
    next.finishedAtMs = finishedAtMs
    return next
  }

  static func pause(_ t: DownloadTask) -> DownloadTask? {
    guard t.isLive else { return nil }
    var next = t.halted()
    next.status = .paused
    next.progress = t.knownProgress
    return next
  }

  static func resume(_ t: DownloadTask) -> DownloadTask? {
    guard t.status == .paused else { return nil }
    var next = t
    next.status = .queued
    return next
  }

  static func retry(_ t: DownloadTask) -> DownloadTask? {
    switch t.status {
    case .failed:
      var next = requeued(t)
      next.progress = t.knownProgress
      return next
    case .canceled:
      var next = requeued(t)
      next.progress = 0
      next.downloadedBytes = nil
      next.totalBytes = nil
      next.stage = .preparing
      return next
    default:
      return nil
    }
  }

  static func cancel(_ t: DownloadTask, nowMs: Int64) -> DownloadTask? {
    guard isUnfinished(t) else { return nil }
    var next = t.halted()
    next.status = .canceled
    next.finishedAtMs = nowMs
    return next
  }

  // Unlike Android, a run killed with the app comes back paused: its partial files are still in its task dir.
  static func onRestart(_ t: DownloadTask) -> DownloadTask { pause(t) ?? t }

  static func keepsPartialFiles(_ status: TaskStatus) -> Bool { status == .paused || status == .failed }

  private static func requeued(_ t: DownloadTask) -> DownloadTask {
    var next = t.halted()
    next.status = .queued
    next.errorCode = nil
    next.errorMessage = nil
    next.savedUri = nil
    next.savedPath = nil
    next.finishedAtMs = nil
    return next
  }
}
