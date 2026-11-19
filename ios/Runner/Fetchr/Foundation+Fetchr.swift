import Foundation
import os

enum Log {
  private static let subsystem = "com.defo.fetchr"
  static let downloads = Logger(subsystem: subsystem, category: "downloads")
  static let library = Logger(subsystem: subsystem, category: "library")
  static let picker = Logger(subsystem: subsystem, category: "picker")
  static let python = Logger(subsystem: subsystem, category: "python")
  static let ytdlp = Logger(subsystem: subsystem, category: "ytdlp")
}

extension Date {
  // Truncated, as Android's System.currentTimeMillis.
  var epochMs: Int64 { Int64(timeIntervalSince1970 * 1000) }
  // Rounded, for file dates, which the library and its cache key compare.
  var roundedEpochMs: Int64 { Int64((timeIntervalSince1970 * 1000).rounded()) }
}

extension URL {
  // Checked before it is set, so a folder made before the rule gets the flag too and one already marked costs a read.
  func excludeFromBackup() {
    var url = self
    guard (try? url.resourceValues(forKeys: [.isExcludedFromBackupKey]))?.isExcludedFromBackup != true else { return }
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try? url.setResourceValues(values)
  }
}

extension Data {
  func writeAtomically(to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try write(to: url, options: .atomic)
  }
}

extension Sequence where Element == UInt8 {
  var hex: String { map { String(format: "%02x", $0) }.joined() }
}

extension FileManager {
  // nil when nothing is there.
  func isDirectory(atPath path: String) -> Bool? {
    var isDir: ObjCBool = false
    return fileExists(atPath: path, isDirectory: &isDir) ? isDir.boolValue : nil
  }
}
