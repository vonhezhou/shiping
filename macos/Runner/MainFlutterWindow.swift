import Cocoa
import FlutterMacOS
import ScreenCaptureKit
import Carbon.HIToolbox

class MainFlutterWindow: NSWindow {
  private var desktopBridge: FrulerDesktopBridge?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    title = "fruler"
    setContentSize(NSSize(width: 1100, height: 760))
    minSize = NSSize(width: 920, height: 680)
    center()
    isReleasedWhenClosed = false

    RegisterGeneratedPlugins(registry: flutterViewController)
    desktopBridge = FrulerDesktopBridge(window: self, messenger: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }
}

/// System integration only. Pixel sampling and measurement rules live in Dart.
private final class FrulerDesktopBridge: NSObject, FlutterStreamHandler {
  private weak var mainWindow: NSWindow?
  private let methods: FlutterMethodChannel
  private let events: FlutterEventChannel
  private var sink: FlutterEventSink?
  private var statusItem: NSStatusItem?
  private var hotkeys: [EventHotKeyRef] = []
  private var hotkeyHandler: EventHandlerRef?
  private var localKeyMonitor: Any?
  private var observers: [NSObjectProtocol] = []
  private var overlays: [UInt32: CapturePanel] = [:]
  private var session: Int?
  private var nextSession = 0
  private var preparing = false
  private var restoreMainWindow = false
  private var previousApplication: NSRunningApplication?
  private var captureTask: Task<Void, Never>?
  private var hasShortcuts = false
  private let stateKey = "fruler.state.v1"

