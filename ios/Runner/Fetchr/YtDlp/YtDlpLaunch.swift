import Foundation

// What `selftest` answered for the yt-dlp that booted, or why Python never got that far.
struct SelftestResult: Equatable {
  var ok: Bool
  var version: String?
  var reason: String
}

extension SelftestResult {
  init(reply: Any) {
    let json = reply as? [String: Any]
    self.init(
      ok: json?["ok"] as? Bool ?? false, version: json?["version"] as? String,
      reason: json?["reason"] as? String ?? "selftest gave no verdict")
  }
}

struct LaunchResult: Codable, Equatable {
  var version: String?
  var ok: Bool
  var reason: String
  var atMs: Int64
}

// `<root>/launch.json`. A version is good once a launch on it passed its selftest, and bad once one failed or never
// reported (a crash, a kill, a boot that hung): `attempt` is written before Python boots and cleared by the verdict.
// A good version needs two missing verdicts in a row: a suspended launch that jetsam kills says nothing about it.
struct LaunchRecord: Codable, Equatable {
  private static let strikesAllowed = 2

  var good: [String] = []
  var bad: [String] = []
  var attempt: String?
  var last: LaunchResult?
  // Missing verdicts in a row, for good versions only.
  var strikes: [String: Int] = [:]

  init() {}

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    good = try values.decodeIfPresent([String].self, forKey: .good) ?? []
    bad = try values.decodeIfPresent([String].self, forKey: .bad) ?? []
    attempt = try values.decodeIfPresent(String.self, forKey: .attempt)
    last = try values.decodeIfPresent(LaunchResult.self, forKey: .last)
    strikes = try values.decodeIfPresent([String: Int].self, forKey: .strikes) ?? [:]
  }

  // The newest installed version that is not bad and not older than the bundled copy; nil runs the bundled one.
  mutating func choose(runnable: [String], bundled: String?, nowMs: Int64) -> String? {
    if let unfinished = attempt {
      let missed = LaunchResult(
        version: unfinished, ok: false, reason: "yt-dlp \(unfinished) did not finish starting", atMs: nowMs)
      let count = (strikes[unfinished] ?? 0) + 1
      if good.contains(unfinished), count < Self.strikesAllowed {
        strikes[unfinished] = count
        attempt = nil
        last = missed
      } else {
        fail(unfinished, missed)
      }
    }
    attempt = runnable.first { version in
      !bad.contains(version) && bundled.map { !YtDlpVersion.newer($0, than: version) } ?? true
    }
    return attempt
  }

  mutating func finish(_ result: SelftestResult, nowMs: Int64) {
    var outcome = LaunchResult(version: result.version, ok: result.ok, reason: result.reason, atMs: nowMs)
    guard let tried = attempt else {
      last = outcome
      return
    }
    attempt = nil
    if result.ok, result.version != tried {
      outcome.ok = false
      outcome.reason = "yt-dlp \(result.version ?? "?") ran instead of \(tried)"
    }
    if outcome.ok {
      strikes[tried] = nil
      bad.removeAll { $0 == tried }
      if !good.contains(tried) { good.append(tried) }
      last = outcome
    } else {
      fail(tried, outcome)
    }
  }

  private mutating func fail(_ version: String, _ outcome: LaunchResult) {
    strikes[version] = nil
    good.removeAll { $0 == version }
    if !bad.contains(version) { bad.append(version) }
    attempt = nil
    last = outcome
  }
}

extension YtDlpUpdater {
  static let launchFile = "launch.json"

  // The yt-dlp this build ships, from its version.py, read before Python boots.
  static func bundledVersion(in bundle: URL = Bundle.main.bundleURL) -> String? {
    let file = bundle.appendingPathComponent("app_packages/yt_dlp/version.py")
    return (try? String(contentsOf: file, encoding: .utf8)).flatMap(YtDlpVersion.declared(in:))
  }

  // Decided before Python boots, because CPython cannot be re-initialised in-process: the dir to put ahead of
  // app_packages, or nil for the bundled copy. Records the attempt, so a launch that never reports marks it bad.
  nonisolated func launchChoice(bundled: String?) -> URL? {
    let original = launchRecord()
    var record = original
    let strikesBefore = record.strikes
    let choice = record.choose(runnable: runnable(), bundled: bundled, nowMs: Date().epochMs)
    // A good version's first unfinished launch is only a strike; say so, or a kill at launch leaves no trace.
    for (version, count) in record.strikes where count > (strikesBefore[version] ?? 0) {
      Log.ytdlp.warning(
        "yt-dlp \(version, privacy: .public) did not finish its last launch (strike \(count, privacy: .public))")
    }
    if record != original { writeLaunchRecord(record) }
    // Nothing imports from a bad version before boot, so its files go now; the record keeps it from coming back.
    for version in record.bad where version != choice {
      try? FileManager.default.removeItem(at: root.appendingPathComponent(version, isDirectory: true))
    }
    if let last = record.last, !last.ok, last.version != nil, last.version != choice {
      Log.ytdlp.error("yt-dlp \(last.version ?? "", privacy: .public) is skipped: \(last.reason, privacy: .public)")
    }
    Log.ytdlp.notice("Launching yt-dlp \(choice ?? "bundled \(bundled ?? "?")", privacy: .public)")
    return choice.map { root.appendingPathComponent($0, isDirectory: true) }
  }

  nonisolated func recordLaunch(_ result: SelftestResult) {
    var record = launchRecord()
    record.finish(result, nowMs: Date().epochMs)
    writeLaunchRecord(record)
    if let last = record.last, !last.ok {
      Log.ytdlp.error("yt-dlp launch failed: \(last.reason, privacy: .public)")
    } else {
      Log.ytdlp.notice("yt-dlp \(result.version ?? "?", privacy: .public) passed its selftest")
    }
  }

  // An unreadable record starts over: at worst a bad version is tried once more.
  nonisolated func launchRecord() -> LaunchRecord {
    let file = root.appendingPathComponent(Self.launchFile)
    return (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(LaunchRecord.self, from: $0) }
      ?? LaunchRecord()
  }

  // A failed write (a full disk) loses this step: the previous record stands, so a missing attempt hides one crash
  // and a missing verdict leaves the attempt to count as one at the next launch. The launch itself goes on.
  private nonisolated func writeLaunchRecord(_ record: LaunchRecord) {
    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      try encoder.encode(record).writeAtomically(to: root.appendingPathComponent(Self.launchFile))
    } catch {
      Log.ytdlp.error("launch.json not written: \(String(describing: error), privacy: .public)")
    }
  }

  private nonisolated func runnable() -> [String] {
    installed().filter { Self.layoutProblem(in: root.appendingPathComponent($0, isDirectory: true)) == nil }
  }

  // The dir goes ahead of app_packages and the stdlib on sys.path, so it may hold only the zipapp's own top-level
  // names, and must carry its own yt_dlp_ejs: without it the bundled one would mix in.
  static func layoutProblem(in dir: URL) -> String? {
    let allowed: Set<String> = ["yt_dlp", "yt_dlp_ejs", "__main__.py", "__pycache__", completeMarker]
    let fm = FileManager.default
    let names = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
    if let other = names.first(where: { !allowed.contains($0) }) { return "unexpected top-level entry \(other)" }
    let required = ["yt_dlp/__init__.py", "yt_dlp/version.py", "yt_dlp_ejs/__init__.py"]
    if let missing = required.first(where: { !fm.fileExists(atPath: dir.appendingPathComponent($0).path) }) {
      return "no \(missing)"
    }
    return nil
  }
}
