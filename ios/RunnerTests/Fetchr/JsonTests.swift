import XCTest
@testable import Runner

final class JsonTests: XCTestCase {
  private func object(_ json: String) throws -> JSONObject { try JSONObject.parse(json) }

  func testNullAndMissingReadAsAbsent() throws {
    let o = try object(#"{"s":null,"n":null}"#)
    XCTAssertNil(o.str("s"))
    XCTAssertNil(o.num("n"))
    XCTAssertNil(o.long("missing"))
    XCTAssertFalse(o.bool("missing"))
    XCTAssertEqual([], o.objects("missing").map { $0.str("x") })
  }

  func testLongRoundsHalfUpLikeKotlin() throws {
    let o = try object(#"{"a":213.886,"b":2.5,"c":2.4999,"d":-2.5}"#)
    XCTAssertEqual(214, o.long("a"))
    XCTAssertEqual(3, o.long("b"))
    XCTAssertEqual(2, o.long("c"))
    XCTAssertEqual(-2, o.long("d"))
  }

  func testBooleansAreNotNumbersAndNumbersAreNotBooleans() throws {
    let o = try object(#"{"t":true,"one":1,"text":"TRUE"}"#)
    XCTAssertNil(o.num("t"))
    XCTAssertTrue(o.bool("t"))
    XCTAssertFalse(o.bool("one"))
    XCTAssertEqual(1, o.num("one"))
    XCTAssertTrue(o.bool("text"))
  }

  func testObjectsSkipsItemsThatAreNotObjects() throws {
    let o = try object(#"{"a":[{"x":"1"},null,2,"s",[],{"x":"2"}],"b":{"x":"3"}}"#)
    XCTAssertEqual(["1", "2"], o.objects("a").map { $0.str("x") })
    XCTAssertTrue(o.objects("b").isEmpty)
  }
}