  init(window: NSWindow, messenger: FlutterBinaryMessenger) {
    mainWindow = window
    methods = FlutterMethodChannel(name: "dev.fruler/desktop", binaryMessenger: messenger)
    events = FlutterEventChannel(name: "dev.fruler/events", binaryMessenger: messenger)
    super.init()
    methods.setMethodCallHandler { [weak self] call, result in self?.handle(call, result: result) }
    events.setStreamHandler(self)
    setupMenu()
    setupHotkeys()
    localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
      if modifiers == [.command, .shift] {
        if event.keyCode == UInt16(kVK_ANSI_C) { self?.emitActivation("picker"); return nil }
        if event.keyCode == UInt16(kVK_ANSI_R) { self?.emitActivation("rectangle"); return nil }
      }
      return event
    }
    observers.append(NotificationCenter.default.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
    ) { [weak self] _ in self?.cancelSession() })
    observers.append(NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main
    ) { [weak self] _ in self?.cancelSession() })
    observers.append(NotificationCenter.default.addObserver(
      forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
    ) { [weak self] _ in
      self?.sink?(["type": "permissionChanged", "permission": CGPreflightScreenCaptureAccess()])
    })
  }

  deinit {
    captureTask?.cancel()
    hotkeys.forEach { UnregisterEventHotKey($0) }
    if let handler = hotkeyHandler { RemoveEventHandler(handler) }
    if let monitor = localKeyMonitor { NSEvent.removeMonitor(monitor) }
    for observer in observers {
      NotificationCenter.default.removeObserver(observer)
      NSWorkspace.shared.notificationCenter.removeObserver(observer)
    }
    if let item = statusItem { NSStatusBar.system.removeStatusItem(item) }
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    cancelSession()
    sink = nil
    return nil
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "initialize":
      result(["permission": CGPreflightScreenCaptureAccess(), "shortcuts": hasShortcuts, "platform": "macos"])
    case "requestPermission":
      result(CGRequestScreenCaptureAccess())
    case "openPrivacySettings":
      if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
        NSWorkspace.shared.open(url)
      }
      result(nil)
    case "loadState":
      result(UserDefaults.standard.string(forKey: stateKey))
    case "saveState":
      if let json = args["json"] as? String {
        UserDefaults.standard.set(json, forKey: stateKey)
      }
      result(nil)
    case "begin":
      guard let tool = args["tool"] as? String,
            ["picker", "rectangle", "horizontal", "vertical", "cross"].contains(tool) else {
        result(FlutterError(code: "invalid_tool", message: "未知工具", details: nil))
        return
      }
      begin(tool: tool, result: result)
    case "updateOverlay":
      if let id = args["sessionId"] as? Int, id == session,
         let display = args["displayId"] as? UInt32 {
        for (key, panel) in overlays { panel.overlay.isPointerActive = key == display }
        overlays[display]?.overlay.update(args)
      }
      result(nil)
    case "finish":
      if let id = args["sessionId"] as? Int, id == session { closeSession() }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func begin(tool: String, result: @escaping FlutterResult) {
    guard !preparing && session == nil else {
      result(FlutterError(code: "capture_busy", message: "已有工具正在使用", details: nil))
      return
    }
    guard CGPreflightScreenCaptureAccess() else {
      result(FlutterError(code: "screen_permission", message: "请先允许 fruler 录制屏幕", details: nil))
      return
    }
    guard sink != nil else {
      result(FlutterError(code: "no_listener", message: "工具尚未就绪", details: nil))
      return
    }
    preparing = true
    nextSession += 1
    let id = nextSession
    session = id
    restoreMainWindow = mainWindow?.isVisible == true && mainWindow?.isMiniaturized == false
    previousApplication = NSWorkspace.shared.frontmostApplication
    mainWindow?.orderOut(nil)
    captureTask = Task { @MainActor [weak self] in
      guard let self = self else { return }
      do {
        // Allow the compositor to remove the dashboard before taking snapshots.
        try await Task.sleep(nanoseconds: 160_000_000)
        try Task.checkCancellation()
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let ownApps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        var captures: [DisplaySnapshot] = []
        for screen in NSScreen.screens {
          try Task.checkCancellation()
          guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                let display = content.displays.first(where: { $0.displayID == number.uint32Value }) else { continue }
          let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
          let config = SCStreamConfiguration()
          // A scaled display's backing pixels can differ from its native panel resolution.
          config.width = Int((screen.frame.width * screen.backingScaleFactor).rounded())
          config.height = Int((screen.frame.height * screen.backingScaleFactor).rounded())
          config.showsCursor = false
          config.pixelFormat = kCVPixelFormatType_32BGRA
          config.colorSpaceName = CGColorSpace.sRGB
          let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
          captures.append(try DisplaySnapshot(screen: screen, displayID: display.displayID, image: image))
        }
        try Task.checkCancellation()
        guard self.session == id, !captures.isEmpty else { throw CaptureFailure.unavailable }
        for snapshot in captures {
          let panel = CapturePanel(snapshot: snapshot, tool: tool)
          panel.overlay.onPointer = { [weak self] x, y, phase in
            guard let self = self, self.session == id else { return }
            self.sink?(["type": "pointer", "sessionId": id,
              "displayId": snapshot.displayID, "x": x, "y": y, "phase": phase])
          }
          panel.overlay.onCancel = { [weak self] in self?.cancelSession() }
          self.overlays[snapshot.displayID] = panel
        }
        self.preparing = false
        NSApp.activate(ignoringOtherApps: true)
        for panel in self.overlays.values { panel.orderFrontRegardless() }
        let pointer = NSEvent.mouseLocation
        let active = self.overlays.values.first { $0.frame.contains(pointer) } ?? self.overlays.values.first
        active?.makeKeyAndOrderFront(nil)
        result(["sessionId": id, "frames": captures.map { $0.channelData }])
        // Input may precede the MethodChannel result; the Dart controller queues it.
        DispatchQueue.main.async { [weak self] in
          guard self?.session == id else { return }
          active?.overlay.sendCurrentPointer()
        }
      } catch {
        let cancelled = error is CancellationError || self.session != id
        if self.session == id { self.closeSession() }
        result(FlutterError(code: cancelled ? "capture_cancelled" : "capture_failed",
          message: cancelled ? "已取消截图" : "屏幕截图失败：\(error.localizedDescription)", details: nil))
      }
    }
  }

  private func cancelSession() {
    guard let id = session else { return }
    captureTask?.cancel()
    closeSession()
    sink?(["type": "cancelled", "sessionId": id])
  }

  private func closeSession() {
    session = nil
    preparing = false
    for panel in overlays.values { panel.orderOut(nil); panel.close() }
    overlays.removeAll()
    if restoreMainWindow {
      NSApp.activate(ignoringOtherApps: true)
      mainWindow?.makeKeyAndOrderFront(nil)
    } else if let previous = previousApplication,
              previous.processIdentifier != ProcessInfo.processInfo.processIdentifier {
      previous.activate(options: [])
    }
    restoreMainWindow = false
    previousApplication = nil
  }

  private func setupMenu() {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    item.button?.image = NSImage(systemSymbolName: "ruler", accessibilityDescription: "fruler")
    let menu = NSMenu()
    menu.addItem(withTitle: "fruler · 屏幕上的像素工具", action: nil, keyEquivalent: "")
    menu.addItem(.separator())
    for (title, tool, key) in [("取色器", "picker", "C"), ("矩形测量", "rectangle", "R"),
      ("水平间距", "horizontal", ""), ("垂直间距", "vertical", ""), ("交叉测距", "cross", "")] {
      let entry = NSMenuItem(title: title, action: #selector(activateTool(_:)), keyEquivalent: key)
      entry.target = self
      entry.representedObject = tool
      if !key.isEmpty { entry.keyEquivalentModifierMask = [.command, .shift] }
      menu.addItem(entry)
    }
    menu.addItem(.separator())
    let show = menu.addItem(withTitle: "打开 fruler", action: #selector(showMainWindow), keyEquivalent: "")
    show.target = self
    let quit = menu.addItem(withTitle: "退出 fruler", action: #selector(quitApp), keyEquivalent: "q")
    quit.target = self
    item.menu = menu
    statusItem = item
  }

  @objc private func activateTool(_ sender: NSMenuItem) {
    guard let tool = sender.representedObject as? String else { return }
    emitActivation(tool)
  }
  private func emitActivation(_ tool: String) {
    guard session == nil, !preparing else { NSSound.beep(); return }
    guard CGPreflightScreenCaptureAccess() else {
      showMainWindow()
      sink?(["type": "activate", "tool": tool])
      return
    }
    sink?(["type": "activate", "tool": tool])
  }
  @objc private func showMainWindow() {
    if session != nil { cancelSession() }
    NSApp.activate(ignoringOtherApps: true)
    mainWindow?.deminiaturize(nil)
    mainWindow?.makeKeyAndOrderFront(nil)
  }
  @objc private func quitApp() { NSApp.terminate(nil) }

  private func setupHotkeys() {
    var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    let context = Unmanaged.passUnretained(self).toOpaque()
    let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
      guard let event = event, let context = context else { return OSStatus(eventNotHandledErr) }
      let bridge = Unmanaged<FrulerDesktopBridge>.fromOpaque(context).takeUnretainedValue()
      var key = EventHotKeyID()
      let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &key)
      guard status == noErr else { return status }
      bridge.emitActivation(key.id == 1 ? "picker" : "rectangle")
      return noErr
    }, 1, &spec, context, &hotkeyHandler)
    guard status == noErr else { return }
    let signature: OSType = 0x46524C52 // FRLR
    for (id, keyCode) in [(UInt32(1), UInt32(kVK_ANSI_C)), (UInt32(2), UInt32(kVK_ANSI_R))] {
      var ref: EventHotKeyRef?
      let error = RegisterEventHotKey(keyCode, UInt32(cmdKey | shiftKey),
        EventHotKeyID(signature: signature, id: id), GetApplicationEventTarget(), 0, &ref)
      if error == noErr, let ref = ref { hotkeys.append(ref) }
    }
    hasShortcuts = hotkeys.count == 2
  }
}

