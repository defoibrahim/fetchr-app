import Foundation

enum InfoParser {
  private static let videoTiers: [Quality] = [.best, .p1080, .p720, .p480]
  private static let youTubePlaceholderTitles: Set<String> = ["[Private video]", "[Deleted video]"]

  // yt-dlp's bytes per second for one kbit/s.
  private static let bytesPerKbit = 125.0

  private struct Size {
    let bytes: Int64
    let estimated: Bool
  }

  // Throws on non-JSON output or a non-object root; the caller maps it through ErrorClassifier.
  static func parse(_ json: String, url: String) throws -> VideoInfo {
    try parse(JSONObject.parse(json), url: url)
  }

  static func parse(_ root: JSONObject, url: String) -> VideoInfo {
    let type = root.str("_type")
    let isPlaylist = type == "playlist" || type == "multi_video"
    return VideoInfo(
      url: url,
      title: root.str("title") ?? url,
      thumbnail: thumbnail(root),
      durationSeconds: root.long("duration"),
      uploader: root.str("uploader"),
      isPlaylist: isPlaylist,
      options: isPlaylist ? bare(videoTiers + [.mp3]) : options(root),
      entries: isPlaylist ? entries(root.objects("entries")) : [],
      isLive: root.bool("is_live")
    )
  }

  // Approximates what yt-dlp downloads for each quality, so the sizes shown match the file saved.
  private static func options(_ root: JSONObject) -> [FormatOption] {
    let cover = [coverOption(root)].compactMap { $0 }
    let formats = root.objects("formats")
    if formats.isEmpty { return bare(videoTiers + [.mp3]) + cover }

    let duration = root.num("duration")
    let audio = formats.filter { $0.str("vcodec") == "none" && $0.str("acodec") != "none" }
    let bestAudio = firstMax(audio, by: audioOrder)
    let mp3 = mp3Option(bestAudio, duration)
    let video = formats.filter { $0.str("vcodec") != "none" }
    if video.isEmpty { return [mp3] + cover }

    // A missing acodec means unknown, so only an explicit "none" rules out sound.
    let hasSound = !audio.isEmpty || video.contains { $0.str("acodec") != "none" }
    let extras = (hasSound ? [mp3] : []) + cover
    let sized = video.filter { dimension($0, "width") > 0 && dimension($0, "height") > 0 }
    if sized.isEmpty { return bare([.best]) + extras }

    var seenSides = Set<Int64>()
    let tiers = videoTiers
      .map { ($0, pickVideo(sized, cap: $0.shortSideCap)) }
      .filter { seenSides.insert(shortSide($0.1)).inserted }
      .map { videoOption($0.0, $0.1, bestAudio, duration) }
    return tiers + extras
  }

  // Mirrors `-S res:<cap>`: the largest short side within the cap, else the smallest one above it.
  private static func pickVideo(_ video: [JSONObject], cap: Int64?) -> JSONObject {
    let sides = video.map(shortSide)
    let side: Int64
    if let cap {
      side = sides.filter { $0 <= cap }.max() ?? sides.min()!
    } else {
      side = sides.max()!
    }
    return firstMax(video.filter { shortSide($0) == side }, by: videoOrder)!
  }

  private static func videoOption(
    _ quality: Quality, _ pick: JSONObject, _ bestAudio: JSONObject?, _ duration: Double?
  ) -> FormatOption {
    // A video-only pick is merged with the best audio stream, so both count toward the size.
    let parts = [pick] + (pick.str("acodec") == "none" ? [bestAudio].compactMap { $0 } : [])
    let known = parts.compactMap { size($0, duration) }
    return FormatOption(
      quality: quality,
      width: pick.long("width"),
      height: pick.long("height"),
      fps: pick.num("fps"),
      sizeBytes: known.count == parts.count ? known.reduce(0) { $0 + $1.bytes } : nil,
      sizeIsEstimate: known.contains { $0.estimated }
    )
  }

  private static func mp3Option(_ bestAudio: JSONObject?, _ duration: Double?) -> FormatOption {
    FormatOption(quality: .mp3, sizeBytes: bestAudio.flatMap { size($0, duration) }?.bytes, sizeIsEstimate: true)
  }

  private static func coverOption(_ root: JSONObject) -> FormatOption? {
    guard let url = thumbnail(root) else { return nil }
    let match = root.objects("thumbnails").first { $0.str("url") == url }
    return FormatOption(
      quality: .cover, width: match?.long("width"), height: match?.long("height"), sizeIsEstimate: false)
  }

  private static func bare(_ qualities: [Quality]) -> [FormatOption] {
    qualities.map { FormatOption(quality: $0, sizeIsEstimate: false) }
  }

  private static let audioOrder = Ordering<JSONObject>([
    { .bool($0.str("acodec")?.hasPrefix("mp4a") == true) },
    { .double(positive($0, "abr") ?? positive($0, "tbr") ?? 0) },
  ])

