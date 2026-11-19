import Foundation

// A launch's yt-dlp work once Python is up: the selftest that marks the chosen version good or bad, then Android's
// daily update. `ytDlpStatus` waits for it a little, so the status never shows a check about to change.
final class YtDlpStartup: @unchecked Sendable {
  private let lock = NSLock()
  private var job: Task<Void, Never>?

  // The job is stored before it runs, so a status call that comes after never misses it.
  func begin(_ body: @escaping @Sendable () async -> Void) {
    lock.withLock { job = Task(priority: .utility) { await body() } }
  }

  // Stops waiting at the timeout; the job itself goes on.
  func wait(timeout: TimeInterval) async {
    guard let job = lock.withLock({ job }) else { return }
    let once = Once()
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      once.set(continuation)
      let sleeper = Task {
        try? await Task.sleep(nanoseconds: UInt64(max(0, timeout) * 1e9))
        once.resume()
      }
      Task {
        await job.value
        sleeper.cancel()
        once.resume()
      }
    }
  }

  static func run(python: PythonCalling, updater: YtDlpUpdater) async {
    let began = Date()
    let result: SelftestResult
    do {
      result = SelftestResult(reply: try await python.call("selftest", [:]))
    } catch {
      result = SelftestResult(ok: false, version: nil, reason: (error as? BridgeError)?.message ?? "\(error)")
    }
    let elapsed = Int(Date().timeIntervalSince(began) * 1000)
    Log.ytdlp.notice("yt-dlp selftest answered in \(elapsed) ms (including boot)")
    updater.recordLaunch(result)
    // As on Android, a yt-dlp that never started is not updated: the next launch runs another copy first.
    guard let running = result.version else { return }
    let due = YtDlpSchedule.isDue(
      lastCheckedMs: updater.checkedAtMs ?? 0, nowMs: Date().epochMs,
      enabled: updater.autoUpdate)
    guard due else { return }
    do {
      let installed = try await updater.update(running: running)
      Log.ytdlp.notice("yt-dlp auto-update checked: \(installed, privacy: .public) for the next launch")
    } catch {
      Log.ytdlp.error("yt-dlp auto-update skipped: \(String(describing: error), privacy: .public)")
    }
  }
}

private final class Once: @unchecked Sendable {
  private let lock = NSLock()
  private var continuation: CheckedContinuation<Void, Never>?
  private var done = false

  func set(_ continuation: CheckedContinuation<Void, Never>) {
    let resumeNow = lock.withLock { () -> Bool in
      if done { return true }
      self.continuation = continuation
      return false
    }
    if resumeNow { continuation.resume() }
  }

  func resume() {
    let pending = lock.withLock { () -> CheckedContinuation<Void, Never>? in
      done = true
      defer { continuation = nil }
      return continuation
    }
    pending?.resume()
  }
}
