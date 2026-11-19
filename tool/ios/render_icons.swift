// Draws the iOS app icon and the launch-screen tile from the logo glyph (assets/icons/logo.svg), with the same
// geometry and colours as Android's adaptive icon and launch splash, so the three stay one logo.
// Run: swift tool/ios/render_icons.swift   (writes into ios/Runner/Assets.xcassets; the PNGs are committed)
import AppKit
import CoreGraphics
import Foundation

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
  .deletingLastPathComponent()
let assets = root.appendingPathComponent("ios/Runner/Assets.xcassets")

func color(_ hex: UInt32) -> CGColor {
  CGColor(
    srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
    blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

// android/app/src/main/res/values{,-night}/colors.xml
let lime: UInt32 = 0xC8F03C
let ink: UInt32 = 0x171714
let glyphInk: UInt32 = 0x121210
let lightBackground: UInt32 = 0xF6F5F0
let darkBackground: UInt32 = 0x121210

// The logo's path in its 24-unit viewBox: M12 4v11 m0 0-5-5 m5 5 5-5 M5 20h14, stroke 2.4, round caps and joins.
func strokeGlyph(_ ctx: CGContext, in rect: CGRect, color glyph: CGColor) {
  let unit = rect.width / 24
  func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * unit, y: rect.maxY - y * unit) }
  let path = CGMutablePath()
  path.move(to: p(12, 4)); path.addLine(to: p(12, 15))
  path.move(to: p(7, 10)); path.addLine(to: p(12, 15)); path.addLine(to: p(17, 10))
  path.move(to: p(5, 20)); path.addLine(to: p(19, 20))
  ctx.addPath(path)
  ctx.setStrokeColor(glyph)
  ctx.setLineWidth(2.4 * unit)
  ctx.setLineCap(.round)
  ctx.setLineJoin(.round)
  ctx.strokePath()
}

func render(_ size: Int, opaque: Bool, to url: URL, draw: (CGContext, CGFloat) -> Void) throws {
  let space = CGColorSpace(name: CGColorSpace.sRGB)!
  let info = opaque ? CGImageAlphaInfo.noneSkipLast.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue
  guard let ctx = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: info)
  else { throw CocoaError(.fileWriteUnknown) }
  ctx.setShouldAntialias(true)
  draw(ctx, CGFloat(size))
  let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
  try rep.representation(using: .png, properties: [:])!.write(to: url, options: .atomic)
}

func writeJSON(_ object: Any, to url: URL) throws {
  let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
  try data.write(to: url, options: .atomic)
}

let fm = FileManager.default

// App icon: one 1024 px opaque square (Xcode derives the rest); the glyph at Android's adaptive share of the
// canvas (24 units at 2.5x on 108 dp).
let iconSet = assets.appendingPathComponent("AppIcon.appiconset")
try? fm.removeItem(at: iconSet)
try fm.createDirectory(at: iconSet, withIntermediateDirectories: true)
try render(1024, opaque: true, to: iconSet.appendingPathComponent("AppIcon-1024.png")) { ctx, side in
  ctx.setFillColor(color(lime))
  ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
  let glyph = side * 60 / 108
  strokeGlyph(ctx, in: CGRect(x: (side - glyph) / 2, y: (side - glyph) / 2, width: glyph, height: glyph),
    color: color(glyphInk))
}
try writeJSON(
  [
    "images": [["filename": "AppIcon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"]],
    "info": ["author": "xcode", "version": 1],
  ], to: iconSet.appendingPathComponent("Contents.json"))

// Launch tile: Flutter's LaunchIntro tile (120 pt, radius 9/30, glyph 18/30), ink on light and lime on dark.
let tileSet = assets.appendingPathComponent("LaunchTile.imageset")
try? fm.removeItem(at: tileSet)
try fm.createDirectory(at: tileSet, withIntermediateDirectories: true)
var images: [[String: Any]] = []
for (appearance, tile, glyph) in [("light", ink, lime), ("dark", lime, glyphInk)] {
  for scale in 1...3 {
    let name = "LaunchTile-\(appearance)@\(scale)x.png"
    try render(120 * scale, opaque: false, to: tileSet.appendingPathComponent(name)) { ctx, side in
      let radius = side * 9 / 30
      ctx.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: side, height: side), cornerWidth: radius,
        cornerHeight: radius, transform: nil))
      ctx.setFillColor(color(tile))
      ctx.fillPath()
      let g = side * 18 / 30
      strokeGlyph(ctx, in: CGRect(x: (side - g) / 2, y: (side - g) / 2, width: g, height: g), color: color(glyph))
    }
    var entry: [String: Any] = ["filename": name, "idiom": "universal", "scale": "\(scale)x"]
    if appearance == "dark" {
      entry["appearances"] = [["appearance": "luminosity", "value": "dark"]]
    }
    images.append(entry)
  }
}
try writeJSON(["images": images, "info": ["author": "xcode", "version": 1]],
  to: tileSet.appendingPathComponent("Contents.json"))

// Launch background as a named colour with a dark variant.
let colorSet = assets.appendingPathComponent("LaunchBackground.colorset")
try? fm.removeItem(at: colorSet)
try fm.createDirectory(at: colorSet, withIntermediateDirectories: true)
func components(_ hex: UInt32) -> [String: Any] {
  [
    "color-space": "srgb",
    "components": [
      "alpha": "1.000", "red": String(format: "0x%02X", (hex >> 16) & 0xFF),
      "green": String(format: "0x%02X", (hex >> 8) & 0xFF), "blue": String(format: "0x%02X", hex & 0xFF),
    ],
  ]
}
try writeJSON(
  [
    "colors": [
      ["color": components(lightBackground), "idiom": "universal"],
      [
        "appearances": [["appearance": "luminosity", "value": "dark"]], "color": components(darkBackground),
        "idiom": "universal",
      ],
    ],
    "info": ["author": "xcode", "version": 1],
  ], to: colorSet.appendingPathComponent("Contents.json"))

print("render_icons: wrote AppIcon, LaunchTile and LaunchBackground into ios/Runner/Assets.xcassets")
