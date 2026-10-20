import Cocoa
import FlutterMacOS
import ScreenCaptureKit
import Carbon.HIToolbox
import UniformTypeIdentifiers

class MainFlutterWindow: NSWindow {
  private var desktopBridge: FrulerDesktopBridge?


  func requestQuitConfirmation() -> Bool { desktopBridge?.requestQuitConfirmation() ?? false }

  override func awakeFromNib() {
    guard FrulerInstance.acquire() else { NSApp.terminate(nil); return }
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    title = "fruler"
    setContentSize(NSSize(width: 1100, height: 760))
    minSize = NSSize(width: 920, height: 680)
    center()
    isReleasedWhenClosed = false

    RegisterGeneratedPlugins(registry: flutterViewController)
    desktopBridge = FrulerDesktopBridge(window: self, messenger: flutterViewController.engine.binaryMessenger)
    #if FRULER_INTEGRATION_TEST
    desktopBridge?.installIntegrationDriver(messenger: flutterViewController.engine.binaryMessenger)
    #endif

    super.awakeFromNib()
  }
}

enum CaptureTool: String, CaseIterable {
  case picker, rectangle, horizontal, vertical, cross, screenshot
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
  private var screenshotHost: CapturePanel?
  private var flutterController: FlutterViewController?
  private var lastExternalApplication: NSRunningApplication?
  private var previousApplication: NSRunningApplication?
  private var captureTask: Task<Void, Never>?
  private var hasShortcuts = false
  private var shortcuts = NativeShortcutBindings.defaults
  private var shortcutRecording = false
  private var pausedMenuKeys: [(NSMenuItem, String)] = []
  private var toolMenuItems: [String: NSMenuItem] = [:]
  private let stateKey = "fruler.state.v1"

