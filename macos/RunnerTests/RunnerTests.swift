import Cocoa
import FlutterMacOS
import XCTest
@testable import fruler

class RunnerTests: XCTestCase {
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
