import XCTest
@testable import Runner

final class TempDirsTests: XCTestCase {
  func testKeepsDirsOfPausedAndFailedTasks() {
    let tasks = [TaskFixtures.task(id: "paused", status: .paused), TaskFixtures.task(id: "failed", status: .failed)]
    XCTAssertEqual(TempDirs.orphans(["paused", "failed"], tasks: tasks), [])
  }

  func testDeletesDirsOfEveryOtherStatusAndUnknownIds() {
    let tasks = [
      TaskFixtures.task(id: "done", status: .completed),
      TaskFixtures.task(id: "canceled", status: .canceled),
      TaskFixtures.task(id: "queued", status: .queued),
      TaskFixtures.task(id: "kept", status: .paused),
    ]
    XCTAssertEqual(
      TempDirs.orphans(["done", "canceled", "queued", "kept", "gone"], tasks: tasks),
      ["done", "canceled", "queued", "gone"])
  }

  func testNoDirsMeansNothingToDelete() {
    XCTAssertEqual(TempDirs.orphans([], tasks: [TaskFixtures.task()]), [])
  }
}
