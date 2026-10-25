import Cocoa
import CoreImage
import FlutterMacOS
import XCTest
@testable import fruler

class RunnerTests: XCTestCase {
  func testNativeLanguageResolutionPreservesExplicitChoiceAndSystemFallback() {
    XCTAssertEqual(NativeStrings.resolve(savedLanguage: "en", preferredLanguages: ["zh-Hans-CN"]), "en")
    XCTAssertEqual(NativeStrings.resolve(savedLanguage: "zh", preferredLanguages: ["en-US"]), "zh")
    XCTAssertEqual(NativeStrings.resolve(savedLanguage: "system", preferredLanguages: ["zh-Hant-TW"]), "zh")
    XCTAssertEqual(NativeStrings.resolve(savedLanguage: nil, preferredLanguages: ["fr-FR"]), "en")
    XCTAssertEqual(NativeStrings.resolve(savedLanguage: "invalid", preferredLanguages: []), "en")
  }

  func testNativeStringsAndApplicationMenuUpdateInBothLanguages() {
    let original = NativeStrings.languageCode
    defer { NativeStrings.configure(original) }
    let menu = NSMenu()
    let item = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
    item.identifier = NSUserInterfaceItemIdentifier("l10n.menu.edit")
    item.submenu = NSMenu(title: "Edit")
    menu.addItem(item)
    for (language, title, count) in [("en", "Edit", "Clear all measurement rectangles (3)"),
                                     ("zh", "编辑", "清除全部测量框（3）")] {
      NativeStrings.configure(language)
      NativeStrings.localizeMenu(menu)
      XCTAssertEqual(item.title, title)
      XCTAssertEqual(item.submenu?.title, title)
      XCTAssertEqual(NativeStrings.text("overlay.clear_count", 3), count)
      XCTAssertNotEqual(NativeStrings.text("error.screen_permission"), "error.screen_permission")
    }
  }

  func testNativeLogsRetainLatestStartupEntriesAndDrainOnce() {
    let buffer = NativeLogBuffer(capacity: 2)
    buffer.log(800, "lifecycle", "first")
    buffer.log(900, "capture", "second")
    buffer.log(1000, "storage", "third")
    var entries: [NativeLogEntry] = []
    buffer.attach { entries.append($0) }
    XCTAssertEqual(entries.map { $0.message }, ["second", "third"])
    XCTAssertEqual(entries.map { $0.level }, [900, 1000])
    XCTAssertEqual(entries.map { $0.category }, ["capture", "storage"])
    buffer.log(800, "desktop", "live")
    XCTAssertEqual(entries.last?.message, "live")
    buffer.attach { entries.append($0) }
    XCTAssertEqual(entries.count, 3)
  }

  func testNativeLogTransportFailureBuffersWithoutRecursiveDelivery() {
    let buffer = NativeLogBuffer(capacity: 2)
    var deliveries = 0
    buffer.attach { entry in
      deliveries += 1
      buffer.pauseAndRetain(entry)
    }
    buffer.log(900, "desktop", "failed")
    buffer.log(800, "desktop", "later")
    XCTAssertEqual(deliveries, 1)
    var recovered: [String] = []
    buffer.attach { recovered.append($0.message) }
    XCTAssertEqual(recovered, ["failed", "later"])
  }

  func testColorPanelUsesNativePickersAndConfirmsOnlyOnce() {
    var replies: [Int64?] = []
    let dialog = AnnotationColorDialog(initialColor: 0x7F12AB34) { replies.append($0) }
    XCTAssertEqual(AnnotationColorDialog.argb(dialog.panel.color), 0x7F12AB34)
    XCTAssertEqual(dialog.panel.toolbar?.items.count, 5)
    XCTAssertTrue(dialog.panel.showsAlpha)
    XCTAssertEqual(dialog.panel.mode, .wheel)
    XCTAssertEqual(dialog.panel.toolbarStyle, .expanded)
    dialog.panel.color = AnnotationColorDialog.nsColor(0x80345678)
    XCTAssertTrue(replies.isEmpty)
    dialog.confirmButton.performClick(nil)
    dialog.cancelButton.performClick(nil)
    XCTAssertEqual(replies.count, 1)
    XCTAssertEqual(replies[0], 0x80345678)
    XCTAssertFalse(dialog.panel.isVisible)
  }

