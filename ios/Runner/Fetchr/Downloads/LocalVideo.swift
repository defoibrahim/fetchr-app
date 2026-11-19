import AVFoundation
import Foundation

// A video on the phone turned into an MP3 by the download pipeline, as Android's LocalVideo: a copy the picker made
// or a library file. Its task's url is the file:// uri; each attempt copies the video into the task dir under the
// name yt-dlp would save it as, so yt-dlp finds it "already downloaded", only converts it and deletes the copy.
enum LocalVideo {
  struct Source: Equatable {
    let file: URL
    // The picked copy's top entry under the picked dir; nil for a library file, which is never deleted.
    let pickedEntry: String?

    var isPicked: Bool { pickedEntry != nil }
  }

  static let gone = FetchrError(code: "unavailable", message: "The video is gone", details: nil)
  private static let notConvertible = FetchrError(
    code: "invalid_url", message: "That video is not in Fetchr's folder.", details: nil)
  private static let defaultName = "video"
  // Never "mp3": the attempt's cut-short cleanup deletes every .mp3 in the task dir.
  private static let defaultExtension = "mp4"
  private static let pickedUnderContainer = "Library/Application Support/picked/"
  private static let documentsUnderContainer = "Documents/"
  // The app container on a device or a simulator; its UUID changes between installs.
  private static let container = try! NSRegularExpression(pattern: "/Data/Application/[0-9A-Fa-f-]{36}/(.+)$")

  static func isLocal(_ url: String) -> Bool { url.hasPrefix("file:") }

  // The convert boundary: a copy under the picked dir or a file under Documents' media roots, nothing else.
  static func source(_ uri: String, documents: URL, picked: URL?) throws -> Source {
    if let picked, let file = try? Paths.pickedFile(fromUri: uri, picked: picked) {
      let relative = file.path.dropFirst(picked.path.count + 1)
      return Source(file: file, pickedEntry: relative.split(separator: "/").first.map(String.init))
    }
    if let relative = try? Paths.mediaRelativePath(fromUri: uri, documents: documents) {
      return Source(file: documents.appendingPathComponent(relative, isDirectory: false), pickedEntry: nil)
    }
    throw notConvertible
  }

  // What Dart may hand to convertToMp3: a source that is a file now.
  static func convertible(_ uri: String, documents: URL, picked: URL?) throws -> URL {
    let file = try source(uri, documents: documents, picked: picked).file
    switch FileManager.default.isDirectory(atPath: file.path) {
    case nil: throw gone
    case true?: throw notConvertible
    case false?: return file
    }
  }

  // A stored task's source, also after the app container moved (a reinstall or an update): the part below the
  // container is looked up again under today's roots and checked again.
  static func resolve(_ url: String, documents: URL, picked: URL?) -> Source? {
    if let found = try? source(url, documents: documents, picked: picked) { return found }
    guard let parsed = URL(string: url), parsed.isFileURL else { return nil }
    let path = parsed.path(percentEncoded: false)
    guard let match = container.firstMatch(in: path, range: NSRange(path.startIndex..., in: path)),
      let range = Range(match.range(at: 1), in: path)
    else { return nil }
    let rest = String(path[range])
    let moved: URL
    if rest.hasPrefix(documentsUnderContainer) {
      moved = documents.appendingPathComponent(String(rest.dropFirst(documentsUnderContainer.count)))
    } else if let picked, rest.hasPrefix(pickedUnderContainer) {
      moved = picked.appendingPathComponent(String(rest.dropFirst(pickedUnderContainer.count)))
    } else {
      return nil
    }
    return try? source(moved.absoluteString, documents: documents, picked: picked)
  }

  // The name without its extension, as Android reads DISPLAY_NAME; the duration is what ffmpeg's report is
  // measured against.
  static func request(for file: URL, folder: String) async -> DownloadRequest {
    let stem = beforeLastDot(file.lastPathComponent)
    let title = stem.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? defaultName : stem
    return DownloadRequest(
      url: file.absoluteString, title: title, quality: .mp3, folder: folder, useAria2c: false,
      durationSeconds: await durationSeconds(file))
  }

  // The copy yt-dlp converts. A copy left whole by an earlier attempt is reused; one cut short is replaced.
  static func stage(_ req: DownloadRequest, into dir: URL) throws -> URL {
    guard let source = URL(string: req.url), source.isFileURL else { throw gone }
    let name = "\(RequestBuilder.safeFileName(req.title)).\(fileExtension(source.lastPathComponent))"
    let target = dir.appendingPathComponent(name, isDirectory: false)
    if isFile(target) { return target }
    guard isFile(source) else { throw gone }
    let partial = dir.appendingPathComponent(name + ".copying", isDirectory: false)
    let manager = FileManager.default
    try? manager.removeItem(at: partial)
    do {
      try manager.copyItem(at: source, to: partial)
    } catch CocoaError.fileReadNoSuchFile, CocoaError.fileNoSuchFile {
      throw gone
    }
    try manager.moveItem(at: partial, to: target)
    return target
  }

  // The copy and the folder the picker made for it.
  static func deletePicked(_ source: Source, picked: URL) {
    guard let entry = source.pickedEntry else { return }
    try? FileManager.default.removeItem(at: source.file)
    let folder = picked.appendingPathComponent(entry, isDirectory: true)
    if folder.standardizedFileURL.path != source.file.standardizedFileURL.path {
      rmdir(folder.path)
    }
  }

  // Entries under the picked dir that no task still to finish converts: a pick whose convert never came, or a copy
  // whose task completed just before a kill.
  static func orphans(in picked: URL, tasks: [DownloadTask], documents: URL) -> [String] {
    let names = (try? FileManager.default.contentsOfDirectory(atPath: picked.path)) ?? []
    let kept = Set(
      tasks.filter { $0.status != .completed && isLocal($0.request.url) }
        .compactMap { resolve($0.request.url, documents: documents, picked: picked)?.pickedEntry })
    return names.filter { !kept.contains($0) }
  }

  private static func durationSeconds(_ file: URL) async -> Int64? {
    guard let duration = try? await AVURLAsset(url: file).load(.duration) else { return nil }
    let seconds = CMTimeGetSeconds(duration)
    guard seconds.isFinite, seconds >= 1, seconds < 9e15 else { return nil }
    return Int64(seconds)
  }

  // The file's own extension, which is also what yt-dlp names its output after.
  private static func fileExtension(_ name: String) -> String {
    guard let dot = name.lastIndex(of: ".") else { return defaultExtension }
    let ext = name[name.index(after: dot)...]
    guard RequestBuilder.isSafeExtension(ext) else { return defaultExtension }
    return ext.lowercased()
  }

  private static func beforeLastDot(_ name: String) -> String {
    guard let dot = name.lastIndex(of: ".") else { return name }
    return String(name[..<dot])
  }

  private static func isFile(_ url: URL) -> Bool {
    FileManager.default.isDirectory(atPath: url.path) == false
  }
}
