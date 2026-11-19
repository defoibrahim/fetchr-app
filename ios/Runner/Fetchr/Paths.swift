import Foundation

enum Paths {
  static let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
  static let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]

  // Unlike Documents and Caches, Application Support does not exist until it is created. It is not backed up: the
  // task list's paused tasks point at partial files in Caches, which a restore would not bring back.
  static let applicationSupportDir: URL = {
    let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    dir.excludeFromBackup()
    return dir
  }()

  // Verified yt-dlp releases, one folder per version, for the next launch to run.
  static let ytDlpDir = applicationSupportDir.appendingPathComponent("yt-dlp", isDirectory: true)

  // Videos the picker copied in, each in its own folder under its own name, until the task converting it ends. Inside
  // Application Support, so its backup exclusion covers them.
  static let pickedDir: URL = {
    let dir = applicationSupportDir.appendingPathComponent("picked", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }()
}

// Every uri Dart sends back (a library item, a saved download) is checked here before any file is touched.
extension Paths {
  static let outsideDocuments = FetchrError(
    code: "invalid_url", message: "That file is not in Fetchr's folder.", details: nil)
  private static let notPicked = FetchrError(
    code: "invalid_url", message: "That video is not one Fetchr picked.", details: nil)

  // The file a `file://` uri names, under `documents`, with `..` and symlinks resolved: what is checked is what is
  // acted on.
  static func documentFile(fromUri uri: String, documents: URL = documentsDir) throws -> URL {
    let relative = try documentRelativePath(fromUri: uri, documents: documents)
    return documents.appendingPathComponent(relative, isDirectory: false)
  }

  // The same file as a path relative to Documents ("Movies/Fetchr/a.mp4"), the form the task list stores.
  static func documentRelativePath(fromUri uri: String, documents: URL = documentsDir) throws -> String {
    try relativePath(fromUri: uri, under: documents, refusal: outsideDocuments)
  }

  // The same, and only under Movies, Music or Pictures: the rest of Documents is the user's own space in Files.
  static func mediaRelativePath(fromUri uri: String, documents: URL = documentsDir) throws -> String {
    let relative = try documentRelativePath(fromUri: uri, documents: documents)
    guard MediaKind.allCases.contains(where: { relative.hasPrefix($0.root + "/") }) else { throw outsideDocuments }
    return relative
  }

  // A video the picker copied, by the same rules as `documentFile`: a second boundary, so a picked uri can never
  // reach a library delete or share.
  static func pickedFile(fromUri uri: String, picked: URL = pickedDir) throws -> URL {
    let relative = try relativePath(fromUri: uri, under: picked, refusal: notPicked)
    return picked.appendingPathComponent(relative, isDirectory: false)
  }

  private static func relativePath(fromUri uri: String, under root: URL, refusal: FetchrError) throws -> String {
    guard let url = URL(string: uri), url.isFileURL, (url.host ?? "").isEmpty, url.query == nil, url.fragment == nil
    else { throw refusal }
    // Fully decoded: `url.path` leaves some escapes (%00) as they are, so they would never be checked.
    let path = url.path(percentEncoded: false)
    guard path.hasPrefix("/"), !path.contains("\0"),
      let file = realPath(URL(fileURLWithPath: path).standardized.path),
      let base = realPath(root.standardized.path), file.hasPrefix(base + "/")
    else { throw refusal }
    return String(file.dropFirst(base.count + 1))
  }

  // realpath of the part of the path that exists, plus the rest as it is written, so a file already deleted (or
  // its whole playlist folder) still resolves. A missing part that is itself a link (dangling) is refused: it
  // could point anywhere.
  private static func realPath(_ path: String) -> String? {
    var head = path
    var rest: [String] = []
    while true {
      if let resolved = realpath(head, nil) {
        defer { free(resolved) }
        let base = String(cString: resolved)
        guard !rest.isEmpty else { return base }
        return (base == "/" ? "" : base) + "/" + rest.joined(separator: "/")
      }
      var info = stat()
      guard errno == ENOENT, lstat(head, &info) != 0, head != "/" else { return nil }
      let parent = (head as NSString).deletingLastPathComponent
      rest.insert((head as NSString).lastPathComponent, at: 0)
      head = parent.isEmpty ? "/" : parent
    }
  }
}
