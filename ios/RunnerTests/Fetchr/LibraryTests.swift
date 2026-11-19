import XCTest
@testable import Runner

final class LibraryTests: XCTestCase {
  private var root: URL!
  private var documents: URL!
  private var caches: URL!
  private var scratch: URL!

  override func setUpWithError() throws {
    root = FileManager.default.temporaryDirectory.appendingPathComponent("library-\(UUID().uuidString)")
    documents = root.appendingPathComponent("Documents", isDirectory: true)
    caches = root.appendingPathComponent("Caches", isDirectory: true)
    scratch = root.appendingPathComponent("scratch", isDirectory: true)
    for dir in [documents!, caches!, scratch!] {
      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: root)
  }

  private func library() -> Library { Library(documents: documents, caches: caches) }

  private func ffmpeg(_ argv: [String]) async throws {
    let reply = try await PythonRuntime.shared.call("debug_ffmpeg", ["probe": false, "argv": argv, "task": "library"])
    let value = try XCTUnwrap(reply as? [String: Any], "\(reply)")
    XCTAssertEqual(value["rc"] as? Int, 0, value["out"] as? String ?? "")
  }

  // Media is made in a scratch dir and moved in, so a half-written file never sits in the library.
  @discardableResult
  private func video(_ rel: String, seconds: Int = 2, size: String = "320x240", created: Date? = nil) async throws -> URL {
    let tmp = scratch.appendingPathComponent("\(UUID().uuidString).mp4")
    try await ffmpeg([
      "-y", "-f", "lavfi", "-i", "testsrc=duration=\(seconds):size=\(size):rate=30", "-f", "lavfi",
      "-i", "sine=duration=\(seconds)", "-c:v", "mpeg4", "-c:a", "aac", "-shortest", tmp.path,
    ])
    return try place(tmp, at: rel, created: created)
  }

  @discardableResult
  private func audio(_ rel: String, seconds: Int = 2, created: Date? = nil) async throws -> URL {
    let tmp = scratch.appendingPathComponent("\(UUID().uuidString).mp3")
    try await ffmpeg(["-y", "-f", "lavfi", "-i", "sine=duration=\(seconds)", "-c:a", "libmp3lame", "-q:a", "2", tmp.path])
    return try place(tmp, at: rel, created: created)
  }

  private func place(_ file: URL, at rel: String, created: Date?) throws -> URL {
    let target = documents.appendingPathComponent(rel)
    try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? FileManager.default.removeItem(at: target)
    try FileManager.default.moveItem(at: file, to: target)
    if let created {
      try FileManager.default.setAttributes([.creationDate: created], ofItemAtPath: target.path)
    }
    return target
  }

