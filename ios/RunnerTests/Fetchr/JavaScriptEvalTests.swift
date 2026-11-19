import XCTest
@testable import Runner

final class JavaScriptEvalTests: XCTestCase {
  private func eval(_ src: String) async throws -> String? {
    try await PythonRuntime.shared.call("debug_js", ["src": src]) as? String
  }

  private func assertFails(_ src: String, contains expected: String, file: StaticString = #filePath, line: UInt = #line) async {
    do {
      _ = try await eval(src)
      XCTFail("evaluation of \(src) did not fail", file: file, line: line)
    } catch let error as BridgeError {
      XCTAssertTrue(error.message.contains(expected), error.message, file: file, line: line)
    } catch {
      XCTFail("unexpected \(error)", file: file, line: line)
    }
  }

  func testEvaluatesExpression() async throws {
    let value = try await eval("1 + 2")
    XCTAssertEqual(value, "3")
  }

  func testReturnsUnicode() async throws {
    let value = try await eval("'é' + '😀'")
    XCTAssertEqual(value, "é😀")
  }

  func testExceptionBecomesBridgeError() async {
    await assertFails("throw new TypeError('boom')", contains: "TypeError: boom")
  }

  func testCallsAreIsolated() async throws {
    _ = try await eval("globalThis.x = 1; 0")
    let value = try await eval("typeof x")
    XCTAssertEqual(value, "undefined")
  }

  // A YouTube player is a few MB of source; each solve parses one in a fresh context.
  func testLargeSourceManyTimes() async throws {
    let padding = String(repeating: "x", count: 3 << 20)
    let src = "var pad = '\(padding)'; var s = 0; for (var i = 0; i < 100000; i++) s += i % 7; pad.length + ':' + s"
    for round in 0..<20 {
      let value = try await eval(src)
      XCTAssertEqual(value, "\(3 << 20):299995", "round \(round)")
    }
  }

  func testSyntaxErrorBecomesBridgeError() async {
    await assertFails("(", contains: "SyntaxError")
  }
}
