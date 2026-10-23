import Cocoa
import FlutterMacOS
import XCTest
@testable import fruler

class RunnerTests: XCTestCase {
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

}