  @discardableResult
  private func write(_ rel: String, _ data: Data = Data("x".utf8)) throws -> URL {
    let target = documents.appendingPathComponent(rel)
    try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: target)
    return target
  }

  private func item(_ items: [Runner.LibraryItem], _ name: String) throws -> Runner.LibraryItem {
    try XCTUnwrap(items.first { $0.name == name }, "no \(name) in \(items.map(\.name))")
  }

  func testListsVideosAndAudioOfTheFolderNewestFirst() async throws {
    let base = Date(timeIntervalSince1970: 1_700_000_000)
    let old = try await video("Movies/Fetchr/old.mp4", created: base)
    try await video("Movies/Fetchr/new.mp4", created: base.addingTimeInterval(200))
    try await audio("Music/Fetchr/song.mp3", created: base.addingTimeInterval(100))
    try await video("Movies/Other/elsewhere.mp4", created: base.addingTimeInterval(300))

    let items = await library().list(folder: "Fetchr")

    XCTAssertEqual(items.map(\.name), ["new.mp4", "song.mp3", "old.mp4"])
    XCTAssertEqual(items.map(\.isAudio), [false, true, false])
    XCTAssertEqual(items.map(\.relativePath), ["Movies/Fetchr/", "Music/Fetchr/", "Movies/Fetchr/"])
    XCTAssertEqual(items.map(\.dateAddedMs), [1_700_000_200_000, 1_700_000_100_000, 1_700_000_000_000])
    let uri = try XCTUnwrap(URL(string: try item(items, "old.mp4").uri))
    XCTAssertTrue(uri.isFileURL)
    XCTAssertEqual(uri.resolvingSymlinksInPath().path, old.resolvingSymlinksInPath().path)
  }

  func testListIncludesPlaylistSubfolders() async throws {
    try await video("Movies/Fetchr/Road trip/01 - a.mp4")

    let items = await library().list(folder: "Fetchr")

    XCTAssertEqual(items.map(\.name), ["01 - a.mp4"])
    XCTAssertEqual(items.first?.relativePath, "Movies/Fetchr/Road trip/")
    XCTAssertEqual(items.first.flatMap { URL(string: $0.uri) }?.lastPathComponent, "01 - a.mp4")
  }

  func testVideoMetadata() async throws {
    let file = try await video("Movies/Fetchr/clip.mp4")

    let clip = try item(await library().list(folder: "Fetchr"), "clip.mp4")

    XCTAssertEqual(clip.width, 320)
    XCTAssertEqual(clip.height, 240)
    let duration = try XCTUnwrap(clip.durationMs)
    XCTAssertTrue((1900...2100).contains(duration), "\(duration)")
    let size = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)
    XCTAssertEqual(clip.sizeBytes, size.int64Value)
    XCTAssertEqual(clip.mimeType, "video/mp4")
    XCTAssertFalse(clip.isAudio)
  }

  func testAudioHasDurationAndNoDimensions() async throws {
    try await audio("Music/Fetchr/song.mp3")

    let song = try item(await library().list(folder: "Fetchr"), "song.mp3")

    XCTAssertTrue(song.isAudio)
    XCTAssertEqual(song.mimeType, "audio/mpeg")
    XCTAssertNil(song.width)
    XCTAssertNil(song.height)
    let duration = try XCTUnwrap(song.durationMs)
    XCTAssertTrue((1900...2150).contains(duration), "\(duration)")
  }

  func testListSkipsPartialsHiddenCoversAndNonMedia() async throws {
    try await video("Movies/Fetchr/kept.mp4")
    try write("Movies/Fetchr/a.mp4.part")
    try write("Movies/Fetchr/a.mp4.ytdl")
    try write("Movies/Fetchr/.hidden.mp4")
    try write("Movies/Fetchr/x.temp.mp4")
    try write("Movies/Fetchr/notes.txt")
    try write("Movies/Fetchr/.trash/gone.mp4")
    try write("Music/Fetchr/b.mp3.part")
    try write("Music/Fetchr/cover.jpg")
    try write("Pictures/Fetchr/c.jpg")

    let items = await library().list(folder: "Fetchr")

    XCTAssertEqual(items.map(\.name), ["kept.mp4"])
  }

  // In the list, a .part or .ytdl name is also refused by its type; only the name rule sees these on their own.
  func testNameRuleRefusesDownloadLeftoversAndHiddenFiles() {
    for name in ["a.mp4.part", "a.f137.mp4.part", "a.mp4.ytdl", "x.temp.mp4", "a.f251.temp.webm", ".hidden.mp4", ".mp4"] {
      XCTAssertFalse(Library.isListable(name), name)
    }
    for name in ["a.mp4", "Road trip - 01.mp3", "part.mp4", "a.partial.mp4", "temp.mp4", "a.ytdl.mp4"] {
      XCTAssertTrue(Library.isListable(name), name)
    }
  }

  // A real video outside Documents, reachable only through symlinks the user (or another app) could plant: the
  // user folder itself, a file and a playlist folder inside it.
  func testListNeverFollowsASymlinkOutOfDocuments() async throws {
    let outside = root.appendingPathComponent("outside", isDirectory: true)
    try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
    let secret = try await video("../outside/secret.mp4")
    XCTAssertTrue(secret.resolvingSymlinksInPath().path.hasPrefix(outside.resolvingSymlinksInPath().path))
    let manager = FileManager.default
    try manager.createDirectory(at: documents.appendingPathComponent("Movies"), withIntermediateDirectories: true)
    try manager.createSymbolicLink(at: documents.appendingPathComponent("Movies/Linked"), withDestinationURL: outside)
    try await video("Movies/Fetchr/kept.mp4")
    try manager.createSymbolicLink(at: documents.appendingPathComponent("Movies/Fetchr/link.mp4"), withDestinationURL: secret)
    try manager.createSymbolicLink(at: documents.appendingPathComponent("Movies/Fetchr/Evil"), withDestinationURL: outside)

    let linkedRoot = await library().list(folder: "Linked")
    let fetchr = await library().list(folder: "Fetchr")

    XCTAssertEqual(linkedRoot.map(\.name), [])
    XCTAssertEqual(fetchr.map(\.name), ["kept.mp4"])
  }

  func testMetadataCacheFollowsAReplacedFile() async throws {
    try await video("Movies/Fetchr/clip.mp4", seconds: 2)
    let first = try item(await library().list(folder: "Fetchr"), "clip.mp4")
    XCTAssertTrue((1900...2100).contains(first.durationMs ?? 0), "\(String(describing: first.durationMs))")
    XCTAssertTrue(FileManager.default.fileExists(atPath: caches.appendingPathComponent("library-info.json").path))

    try await video("Movies/Fetchr/clip.mp4", seconds: 4, size: "160x120")
    let second = try item(await library().list(folder: "Fetchr"), "clip.mp4")

    XCTAssertTrue((3900...4100).contains(second.durationMs ?? 0), "\(String(describing: second.durationMs))")
    XCTAssertEqual(second.width, 160)
  }

  func testMetadataComesFromTheCacheWhenTheFileIsUnchanged() async throws {
    let file = try await video("Movies/Fetchr/clip.mp4")
    let first = try item(await library().list(folder: "Fetchr"), "clip.mp4")
    XCTAssertEqual(first.width, 320)

    // Unreadable content under the same modification date: only the cache a new Library reads from disk still
    // knows the dimensions.
    let modified = try XCTUnwrap(try file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
    try Data(count: 64).write(to: file)
    try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: file.path)
    let second = try item(await library().list(folder: "Fetchr"), "clip.mp4")

    XCTAssertEqual(second.width, 320)
    XCTAssertEqual(second.durationMs, first.durationMs)
    XCTAssertEqual(second.sizeBytes, 64)
  }

  func testCacheForgetsFilesThatAreGone() async throws {
    let file = try await video("Movies/Fetchr/clip.mp4")
    _ = await library().list(folder: "Fetchr")
    let cacheFile = caches.appendingPathComponent("library-info.json")
    XCTAssertTrue(try String(contentsOf: cacheFile, encoding: .utf8).contains("clip.mp4"))

    try FileManager.default.removeItem(at: file)
    _ = await library().list(folder: "Fetchr")

    XCTAssertFalse(try String(contentsOf: cacheFile, encoding: .utf8).contains("clip.mp4"))
  }

  // Two lists that overlap: the older snapshot must not land on disk after the newer one and drop its entries.
  func testCacheNeverWritesAnOlderSnapshotOverANewerOne() async throws {
    let url = caches.appendingPathComponent("library-info.json")
    let firstWriteHeld = DispatchSemaphore(value: 0)
    let releaseFirstWrite = DispatchSemaphore(value: 0)
    let calls = Recorded<Int>()
    let cache = MediaInfoCache(url: url) {
      let call = (calls.value ?? 0) + 1
      calls.set(call)
      guard call == 1 else { return }
      firstWriteHeld.signal()
      _ = releaseFirstWrite.wait(timeout: .now() + 10)
    }
    let missing = scratch.appendingPathComponent("missing.mp4")
    _ = await cache.info(for: missing, key: "Movies/Fetchr/a.mp4|1")
    let older = Thread { cache.save(keeping: ["Movies/Fetchr/a.mp4|1"], under: ["Movies/Fetchr/"]) }
    older.start()
    XCTAssertEqual(firstWriteHeld.wait(timeout: .now() + 10), .success)

    _ = await cache.info(for: missing, key: "Movies/Fetchr/b.mp4|1")
    cache.save(keeping: ["Movies/Fetchr/a.mp4|1", "Movies/Fetchr/b.mp4|1"], under: ["Movies/Fetchr/"])
    releaseFirstWrite.signal()
    while !older.isFinished { try await Task.sleep(nanoseconds: 10_000_000) }

    let written = try JSONDecoder().decode([String: MediaInfo].self, from: Data(contentsOf: url))
    XCTAssertEqual(Set(written.keys), ["Movies/Fetchr/a.mp4|1", "Movies/Fetchr/b.mp4|1"])
  }

  func testCorruptFileStillListsWithoutMetadata() async throws {
    var bytes = Data(count: 4096)
    for i in bytes.indices { bytes[i] = UInt8.random(in: 0...255) }
    try write("Movies/Fetchr/x.mp4", bytes)
    try write("Movies/Fetchr/empty.mp4", Data())
    try await video("Movies/Fetchr/good.mp4")

    let items = await library().list(folder: "Fetchr")

    XCTAssertEqual(Set(items.map(\.name)), ["x.mp4", "empty.mp4", "good.mp4"])
    for name in ["x.mp4", "empty.mp4"] {
      let bad = try item(items, name)
      XCTAssertNil(bad.durationMs, name)
      XCTAssertNil(bad.width, name)
      XCTAssertNil(bad.height, name)
    }
    XCTAssertEqual(try item(items, "x.mp4").sizeBytes, 4096)
    XCTAssertEqual(try item(items, "good.mp4").width, 320)
  }

  // UTType knows both on iOS 26 (mkv is the one it does not); yt-dlp keeps a single-file format's own container.
  func testWebmFlvAndMkvList() async throws {
    for name in ["a.webm", "b.flv", "c.mkv"] { try write("Movies/Fetchr/\(name)") }

    let items = await library().list(folder: "Fetchr")

    XCTAssertEqual(
      Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.mimeType) }),
      ["a.webm": "video/webm", "b.flv": "video/x-flv", "c.mkv": "video/x-matroska"])
  }

  func testUnsafeFolderNameStaysInsideItsRoot() async throws {
    try await video("Movies/Fetchr/inside.mp4")
    try await video("Movies/outside.mp4")
    try await video("top.mp4")

    let items = await library().list(folder: "../../")

    XCTAssertEqual(items.map(\.name), ["inside.mp4"])
    XCTAssertEqual(items.first?.relativePath, "Movies/Fetchr/")
  }

  func testMissingFolderListsNothing() async {
    let items = await library().list(folder: "Fetchr")
    XCTAssertTrue(items.isEmpty)
  }

  func testFreeSpaceIsPositive() throws {
    XCTAssertGreaterThan(try library().freeSpaceBytes(), 0)
  }

  func testSaveMarksMediaRootsExcludedFromBackup() throws {
    for (root, name) in [("Movies", "a.mp4"), ("Music", "b.mp3"), ("Pictures", "c.jpg")] {
      let source = scratch.appendingPathComponent(name)
      try Data("x".utf8).write(to: source)
      _ = try SaveLocation.save(source, toRelativeFolder: "\(root)/Fetchr/Road trip", documents: documents)
      let values = try documents.appendingPathComponent(root, isDirectory: true)
        .resourceValues(forKeys: [.isExcludedFromBackupKey])
      XCTAssertEqual(values.isExcludedFromBackup, true, root)
    }
  }

  func testHostApiListsTheLibrary() async throws {
    try await video("Movies/Fetchr/clip.mp4")
    let api = HostApi(python: FakePython(), library: library())

    let items = try await api.listLibrary(folder: "Fetchr")

    XCTAssertEqual(items.map(\.name), ["clip.mp4"])
    let free = try await api.freeSpaceBytes()
    XCTAssertGreaterThan(free, 0)
  }
}
