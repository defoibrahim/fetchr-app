import XCTest
@testable import Runner

// Kotlin's YtDlpScheduleTest.
final class YtDlpScheduleTests: XCTestCase {
  private let hour: Int64 = 60 * 60 * 1000
  private let now: Int64 = 1_800_000_000_000

  func testNotDueWhenDisabled() {
    XCTAssertFalse(YtDlpSchedule.isDue(lastCheckedMs: 0, nowMs: now, enabled: false))
    XCTAssertFalse(YtDlpSchedule.isDue(lastCheckedMs: now + hour, nowMs: now, enabled: false))
  }

  func testDueWhenNeverChecked() {
    XCTAssertTrue(YtDlpSchedule.isDue(lastCheckedMs: 0, nowMs: now, enabled: true))
  }

  func testNotDueBeforeTwentyFourHours() {
    XCTAssertFalse(YtDlpSchedule.isDue(lastCheckedMs: now - 23 * hour, nowMs: now, enabled: true))
  }

  func testDueAtTwentyFourHours() {
    XCTAssertTrue(YtDlpSchedule.isDue(lastCheckedMs: now - 24 * hour, nowMs: now, enabled: true))
  }

  func testDueWhenTheClockMovedBack() {
    XCTAssertTrue(YtDlpSchedule.isDue(lastCheckedMs: now + hour, nowMs: now, enabled: true))
  }
}
