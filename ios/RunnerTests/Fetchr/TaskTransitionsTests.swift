import XCTest
@testable import Runner

final class TaskTransitionsTests: XCTestCase {
  private func task(
    status: TaskStatus = .running, progress: Double = 0.4, speedBytesPerSec: Int64? = 5, stalled: Bool = false,
    errorCode: String? = nil, errorMessage: String? = nil, finishedAtMs: Int64? = nil
  ) -> DownloadTask {
    TaskFixtures.task(
      status: status, progress: progress, speedBytesPerSec: speedBytesPerSec, stalled: stalled,
      errorCode: errorCode, errorMessage: errorMessage, finishedAtMs: finishedAtMs)
  }

  private func others(_ keep: TaskStatus...) -> [TaskStatus] { TaskStatus.allCases.filter { !keep.contains($0) } }

  func testPauseFromQueuedAndRunningKeepsProgressAndBytes() throws {
    for from in [TaskStatus.queued, .running] {
      let paused = try XCTUnwrap(TaskTransitions.pause(task(status: from, stalled: true)))
      XCTAssertEqual(paused.status, .paused)
      XCTAssertEqual(paused.progress, 0.4)
      XCTAssertEqual(paused.downloadedBytes, 40)
      XCTAssertEqual(paused.totalBytes, 100)
      XCTAssertEqual(paused.stage, .downloading)
      XCTAssertNil(paused.speedBytesPerSec)
      XCTAssertEqual(paused.etaSeconds, -1)
      XCTAssertFalse(paused.stalled)
    }
  }

  func testPausedProgressIsNeverNegative() throws {
    XCTAssertEqual(try XCTUnwrap(TaskTransitions.pause(task(progress: -1))).progress, 0)
  }

  func testPauseFromAnyOtherStatusIsRejected() {
    for from in others(.queued, .running) {
      XCTAssertNil(TaskTransitions.pause(task(status: from)), "\(from)")
    }
  }

  func testResumeOnlyFromPausedKeepingProgress() throws {
    let resumed = try XCTUnwrap(TaskTransitions.resume(task(status: .paused, speedBytesPerSec: nil)))
    XCTAssertEqual(resumed.status, .queued)
    XCTAssertEqual(resumed.progress, 0.4)
    XCTAssertEqual(resumed.downloadedBytes, 40)
    for from in others(.paused) {
      XCTAssertNil(TaskTransitions.resume(task(status: from)), "\(from)")
    }
  }

  func testRetryFailedKeepsProgressAndBytesAndClearsTheError() throws {
    let failed = task(
      status: .failed, speedBytesPerSec: nil, errorCode: "network", errorMessage: "Connection dropped",
      finishedAtMs: 9)
    let retried = try XCTUnwrap(TaskTransitions.retry(failed))
    XCTAssertEqual(retried.status, .queued)
    XCTAssertEqual(retried.progress, 0.4)
    XCTAssertEqual(retried.downloadedBytes, 40)
    XCTAssertEqual(retried.totalBytes, 100)
    XCTAssertNil(retried.errorCode)
    XCTAssertNil(retried.errorMessage)
    XCTAssertNil(retried.finishedAtMs)
    XCTAssertEqual(retried.etaSeconds, -1)
  }

  func testRetryCanceledStartsFromZero() throws {
    let retried = try XCTUnwrap(TaskTransitions.retry(task(status: .canceled, finishedAtMs: 9)))
    XCTAssertEqual(retried.status, .queued)
    XCTAssertEqual(retried.progress, 0)
    XCTAssertNil(retried.downloadedBytes)
    XCTAssertNil(retried.totalBytes)
    XCTAssertNil(retried.finishedAtMs)
    XCTAssertEqual(retried.stage, .preparing)
  }

  func testRetryFromAnyOtherStatusIsRejected() {
    for from in others(.failed, .canceled) {
      XCTAssertNil(TaskTransitions.retry(task(status: from)), "\(from)")
    }
  }

  func testRetriedProgressIsNeverNegative() throws {
    XCTAssertEqual(try XCTUnwrap(TaskTransitions.retry(task(status: .failed, progress: -1))).progress, 0)
  }

  func testCancelStampsTheFinishTime() throws {
    for from in [TaskStatus.queued, .running, .paused] {
      let canceled = try XCTUnwrap(TaskTransitions.cancel(task(status: from, stalled: true), nowMs: 77))
      XCTAssertEqual(canceled.status, .canceled)
      XCTAssertEqual(canceled.finishedAtMs, 77)
      XCTAssertEqual(canceled.etaSeconds, -1)
      XCTAssertNil(canceled.speedBytesPerSec)
      XCTAssertFalse(canceled.stalled)
    }
    for from in others(.queued, .running, .paused) {
      XCTAssertNil(TaskTransitions.cancel(task(status: from), nowMs: 77), "\(from)")
    }
  }