  init(window: NSWindow, messenger: FlutterBinaryMessenger) {
    mainWindow = window
    flutterController = window.contentViewController as? FlutterViewController
    methods = FlutterMethodChannel(name: "dev.fruler/desktop", binaryMessenger: messenger)
    events = FlutterEventChannel(name: "dev.fruler/events", binaryMessenger: messenger)
    super.init()
    methods.setMethodCallHandler { [weak self] call, result in self?.handle(call, result: result) }
    events.setStreamHandler(self)
    setupMenu()
    setupHotkeys()
    localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self = self else { return event }
      if self.shortcutRecording {
        if let key = NativeShortcut.codes.first(where: { $0.value == UInt32(event.keyCode) })?.key {
          let flags = event.modifierFlags
          self.sink?(["type": "shortcutRecorded", "chord": ["key": key,
            "meta": flags.contains(.command), "control": flags.contains(.control),
            "alt": flags.contains(.option), "shift": flags.contains(.shift)]])
        }
        return event
      }
      if self.session != nil, self.screenshotHost == nil, Int(event.keyCode) == kVK_ANSI_Z, event.modifierFlags.contains(.command) {
        self.overlays.values.first(where: { $0.isKeyWindow })?.overlay.onEvent?([
          "type":event.modifierFlags.contains(.shift) ? "redoPins":"undoPins"])
        return nil
      }
      guard self.hasShortcuts else { return event }
      if self.shortcuts.picker.matches(event) { self.emitActivation("picker"); return nil }
      if self.shortcuts.ruler.matches(event) { self.emitActivation("rectangle"); return nil }
      if self.shortcuts.screenshot.matches(event) { self.emitActivation("screenshot"); return nil }
      return event
    }
    observers.append(NotificationCenter.default.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
    ) { [weak self] _ in self?.cancelSession() })
    observers.append(NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main
    ) { [weak self] _ in self?.cancelSession() })
    observers.append(NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification, object:nil, queue:.main
    ) { [weak self] note in
      if let app=note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
        app.processIdentifier != ProcessInfo.processInfo.processIdentifier {self?.lastExternalApplication=app}
    })
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

  func requestQuitConfirmation() -> Bool {
    if session != nil {cancelSession()}
    return false
  }

  #if FRULER_INTEGRATION_TEST
  private var integrationDriver: FlutterMethodChannel?
  private var cancelNextSave = false
  private var clipboardBackup: [[NSPasteboard.PasteboardType: Data]]?
  private var pointerBackup: CGPoint?
  func installIntegrationDriver(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "dev.fruler/integration", binaryMessenger: messenger)
    integrationDriver = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      let args = call.arguments as? [String: Any] ?? [:]
      switch call.method {
      case "status":
        result(["panels":self.overlays.count,"active":self.session != nil,
          "permission":CGPreflightScreenCaptureAccess(),"bundleId":Bundle.main.bundleIdentifier ?? "",
          "mainVisible":self.mainWindow?.isVisible == true,"editing":self.screenshotHost != nil,
          "rulerViews":self.overlays.values.map { $0.overlay.integrationState },
          "windowNumber":self.screenshotHost?.windowNumber ?? self.overlays.values.first?.windowNumber ?? -1])
      case "clickRulerControl":
        guard let panel = self.overlays.values.first(where: { $0.isKeyWindow }) else {
          result(false);return
        }
        result(panel.overlay.integrationClickControl(args["name"] as? String ?? ""))
      case "rulerLayout":
        guard let panel = self.overlays.values.first,
          let width = args["width"] as? Double, let height = args["height"] as? Double else {
          result(FlutterError(code:"test_no_panel",message:"No native panel",details:nil));return
        }
        result(panel.overlay.integrationLayout(width: width, height: height))
      case "pointer":
        guard let id=args["displayId"] as? UInt32, let panel=self.overlays[id],
          let x=args["x"] as? Double, let y=args["y"] as? Double, let phase=args["phase"] as? String,
          let type=["down":NSEvent.EventType.leftMouseDown,"drag":.leftMouseDragged,"up":.leftMouseUp,"move":.mouseMoved][phase] else {
          result(FlutterError(code:"test_no_panel",message:"No native panel",details:nil));return
        }
        panel.layoutIfNeeded()
        let point=panel.overlay.convert(NSPoint(x:x,y:y),to:nil)
        if args["warp"] as? Bool == true {
          let screenPoint = panel.convertPoint(toScreen: point)
          CGWarpMouseCursorPosition(CGPoint(x: screenPoint.x,
            y: (NSScreen.screens.first?.frame.maxY ?? 0) - screenPoint.y))
        }
        guard let event=NSEvent.mouseEvent(with:type,location:point,modifierFlags:[],
          timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:panel.windowNumber,
          context:nil,eventNumber:1,clickCount:1,pressure:1) else {result(nil);return}
        panel.sendEvent(event);result(nil)
      case "scroll":
        guard let host=self.screenshotHost, let view=self.flutterController?.view,
          let x=args["x"] as? Double, let y=args["y"] as? Double,
          let delta=args["delta"] as? Int32,
          let cg=CGEvent(scrollWheelEvent2Source:nil,units:.line,wheelCount:1,
            wheel1:delta,wheel2:0,wheel3:0) else {
          result(FlutterError(code:"test_no_scroll_target",message:"No screenshot scroll target",details:nil));return
        }
        host.makeKeyAndOrderFront(nil)
        let point=view.convert(NSPoint(x:x,y:view.isFlipped ? y : view.bounds.height-y),to:nil)
        // CGEvent-created NSEvents have no window; encode the target window
        // point as their screen location before passing to the Cocoa responder.
        cg.location=CGPoint(x:point.x,y:(NSScreen.screens.first?.frame.maxY ?? 0)-point.y)
        cg.flags=[]
        guard let event=NSEvent(cgEvent:cg) else {
          result(FlutterError(code:"test_scroll_event",message:"Cannot create native scroll event",details:nil));return
        }
        self.flutterController?.scrollWheel(with:event)
        result(nil)
      case "key":
        guard let panel=self.overlays.values.first(where:{$0.isKeyWindow}) ?? self.overlays.values.first,
          let code=args["keyCode"] as? UInt16,
          let event=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:
            (args["command"] as? Bool == true ? NSEvent.ModifierFlags.command : []).union(
              args["shift"] as? Bool == true ? .shift : []),
            timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:panel.windowNumber,
            context:nil,characters:"",charactersIgnoringModifiers:"",isARepeat:false,keyCode:code) else {
          result(FlutterError(code:"test_no_panel",message:"No native panel",details:nil));return
        }
        panel.makeKeyAndOrderFront(nil);panel.makeFirstResponder(panel.overlay)
        panel.sendEvent(event);result(nil)
      case "insertText":
        guard let host=self.screenshotHost,
          let client=host.firstResponder as? NSTextInputClient,
          let value=args["text"] as? String else {
          result(FlutterError(code:"test_no_text_client",message:"Screenshot responder is not a text input client",details:nil));return
        }
        client.insertText(value,replacementRange:NSRange(location:NSNotFound,length:0))
        result(nil)
      case "cancelNextSave": self.cancelNextSave=true;result(nil)
      case "backupClipboard":
        self.pointerBackup = CGEvent(source: nil)?.location
        self.clipboardBackup=(NSPasteboard.general.pasteboardItems ?? []).map { item in
          Dictionary(uniqueKeysWithValues:item.types.compactMap { type in item.data(forType:type).map { (type,$0) } })
        };result(nil)
      case "clipboardText": result(NSPasteboard.general.string(forType:.string))
      case "clipboardPng": result(NSPasteboard.general.data(forType:.png).map { FlutterStandardTypedData(bytes:$0) })
      case "restoreClipboard":
        if let point = self.pointerBackup { CGWarpMouseCursorPosition(point); self.pointerBackup = nil }
        if let backup=self.clipboardBackup {
          let items=backup.map { values -> NSPasteboardItem in
            let item=NSPasteboardItem();for (type,data) in values {item.setData(data,forType:type)};return item
          }
          NSPasteboard.general.clearContents();if !items.isEmpty {NSPasteboard.general.writeObjects(items)}
          self.clipboardBackup=nil
        };result(nil)
      default:result(FlutterMethodNotImplemented)
      }
    }
  }
  #endif

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "initialize":
      result(["permission": CGPreflightScreenCaptureAccess(), "shortcuts": hasShortcuts, "platform": "macos"])
    case "configureShortcuts":
      guard let requested = NativeShortcutBindings(args), requested.isValid else {
        result(FlutterError(code: "shortcut_invalid", message: "请使用不同的字母或数字组合，并避开系统退出、编辑和截图快捷键。", details: nil))
        return
      }
      if requested == shortcuts && (hasShortcuts || shortcutRecording) { result(true); return }
      let previous = shortcuts
      let hadShortcuts = hasShortcuts
      unregisterHotkeys()
      if shortcutRecording || registerHotkeys(requested) {
        shortcuts = requested
        updateMenuShortcuts()
        result(true)
      } else {
        if hadShortcuts { _ = registerHotkeys(previous) }
        updateMenuShortcuts()
        result(FlutterError(code: "shortcut_conflict", message: "快捷键已被占用", details: ["shortcuts": hasShortcuts]))
      }
    case "setShortcutRecording":
      shortcutRecording = args["recording"] as? Bool == true
      if shortcutRecording {
        pauseApplicationMenuKeys()
        unregisterHotkeys()
        updateMenuShortcuts()
        result(true)
      } else {
        for (item, key) in pausedMenuKeys { item.keyEquivalent = key }
        pausedMenuKeys.removeAll()
        let registered = registerHotkeys(shortcuts)
        updateMenuShortcuts()
        result(registered)
      }
    case "requestPermission":
      result(CGRequestScreenCaptureAccess())
    case "showMainWindow":
      showMainWindow(); result(nil)
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
    case "replyToQuit":
      NSApp.reply(toApplicationShouldTerminate:args["allow"] as? Bool == true)
      result(nil)
    case "exportImage":
      guard let bytes = args["png"] as? FlutterStandardTypedData else {
        result(FlutterError(code:"image_export_failed",message:"图片数据无效",details:nil)); return
      }
      if args["save"] as? Bool == true {
        let captureID = session
        for panel in overlays.values { panel.orderOut(nil) }
        defer {
          if session == captureID {
            for panel in overlays.values { panel.orderFrontRegardless() }
            screenshotHost?.makeKeyAndOrderFront(nil)
          }
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "fruler-screenshot.png"
        #if FRULER_INTEGRATION_TEST
        if cancelNextSave {
          cancelNextSave = false
          DispatchQueue.main.async { panel.cancel(nil) }
        }
        #endif
        panel.allowedContentTypes = [.png]
        NSApp.activate(ignoringOtherApps:true)
        guard panel.runModal() == .OK, let url = panel.url else { result(false); return }
        do { try bytes.data.write(to:url,options:.atomic); result(true) }
        catch { result(FlutterError(code:"image_export_failed",message:error.localizedDescription,details:nil)) }
      } else {
        NSPasteboard.general.clearContents()
        if NSPasteboard.general.setData(bytes.data,forType:.png) { result(true) }
        else { result(FlutterError(code:"clipboard_failed",message:"无法写入图片剪贴板",details:nil)) }
      }
    case "openPaletteFile":
      let panel = NSOpenPanel()
      panel.allowedContentTypes = [.json]
      panel.allowsMultipleSelection = false
      panel.canChooseDirectories = false
      NSApp.activate(ignoringOtherApps: true)
      guard panel.runModal() == .OK, let url = panel.url else { result(nil); return }
      do {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 2 * 1024 * 1024 else {
          result(FlutterError(code: "import_failed", message: "JSON 文件不能超过 2 MB", details: nil)); return
        }
        let text = try String(contentsOf: url, encoding: .utf8)
        guard text.utf8.count <= 2 * 1024 * 1024 else {
          result(FlutterError(code: "import_failed", message: "JSON 文件不能超过 2 MB", details: nil)); return
        }
        result(text)
      } catch { result(FlutterError(code: "import_failed", message: error.localizedDescription, details: nil)) }
    case "saveTextFile":
      guard let filename = args["filename"] as? String, let text = args["text"] as? String else {
        result(FlutterError(code: "invalid_export", message: "导出内容无效", details: nil)); return
      }
      let panel = NSSavePanel()
      panel.nameFieldStringValue = filename
      panel.allowedContentTypes = [UTType(filenameExtension: (filename as NSString).pathExtension) ?? .plainText]
      panel.canCreateDirectories = true
      NSApp.activate(ignoringOtherApps: true)
      guard panel.runModal() == .OK, let url = panel.url else { result(false); return }
      do { try Data(text.utf8).write(to: url, options: .atomic); result(true) }
      catch { result(FlutterError(code: "export_failed", message: error.localizedDescription, details: nil)) }
    case "exportAnnotations":
      guard let id = args["sessionId"] as? Int, id == session,
            let display = args["displayId"] as? UInt32,
            let overlay = overlays[display]?.overlay,
            let pins = args["annotations"] as? [[String: Any]],
            let png = AnnotationRenderer.png(image: overlay.snapshot.image, annotations: pins) else {
        result(FlutterError(code: "invalid_export", message: "没有可导出的标注", details: nil)); return
      }
      if args["save"] as? Bool == true {
        for panel in overlays.values { panel.overlay.releaseCursor(); panel.orderOut(nil) }
        defer {
          if session == id {
            for panel in overlays.values { panel.orderFrontRegardless() }
            overlays[display]?.makeKeyAndOrderFront(nil)
          }
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "fruler-measurement.png"
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { result(false); return }
        do { try png.write(to: url, options: .atomic); result(true) }
        catch { result(FlutterError(code: "export_failed", message: error.localizedDescription, details: nil)) }
      } else {
        NSPasteboard.general.clearContents()
        if NSPasteboard.general.setData(png, forType: .png) { result(true) }
        else { result(FlutterError(code: "clipboard_failed", message: "无法写入图片剪贴板", details: nil)) }
      }
    case "begin":
      guard let tool = args["tool"] as? String,
            CaptureTool(rawValue: tool) != nil else {
        result(FlutterError(code: "invalid_tool", message: "未知工具", details: nil))
        return
      }
      begin(tool: tool, result: result)
    case "updateOverlay":
      if let id = args["sessionId"] as? Int, id == session {
        for panel in overlays.values { panel.overlay.updateOptions(args) }
        if let display = args["displayId"] as? UInt32 {
          for (key, panel) in overlays { panel.overlay.isPointerActive = key == display }
          overlays[display]?.overlay.update(args)
        }
      }
      result(nil)
    case "editScreenshot":
      guard let id = args["sessionId"] as? Int, id == session,
            let display = args["displayId"] as? UInt32, let panel = overlays[display],
            let controller = flutterController else {
        result(FlutterError(code:"capture_cancelled",message:"截图会话已结束",details:nil)); return
      }
      for overlay in overlays.values { overlay.overlay.setScreenshotEditing(true); overlay.overlay.releaseCursor() }
      mainWindow?.contentViewController = nil
      controller.backgroundColor = .clear
      panel.isOpaque = false
      controller.view.frame = panel.overlay.bounds
      controller.view.autoresizingMask = [.width,.height]
      panel.overlay.addSubview(controller.view)
      screenshotHost = panel
      panel.makeKeyAndOrderFront(nil)
      panel.makeFirstResponder(controller.view)
      result(nil)
    case "reselectScreenshot":
      if let id = args["sessionId"] as? Int, id == session {
        restoreScreenshotView()
        for panel in overlays.values { panel.overlay.setScreenshotEditing(false) }
        overlays.values.first?.makeKeyAndOrderFront(nil)
        if let panel = overlays.values.first { panel.makeFirstResponder(panel.overlay) }
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
    let frontmost = NSWorkspace.shared.frontmostApplication
    previousApplication = frontmost?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? lastExternalApplication : frontmost
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
          panel.overlay.onEvent = { [weak self] event in
            guard let self = self, self.session == id else { return }
            var data = event
            data["sessionId"] = id
            data["displayId"] = snapshot.displayID
            self.sink?(data)
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

  private func restoreScreenshotView() {
    guard screenshotHost != nil, let controller = flutterController else { return }
    controller.view.removeFromSuperview()
    controller.backgroundColor = NSColor.windowBackgroundColor
    mainWindow?.contentViewController = controller
    screenshotHost = nil
  }

  private func closeSession() {
    session = nil
    preparing = false
    restoreScreenshotView()
    for panel in overlays.values { panel.overlay.releaseCursor(); panel.orderOut(nil); panel.close() }
    overlays.removeAll()
    if let previous = previousApplication, !previous.isTerminated,
       previous.processIdentifier != ProcessInfo.processInfo.processIdentifier {
      previous.activate(options: [])
    } else { NSApp.hide(nil) }
    previousApplication = nil
  }

  private func setupMenu() {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    item.button?.image = NSImage(systemSymbolName: "ruler", accessibilityDescription: "fruler")
    let menu = NSMenu()
    menu.addItem(withTitle: "fruler · 屏幕上的像素工具", action: nil, keyEquivalent: "")
    menu.addItem(.separator())
    for (title, tool, key) in [("截图并标注", "screenshot", "X"), ("取色器", "picker", "C"), ("矩形测量", "rectangle", "R"),
      ("水平间距", "horizontal", ""), ("垂直间距", "vertical", ""), ("交叉测距", "cross", "")] {
      let entry = NSMenuItem(title: title, action: #selector(activateTool(_:)), keyEquivalent: key)
      entry.target = self
      entry.representedObject = tool
      if !key.isEmpty { entry.keyEquivalentModifierMask = [.command, .shift] }
      toolMenuItems[tool] = entry
      menu.addItem(entry)
    }
    menu.addItem(.separator())
    let show = menu.addItem(withTitle: "打开 fruler", action: #selector(showMainWindow), keyEquivalent: "")
    show.target = self
    let quit = menu.addItem(withTitle: "退出 fruler", action: #selector(quitApp), keyEquivalent: "q")
    quit.target = self
    item.menu = menu
    statusItem = item
    updateMenuShortcuts()
  }

  @objc private func activateTool(_ sender: NSMenuItem) {
    guard let tool = sender.representedObject as? String else { return }
    emitActivation(tool)
  }
  private func emitActivation(_ tool: String) {
    guard !shortcutRecording else { return }
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
      bridge.emitActivation(key.id == 1 ? "picker" : key.id == 2 ? "rectangle" : "screenshot")
      return noErr
    }, 1, &spec, context, &hotkeyHandler)
    guard status == noErr else { return }
    updateMenuShortcuts()
  }

  private func unregisterHotkeys() {
    hotkeys.forEach { UnregisterEventHotKey($0) }
    hotkeys.removeAll()
    hasShortcuts = false
  }

  @discardableResult private func registerHotkeys(_ bindings: NativeShortcutBindings) -> Bool {
    unregisterHotkeys()
    guard hotkeyHandler != nil else { return false }
    let signature: OSType = 0x46524C52
    for (id, chord) in [(UInt32(1), bindings.picker), (UInt32(2), bindings.ruler), (UInt32(3), bindings.screenshot)] {
      var ref: EventHotKeyRef?
      let error = RegisterEventHotKey(chord.keyCode, chord.carbonModifiers,
        EventHotKeyID(signature: signature, id: id), GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &ref)
      guard error == noErr, let value = ref else { unregisterHotkeys(); return false }
      hotkeys.append(value)
    }
    hasShortcuts = hotkeys.count == 3
    return hasShortcuts
  }

  private func pauseApplicationMenuKeys() {
    guard pausedMenuKeys.isEmpty else { return }
    func pause(_ menu: NSMenu?) {
      for item in menu?.items ?? [] {
        if !item.keyEquivalent.isEmpty {
          pausedMenuKeys.append((item, item.keyEquivalent))
          item.keyEquivalent = ""
        }
        pause(item.submenu)
      }
    }
    pause(NSApp.mainMenu)
  }

  private func updateMenuShortcuts() {
    for (tool, chord) in [("picker", shortcuts.picker), ("rectangle", shortcuts.ruler), ("screenshot", shortcuts.screenshot)] {
      toolMenuItems[tool]?.keyEquivalent = (shortcutRecording || !hasShortcuts) ? "" : chord.key.lowercased()
      toolMenuItems[tool]?.keyEquivalentModifierMask = chord.modifiers
    }
  }
}

private struct NativeShortcut: Equatable {
  let key: String
  let modifiers: NSEvent.ModifierFlags
  static let codes: [String: UInt32] = ["A":0,"S":1,"D":2,"F":3,"H":4,"G":5,"Z":6,"X":7,"C":8,"V":9,
    "B":11,"Q":12,"W":13,"E":14,"R":15,"Y":16,"T":17,"1":18,"2":19,"3":20,"4":21,"6":22,"5":23,
    "9":25,"7":26,"8":28,"0":29,"O":31,"U":32,"I":34,"P":35,"L":37,"J":38,"K":40,"N":45,"M":46]
  init(key: String, modifiers: NSEvent.ModifierFlags) { self.key = key; self.modifiers = modifiers }
  init?(_ data: Any?) {
    guard let data = data as? [String: Any], let key = data["key"] as? String,
          Self.codes[key] != nil else { return nil }
    var flags: NSEvent.ModifierFlags = []
    if data["meta"] as? Bool == true { flags.insert(.command) }
    if data["control"] as? Bool == true { flags.insert(.control) }
    if data["alt"] as? Bool == true { flags.insert(.option) }
    if data["shift"] as? Bool == true { flags.insert(.shift) }
    self.init(key: key, modifiers: flags)
  }
  var keyCode: UInt32 { Self.codes[key]! }
  var carbonModifiers: UInt32 {
    var value: UInt32 = 0
    if modifiers.contains(.command) { value |= UInt32(cmdKey) }
    if modifiers.contains(.control) { value |= UInt32(controlKey) }
    if modifiers.contains(.option) { value |= UInt32(optionKey) }
    if modifiers.contains(.shift) { value |= UInt32(shiftKey) }
    return value
  }
  var isValid: Bool {
    guard !modifiers.intersection([.command, .control, .option]).isEmpty else { return false }
    if modifiers.contains(.command) && modifiers.intersection([.control, .option]).isEmpty {
      if ["Q", "W", "H", "M", "S", "Z"].contains(key) { return false }
      if !modifiers.contains(.shift) && ["A", "C", "V", "X", "O"].contains(key) { return false }
      if modifiers.contains(.shift) && ["3", "4", "5"].contains(key) { return false }
    }
    return true
  }
  func matches(_ event: NSEvent) -> Bool {
    UInt32(event.keyCode) == keyCode && event.modifierFlags.intersection([.command,.control,.option,.shift]) == modifiers
  }
}

private struct NativeShortcutBindings: Equatable {
  let picker: NativeShortcut
  let ruler: NativeShortcut
  let screenshot: NativeShortcut
  static let defaults = NativeShortcutBindings(picker: NativeShortcut(key: "C", modifiers: [.command, .shift]),
    ruler: NativeShortcut(key: "R", modifiers: [.command, .shift]))
  init(picker: NativeShortcut, ruler: NativeShortcut, screenshot: NativeShortcut = NativeShortcut(key: "X", modifiers: [.command, .shift])) { self.picker = picker; self.ruler = ruler; self.screenshot = screenshot }
  init?(_ data: [String: Any]) {
    guard let picker = NativeShortcut(data["picker"]), let ruler = NativeShortcut(data["ruler"]) else { return nil }
    guard data["screenshot"] == nil || NativeShortcut(data["screenshot"]) != nil else { return nil }
    self.init(picker: picker, ruler: ruler, screenshot: NativeShortcut(data["screenshot"]) ?? Self.defaults.screenshot)
  }
  var isValid: Bool { picker.isValid && ruler.isValid && screenshot.isValid && picker != ruler && picker != screenshot && ruler != screenshot }
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

private final class CaptureButton: NSButton {
  override func resetCursorRects() {
    addCursorRect(bounds, cursor: isEnabled ? .pointingHand : .arrow)
  }
  override var isEnabled: Bool {
    didSet { window?.invalidateCursorRects(for: self) }
  }
}

private final class CapturePopUpButton: NSPopUpButton {
  override func resetCursorRects() {
    addCursorRect(bounds, cursor: isEnabled ? .pointingHand : .arrow)
  }
}

private final class CaptureOverlayView: NSView {
  let snapshot: DisplaySnapshot
  private var tool: String
  var onEvent: (([String: Any]) -> Void)?
  var onCancel: (() -> Void)?
  var isPointerActive = false {
    didSet { if !isPointerActive { releaseCursor() }; if oldValue != isPointerActive { needsDisplay = true } }
  }
  private var pointer = NSPoint.zero
  private var hoverLocation: NSPoint?
  private var label = ""
  private var selectedColor = NSColor.white
  private var measuredRect: NSRect?
  private var tracking: NSTrackingArea?
  private var tolerance = 16
  private var zoom = 12
  private var anchored = false
  private var cursorHidden = false
  private var scrollRemainder: CGFloat = 0
  private var pins: [(id: Int, rect: NSRect, label: String)] = []
  private var continuous = false
  private var pickedCount = 0
  private var pickerActions = "左键取色 · 右键取消"
  private var editingPins = false
  private var selectedPin: Int?
  private var pinDrag: (id: Int, start: NSPoint, handle: String)?
  private var capturePurpose = ""
  private let editbar = NSView()
  private let continuousButton = CaptureButton(checkboxWithTitle: "连续取色", target: nil, action: nil)
  private let copySizeButton = CaptureButton(title: "复制尺寸 ⌘C", target: nil, action: nil)
  private let editButton = CaptureButton(title: "编辑标注", target: nil, action: nil)
  private let redoButton = CaptureButton(title:"重做",target:nil,action:nil)
  private let undoButton = CaptureButton(title: "撤销", target: nil, action: nil)
  private let deleteButton = CaptureButton(title: "删除测量框", target: nil, action: nil)
  private let copyImageButton = CaptureButton(title: "复制图片", target: nil, action: nil)
  private let saveImageButton = CaptureButton(title: "导出 PNG", target: nil, action: nil)
  private let pinSelector = CapturePopUpButton(frame: .zero, pullsDown: false)
  private var modeButtons: [String: NSButton] = [:]
  private let toolbar = NSView()
  private let infoLabel = NSTextField(labelWithString: "")
  private let clearButton = CaptureButton(title: "清除标注", target: nil, action: nil)
  private var toolbarWidth: NSLayoutConstraint?
  private let accent = NSColor(srgbRed: 215 / 255, green: 250 / 255, blue: 107 / 255, alpha: 1)

  init(snapshot: DisplaySnapshot, tool: String) {
    self.snapshot = snapshot
    self.tool = tool
    super.init(frame: NSRect(origin: .zero, size: snapshot.frame.size))
    setupToolbar()
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
  override var isFlipped: Bool { true }
  override var acceptsFirstResponder: Bool { true }

  override func updateTrackingAreas() {
    if let area = tracking { removeTrackingArea(area) }
    let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .cursorUpdate, .activeAlways, .inVisibleRect], owner: self)
    addTrackingArea(area)
    tracking = area
    super.updateTrackingAreas()
  }
  override func resetCursorRects() {
    // Flutter owns cursor feedback while screenshot annotations are editing.
    guard !screenshotEditing else { return }
    let location = window.map { convert($0.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil) }
      ?? hoverLocation ?? .zero
    addCursorRect(bounds, cursor: cursor(at: location))
  }
  override func cursorUpdate(with event: NSEvent) {
    releaseCursor()
    applyCursor(at: convert(event.locationInWindow, from: nil))
  }

  private func cursor(at location: NSPoint) -> NSCursor {
    if pinDrag != nil { return .closedHand }
    func control(in view: NSView) -> NSControl? {
      for child in view.subviews.reversed() where !child.isHidden {
        guard child.convert(child.bounds, to: self).contains(location) else { continue }
        if let item = child as? NSControl { return item }
        if let item = control(in: child) { return item }
      }
      return nil
    }
    for bar in [toolbar, editbar] where !bar.isHidden {
      if bar.convert(bar.bounds, to: self).contains(location) {
        if let item = control(in: bar), item.isEnabled,
          item is NSButton || item is NSPopUpButton { return .pointingHand }
        return .arrow
      }
    }
    if tool == "rectangle" || editingPins {
      if pins.contains(where: { $0.rect.insetBy(dx: -5, dy: -5).contains(location) }) {
        return .openHand
      }
    }
    return .crosshair
  }

  private func applyCursor(at location: NSPoint) {
    guard !screenshotEditing else { return }
    hoverLocation = location
    cursor(at: location).set()
  }
  override func mouseEntered(with event: NSEvent) { window?.makeKey(); send(event, phase: "move") }
  override func mouseExited(with event: NSEvent) {
    isPointerActive = false
    if pinDrag == nil { hoverLocation = nil; NSCursor.arrow.set() }
  }
  override func mouseMoved(with event: NSEvent) { send(event, phase: "move") }
  override func mouseDown(with event: NSEvent) { window?.makeKey(); send(event, phase: "down") }
  override func mouseDragged(with event: NSEvent) { send(event, phase: "drag") }
  override func mouseUp(with event: NSEvent) { send(event, phase: "up") }
  override func rightMouseDown(with event: NSEvent) { if tool == "picker" { send(event,phase:"down") } else { onCancel?() } }
  override func rightMouseUp(with event: NSEvent) { if tool == "picker" { send(event,phase:"up") } }
  override func otherMouseDown(with event: NSEvent) { if tool == "picker", event.buttonNumber == 2 { send(event,phase:"down") } }
  override func otherMouseUp(with event: NSEvent) { if tool == "picker", event.buttonNumber == 2 { send(event,phase:"up") } }
  override func keyDown(with event: NSEvent) {
    switch Int(event.keyCode) {
    case kVK_Escape: onCancel?()
    case kVK_ANSI_C where tool == "rectangle" && event.modifierFlags.contains(.command):
      onEvent?(["type": "copyMeasurement"])
    case kVK_ANSI_Z where event.modifierFlags.contains(.command):
      onEvent?(["type": event.modifierFlags.contains(.shift) ? "redoPins" : "undoPins"])
    case kVK_Delete, kVK_ForwardDelete:
      if editingPins || (tool == "rectangle" && selectedPin != nil) { onEvent?(["type": "deletePin"]) }
    case kVK_Return, kVK_ANSI_KeypadEnter:
      onEvent?(["type": "confirm", "keep": event.modifierFlags.contains(.shift)])
    case kVK_LeftArrow: onEvent?(["type": "nudge", "dx": -1, "dy": 0, "resize": event.modifierFlags.contains(.shift)])
    case kVK_RightArrow: onEvent?(["type": "nudge", "dx": 1, "dy": 0, "resize": event.modifierFlags.contains(.shift)])
    case kVK_UpArrow: onEvent?(["type": "nudge", "dx": 0, "dy": -1, "resize": event.modifierFlags.contains(.shift)])
    case kVK_DownArrow: onEvent?(["type": "nudge", "dx": 0, "dy": 1, "resize": event.modifierFlags.contains(.shift)])
    case kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4:
      guard tool != "picker", tool != "screenshot", !event.isARepeat else { return }
      let modes = [kVK_ANSI_1: "rectangle", kVK_ANSI_2: "horizontal", kVK_ANSI_3: "vertical", kVK_ANSI_4: "cross"]
      onEvent?(["type": "modeChanged", "tool": modes[Int(event.keyCode)]!])
    default: break
    }
  }

  override func scrollWheel(with event: NSEvent) {
    guard tool != "rectangle", tool != "screenshot" else { return }
    scrollRemainder += event.scrollingDeltaY / (event.hasPreciseScrollingDeltas ? 12 : 1)
    let steps = Int(scrollRemainder.rounded(.towardZero))
    if steps != 0 {
      scrollRemainder -= CGFloat(steps)
      onEvent?(["type": "scroll", "steps": steps])
    }
    if event.phase == .ended || event.momentumPhase == .ended { scrollRemainder = 0 }
  }

  private func send(_ event: NSEvent, phase: String) {
    let location = convert(event.locationInWindow, from: nil)
    releaseCursor()
    applyCursor(at: location)
    if pinDrag == nil {
      guard !toolbar.frame.contains(location), (editbar.isHidden || !editbar.frame.contains(location)) else { return }
    }
    if (editingPins || (tool == "rectangle" && !pins.isEmpty)) && tool != "picker" {
      releaseCursor()
      if phase == "down" {
        let selected = pins.first { $0.id == selectedPin }
        let selectedHandle = selected.flatMap { resizeHandle($0.rect, at: location) }
        let pin = selectedHandle != nil ? selected : pins.reversed().first { $0.rect.insetBy(dx: -4, dy: -4).contains(location) }
        onEvent?(["type": "selectPin", "id": pin?.id as Any? ?? NSNull()])
        if let pin = pin {
          let handle = selectedHandle ?? "move"
          pinDrag = (pin.id, location, handle)
          applyCursor(at: location)
          onEvent?(["type": "pinDrag", "id": pin.id, "phase": "start"])
          return
        }
      } else if let drag = pinDrag, phase == "drag" || phase == "up" {
        onEvent?(["type": "pinDrag", "id": drag.id, "phase": phase == "up" ? "end" : "update",
          "handle": drag.handle, "dx": location.x - drag.start.x, "dy": location.y - drag.start.y])
        if phase == "up" { pinDrag = nil }
        applyCursor(at: location)
        return
      }
      if editingPins { return }
    }
    releaseCursor()
    pointer = location
    isPointerActive = true
    needsDisplay = true
    onEvent?(["type": "pointer", "x": pointer.x, "y": pointer.y, "phase": phase,
      "keep": event.modifierFlags.contains(.shift),
      "button": event.buttonNumber == 1 ? "secondary" : event.buttonNumber == 2 ? "middle" : "primary"])
  }
  private func resizeHandle(_ rect: NSRect, at point: NSPoint) -> String? {
    let handles: [(String, NSPoint)] = [
      ("nw", NSPoint(x: rect.minX, y: rect.minY)), ("ne", NSPoint(x: rect.maxX, y: rect.minY)),
      ("sw", NSPoint(x: rect.minX, y: rect.maxY)), ("se", NSPoint(x: rect.maxX, y: rect.maxY)),
      ("n", NSPoint(x: rect.midX, y: rect.minY)), ("s", NSPoint(x: rect.midX, y: rect.maxY)),
      ("w", NSPoint(x: rect.minX, y: rect.midY)), ("e", NSPoint(x: rect.maxX, y: rect.midY))]
    return handles.first { abs($0.1.x - point.x) <= 5 && abs($0.1.y - point.y) <= 5 }?.0
  }
  func sendCurrentPointer() {
    guard let window = window else { return }
    pointer = convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
    isPointerActive = bounds.contains(pointer)
    if isPointerActive { onEvent?(["type": "pointer", "x": pointer.x, "y": pointer.y, "phase": "move"]) }
    needsDisplay = true
  }

  func update(_ data: [String: Any]) {
    if let x = data["x"] as? Double, let y = data["y"] as? Double { pointer = NSPoint(x: x, y: y) }
    label = data["label"] as? String ?? ""
    anchored = data["anchored"] as? Bool == true
    if data["keyboard"] as? Bool == true && isPointerActive {
      if !cursorHidden { NSCursor.hide(); cursorHidden = true }
    } else { releaseCursor() }
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

  #if FRULER_INTEGRATION_TEST
  func integrationClickControl(_ name: String) -> Bool {
    guard let button = ["delete": deleteButton, "undo": undoButton][name], button.isEnabled else { return false }
    button.performClick(nil)
    return true
  }
  func integrationLayout(width: Double, height: Double) -> Bool {
    let view = CaptureOverlayView(snapshot: snapshot, tool: tool)
    view.setFrameSize(NSSize(width: width, height: height))
    view.updateOptions(["tool":tool, "selectedPin":1])
    view.layoutSubtreeIfNeeded()
    return [view.toolbar, view.editbar].allSatisfy { bar in
      view.bounds.contains(bar.frame) && bar.subviews.allSatisfy { bar.bounds.contains($0.frame) }
    }
  }
  var integrationState: [String: Any] {
    let current = NSCursor.current
    let cursorName = [("openHand", NSCursor.openHand), ("closedHand", NSCursor.closedHand),
      ("pointingHand", NSCursor.pointingHand), ("arrow", NSCursor.arrow), ("crosshair", NSCursor.crosshair)]
      .first { current === $0.1 || (current.hotSpot == $0.1.hotSpot &&
        current.image.tiffRepresentation == $0.1.image.tiffRepresentation) }?.0 ?? "other"
    let controls = [("delete", deleteButton), ("undo", undoButton), ("copySize", copySizeButton)]
      .reduce(into: [String: Any]()) { result, entry in
        let rect = entry.1.convert(entry.1.bounds, to: self)
        result[entry.0] = ["x": rect.midX, "y": rect.midY, "enabled": entry.1.isEnabled]
      }
    return ["cursor": cursorName, "controls": controls,"displayId": snapshot.displayID, "tool": tool,
     "selectedPin": selectedPin as Any? ?? NSNull(),
     "pins": pins.map { ["id": $0.id, "x": $0.rect.minX, "y": $0.rect.minY,
       "width": $0.rect.width, "height": $0.rect.height, "label": $0.label] as [String: Any] },
     "copySizeEnabled": copySizeButton.isEnabled]
  }
  #endif

  func releaseCursor() {
    if cursorHidden { NSCursor.unhide(); cursorHidden = false }
  }

  func updateOptions(_ data: [String: Any]) {
    if let value = data["tool"] as? String { tool = value }
    capturePurpose = data["capturePurpose"] as? String ?? ""
    pickerActions = data["pickerActions"] as? String ?? pickerActions
    if let value = data["tolerance"] as? Int { tolerance = value }
    if let value = data["zoom"] as? Int { zoom = value }
    if let value = data["continuous"] as? Bool { continuous = value }
    if let value = data["pickedCount"] as? Int { pickedCount = value }
    if let value = data["editingPins"] as? Bool { editingPins = value }
    selectedPin = data["selectedPin"] as? Int
    continuousButton.state = continuous ? .on : .off
    continuousButton.isHidden = tool != "picker" || !capturePurpose.isEmpty
    editbar.isHidden = tool == "picker" || tool == "screenshot"
    editButton.title = editingPins ? "添加测量框" : "仅编辑框"
    copySizeButton.isHidden = tool != "rectangle"
    copySizeButton.isEnabled = selectedPin != nil
    undoButton.isEnabled = data["canUndoPins"] as? Bool == true
    redoButton.isEnabled = data["canRedoPins"] as? Bool == true
    if let values = data["pinned"] as? [[String: Any]] {
      pins = values.enumerated().compactMap { index, item in
        guard item["displayId"] as? UInt32 == snapshot.displayID,
              let rect = item["rect"] as? [String: Int],
              let left = rect["left"], let top = rect["top"], let right = rect["right"], let bottom = rect["bottom"] else { return nil }
        let sx = bounds.width / Double(snapshot.width), sy = bounds.height / Double(snapshot.height)
        return (item["id"] as? Int ?? index + 1, NSRect(x: Double(left) * sx, y: Double(top) * sy,
          width: Double(right - left) * sx, height: Double(bottom - top) * sy),
          "\(item["id"] as? Int ?? index + 1) · \(item["label"] as? String ?? "")")
      }
      clearButton.title = "清除标注 \(values.count)"
      clearButton.isEnabled = !values.isEmpty
      let titles = ["选择本屏标注"] + pins.map { $0.label }
      if pinSelector.itemTitles != titles {
        pinSelector.removeAllItems(); pinSelector.addItems(withTitles: titles)
      }
      pinSelector.selectItem(at: pins.firstIndex(where: { $0.id == selectedPin }).map { $0 + 1 } ?? 0)
      deleteButton.isEnabled = pins.contains(where: { $0.id == selectedPin })
      copyImageButton.isEnabled = !pins.isEmpty
      saveImageButton.isEnabled = !pins.isEmpty
    }
    for (mode, button) in modeButtons {
      let selected = mode == tool
      button.isHidden = tool == "picker" || tool == "screenshot"
      button.layer?.backgroundColor = (selected ? accent : NSColor.white.withAlphaComponent(0.07)).cgColor
      button.contentTintColor = selected ? .black : .white
      button.setAccessibilityValue(selected ? "已选中" : "")
    }
    clearButton.isHidden = tool == "picker" || tool == "screenshot"
    infoLabel.stringValue = tool == "picker" ? "\(capturePurpose.isEmpty ? "取色" : capturePurpose) · \(zoom)× · 已采集 \(pickedCount)" :
      tool == "screenshot" ? "框选截图 · 松开进入标注 · 方向键微调 · Enter 确认" : editingPins ? "拖动框/边角 · 方向键移动 · Shift 调尺寸" : tool == "rectangle" ? "空白处新增 · 拖框移动 / 边角缩放 · Enter 完成" : "容差 \(tolerance) · 滚轮调整"
    toolbarWidth?.constant = min(bounds.width - 24, tool == "picker" ? 470 : 740)
    needsDisplay = true
    window?.invalidateCursorRects(for: self)
    if let location = hoverLocation { applyCursor(at: location) }
  }

  private func setupToolbar() {
    toolbar.translatesAutoresizingMaskIntoConstraints = false
    toolbar.wantsLayer = true
    toolbar.layer?.backgroundColor = NSColor(srgbRed: 0.055, green: 0.065, blue: 0.075, alpha: 0.97).cgColor
    toolbar.layer?.cornerRadius = 12
    toolbar.layer?.borderColor = NSColor.white.withAlphaComponent(0.17).cgColor
    toolbar.layer?.borderWidth = 1
    addSubview(toolbar)
    let stack = NSStackView()
    stack.translatesAutoresizingMaskIntoConstraints = false
    stack.orientation = .horizontal
    stack.spacing = 7
    stack.alignment = .centerY
    toolbar.addSubview(stack)
    for (index, mode) in ["rectangle", "horizontal", "vertical", "cross"].enumerated() {
      let names = ["矩形", "水平", "垂直", "交叉"]
      let button = CaptureButton(title: "\(index + 1) \(names[index])", target: self, action: #selector(changeMode(_:)))
      button.identifier = NSUserInterfaceItemIdentifier(mode)
      button.font = .systemFont(ofSize: 11, weight: .medium)
      button.isBordered = false
      button.wantsLayer = true
      button.layer?.cornerRadius = 6
      button.widthAnchor.constraint(equalToConstant: 67).isActive = true
      button.heightAnchor.constraint(equalToConstant: 28).isActive = true
      button.toolTip = "切换\(names[index])模式（\(index + 1)）"
      modeButtons[mode] = button
      stack.addArrangedSubview(button)
    }
    infoLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
    infoLabel.textColor = accent
    infoLabel.alignment = .center
    infoLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
    infoLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    stack.addArrangedSubview(infoLabel)
    continuousButton.target = self
    continuousButton.action = #selector(toggleContinuous)
    continuousButton.font = .systemFont(ofSize: 11)
    stack.addArrangedSubview(continuousButton)
    clearButton.target = self
    clearButton.action = #selector(clearPins)
    clearButton.bezelStyle = .rounded
    clearButton.font = .systemFont(ofSize: 11)
    stack.addArrangedSubview(clearButton)
    let close = CaptureButton(title: "退出 Esc", target: self, action: #selector(cancelCapture))
    close.bezelStyle = .rounded
    close.font = .systemFont(ofSize: 11)
    stack.addArrangedSubview(close)
    let width = toolbar.widthAnchor.constraint(equalToConstant: min(bounds.width - 24, 740))
    toolbarWidth = width
    NSLayoutConstraint.activate([
      toolbar.centerXAnchor.constraint(equalTo: centerXAnchor), toolbar.topAnchor.constraint(equalTo: topAnchor, constant: 22),
      toolbar.heightAnchor.constraint(equalToConstant: 46), width,
      stack.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 12),
      stack.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -12),
      stack.topAnchor.constraint(equalTo: toolbar.topAnchor, constant: 8),
      stack.bottomAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: -8)
    ])
    setupEditbar()
    updateOptions(["tool": tool])
  }

  private func setupEditbar() {
    editbar.translatesAutoresizingMaskIntoConstraints = false
    editbar.wantsLayer = true
    editbar.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.93).cgColor
    editbar.layer?.cornerRadius = 10
    addSubview(editbar)
    let stack = NSStackView()
    stack.translatesAutoresizingMaskIntoConstraints = false
    stack.orientation = .horizontal; stack.spacing = 8; stack.alignment = .centerY
    editbar.addSubview(stack)
    let actions: [(NSButton, Selector)] = [(copySizeButton, #selector(copyMeasurement)), (editButton, #selector(togglePinEditing)),
      (undoButton, #selector(undoPin)), (redoButton,#selector(redoPin)), (deleteButton, #selector(deletePin)),
      (copyImageButton, #selector(copyAnnotationImage)), (saveImageButton, #selector(saveAnnotationImage))]
    for (button, action) in actions {
      button.target = self; button.action = action; button.bezelStyle = .rounded
      button.font = .systemFont(ofSize: 11); stack.addArrangedSubview(button)
    }
    deleteButton.toolTip = "删除选中的测量框（Delete / Backspace），⌘Z 撤销"
    pinSelector.target = self; pinSelector.action = #selector(selectAnnotation)
    pinSelector.font = .systemFont(ofSize: 11)
    pinSelector.widthAnchor.constraint(equalToConstant: 180).isActive = true
    stack.insertArrangedSubview(pinSelector, at: 2)
    NSLayoutConstraint.activate([
      editbar.centerXAnchor.constraint(equalTo: centerXAnchor),
      editbar.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 8),
      stack.leadingAnchor.constraint(equalTo: editbar.leadingAnchor, constant: 12),
      stack.trailingAnchor.constraint(equalTo: editbar.trailingAnchor, constant: -12),
      stack.topAnchor.constraint(equalTo: editbar.topAnchor, constant: 8),
      stack.bottomAnchor.constraint(equalTo: editbar.bottomAnchor, constant: -8)
    ])
  }
  private func emitControl(_ type: String, data: [String: Any] = [:]) {
    var event = data; event["type"] = type; onEvent?(event)
    window?.makeFirstResponder(self)
  }
  @objc private func copyMeasurement() { emitControl("copyMeasurement") }
  @objc private func toggleContinuous() { emitControl("continuousChanged", data: ["enabled": continuousButton.state == .on]) }
  @objc private func togglePinEditing() { emitControl("editPins") }
  @objc private func redoPin() { emitControl("redoPins") }
  @objc private func undoPin() { emitControl("undoPins") }
  @objc private func deletePin() { emitControl("deletePin") }
  @objc private func selectAnnotation() {
    let index = pinSelector.indexOfSelectedItem - 1
    emitControl("selectPin", data: ["id": pins.indices.contains(index) ? pins[index].id as Any : NSNull()])
  }
  @objc private func copyAnnotationImage() { emitControl("exportPins", data: ["save": false]) }
  @objc private func saveAnnotationImage() { emitControl("exportPins", data: ["save": true]) }

  @objc private func changeMode(_ sender: NSButton) {
    if let mode = sender.identifier?.rawValue { onEvent?(["type": "modeChanged", "tool": mode]) }
    window?.makeFirstResponder(self)
  }
  @objc private func clearPins() {
    onEvent?(["type": "clearPins"])
    window?.makeFirstResponder(self)
  }
  @objc private func cancelCapture() { onCancel?() }

  private var screenshotEditing = false
  func setScreenshotEditing(_ editing: Bool) {
    screenshotEditing = editing
    window?.invalidateCursorRects(for: self)
    toolbar.isHidden = editing
    editbar.isHidden = editing || tool == "screenshot" || tool == "picker"
    isPointerActive = false
    needsDisplay = true
  }

  override func draw(_ dirtyRect: NSRect) {
    NSImage(cgImage: snapshot.image, size: bounds.size).draw(in: bounds, from: .zero,
      operation: .copy, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.none])
    if screenshotEditing { return }
    if tool != "picker" {
      NSColor.black.withAlphaComponent(0.08).setFill()
      bounds.fill()
    }
    for pin in pins {
      accent.withAlphaComponent(0.08).setFill(); pin.rect.fill()
      accent.setStroke()
      let outline = NSBezierPath(rect: pin.rect); outline.lineWidth = pin.id == selectedPin ? 3 : 1.5; outline.stroke()
      if pin.id == selectedPin {
        for point in [NSPoint(x: pin.rect.minX,y: pin.rect.minY), NSPoint(x: pin.rect.maxX,y: pin.rect.minY),
          NSPoint(x: pin.rect.minX,y: pin.rect.maxY), NSPoint(x: pin.rect.maxX,y: pin.rect.maxY),
          NSPoint(x: pin.rect.midX,y: pin.rect.minY), NSPoint(x: pin.rect.midX,y: pin.rect.maxY),
          NSPoint(x: pin.rect.minX,y: pin.rect.midY), NSPoint(x: pin.rect.maxX,y: pin.rect.midY)] {
          accent.setFill(); NSRect(x: point.x - 3,y: point.y - 3,width: 6,height: 6).fill()
        }
      }
      let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
        .foregroundColor: accent, .backgroundColor: NSColor.black.withAlphaComponent(0.85)]
      (pin.label as NSString).draw(at: NSPoint(x: pin.rect.minX + 4, y: max(4, pin.rect.minY - 20)), withAttributes: attrs)
    }
    guard isPointerActive, !editingPins else { return }
    if tool == "rectangle", !anchored, selectedPin != nil { return }
    if let rect = measuredRect { drawMeasurement(rect) }
    drawCrosshair()
    drawLoupe()
  }

  private func drawMeasurement(_ rect: NSRect) {
    accent.setStroke()
    let path = NSBezierPath()
    path.lineWidth = 1.5
    if tool == "rectangle" || tool == "screenshot" {
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
    let width: CGFloat = tool == "picker" ? 380 : 300
    let height: CGFloat = tool == "picker" ? 208 : 64
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
      let cell = CGFloat(zoom) / (window?.backingScaleFactor ?? 1)
      let radius = Int(ceil(99 / cell / 2)) + 1
      let minX = max(0, px - radius), minY = max(0, py - radius)
      let maxX = min(snapshot.width, px + radius + 1), maxY = min(snapshot.height, py + radius + 1)
      if let crop = snapshot.image.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)) {
        let area = NSRect(x: box.minX + 14, y: box.minY + 12, width: 99, height: 99)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: area).addClip()
        NSColor.black.setFill(); area.fill()
        // At display edges pad the missing pixels instead of stretching the crop.
        let imageRect = NSRect(x: area.midX - (CGFloat(px - minX) + 0.5) * cell,
          y: area.midY - (CGFloat(py - minY) + 0.5) * cell,
          width: CGFloat(maxX - minX) * cell, height: CGFloat(maxY - minY) * cell)
        NSImage(cgImage: crop, size: imageRect.size).draw(in: imageRect, from: .zero,
          operation: .copy, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.none])
        accent.setStroke()
        let center = NSBezierPath(rect: NSRect(x: area.midX - cell / 2, y: area.midY - cell / 2, width: cell, height: cell))
        center.lineWidth = 1.5; center.stroke()
        NSGraphicsContext.restoreGraphicsState()
      }
      selectedColor.setFill()
      NSBezierPath(roundedRect: NSRect(x: box.minX + 130, y: box.minY + 12, width: width - 146, height: 99), xRadius: 7, yRadius: 7).fill()
    }
    let labelY = tool == "picker" ? box.minY + 122 : box.minY + 12
    (label as NSString).draw(at: NSPoint(x: box.minX + 14, y: labelY), withAttributes: [
      .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.white])
    let hint = tool == "rectangle" ? (anchored ? "松手保留 · 方向键微调" : "拖拽新增 · 拖框移动 / 边角缩放 · Enter 复制并结束") :
      (continuous && tool == "picker" ? "点击 / Enter 连续采集 · Esc 结束" : "点击 / Enter 复制 · 方向键微调 · Esc 取消")
    let actionHint = tool == "picker" ? "\(pickerActions)\nEnter 按左键动作 · 方向键微调 · Esc 取消" : hint
    (actionHint as NSString).draw(in:NSRect(x:box.minX+14,y:labelY+21,width:width-28,height:60),withAttributes:[
      .font:NSFont.systemFont(ofSize:11),.foregroundColor:NSColor.gray])
  }


}

