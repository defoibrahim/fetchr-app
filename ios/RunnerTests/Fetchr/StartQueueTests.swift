import XCTest
@testable import Runner

final class StartQueueTests: XCTestCase {
  func testStartsAtMostMaxInAddOrder() {
    var queue = StartQueue(max: 2)
    ["a", "b", "c"].forEach { queue.add($0) }
    XCTAssertEqual(queue.next(), "a")
    XCTAssertEqual(queue.next(), "b")
    XCTAssertNil(queue.next())
    XCTAssertEqual(queue.order, ["c"])

    queue.remove("a")
    XCTAssertEqual(queue.next(), "c")
    XCTAssertNil(queue.next())
    XCTAssertEqual(queue.order, [])
  }

  func testNextOnAnEmptyQueueTakesNoSlot() {
    var queue = StartQueue(max: 1)
    XCTAssertNil(queue.next())
    queue.add("a")
    XCTAssertEqual(queue.next(), "a")
  }

  func testNextSkipsAWaitingRunThatIsNotReadyWithoutLosingItsPlace() {
    var queue = StartQueue(max: 1)
    ["a", "b"].forEach { queue.add($0) }
    XCTAssertEqual(queue.next { $0 != "a" }, "b")
    XCTAssertEqual(queue.order, ["a"])
    XCTAssertNil(queue.next(), "the slot is taken")
    queue.remove("b")
    XCTAssertNil(queue.next { _ in false })
    XCTAssertEqual(queue.next(), "a")
  }

  func testReorderChangesWhichWaitingRunStartsNext() {
    var queue = StartQueue(max: 1)
    ["a", "b", "c", "d"].forEach { queue.add($0) }
    XCTAssertEqual(queue.next(), "a")

    queue.reorder(taskIds: ["d", "b"], taskOf: { $0 })
    XCTAssertEqual(queue.order, ["d", "c", "b"])

    queue.remove("a")
    XCTAssertEqual(queue.next(), "d")
  }

  // A key names one run; the task id it belongs to is what the user reorders by.
  func testReorderMatchesKeysByTheirTask() {
    var queue = StartQueue(max: 1)
    ["a#1", "b#1", "c#2"].forEach { queue.add($0) }
    queue.reorder(taskIds: ["c", "b"], taskOf: { String($0.prefix(1)) })
    XCTAssertEqual(queue.order, ["a#1", "c#2", "b#1"])
  }

  func testSwapSlotsMovesOnlyTheMovableItemsOfIds() {
    var list = ["a", "Q1", "b", "Q2", "Q3"]
    list.swapSlots(["Q3", "b", "Q1"], id: { $0 }, movable: { $0.hasPrefix("Q") })
    XCTAssertEqual(list, ["a", "Q3", "b", "Q2", "Q1"])
  }

  func testARemovedWaitingKeyGivesItsPlaceUp() {
    var queue = StartQueue(max: 1)
    ["a", "b", "c"].forEach { queue.add($0) }
    XCTAssertEqual(queue.next(), "a")

    queue.remove("b")
    XCTAssertEqual(queue.order, ["c"])
    queue.remove("gone")
    XCTAssertEqual(queue.order, ["c"])

    queue.remove("a")
    XCTAssertEqual(queue.next(), "c")
  }

  // Only a run that took a slot frees one, and only once: a waiting or unknown key, or a second remove, frees none.
  func testRemovingTwiceOrAnUnknownKeyFreesNoOtherSlot() {
    var queue = StartQueue(max: 1)
    ["a", "b", "c"].forEach { queue.add($0) }
    XCTAssertEqual(queue.next(), "a")
    queue.remove("a")
    XCTAssertEqual(queue.next(), "b")
    queue.remove("a")
    queue.remove("c")
    queue.remove("gone")
    XCTAssertNil(queue.next())
  }
}
