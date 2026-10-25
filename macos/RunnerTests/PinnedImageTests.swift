import Cocoa
import XCTest
@testable import fruler

final class PinnedImageTests: XCTestCase {
  func testZoomKeepsPointerAnchorAndClampsScale() {
    let frame = NSRect(x: -600, y: 80, width: 200, height: 100)
    let anchor = NSPoint(x: -450, y: 100)
    let enlarged = PinnedImageGeometry.scaledFrame(frame, size: NSSize(width: 400, height: 200), anchor: anchor)
    XCTAssertEqual(enlarged, NSRect(x: -750, y: 60, width: 400, height: 200))
    XCTAssertEqual(PinnedImageGeometry.clampedScale(-1), 0.05)
    XCTAssertEqual(PinnedImageGeometry.clampedScale(100), 16)
    XCTAssertEqual(PinnedImageGeometry.clampedScale(.nan), 1)
  }

  func testFitNeverUpscalesAndKeepsLargeImagesReachable() {
    let screen = NSRect(x: -1200, y: -100, width: 1000, height: 700)
    let scale = PinnedImageGeometry.fitScale(size: NSSize(width: 2000, height: 1000), screen: screen)
    XCTAssertEqual(scale, 0.45, accuracy: 0.0001)
    XCTAssertEqual(PinnedImageGeometry.fitScale(size: NSSize(width: 10, height: 10), screen: screen), 1)
    let frame = PinnedImageGeometry.visibleFrame(NSRect(x: 3000, y: 3000, width: 400, height: 200), screen: screen)
    XCTAssertTrue(screen.contains(frame))
  }

  func testTransformExportsFullPixelsInDisplayOrder() throws {
    // 非方形二维色块检查旋转方向和坐标轴，而非仅检查导出尺寸。
    let image = sampleImage()
    XCTAssertEqual(pixelBytes(try PinnedImageTransform(flipHorizontal: true).render(image)),
      colorBytes([2,1,0, 5,4,3]))
    XCTAssertEqual(pixelBytes(try PinnedImageTransform(flipVertical: true).render(image)),
      colorBytes([3,4,5, 0,1,2]))
    let clockwise = try PinnedImageTransform(quarterTurns: 1).render(image)
    XCTAssertEqual(clockwise.width, 2)
    XCTAssertEqual(clockwise.height, 3)
    XCTAssertEqual(pixelBytes(clockwise), colorBytes([3,0, 4,1, 5,2]))
    let anticlockwise = try PinnedImageTransform(quarterTurns: 3).render(image)
    XCTAssertEqual(pixelBytes(anticlockwise), colorBytes([2,5, 1,4, 0,3]))
    XCTAssertEqual(pixelBytes(try PinnedImageTransform(quarterTurns: 4).render(image)), colorBytes([0,1,2,3,4,5]))
  }

  func testRotateAfterFlipActsOnVisibleImageAndResetPreservesCenter() throws {
    let image = sampleImage()
    let panel = PinnedImagePanel(id: 1, image: image, logicalSize: NSSize(width: 300, height: 200),
      center: NSPoint(x: 400, y: 300), visibleFrame: NSRect(x: 0, y: 0, width: 1100, height: 760))
    defer { panel.close() }
    let center = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
    XCTAssertTrue(panel.performAction("flip_horizontal"))
    XCTAssertTrue(panel.performAction("rotate_right"))
    XCTAssertEqual(pixelBytes(panel.renderedImage), colorBytes([5,2, 4,1, 3,0]))
    XCTAssertEqual(panel.frame.size, NSSize(width: 200, height: 300))
    panel.setScale(2)
    panel.adjustOpacity(-0.5)
    let png = try panel.exportPNG()
    let exported = NSBitmapImageRep(data: png)!.cgImage!
    XCTAssertEqual(exported.width, 2)
    XCTAssertEqual(exported.height, 3)
    XCTAssertEqual(pixelBytes(exported), colorBytes([5,2, 4,1, 3,0]))
    panel.resetImage()
    XCTAssertEqual(panel.scale, 1)
    XCTAssertEqual(panel.alphaValue, 1)
    XCTAssertEqual(panel.frame.size, NSSize(width: 300, height: 200))
    XCTAssertEqual(NSPoint(x: panel.frame.midX, y: panel.frame.midY), center)
    XCTAssertEqual(pixelBytes(panel.renderedImage), colorBytes([0,1,2,3,4,5]))
  }

  func testDisconnectedDisplayMovesToNearestVisibleScreen() {
    let frame = NSRect(x: -1800, y: 80, width: 200, height: 100)
    let left = NSRect(x: -1000, y: 0, width: 1000, height: 700)
    let right = NSRect(x: 0, y: 0, width: 1100, height: 760)
    XCTAssertEqual(PinnedImageGeometry.bestScreen(for: frame, screens: [right, left]), left)
    XCTAssertTrue(left.contains(PinnedImageGeometry.visibleFrame(frame, screen: left)))
    XCTAssertNil(PinnedImageGeometry.bestScreen(for: frame, screens: []))
  }