  func testColorPanelCancellationAndColorSpaceConversion() {
    for color: Int64 in [0x00000000, 0xFFFFFFFF, 0xFF000000, 0x8012AB34] {
      XCTAssertEqual(AnnotationColorDialog.argb(AnnotationColorDialog.nsColor(color)), color)
    }
    XCTAssertEqual(AnnotationColorDialog.argb(NSColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 0.5)), 0x80808080)
    var replied = false
    let dialog = AnnotationColorDialog(initialColor: 0xFFFFFFFF) {
      XCTAssertNil($0); replied = true
    }
    dialog.cancelButton.performClick(nil)
    XCTAssertTrue(replied)
  }

  func testWindowSelectionClipsAcrossNegativeDisplayOriginsAndRetina() {
    let local=CaptureRegionGeometry.localRect(CGRect(x:-1100,y:50,width:400,height:300),
      display:CGRect(x:-1000,y:0,width:1000,height:800))!
    XCTAssertEqual(local,CGRect(x:0,y:50,width:300,height:300))
    XCTAssertEqual(CaptureRegionGeometry.pixels(local,size:CGSize(width:1000,height:800),width:2000,height:1600),
      ["left":0,"top":100,"right":600,"bottom":700])
    XCTAssertNil(CaptureRegionGeometry.localRect(CGRect(x:10,y:10,width:20,height:20),
      display:CGRect(x:-1000,y:0,width:1000,height:800)))
  }

  func testNativeCaptureCommandContractIncludesScreenshot() {
    XCTAssertNotNil(CaptureTool(name: "screenshot"))
    let tools = ["picker", "rectangle", "horizontal", "vertical", "cross", "screenshot"]
    for name in tools {
      XCTAssertEqual(CaptureTool(name: name)?.name, name)
    }
  }

  func testNativeCaptureCommandContractRejectsUnknownCommands() {
    for value in ["", "unknown", "Screenshot", "invalid-test-tool"] {
      XCTAssertNil(CaptureTool(name: value))
    }
  }
  func testQrMenuActivationUsesItsOwnEventAndReusesScreenshotCapture() {
    XCTAssertEqual(EventKind.activateQrCode.name, "activateQrCode")
    XCTAssertEqual(EventKind(name: "activateQrCode"), .activateQrCode)
    let event = nativeEvent(["type": "activateQrCode"])
    XCTAssertEqual(event.kind, .activateQrCode)
    XCTAssertNil(event.tool)
    XCTAssertNil(CaptureTool(name: "qrCode"))
  }

  func testTypedPointerAndNudgeKeepSessionAndCoordinates() {
    let pointer = nativeEvent(["type": "pointer", "sessionId": 7, "displayId": UInt32(3),
      "x": 12.5, "y": 40.0, "phase": "drag", "button": "secondary"])
    XCTAssertEqual(pointer.kind, .pointer)
    XCTAssertEqual(pointer.sessionId, 7)
    XCTAssertEqual(pointer.displayId, 3)
    XCTAssertEqual(pointer.x, 12.5)
    XCTAssertEqual(pointer.phase, .drag)
    XCTAssertEqual(pointer.button, .secondary)
    let nudge = nativeEvent(["type": "nudge", "dx": -1, "dy": 0, "resize": true])
    XCTAssertEqual(nudge.dx, -1)
    XCTAssertEqual(nudge.resize, true)
  }

  func testFFIReferencesSurviveSessionReleaseAndFreeAfterLastReader() {
    XCTAssertNil(NativePixelBuffer(byteCount: 0))
    XCTAssertNil(frulerFrameAcquire(-1))
    var owner = NativePixelBuffer(byteCount: 32)
    weak var observed = owner
    let id = owner!.id
    owner!.data.storeBytes(of: UInt32(0xFF030201), as: UInt32.self)
    let first = frulerFrameAcquire(id)!
    let second = frulerFrameAcquire(id)!
    XCTAssertEqual(frulerFrameLength(first), 32)
    owner!.unpublish()
    owner = nil
    XCTAssertNil(frulerFrameAcquire(id))
    XCTAssertNotNil(observed)
    XCTAssertEqual(frulerFrameData(first)!.load(as: UInt32.self), 0xFF030201)
    frulerFrameRelease(first)
    XCTAssertNotNil(observed)
    frulerFrameRelease(second)
    XCTAssertNil(observed)
  }

  func testFFIAcquireReleaseAcrossThreads() {
    var owner = NativePixelBuffer(byteCount: 16)
    weak var observed = owner
    let id = owner!.id
    owner!.data.storeBytes(of: UInt8(91), as: UInt8.self)
    DispatchQueue.concurrentPerform(iterations: 200) { _ in
      let token = frulerFrameAcquire(id)!
      XCTAssertEqual(frulerFrameData(token)!.load(as: UInt8.self), 91)
      frulerFrameRelease(token)
    }
    owner!.unpublish()
    owner = nil
    XCTAssertNil(observed)
    XCTAssertNil(frulerFrameAcquire(id))
  }

  private func qrCanvas(scale: Int = 1, duplicate: Bool = false, leftValue: String = "fruler-left") throws -> CGImage {
    let width = 480 * scale, height = 480 * scale
    let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height,
      bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.interpolationQuality = .none
    for (value, left, top) in [(leftValue, 30, 30), ("fruler-right", 270, 30),
                               (duplicate ? leftValue : "fruler-bottom", 30, 270)] {
      let filter = try XCTUnwrap(CIFilter(name: "CIQRCodeGenerator"))
      filter.setValue(Data(value.utf8), forKey: "inputMessage")
      filter.setValue("M", forKey: "inputCorrectionLevel")
      let output = try XCTUnwrap(filter.outputImage)
      let code = try XCTUnwrap(CIContext().createCGImage(output, from: output.extent))
      context.draw(code, in: CGRect(x: left * scale, y: height - (top + 180) * scale,
        width: 180 * scale, height: 180 * scale))
    }
    return try XCTUnwrap(context.makeImage())
  }

  private func qrBounds(_ left: Int64, _ top: Int64, _ right: Int64, _ bottom: Int64) -> PixelBounds {
    PixelBounds(left: left, top: top, right: right, bottom: bottom)
  }

  func testQrRecognitionCropsBeforeDetectionAndKeepsDisplayPixelOrientation() throws {
    for scale: Int64 in [1, 2] {
      let image = try qrCanvas(scale: Int(scale))
      func scan(_ left: Int64, _ top: Int64, _ right: Int64, _ bottom: Int64) throws -> [String] {
        try QrCodeRecognizer.recognize(image: image,
          rect: qrBounds(left * scale, top * scale, right * scale, bottom * scale))
      }
      XCTAssertEqual(try scan(0, 0, 240, 240), ["fruler-left"])
      XCTAssertEqual(try scan(240, 0, 480, 240), ["fruler-right"])
      XCTAssertEqual(try scan(0, 240, 240, 480), ["fruler-bottom"])
      XCTAssertEqual(try scan(0, 0, 480, 480), ["fruler-left", "fruler-right", "fruler-bottom"])
      XCTAssertEqual(try scan(240, 240, 480, 480), [])
      // 小于二维码的选区也不能向外扩张找到完整码。
      XCTAssertEqual(try scan(40, 40, 80, 80), [])
    }
  }

  func testQrRecognitionDeduplicatesPayloadsWithoutRemovingWhitespace() throws {
    let image = try qrCanvas(duplicate: true)
    XCTAssertEqual(try QrCodeRecognizer.recognize(image: image, rect: qrBounds(0, 0, 480, 480)),
      ["fruler-left", "fruler-right"])
    let whitespace = try qrCanvas(leftValue: "  fruler\n")
    XCTAssertEqual(try QrCodeRecognizer.recognize(image: whitespace, rect: qrBounds(0, 0, 240, 240)),
      ["  fruler\n"])
  }

  func testQrRecognitionRejectsInvalidAndOutOfBoundsRegions() throws {
    let image = try qrCanvas()
    for bounds in [qrBounds(-1, 0, 240, 240), qrBounds(0, -1, 240, 240),
                   qrBounds(0, 0, 481, 240), qrBounds(0, 0, 240, 481),
                   qrBounds(0, 0, 0, 240), qrBounds(0, 0, 240, 0),
                   qrBounds(240, 0, 0, 240), qrBounds(0, 240, 240, 0),
                   qrBounds(Int64.min, 0, Int64.max, 240)] {
      XCTAssertThrowsError(try QrCodeRecognizer.recognize(image: image, rect: bounds)) { error in
        XCTAssertEqual((error as? PigeonError)?.code, "invalid_qr_region")
      }
    }
  }

}
