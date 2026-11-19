import Foundation

enum RequestBuilder {
  private static let defaultFolder = "Fetchr"
  private static let defaultName = "video"
  // Bytes are what file systems cap; 150 UTF-16 units stays under 255 bytes for most scripts.
  private static let maxName = 150
  private static let template = "%(title).150B [%(id)s].%(ext)s"
  // ffmpeg's -progress report while an MP3 converts, in the task dir. yt-dlp keeps ffmpeg's own output to itself.
  static let conversionReport = "ffmpeg.progress"
  private static let forbidden: Set<Unicode.Scalar> = ["\\", "/", ":", "*", "?", "\"", "<", ">", "|"]
  // Parallel HLS/DASH fragments per task. Two tasks run at once, so 4 means at most 8 requests to a server.
  private static let concurrentFragments = "4"

  // The scheme check also keeps a value starting with "-" from ever reaching yt-dlp as an option.
  static func requireHttpUrl(_ url: String) throws -> String {
    let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let parsed = components(trimmed),
      let scheme = parsed.scheme?.lowercased(), scheme == "http" || scheme == "https",
      let host = parsed.host, !host.isEmpty,
      !trimmed.unicodeScalars.contains(where: isRejected)
    else {
      throw FetchrError(code: "invalid_url", message: "That is not a valid web link.", details: nil)
    }
    return trimmed
  }

  static func infoArgv(cacheDir: URL) -> [String] {
    ["--flat-playlist", "--cache-dir", ytDlpCache(cacheDir)]
  }

  static func safeFolder(_ name: String) -> String {
    let folder = text(trimEnd(folderSegment(name)))
    return folder.isEmpty ? defaultFolder : folder
  }

  // A playlist's videos go into a folder named after it, inside the user's folder.
  static func saveFolder(_ req: DownloadRequest) -> String {
    let root = safeFolder(req.folder)
    let playlist = req.playlistTitle.map { text(trimEnd(take(folderSegment($0)))) } ?? ""
    return playlist.isEmpty ? root : "\(root)/\(playlist)"
  }

  // A file name for yt-dlp's -o, where % starts a template field.
  // A file extension that is ASCII letters and digits only, never empty.
  static func isSafeExtension<S: StringProtocol>(_ ext: S) -> Bool {
    !ext.isEmpty && ext.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
  }

  static func safeFileName(_ name: String) -> String {
    let kept = name.unicodeScalars.filter { !forbidden.contains($0) && $0 != "%" && !isControl($0) }
    let trimmed = kept.drop { $0 == "." || $0 == "-" || isSpace($0) }
    let fileName = text(take(trimEnd(Array(trimmed))))
    return fileName.isEmpty ? defaultName : fileName
  }

  // "03 - " before a playlist entry's name, padded to the playlist's width, so its files sort in playlist order.
  static func outputTemplate(_ req: DownloadRequest) -> String {
    guard let index = req.playlistIndex else { return template }
    let width = max(2, String(req.playlistCount ?? index).count)
    let number = String(index)
    return String(repeating: "0", count: max(0, width - number.count)) + number + " - " + template
  }

  // The URL is checked by requireHttpUrl and passed to Python next to this argv.
  static func downloadArgv(_ req: DownloadRequest, outDir: URL, cacheDir: URL) -> [String] {
    var argv = [
      "--no-playlist", "--no-mtime", "--cache-dir", ytDlpCache(cacheDir),
      "-o", outDir.appendingPathComponent(outputTemplate(req), isDirectory: false).path,
      "-N", concurrentFragments,
    ]
    switch req.quality {
    case .mp3:
      argv += mp3Options(outDir)
    case .cover:
      // The converted .jpg is the only file left in the task dir.
      argv += ["--skip-download", "--write-thumbnail", "--convert-thumbnails", "jpg"]
    case .best, .p1080, .p720, .p480:
      argv += ["-f", "bv*+ba/b", "-S", videoSort(req.quality), "--merge-output-format", "mp4"]
    }
    return argv
  }

