import Compression
import Foundation

// Reads the zip yt-dlp ships as its zipapp (a `#!` line, then a zip). iOS has no zip API. Only plain files, stored or
// deflated, under relative paths are accepted: anything else could write outside the target or be a link to
// somewhere else.
struct ZipExtractor {
  struct Refused: Error, CustomStringConvertible {
    let description: String
  }

  struct Limits {
    var maxEntries: Int
    var maxTotalBytes: Int

    static let standard = Limits(maxEntries: 20_000, maxTotalBytes: 256 << 20)
  }

  private struct Entry {
    let name: String
    let method: UInt16
    let crc: UInt32
    let packedSize: Int
    let size: Int
    let localOffset: Int
    let isDirectory: Bool
  }

  // Into a `.partial` sibling first, renamed onto `dir` once every entry is written and checked; a refused or
  // interrupted archive leaves no `dir`.
  static func extract(_ zip: URL, to dir: URL, limits: Limits = .standard) throws {
    let fm = FileManager.default
    let partial = URL(fileURLWithPath: dir.standardizedFileURL.path + ".partial", isDirectory: true)
    try? fm.removeItem(at: partial)
    do {
      let data = try Data(contentsOf: zip, options: .alwaysMapped)
      let (entries, base) = try centralDirectory(data, limits: limits)
      try fm.createDirectory(at: partial, withIntermediateDirectories: true)
      for entry in entries {
        let target = partial.appendingPathComponent(entry.name, isDirectory: entry.isDirectory)
        if entry.isDirectory {
          try fm.createDirectory(at: target, withIntermediateDirectories: true)
          continue
        }
        let body = try contents(of: entry, in: data, base: base)
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard fm.createFile(atPath: target.path, contents: body) else {
          throw CocoaError(.fileWriteUnknown)
        }
      }
      try? fm.removeItem(at: dir)
      try fm.moveItem(at: partial, to: dir)
    } catch {
      try? fm.removeItem(at: partial)
      throw error
    }
  }

  // Every entry is checked before anything is written.
  private static func centralDirectory(_ data: Data, limits: Limits) throws -> ([Entry], Int) {
    guard let end = endRecord(data) else { throw Refused(description: "not a zip") }
    guard data.u16(end + 4) == 0, data.u16(end + 6) == 0 else { throw Refused(description: "a multi-part zip") }
    let count = Int(data.u16(end + 10))
    let size = Int(data.u32(end + 12))
    let offset = Int(data.u32(end + 16))
    guard count != 0xFFFF, size != 0xFFFF_FFFF, offset != 0xFFFF_FFFF else {
      throw Refused(description: "a zip64 archive")
    }
    guard count <= limits.maxEntries else { throw Refused(description: "\(count) entries") }
    // Offsets count from the start of the zip, which in a zipapp sits after the `#!` line.
    let start = end - size
    let base = start - offset
    guard start >= 0, base >= 0 else { throw Refused(description: "a damaged central directory") }

    var entries: [Entry] = []
    var names = Set<String>()
    var at = start
    for _ in 0..<count {
      guard at + 46 <= end, data.u32(at) == 0x0201_4b50 else { throw Refused(description: "a damaged central directory") }
      let flags = data.u16(at + 8)
      let method = data.u16(at + 10)
      let nameLength = Int(data.u16(at + 28))
      let extraLength = Int(data.u16(at + 30))
      let commentLength = Int(data.u16(at + 32))
      let mode = data.u32(at + 38) >> 16
      guard at + 46 + nameLength <= end,
        let name = String(data: data.subdata(in: (at + 46)..<(at + 46 + nameLength)), encoding: .utf8)
      else { throw Refused(description: "an entry name that is not UTF-8") }
      guard flags & 1 == 0 else { throw Refused(description: "an encrypted entry \(name)") }
      guard method == 0 || method == 8 else { throw Refused(description: "compression method \(method) in \(name)") }
      let type = mode & 0o170000
      guard type == 0 || type == 0o100000 || type == 0o040000 else {
        throw Refused(description: "\(name) is a link or a special file")
      }
      let isDirectory = name.hasSuffix("/")
      let clean = try safeName(isDirectory ? String(name.dropLast()) : name)
      guard names.insert(clean).inserted else { throw Refused(description: "\(name) appears twice") }
      entries.append(
        Entry(
          name: clean, method: method, crc: data.u32(at + 16), packedSize: Int(data.u32(at + 20)),
          size: Int(data.u32(at + 24)), localOffset: base + Int(data.u32(at + 42)), isDirectory: isDirectory))
      at += 46 + nameLength + extraLength + commentLength
    }
    let total = entries.reduce(0) { $0 + $1.size }
    guard total <= limits.maxTotalBytes else { throw Refused(description: "\(total) bytes uncompressed") }
    // A file entry inside a path another entry writes as a file would fail half way; refuse it up front.
    let files = Set(entries.filter { !$0.isDirectory }.map(\.name))
    for entry in entries {
      var parent = (entry.name as NSString).deletingLastPathComponent
      while !parent.isEmpty {
        if files.contains(parent) { throw Refused(description: "\(entry.name) is inside the file \(parent)") }
        parent = (parent as NSString).deletingLastPathComponent
      }
    }
    return (entries, base)
  }