private enum CaptureFailure: LocalizedError {
  case unavailable
  var errorDescription: String? { "没有可用的显示器或像素缓冲区。" }
}

private struct DisplaySnapshot {
  let displayID: UInt32
  let frame: NSRect
  let name: String
  let width: Int
  let height: Int
  let rgba: Data
  let image: CGImage

  init(screen: NSScreen, displayID: UInt32, image: CGImage) throws {
    self.displayID = displayID
    frame = screen.frame
    name = screen.localizedName
    let pixelWidth = image.width
    let pixelHeight = image.height
    width = pixelWidth
    height = pixelHeight
    guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { throw CaptureFailure.unavailable }
    var bytes = Data(count: pixelWidth * pixelHeight * 4)
    let normalized: CGImage? = bytes.withUnsafeMutableBytes { buffer in
      guard let context = CGContext(data: buffer.baseAddress, width: pixelWidth, height: pixelHeight,
        bitsPerComponent: 8, bytesPerRow: pixelWidth * 4, space: space,
        bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
      context.interpolationQuality = .none
      context.draw(image, in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
      return context.makeImage()
    }
    guard let normalized = normalized else { throw CaptureFailure.unavailable }
    self.image = normalized
    rgba = bytes
  }

  var channelData: [String: Any] {
    ["id": displayID, "name": name, "width": width, "height": height,
      "logicalWidth": frame.width, "logicalHeight": frame.height,
      "rgba": FlutterStandardTypedData(bytes: rgba)]
  }
}

private final class CapturePanel: NSPanel {
  let overlay: CaptureOverlayView
  init(snapshot: DisplaySnapshot, tool: String) {
    overlay = CaptureOverlayView(snapshot: snapshot, tool: tool)
    super.init(contentRect: snapshot.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    level = .screenSaver
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    isOpaque = true
    backgroundColor = .black
    hasShadow = false
    hidesOnDeactivate = false
    isReleasedWhenClosed = false
    acceptsMouseMovedEvents = true
    contentView = overlay
    setFrame(snapshot.frame, display: false)
    makeFirstResponder(overlay)
  }
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
}

private final class CaptureOverlayView: NSView {
  let snapshot: DisplaySnapshot
  let tool: String
  var onPointer: ((Double, Double, String) -> Void)?
  var onCancel: (() -> Void)?
  var isPointerActive = false { didSet { if oldValue != isPointerActive { needsDisplay = true } } }
  private var pointer = NSPoint.zero
  private var label = ""
  private var selectedColor = NSColor.white
  private var measuredRect: NSRect?
  private var tracking: NSTrackingArea?
  private let accent = NSColor(srgbRed: 215 / 255, green: 250 / 255, blue: 107 / 255, alpha: 1)

  init(snapshot: DisplaySnapshot, tool: String) {
    self.snapshot = snapshot
    self.tool = tool
    super.init(frame: NSRect(origin: .zero, size: snapshot.frame.size))
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
  override var isFlipped: Bool { true }
  override var acceptsFirstResponder: Bool { true }

  override func updateTrackingAreas() {
    if let area = tracking { removeTrackingArea(area) }
    let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
    addTrackingArea(area)
    tracking = area
    super.updateTrackingAreas()
  }
  override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
  override func mouseEntered(with event: NSEvent) { window?.makeKey(); send(event, phase: "move") }
  override func mouseExited(with event: NSEvent) { isPointerActive = false }
  override func mouseMoved(with event: NSEvent) { send(event, phase: "move") }
  override func mouseDown(with event: NSEvent) { window?.makeKey(); send(event, phase: "down") }
  override func mouseDragged(with event: NSEvent) { send(event, phase: "drag") }
  override func mouseUp(with event: NSEvent) { send(event, phase: "up") }
  override func rightMouseDown(with event: NSEvent) { onCancel?() }
  override func keyDown(with event: NSEvent) {
    if event.keyCode == UInt16(kVK_Escape) { onCancel?() }
  }

  private func send(_ event: NSEvent, phase: String) {
    pointer = convert(event.locationInWindow, from: nil)
    isPointerActive = true
    needsDisplay = true
    onPointer?(pointer.x, pointer.y, phase)
  }
  func sendCurrentPointer() {
    guard let window = window else { return }
    pointer = convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
    isPointerActive = bounds.contains(pointer)
    if isPointerActive { onPointer?(pointer.x, pointer.y, "move") }
    needsDisplay = true
  }

  func update(_ data: [String: Any]) {
    if let x = data["x"] as? Double, let y = data["y"] as? Double { pointer = NSPoint(x: x, y: y) }
    label = data["label"] as? String ?? ""
    if let rgb = data["color"] as? [Int], rgb.count == 3 {
      selectedColor = NSColor(srgbRed: Double(rgb[0]) / 255, green: Double(rgb[1]) / 255,
        blue: Double(rgb[2]) / 255, alpha: 1)
    }
    if let rect = data["rect"] as? [String: Int], let left = rect["left"], let top = rect["top"],
       let right = rect["right"], let bottom = rect["bottom"] {
      let sx = bounds.width / Double(snapshot.width)
      let sy = bounds.height / Double(snapshot.height)
      measuredRect = NSRect(x: Double(left) * sx, y: Double(top) * sy,
        width: Double(right - left) * sx, height: Double(bottom - top) * sy)
    } else { measuredRect = nil }
    needsDisplay = true
  }

  override func draw(_ dirtyRect: NSRect) {
    NSImage(cgImage: snapshot.image, size: bounds.size).draw(in: bounds, from: .zero,
      operation: .copy, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.none])
    if tool != "picker" {
      NSColor.black.withAlphaComponent(0.08).setFill()
      bounds.fill()
    }
    drawInstructions()
    guard isPointerActive else { return }
    if let rect = measuredRect { drawMeasurement(rect) }
    drawCrosshair()
    drawLoupe()
  }

  private func drawMeasurement(_ rect: NSRect) {
    accent.setStroke()
    let path = NSBezierPath()
    path.lineWidth = 1.5
    if tool == "rectangle" {
      accent.withAlphaComponent(0.1).setFill()
      rect.fill()
      path.appendRect(rect)
    } else {
      if tool != "vertical" {
        path.move(to: NSPoint(x: rect.minX, y: pointer.y))
        path.line(to: NSPoint(x: rect.maxX, y: pointer.y))
        for x in [rect.minX, rect.maxX] {
          path.move(to: NSPoint(x: x, y: pointer.y - 8)); path.line(to: NSPoint(x: x, y: pointer.y + 8))
        }
      }
      if tool != "horizontal" {
        path.move(to: NSPoint(x: pointer.x, y: rect.minY))
        path.line(to: NSPoint(x: pointer.x, y: rect.maxY))
        for y in [rect.minY, rect.maxY] {
          path.move(to: NSPoint(x: pointer.x - 8, y: y)); path.line(to: NSPoint(x: pointer.x + 8, y: y))
        }
      }
    }
    path.stroke()
  }

  private func drawCrosshair() {
    let path = NSBezierPath()
    path.lineWidth = 0.5
    NSColor.white.withAlphaComponent(0.65).setStroke()
    path.move(to: NSPoint(x: 0, y: pointer.y)); path.line(to: NSPoint(x: bounds.width, y: pointer.y))
    path.move(to: NSPoint(x: pointer.x, y: 0)); path.line(to: NSPoint(x: pointer.x, y: bounds.height))
    path.stroke()
  }

  private func drawLoupe() {
    let width: CGFloat = 300
    let height: CGFloat = tool == "picker" ? 170 : 64
    var x = pointer.x + 26
    var y = pointer.y + 26
    if x + width > bounds.width - 12 { x = pointer.x - width - 26 }
    if y + height > bounds.height - 12 { y = pointer.y - height - 26 }
    let box = NSRect(x: max(12, x), y: max(12, y), width: width, height: height)
    NSColor(srgbRed: 0.065, green: 0.075, blue: 0.085, alpha: 0.97).setFill()
    NSBezierPath(roundedRect: box, xRadius: 12, yRadius: 12).fill()
    if tool == "picker" {
      let px = Int((pointer.x / bounds.width * Double(snapshot.width)).rounded(.down)).clamped(0, snapshot.width - 1)
      let py = Int((pointer.y / bounds.height * Double(snapshot.height)).rounded(.down)).clamped(0, snapshot.height - 1)
      let minX = max(0, px - 5), minY = max(0, py - 5)
      let maxX = min(snapshot.width, px + 6), maxY = min(snapshot.height, py + 6)
      if let crop = snapshot.image.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)) {
        let cell: CGFloat = 9
        let area = NSRect(x: box.minX + 14, y: box.minY + 12, width: 99, height: 99)
        NSColor.black.setFill(); area.fill()
        // At display edges pad the missing pixels instead of stretching the crop.
        let imageRect = NSRect(x: area.minX + CGFloat(minX - px + 5) * cell,
          y: area.minY + CGFloat(minY - py + 5) * cell,
          width: CGFloat(maxX - minX) * cell, height: CGFloat(maxY - minY) * cell)
        NSImage(cgImage: crop, size: imageRect.size).draw(in: imageRect, from: .zero,
          operation: .copy, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.none])
        accent.setStroke()
        let center = NSBezierPath(rect: NSRect(x: area.minX + 45, y: area.minY + 45, width: 9, height: 9))
        center.lineWidth = 2; center.stroke()
      }
      selectedColor.setFill()
      NSBezierPath(roundedRect: NSRect(x: box.minX + 130, y: box.minY + 12, width: 154, height: 99), xRadius: 7, yRadius: 7).fill()
    }
    let labelY = tool == "picker" ? box.minY + 122 : box.minY + 12
    (label as NSString).draw(at: NSPoint(x: box.minX + 14, y: labelY), withAttributes: [
      .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.white])
    let hint = tool == "rectangle" ? "松开复制尺寸  ·  Esc 取消" : "点击复制  ·  Esc 取消"
    (hint as NSString).draw(at: NSPoint(x: box.minX + 14, y: labelY + 21), withAttributes: [
      .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.gray])
  }

  private func drawInstructions() {
    let title = ["picker": "取色器", "rectangle": "矩形测量", "horizontal": "水平间距",
      "vertical": "垂直间距", "cross": "交叉测距"][tool] ?? "fruler"
    let text = "fruler  /  \(title)     屏幕已冻结 · Esc 或右键退出"
    let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.white]
    let size = (text as NSString).size(withAttributes: attrs)
    let box = NSRect(x: (bounds.width - size.width) / 2 - 18, y: 24, width: size.width + 36, height: 38)
    NSColor.black.withAlphaComponent(0.85).setFill()
    NSBezierPath(roundedRect: box, xRadius: 10, yRadius: 10).fill()
    (text as NSString).draw(at: NSPoint(x: box.minX + 18, y: box.minY + 11), withAttributes: attrs)
  }
}

private extension Int {
  func clamped(_ minValue: Int, _ maxValue: Int) -> Int { Swift.min(maxValue, Swift.max(minValue, self)) }
}