  // `source` is a video LocalVideo staged in the task dir. yt-dlp finds it already where -o points, so it only
  // converts it. File URLs are switched on for this request only; the URL is `convertUrl(source:)`.
  static func convertArgv(source: URL, cacheDir: URL) -> [String] {
    let outDir = source.deletingLastPathComponent()
    let stem = source.deletingPathExtension().lastPathComponent
    return [
      "--enable-file-urls", "--no-mtime", "--cache-dir", ytDlpCache(cacheDir),
      "-o", outDir.appendingPathComponent("\(stem).%(ext)s", isDirectory: false).path,
    ] + mp3Options(outDir)
  }

  // Percent-encoded, so a space, a bracket or a # stays part of the path.
  static func convertUrl(source: URL) -> String {
    URL(fileURLWithPath: source.path, isDirectory: false).absoluteString
  }

  private static func mp3Options(_ outDir: URL) -> [String] {
    let report = outDir.appendingPathComponent(conversionReport, isDirectory: false).path
    return [
      "-f", "ba/b", "-x", "--audio-format", "mp3", "--audio-quality", "0",
      // yt-dlp splits this like a shell; -progress is global, so ffmpeg takes it among the output options.
      "--postprocessor-args", "ExtractAudio+ffmpeg:-progress \"\(report)\"",
    ]
  }

  // yt-dlp's res is the smaller of width and height, so a cap holds for portrait video too.
  private static func videoSort(_ quality: Quality) -> String {
    let res = quality.shortSideCap.map { "res:\($0)" } ?? "res"
    return "\(res),vcodec:h264,acodec:aac"
  }

  private static func folderSegment(_ name: String) -> [Unicode.Scalar] {
    let kept = name.unicodeScalars.filter { !forbidden.contains($0) && !isControl($0) }
    return Array(kept.drop { $0 == "." || isSpace($0) })
  }

  private static func trimEnd(_ scalars: [Unicode.Scalar]) -> [Unicode.Scalar] {
    Array(scalars.reversed().drop(while: isSpace).reversed())
  }

  // Kotlin's take counts UTF-16 units; a pair that would cross the cap is left out instead of split.
  private static func take(_ scalars: [Unicode.Scalar]) -> [Unicode.Scalar] {
    var units = 0
    return Array(
      scalars.prefix { scalar in
        units += scalar.utf16.count
        return units <= maxName
      })
  }

  private static func text(_ scalars: [Unicode.Scalar]) -> String {
    var view = String.UnicodeScalarView()
    view.append(contentsOf: scalars)
    return String(view)
  }

  private static func ytDlpCache(_ cacheDir: URL) -> String {
    cacheDir.appendingPathComponent("yt-dlp").path
  }

  // Android's java.net.URL takes characters such as "|" that URLComponents rejects, so those are escaped for
  // parsing only; the caller still gets the link as typed.
  private static let parseable = CharacterSet.urlQueryAllowed.union(CharacterSet(charactersIn: "#[]%"))

  private static func components(_ trimmed: String) -> URLComponents? {
    if let parsed = URLComponents(string: trimmed) { return parsed }
    return trimmed.addingPercentEncoding(withAllowedCharacters: parseable).flatMap(URLComponents.init(string:))
  }

  // Kotlin's isWhitespace or isISOControl.
  private static func isRejected(_ scalar: Unicode.Scalar) -> Bool {
    isControl(scalar) || isSpace(scalar)
  }

  private static func isControl(_ scalar: Unicode.Scalar) -> Bool {
    scalar.value < 0x20 || (0x7F...0x9F).contains(scalar.value)
  }

  private static func isSpace(_ scalar: Unicode.Scalar) -> Bool {
    CharacterSet.whitespacesAndNewlines.contains(scalar)
  }
}

extension Quality {
  // The cap on a video's shorter side that a quality asks for; nil when it has none.
  var shortSideCap: Int64? {
    switch self {
    case .p1080: return 1080
    case .p720: return 720
    case .p480: return 480
    case .best, .mp3, .cover: return nil
    }
  }
}
