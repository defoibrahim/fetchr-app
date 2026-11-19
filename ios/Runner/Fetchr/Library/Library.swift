import Foundation
import UniformTypeIdentifiers

// The saved videos and MP3s, as Android's MediaStore query lists them: Movies/<folder> and Music/<folder> with
// their playlist subfolders, newest first. Covers (Pictures) are saved but never listed.
struct Library {
  private struct Entry {
    let file: URL
    let relativeFile: String
    let folder: String
    let kind: MediaKind
    let mimeType: String
    let sizeBytes: Int64
    let addedMs: Int64
    let cacheKey: String
  }

  private static let keys: Set<URLResourceKey> = [
    .isRegularFileKey, .fileSizeKey, .creationDateKey, .contentModificationDateKey,
  ]
  private static let parallelReads = 4
  // Types UTType does not know on iOS.
  private static let extraTypes: [String: (MediaKind, String)] = ["mkv": (.video, "video/x-matroska")]

  let documents: URL
  private let cache: MediaInfoCache
  private let thumbnails: Thumbnails

  init(documents: URL, caches: URL) {
    self.documents = documents
    cache = MediaInfoCache(url: caches.appendingPathComponent("library-info.json", isDirectory: false))
    thumbnails = Thumbnails(caches: caches)
  }

  // Detached, because pigeon calls arrive on the main actor and the walk and the file reads block.
  func list(folder: String) async -> [LibraryItem] {
    await Task.detached(priority: .userInitiated) { await self.collect(folder: folder) }.value
  }

  private func collect(folder: String) async -> [LibraryItem] {
    let safe = RequestBuilder.safeFolder(folder)
    let kinds: [MediaKind] = [.video, .audio]
    let entries = kinds.flatMap { files(of: $0, in: safe) }
    let infos = await metadata(of: entries)
    cache.save(keeping: Set(entries.map(\.cacheKey)), under: kinds.map { "\($0.root)/\(safe)/" })
    let items = zip(entries, infos).map { entry, info in
      let audio = entry.kind == .audio
      return LibraryItem(
        uri: documents.appendingPathComponent(entry.relativeFile, isDirectory: false).absoluteString,
        name: entry.file.lastPathComponent, mimeType: entry.mimeType, isAudio: audio, sizeBytes: entry.sizeBytes,
        durationMs: info.durationMs, dateAddedMs: entry.addedMs, width: audio ? nil : info.width,
        height: audio ? nil : info.height, relativePath: entry.folder)
    }
    return items.sorted { a, b in
      a.dateAddedMs != b.dateAddedMs ? a.dateAddedMs > b.dateAddedMs : (a.relativePath ?? "", a.name) < (b.relativePath ?? "", b.name)
    }
  }

  // The file relative to Documents, for the task list. Only under the media roots: the rest of Documents is the
  // user's own space in the Files app. Never a folder: deleting one would take every file in it.
  @discardableResult
  func delete(uri: String) throws -> String {
    let relative = try Paths.mediaRelativePath(fromUri: uri, documents: documents)
    let file = documents.appendingPathComponent(relative, isDirectory: false)
    if FileManager.default.isDirectory(atPath: file.path) == true {
      throw FetchrError(code: "invalid_url", message: "That is a folder, not a file.", details: nil)
    }
    try SaveLocation.deleteSaved(relative, documents: documents)
    return relative
  }

  // Detached like `list`: decoding a frame blocks.
  func thumbnail(uri: String, widthPx: Int, heightPx: Int) async throws -> String? {
    let relative = try Paths.documentRelativePath(fromUri: uri, documents: documents)
    let file = documents.appendingPathComponent(relative, isDirectory: false)
    return await Task.detached(priority: .utility) { [thumbnails] in
      await thumbnails.thumbnail(for: file, relativePath: relative, widthPx: widthPx, heightPx: heightPx)
    }.value
  }

  func freeSpaceBytes() throws -> Int64 {
    let values = try documents.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
    guard let bytes = values.volumeAvailableCapacityForImportantUsage else {
      throw FetchrError(code: "unknown", message: "Free space is not known.", details: nil)
    }
    return bytes
  }

  // Paths are compared with symlinks resolved (/var is /private/var), and a root that resolves outside Documents
  // is not listed.
  private func files(of kind: MediaKind, in folder: String) -> [Entry] {
    let manager = FileManager.default
    let rootRel = "\(kind.root)/\(folder)"
    let root = documents.appendingPathComponent(rootRel, isDirectory: true)
    let docsPath = documents.resolvingSymlinksInPath().path
    let rootPath = root.resolvingSymlinksInPath().path
    guard rootPath.hasPrefix(docsPath + "/"), manager.isDirectory(atPath: rootPath) == true,
      let walk = manager.enumerator(
        at: URL(fileURLWithPath: rootPath, isDirectory: true), includingPropertiesForKeys: Array(Self.keys),
        options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, _ in true })
    else { return [] }
    var entries: [Entry] = []
    for case let file as URL in walk {
      let name = file.lastPathComponent
      guard Self.isListable(name), let mime = Self.mimeType(of: file, kind: kind),
        let values = try? file.resourceValues(forKeys: Self.keys), values.isRegularFile == true
      else { continue }
      let full = file.resolvingSymlinksInPath().path
      guard full.hasPrefix(rootPath + "/") else { continue }
      let inside = String(full.dropFirst(rootPath.count + 1))
      let relativeFile = "\(rootRel)/\(inside)"
      let folderRel = (relativeFile as NSString).deletingLastPathComponent + "/"
      let added = values.creationDate ?? values.contentModificationDate
      entries.append(
        Entry(
          file: file, relativeFile: relativeFile, folder: folderRel, kind: kind, mimeType: mime,
          sizeBytes: Int64(values.fileSize ?? 0), addedMs: (added?.roundedEpochMs ?? 0),
          cacheKey: MediaInfoCache.key(relativePath: relativeFile, modified: values.contentModificationDate)))
    }
    return entries
  }

  // At most a few files open at once; cache hits return without opening anything.
  private func metadata(of entries: [Entry]) async -> [MediaInfo] {
    await withTaskGroup(of: (Int, MediaInfo).self) { group in
      var results = [MediaInfo](repeating: MediaInfo(), count: entries.count)
      var pending = entries.indices.makeIterator()
      func start(_ index: Int) {
        let entry = entries[index]
        group.addTask { [cache] in (index, await cache.info(for: entry.file, key: entry.cacheKey)) }
      }
      for _ in 0..<Self.parallelReads {
        guard let index = pending.next() else { break }
        start(index)
      }
      while let done = await group.next() {
        results[done.0] = done.1
        if let next = pending.next() { start(next) }
      }
      return results
    }
  }

  // Leftovers of a download (yt-dlp's .part and .ytdl, ffmpeg's .temp. while it merges) and hidden files.
  static func isListable(_ name: String) -> Bool {
    !name.hasPrefix(".") && !SaveLocation.leftovers.contains(where: name.hasSuffix) && !name.contains(".temp.")
  }

  // Only what Android's video or audio collection would hold for that root; nil skips the file.
  private static func mimeType(of file: URL, kind: MediaKind) -> String? {
    let ext = file.pathExtension.lowercased()
    if let type = UTType(filenameExtension: ext), type.conforms(to: kind == .audio ? .audio : .movie) {
      return type.preferredMIMEType ?? (kind == .audio ? "audio/mpeg" : "video/mp4")
    }
    if let extra = extraTypes[ext], extra.0 == kind { return extra.1 }
    return nil
  }
}