  func testClipboardTextAndHexColorRenderWithoutTruncatingLines() throws {
    let color = try ClipboardPinRenderer.render("#12AB34")
    XCTAssertEqual(color.width, 240)
    XCTAssertEqual(color.height, 180)
    let short = try ClipboardPinRenderer.render("你好，fruler")
    let multiline = try ClipboardPinRenderer.render(Array(repeating: "多行文字", count: 100).joined(separator: "\n"))
    XCTAssertGreaterThan(multiline.height, 1600)
    XCTAssertGreaterThan(multiline.height, short.height)
  }

  func testManagerHidesWithoutDestroyingAndCloseReleasesWindows() throws {
    let manager = PinnedImageManager()
    defer { manager.closeAll() }
    weak var retained: PinnedImagePanel?
    try autoreleasepool {
      try manager.pin(png: samplePNG(), logicalSize: NSSize(width: 100, height: 60), center: nil)
      try manager.pin(png: samplePNG(), logicalSize: NSSize(width: 80, height: 40), center: nil)
      XCTAssertEqual(manager.panels.count, 2)
      XCTAssertTrue(manager.panels.allSatisfy { $0.isVisible && !$0.hidesOnDeactivate })
      XCTAssertTrue(manager.panels.allSatisfy { $0.styleMask.contains(.nonactivatingPanel) })
      retained = manager.panels.first
      manager.toggleVisibility()
      XCTAssertTrue(manager.panels.allSatisfy { !$0.isVisible })
      XCTAssertNotNil(retained)
      manager.toggleVisibility()
      XCTAssertTrue(manager.panels.allSatisfy { $0.isVisible })
      manager.closeAll()
      XCTAssertTrue(manager.panels.isEmpty)
    }
    // AppKit 窗口注册会产生 autorelease 临时引用，池排空后检查实际持有关系。
    XCTAssertNil(retained)
  }

  func testResourceLimitsRejectWithoutChangingExistingPins() throws {
    let manager = PinnedImageManager(maximumCount: 2, maximumPixelCount: 10)
    defer { manager.closeAll() }
    try manager.pin(png: samplePNG(), logicalSize: nil, center: nil)
    let existing = manager.panels[0]
    XCTAssertThrowsError(try manager.pin(png: samplePNG(), logicalSize: nil, center: nil)) { error in
      guard case PinImageError.resourceLimit = error else { return XCTFail("Expected pixel budget error") }
    }
    XCTAssertEqual(manager.panels.count, 1)
    XCTAssertTrue(manager.panels[0] === existing)
    XCTAssertTrue(existing.isVisible)
    let countLimited = PinnedImageManager(maximumCount: 1)
    defer { countLimited.closeAll() }
    try countLimited.pin(png: samplePNG(), logicalSize: nil, center: nil)
    XCTAssertThrowsError(try countLimited.pin(png: samplePNG(), logicalSize: nil, center: nil))
    XCTAssertEqual(countLimited.panels.count, 1)
    XCTAssertThrowsError(try ClipboardPinRenderer.render(String(repeating: "字", count: 100_001))) { error in
      guard case PinImageError.resourceLimit = error else { return XCTFail("Expected text budget error") }
    }
  }

  func testInvalidImageNeverCreatesWindow() {
    let manager = PinnedImageManager()
    XCTAssertThrowsError(try manager.pin(png: Data([1,2,3]), logicalSize: nil, center: nil))
    XCTAssertTrue(manager.panels.isEmpty)
  }

  private func colorBytes(_ order: [Int]) -> [UInt8] {
    let colors: [[UInt8]] = [[255,0,0,255], [0,255,0,255], [0,0,255,255],
      [255,255,0,255], [0,255,255,255], [255,0,255,255]]
    return order.flatMap { colors[$0] }
  }

  private func sampleImage() -> CGImage {
    let provider = CGDataProvider(data: Data(colorBytes([0,1,2,3,4,5])) as CFData)!
    return CGImage(width: 3, height: 2, bitsPerComponent: 8, bitsPerPixel: 32,
      bytesPerRow: 12, space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
      provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
  }

  private func samplePNG() -> Data {
    NSBitmapImageRep(cgImage: sampleImage()).representation(using: .png, properties: [:])!
  }

  private func pixelBytes(_ image: CGImage) -> [UInt8] {
    var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
    bytes.withUnsafeMutableBytes { storage in
      let context = CGContext(data: storage.baseAddress, width: image.width, height: image.height,
        bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
      context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    return bytes
  }
}
