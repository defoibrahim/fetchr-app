import Foundation

// What a download is to the Files app: the Documents folder it lands in, as Android's MediaStore collection.
enum MediaKind: CaseIterable {
  case video, audio, image

  static func of(_ quality: Quality) -> MediaKind {
    switch quality {
    case .mp3: return .audio
    case .cover: return .image
    case .best, .p1080, .p720, .p480: return .video
    }
  }

  var root: String {
    switch self {
    case .video: return "Movies"
    case .audio: return "Music"
    case .image: return "Pictures"
    }
  }
}

enum SaveLocation {
  // yt-dlp's partial download and its resume state.
  static let leftovers = [".part", ".ytdl"]

  static func relativeFolder(_ req: DownloadRequest) -> String {
    "\(MediaKind.of(req.quality).root)/\(RequestBuilder.saveFolder(req))"
  }

  static func pickResult(in dir: URL, quality: Quality) throws -> URL {
    let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
    let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys)) ?? []
    let candidates = files.compactMap { url -> (URL, Int)? in
      let name = url.lastPathComponent
      guard name != RequestBuilder.conversionReport, !leftovers.contains(where: name.hasSuffix),
        quality != .mp3 || url.pathExtension.lowercased() == "mp3",
        let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true
      else { return nil }
      return (url, values.fileSize ?? 0)
    }
    guard let largest = candidates.max(by: { $0.1 < $1.1 }) else {
      throw FetchrError(code: "unknown", message: "No file was saved.", details: nil)
    }
    return largest.0
  }

  // Moves the file in; a name already taken becomes "name (1).ext", "name (2).ext", ... as on Android.
  static func save(_ file: URL, toRelativeFolder rel: String, documents: URL) throws -> URL {
    let folder = documents.appendingPathComponent(rel, isDirectory: true)
    let manager = FileManager.default
    try manager.createDirectory(at: folder, withIntermediateDirectories: true)
    if let root = rel.split(separator: "/").first {
      // Downloads can be fetched again, so they stay out of iCloud backups (design 5.6); checked on every save.
      documents.appendingPathComponent(String(root), isDirectory: true).excludeFromBackup()
    }
    let ext = file.pathExtension
    let stem = file.deletingPathExtension().lastPathComponent
    var counter = 0
    while true {
      let name = counter == 0 ? file.lastPathComponent : "\(stem) (\(counter))" + (ext.isEmpty ? "" : ".\(ext)")
      let target = folder.appendingPathComponent(name, isDirectory: false)
      if !manager.fileExists(atPath: target.path) {
        do {
          try manager.moveItem(at: file, to: target)
          return target
        } catch CocoaError.fileWriteFileExists {
          // Taken between the check and the move; try the next name.
        }
      }
      counter += 1
    }
  }

  // A file already gone counts as deleted. rmdir only removes an empty folder, and only a playlist folder (below
  // <Movies|Music|Pictures>/<folder>) is tried, never the user's folder itself.
  static func deleteSaved(_ relative: String, documents: URL) throws {
    let file = documents.appendingPathComponent(relative, isDirectory: false)
    do {
      try FileManager.default.removeItem(at: file)
    } catch let error as CocoaError where error.code == .fileNoSuchFile {
    }
    if relative.split(separator: "/").count > 3 {
      rmdir(file.deletingLastPathComponent().path)
    }
  }
}
