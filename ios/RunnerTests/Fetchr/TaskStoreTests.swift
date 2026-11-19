import XCTest
@testable import Runner

final class TaskStoreTests: XCTestCase {
  private var dir: URL!
  private var url: URL { dir.appendingPathComponent("Application Support/downloads.json") }

  override func setUpWithError() throws {
    dir = FileManager.default.temporaryDirectory.appendingPathComponent("TaskStoreTests-\(UUID().uuidString)")
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: dir)
  }

  private func stored(_ id: String, status: TaskStatus = .completed, createdAtMs: Int64 = 1) -> StoredTask {
    StoredTask(
      task: TaskFixtures.task(id: id, status: status, savedPath: "Movies/Fetchr", createdAtMs: createdAtMs),
      savedFile: status == .completed ? "Movies/Fetchr/\(id).mp4" : nil)
  }

  private func write(_ json: String) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(json.utf8).write(to: url)
  }

  func testSaveThenLoadRoundTrips() {
    let tasks = [stored("b", createdAtMs: 2), stored("a", status: .paused), stored("c", status: .failed)]
    let store = TaskStore(url: url)

    store.save(tasks)
    store.waitForPendingWrites()

    XCTAssertEqual(store.load(), tasks)
    XCTAssertEqual(TaskStore(url: url).load(), tasks)
  }

  func testLoadAppliesTheRestartRule() {
    let store = TaskStore(url: url)

    store.save([stored("r", status: .running)])
    store.waitForPendingWrites()

    XCTAssertEqual(store.load().map(\.task.status), [.paused])
  }

  func testMissingStoreLoadsEmpty() {
    XCTAssertEqual(TaskStore(url: url).load(), [])
  }

  func testCorruptStoreLoadsEmpty() throws {
    try write("[{\"id\":\"half-writ")
    let store = TaskStore(url: url)

    XCTAssertEqual(store.load(), [])

    store.save([stored("next")])
    store.waitForPendingWrites()
    XCTAssertEqual(TaskStore(url: url).load().map(\.task.id), ["next"])
  }

  func testMalformedTaskIsSkipped() throws {
    let good = String(decoding: TaskCodec.encode([stored("good")])!, as: UTF8.self)
    try write(String(good.dropLast()) + ",{\"id\":\"bad\",\"status\":\"NOPE\"}]")
    let store = TaskStore(url: url)

    let loaded = store.load()
    XCTAssertEqual(loaded.map(\.task.id), ["good"])

    store.save(loaded)
    store.waitForPendingWrites()
    let rewritten = try String(contentsOf: url, encoding: .utf8)
    XCTAssertFalse(rewritten.contains("bad"), rewritten)
  }

  func testRapidSavesEndWithTheLastList() {
    let store = TaskStore(url: url)
    let lists = (1...100).map { n in (0..<n).map { stored("t\($0)", createdAtMs: Int64(n - $0)) } }

    for list in lists { store.save(list) }
    store.waitForPendingWrites()

    XCTAssertEqual(TaskStore(url: url).load(), lists[99])
  }

  func testSavesFromManyThreadsEndWithTheLastOne() {
    let store = TaskStore(url: url)
    DispatchQueue.concurrentPerform(iterations: 50) { i in store.save([stored("t\(i)")]) }
    let last = [stored("last")]

    store.save(last)
    store.waitForPendingWrites()

    XCTAssertEqual(TaskStore(url: url).load(), last)
  }

  func testApplicationSupportDirExistsAndIsExcludedFromBackup() throws {
    let appSupport = Paths.applicationSupportDir
    var isDir: ObjCBool = false

    XCTAssertTrue(FileManager.default.fileExists(atPath: appSupport.path, isDirectory: &isDir))
    XCTAssertTrue(isDir.boolValue)
    XCTAssertEqual(appSupport.lastPathComponent, "Application Support")
    let values = try URL(fileURLWithPath: appSupport.path).resourceValues(forKeys: [.isExcludedFromBackupKey])
    XCTAssertEqual(values.isExcludedFromBackup, true)
  }
}
