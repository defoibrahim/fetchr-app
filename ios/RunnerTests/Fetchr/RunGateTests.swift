import XCTest
@testable import Runner

// Kotlin's RunGateTest.
final class RunGateTests: XCTestCase {
  private func swapError(_ gate: RunGate) async -> String? {
    do {
      try await gate.beginSwap()
      return nil
    } catch {
      return (error as? FetchrError)?.code ?? "\(error)"
    }
  }

  func testSwapIsBusyWhileARunIsActive() async {
    let gate = RunGate()
    await gate.enter()
    let busy = await swapError(gate)
    XCTAssertEqual(busy, "busy")
    await gate.leave()
    let free = await swapError(gate)
    XCTAssertNil(free)
  }

  func testSecondSwapIsBusy() async throws {
    let gate = RunGate()
    try await gate.beginSwap()
    let second = await swapError(gate)
    XCTAssertEqual(second, "busy")
  }

  func testEnterWaitsUntilTheSwapEnds() async throws {
    let gate = RunGate()
    try await gate.beginSwap()
    let entered = Flag()
    let run = Task {
      await gate.enter()
      entered.set()
    }
    try await Task.sleep(nanoseconds: 100_000_000)
    XCTAssertFalse(entered.value)
    await gate.endSwap()
    await run.value
    XCTAssertTrue(entered.value)
    let busy = await swapError(gate)
    XCTAssertEqual(busy, "busy", "the run that waited is now active")
  }

  func testGatedCallHoldsTheGateUntilPythonReturns() async throws {
    let gate = RunGate()
    let python = FakePython()
    let hold = Gate()
    python.hold = { _ in await hold.wait() }
    let call = Task { try await python.call("info", [:], gate: gate) }
    try await waitUntil { python.calls.count == 1 }
    let busy = await swapError(gate)
    XCTAssertEqual(busy, "busy")
    hold.release()
    _ = try await call.value
    let free = await swapError(gate)
    XCTAssertNil(free)
  }

  // Attempts that start while an update installs wait in enter(); paused or canceled there, they never call Python
  // and leave no run behind.
  func testAttemptAbandonedWhileWaitingLeavesNoRunBehind() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("gate-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let documents = root.appendingPathComponent("Documents")
    let caches = root.appendingPathComponent("Caches")
    try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
    let gate = RunGate()
    try await gate.beginSwap()
    let downloads = FakeDownloads()
    let repository = DownloadRepository(python: downloads, documents: documents, cachesDir: caches, gate: gate)
    downloads.repository = repository
    let ids = await repository.enqueue([downloadRequest(), downloadRequest()])
    _ = try await waitFor(repository) { $0.allSatisfy { $0.status == .running } }
    try await Task.sleep(nanoseconds: 100_000_000)
    await repository.pause(ids[0])
    await repository.cancel(ids[1])
    await gate.endSwap()
    await repository.waitUntilIdle()
    XCTAssertEqual(downloads.runs.count, 0, "neither called Python")
    let free = await swapError(gate)
    XCTAssertNil(free, "the gate is not left held")
  }

  func testGatedCallThatThrowsLeavesTheGate() async throws {
    let gate = RunGate()
    let python = FakePython()
    python.reply = { _ in throw BridgeError(hint: nil, message: "boom") }
    do {
      _ = try await python.call("info", [:], gate: gate)
      XCTFail("expected a failure")
    } catch {}
    let free = await swapError(gate)
    XCTAssertNil(free)
  }
}

final class Flag: @unchecked Sendable {
  private let lock = NSLock()
  private var raised = false
  var value: Bool { lock.withLock { raised } }
  func set() { lock.withLock { raised = true } }
}

func waitUntil(
  timeout: TimeInterval = 5, file: StaticString = #filePath, line: UInt = #line, _ condition: () async -> Bool
) async throws {
  let deadline = Date().addingTimeInterval(timeout)
  while await !condition() {
    if Date() > deadline {
      XCTFail("timed out", file: file, line: line)
      throw CancellationError()
    }
    try await Task.sleep(nanoseconds: 10_000_000)
  }
}
