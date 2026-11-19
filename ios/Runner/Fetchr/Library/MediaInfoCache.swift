import AVFoundation
import Foundation
import os

struct MediaInfo: Codable, Equatable {
  var durationMs: Int64?
  var width: Int64?
  var height: Int64?
}

// Duration and dimensions per file, so a list does not open every file again. The key carries the modification
// time, so a file replaced through the Files app is read again.
final class MediaInfoCache: @unchecked Sendable {
  private let url: URL
  private let lock = NSLock()
  private var entries: [String: MediaInfo]?
  private var dirty = false
  // Each snapshot's number, under `lock`; the newest one on disk, under `writeLock`. Two lists can overlap, and the
  // older snapshot reaching the disk last would drop the newer one's entries.
  private var snapshots = 0
  private let writeLock = NSLock()
  private var written = 0
  private let beforeWrite: (@Sendable () -> Void)?

  // `beforeWrite` lets a test hold a write between taking its snapshot and writing it.
  init(url: URL, beforeWrite: (@Sendable () -> Void)? = nil) {
    self.url = url
    self.beforeWrite = beforeWrite
  }

  static func key(relativePath: String, modified: Date?) -> String {
    "\(relativePath)|\((modified?.roundedEpochMs ?? 0))"
  }

  func info(for file: URL, key: String) async -> MediaInfo {
    if let hit = lock.withLock({ loaded()[key] }) { return hit }
    let info = await Self.read(file)
    lock.withLock {
      _ = loaded()
      entries?[key] = info
      dirty = true
    }
    return info
  }

  // Drops the entries under `prefixes` that are not in `keys` (files gone or replaced), then writes if anything
  // changed. Entries of other folders stay for when the user switches back.
  func save(keeping keys: Set<String>, under prefixes: [String]) {
    let snapshot: (entries: [String: MediaInfo], number: Int)? = lock.withLock {
      var all = loaded()
      let stale = all.keys.filter { key in !keys.contains(key) && prefixes.contains(where: key.hasPrefix) }
      for key in stale { all.removeValue(forKey: key) }
      entries = all
      guard dirty || !stale.isEmpty else { return nil }
      dirty = false
      snapshots += 1
      return (all, snapshots)
    }
    guard let snapshot else { return }
    beforeWrite?()
    writeLock.withLock {
      guard snapshot.number > written else { return }
      written = snapshot.number
      do {
        try JSONEncoder().encode(snapshot.entries).writeAtomically(to: url)
      } catch {
        Log.library.error("Library info cache not written: \(error.localizedDescription, privacy: .public)")
      }
    }
  }

  // Under the lock. A missing or corrupt file starts an empty cache.
  private func loaded() -> [String: MediaInfo] {
    if let entries { return entries }
    let read = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode([String: MediaInfo].self, from: $0) }
    entries = read ?? [:]
    return entries!
  }

  // A file AVFoundation cannot open (corrupt, empty, a format it does not know) has no metadata; it still lists.
  private static func read(_ file: URL) async -> MediaInfo {
    let asset = AVURLAsset(url: file)
    guard let loaded = try? await asset.load(.duration, .tracks) else { return MediaInfo() }
    let (duration, tracks) = loaded
    var info = MediaInfo()
    if duration.isNumeric, duration.seconds > 0 {
      info.durationMs = Int64((duration.seconds * 1000).rounded())
    }
    if let video = tracks.first(where: { $0.mediaType == .video }),
      let geometry = try? await video.load(.naturalSize, .preferredTransform)
    {
      let shown = geometry.0.applying(geometry.1)
      let width = Int64(abs(shown.width).rounded())
      let height = Int64(abs(shown.height).rounded())
      if width > 0, height > 0 {
        info.width = width
        info.height = height
      }
    }
    return info
  }
}
