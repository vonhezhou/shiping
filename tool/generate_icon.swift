import AppKit

// Run from the project root: swift tool/generate_icon.swift
let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
  .appendingPathComponent("macos/Runner/Assets.xcassets/AppIcon.appiconset")
for size in [16, 32, 64, 128, 256, 512, 1024] {
  guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
    let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else { fatalError("Cannot create icon bitmap") }
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = graphics
  let context = graphics.cgContext
  context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
  context.setFillColor(NSColor(srgbRed: 0.84, green: 0.98, blue: 0.42, alpha: 1).cgColor)
  context.addPath(CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824),
    cornerWidth: 185, cornerHeight: 185, transform: nil))
  context.fillPath()
  context.setFillColor(NSColor(srgbRed: 0.1, green: 0.14, blue: 0.06, alpha: 1).cgColor)
  context.fill(CGRect(x: 294, y: 273, width: 96, height: 478))
  context.fill(CGRect(x: 294, y: 655, width: 428, height: 96))
  context.fill(CGRect(x: 294, y: 463, width: 323, height: 82))
  context.setFillColor(NSColor(srgbRed: 0.84, green: 0.98, blue: 0.42, alpha: 1).cgColor)
  context.fill(CGRect(x: 452, y: 691, width: 26, height: 60))
  context.fill(CGRect(x: 570, y: 713, width: 26, height: 38))
  context.fill(CGRect(x: 685, y: 691, width: 26, height: 60))
  NSGraphicsContext.restoreGraphicsState()
  guard let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("Cannot encode icon") }
  try data.write(to: directory.appendingPathComponent("app_icon_\(size).png"))
}
print("Generated fruler icons (7 sizes).")
