import XCTest
@testable import Runner

// Ports TaskCodecTest.kt. iOS stores the saved file relative to Documents instead of a savedUri, and a live task
// comes back paused instead of failed "Interrupted".
final class TaskCodecTests: XCTestCase {
  private let errorCodes = [
    "unsupported_site", "invalid_url", "private_video", "unavailable", "network", "no_storage", "permission_denied",
    "busy", "no_folder_app", "unknown",
  ]

  private let request = DownloadRequest(
    url: "https://example.com/watch?v=abc", title: "A \"quoted\" title\nwith newline",
    thumbnail: "https://example.com/t.jpg", quality: .p720, folder: "Fetchr", useAria2c: true)

  private func stored(
    id: String = "t1",
    status: TaskStatus = .completed,
    progress: Double = 1,
    etaSeconds: Int64 = 0,
    errorCode: String? = nil,
    errorMessage: String? = nil,
    savedFile: String? = "Movies/Fetchr/Road trip/A title.mp4",
    savedPath: String? = "Movies/Fetchr/Road trip",
    request: DownloadRequest? = nil,
    stage: TaskStage = .preparing,
    downloadedBytes: Int64? = nil,
    totalBytes: Int64? = nil,
    speedBytesPerSec: Int64? = nil,
    stalled: Bool = false,
    finishedAtMs: Int64? = nil,
    createdAtMs: Int64 = 1_760_000_000_123
  ) -> StoredTask {
    StoredTask(
      task: TaskFixtures.task(
        id: id, request: request ?? self.request, status: status, progress: progress, etaSeconds: etaSeconds,
        stage: stage, downloadedBytes: downloadedBytes, totalBytes: totalBytes, speedBytesPerSec: speedBytesPerSec,
        stalled: stalled, errorCode: errorCode, errorMessage: errorMessage, savedPath: savedPath,
        finishedAtMs: finishedAtMs, createdAtMs: createdAtMs),
      savedFile: savedFile)
  }

  private func roundTrip(_ tasks: [StoredTask]) -> [StoredTask] {
    TaskCodec.decode(TaskCodec.encode(tasks)!)
  }

  private func text(_ data: Data?) -> String { String(decoding: data ?? Data(), as: UTF8.self) }

  private func decode(_ json: String) -> [StoredTask] { TaskCodec.decode(Data(json.utf8)) }

  func testRoundTripsEveryField() {
    var mp3 = request
    mp3.thumbnail = nil
    mp3.quality = .mp3
    mp3.useAria2c = false
    let tasks = [
      stored(),
      stored(
        id: "t2", status: .failed, progress: 0.37, etaSeconds: -1, errorCode: "private_video",
        errorMessage: "Private video", savedFile: nil, request: mp3),
      stored(id: "t3", status: .canceled, progress: -1, etaSeconds: -1, savedFile: nil),
    ]

    XCTAssertEqual(roundTrip(tasks), tasks)
  }

  func testRoundTripsACoverTask() {
    var coverRequest = request
    coverRequest.quality = .cover
    coverRequest.useAria2c = false
    let cover = stored(id: "cover", savedFile: "Pictures/Fetchr/A title.jpg", request: coverRequest)

    let decoded = roundTrip([cover])

    XCTAssertEqual(decoded, [cover])
    XCTAssertEqual(decoded.first?.task.request.quality, .cover)
  }

  func testRoundTripsEveryEnumValue() {
    let qualities = Quality.allCases.enumerated().map { i, quality -> StoredTask in
      var r = request
      r.quality = quality
      return stored(id: "q\(i)", request: r)
    }
    let failures = errorCodes.enumerated().map { i, code in
      stored(id: "e\(i)", status: .failed, errorCode: code, errorMessage: "m", savedFile: nil)
    }
    let statuses = [TaskStatus.completed, .failed, .canceled, .paused].map {
      stored(id: "s\($0.rawValue)", status: $0, savedFile: nil)
    }
    let tasks = qualities + failures + statuses

    XCTAssertEqual(roundTrip(tasks), tasks)
  }

  func testEnumsAreStoredByKotlinName() {
    var r = request
    r.quality = .p1080
    let json = text(TaskCodec.encode([stored(status: .paused, request: r, stage: .postProcessing)]))

    XCTAssertTrue(json.contains("\"P1080\""), json)
    XCTAssertTrue(json.contains("\"PAUSED\""), json)
    XCTAssertTrue(json.contains("\"POST_PROCESSING\""), json)
    let android = """
      [{"id":"a","status":"FAILED","progress":0.5,"etaSeconds":-1,"createdAtMs":5,"stage":"DOWNLOADING",
      "request":{"url":"https://example.com/a","title":"A","quality":"BEST","folder":"Fetchr","useAria2c":true}}]
      """
    let decoded = decode(android).first?.task
    XCTAssertEqual(decoded?.status, .failed)
    XCTAssertEqual(decoded?.stage, .downloading)
    XCTAssertEqual(decoded?.request.quality, .best)
  }

