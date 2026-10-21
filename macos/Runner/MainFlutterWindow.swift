import Cocoa
import FlutterMacOS
import ScreenCaptureKit
import Carbon.HIToolbox
import UniformTypeIdentifiers

class MainFlutterWindow: NSWindow {
  private var desktopBridge: FrulerDesktopBridge?
  private var historyRequested = false
  override func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
    if place != .out && !historyRequested { return }
    super.order(place, relativeTo: otherWin)
  }
  func presentHistory() {
    historyRequested = true
    deminiaturize(nil)
    makeKeyAndOrderFront(nil)
  }

  func requestQuitConfirmation() -> Bool { desktopBridge?.requestQuitConfirmation() ?? false }

  override func awakeFromNib() {
    guard FrulerInstance.acquire() else { NSApp.terminate(nil); return }
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    // Start the engine even though the history window stays hidden at launch.
    _ = flutterViewController.view
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

    flutterViewController.engine.run(withEntrypoint: nil)
    super.awakeFromNib()
  }
}

/// System integration only. Pixel sampling and measurement rules live in Dart.
private final class FrulerDesktopBridge: NSObject, DesktopHostApi {
  private weak var mainWindow: NSWindow?
  private let callbacks: DesktopFlutterApi
  private var sink: (([String: Any]) -> Void)?
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

  func availableFontFamilies(completion: @escaping (Result<[String], Error>) -> Void) {
    completion(.success(NSFontManager.shared.availableFontFamilies.sorted {
      $0.localizedStandardCompare($1) == .orderedAscending
    }))
  }

