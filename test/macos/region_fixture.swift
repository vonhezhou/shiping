import Cocoa
import CoreImage
// 夹具独立于被测进程：即使测试应用异常退出，也恢复测试前的系统剪贴板。
let savedPasteboard = (NSPasteboard.general.pasteboardItems ?? []).map { item in
  Dictionary(uniqueKeysWithValues: item.types.compactMap { type in
    item.data(forType: type).map { (type, $0) }
  })
}
signal(SIGTERM, SIG_IGN)
let termination = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
termination.setEventHandler {
  NSPasteboard.general.clearContents()
  let items = savedPasteboard.map { entry in
    let item = NSPasteboardItem()
    for (type, data) in entry { item.setData(data, forType: type) }
    return item
  }
  NSPasteboard.general.writeObjects(items)
  exit(0)
}
termination.resume()
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let screen = NSScreen.screens[0].frame
let window = NSWindow(contentRect:NSRect(x:screen.minX+100,y:screen.maxY-520,width:360,height:220),
  styleMask:[.titled,.closable],backing:.buffered,defer:false)
window.title="fruler-region-fixture"
window.isReleasedWhenClosed=false
let button=NSButton(title:"Region fixture control",target:nil,action:nil)
button.frame=NSRect(x:40,y:60,width:180,height:32)
window.contentView?.addSubview(button)
let observer=DistributedNotificationCenter.default().addObserver(
  forName:Notification.Name("dev.fruler.integration.raiseRegionFixture"),object:nil,queue:.main) { _ in
    app.activate(ignoringOtherApps:true)
    window.makeKeyAndOrderFront(nil)
}
#if FRULER_INTEGRATION_TEST
// 在测试夹具中投递真实系统鼠标事件，AppKit 自己处理颜色拖放和样本选择。
let colorObserver = DistributedNotificationCenter.default().addObserver(
  forName: Notification.Name("dev.fruler.integration.colorSampleInput"), object: nil, queue: .main) { note in
  guard let payload = note.object as? String, let data = payload.data(using: .utf8),
    let args = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
    let start = args["start"] as? [Double], let target = args["target"] as? [Double],
    let drag = args["drag"] as? Bool, let token = args["token"] as? String else { return }
  let reply = Notification.Name("dev.fruler.integration.colorSampleReply.\(token)")
  guard CGPreflightPostEventAccess() else {
    DistributedNotificationCenter.default().postNotificationName(reply, object: "Fixture needs Accessibility permission for real mouse events", userInfo: nil, deliverImmediately: true)
    return
  }
  DispatchQueue.global().async {
    let inputSource = CGEventSource(stateID: .hidSystemState)
    var lastPoint = CGPoint(x: start[0], y: start[1])
    func post(_ type: CGEventType, _ x: Double, _ y: Double) {
      let event = CGEvent(mouseEventSource: inputSource, mouseType: type, mouseCursorPosition: CGPoint(x:x,y:y), mouseButton: .left)!
      event.setIntegerValueField(.mouseEventClickState, value: 1)
      event.setIntegerValueField(.mouseEventDeltaX, value: Int64((x - lastPoint.x).rounded()))
      event.setIntegerValueField(.mouseEventDeltaY, value: Int64((y - lastPoint.y).rounded()))
      event.setDoubleValueField(.mouseEventPressure, value: type == .leftMouseUp ? 0 : 1)
      lastPoint = CGPoint(x: x, y: y)
      event.post(tap: .cghidEventTap)
    }
    post(.mouseMoved, start[0], start[1])
    Thread.sleep(forTimeInterval: 0.1)
    post(.leftMouseDown, start[0], start[1])
    Thread.sleep(forTimeInterval: 0.2)
    if drag {
      for i in 1...12 {
        post(.leftMouseDragged, start[0] + (target[0] - start[0]) * Double(i) / 12,
          start[1] + (target[1] - start[1]) * Double(i) / 12)
        Thread.sleep(forTimeInterval: 0.04)
      }
    }
    post(.leftMouseUp, target[0], target[1])
    // 等待系统颜色放置动画结束，再允许测试改变当前颜色。
    Thread.sleep(forTimeInterval: drag ? 1.0 : 0.3)
    DistributedNotificationCenter.default().postNotificationName(reply, object: "ok", userInfo: nil, deliverImmediately: true)
  }
}
#endif
// 两张真实可见二维码供 ScreenCaptureKit 采集，生产路径不会注入夹具图片。
final class QRFixtureView: NSView {
  override var isFlipped: Bool { true }
  let context = CIContext()
  override func draw(_ dirtyRect: NSRect) {
    NSColor.white.setFill()
    bounds.fill()
    NSGraphicsContext.current?.imageInterpolation = .none
    for (payload, x) in [("fruler:selected-left", 40.0), ("fruler:outside-right", 380.0)] {
      let filter = CIFilter(name: "CIQRCodeGenerator")!
      filter.setValue(Data(payload.utf8), forKey: "inputMessage")
      filter.setValue("M", forKey: "inputCorrectionLevel")
      let output = filter.outputImage!
      let scale = floor(180 / output.extent.width)
      let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
      let image = context.createCGImage(scaled, from: scaled.extent)!
      NSImage(cgImage: image, size: .zero).draw(
        in: NSRect(x: x, y: 60, width: scaled.extent.width, height: scaled.extent.height),
        from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
    }
  }
}
let qrWindow = NSWindow(contentRect: NSRect(x: screen.minX + 80, y: screen.maxY - 500, width: 640, height: 360),
  styleMask: [.titled], backing: .buffered, defer: false)
qrWindow.title = "fruler-qr-fixture"
qrWindow.isReleasedWhenClosed = false
qrWindow.contentView = QRFixtureView(frame: NSRect(x: 0, y: 0, width: 640, height: 360))
let qrObserver = DistributedNotificationCenter.default().addObserver(
  forName: Notification.Name("dev.fruler.integration.qrFixture"), object: nil, queue: .main) { note in
  if note.object as? String == "hide" { qrWindow.orderOut(nil) }
  else {
    app.activate(ignoringOtherApps: true)
    qrWindow.makeKeyAndOrderFront(nil)
  }
}
window.orderFrontRegardless()
print("ready");fflush(stdout)
app.run()