  func testEmptyListRoundTrips() {
    XCTAssertEqual(roundTrip([]), [])
  }

  func testKeepsOrder() {
    let tasks = [stored(id: "c"), stored(id: "a"), stored(id: "b")]

    XCTAssertEqual(roundTrip(tasks).map(\.task.id), ["c", "a", "b"])
  }

  func testSortsNewestFirstKeepingTiesInStoredOrder() {
    let tasks = [
      stored(id: "old", createdAtMs: 10), stored(id: "new-b", createdAtMs: 30), stored(id: "mid", createdAtMs: 20),
      stored(id: "new-a", createdAtMs: 30),
    ]

    XCTAssertEqual(roundTrip(tasks).map(\.task.id), ["new-b", "new-a", "mid", "old"])
  }

  func testNullOptionalsStayNull() {
    var bareRequest = request
    bareRequest.thumbnail = nil
    let bare = stored(status: .failed, savedFile: nil, savedPath: nil, request: bareRequest)

    let decoded = roundTrip([bare]).first

    XCTAssertNil(decoded?.task.request.thumbnail)
    XCTAssertNil(decoded?.task.errorCode)
    XCTAssertNil(decoded?.task.errorMessage)
    XCTAssertNil(decoded?.task.savedUri)
    XCTAssertNil(decoded?.task.savedPath)
    XCTAssertNil(decoded?.savedFile)
    XCTAssertFalse(text(TaskCodec.encode([bare])).contains("null"))
  }

  func testQueuedAndRunningLoadAsPaused() {
    let tasks = [
      stored(id: "q", status: .queued, progress: -1, etaSeconds: -1, savedFile: nil, savedPath: nil),
      stored(
        id: "r", status: .running, progress: 0.5, etaSeconds: 30, savedFile: nil, savedPath: nil,
        speedBytesPerSec: 2_500_000),
    ]

    let decoded = roundTrip(tasks).map(\.task)

    XCTAssertEqual(decoded.map(\.id), ["q", "r"])
    XCTAssertEqual(decoded.map(\.progress), [0, 0.5])
    for task in decoded {
      XCTAssertEqual(task.status, .paused)
      XCTAssertEqual(task.etaSeconds, -1)
      XCTAssertNil(task.speedBytesPerSec)
      XCTAssertNil(task.errorCode)
      XCTAssertNil(task.errorMessage)
      XCTAssertEqual(task.request, request)
    }
  }

  func testPausedTaskKeepsItsProgressAndBytes() {
    let paused = stored(
      id: "p", status: .paused, progress: 0.42, savedFile: nil, stage: .downloading, downloadedBytes: 44_040_192,
      totalBytes: 104_857_600, finishedAtMs: 1_760_000_100_000)

    let decoded = roundTrip([paused])

    XCTAssertEqual(decoded, [paused])
    XCTAssertEqual(decoded.first?.task.status, .paused)
  }

  func testEveryStageAndFinishTimeRoundTrips() {
    let tasks = TaskStage.allCases.enumerated().map { i, stage in
      stored(
        id: "s\(i)", status: .failed, errorCode: "network", errorMessage: "m", savedFile: nil, stage: stage,
        downloadedBytes: 1_000 * Int64(i), totalBytes: 5_000_000_000, speedBytesPerSec: 2_500_000,
        finishedAtMs: 1_760_000_200_000 + Int64(i))
    }

    XCTAssertEqual(roundTrip(tasks), tasks)
  }

  func testRequestMetadataRoundTrips() {
    var r = request
    r.uploader = "Blender"
    r.durationSeconds = 635
    r.playlistTitle = "Shorts"
    r.playlistIndex = 2
    r.playlistCount = 17
    let withMeta = stored(request: r)

    XCTAssertEqual(roundTrip([withMeta]), [withMeta])
  }

  func testLargeIntegersRoundTripExactly() {
    // 2^53 + 1 is the first integer a Double cannot hold.
    let big: Int64 = 9_007_199_254_740_993
    let task = stored(
      status: .paused, downloadedBytes: big, totalBytes: .max, speedBytesPerSec: big - 2, finishedAtMs: big + 2,
      createdAtMs: 1_760_000_000_123)

    let decoded = roundTrip([task])

    XCTAssertEqual(decoded, [task])
    XCTAssertEqual(decoded.first?.task.downloadedBytes, big)
    XCTAssertEqual(decoded.first?.task.totalBytes, .max)
    XCTAssertTrue(text(TaskCodec.encode([task])).contains("1760000000123"))
  }

