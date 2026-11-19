import XCTest
@testable import Runner

final class TaskProgressTests: XCTestCase {
  private func at(
    _ progress: Double, eta: Int64 = 30, stage: TaskStage = .downloading, stalled: Bool = false
  ) -> DownloadTask {
    TaskFixtures.task(progress: progress, etaSeconds: eta, stage: stage, stalled: stalled)
  }

  func testTinyMoveWithSameEtaIsSkipped() {
    XCTAssertFalse(TaskProgress.changed(at(0.500), at(0.504)))
    XCTAssertFalse(TaskProgress.changed(at(-1, eta: -1), at(-1, eta: -1)))
  }

  func testHalfAPercentMovePasses() {
    XCTAssertTrue(TaskProgress.changed(at(0.50), at(0.51)))
    XCTAssertTrue(TaskProgress.changed(at(0.51), at(0.50)))
  }

  func testNewEtaAlwaysPasses() {
    XCTAssertTrue(TaskProgress.changed(at(0.500), at(0.501, eta: 29)))
    XCTAssertTrue(TaskProgress.changed(at(0.5, eta: -1), at(0.5, eta: 12)))
  }

  func testEnteringOrLeavingUnknownAlwaysPasses() {
    XCTAssertTrue(TaskProgress.changed(at(-1, eta: -1), at(0, eta: -1)))
    XCTAssertTrue(TaskProgress.changed(at(0.001, eta: 5), at(-1, eta: 5)))
  }

  func testANewStagePassesEvenWhenTheBarDidNotMove() {
    XCTAssertTrue(TaskProgress.changed(at(1), at(1, stage: .postProcessing)))
  }

  func testStallingOrRecoveringPassesEvenWhenTheBarDidNotMove() {
    XCTAssertTrue(TaskProgress.changed(at(0.5), at(0.5, stalled: true)))
    XCTAssertTrue(TaskProgress.changed(at(0.5, stalled: true), at(0.5)))
  }

  func testAConversionReadsTheNewestReportBlockAgainstTheDuration() throws {
    let report =
      "out_time_us=N/A\nout_time_ms=N/A\nprogress=continue\n"
      + "out_time_us=30000000\nout_time_ms=30000000\nprogress=continue\n"
      + "out_time_us=90000000\nout_time_ms=90000000\nprogress=continue\n"
    XCTAssertEqual(try XCTUnwrap(TaskProgress.conversion(report: report, durationSeconds: 120)), 0.75, accuracy: 1e-9)
  }

  func testAConversionWithNoReadingOrNoDurationIsUnknown() {
    XCTAssertNil(TaskProgress.conversion(report: "", durationSeconds: 120))
    XCTAssertNil(TaskProgress.conversion(report: "out_time_us=N/A\nprogress=continue\n", durationSeconds: 120))
    XCTAssertNil(TaskProgress.conversion(report: "out_time_us=30000000\n", durationSeconds: 0))
    XCTAssertNil(TaskProgress.conversion(report: "out_time_us=30000000\n", durationSeconds: -5))
  }

  func testAConversionStaysOnTheBar() {
    XCTAssertEqual(TaskProgress.conversion(report: "out_time_us=130000000\nprogress=end\n", durationSeconds: 120), 1)
    XCTAssertEqual(TaskProgress.conversion(report: "out_time_us=-9223372036854775807\n", durationSeconds: 120), 0)
  }

  func testWithConversionOnlyWhileRunningPostProcessingAndMoved() throws {
    let converting = TaskFixtures.task(progress: -1, stage: .postProcessing)
    XCTAssertEqual(try XCTUnwrap(converting.withConversion(0.5)).progress, 0.5)
    XCTAssertNil(TaskFixtures.task(stage: .downloading).withConversion(0.5))
    XCTAssertNil(TaskFixtures.task(status: .paused, stage: .postProcessing).withConversion(0.5))
    XCTAssertNil(TaskFixtures.task(progress: 0.5, stage: .postProcessing).withConversion(0.501), "a tick under the step")
  }
}