  init(window: NSWindow, messenger: FlutterBinaryMessenger) {
    mainWindow = window
    flutterController = window.contentViewController as? FlutterViewController
    callbacks = DesktopFlutterApi(binaryMessenger: messenger)
    super.init()
    DesktopHostApiSetup.setUp(binaryMessenger: messenger, api: self)
    sink = { [weak self] data in
      guard let self = self else { return }
      self.callbacks.onEvent(event: nativeEvent(data)) { response in
        if case .failure(let error) = response {
          NSLog("fruler callback failed: %@", String(describing: error))
        }
      }
    }
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
    for panel in overlays.values { panel.overlay.snapshot.pixels.unpublish() }
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

  func requestQuitConfirmation() -> Bool {
    if session != nil {cancelSession()}
    return false
  }

  #if FRULER_INTEGRATION_TEST
  private var integrationDriver: FlutterMethodChannel?
  private var cancelNextSave = false
  private var clipboardBackup: [[NSPasteboard.PasteboardType: Data]]?
  private var pointerBackup: CGPoint?
  private var integrationPixelFixture: NativePixelBuffer?
  func installIntegrationDriver(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "dev.fruler/integration", binaryMessenger: messenger)
    integrationDriver = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      let args = call.arguments as? [String: Any] ?? [:]
      switch call.method {
      case "pixelBufferCount": result(NativePixelBuffer.liveCount)
      case "createPixelFixture":
        self.integrationPixelFixture?.unpublish()
        guard let pixels = NativePixelBuffer(byteCount: 32) else { result(nil); return }
        let bytes = pixels.data.assumingMemoryBound(to: UInt8.self)
        for y in 0..<2 {
          for x in 0..<3 {
            let index = y * 16 + x * 4
            bytes[index] = UInt8(20 + x * 30)
            bytes[index + 1] = UInt8(40 + y * 50)
            bytes[index + 2] = 60
            bytes[index + 3] = 255
          }
        }
        self.integrationPixelFixture = pixels
        result(["bufferId": pixels.id, "byteLength": pixels.byteCount, "rowBytes": 16])
      case "releasePixelFixture":
        self.integrationPixelFixture?.unpublish()
        self.integrationPixelFixture = nil
        result(nil)
      case "raiseRegionFixture":
        DistributedNotificationCenter.default().postNotificationName(
          Notification.Name("dev.fruler.integration.raiseRegionFixture"),object:nil,userInfo:nil,deliverImmediately:true)
        result(nil)
      case "status":
        result(["panels":self.overlays.count,"active":self.session != nil,
          "permission":CGPreflightScreenCaptureAccess(),"bundleId":Bundle.main.bundleIdentifier ?? "",
          "mainVisible":self.mainWindow?.isVisible == true,"editing":self.screenshotHost != nil,
          "statusItemCount":self.statusItem == nil ? 0 : 1,"accessory":NSApp.activationPolicy() == .accessory,
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
        let keyCharacters: [UInt16:String] = [51:"\u{7f}",117:"\u{f728}",6:"z",16:"y",8:"c",46:"m"]
        guard let panel=self.overlays.values.first(where:{$0.isKeyWindow}) ?? self.overlays.values.first,
          let code=args["keyCode"] as? UInt16,
          let event=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:
            (args["command"] as? Bool == true ? NSEvent.ModifierFlags.command : []).union(
              args["shift"] as? Bool == true ? .shift : []),
            timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:panel.windowNumber,
            context:nil,characters:keyCharacters[code] ?? "",charactersIgnoringModifiers:keyCharacters[code] ?? "",isARepeat:false,keyCode:code) else {
          result(FlutterError(code:"test_no_panel",message:"No native panel",details:nil));return
        }
        if let host = self.screenshotHost {
          host.makeKeyAndOrderFront(nil)
          // Keep Flutter's text input responder when editing text.
          if host.firstResponder === host.overlay {
            host.makeFirstResponder(self.flutterController?.view)
          }
          NSApp.sendEvent(event)
          if let up = NSEvent.keyEvent(with: .keyUp, location: .zero,
            modifierFlags: event.modifierFlags, timestamp: event.timestamp,
            windowNumber: host.windowNumber, context: nil,
            characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code) {
            NSApp.sendEvent(up)
          }
        } else {
          panel.makeKeyAndOrderFront(nil);panel.makeFirstResponder(panel.overlay)
          panel.sendEvent(event)
        }
        result(nil)
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

  func initialize(completion: @escaping (Result<NativeStatus, Error>) -> Void) {
    completion(.success(NativeStatus(permission: CGPreflightScreenCaptureAccess(), shortcuts: hasShortcuts)))
  }

  func configureShortcuts(bindings: NativeBindings, completion: @escaping (Result<Bool, Error>) -> Void) {
    let args: [String: Any] = bindings.local
    guard let requested = NativeShortcutBindings(args), requested.isValid else {
      completion(.failure(PigeonError(code: "shortcut_invalid", message: "请使用不同的字母或数字组合，并避开系统退出、编辑和截图快捷键。", details: nil)))
      return
    }
    if requested == shortcuts && (hasShortcuts || shortcutRecording) { completion(.success(true)); return }
    let previous = shortcuts
    let hadShortcuts = hasShortcuts
    unregisterHotkeys()
    if shortcutRecording || registerHotkeys(requested) {
      shortcuts = requested
      updateMenuShortcuts()
      completion(.success(true))
    } else {
      if hadShortcuts { _ = registerHotkeys(previous) }
      updateMenuShortcuts()
      completion(.failure(PigeonError(code: "shortcut_conflict", message: "快捷键已被占用", details: ["shortcuts": hasShortcuts])))
    }
  }

  func setShortcutRecording(recording: Bool, completion: @escaping (Result<Bool, Error>) -> Void) {
    shortcutRecording = recording
    if shortcutRecording {
      pauseApplicationMenuKeys()
      unregisterHotkeys()
      updateMenuShortcuts()
      completion(.success(true))
    } else {
      for (item, key) in pausedMenuKeys { item.keyEquivalent = key }
      pausedMenuKeys.removeAll()
      let registered = registerHotkeys(shortcuts)
      updateMenuShortcuts()
      completion(.success(registered))
    }
  }

  func requestPermission(completion: @escaping (Result<Bool, Error>) -> Void) {
    completion(.success(CGRequestScreenCaptureAccess()))
  }

  func showMainWindow(completion: @escaping (Result<Void, Error>) -> Void) {
    presentMainWindow(); completion(.success(()))
  }

  func openPrivacySettings(completion: @escaping (Result<Void, Error>) -> Void) {
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
      NSWorkspace.shared.open(url)
    }
    completion(.success(()))
  }

  func loadState(completion: @escaping (Result<String?, Error>) -> Void) {
    completion(.success(UserDefaults.standard.string(forKey: stateKey)))
  }

  func saveState(json: String, completion: @escaping (Result<Void, Error>) -> Void) {
    UserDefaults.standard.set(json, forKey: stateKey)
    completion(.success(()))
  }

  func replyToQuit(allow: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
    NSApp.reply(toApplicationShouldTerminate:allow)
    completion(.success(()))
  }

  func exportImage(png: FlutterStandardTypedData, save: Bool, completion: @escaping (Result<Bool, Error>) -> Void) {
    let bytes = png
    if save {
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
      guard panel.runModal() == .OK, let url = panel.url else { completion(.success(false)); return }
      do { try bytes.data.write(to:url,options:.atomic); completion(.success(true)) }
      catch { completion(.failure(PigeonError(code:"image_export_failed",message:error.localizedDescription,details:nil))) }
    } else {
      NSPasteboard.general.clearContents()
      if NSPasteboard.general.setData(bytes.data,forType:.png) { completion(.success(true)) }
      else { completion(.failure(PigeonError(code:"clipboard_failed",message:"无法写入图片剪贴板",details:nil))) }
    }
  }

  func openPaletteFile(completion: @escaping (Result<String?, Error>) -> Void) {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.json]
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    NSApp.activate(ignoringOtherApps: true)
    guard panel.runModal() == .OK, let url = panel.url else { completion(.success(nil)); return }
    do {
      let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
      guard size <= 2 * 1024 * 1024 else {
        completion(.failure(PigeonError(code: "import_failed", message: "JSON 文件不能超过 2 MB", details: nil))); return
      }
      let text = try String(contentsOf: url, encoding: .utf8)
      guard text.utf8.count <= 2 * 1024 * 1024 else {
        completion(.failure(PigeonError(code: "import_failed", message: "JSON 文件不能超过 2 MB", details: nil))); return
      }
      completion(.success(text))
    } catch { completion(.failure(PigeonError(code: "import_failed", message: error.localizedDescription, details: nil))) }
  }

  func saveTextFile(filename: String, text: String, completion: @escaping (Result<Bool, Error>) -> Void) {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = filename
    panel.allowedContentTypes = [UTType(filenameExtension: (filename as NSString).pathExtension) ?? .plainText]
    panel.canCreateDirectories = true
    NSApp.activate(ignoringOtherApps: true)
    guard panel.runModal() == .OK, let url = panel.url else { completion(.success(false)); return }
    do { try Data(text.utf8).write(to: url, options: .atomic); completion(.success(true)) }
    catch { completion(.failure(PigeonError(code: "export_failed", message: error.localizedDescription, details: nil))) }
  }

  func exportAnnotations(sessionId: Int64, displayId: Int64, annotations: [MeasurementPin], save: Bool, completion: @escaping (Result<Bool, Error>) -> Void) {
    let id = Int(sessionId)
    guard id == session, let display = UInt32(exactly: displayId),
          let overlay = overlays[display]?.overlay,
          let png = AnnotationRenderer.png(image: overlay.snapshot.image, annotations: annotations.map { $0.local }) else {
      completion(.failure(PigeonError(code: "invalid_export", message: "没有可导出的标注", details: nil))); return
    }
    if save {
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
      guard panel.runModal() == .OK, let url = panel.url else { completion(.success(false)); return }
      do { try png.write(to: url, options: .atomic); completion(.success(true)) }
      catch { completion(.failure(PigeonError(code: "export_failed", message: error.localizedDescription, details: nil))) }
    } else {
      NSPasteboard.general.clearContents()
      if NSPasteboard.general.setData(png, forType: .png) { completion(.success(true)) }
      else { completion(.failure(PigeonError(code: "clipboard_failed", message: "无法写入图片剪贴板", details: nil))) }
    }
  }

  func begin(tool: CaptureTool, completion: @escaping (Result<CaptureReply, Error>) -> Void) {
    capture(tool: tool.name, completion: completion)
  }

  func updateOverlay(state: OverlayState, completion: @escaping (Result<Void, Error>) -> Void) {
    let args: [String: Any] = state.local
    if Int(state.sessionId) == session {
      for panel in overlays.values { panel.overlay.updateOptions(args) }
      if let display = args["displayId"] as? UInt32 {
        for (key, panel) in overlays { panel.overlay.isPointerActive = key == display }
        overlays[display]?.overlay.update(args)
      }
    }
    completion(.success(()))
  }

  func editScreenshot(sessionId: Int64, displayId: Int64, completion: @escaping (Result<Void, Error>) -> Void) {
    let id = Int(sessionId)
    guard id == session,
          let display = UInt32(exactly: displayId), let panel = overlays[display],
          let controller = flutterController else {
      completion(.failure(PigeonError(code:"capture_cancelled",message:"截图会话已结束",details:nil))); return
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
    completion(.success(()))
  }

  func reselectScreenshot(sessionId: Int64, completion: @escaping (Result<Void, Error>) -> Void) {
    if Int(sessionId) == session {
      restoreScreenshotView()
      for panel in overlays.values { panel.overlay.setScreenshotEditing(false) }
      overlays.values.first?.makeKeyAndOrderFront(nil)
      if let panel = overlays.values.first { panel.makeFirstResponder(panel.overlay) }
    }
    completion(.success(()))
  }

  func finish(sessionId: Int64, completion: @escaping (Result<Void, Error>) -> Void) {
    if Int(sessionId) == session { closeSession() }
    completion(.success(()))
  }

  private func capture(tool: String, completion: @escaping (Result<CaptureReply, Error>) -> Void) {
    guard !preparing && session == nil else {
      completion(.failure(PigeonError(code: "capture_busy", message: "已有工具正在使用", details: nil)))
      return
    }
    guard CGPreflightScreenCaptureAccess() else {
      completion(.failure(PigeonError(code: "screen_permission", message: "请先允许 fruler 录制屏幕", details: nil)))
      return
    }
    guard sink != nil else {
      completion(.failure(PigeonError(code: "no_listener", message: "工具尚未就绪", details: nil)))
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
        let targets = CaptureRegionTarget.visibleWindows()
        for snapshot in captures {
          let panel = CapturePanel(snapshot: snapshot, tool: tool)
          panel.overlay.regionTargets = targets
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
        completion(.success(CaptureReply(sessionId: Int64(id), displays: captures.map { $0.channelData })))
        // Input may precede the Pigeon capture reply; the Dart controller queues it.
        DispatchQueue.main.async { [weak self] in
          guard self?.session == id else { return }
          active?.overlay.sendCurrentPointer()
        }
      } catch {
        let cancelled = error is CancellationError || self.session != id
        if self.session == id { self.closeSession() }
        completion(.failure(PigeonError(code: cancelled ? "capture_cancelled" : "capture_failed",
          message: cancelled ? "已取消截图" : "屏幕截图失败：\(error.localizedDescription)", details: nil)))
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
    for panel in overlays.values {
      panel.overlay.snapshot.pixels.unpublish()
      panel.overlay.releaseCursor(); panel.orderOut(nil); panel.close()
    }
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
    let show = menu.addItem(withTitle: "打开 fruler", action: #selector(presentMainWindow), keyEquivalent: "")
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
      presentMainWindow()
      sink?(["type": "activate", "tool": tool])
      return
    }
    sink?(["type": "activate", "tool": tool])
  }
  @objc private func presentMainWindow() {
    if session != nil { cancelSession() }
    NSApp.activate(ignoringOtherApps: true)
    (mainWindow as? MainFlutterWindow)?.presentHistory()
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

struct CaptureRegionGeometry {
  static func localRect(_ rect: CGRect, display: CGRect) -> CGRect? {
    let clipped = rect.intersection(display)
    guard !clipped.isNull, clipped.width >= 1, clipped.height >= 1 else { return nil }
    return clipped.offsetBy(dx: -display.minX, dy: -display.minY)
  }
  static func pixels(_ rect: CGRect, size: CGSize, width: Int, height: Int) -> [String:Int] {
    ["left":max(0,Int(floor(rect.minX / size.width * Double(width)))),
     "top":max(0,Int(floor(rect.minY / size.height * Double(height)))),
     "right":min(width,Int(ceil(rect.maxX / size.width * Double(width)))),
     "bottom":min(height,Int(ceil(rect.maxY / size.height * Double(height))))]
  }
}
private struct CaptureRegionTarget {
  let rect: CGRect
  let title: String
  static func visibleWindows() -> [CaptureRegionTarget] {
    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly,.excludeDesktopElements],kCGNullWindowID) as? [[String:Any]] ?? []
    return windows.compactMap { info in
      guard let pid = info[kCGWindowOwnerPID as String] as? Int32,
        pid != ProcessInfo.processInfo.processIdentifier,
        info[kCGWindowLayer as String] as? Int == 0,
        (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
        let bounds = info[kCGWindowBounds as String] as? [String:Any],
        let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary),
        rect.width > 1, rect.height > 1 else { return nil }
      return CaptureRegionTarget(rect:rect,title:info[kCGWindowName as String] as? String ?? "")
    }
  }
}

private struct DisplaySnapshot {
  let displayID: UInt32
  let frame: NSRect
  let name: String
  let width: Int
  let height: Int
  let pixels: NativePixelBuffer
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
    guard let pixels = NativePixelBuffer(byteCount: pixelWidth * pixelHeight * 4) else {
      throw CaptureFailure.unavailable
    }
    self.pixels = pixels
    let normalized: CGImage? = {
      guard let context = CGContext(data: pixels.data, width: pixelWidth, height: pixelHeight,
        bitsPerComponent: 8, bytesPerRow: pixelWidth * 4, space: space,
        bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
      context.interpolationQuality = .none
      context.setFillColor(CGColor(gray: 1, alpha: 1))
      context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
      context.draw(image, in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
      return context.makeImage()
    }()
    guard let normalized = normalized else { throw CaptureFailure.unavailable }
    self.image = normalized
  }

  var channelData: DisplayFrame {
    DisplayFrame(id: Int64(displayID), name: name, width: Int64(width), height: Int64(height),
      logicalWidth: Double(frame.width), logicalHeight: Double(frame.height),
      bufferId: pixels.id, byteLength: Int64(pixels.byteCount), rowBytes: Int64(width * 4))
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
  var regionTargets: [CaptureRegionTarget] = []
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
    toolbar.isHidden = tool == "screenshot"
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
    case kVK_ANSI_C where tool == "screenshot" && !event.modifierFlags.contains(.command):
      onEvent?(["type":"sampleColor"])
    case kVK_ANSI_M where tool == "screenshot" && !event.modifierFlags.contains(.command):
      onEvent?(["type":"copyCaptureSize"])
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

  private func suggestedRegion(at location: NSPoint) -> CGRect {
    let display = CGDisplayBounds(snapshot.displayID)
    let global = CGPoint(x:display.minX+location.x,y:display.minY+location.y)
    guard let target = regionTargets.first(where:{$0.rect.contains(global)}) else { return bounds }
    return CaptureRegionGeometry.localRect(target.rect,display:display) ?? bounds
  }

  private func send(_ event: NSEvent, phase: String) {
    let location = convert(event.locationInWindow, from: nil)
    releaseCursor()
    applyCursor(at: location)
    if pinDrag == nil {
      guard (toolbar.isHidden || !toolbar.frame.contains(location)), (editbar.isHidden || !editbar.frame.contains(location)) else { return }
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
    var data: [String:Any] = ["type": "pointer", "x": pointer.x, "y": pointer.y, "phase": phase,
      "keep": event.modifierFlags.contains(.shift),
      "button": event.buttonNumber == 1 ? "secondary" : event.buttonNumber == 2 ? "middle" : "primary"]
    if tool == "screenshot" && !event.modifierFlags.contains(.option) {
      data["suggestedRect"] = CaptureRegionGeometry.pixels(suggestedRegion(at:location),
        size:bounds.size,width:snapshot.width,height:snapshot.height)
    }
    onEvent?(data)
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
    if isPointerActive {
      var data: [String:Any] = ["type":"pointer","x":pointer.x,"y":pointer.y,"phase":"move"]
      if tool == "screenshot" {
        data["suggestedRect"] = CaptureRegionGeometry.pixels(suggestedRegion(at:pointer),
          size:bounds.size,width:snapshot.width,height:snapshot.height)
      }
      onEvent?(data)
    }
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
    let control: NSButton? = modeButtons[name] ?? ["delete":deleteButton,"undo":undoButton][name]
    guard let button=control, button.isEnabled else { return false }
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
     "preview":measuredRect.map { CaptureRegionGeometry.pixels($0,size:bounds.size,width:snapshot.width,height:snapshot.height) } as Any? ?? NSNull(),
     "regions":regionTargets.compactMap { target -> [String:Any]? in
       guard let rect=CaptureRegionGeometry.localRect(target.rect,display:CGDisplayBounds(snapshot.displayID)) else { return nil }
       return ["title":target.title,"x":rect.minX,"y":rect.minY,"width":rect.width,"height":rect.height]
     },

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
    toolbar.isHidden = screenshotEditing || tool == "screenshot"
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
      button.isHidden = (tool == "picker" || tool == "screenshot") && !["screenshot","picker","rectangle"].contains(mode)
      button.layer?.backgroundColor = (selected ? accent : NSColor.white.withAlphaComponent(0.07)).cgColor
      button.contentTintColor = selected ? .black : .white
      button.setAccessibilityValue(selected ? "已选中" : "")
    }
    clearButton.isHidden = tool == "picker" || tool == "screenshot"
    infoLabel.stringValue = tool == "picker" ? "\(capturePurpose.isEmpty ? "取色" : capturePurpose) · \(zoom)× · 已采集 \(pickedCount)" :
      tool == "screenshot" ? "单击吸附 · 拖动框选 · C 取色 · M 复制尺寸" : editingPins ? "拖动框/边角 · 方向键移动 · Shift 调尺寸" : tool == "rectangle" ? "空白处新增 · 拖框移动 / 边角缩放 · Enter 完成" : "容差 \(tolerance) · 滚轮调整"
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
    for (index, mode) in ["screenshot", "picker", "rectangle", "horizontal", "vertical", "cross"].enumerated() {
      let names = ["截图", "取色", "矩形", "水平", "垂直", "交叉"]
      let button = CaptureButton(title: names[index], target: self, action: #selector(changeMode(_:)))
      button.identifier = NSUserInterfaceItemIdentifier(mode)
      button.font = .systemFont(ofSize: 11, weight: .medium)
      button.isBordered = false
      button.wantsLayer = true
      button.layer?.cornerRadius = 6
      button.widthAnchor.constraint(equalToConstant: 67).isActive = true
      button.heightAnchor.constraint(equalToConstant: 28).isActive = true
      button.toolTip = index >= 2 ? "切换\(names[index])模式（\(index - 1)）" : "切换\(names[index])，复用当前截图"
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
    toolbar.isHidden = editing || tool == "screenshot"
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
    if tool == "screenshot", let rect = measuredRect {
      let shade = NSBezierPath(rect:bounds)
      shade.appendRect(rect);shade.windingRule = .evenOdd
      NSColor.black.withAlphaComponent(0.22).setFill();shade.fill()
    }
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
    let sampling = tool == "picker" || tool == "screenshot"
    let width: CGFloat = sampling ? 220 : 300
    let height: CGFloat = sampling ? (tool == "picker" ? 278 : 250) : 64
    var x = pointer.x + 26
    var y = pointer.y + 26
    if x + width > bounds.width - 12 { x = pointer.x - width - 26 }
    if y + height > bounds.height - 12 { y = pointer.y - height - 26 }
    let box = NSRect(x: max(12, x), y: max(12, y), width: width, height: height)
    NSColor(srgbRed: 0.065, green: 0.075, blue: 0.085, alpha: 0.97).setFill()
    NSBezierPath(roundedRect: box, xRadius: 12, yRadius: 12).fill()
    if sampling {
      let px = Int((pointer.x / bounds.width * Double(snapshot.width)).rounded(.down)).clamped(0, snapshot.width - 1)
      let py = Int((pointer.y / bounds.height * Double(snapshot.height)).rounded(.down)).clamped(0, snapshot.height - 1)
      let cell = CGFloat(zoom) / (window?.backingScaleFactor ?? 1)
      let radius = Int(ceil(192 / cell / 2)) + 1
      let minX = max(0, px - radius), minY = max(0, py - radius)
      let maxX = min(snapshot.width, px + radius + 1), maxY = min(snapshot.height, py + radius + 1)
      if let crop = snapshot.image.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)) {
        let area = NSRect(x: box.minX + 14, y: box.minY + 12, width: 192, height: 112)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: area).addClip()
        NSColor.black.setFill(); area.fill()
        // At display edges pad the missing pixels instead of stretching the crop.
        let imageRect = NSRect(x: area.midX - (CGFloat(px - minX) + 0.5) * cell,
          y: area.midY - (CGFloat(py - minY) + 0.5) * cell,
          width: CGFloat(maxX - minX) * cell, height: CGFloat(maxY - minY) * cell)
        NSImage(cgImage: crop, size: imageRect.size).draw(in: imageRect, from: .zero,
          operation: .copy, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.none])
        if tool == "screenshot", let rect = measuredRect {
          let sx = CGFloat(snapshot.width) / bounds.width, sy = CGFloat(snapshot.height) / bounds.height
          let enlarged = NSRect(x: area.midX + (rect.minX * sx - CGFloat(px) - 0.5) * cell,
            y: area.midY + (rect.minY * sy - CGFloat(py) - 0.5) * cell,
            width: rect.width * sx * cell, height: rect.height * sy * cell)
          accent.setStroke()
          let edge = NSBezierPath(rect: enlarged); edge.lineWidth = 1; edge.stroke()
        }
        accent.setStroke()
        let center = NSBezierPath(rect: NSRect(x: area.midX - cell / 2, y: area.midY - cell / 2, width: cell, height: cell))
        center.lineWidth = 1.5; center.stroke()
        NSGraphicsContext.restoreGraphicsState()
      }
    }
    let labelY = sampling ? box.minY + 134 : box.minY + 12
    if sampling {
      selectedColor.setFill()
      NSRect(x: box.minX + 14, y: labelY + 2, width: 12, height: 12).fill()
      NSColor.white.withAlphaComponent(0.5).setStroke()
      NSBezierPath(rect: NSRect(x: box.minX + 14, y: labelY + 2, width: 12, height: 12)).stroke()
      let rgb = selectedColor.usingColorSpace(.sRGB) ?? selectedColor
      let r = Int((rgb.redComponent * 255).rounded()), g = Int((rgb.greenComponent * 255).rounded()), b = Int((rgb.blueComponent * 255).rounded())
      let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.white]
      (String(format: "#%02X%02X%02X", r, g, b) as NSString).draw(at: NSPoint(x: box.minX + 32, y: labelY), withAttributes: attrs)
      let px = Int((pointer.x / bounds.width * Double(snapshot.width)).rounded(.down)).clamped(0, snapshot.width - 1)
      let py = Int((pointer.y / bounds.height * Double(snapshot.height)).rounded(.down)).clamped(0, snapshot.height - 1)
      var details = "RGB: \(r), \(g), \(b)\nX: \(px)  Y: \(py)"
      if tool == "screenshot", let rect = measuredRect {
        let w = Int((rect.width / bounds.width * Double(snapshot.width)).rounded())
        let h = Int((rect.height / bounds.height * Double(snapshot.height)).rounded())
        details += "\n区域: \(w) × \(h) px"
      }
      (details as NSString).draw(at: NSPoint(x: box.minX + 14, y: labelY + 18), withAttributes: attrs)
    } else {
      (label as NSString).draw(at: NSPoint(x: box.minX + 14, y: labelY), withAttributes: [
        .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.white])
    }
    let hint = tool == "rectangle" ? (anchored ? "松手保留 · 方向键微调" : "拖拽新增 · 拖框移动 / 边角缩放 · Enter 复制并结束") :
      (continuous && tool == "picker" ? "点击 / Enter 连续采集 · Esc 结束" : "点击 / Enter 复制 · 方向键微调 · Esc 取消")
    let actionHint = tool == "screenshot" ? "C 复制颜色 · M 复制尺寸\nOption 暂停吸附" : tool == "picker" ? "\(pickerActions)\nEnter 按左键动作 · 方向键微调 · Esc 取消" : hint
    (actionHint as NSString).draw(in:NSRect(x:box.minX+14,y: sampling ? box.minY + 207 : labelY + 21,width:width-28,height:60),withAttributes:[
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