  func testJsonWrittenBeforeTheNewKeysDecodesWithDefaults() {
    let old = """
      [{"id":"old","status":"COMPLETED","progress":1,"etaSeconds":0,
      "savedUri":"file:///old/container/Documents/Movies/Fetchr/a.mp4","createdAtMs":1760000000123,
      "request":{"url":"https://example.com/a","title":"Old","quality":"P720","folder":"Fetchr","useAria2c":false}}]
      """

    let decoded = decode(old).first

    XCTAssertEqual(decoded?.task.status, .completed)
    XCTAssertEqual(decoded?.task.progress, 1)
    XCTAssertEqual(decoded?.task.createdAtMs, 1_760_000_000_123)
    XCTAssertEqual(decoded?.task.stage, .preparing)
    XCTAssertNil(decoded?.task.savedUri)
    XCTAssertNil(decoded?.savedFile)
    XCTAssertNil(decoded?.task.savedPath)
    XCTAssertNil(decoded?.task.downloadedBytes)
    XCTAssertNil(decoded?.task.totalBytes)
    XCTAssertNil(decoded?.task.speedBytesPerSec)
    XCTAssertNil(decoded?.task.finishedAtMs)
    XCTAssertEqual(decoded?.task.stalled, false)
    XCTAssertNil(decoded?.task.request.uploader)
    XCTAssertNil(decoded?.task.request.durationSeconds)
    XCTAssertNil(decoded?.task.request.playlistTitle)
    XCTAssertNil(decoded?.task.request.playlistIndex)
    XCTAssertNil(decoded?.task.request.playlistCount)
  }

  func testStalledIsNeverPersisted() {
    let stalled = stored(status: .paused, savedFile: nil, stalled: true)

    let json = TaskCodec.encode([stalled])!

    XCTAssertFalse(text(json).contains("stalled"))
    XCTAssertEqual(TaskCodec.decode(json).first?.task.stalled, false)
  }

  func testPausedOnRestartKeepsItsBytesSoResumeContinues() {
    let running = stored(
      status: .running, progress: 0.5, savedFile: nil, savedPath: nil, stage: .downloading,
      downloadedBytes: 52_428_800, totalBytes: 104_857_600)

    let decoded = roundTrip([running]).first?.task

    XCTAssertEqual(decoded?.status, .paused)
    XCTAssertEqual(decoded?.progress, 0.5)
    XCTAssertEqual(decoded?.stage, .downloading)
    XCTAssertEqual(decoded?.downloadedBytes, 52_428_800)
    XCTAssertEqual(decoded?.totalBytes, 104_857_600)
  }

  func testFinishedStatusesAreNotRewritten() {
    let tasks = [stored(id: "ok", status: .completed), stored(id: "no", status: .canceled, savedFile: nil)]

    XCTAssertEqual(roundTrip(tasks), tasks)
  }

  func testCorruptInputLoadsAsEmpty() {
    XCTAssertEqual(decode(""), [])
    XCTAssertEqual(decode("{not json"), [])
    XCTAssertEqual(decode("{\"id\":\"t1\"}"), [])
    XCTAssertEqual(TaskCodec.decode(Data([0xFF, 0xFE, 0x00])), [])
  }

  func testMalformedTaskIsSkippedAndTheRestLoad() {
    let good = text(TaskCodec.encode([stored(id: "good")]))
    let withBad = good.dropLast() + """
      ,{"id":"bad","status":"NOPE"},5,null,"x",{"id":"noRequest","status":"PAUSED","progress":0,"etaSeconds":0,\
      "createdAtMs":1},{"id":"badQuality","status":"PAUSED","progress":0,"etaSeconds":0,"createdAtMs":1,\
      "request":{"url":"u","title":"t","quality":"P2160","folder":"f","useAria2c":false}}]
      """

    XCTAssertEqual(decode(String(withBad)).map(\.task.id), ["good"])
  }

  func testSavedFileRoundTripsAndSavedUriIsNeverWritten() {
    var task = stored(savedFile: "Movies/Fetchr/Shorts/Clip (1).mp4")
    task.task.savedUri = "file:///var/mobile/Containers/Data/Application/X/Documents/Movies/Fetchr/Shorts/Clip%20(1).mp4"

    let json = TaskCodec.encode([task])!
    let decoded = TaskCodec.decode(json).first

    XCTAssertFalse(text(json).contains("savedUri"), text(json))
    // JSONEncoder writes "/" as "\/", so look for a path part without slashes.
    XCTAssertFalse(text(json).contains("Containers"), text(json))
    XCTAssertEqual(decoded?.savedFile, "Movies/Fetchr/Shorts/Clip (1).mp4")
    XCTAssertNil(decoded?.task.savedUri)
    XCTAssertEqual(decoded?.task.savedPath, "Movies/Fetchr/Road trip")
  }
}
