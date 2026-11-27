import AppKit

// 在项目根目录运行：swift tool/generate_icon.swift
let assets = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
  .appendingPathComponent("macos/Runner/Assets.xcassets")

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> CGColor {
  NSColor(srgbRed: red, green: green, blue: blue, alpha: 1).cgColor
}

// App 与菜单栏共用轮廓；少量宽刻度保证 18 pt 下仍可辨认。
func drawRuler(_ context: CGContext, in rect: CGRect, orange: Bool) {
  context.saveGState()
  context.translateBy(x: rect.minX, y: rect.minY)
  context.scaleBy(x: rect.width, y: rect.height)
  context.beginTransparencyLayer(auxiliaryInfo: nil)
  let path = CGMutablePath()
  path.move(to: CGPoint(x: 0, y: 0.06))
  path.addQuadCurve(to: CGPoint(x: 0.085, y: 0.025), control: .zero)
  path.addLine(to: CGPoint(x: 0.975, y: 0.915))
  path.addQuadCurve(to: CGPoint(x: 0.94, y: 1), control: CGPoint(x: 1.06, y: 1))
  path.addLine(to: CGPoint(x: 0.06, y: 1))
  path.addQuadCurve(to: CGPoint(x: 0, y: 0.94), control: CGPoint(x: 0, y: 1))
  path.closeSubpath()
  path.move(to: CGPoint(x: 0.16, y: 0.43))
  path.addQuadCurve(to: CGPoint(x: 0.19, y: 0.415), control: CGPoint(x: 0.16, y: 0.385))
  path.addLine(to: CGPoint(x: 0.575, y: 0.8))
  path.addQuadCurve(to: CGPoint(x: 0.56, y: 0.84), control: CGPoint(x: 0.615, y: 0.84))
  path.addLine(to: CGPoint(x: 0.185, y: 0.84))
  path.addQuadCurve(to: CGPoint(x: 0.16, y: 0.815), control: CGPoint(x: 0.16, y: 0.84))
  path.closeSubpath()
  context.saveGState()
  context.addPath(path)
  context.clip(using: .evenOdd)
  if orange {
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
      colors: [color(1, 0.70, 0.24), color(1, 0.53, 0.04)] as CFArray,
      locations: [0, 1])!
    context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0.4, y: 1), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
  } else {
    context.setFillColor(NSColor.black.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
  }
  context.restoreGState()
  context.setBlendMode(.clear)
  context.setLineWidth(0.047)
  context.setLineCap(.round)
  for position: CGFloat in [0.27, 0.52, 0.77] {
    context.beginPath()
    context.move(to: CGPoint(x: position + 0.03, y: position - 0.03))
    context.addLine(to: CGPoint(x: position - 0.055, y: position + 0.055))
    context.strokePath()
  }
  context.setBlendMode(.normal)
  context.endTransparencyLayer()
  context.restoreGState()
}

func writePNG(size: Int, to url: URL, draw: (CGContext) -> Void) throws {
  guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
    let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else { fatalError("Cannot create icon bitmap") }
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = graphics
  let context = graphics.cgContext
  context.translateBy(x: 0, y: CGFloat(size))
  context.scaleBy(x: CGFloat(size) / 1024, y: -CGFloat(size) / 1024)
  draw(context)
  NSGraphicsContext.restoreGraphicsState()
  guard let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("Cannot encode icon") }
  try data.write(to: url)
}

for size in [16, 32, 64, 128, 256, 512, 1024] {
  try writePNG(size: size, to: assets.appendingPathComponent("AppIcon.appiconset/app_icon_\(size).png")) { context in
    context.saveGState()
    context.addPath(CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824),
      cornerWidth: 185, cornerHeight: 185, transform: nil))
    context.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
      colors: [color(0.16, 0.26, 0.35), color(0.065, 0.12, 0.18)] as CFArray,
      locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 100, y: 100),
      end: CGPoint(x: 850, y: 924), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    context.restoreGState()
    drawRuler(context, in: CGRect(x: 226, y: 218, width: 572, height: 572), orange: true)
  }
}
let tray = assets.appendingPathComponent("TrayIcon.imageset")
try FileManager.default.createDirectory(at: tray, withIntermediateDirectories: true)
for scale in [1, 2] {
  try writePNG(size: 18 * scale, to: tray.appendingPathComponent("tray_icon_\(18 * scale).png")) { context in
    drawRuler(context, in: CGRect(x: 28, y: 28, width: 968, height: 968), orange: false)
  }
}
let contents = """
{
  "images" : [
    { "filename" : "tray_icon_18.png", "idiom" : "mac", "scale" : "1x" },
    { "filename" : "tray_icon_36.png", "idiom" : "mac", "scale" : "2x" }
  ],
  "info" : { "author" : "xcode", "version" : 1 },
  "properties" : { "template-rendering-intent" : "template" }
}
"""
try contents.write(to: tray.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
print("Generated fruler App icons (7 sizes) and template tray icons (1x/2x).")