  // yt-dlp's codec preference lists, best first: "" is any other codec and nil a missing one.
  private static let vcodecs = CodecOrder([
    "av0?1", "vp0?9.2", "vp0?9", "[hx]265|he?vc?", "[hx]264|avc", "vp0?8", "mp4v|h263", "theora", "", nil, "none",
  ])
  private static let acodecs = CodecOrder([
    "[af]lac", "wav|aiff", "opus", "vorbis|ogg", "aac", "mp?4a?", "mp3", "ac-?4", "e-?a?c-?3", "ac-?3", "dts",
    "", nil, "none",
  ])

  // Within one short side: `-S vcodec:h264,acodec:aac`, then yt-dlp's defaults (frame rate, size, bitrate).
  private static let videoOrder = Ordering<JSONObject>([
    { .int(vcodecs.rank(limit: "h264", $0.str("vcodec"))) },
    { .int(acodecs.rank(limit: "aac", $0.str("acodec"))) },
    { .double($0.num("fps") ?? 0) },
    { .double(positive($0, "filesize") ?? positive($0, "filesize_approx") ?? 0) },
    { .double($0.num("tbr") ?? 0) },
  ])

  private static func positive(_ object: JSONObject, _ key: String) -> Double? {
    object.num(key).flatMap { $0 > 0 ? $0 : nil }
  }

  private static func dimension(_ object: JSONObject, _ key: String) -> Int64 { object.long(key) ?? 0 }

  private static func shortSide(_ object: JSONObject) -> Int64 {
    min(dimension(object, "width"), dimension(object, "height"))
  }

  private static func size(_ object: JSONObject, _ duration: Double?) -> Size? {
    if let bytes = positive(object, "filesize") { return Size(bytes: roundToLong(bytes), estimated: false) }
    if let bytes = positive(object, "filesize_approx") { return Size(bytes: roundToLong(bytes), estimated: true) }
    guard let kbit = positive(object, "tbr") ?? positive(object, "abr"), let duration else { return nil }
    return Size(bytes: roundToLong(kbit * duration * bytesPerKbit), estimated: true)
  }

  private static func entries(_ items: [JSONObject]) -> [PlaylistEntry] {
    items.compactMap { e in
      guard let entryUrl = e.str("url") ?? e.str("webpage_url"), !isDeadYouTubeEntry(e) else { return nil }
      return PlaylistEntry(
        url: entryUrl, title: e.str("title") ?? entryUrl, thumbnail: thumbnail(e), durationSeconds: e.long("duration"))
    }
  }

  // A private, deleted or otherwise unavailable YouTube video keeps its slot in a flat playlist with a placeholder
  // title or none, and only fails once downloaded. Other sites can leave the title out of a working entry.
  private static func isDeadYouTubeEntry(_ e: JSONObject) -> Bool {
    guard e.str("ie_key") == "Youtube" else { return false }
    guard let title = e.str("title") else { return true }
    return youTubePlaceholderTitles.contains(title)
  }

  // yt-dlp sorts thumbnails worst to best, so the last one is the largest.
  private static func thumbnail(_ object: JSONObject) -> String? {
    object.str("thumbnail") ?? object.objects("thumbnails").last?.str("url")
  }

  // Kotlin's maxWith: on a tie the earliest element wins.
  private static func firstMax(_ items: [JSONObject], by order: Ordering<JSONObject>) -> JSONObject? {
    guard var best = items.first else { return nil }
    for item in items.dropFirst() where order.less(best, item) { best = item }
    return best
  }
}

// Kotlin's compareBy: the first selector that differs decides, and false sorts before true.
private struct Ordering<T> {
  enum Key: Comparable {
    case bool(Bool)
    case int(Int)
    case double(Double)

    static func < (a: Key, b: Key) -> Bool {
      switch (a, b) {
      case let (.bool(x), .bool(y)): return !x && y
      case let (.int(x), .int(y)): return x < y
      case let (.double(x), .double(y)): return x < y
      default: return false
      }
    }
  }

  let selectors: [(T) -> Key]

  init(_ selectors: [(T) -> Key]) {
    self.selectors = selectors
  }

  func less(_ a: T, _ b: T) -> Bool {
    for select in selectors {
      let (x, y) = (select(a), select(b))
      if x < y { return true }
      if y < x { return false }
    }
    return false
  }
}

private struct CodecOrder {
  private let order: [String?]
  private let patterns: [NSRegularExpression?]

  init(_ order: [String?]) {
    self.order = order
    // The patterns are constants, so a bad one is a programming error.
    patterns = order.map { entry in
      guard let entry, !entry.isEmpty else { return nil }
      return try! NSRegularExpression(pattern: "^(?:\(entry))")
    }
  }

  // `-S <field>:<limit>`: codecs at or below the limit win, closest first, then those above it, closest first.
  func rank(limit: String, _ codec: String?) -> Int {
    let at = index(codec)
    return at >= index(limit) ? order.count - at : at - order.count
  }

  private func index(_ codec: String?) -> Int {
    guard let codec else { return order.firstIndex { $0 == nil }! }
    let name = codec.lowercased()
    let range = NSRange(name.startIndex..., in: name)
    let hit = patterns.firstIndex { $0?.firstMatch(in: name, range: range) != nil }
    return hit ?? order.firstIndex(of: "")!
  }
}
