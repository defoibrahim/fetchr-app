import XCTest

private final class FixtureBundle {}

// The InfoParser fixtures the Kotlin tests use, bundled as RunnerTests' `info` folder.
func infoFixture(_ name: String, file: StaticString = #filePath, line: UInt = #line) throws -> String {
  let url = try XCTUnwrap(
    Bundle(for: FixtureBundle.self).url(forResource: name, withExtension: "json", subdirectory: "info"),
    "missing fixture \(name)", file: file, line: line)
  return try String(contentsOf: url, encoding: .utf8)
}