  // A relative path of ordinary components: no leading `/`, no `\`, no empty, `.` or `..` part.
  private static func safeName(_ name: String) throws -> String {
    let parts = name.split(separator: "/", omittingEmptySubsequences: false)
    guard !name.isEmpty, !name.contains("\\"), !name.contains("\0"),
      parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." })
    else { throw Refused(description: "an unsafe entry name \(name)") }
    return name
  }

  private static func endRecord(_ data: Data) -> Int? {
    guard data.count >= 22 else { return nil }
    let lowest = max(0, data.count - 22 - 0xFFFF)
    var at = data.count - 22
    while at >= lowest {
      if data.u32(at) == 0x0605_4b50 { return at }
      at -= 1
    }
    return nil
  }

  private static func contents(of entry: Entry, in data: Data, base: Int) throws -> Data {
    let header = entry.localOffset
    guard header + 30 <= data.count, data.u32(header) == 0x0403_4b50 else {
      throw Refused(description: "a damaged entry \(entry.name)")
    }
    let start = header + 30 + Int(data.u16(header + 26)) + Int(data.u16(header + 28))
    guard start + entry.packedSize <= data.count else { throw Refused(description: "a truncated entry \(entry.name)") }
    let packed = data.subdata(in: start..<(start + entry.packedSize))
    let body: Data
    if entry.method == 0 {
      guard entry.packedSize == entry.size else { throw Refused(description: "a damaged entry \(entry.name)") }
      body = packed
    } else {
      body = try inflate(packed, size: entry.size, name: entry.name)
    }
    guard crc32(body) == entry.crc else { throw Refused(description: "a checksum mismatch in \(entry.name)") }
    return body
  }

  // Compression's ZLIB is raw DEFLATE, the zip format's method 8.
  private static func inflate(_ packed: Data, size: Int, name: String) throws -> Data {
    guard size > 0 else { return Data() }
    guard !packed.isEmpty else { throw Refused(description: "a damaged entry \(name)") }
    var out = Data(count: size)
    let written = out.withUnsafeMutableBytes { dst in
      packed.withUnsafeBytes { src in
        compression_decode_buffer(
          dst.bindMemory(to: UInt8.self).baseAddress!, size, src.bindMemory(to: UInt8.self).baseAddress!,
          packed.count, nil, COMPRESSION_ZLIB)
      }
    }
    guard written == size else { throw Refused(description: "a damaged entry \(name)") }
    return out
  }

  private static let crcTable: [UInt32] = (0..<256).map { n in
    var c = UInt32(n)
    for _ in 0..<8 { c = c & 1 != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
    return c
  }

  static func crc32(_ data: Data) -> UInt32 {
    var crc: UInt32 = 0xFFFF_FFFF
    data.withUnsafeBytes { bytes in
      for byte in bytes {
        crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
      }
    }
    return crc ^ 0xFFFF_FFFF
  }
}

extension Data {
  fileprivate func u16(_ at: Int) -> UInt16 {
    let i = startIndex + at
    return UInt16(self[i]) | UInt16(self[i + 1]) << 8
  }

  fileprivate func u32(_ at: Int) -> UInt32 {
    let i = startIndex + at
    return UInt32(self[i]) | UInt32(self[i + 1]) << 8 | UInt32(self[i + 2]) << 16 | UInt32(self[i + 3]) << 24
  }
}
