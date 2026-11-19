import XCTest
@testable import Runner

final class PythonRuntimeTests: XCTestCase {
  private static let okReply = #"{"ok":true,"value":"done"}"#

  func testPingReturnsYtDlpVersion() async throws {
    let value = try await PythonRuntime.shared.call("ping", [:])
    XCTAssertEqual(value as? [String: String], ["ytDlpVersion": "2026.10.26"])
  }

  func testCallBeforeReadyWaits() async throws {
    let booted = Flag()
    let runtime = PythonRuntime(
      boot: { _ in
        Thread.sleep(forTimeInterval: 0.3)
        booted.set()
        return nil
      },
      call: { _, _ in
        XCTAssertTrue(booted.value, "called Python before boot finished")
        return Self.okReply
      })
    runtime.start()
    let started = Date()
    let value = try await runtime.call("ping", [:])
    XCTAssertEqual(value as? String, "done")
    XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(started), 0.2)
  }

  func testBootFailureSurfacesAsUnknown() async throws {
    let runtime = PythonRuntime(boot: { _ in "boom" }, call: { _, _ in Self.okReply })
    runtime.start()
    for _ in 0..<2 {
      do {
        _ = try await runtime.call("ping", [:])
        XCTFail("call after a failed boot returned")
      } catch let error as BridgeError {
        XCTAssertTrue(error.message.hasPrefix("Python failed to start"), error.message)
        XCTAssertTrue(error.message.contains("boom"), error.message)
        XCTAssertEqual(ErrorClassifier.classify(error).code, "unknown")
      }
    }
  }

  func testCallsNeverRunOnTheMainThread() async throws {
    let runtime = PythonRuntime(
      boot: { _ in nil },
      call: { _, _ in
        XCTAssertFalse(Thread.isMainThread)
        return Self.okReply
      })
    runtime.start()
    _ = try await runtime.call("ping", [:])
  }

  func testCallsRunOnEightMegabyteThreads() async throws {
    let seen = Recorder()
    let runtime = PythonRuntime(
      boot: { _ in nil },
      call: { _, _ in
        seen.set(stack: Thread.current.stackSize, main: Thread.isMainThread)
        return Self.okReply
      })
    runtime.start()
    _ = try await runtime.call("ping", [:])
    XCTAssertGreaterThanOrEqual(seen.stack, 8 << 20)
    XCTAssertFalse(seen.main)
  }

  func testCallsDoNotWaitForEachOther() async throws {
    let runtime = PythonRuntime(
      boot: { _ in nil },
      call: { name, _ in
        if name == "slow" { Thread.sleep(forTimeInterval: 1) }
        return Self.okReply
      })
    runtime.start()
    let slow = (0..<3).map { _ in Task { try await runtime.call("slow", [:]) } }
    try await Task.sleep(nanoseconds: 100_000_000)
    let began = Date()
    _ = try await runtime.call("fast", [:])
    XCTAssertLessThan(Date().timeIntervalSince(began), 0.3)
    for task in slow { _ = try await task.value }
  }

  func testPythonMainThreadIsAlive() async throws {
    let value = try await PythonRuntime.shared.call("debug_main_alive", [:])
    XCTAssertEqual(value as? Bool, true)
  }

  func testConcurrentCalls() async throws {
    let versions = try await withThrowingTaskGroup(of: [String: String]?.self) { group in
      for _ in 0..<8 {
        group.addTask { try await PythonRuntime.shared.call("ping", [:]) as? [String: String] }
      }
      return try await group.reduce(into: []) { $0.append($1) }
    }
    XCTAssertEqual(versions.count, 8)
    XCTAssertTrue(versions.allSatisfy { $0 == ["ytDlpVersion": "2026.10.26"] })
  }

  func testErrorEnvelopeBecomesBridgeError() async throws {
    do {
      _ = try await PythonRuntime.shared.call("nope", [:])
      XCTFail("unknown call returned")
    } catch let error as BridgeError {
      XCTAssertFalse(error.message.isEmpty)
    }
  }

  // A title cut mid-emoji leaves a lone surrogate, which JSONSerialization rejects.
  func testLoneSurrogatesDecodeAsReplacementCharacters() async throws {
    let text = #""broken \ud83d end""#
    let value = try await PythonRuntime.shared.call("debug_echo", ["json": text])
    XCTAssertEqual(value as? String, "broken \u{FFFD} end")
    do {
      _ = try await PythonRuntime.shared.call("debug_echo", ["json": text, "raise": true])
      XCTFail("debug_echo with raise returned")
    } catch let error as BridgeError {
      XCTAssertEqual(error.message, "broken \u{FFFD} end")
    }
  }

  func testEmitReachesHandler() async throws {
    let received = expectation(description: "emit")
    PythonRuntime.setEmitHandler { task, json in
      XCTAssertEqual(task, "t")
      XCTAssertEqual(json, "{}")
      received.fulfill()
    }
    defer { PythonRuntime.setEmitHandler(nil) }
    _ = try await PythonRuntime.shared.call("debug_emit", ["task": "t", "json": "{}"])
    await fulfillment(of: [received], timeout: 5)
  }
}

private final class Recorder: @unchecked Sendable {
  private let lock = NSLock()
  private var _stack = 0
  private var _main = true

  var stack: Int { lock.withLock { _stack } }
  var main: Bool { lock.withLock { _main } }

  func set(stack: Int, main: Bool) { lock.withLock { _stack = stack; _main = main } }
}