private extension Int {
  func clamped(_ minValue: Int, _ maxValue: Int) -> Int { Swift.min(maxValue, Swift.max(minValue, self)) }
}

/// Render a local crop from the frozen frame, at screenshot-pixel resolution.
private enum AnnotationRenderer {
  static func labelFrame(rect: NSRect, size: NSSize, canvas: NSRect, occupied: [NSRect]) -> NSRect {
    let x = min(max(0, rect.minX), max(0, canvas.width - size.width))
    let y = max(0, rect.minY - 22), step = size.height + 4
    let aboveCount = Int(y / step) + 1
    let fallback = NSRect(x: x, y: y, width: size.width, height: size.height)
    for index in 0..<(aboveCount + Int(canvas.height / step) + 2) {
      let candidateY = index < aboveCount ? y - CGFloat(index) * step :
        max(rect.maxY + 8, y + step) + CGFloat(index - aboveCount) * step
      guard candidateY >= 0, candidateY + size.height <= canvas.height else { continue }
      let candidate = NSRect(x: x, y: candidateY, width: size.width, height: size.height)
      if !occupied.contains(where: { $0.insetBy(dx: -2, dy: -2).intersects(candidate) }) { return candidate }
    }
    return fallback
  }
  static func png(image: CGImage, annotations: [[String: Any]]) -> Data? {
    let canvas = NSRect(x: 0,y: 0,width: image.width,height: image.height)
    let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 13,weight: .semibold),
      .foregroundColor: NSColor(srgbRed: 215/255,green: 250/255,blue: 107/255,alpha: 1),
      .backgroundColor: NSColor.black.withAlphaComponent(0.85)]
    var items: [(NSRect, String, NSRect)] = []
    var crop = NSRect.null
    for annotation in annotations {
      guard let data = annotation["rect"] as? [String: Int], let left = data["left"], let top = data["top"],
            let right = data["right"], let bottom = data["bottom"], left >= 0, top >= 0,
            right <= image.width, bottom <= image.height, right > left, bottom > top else { continue }
      let rect = NSRect(x: left,y: top,width: right-left,height: bottom-top)
      let label = "\(annotation["id"] as? Int ?? items.count + 1) · \(annotation["label"] as? String ?? "")"
      let size = (label as NSString).size(withAttributes: attrs)
      let labelRect = labelFrame(rect: rect, size: size, canvas: canvas, occupied: items.map { $0.2 })
      items.append((rect,label,labelRect))
      crop = crop.union(rect).union(labelRect)
    }
    guard !items.isEmpty else { return nil }
    crop = crop.insetBy(dx: -16,dy: -16).intersection(canvas).integral
    guard let context = CGContext(data: nil,width: Int(crop.width),height: Int(crop.height),bitsPerComponent: 8,
      bytesPerRow: 0,space: CGColorSpace(name: CGColorSpace.sRGB)!,bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    context.translateBy(x: 0,y: crop.height); context.scaleBy(x: 1,y: -1)
    context.translateBy(x: -crop.minX,y: -crop.minY)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context,flipped: true)
    NSImage(cgImage: image,size: canvas.size).draw(in: canvas,from: .zero,operation: .copy,fraction: 1,respectFlipped: true,
      hints: [.interpolation: NSImageInterpolation.none])
    let accent = NSColor(srgbRed: 215/255,green: 250/255,blue: 107/255,alpha: 1)
    for (rect,label,labelRect) in items {
      accent.setStroke(); let outline = NSBezierPath(rect: rect); outline.lineWidth = 2; outline.stroke()
      (label as NSString).draw(at: labelRect.origin,withAttributes: attrs)
    }
    NSGraphicsContext.restoreGraphicsState()
    guard let result = context.makeImage() else { return nil }
    return NSBitmapImageRep(cgImage: result).representation(using: .png,properties: [:])
  }
}
