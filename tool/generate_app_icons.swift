import AppKit
import CoreGraphics
import Foundation
import ImageIO

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let macIconDir = root.appendingPathComponent("macos/Runner/Assets.xcassets/AppIcon.appiconset")
let windowsIcon = root.appendingPathComponent("windows/runner/resources/app_icon.ico")
let brandDir = root.appendingPathComponent("assets/brand")

let colorSpace = CGColorSpaceCreateDeviceRGB()

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
  let r = CGFloat((hex >> 16) & 0xff) / 255
  let g = CGFloat((hex >> 8) & 0xff) / 255
  let b = CGFloat(hex & 0xff) / 255
  return CGColor(red: r, green: g, blue: b, alpha: alpha)
}

func roundedRect(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
  CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func fillRounded(_ ctx: CGContext, _ rect: CGRect, _ radius: CGFloat, _ fill: CGColor) {
  ctx.addPath(roundedRect(rect, radius))
  ctx.setFillColor(fill)
  ctx.fillPath()
}

func strokeLine(_ ctx: CGContext, _ points: [CGPoint], _ stroke: CGColor, _ width: CGFloat) {
  guard let first = points.first else { return }
  ctx.beginPath()
  ctx.move(to: first)
  for point in points.dropFirst() {
    ctx.addLine(to: point)
  }
  ctx.setStrokeColor(stroke)
  ctx.setLineWidth(width)
  ctx.setLineCap(.round)
  ctx.setLineJoin(.round)
  ctx.strokePath()
}

func pngData(size: Int) throws -> Data {
  let scale = CGFloat(size) / 1024
  let bytesPerRow = size * 4
  guard
    let ctx = CGContext(
      data: nil,
      width: size,
      height: size,
      bitsPerComponent: 8,
      bytesPerRow: bytesPerRow,
      space: colorSpace,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
  else {
    throw NSError(domain: "IconGenerator", code: 1)
  }

  func p(_ value: CGFloat) -> CGFloat { value * scale }
  func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
    CGRect(x: p(x), y: p(y), width: p(w), height: p(h))
  }

  ctx.translateBy(x: 0, y: CGFloat(size))
  ctx.scaleBy(x: 1, y: -1)
  ctx.clear(CGRect(x: 0, y: 0, width: size, height: size))

  let bgRect = r(74, 76, 876, 876)
  let bgPath = roundedRect(bgRect, p(205))

  ctx.saveGState()
  ctx.setShadow(offset: CGSize(width: 0, height: p(24)), blur: p(34), color: color(0x001018, alpha: 0.28))
  ctx.addPath(bgPath)
  ctx.setFillColor(color(0x0B3A35))
  ctx.fillPath()
  ctx.restoreGState()

  ctx.saveGState()
  ctx.addPath(bgPath)
  ctx.clip()
  let gradient = CGGradient(
    colorsSpace: colorSpace,
    colors: [color(0x123C7C), color(0x0F4C5C), color(0x0B3A35)] as CFArray,
    locations: [0, 0.55, 1]
  )!
  ctx.drawLinearGradient(
    gradient,
    start: CGPoint(x: p(128), y: p(96)),
    end: CGPoint(x: p(896), y: p(928)),
    options: []
  )

  ctx.beginPath()
  ctx.move(to: CGPoint(x: p(-24), y: p(766)))
  ctx.addLine(to: CGPoint(x: p(802), y: p(-60)))
  ctx.addLine(to: CGPoint(x: p(1024), y: p(-60)))
  ctx.addLine(to: CGPoint(x: p(1024), y: p(202)))
  ctx.addLine(to: CGPoint(x: p(208), y: p(1018)))
  ctx.addLine(to: CGPoint(x: p(-24), y: p(1018)))
  ctx.closePath()
  ctx.setFillColor(color(0x2563EB, alpha: 0.18))
  ctx.fillPath()
  ctx.restoreGState()

  strokeLine(ctx, [CGPoint(x: p(190), y: p(678)), CGPoint(x: p(326), y: p(678))], color(0x7DE7F7, alpha: 0.88), p(34))
  strokeLine(ctx, [CGPoint(x: p(698), y: p(334)), CGPoint(x: p(842), y: p(334))], color(0x7DE7F7, alpha: 0.88), p(34))
  fillRounded(ctx, r(152, 640, 76, 76), p(38), color(0xF2B84B))
  fillRounded(ctx, r(804, 296, 76, 76), p(38), color(0x39D783))

  ctx.saveGState()
  ctx.setShadow(offset: CGSize(width: 0, height: p(28)), blur: p(28), color: color(0x001018, alpha: 0.28))
  fillRounded(ctx, r(304, 150, 416, 724), p(76), color(0xF4FFF9))
  ctx.restoreGState()

  fillRounded(ctx, r(342, 244, 340, 496), p(46), color(0x0B252B))
  fillRounded(ctx, r(446, 196, 132, 18), p(9), color(0x0B252B, alpha: 0.62))
  fillRounded(ctx, r(474, 790, 76, 20), p(10), color(0x0B252B, alpha: 0.38))

  strokeLine(
    ctx,
    [CGPoint(x: p(430), y: p(424)), CGPoint(x: p(492), y: p(496)), CGPoint(x: p(430), y: p(568))],
    color(0x39D783),
    p(40)
  )
  strokeLine(ctx, [CGPoint(x: p(538), y: p(568)), CGPoint(x: p(622), y: p(568))], color(0x7DE7F7), p(36))
  fillRounded(ctx, r(472, 798, 80, 42), p(4), color(0xF2B84B))

  guard
    let image = ctx.makeImage(),
    let mutableData = CFDataCreateMutable(nil, 0),
    let destination = CGImageDestinationCreateWithData(mutableData, "public.png" as CFString, 1, nil)
  else {
    throw NSError(domain: "IconGenerator", code: 2)
  }
  CGImageDestinationAddImage(destination, image, nil)
  guard CGImageDestinationFinalize(destination) else {
    throw NSError(domain: "IconGenerator", code: 3)
  }
  return mutableData as Data
}

extension Data {
  mutating func appendUInt16LE(_ value: UInt16) {
    append(UInt8(value & 0xff))
    append(UInt8((value >> 8) & 0xff))
  }

  mutating func appendUInt32LE(_ value: UInt32) {
    append(UInt8(value & 0xff))
    append(UInt8((value >> 8) & 0xff))
    append(UInt8((value >> 16) & 0xff))
    append(UInt8((value >> 24) & 0xff))
  }
}

func writeWindowsIcon(images: [(size: Int, data: Data)], to url: URL) throws {
  var output = Data()
  output.appendUInt16LE(0)
  output.appendUInt16LE(1)
  output.appendUInt16LE(UInt16(images.count))

  var offset = 6 + images.count * 16
  for image in images {
    output.append(UInt8(image.size == 256 ? 0 : image.size))
    output.append(UInt8(image.size == 256 ? 0 : image.size))
    output.append(0)
    output.append(0)
    output.appendUInt16LE(1)
    output.appendUInt16LE(32)
    output.appendUInt32LE(UInt32(image.data.count))
    output.appendUInt32LE(UInt32(offset))
    offset += image.data.count
  }

  for image in images {
    output.append(image.data)
  }
  try output.write(to: url)
}

try FileManager.default.createDirectory(at: brandDir, withIntermediateDirectories: true)

for size in [16, 32, 64, 128, 256, 512, 1024] {
  let data = try pngData(size: size)
  try data.write(to: macIconDir.appendingPathComponent("app_icon_\(size).png"))
  if size == 1024 {
    try data.write(to: brandDir.appendingPathComponent("app_logo.png"))
  }
}

let icoImages = try [16, 32, 48, 64, 128, 256].map { size in
  (size: size, data: try pngData(size: size))
}
try writeWindowsIcon(images: icoImages, to: windowsIcon)

print("Generated app icons for macOS, Windows, and assets/brand/app_logo.png")
