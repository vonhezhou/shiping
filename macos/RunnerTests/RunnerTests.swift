import Cocoa
import FlutterMacOS
import XCTest
@testable import fruler

class RunnerTests: XCTestCase {
  func testNativeCaptureCommandContractIncludesScreenshot() {
    XCTAssertNotNil(CaptureTool(rawValue: "screenshot"))
    XCTAssertEqual(Set(CaptureTool.allCases.map(\.rawValue)),
      Set(["picker", "rectangle", "horizontal", "vertical", "cross", "screenshot"]))
  }

  func testNativeCaptureCommandContractRejectsUnknownCommands() {
    for value in ["", "unknown", "Screenshot", "invalid-test-tool"] {
      XCTAssertNil(CaptureTool(rawValue: value))
    }
  }
}
