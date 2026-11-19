import AVFoundation
import CryptoKit
import Foundation
import ImageIO
import QuickLookThumbnailing
import UniformTypeIdentifiers

// A library card's picture as a cached JPEG, so Flutter's image cache can hit on scroll-back. Never evicted, as on
// Android: a replaced file orphans its old JPEG, and iOS clears Caches under pressure.
struct Thumbnails {
  private static let quality = 0.85

  let dir: URL

  init(caches: URL) {
    dir = caches.appendingPathComponent("thumbs", isDirectory: true)
  }

  // `file` is already checked to be inside Documents, and `relativePath` is its path there. Nil when it has no
  // picture (a plain MP3, a corrupt video) or is gone.
  func thumbnail(for file: URL, relativePath: String, widthPx: Int, heightPx: Int) async -> String? {
    guard widthPx > 0, heightPx > 0,
      let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey]),
      values.isRegularFile == true
    else { return nil }
    let key = MediaInfoCache.key(relativePath: relativePath, modified: values.contentModificationDate)
    let target = dir.appendingPathComponent("\(Self.sha256("\(key)|\(widthPx)x\(heightPx)")).jpg", isDirectory: false)
    if FileManager.default.fileExists(atPath: target.path) { return target.path }
    let box = CGSize(width: widthPx, height: heightPx)
    guard let image = await Self.picture(of: file, fitting: box) else { return nil }
    return write(Self.fit(image, in: box), to: target)
  }

  // Audio: only its embedded artwork, because QuickLook answers a plain MP3 with a generic placeholder. Video:
  // QuickLook, else a frame at 10 % of the duration.
  private static func picture(of file: URL, fitting box: CGSize) async -> CGImage? {
    if UTType(filenameExtension: file.pathExtension)?.conforms(to: .audio) == true {
      return await artwork(of: AVURLAsset(url: file))
    }
    let request = QLThumbnailGenerator.Request(fileAt: file, size: box, scale: 1, representationTypes: .thumbnail)
    if let shot = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
      return shot.cgImage
    }
    return await frame(of: file, fitting: box)
  }

  // A frame at 10 % of the duration, fitted to the box; nil without a video track that decodes.
  static func frame(of file: URL, fitting box: CGSize) async -> CGImage? {
    let asset = AVURLAsset(url: file)
    guard let (duration, tracks) = try? await asset.load(.duration, .tracks),
      tracks.contains(where: { $0.mediaType == .video })
    else { return nil }
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = box
    let at = duration.isNumeric ? CMTimeMultiplyByFloat64(duration, multiplier: 0.1) : .zero
    guard let image = try? await generator.image(at: at).image else { return nil }
    return fit(image, in: box)
  }

  private static func artwork(of asset: AVURLAsset) async -> CGImage? {
    guard let metadata = try? await asset.load(.commonMetadata) else { return nil }
    for item in AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: .commonIdentifierArtwork) {
      guard let data = try? await item.load(.dataValue),
        let source = CGImageSourceCreateWithData(data as CFData, nil),
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
      else { continue }
      return image
    }
    return nil
  }

  // Scaled down to fit the box, never up; the extractors' own size limits are not all exact.
  private static func fit(_ image: CGImage, in box: CGSize) -> CGImage {
    let scale = min(box.width / CGFloat(image.width), box.height / CGFloat(image.height))
    guard scale < 1 else { return image }
    let width = max(1, Int((CGFloat(image.width) * scale).rounded()))
    let height = max(1, Int((CGFloat(image.height) * scale).rounded()))
    guard
      let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { return image }
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage() ?? image
  }

  // A temp name renamed into place, so a second caller never reads a half-written JPEG.
  private func write(_ image: CGImage, to target: URL) -> String? {
    let tmp = dir.appendingPathComponent(".\(UUID().uuidString).tmp", isDirectory: false)
    defer { try? FileManager.default.removeItem(at: tmp) }
    guard (try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)) != nil,
      let out = CGImageDestinationCreateWithURL(tmp as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
    else { return nil }
    CGImageDestinationAddImage(out, image, [kCGImageDestinationLossyCompressionQuality: Self.quality] as CFDictionary)
    guard CGImageDestinationFinalize(out), rename(tmp.path, target.path) == 0 else { return nil }
    return target.path
  }

  private static func sha256(_ text: String) -> String {
    SHA256.hash(data: Data(text.utf8)).hex
  }
}