  func testRestartPausesLiveTasksOnly() {
    for from in [TaskStatus.queued, .running] {
      for progress in [0.4, -1] {
        let paused = TaskTransitions.onRestart(task(status: from, progress: progress, stalled: true, finishedAtMs: 9))
        XCTAssertEqual(paused.status, .paused, "\(from)")
        XCTAssertEqual(paused.progress, max(0, progress))
        XCTAssertEqual(paused.downloadedBytes, 40)
        XCTAssertEqual(paused.totalBytes, 100)
        XCTAssertEqual(paused.finishedAtMs, 9)
        XCTAssertNil(paused.errorCode)
        XCTAssertNil(paused.errorMessage)
        XCTAssertEqual(paused.etaSeconds, -1)
        XCTAssertNil(paused.speedBytesPerSec)
        XCTAssertFalse(paused.stalled)
      }
    }
    for from in others(.queued, .running) {
      let t = task(status: from)
      XCTAssertEqual(TaskTransitions.onRestart(t), t, "\(from)")
    }
  }

  func testStartTakesOnlyAQueuedTaskAndKeepsAResumedPercent() throws {
    let started = try XCTUnwrap(TaskTransitions.start(task(status: .queued, progress: 0.41, stalled: true)))
    XCTAssertEqual(started.status, .running)
    XCTAssertEqual(started.progress, 0.41)
    XCTAssertEqual(started.stage, .preparing)
    XCTAssertFalse(started.stalled)
    XCTAssertEqual(try XCTUnwrap(TaskTransitions.start(task(status: .queued, progress: 0))).progress, -1)
    for from in others(.queued) {
      XCTAssertNil(TaskTransitions.start(task(status: from)), "\(from)")
    }
  }

  func testCompleteLandsFromAnyUnfinishedStatusOnly() throws {
    for from in [TaskStatus.running, .paused, .queued] {
      let done = try XCTUnwrap(
        TaskTransitions.complete(
          task(status: from, errorCode: "network"), savedPath: "Movies/Fetchr", bytes: 90, nowMs: 7))
      XCTAssertEqual(done.status, .completed)
      XCTAssertNil(done.savedUri)
      XCTAssertEqual(done.savedPath, "Movies/Fetchr")
      XCTAssertEqual(done.progress, 1)
      XCTAssertEqual(done.etaSeconds, 0)
      XCTAssertEqual(done.downloadedBytes, 90)
      XCTAssertEqual(done.totalBytes, 90)
      XCTAssertEqual(done.finishedAtMs, 7)
      XCTAssertNil(done.errorCode)
      XCTAssertNil(done.speedBytesPerSec)
    }
    for from in [TaskStatus.canceled, .failed, .completed] {
      XCTAssertNil(
        TaskTransitions.complete(task(status: from), savedPath: "Movies/Fetchr", bytes: 90, nowMs: 7), "\(from)")
    }
  }

  func testFailKeepsBytesAndStampsTheCallersTime() throws {
    let failed = try XCTUnwrap(
      TaskTransitions.fail(task(stalled: true), code: "network", message: "Connection dropped", finishedAtMs: 9))
    XCTAssertEqual(failed.status, .failed)
    XCTAssertEqual(failed.errorCode, "network")
    XCTAssertEqual(failed.errorMessage, "Connection dropped")
    XCTAssertEqual(failed.finishedAtMs, 9)
    XCTAssertEqual(failed.progress, 0.4)
    XCTAssertEqual(failed.downloadedBytes, 40)
    XCTAssertEqual(failed.etaSeconds, -1)
    XCTAssertNil(failed.speedBytesPerSec)
    XCTAssertFalse(failed.stalled)
  }

  func testFailOnlyAppliesToLiveTasks() {
    for from in [TaskStatus.paused, .completed, .failed, .canceled] {
      XCTAssertNil(TaskTransitions.fail(task(status: from), code: "network", message: nil, finishedAtMs: 9), "\(from)")
    }
  }

  func testOnlyLiveAndPausedTasksAreUnfinished() {
    for s in TaskStatus.allCases {
      XCTAssertEqual(TaskTransitions.isUnfinished(task(status: s)), [.queued, .running, .paused].contains(s), "\(s)")
      XCTAssertEqual(task(status: s).isLive, [.queued, .running].contains(s), "\(s)")
    }
  }

  func testOnlyPausedAndFailedKeepPartialFiles() {
    for s in TaskStatus.allCases {
      XCTAssertEqual(TaskTransitions.keepsPartialFiles(s), s == .paused || s == .failed, "\(s)")
    }
  }
}
