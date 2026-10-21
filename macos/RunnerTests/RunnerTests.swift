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

}
