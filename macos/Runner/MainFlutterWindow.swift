import Cocoa
import FlutterMacOS
import ScreenCaptureKit
import Carbon.HIToolbox
import UniformTypeIdentifiers
import AVFoundation

/// 启动时 Dart 通道尚未就绪，保留有限条原生日志，由 Dart 统一落盘和轮转。
final class NativeLogBuffer {
  private let capacity: Int
  private var pending: [NativeLogEntry] = []
  private var delivery: ((NativeLogEntry) -> Void)?

  init(capacity: Int = 128) { self.capacity = max(1, capacity) }

  func log(_ level: Int64 = 800, _ category: String, _ message: String) {
    emit(NativeLogEntry(level: level, category: category, message: message))
  }

  func attach(_ delivery: @escaping (NativeLogEntry) -> Void) {
    self.delivery = delivery
    let entries = pending
    pending.removeAll()
    for entry in entries { emit(entry) }
  }

  func pauseAndRetain(_ entry: NativeLogEntry) {
    // 日志回调本身失败时只入队，避免递归调用已经失效的通道。
    delivery = nil
    emit(entry)
  }

  private func emit(_ entry: NativeLogEntry) {
    if let delivery = delivery { delivery(entry) }
    else {
      pending.append(entry)
      if pending.count > capacity { pending.removeFirst(pending.count - capacity) }
    }
  }
}

let nativeLogs = NativeLogBuffer()

#if FRULER_INTEGRATION_TEST
private enum NativeInputDiagnostics {
  static private(set) var recent: [String] = []
  static func record(_ message: String) {
    if recent.last == message { return }
    recent.append(message)
    if recent.count > 8 { recent.removeFirst(recent.count - 8) }
  }
}
#endif

class MainFlutterWindow: NSWindow {
  private var desktopBridge: FrulerDesktopBridge?
  private var historyRequested = false
  override func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
    // 隐藏后收回显示许可，避免搬移 Flutter 视图时 AppKit 自动带出历史窗口。
    if place == .out { historyRequested = false }
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
    guard FrulerInstance.acquire(logFailure: { message in
      nativeLogs.log(1000, "lifecycle", message)
      // 实例锁失败会阻止 Flutter 启动，此时仍需在系统日志中保留诊断。
      NSLog("fruler %@", message)
    }) else { NSApp.terminate(nil); return }
    nativeLogs.log(800, "lifecycle", "Native application launch started.")
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
  private let pinnedImages = PinnedImageManager()
  private var screenshotHost: CapturePanel?
  private var colorDialog: AnnotationColorDialog?
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
  private let recorder = ScreenRecorder()
  private var recordingTransition = false
  private var discardingRecording = false
  private var recordingTimer: Timer?
  private var recordingStartedAt: Date?
  private var recordingReturnApplication: NSRunningApplication?
  private var recordingTemporaryURL: URL?

  private var flutterInputView: NSView? {
    func inputView(_ view: NSView) -> NSView? {
      if view.acceptsFirstResponder { return view }
      for child in view.subviews { if let input = inputView(child) { return input } }
      return nil
    }
    return flutterController.flatMap { inputView($0.view) }
  }

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
          nativeLogs.log(1000, "desktop", "Native event callback failed: errorType=\(String(reflecting: type(of: error))).")
        }
      }
    }
    setupMenu()
    recorder.onFailure = { [weak self] error in
      guard let self = self else { return }
      self.recordingTransition = false
      self.cleanupRecording()
      let detail = self.recordingErrorMessage(error)
      nativeLogs.log(1000, "recording", "Screen recording failed: errorType=\(String(reflecting: type(of: error))).")
      self.sink?(["type": "recordingFailed", "message": detail])
      self.presentRecordingError(detail)
      self.restoreRecordingApplication()
    }
    setupHotkeys()
    nativeLogs.log(800, "desktop", "Desktop bridge installed.")
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
      if self.shortcuts.pinClipboard.matches(event) { self.emitPinAction("pinClipboard"); return nil }
      if self.shortcuts.togglePins.matches(event) { self.emitPinAction("togglePinnedImages"); return nil }
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
    if recordingTransition {
      DispatchQueue.main.async { NSApp.reply(toApplicationShouldTerminate: false) }
      return true
    }
    if recorder.isRecording {
      DispatchQueue.main.async { [weak self] in
        self?.stopRecording { outcome in
          if case .failure(let error) = outcome {
            self?.sink?(["type": "recordingFailed", "message": self?.recordingErrorMessage(error) ?? error.localizedDescription])
          }
          NSApp.reply(toApplicationShouldTerminate: (try? outcome.get()) != nil)
        }
      }
      return true
    }
    return false
  }

  #if FRULER_INTEGRATION_TEST
  private var integrationDriver: FlutterMethodChannel?
  private var cancelNextSave = false
  private var recordingSavePath: String?
  private var recordingRetryPaths: [String] = []
  private var recordingSaveFailureCount = 0
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
      case "recordingState":
        let temporaryFiles = (try? FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path)) ?? []
        result(["active": self.recorder.isRecording, "transitioning": self.recordingTransition,
          "saveFailureCount": self.recordingSaveFailureCount,
          "temporaryFileCount": temporaryFiles.filter {
            $0.hasPrefix("fruler-recording-") && ($0.hasSuffix(".mp4") || $0.contains(".mp4.sb-"))
          }.count])
      case "setRecordingSavePath":
        self.recordingSavePath = args["path"] as? String
        self.recordingRetryPaths = args["retryPaths"] as? [String] ?? []
        self.recordingSaveFailureCount = 0
        result(nil)
      case "recordingMetadata":
        guard let path = args["path"] as? String else { result(nil); return }
        let asset = AVURLAsset(url: URL(fileURLWithPath: path))
        Task { @MainActor in
          do {
            guard let track = try await asset.loadTracks(withMediaType: .video).first else { result(nil); return }
            let size = try await track.load(.naturalSize)
            let duration = try await asset.load(.duration)
            let fps = try await track.load(.nominalFrameRate)
            let formats = try await track.load(.formatDescriptions)
            let audio = try await asset.loadTracks(withMediaType: .audio)
            let code = formats.first.map { CMFormatDescriptionGetMediaSubType($0) } ?? 0
            let codec = String(bytes: [UInt8((code >> 24) & 255), UInt8((code >> 16) & 255), UInt8((code >> 8) & 255), UInt8(code & 255)], encoding: .ascii) ?? ""
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            let image = try await generator.image(at: CMTime(seconds: min(0.4, duration.seconds / 2), preferredTimescale: 600)).image
            var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
            guard let context = CGContext(data: &pixels, width: image.width, height: image.height,
              bitsPerComponent: 8, bytesPerRow: image.width * 4, space: colorSpace,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { result(nil); return }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            func rgb(_ y: Int) -> [Int] {
              let index = (y * image.width + image.width / 2) * 4
              return (0..<3).map { Int(pixels[index + $0]) }
            }
            result(["width": Int(size.width), "height": Int(size.height), "duration": duration.seconds,
              "codec": codec, "frameRate": Double(fps), "audioTracks": audio.count,
              "topRGB": rgb(image.height / 4), "bottomRGB": rgb(image.height * 3 / 4)])
          } catch { result(FlutterError(code: "test_recording_metadata", message: error.localizedDescription, details: nil)) }
        }
      case "pinState": result(self.pinnedImages.integrationState)
      case "pinClipboardFixture":
        let kind = args["kind"] as? String ?? "image"
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if kind == "image" {
          let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 80, pixelsHigh: 60,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 320, bitsPerPixel: 32)!
          for y in 0..<60 { for x in 0..<80 {
            let offset = y * 320 + x * 4
            rep.bitmapData![offset] = UInt8(x * 3)
            rep.bitmapData![offset + 1] = UInt8(y * 4)
            rep.bitmapData![offset + 2] = 120
            rep.bitmapData![offset + 3] = 255
          } }
          pasteboard.setData(rep.representation(using: .png, properties: [:])!, forType: .png)
        } else if kind == "text" || kind == "color" {
          pasteboard.setString(args["text"] as? String ?? (kind == "color" ? "#12AB34" : "fruler pinned text"), forType: .string)
        }
        result(nil)
      case "pinInput":
        let id = args["id"] as? Int
        guard let panel = self.pinnedImages.panels.first(where: { id == nil || $0.pinID == id }) else {
          result(FlutterError(code: "test_no_pin", message: "No pinned image", details: nil)); return
        }
        let view = panel.imageView
        let flags: NSEvent.ModifierFlags = (args["command"] as? Bool == true ? NSEvent.ModifierFlags.command : [])
          .union(args["shift"] as? Bool == true ? .shift : [])
        let point = view.convert(NSPoint(x: args["x"] as? Double ?? view.bounds.midX,
          y: args["y"] as? Double ?? view.bounds.midY), to: nil)
        switch args["action"] as? String {
        case "key":
          let code = args["keyCode"] as? UInt16 ?? 0
          let chars: [UInt16: String] = [8: "c", 1: "s", 13: "w", 18: "1", 19: "2", 20: "3", 21: "4", 29: "0", 25: "9", 24: "=", 27: "-"]
          guard let event = NSEvent.keyEvent(with: .keyDown, location: point, modifierFlags: flags,
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber,
            context: nil, characters: chars[code] ?? "", charactersIgnoringModifiers: chars[code] ?? "",
            isARepeat: false, keyCode: code) else { result(false); return }
          panel.makeKeyAndOrderFront(nil); panel.makeFirstResponder(view)
          panel.sendEvent(event)
        case "scroll":
          guard let cg = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1,
            wheel1: args["delta"] as? Int32 ?? 0, wheel2: 0, wheel3: 0) else { result(false); return }
          cg.flags = CGEventFlags(rawValue: UInt64(flags.rawValue))
          let screenPoint = panel.convertPoint(toScreen: point)
          cg.location = CGPoint(x: screenPoint.x, y: (NSScreen.screens.first?.frame.maxY ?? 0) - screenPoint.y)
          if let event = NSEvent(cgEvent: cg) { view.scrollWheel(with: event) }
        case "mouse":
          let button = args["button"] as? String ?? "primary"
          let phase = args["phase"] as? String ?? "down"
          let types: [String: NSEvent.EventType] = button == "middle"
            ? ["down": .otherMouseDown, "drag": .otherMouseDragged, "up": .otherMouseUp]
            : ["down": .leftMouseDown, "drag": .leftMouseDragged, "up": .leftMouseUp]
          guard let type = types[phase], var event = NSEvent.mouseEvent(with: type,
            location: point, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: panel.windowNumber, context: nil, eventNumber: 0,
            clickCount: args["clickCount"] as? Int ?? 1, pressure: 1) else { result(false); return }
          if button == "middle", let cg = event.cgEvent {
            cg.setIntegerValueField(.mouseEventButtonNumber, value: 2)
            if let adjusted = NSEvent(cgEvent: cg) { event = adjusted }
          }
          panel.sendEvent(event)
        case "menu":
          panel.integrationCancelNextSave = args["cancelSave"] as? Bool ?? false
          result(panel.performAction(args["name"] as? String ?? "")); return
        default: result(FlutterError(code: "test_invalid_pin_input", message: "Unknown pin input", details: nil)); return
        }
        result(nil)
      case "inputDiagnostics": result(NativeInputDiagnostics.recent)
      case "requestExit":
        result(nil)
        DispatchQueue.main.async { NSApp.terminate(nil) }
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
      case "clickMenu":
        let name = args["name"] as? String ?? ""
        guard let menu = self.statusItem?.menu,
              let index = menu.items.firstIndex(where: {
                ($0.representedObject as? String) == name || $0.identifier?.rawValue == name
              }) else { result(false); return }
        menu.performActionForItem(at: index)
        result(true)
      case "status":
        result(["panels":self.overlays.count,"active":self.session != nil,
          "applicationActive":NSApp.isActive,
          "permission":CGPreflightScreenCaptureAccess(),"bundleId":Bundle.main.bundleIdentifier ?? "",
          "mainVisible":self.mainWindow?.isVisible == true,"editing":self.screenshotHost != nil,
          "menu": self.statusItem?.menu?.items.map { entry -> [String: Any] in
            ["title": entry.title, "separator": entry.isSeparatorItem,
             "tool": entry.representedObject as? String ?? "", "key": entry.keyEquivalent,
             "hasImage": entry.image != nil]
          } ?? [],
          "statusItemCount":self.statusItem == nil ? 0 : 1,"accessory":NSApp.activationPolicy() == .accessory,
          "rulerViews":self.overlays.values.map { $0.overlay.integrationState },
          "windowNumber":self.screenshotHost?.windowNumber ?? self.overlays.values.first?.windowNumber ?? -1])
      case "colorPanelState":
        guard let dialog = self.colorDialog else { result(nil); return }
        result(["visible": dialog.panel.isVisible, "nativeClass": String(describing: type(of: dialog.panel)),
          "mode": dialog.panel.mode.rawValue, "showsAlpha": dialog.panel.showsAlpha,
          "color": AnnotationColorDialog.argb(dialog.panel.color) as Any? ?? NSNull(),
          "pickerCount": dialog.panel.toolbar?.items.count ?? 0,
          "aboveScreenshot": dialog.panel.level.rawValue > (self.screenshotHost?.level.rawValue ?? 0)])
      case "colorPanelSelect":
        guard let dialog = self.colorDialog, let color = args["color"] as? Int64 else {
          result(FlutterError(code:"test_no_color_panel",message:"No native color panel",details:nil));return
        }
        if let mode = args["mode"] as? Int, let pickerMode = NSColorPanel.Mode(rawValue: mode) {
          dialog.panel.mode = pickerMode
        }
        dialog.panel.color = AnnotationColorDialog.nsColor(color)
        result(nil)
      case "colorSampleExpected":
        result(UserDefaults.standard.object(forKey: "fruler.integration.expectedSample"))
      case "colorSampleInput":
        guard let dialog = self.colorDialog, let root = dialog.panel.contentView else {
          result(FlutterError(code:"test_no_color_panel",message:"No native color panel",details:nil));return
        }
        func findView(_ root: NSView, _ name: String) -> NSView? {
          if String(describing: type(of: root)) == name { return root }
          for child in root.subviews { if let found = findView(child, name) { return found } }
          return nil
        }
        guard let well = findView(root, "NSColorPanelColorWell"),
              let samples = findView(root, "NSColorPanelFavoritesList") else {
          result(FlutterError(code:"test_no_samples",message:"Native color sample views unavailable",details:nil));return
        }
        dialog.panel.makeKeyAndOrderFront(nil)
        root.layoutSubtreeIfNeeded()
        let source = well.convert(NSPoint(x: well.bounds.midX, y: well.bounds.midY), to: nil)
        let target = samples.convert(NSPoint(x: samples.bounds.minX + 8.5,
          y: samples.isFlipped ? samples.bounds.minY + 8.5 : samples.bounds.maxY - 8.5), to: nil)
        let drag = args["action"] as? String == "drag"
        if drag { UserDefaults.standard.set(AnnotationColorDialog.argb(dialog.panel.color), forKey: "fruler.integration.expectedSample") }
        let start = drag ? source : target
        func cursor(_ point: NSPoint) -> [Double] {
          let screen = dialog.panel.convertPoint(toScreen: point)
          return [screen.x, (NSScreen.screens.first?.frame.maxY ?? 0) - screen.y]
        }
        let token = UUID().uuidString
        let center = DistributedNotificationCenter.default()
        let replyName = Notification.Name("dev.fruler.integration.colorSampleReply.\(token)")
        final class InputReply {
          var observer: NSObjectProtocol?
          var completed = false
        }
        let pending = InputReply()
        pending.observer = center.addObserver(forName: replyName, object: nil, queue: .main) { note in
          guard !pending.completed else { return }
          pending.completed = true
          if let observer = pending.observer { center.removeObserver(observer) }
          pending.observer = nil
          if note.object as? String == "ok" { result(nil) }
          else { result(FlutterError(code:"test_sample_input_failed",message:note.object as? String,details:nil)) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
          guard !pending.completed else { return }
          pending.completed = true
          if let observer = pending.observer { center.removeObserver(observer) }
          pending.observer = nil
          result(FlutterError(code:"test_sample_fixture_timeout",message:"Native input fixture did not reply",details:nil))
        }
        let payload: [String: Any] = ["start": cursor(start), "target": cursor(target), "drag": drag, "token": token]
        let bytes = try! JSONSerialization.data(withJSONObject: payload)
        center.postNotificationName(Notification.Name("dev.fruler.integration.colorSampleInput"),
          object: String(data: bytes, encoding: .utf8), userInfo: nil, deliverImmediately: true)
      case "colorPanelAction":
        guard let dialog = self.colorDialog else {
          result(FlutterError(code:"test_no_color_panel",message:"No native color panel",details:nil));return
        }
        switch args["action"] as? String {
        case "confirm": dialog.confirmButton.performClick(nil)
        case "cancel": dialog.cancelButton.performClick(nil)
        case "close": dialog.panel.performClose(nil)
        default: result(FlutterError(code:"test_invalid_action",message:"Unknown color action",details:nil));return
        }
        result(nil)
      case "setRulerTolerance":
        guard let panel = self.overlays.values.first(where: { $0.isKeyWindow }) else { result(false); return }
        result(panel.overlay.integrationSetTolerance(args["value"] as? String ?? ""))
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
        let button = args["button"] as? String ?? "primary"
        let mouseTypes: [String: NSEvent.EventType] = button == "secondary"
          ? ["down": .rightMouseDown, "drag": .rightMouseDragged, "up": .rightMouseUp, "move": .mouseMoved]
          : button == "middle"
          ? ["down": .otherMouseDown, "drag": .otherMouseDragged, "up": .otherMouseUp, "move": .mouseMoved]
          : ["down": .leftMouseDown, "drag": .leftMouseDragged, "up": .leftMouseUp, "move": .mouseMoved]
        guard let id=args["displayId"] as? UInt32, let panel=self.overlays[id],
          let x=args["x"] as? Double, let y=args["y"] as? Double, let phase=args["phase"] as? String,
          let type=mouseTypes[phase] else {
          result(FlutterError(code:"test_no_panel",message:"No native panel",details:nil));return
        }
        // 测试驱动接管浮层鼠标，避免 CGWarpMouseCursorPosition 随后生成的
        // 系统悬停事件覆盖已投递的定位、框选或拖动事件。
        for overlay in self.overlays.values { overlay.overlay.integrationDriving = true }
        let before = "active=\(NSApp.isActive),key=\(panel.isKeyWindow)"
        let firstMouseBefore = panel.overlay.integrationFirstMouseCount
        panel.makeKeyAndOrderFront(nil)
        panel.layoutIfNeeded()
        let point=panel.overlay.convert(NSPoint(x:x,y:y),to:nil)
        if args["warp"] as? Bool == true {
          let screenPoint = panel.convertPoint(toScreen: point)
          CGWarpMouseCursorPosition(CGPoint(x: screenPoint.x,
            y: (NSScreen.screens.first?.frame.maxY ?? 0) - screenPoint.y))
        }
        guard var event=NSEvent.mouseEvent(with:type,location:point,modifierFlags:[],
          timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:panel.windowNumber,
          context:nil,eventNumber:CaptureOverlayView.integrationEventNumber,clickCount:1,pressure:1) else {result(nil);return}
        if button == "secondary" || button == "middle" {
          // Cocoa 工厂即便创建右/中键事件也默认使用 0 号键，需还原真实按键编号。
          guard let cg = event.cgEvent else { result(false); return }
          cg.setIntegerValueField(.mouseEventButtonNumber, value: button == "secondary" ? 1 : 2)
          cg.setIntegerValueField(.eventSourceUserData, value: Int64(CaptureOverlayView.integrationEventNumber))
          guard let adjusted = NSEvent(cgEvent: cg) else { result(false); return }
          event = adjusted
        }
        let hit = panel.contentView?.hitTest(point)
        let target = hit.map { NSStringFromClass(Swift.type(of: $0)) } ?? "nil"
        panel.sendEvent(event)
        NativeInputDiagnostics.record("driver \(phase) session=\(self.session ?? -1) before[\(before)] after[active=\(NSApp.isActive),key=\(panel.isKeyWindow)] hit=\(target) firstMouse=\(firstMouseBefore)->\(panel.overlay.integrationFirstMouseCount) phases=\(panel.overlay.integrationInputPhases.joined(separator: ","))")
        result(nil)
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
        let keyCharacters: [UInt16:String] = [51:"\u{7f}",117:"\u{f728}",6:"z",16:"y",8:"c",46:"m",17:"t"]
        guard let panel=self.overlays.values.first(where:{$0.isKeyWindow}) ?? self.overlays.values.first,
          let code=args["keyCode"] as? UInt16,
          let event=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:
            (args["command"] as? Bool == true ? NSEvent.ModifierFlags.command.union(NSEvent.ModifierFlags(rawValue: 0x8)) : []).union(
              args["shift"] as? Bool == true ? NSEvent.ModifierFlags.shift.union(NSEvent.ModifierFlags(rawValue: 0x2)) : []),
            timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:panel.windowNumber,
            context:nil,characters:keyCharacters[code] ?? "",charactersIgnoringModifiers:keyCharacters[code] ?? "",isARepeat:false,keyCode:code) else {
          result(FlutterError(code:"test_no_panel",message:"No native panel",details:nil));return
        }
        if let host = self.screenshotHost {
          host.makeKeyAndOrderFront(nil)
          // Keep Flutter's text input responder when editing text.
          if host.firstResponder === host.overlay || host.firstResponder === self.flutterController?.view {
            host.makeFirstResponder(self.flutterInputView)
          }
          // Cocoa 实际输入先发送修饰键状态变化，再发送主键；只设主键flags不足以更新Flutter状态。
          // 同时保留 NX_DEVICELCMDKEYMASK / NX_DEVICELSHIFTKEYMASK，Flutter按左右设备位同步修饰键。
          let modifiers: [(NSEvent.ModifierFlags, UInt16)] = [
            (.command.union(NSEvent.ModifierFlags(rawValue: 0x8)), 55),
            (.shift.union(NSEvent.ModifierFlags(rawValue: 0x2)), 56)
          ].filter { event.modifierFlags.contains($0.0) }
          func sendModifiers(_ flags: NSEvent.ModifierFlags, code: UInt16) {
            if let change = NSEvent.keyEvent(with: .flagsChanged, location: .zero,
              modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
              windowNumber: host.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "",
              isARepeat: false, keyCode: code) { NSApp.sendEvent(change) }
          }
          var pressed: NSEvent.ModifierFlags = []
          for (flag, code) in modifiers { pressed.insert(flag); sendModifiers(pressed, code: code) }
          NSApp.sendEvent(event)
          if let up = NSEvent.keyEvent(with: .keyUp, location: .zero,
            modifierFlags: event.modifierFlags, timestamp: event.timestamp,
            windowNumber: host.windowNumber, context: nil,
            characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code) {
            NSApp.sendEvent(up)
          }
          for (flag, code) in modifiers.reversed() { pressed.remove(flag); sendModifiers(pressed, code: code) }
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

  func configureLocale(languageCode: String, completion: @escaping (Result<Void, Error>) -> Void) {
    guard languageCode == "en" || languageCode == "zh" else {
      completion(.failure(PigeonError(code: "locale_invalid", message: NativeStrings.text("error.locale_invalid"), details: nil)))
      return
    }
    NativeStrings.configure(languageCode)
    NativeStrings.localizeMenu(NSApp.mainMenu)
    setupMenu()
    for panel in overlays.values { panel.overlay.refreshLocalization() }
    colorDialog?.refreshLocalization()
    pinnedImages.refreshLocale()
    nativeLogs.log(800, "desktop", "Locale configured: language=\(languageCode).")
    completion(.success(()))
  }

  func initialize(completion: @escaping (Result<NativeStatus, Error>) -> Void) {
    nativeLogs.attach { [weak self] entry in
      guard let self = self else { nativeLogs.pauseAndRetain(entry); return }
      self.callbacks.onLog(entry: entry) { response in
        if case .failure = response {
          nativeLogs.pauseAndRetain(entry)
          NSLog("fruler native log delivery failed; buffered for retry")
        }
      }
    }
    let permission = CGPreflightScreenCaptureAccess()
    nativeLogs.log(800, "desktop", "Desktop initialized: permission=\(permission), shortcuts=\(hasShortcuts).")
    completion(.success(NativeStatus(permission: permission, shortcuts: hasShortcuts)))
  }

  func configureShortcuts(bindings: NativeBindings, completion: @escaping (Result<Bool, Error>) -> Void) {
    let args: [String: Any] = bindings.local
    guard let requested = NativeShortcutBindings(args), requested.isValid else {
      nativeLogs.log(900, "shortcuts", "Shortcut configuration rejected: invalid binding.")
      completion(.failure(PigeonError(code: "shortcut_invalid", message: NativeStrings.text("error.shortcut_invalid"), details: nil)))
      return
    }
    if requested == shortcuts && (hasShortcuts || shortcutRecording) { completion(.success(true)); return }
    let previous = shortcuts
    let hadShortcuts = hasShortcuts
    unregisterHotkeys()
    if shortcutRecording || registerHotkeys(requested) {
      shortcuts = requested
      updateMenuShortcuts()
      nativeLogs.log(800, "shortcuts", "Shortcut configuration completed.")
      completion(.success(true))
    } else {
      if hadShortcuts { _ = registerHotkeys(previous) }
      updateMenuShortcuts()
      nativeLogs.log(900, "shortcuts", "Shortcut configuration failed: conflict, restored=\(hasShortcuts).")
      completion(.failure(PigeonError(code: "shortcut_conflict", message: NativeStrings.text("error.shortcut_conflict"), details: ["shortcuts": hasShortcuts])))
    }
  }

  func setShortcutRecording(recording: Bool, completion: @escaping (Result<Bool, Error>) -> Void) {
    nativeLogs.log(800, "shortcuts", "Shortcut recording changed: recording=\(recording).")
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

  func pickAnnotationColor(initialColor: Int64, completion: @escaping (Result<Int64?, Error>) -> Void) {
    guard initialColor >= 0, initialColor <= 0xFFFFFFFF else {
      completion(.failure(PigeonError(code: "invalid_color", message: NativeStrings.text("error.invalid_color"), details: nil))); return
    }
    guard let host = screenshotHost, let captureID = session, colorDialog == nil else {
      completion(.failure(PigeonError(code: "invalid_state", message: NativeStrings.text("error.color_unavailable"), details: nil))); return
    }
    let dialog = AnnotationColorDialog(initialColor: initialColor) { [weak self] color in
      guard let self = self else { completion(.success(nil)); return }
      self.colorDialog = nil
      if self.session == captureID { self.screenshotHost?.makeKeyAndOrderFront(nil) }
      completion(.success(color))
    }
    colorDialog = dialog
    dialog.present(relativeTo: host)
  }

  func requestPermission(completion: @escaping (Result<Bool, Error>) -> Void) {
    let granted = CGRequestScreenCaptureAccess()
    nativeLogs.log(800, "desktop", "Screen permission requested: granted=\(granted).")
    completion(.success(granted))
  }

  func showMainWindow(completion: @escaping (Result<Void, Error>) -> Void) {
    nativeLogs.log(800, "desktop", "Main window requested.")
    presentMainWindow(); completion(.success(()))
  }

  func openPrivacySettings(completion: @escaping (Result<Void, Error>) -> Void) {
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
      NSWorkspace.shared.open(url)
    }
    completion(.success(()))
  }

  func loadState(completion: @escaping (Result<String?, Error>) -> Void) {
    let saved = UserDefaults.standard.string(forKey: stateKey)
    nativeLogs.log(800, "storage", "State loaded: present=\(saved != nil).")
    completion(.success(saved))
  }

  func saveState(json: String, completion: @escaping (Result<Void, Error>) -> Void) {
    UserDefaults.standard.set(json, forKey: stateKey)
    nativeLogs.log(500, "storage", "State saved.")
    completion(.success(()))
  }

  func replyToQuit(allow: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
    NSApp.reply(toApplicationShouldTerminate:allow)
    completion(.success(()))
  }

  func exportImage(png: FlutterStandardTypedData, save: Bool, completion: @escaping (Result<Bool, Error>) -> Void) {
    let bytes = png
    nativeLogs.log(800, "export", "Image export requested: save=\(save).")
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
      guard panel.runModal() == .OK, let url = panel.url else {
        nativeLogs.log(800, "export", "File export cancelled.")
        completion(.success(false)); return
      }
      do {
        try bytes.data.write(to:url,options:.atomic)
        nativeLogs.log(800, "export", "Image file export completed.")
        completion(.success(true))
      } catch {
        nativeLogs.log(1000, "export", "Image file export failed: errorType=\(String(reflecting: type(of: error))).")
        completion(.failure(PigeonError(code:"image_export_failed",message:NativeStrings.text("error.image_export", error.localizedDescription),details:nil)))
      }
    } else {
      NSPasteboard.general.clearContents()
      if NSPasteboard.general.setData(bytes.data,forType:.png) {
        nativeLogs.log(800, "export", "Image clipboard write completed.")
        completion(.success(true))
      } else {
        nativeLogs.log(1000, "export", "Image clipboard write failed.")
        completion(.failure(PigeonError(code:"clipboard_failed",message:NativeStrings.text("error.clipboard_image"),details:nil)))
      }
    }
  }

  func pinImage(png: FlutterStandardTypedData, sessionId: Int64?, displayId: Int64?, rect: PixelBounds?,
    completion: @escaping (Result<Void, Error>) -> Void) {
    do {
      var size: NSSize?, center: NSPoint?
      if let id = sessionId {
        guard Int(id) == session, let displayId = displayId,
          let display = UInt32(exactly: displayId), let panel = overlays[display], let rect = rect else {
          throw PinImageError.invalidImage
        }
        let snapshot = panel.overlay.snapshot
        guard rect.left >= 0, rect.top >= 0, rect.right <= snapshot.width,
          rect.bottom <= snapshot.height, rect.right > rect.left, rect.bottom > rect.top else {
          throw PinImageError.invalidImage
        }
        let scaleX = snapshot.frame.width / CGFloat(snapshot.width)
        let scaleY = snapshot.frame.height / CGFloat(snapshot.height)
        size = NSSize(width: CGFloat(rect.right - rect.left) * scaleX,
          height: CGFloat(rect.bottom - rect.top) * scaleY)
        center = NSPoint(x: snapshot.frame.minX + CGFloat(rect.left + rect.right) / 2 * scaleX,
          y: snapshot.frame.maxY - CGFloat(rect.top + rect.bottom) / 2 * scaleY)
      } else if displayId != nil || rect != nil { throw PinImageError.invalidImage }
      try pinnedImages.pin(png: png.data, logicalSize: size, center: center)
      completion(.success(()))
    } catch { completion(.failure(PigeonError(code: "pin_failed", message: error.localizedDescription, details: nil))) }
  }

  func pinClipboard(completion: @escaping (Result<Void, Error>) -> Void) {
    guard session == nil, !preparing else {
      completion(.failure(PigeonError(code: "capture_busy", message: NativeStrings.text("error.capture_busy"), details: nil))); return
    }
    do {
      try pinnedImages.pinClipboard()
      completion(.success(()))
    } catch { completion(.failure(PigeonError(code: "pin_failed", message: error.localizedDescription, details: nil))) }
  }

  func togglePinnedImages(completion: @escaping (Result<Void, Error>) -> Void) {
    pinnedImages.toggleVisibility()
    completion(.success(()))
  }

  func closePinnedImages(completion: @escaping (Result<Void, Error>) -> Void) {
    pinnedImages.closeAll()
    completion(.success(()))
  }

  func openPaletteFile(completion: @escaping (Result<String?, Error>) -> Void) {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.json]
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    NSApp.activate(ignoringOtherApps: true)
    guard panel.runModal() == .OK, let url = panel.url else {
      nativeLogs.log(800, "storage", "Palette import cancelled.")
      completion(.success(nil)); return
    }
    do {
      let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
      guard size <= 2 * 1024 * 1024 else {
        completion(.failure(PigeonError(code: "import_failed", message: NativeStrings.text("error.import_size"), details: nil))); return
      }
      let text = try String(contentsOf: url, encoding: .utf8)
      guard text.utf8.count <= 2 * 1024 * 1024 else {
        completion(.failure(PigeonError(code: "import_failed", message: NativeStrings.text("error.import_size"), details: nil))); return
      }
      nativeLogs.log(800, "storage", "Palette import read completed.")
      completion(.success(text))
    } catch {
      nativeLogs.log(1000, "storage", "Palette import read failed: errorType=\(String(reflecting: type(of: error))).")
      completion(.failure(PigeonError(code: "import_failed", message: NativeStrings.text("error.palette_import", error.localizedDescription), details: nil)))
    }
  }

  func saveTextFile(filename: String, text: String, completion: @escaping (Result<Bool, Error>) -> Void) {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = filename
    panel.allowedContentTypes = [UTType(filenameExtension: (filename as NSString).pathExtension) ?? .plainText]
    panel.canCreateDirectories = true
    NSApp.activate(ignoringOtherApps: true)
    guard panel.runModal() == .OK, let url = panel.url else {
      nativeLogs.log(800, "export", "File export cancelled.")
      completion(.success(false)); return
    }
    do {
      try Data(text.utf8).write(to: url, options: .atomic)
      nativeLogs.log(800, "export", "Text file export completed.")
      completion(.success(true))
    } catch {
      nativeLogs.log(1000, "export", "File export failed: errorType=\(String(reflecting: type(of: error))).")
      completion(.failure(PigeonError(code: "export_failed", message: NativeStrings.text("error.file_export", error.localizedDescription), details: nil)))
    }
  }

  func exportAnnotations(sessionId: Int64, displayId: Int64, annotations: [MeasurementPin], save: Bool, completion: @escaping (Result<Bool, Error>) -> Void) {
    let id = Int(sessionId)
    guard id == session, let display = UInt32(exactly: displayId),
          let overlay = overlays[display]?.overlay,
          let png = AnnotationRenderer.png(image: overlay.snapshot.image, annotations: annotations.map { $0.local }) else {
      completion(.failure(PigeonError(code: "invalid_export", message: NativeStrings.text("error.invalid_export"), details: nil))); return
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
      guard panel.runModal() == .OK, let url = panel.url else {
        nativeLogs.log(800, "export", "File export cancelled.")
        completion(.success(false)); return
      }
      do {
        try png.write(to: url, options: .atomic)
        nativeLogs.log(800, "export", "Measurement image file export completed.")
        completion(.success(true))
      } catch {
        nativeLogs.log(1000, "export", "File export failed: errorType=\(String(reflecting: type(of: error))).")
        completion(.failure(PigeonError(code: "export_failed", message: NativeStrings.text("error.file_export", error.localizedDescription), details: nil)))
      }
    } else {
      NSPasteboard.general.clearContents()
      if NSPasteboard.general.setData(png, forType: .png) {
        nativeLogs.log(800, "export", "Measurement image clipboard write completed.")
        completion(.success(true))
      } else {
        nativeLogs.log(1000, "export", "Measurement image clipboard write failed.")
        completion(.failure(PigeonError(code: "clipboard_failed", message: NativeStrings.text("error.clipboard_image"), details: nil)))
      }
    }
  }

  func begin(tool: CaptureTool, completion: @escaping (Result<CaptureReply, Error>) -> Void) {
    nativeLogs.log(800, "capture", "Capture requested: tool=\(tool.name).")
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
      completion(.failure(PigeonError(code:"capture_cancelled",message:NativeStrings.text("error.capture_ended"),details:nil))); return
    }
    for overlay in overlays.values { overlay.overlay.setScreenshotEditing(true); overlay.overlay.releaseCursor() }
    mainWindow?.contentViewController = nil
    controller.backgroundColor = .clear
    panel.isOpaque = false
    controller.view.frame = panel.overlay.bounds
    controller.view.autoresizingMask = [.width,.height]
    panel.overlay.addSubview(controller.view)
    nativeLogs.log(800, "capture", "Screenshot editor attached: session=\(id).")
    screenshotHost = panel
    panel.makeKeyAndOrderFront(nil)
    panel.makeFirstResponder(flutterInputView)
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
    nativeLogs.log(800, "capture", "Capture finish requested: session=\(sessionId).")
    if Int(sessionId) == session { closeSession() }
    completion(.success(()))
  }

  func startRecording(sessionId: Int64, displayId: Int64, rect: PixelBounds,
    options: RecordingConfiguration, completion: @escaping (Result<Void, Error>) -> Void) {
    guard !recordingTransition, !recorder.busy, Int(sessionId) == session,
      let display = UInt32(exactly: displayId), let snapshot = overlays[display]?.overlay.snapshot,
      overlays[display]?.overlay.isRecordingSelection == true,
      rect.left >= 0, rect.top >= 0, rect.right <= snapshot.width, rect.bottom <= snapshot.height,
      rect.right > rect.left, rect.bottom > rect.top else {
      completion(.failure(PigeonError(code: "recording_region", message: NativeStrings.text("recording.invalid_region"), details: nil))); return
    }
    do {
      let configuration = try ScreenRecordingOptions(data: ["codec": options.codec,
        "frameRate": Int(options.frameRate), "quality": options.quality, "resolution": options.resolution,
        "showCursor": options.showCursor, "systemAudio": options.systemAudio])
      let region = CGRect(x: CGFloat(rect.left) * snapshot.frame.width / CGFloat(snapshot.width),
        y: CGFloat(rect.top) * snapshot.frame.height / CGFloat(snapshot.height),
        width: CGFloat(rect.right - rect.left) * snapshot.frame.width / CGFloat(snapshot.width),
        height: CGFloat(rect.bottom - rect.top) * snapshot.frame.height / CGFloat(snapshot.height))
      recordingTransition = true
      recordingReturnApplication = previousApplication
      // 先移除冻结快照与选区，再开始实时采集；不将浮层写进视频。
      closeSession()
      let url = FileManager.default.temporaryDirectory.appendingPathComponent("fruler-recording-\(UUID().uuidString).mp4")
      recordingTemporaryURL = url
      recorder.start(displayID: display, region: region, options: configuration, outputURL: url) { [weak self] outcome in
        guard let self = self else { completion(outcome); return }
        self.recordingTransition = false
        switch outcome {
        case .success:
          nativeLogs.log(800, "recording", "Screen recording started: codec=\(options.codec), fps=\(options.frameRate), resolution=\(options.resolution), audio=\(options.systemAudio).")
          self.recordingStartedAt = Date()
          self.recordingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.updateRecordingStatus() }
          self.setupMenu()
          self.updateRecordingStatus()
          completion(.success(()))
        case .failure(let error):
          self.cleanupRecording()
          let detail = self.recordingErrorMessage(error)
          completion(.failure(PigeonError(code: "recording_failed", message: detail, details: nil)))
          if !self.discardingRecording {
            self.presentRecordingError(detail)
            self.restoreRecordingApplication()
          }
        }
      }
    } catch {
      completion(.failure(PigeonError(code: "recording_options", message: recordingErrorMessage(error), details: nil)))
    }
  }

  func stopRecording(completion: @escaping (Result<Bool, Error>) -> Void) {
    guard recorder.isRecording, !recordingTransition else {
      completion(.failure(PigeonError(code: "recording_busy", message: NativeStrings.text("error.capture_busy"), details: nil))); return
    }
    recordingTransition = true
    recordingTimer?.invalidate(); recordingTimer = nil
    recorder.stop { [weak self] outcome in
      guard let self = self else { return }
      defer {
        self.recordingTransition = false
        self.cleanupRecording()
        self.restoreRecordingApplication()
      }
      switch outcome {
      case .failure(let error):
        let detail = self.recordingErrorMessage(error)
        completion(.failure(PigeonError(code: "recording_failed", message: detail, details: nil)))
        if !self.discardingRecording { self.presentRecordingError(detail) }
      case .success(let recording):
        while true {
          let panel = NSSavePanel()
          panel.nameFieldStringValue = "fruler-recording-\(Int(Date().timeIntervalSince1970)).mp4"
          panel.allowedContentTypes = [.mpeg4Movie]
          panel.canCreateDirectories = true
          panel.title = NativeStrings.text("recording.save")
          var destination: URL?
          #if FRULER_INTEGRATION_TEST
          if let path = self.recordingSavePath {
            destination = URL(fileURLWithPath: path); self.recordingSavePath = nil
          } else if self.cancelNextSave { self.cancelNextSave = false }
          else {
            NSApp.activate(ignoringOtherApps: true)
            if panel.runModal() == .OK { destination = panel.url }
          }
          #else
          NSApp.activate(ignoringOtherApps: true)
          if panel.runModal() == .OK { destination = panel.url }
          #endif
          guard let destination = destination else { completion(.success(false)); return }
          do {
            // 只在完整编码结束后替换目标文件，写入失败不破坏已有视频。
            if FileManager.default.fileExists(atPath: destination.path) {
              _ = try FileManager.default.replaceItemAt(destination, withItemAt: recording.url)
            } else { try FileManager.default.moveItem(at: recording.url, to: destination) }
            nativeLogs.log(800, "recording", "Screen recording saved: width=\(recording.width), height=\(recording.height).")
            completion(.success(true))
            return
          } catch {
            nativeLogs.log(1000, "recording", "Recording file save failed: errorType=\(String(reflecting: type(of: error))).")
            #if FRULER_INTEGRATION_TEST
            self.recordingSaveFailureCount += 1
            #endif
            let alert = NSAlert()
            alert.messageText = NativeStrings.text("recording.save_failed")
            alert.informativeText = NativeStrings.text("error.file_export", error.localizedDescription)
            alert.addButton(withTitle: NativeStrings.text("recording.retry"))
            alert.addButton(withTitle: NativeStrings.text("recording.discard"))
            NSApp.activate(ignoringOtherApps: true)
            #if FRULER_INTEGRATION_TEST
            if !self.recordingRetryPaths.isEmpty {
              self.recordingSavePath = self.recordingRetryPaths.removeFirst()
              // stop 回调位于主队列，模态期间主队列不可重入；用模态 run loop 投递真实按钮点击。
              let retry = Timer(timeInterval: 0, repeats: false) { _ in alert.buttons.first?.performClick(nil) }
              RunLoop.main.add(retry, forMode: .modalPanel)
            }
            #endif
            if alert.runModal() != .alertFirstButtonReturn { completion(.success(false)); return }
          }
        }
      }
    }
  }

  private func cleanupRecording() {
    recordingTimer?.invalidate(); recordingTimer = nil
    recordingStartedAt = nil
    if let url = recordingTemporaryURL { try? FileManager.default.removeItem(at: url) }
    recordingTemporaryURL = nil
    statusItem?.button?.title = ""
    setupMenu()
  }

  private func recordingErrorMessage(_ error: Error) -> String {
    if let error = error as? ScreenRecordingError { return NativeStrings.text("error.\(error.code)") }
    if let error = error as? PigeonError { return error.message ?? NativeStrings.text("error.recording_write") }
    return error.localizedDescription
  }

  private func presentRecordingError(_ detail: String) {
    NSApp.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.messageText = NativeStrings.text("recording.failed")
    alert.informativeText = NativeStrings.text("error.recording", detail)
    alert.runModal()
  }

  private func restoreRecordingApplication() {
    if let application = recordingReturnApplication, !application.isTerminated {
      application.activate(options: [])
    } else if mainWindow?.isVisible != true { NSApp.hide(nil) }
    recordingReturnApplication = nil
  }

  func cancelRecording(completion: @escaping (Result<Void, Error>) -> Void) {
    discardingRecording = true
    recorder.cancel()
    discardingRecording = false
    recordingTransition = false
    cleanupRecording()
    recordingReturnApplication = nil
    completion(.success(()))
  }

  private func updateRecordingStatus() {
    guard let started = recordingStartedAt else { return }
    let seconds = Int(Date().timeIntervalSince(started))
    statusItem?.button?.title = String(format: " ● %02d:%02d", seconds / 60, seconds % 60)
  }

  private func capture(tool: String, completion: @escaping (Result<CaptureReply, Error>) -> Void) {
    guard !preparing && session == nil && !recorder.busy && !recordingTransition else {
      completion(.failure(PigeonError(code: "capture_busy", message: NativeStrings.text("error.capture_busy"), details: nil)))
      return
    }
    guard CGPreflightScreenCaptureAccess() else {
      nativeLogs.log(900, "capture", "Capture rejected: screen permission required.")
      completion(.failure(PigeonError(code: "screen_permission", message: NativeStrings.text("error.screen_permission"), details: nil)))
      return
    }
    guard sink != nil else {
      completion(.failure(PigeonError(code: "no_listener", message: NativeStrings.text("error.no_listener"), details: nil)))
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
      var captureStage = "compositor_wait"
      do {
        // Allow the compositor to remove the dashboard before taking snapshots.
        try await Task.sleep(nanoseconds: 160_000_000)
        try Task.checkCancellation()
        captureStage = "shareable_content"
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let screens = NSScreen.screens
        nativeLogs.log(800, "capture", "Capture displays discovered: session=\(id), screens=\(screens.count), shareableDisplays=\(content.displays.count).")
        let ownApps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        // 贴图属于屏幕内容；仅把可见贴图从本应用排除规则中重新纳入。
        let visiblePins = Set(self.pinnedImages.panels.filter { $0.isVisible && !$0.isPinnedHidden }.map { $0.windowNumber })
        let pinnedWindows = content.windows.filter { visiblePins.contains(Int($0.windowID)) }
        var captures: [DisplaySnapshot] = []
        for screen in screens {
          try Task.checkCancellation()
          captureStage = "display_match"
          guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                let display = content.displays.first(where: { $0.displayID == number.uint32Value }) else { continue }
          let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: pinnedWindows)
          let config = SCStreamConfiguration()
          // A scaled display's backing pixels can differ from its native panel resolution.
          config.width = Int((screen.frame.width * screen.backingScaleFactor).rounded())
          config.height = Int((screen.frame.height * screen.backingScaleFactor).rounded())
          config.showsCursor = false
          config.pixelFormat = kCVPixelFormatType_32BGRA
          config.colorSpaceName = CGColorSpace.sRGB
          captureStage = "screen_image"
          let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
          captureStage = "snapshot_normalization"
          captures.append(try DisplaySnapshot(screen: screen, displayID: display.displayID, image: image))
        }
        try Task.checkCancellation()
        captureStage = "display_validation"
        guard self.session == id, !captures.isEmpty else { throw CaptureFailure.unavailable }
        captureStage = "panel_setup"
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
        nativeLogs.log(800, "capture", "Capture prepared: session=\(id), tool=\(tool), displays=\(captures.count).")
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
        nativeLogs.log(cancelled ? 800 : 1000, "capture", "Capture failed: session=\(id), stage=\(captureStage), cancelled=\(cancelled), errorType=\(String(reflecting: type(of: error))).")
        if self.session == id { self.closeSession() }
        completion(.failure(PigeonError(code: cancelled ? "capture_cancelled" : "capture_failed",
          message: cancelled ? NativeStrings.text("error.capture_cancelled") : NativeStrings.text("error.capture_failed", error.localizedDescription), details: nil)))
      }
    }
  }

  private func cancelSession() {
    guard let id = session else { return }
    nativeLogs.log(800, "capture", "Capture cancelled: session=\(id).")
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
    nativeLogs.log(800, "capture", "Capture panels closed: session=\(session ?? -1), panels=\(overlays.count).")
    session = nil
    colorDialog?.cancel(nil)
    colorDialog = nil
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
    } else if !pinnedImages.panels.contains(where: { !$0.isPinnedHidden }) { NSApp.hide(nil) }
    pinnedImages.showVisible()
    previousApplication = nil
  }

  private func setupMenu() {
    let item = statusItem ?? NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    item.length = recorder.isRecording ? NSStatusItem.variableLength : NSStatusItem.squareLength
    item.button?.image = NSImage(systemSymbolName: "ruler", accessibilityDescription: "fruler")
    item.button?.contentTintColor = recorder.isRecording ? .systemRed : nil
    let menu = NSMenu()
    // 常用工具独立成组，快捷键靠右；管理入口和退出另起分组。
    for (title, tool, key, symbol) in [
      (NativeStrings.text("tool.screenshot"), "screenshot", "X", "viewfinder"),
      (NativeStrings.text(recorder.isRecording ? "recording.stop" : "tool.recording"), recorder.isRecording ? "stopRecording" : "recording", "", "record.circle"),
      (NativeStrings.text("tool.picker"), "picker", "C", "eyedropper"),
      (NativeStrings.text("tool.ruler"), "rectangle", "R", "ruler")
    ] {
      let entry = NSMenuItem(title: title, action: #selector(activateTool(_:)), keyEquivalent: key)
      entry.target = self
      entry.representedObject = tool
      entry.keyEquivalentModifierMask = [.command, .shift]
      entry.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
      entry.image?.size = NSSize(width: 16, height: 16)
      toolMenuItems[tool] = entry
      menu.addItem(entry)
    }
    menu.addItem(.separator())
    for (key, action, symbol) in [("pin.clipboard", "pinClipboard", "pin"),
      ("pin.toggle", "togglePinnedImages", "eye"), ("pin.close_all", "closePinnedImages", "xmark.rectangle")] {
      let entry = menu.addItem(withTitle: NativeStrings.text(key), action: #selector(pinMenuAction(_:)), keyEquivalent: "")
      entry.target = self
      entry.identifier = NSUserInterfaceItemIdentifier(action)
      entry.image = NSImage(systemSymbolName: symbol, accessibilityDescription: entry.title)
      entry.image?.size = NSSize(width: 16, height: 16)
      if action != "closePinnedImages" { toolMenuItems[action] = entry }
    }
    menu.addItem(.separator())
    let history = menu.addItem(withTitle: NativeStrings.text("menu.history"), action: #selector(openHistory), keyEquivalent: "")
    history.target = self
    history.identifier = NSUserInterfaceItemIdentifier("history")
    let settings = menu.addItem(withTitle: NativeStrings.text("menu.settings"), action: #selector(openSettings), keyEquivalent: ",")
    settings.target = self
    settings.identifier = NSUserInterfaceItemIdentifier("settings")
    menu.addItem(.separator())
    let quit = menu.addItem(withTitle: NativeStrings.text("menu.quit"), action: #selector(quitApp), keyEquivalent: "q")
    quit.target = self
    item.menu = menu
    statusItem = item
    updateMenuShortcuts()
  }

  @objc private func pinMenuAction(_ sender: NSMenuItem) {
    if let action = sender.identifier?.rawValue { emitPinAction(action) }
  }

  private func emitPinAction(_ action: String) {
    guard !shortcutRecording, session == nil, !preparing else { NSSound.beep(); return }
    sink?(["type": action])
  }

  @objc private func activateTool(_ sender: NSMenuItem) {
    guard let tool = sender.representedObject as? String else { return }
    emitActivation(tool)
  }
  private func emitActivation(_ tool: String) {
    if tool == "stopRecording" { sink?(["type": "stopRecording"]); return }
    guard !shortcutRecording else { return }
    guard session == nil, !preparing, !recorder.busy, !recordingTransition else { NSSound.beep(); return }
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
  @objc private func openHistory() {
    presentMainWindow()
    sink?(["type": "showHistory"])
  }
  @objc private func openSettings() {
    presentMainWindow()
    sink?(["type": "showSettings"])
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
      switch key.id {
      case 1: bridge.emitActivation("picker")
      case 2: bridge.emitActivation("rectangle")
      case 3: bridge.emitActivation("screenshot")
      case 4: bridge.emitPinAction("pinClipboard")
      case 5: bridge.emitPinAction("togglePinnedImages")
      default: return OSStatus(eventNotHandledErr)
      }
      return noErr
    }, 1, &spec, context, &hotkeyHandler)
    guard status == noErr else {
      nativeLogs.log(1000, "shortcuts", "Hotkey handler installation failed: status=\(status).")
      return
    }
    nativeLogs.log(800, "shortcuts", "Hotkey handler installed.")
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
    for (id, chord) in [(UInt32(1), bindings.picker), (UInt32(2), bindings.ruler), (UInt32(3), bindings.screenshot),
      (UInt32(4), bindings.pinClipboard), (UInt32(5), bindings.togglePins)] {
      var ref: EventHotKeyRef?
      let error = RegisterEventHotKey(chord.keyCode, chord.carbonModifiers,
        EventHotKeyID(signature: signature, id: id), GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &ref)
      guard error == noErr, let value = ref else {
        nativeLogs.log(900, "shortcuts", "Hotkey registration failed: id=\(id), status=\(error).")
        unregisterHotkeys(); return false
      }
      hotkeys.append(value)
    }
    hasShortcuts = hotkeys.count == 5
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
    for (tool, chord) in [("picker", shortcuts.picker), ("rectangle", shortcuts.ruler), ("screenshot", shortcuts.screenshot),
      ("pinClipboard", shortcuts.pinClipboard), ("togglePinnedImages", shortcuts.togglePins)] {
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
  let pinClipboard: NativeShortcut
  let togglePins: NativeShortcut
  static let defaults = NativeShortcutBindings(picker: NativeShortcut(key: "C", modifiers: [.command, .shift]),
    ruler: NativeShortcut(key: "R", modifiers: [.command, .shift]))
  init(picker: NativeShortcut, ruler: NativeShortcut,
    screenshot: NativeShortcut = NativeShortcut(key: "X", modifiers: [.command, .shift]),
    pinClipboard: NativeShortcut = NativeShortcut(key: "T", modifiers: [.command, .shift]),
    togglePins: NativeShortcut = NativeShortcut(key: "V", modifiers: [.command, .shift])) {
    self.picker = picker; self.ruler = ruler; self.screenshot = screenshot
    self.pinClipboard = pinClipboard; self.togglePins = togglePins
  }
  init?(_ data: [String: Any]) {
    guard let picker = NativeShortcut(data["picker"]), let ruler = NativeShortcut(data["ruler"]),
      let screenshot = NativeShortcut(data["screenshot"]), let pin = NativeShortcut(data["pinClipboard"]),
      let toggle = NativeShortcut(data["togglePins"]) else { return nil }
    self.init(picker: picker, ruler: ruler, screenshot: screenshot, pinClipboard: pin, togglePins: toggle)
  }
  var isValid: Bool {
    let chords = [picker, ruler, screenshot, pinClipboard, togglePins]
    return chords.allSatisfy { $0.isValid } &&
      chords.enumerated().allSatisfy { index, chord in !chords.prefix(index).contains(chord) }
  }
}

private enum CaptureFailure: LocalizedError {
  case unavailable
  var errorDescription: String? { NativeStrings.text("error.capture_unavailable") }
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
    guard let space = CGColorSpace(name: CGColorSpace.sRGB) else {
      nativeLogs.log(1000, "capture", "Snapshot unavailable: stage=color_space.")
      throw CaptureFailure.unavailable
    }
    guard let pixels = NativePixelBuffer(byteCount: pixelWidth * pixelHeight * 4) else {
      nativeLogs.log(1000, "capture", "Snapshot unavailable: stage=pixel_allocation.")
      throw CaptureFailure.unavailable
    }
    self.pixels = pixels
    let normalized: CGImage? = {
      guard let context = CGContext(data: pixels.data, width: pixelWidth, height: pixelHeight,
        bitsPerComponent: 8, bytesPerRow: pixelWidth * 4, space: space,
        bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue)
        else {
          nativeLogs.log(1000, "capture", "Snapshot unavailable: stage=bitmap_context.")
          return nil
        }
      context.interpolationQuality = .none
      context.setFillColor(CGColor(gray: 1, alpha: 1))
      context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
      context.draw(image, in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
      return context.makeImage()
    }()
    guard let normalized = normalized else {
      nativeLogs.log(1000, "capture", "Snapshot unavailable: stage=normalized_image.")
      throw CaptureFailure.unavailable
    }
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

private final class CaptureOverlayView: NSView, NSTextFieldDelegate {
  let snapshot: DisplaySnapshot
  var regionTargets: [CaptureRegionTarget] = []
  private var tool: String
  var isRecordingSelection: Bool { tool == "recording" }
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
  private var colorOutputName = "HEX"
  private var anchored = false
  private var cursorHidden = false
  private var scrollRemainder: CGFloat = 0
  private var pins: [(id: Int, rect: NSRect, label: String)] = []
  private var continuous = false
  private var pickedCount = 0
  private var pickerActions = NativeStrings.text("picker.default_actions")
  private var editingPins = false
  private var selectedPin: Int?
  private var pinDrag: (id: Int, start: NSPoint, handle: String)?
  private var capturePurpose = ""
  private let editbar = NSView()
  private let continuousButton = CaptureButton(checkboxWithTitle: NativeStrings.text("picker.continuous"), target: nil, action: nil)
  private let copySizeButton = CaptureButton(title: NativeStrings.text("overlay.copy_size_title"), target: nil, action: nil)
  private let redoButton = CaptureButton(title:NativeStrings.text("overlay.redo"),target:nil,action:nil)
  private let undoButton = CaptureButton(title: NativeStrings.text("overlay.undo"), target: nil, action: nil)
  private let deleteButton = CaptureButton(title: NativeStrings.text("overlay.delete"), target: nil, action: nil)
  private var modeButtons: [String: NSButton] = [:]
  private let toolbar = NSView()
  private let infoLabel = NSTextField(labelWithString: "")
  private let toleranceGroup = NSStackView()
  private let toleranceLabel = NSTextField(labelWithString: NativeStrings.text("overlay.tolerance"))
  private let closeButton = CaptureButton(title: "", target: nil, action: nil)
  private var lastOptions: [String: Any] = [:]
  private let toleranceField = NSTextField(string: "16")
  private let clearButton = CaptureButton(title: NativeStrings.text("overlay.clear"), target: nil, action: nil)
  private let accent = NSColor(srgbRed: 38 / 255, green: 131 / 255, blue: 1, alpha: 1)
  private let toolbarSurface = NSColor(srgbRed: 41 / 255, green: 41 / 255, blue: 41 / 255, alpha: 1)

  init(snapshot: DisplaySnapshot, tool: String) {
    self.snapshot = snapshot
    self.tool = tool
    super.init(frame: NSRect(origin: .zero, size: snapshot.frame.size))
    setupToolbar()
    toolbar.isHidden = (tool == "screenshot" || tool == "recording")
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  #if FRULER_INTEGRATION_TEST
  static let integrationEventNumber = 0x4652554C
  var integrationDriving = false
  private(set) var integrationFirstMouseCount = 0
  private(set) var integrationInputPhases: [String] = []

  private func recordIntegrationPhase(_ phase: String, rejected: Bool) {
    let entry = "\(phase):\(rejected ? "noise" : "received")"
    if integrationInputPhases.last != entry {
      integrationInputPhases.append(entry)
      if integrationInputPhases.count > 8 { integrationInputPhases.removeFirst() }
    }
    NativeInputDiagnostics.record("overlay tool=\(tool) phase=\(phase) noise=\(rejected)")
  }
  #endif

  private func ignoresIntegrationNoise(_ event: NSEvent) -> Bool {
    #if FRULER_INTEGRATION_TEST
    // CGEvent 转回 NSEvent 时 eventNumber 会截成 16 位，另保留完整的驱动标记。
    return integrationDriving && event.eventNumber != Self.integrationEventNumber &&
      event.cgEvent?.getIntegerValueField(.eventSourceUserData) != Int64(Self.integrationEventNumber)
    #else
    return false
    #endif
  }
  override var isFlipped: Bool { true }
  override var acceptsFirstResponder: Bool { true }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
    // 屏幕工具应立即响应首击，不能让窗口激活过程吞掉取色或选区的第一次点击。
    #if FRULER_INTEGRATION_TEST
    integrationFirstMouseCount += 1
    NativeInputDiagnostics.record("firstMouse tool=\(tool) count=\(integrationFirstMouseCount) accepted=true active=\(NSApp.isActive) key=\(window?.isKeyWindow == true)")
    #endif
    return true
  }

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
    if ignoresIntegrationNoise(event) { return }
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
  override func mouseEntered(with event: NSEvent) { if ignoresIntegrationNoise(event) { return }; window?.makeKey(); send(event, phase: "move") }
  override func mouseExited(with event: NSEvent) {
    if ignoresIntegrationNoise(event) { return }
    isPointerActive = false
    if pinDrag == nil { hoverLocation = nil; NSCursor.arrow.set() }
  }
  override func mouseMoved(with event: NSEvent) { send(event, phase: "move") }
  override func mouseDown(with event: NSEvent) {
    if ignoresIntegrationNoise(event) {
      #if FRULER_INTEGRATION_TEST
      recordIntegrationPhase("down", rejected: true)
      #endif
      return
    }
    window?.makeKey()
    send(event, phase: "down")
  }
  override func mouseDragged(with event: NSEvent) { send(event, phase: "drag") }
  override func mouseUp(with event: NSEvent) { send(event, phase: "up") }
  override func rightMouseDown(with event: NSEvent) { if ignoresIntegrationNoise(event) { return }; if tool == "picker" { send(event,phase:"down") } else { onCancel?() } }
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
      guard tool != "picker", tool != "screenshot", tool != "recording", !event.isARepeat else { return }
      let modes = [kVK_ANSI_1: "rectangle", kVK_ANSI_2: "horizontal", kVK_ANSI_3: "vertical", kVK_ANSI_4: "cross"]
      onEvent?(["type": "modeChanged", "tool": modes[Int(event.keyCode)]!])
    default: break
    }
  }

  override func scrollWheel(with event: NSEvent) {
    guard tool != "rectangle", tool != "screenshot", tool != "recording" else { return }
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
    #if FRULER_INTEGRATION_TEST
    recordIntegrationPhase(phase, rejected: ignoresIntegrationNoise(event))
    #endif
    if ignoresIntegrationNoise(event) { return }
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
    #if FRULER_INTEGRATION_TEST
    if integrationDriving { return }
    #endif
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
  func integrationSetTolerance(_ value: String) -> Bool {
    guard !toleranceGroup.isHidden else { return false }
    toleranceField.selectText(nil)
    if let editor = toleranceField.currentEditor() {
      editor.selectAll(nil)
      editor.insertText(value)
      toleranceField.validateEditing()
    } else { return false }
    toleranceField.sendAction(toleranceField.action, to: toleranceField.target)
    window?.makeFirstResponder(self)
    return true
  }
  func integrationClickControl(_ name: String) -> Bool {
    let control: NSButton? = modeButtons[name] ?? ["delete":deleteButton,"undo":undoButton][name]
    guard let button=control, button.isEnabled, !button.isHidden, !toolbar.isHidden else { return false }
    button.performClick(nil)
    return true
  }
  func integrationLayout(width: Double, height: Double) -> Bool {
    let view = CaptureOverlayView(snapshot: snapshot, tool: tool)
    view.setFrameSize(NSSize(width: width, height: height))
    view.updateOptions(["tool":tool, "selectedPin":1])
    view.layoutSubtreeIfNeeded()
    return [view.toolbar, view.editbar].allSatisfy { bar in
      bar.frame.minY < view.bounds.midY && view.bounds.contains(bar.frame) && bar.subviews.allSatisfy { bar.bounds.contains($0.frame) }
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
    let modes = modeButtons.mapValues { button -> [String: Any] in
      ["hasImage": button.image != nil, "title": button.title, "hidden": button.isHidden,
       "tooltip": button.toolTip ?? "", "selected": button.accessibilityValue() as? String ?? ""]
    }
    return ["toolbarWidth": toolbar.frame.width,
     "toolbarContentWidth": toolbar.subviews.first?.frame.width ?? 0,
     "editbarVisible": !editbar.isHidden, "toleranceVisible": !toleranceGroup.isHidden,
     "tolerance": tolerance, "toolbarTop": toolbar.frame.minY, "editbarTop": editbar.frame.minY,
     "colorOutputName": colorOutputName, "modes": modes, "cursor": cursorName, "controls": controls,"displayId": snapshot.displayID, "tool": tool,
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
    lastOptions = data
    if let value = data["tool"] as? String { tool = value }
    toolbar.isHidden = screenshotEditing || (tool == "screenshot" || tool == "recording")
    capturePurpose = data["capturePurpose"] as? String ?? ""
    pickerActions = data["pickerActions"] as? String ?? pickerActions
    if let value = data["tolerance"] as? Int { tolerance = value }
    if let value = data["zoom"] as? Int { zoom = value }
    if let value = data["colorOutputName"] as? String { colorOutputName = value }
    if let value = data["continuous"] as? Bool { continuous = value }
    if let value = data["pickedCount"] as? Int { pickedCount = value }
    if let value = data["editingPins"] as? Bool { editingPins = value }
    selectedPin = data["selectedPin"] as? Int
    continuousButton.state = continuous ? .on : .off
    continuousButton.isHidden = tool != "picker" || !capturePurpose.isEmpty
    editbar.isHidden = tool != "rectangle" || (pins.isEmpty && data["canUndoPins"] as? Bool != true && data["canRedoPins"] as? Bool != true)
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
      clearButton.toolTip = NativeStrings.text("overlay.clear_count", values.count)
      clearButton.isEnabled = !values.isEmpty
      deleteButton.isEnabled = pins.contains(where: { $0.id == selectedPin })

    }
    editbar.isHidden = tool != "rectangle" || (pins.isEmpty && !undoButton.isEnabled && !redoButton.isEnabled)
    for (mode, button) in modeButtons {
      let selected = mode == tool
      button.isHidden = tool == "picker" || (tool == "screenshot" || tool == "recording")
      button.layer?.backgroundColor = (selected ? accent : NSColor.clear).cgColor
      button.contentTintColor = .white
      button.setAccessibilityValue(selected ? NativeStrings.text("overlay.selected") : "")
    }
    clearButton.isHidden = tool == "picker" || (tool == "screenshot" || tool == "recording")
    infoLabel.stringValue = tool == "picker" ? NativeStrings.text("overlay.picker_summary", capturePurpose.isEmpty ? colorOutputName : capturePurpose, zoom, pickedCount) :
      (tool == "screenshot" || tool == "recording") ? NativeStrings.text("overlay.screenshot_summary") : editingPins ? NativeStrings.text("overlay.editing_summary") : tool == "rectangle" ? NativeStrings.text("overlay.rectangle_summary") : NativeStrings.text("overlay.tolerance_summary", tolerance)
    infoLabel.toolTip = tool == "picker" ? NativeStrings.text("overlay.picker_tooltip", pickerActions) : NativeStrings.text("overlay.ruler_tooltip")
    infoLabel.isHidden = tool != "picker"
    toleranceGroup.isHidden = !["horizontal", "vertical", "cross"].contains(tool)
    if toleranceField.currentEditor() == nil { toleranceField.stringValue = String(tolerance) }
    needsDisplay = true
    window?.invalidateCursorRects(for: self)
    if let location = hoverLocation { applyCursor(at: location) }
  }

  func refreshLocalization() {
    continuousButton.title = NativeStrings.text("picker.continuous")
    continuousButton.toolTip = NativeStrings.text("picker.continuous_tooltip")
    toleranceLabel.stringValue = NativeStrings.text("overlay.tolerance")
    toleranceField.toolTip = NativeStrings.text("overlay.tolerance_tooltip")
    toleranceField.setAccessibilityLabel(NativeStrings.text("overlay.tolerance_accessibility"))
    for (index, mode) in ["rectangle", "horizontal", "vertical", "cross"].enumerated() {
      let title = NativeStrings.text("mode.shortcut", NativeStrings.text("mode.\(mode)"), index + 1)
      modeButtons[mode]?.toolTip = title
      modeButtons[mode]?.setAccessibilityLabel(title)
    }
    for (button, key) in [(copySizeButton, "overlay.copy_size_tooltip"),
      (undoButton, "overlay.undo_tooltip"), (redoButton, "overlay.redo_tooltip"),
      (deleteButton, "overlay.delete_selected_tooltip"), (clearButton, "overlay.clear_tooltip"),
      (closeButton, "overlay.cancel_tooltip")] {
      let title = NativeStrings.text(key)
      button.toolTip = title
      button.setAccessibilityLabel(title)
    }
    updateOptions(lastOptions)
    needsLayout = true
    needsDisplay = true
  }

  private func styleButton(_ button: NSButton, symbol: String, tooltip: String) {
    button.title = ""
    button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
    button.imagePosition = .imageOnly
    button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: symbol == "xmark" ? 12 : 16, weight: .regular)
    button.contentTintColor = .white
    button.isBordered = false
    button.wantsLayer = true
    button.layer?.cornerRadius = 3
    button.toolTip = tooltip
    button.setAccessibilityLabel(tooltip)
    button.widthAnchor.constraint(equalToConstant: 28).isActive = true
    button.heightAnchor.constraint(equalToConstant: 28).isActive = true
  }

  private func styleToolbar(_ bar: NSView) {
    bar.translatesAutoresizingMaskIntoConstraints = false
    bar.appearance = NSAppearance(named: .darkAqua)
    bar.wantsLayer = true
    bar.layer?.backgroundColor = toolbarSurface.cgColor
    bar.layer?.cornerRadius = 4
    bar.shadow = NSShadow()
    bar.shadow?.shadowColor = NSColor.black.withAlphaComponent(0.3)
    bar.shadow?.shadowBlurRadius = 4
    bar.shadow?.shadowOffset = NSSize(width: 0, height: -2)
  }

  private func setupToolbar() {
    styleToolbar(toolbar)
    addSubview(toolbar)
    let stack = NSStackView()
    stack.translatesAutoresizingMaskIntoConstraints = false
    stack.orientation = .horizontal
    stack.spacing = 6
    stack.alignment = .centerY
    toolbar.addSubview(stack)
    for (index, mode) in ["rectangle", "horizontal", "vertical", "cross"].enumerated() {
      let names = [NativeStrings.text("mode.rectangle"), NativeStrings.text("mode.horizontal"), NativeStrings.text("mode.vertical"), NativeStrings.text("mode.cross")]
      let symbols = ["rectangle.dashed", "arrow.left.and.right", "arrow.up.and.down", "arrow.up.and.down.and.arrow.left.and.right"]
      let button = CaptureButton(title: "", target: self, action: #selector(changeMode(_:)))
      button.identifier = NSUserInterfaceItemIdentifier(mode)
      styleButton(button, symbol: symbols[index], tooltip: NativeStrings.text("mode.shortcut", names[index], index + 1))
      modeButtons[mode] = button
      stack.addArrangedSubview(button)
    }
    infoLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
    infoLabel.textColor = NSColor.white.withAlphaComponent(0.8)
    infoLabel.alignment = .center
    infoLabel.lineBreakMode = .byTruncatingTail
    infoLabel.setContentHuggingPriority(.required, for: .horizontal)
    infoLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    stack.addArrangedSubview(infoLabel)
    toleranceGroup.orientation = .horizontal
    toleranceGroup.spacing = 6
    toleranceGroup.alignment = .centerY
    toleranceLabel.font = .systemFont(ofSize: 11)
    toleranceLabel.textColor = .white
    toleranceGroup.addArrangedSubview(toleranceLabel)
    toleranceField.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
    toleranceField.alignment = .center
    toleranceField.widthAnchor.constraint(equalToConstant: 42).isActive = true
    toleranceField.toolTip = NativeStrings.text("overlay.tolerance_tooltip")
    toleranceField.setAccessibilityLabel(NativeStrings.text("overlay.tolerance_accessibility"))
    toleranceField.target = self
    toleranceField.action = #selector(applyTolerance)
    toleranceField.delegate = self
    toleranceGroup.addArrangedSubview(toleranceField)
    stack.addArrangedSubview(toleranceGroup)
    continuousButton.target = self
    continuousButton.action = #selector(toggleContinuous)
    continuousButton.font = .systemFont(ofSize: 11)
    continuousButton.contentTintColor = .white
    continuousButton.toolTip = NativeStrings.text("picker.continuous_tooltip")
    stack.addArrangedSubview(continuousButton)
    clearButton.target = self
    clearButton.action = #selector(clearPins)
    styleButton(clearButton, symbol: "trash.slash", tooltip: NativeStrings.text("overlay.clear_all_tooltip"))
    let close = closeButton
    close.target = self
    close.action = #selector(cancelCapture)
    styleButton(close, symbol: "xmark", tooltip: NativeStrings.text("overlay.cancel_tooltip"))
    stack.addArrangedSubview(close)
    NSLayoutConstraint.activate([
      toolbar.centerXAnchor.constraint(equalTo: centerXAnchor),
      toolbar.topAnchor.constraint(equalTo: topAnchor, constant: 22),
      toolbar.heightAnchor.constraint(equalToConstant: 34),
      toolbar.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -24),
      stack.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 10),
      stack.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -10),
      stack.topAnchor.constraint(equalTo: toolbar.topAnchor, constant: 3),
      stack.bottomAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: -3)
    ])
    setupEditbar()
    updateOptions(["tool": tool])
  }

  private func setupEditbar() {
    styleToolbar(editbar)
    addSubview(editbar)
    let stack = NSStackView()
    stack.translatesAutoresizingMaskIntoConstraints = false
    stack.orientation = .horizontal; stack.spacing = 6; stack.alignment = .centerY
    editbar.addSubview(stack)
    let actions: [(NSButton, Selector)] = [(copySizeButton, #selector(copyMeasurement)),
      (undoButton, #selector(undoPin)), (redoButton, #selector(redoPin)),
      (deleteButton, #selector(deletePin)), (clearButton, #selector(clearPins))]
    let symbols = ["doc.on.clipboard", "arrow.uturn.backward", "arrow.uturn.forward", "trash", "trash.slash"]
    let tooltips = [NativeStrings.text("overlay.copy_size_tooltip"), NativeStrings.text("overlay.undo_tooltip"), NativeStrings.text("overlay.redo_tooltip"), NativeStrings.text("overlay.delete_tooltip"), NativeStrings.text("overlay.clear_tooltip")]
    for (index, entry) in actions.enumerated() {
      let (button, action) = entry
      button.target = self; button.action = action
      styleButton(button, symbol: symbols[index], tooltip: tooltips[index])
      stack.addArrangedSubview(button)
    }
    deleteButton.toolTip = NativeStrings.text("overlay.delete_selected_tooltip")
    NSLayoutConstraint.activate([
      editbar.centerXAnchor.constraint(equalTo: centerXAnchor),
      editbar.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 4),
      stack.leadingAnchor.constraint(equalTo: editbar.leadingAnchor, constant: 10),
      stack.trailingAnchor.constraint(equalTo: editbar.trailingAnchor, constant: -10),
      stack.topAnchor.constraint(equalTo: editbar.topAnchor, constant: 3),
      stack.bottomAnchor.constraint(equalTo: editbar.bottomAnchor, constant: -3)
    ])
  }
  private func emitControl(_ type: String, data: [String: Any] = [:]) {
    var event = data; event["type"] = type; onEvent?(event)
    window?.makeFirstResponder(self)
  }
  @objc private func copyMeasurement() { emitControl("copyMeasurement") }
  @objc private func toggleContinuous() { emitControl("continuousChanged", data: ["enabled": continuousButton.state == .on]) }
  @objc private func redoPin() { emitControl("redoPins") }
  @objc private func undoPin() { emitControl("undoPins") }
  @objc private func deletePin() { emitControl("deletePin") }
  @objc private func applyTolerance() {
    let raw = toleranceField.stringValue.trimmingCharacters(in: .whitespaces)
    guard !raw.isEmpty, raw.allSatisfy({ $0.isASCII && $0.isNumber }),
          let value = Int(raw), (0...255).contains(value) else {
      toleranceField.stringValue = String(tolerance)
      return
    }
    guard value != tolerance else { return }
    tolerance = value
    emitControl("toleranceChanged", data: ["tolerance": value])
  }
  func controlTextDidEndEditing(_ notification: Notification) {
    if notification.object as? NSTextField === toleranceField { applyTolerance() }
  }

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
    toolbar.isHidden = editing || (tool == "screenshot" || tool == "recording")
    editbar.isHidden = editing || (tool == "screenshot" || tool == "recording") || tool == "picker"
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
    if (tool == "screenshot" || tool == "recording"), let rect = measuredRect {
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
    if tool == "rectangle" || (tool == "screenshot" || tool == "recording") {
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
    let width: CGFloat = sampling ? 220 : tool == "recording" ? 340 : 300
    let height: CGFloat = sampling ? (tool == "picker" ? 278 : 250) : tool == "recording" ? 90 : 64
    var x = pointer.x + 26
    var y = pointer.y + 26
    if x + width > bounds.width - 12 { x = pointer.x - width - 26 }
    if y + height > bounds.height - 12 { y = pointer.y - height - 26 }
    let box = NSRect(x: max(12, x), y: max(12, y), width: width, height: height)
    toolbarSurface.setFill()
    NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4).fill()
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
        if (tool == "screenshot" || tool == "recording"), let rect = measuredRect {
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
      if (tool == "screenshot" || tool == "recording"), let rect = measuredRect {
        let w = Int((rect.width / bounds.width * Double(snapshot.width)).rounded())
        let h = Int((rect.height / bounds.height * Double(snapshot.height)).rounded())
        details += NativeStrings.text("loupe.area", w, h)
      }
      (details as NSString).draw(at: NSPoint(x: box.minX + 14, y: labelY + 18), withAttributes: attrs)
    } else {
      (label as NSString).draw(at: NSPoint(x: box.minX + 14, y: labelY), withAttributes: [
        .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.white])
    }
    let hint = tool == "rectangle" ? (anchored ? NativeStrings.text("loupe.anchored_hint") : NativeStrings.text("loupe.rectangle_hint")) :
      (continuous && tool == "picker" ? NativeStrings.text("loupe.continuous_hint") : NativeStrings.text("loupe.copy_hint"))
    let actionHint = tool == "recording" ? NativeStrings.text("recording.hint") : tool == "screenshot" ? NativeStrings.text("loupe.screenshot_hint") : tool == "picker" ? NativeStrings.text("loupe.picker_hint", pickerActions) : hint
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

/// 复用与 macOS Snipaste 相同的原生颜色选择器，确认前不修改标注。
final class AnnotationColorDialog: NSObject, NSWindowDelegate {
  let panel: NSColorPanel
  let confirmButton: NSButton
  let cancelButton: NSButton
  private var completion: ((Int64?) -> Void)?
  private weak var owner: NSWindow?
  private var ownerLevel: NSWindow.Level?

  init(initialColor: Int64, completion: @escaping (Int64?) -> Void) {
    panel = NSColorPanel(contentRect: NSRect(x: 0, y: 0, width: 266, height: 390),
      styleMask: [.titled, .closable], backing: .buffered, defer: false)
    confirmButton = NSButton(title: NativeStrings.text("color.confirm"), target: nil, action: nil)
    cancelButton = NSButton(title: NativeStrings.text("color.cancel"), target: nil, action: nil)
    self.completion = completion
    super.init()
    panel.title = NativeStrings.text("color.title")
    panel.toolbarStyle = .expanded
    panel.toolbar?.displayMode = .iconOnly
    panel.isReleasedWhenClosed = false
    panel.delegate = self
    panel.showsAlpha = true
    panel.mode = .wheel
    panel.color = Self.nsColor(initialColor)
    panel.setTarget(nil)
    panel.setAction(nil)
    panel.level = .popUpMenu
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.hidesOnDeactivate = false
    let footer = NSView(frame: NSRect(x: 0, y: 0, width: 266, height: 44))
    for button in [cancelButton, confirmButton] {
      button.bezelStyle = .rounded
      button.target = self
      button.translatesAutoresizingMaskIntoConstraints = false
      footer.addSubview(button)
    }
    confirmButton.action = #selector(confirm(_:))
    confirmButton.keyEquivalent = "\r"
    cancelButton.action = #selector(cancel(_:))
    cancelButton.keyEquivalent = "\u{1b}"
    NSLayoutConstraint.activate([
      confirmButton.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -12),
      confirmButton.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
      confirmButton.widthAnchor.constraint(equalToConstant: 72),
      cancelButton.trailingAnchor.constraint(equalTo: confirmButton.leadingAnchor, constant: -8),
      cancelButton.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
      cancelButton.widthAnchor.constraint(equalToConstant: 72),
    ])
    // 将系统选色内容整体放在按钮上方，保留样本网格的位置与 Snipaste 一致。
    let systemContent = panel.contentView!
    let size = NSSize(width: systemContent.frame.width, height: systemContent.frame.height + 44)
    let content = NSView(frame: NSRect(origin: .zero, size: size))
    panel.contentView = nil
    systemContent.setFrameOrigin(NSPoint(x: 0, y: 44))
    systemContent.autoresizingMask = [.width, .height]
    content.addSubview(systemContent)
    footer.autoresizingMask = [.width]
    content.addSubview(footer)
    panel.contentView = content
    panel.setContentSize(size)
  }

  func refreshLocalization() {
    panel.title = NativeStrings.text("color.title")
    confirmButton.title = NativeStrings.text("color.confirm")
    cancelButton.title = NativeStrings.text("color.cancel")
  }

  static func nsColor(_ argb: Int64) -> NSColor {
    NSColor(srgbRed: CGFloat((argb >> 16) & 255) / 255,
      green: CGFloat((argb >> 8) & 255) / 255, blue: CGFloat(argb & 255) / 255,
      alpha: CGFloat((argb >> 24) & 255) / 255)
  }

  static func argb(_ color: NSColor) -> Int64? {
    guard let rgb = color.usingColorSpace(.sRGB) else { return nil }
    func byte(_ value: CGFloat) -> Int64 { Int64((min(1, max(0, value)) * 255).rounded()) }
    return byte(rgb.alphaComponent) << 24 | byte(rgb.redComponent) << 16 |
      byte(rgb.greenComponent) << 8 | byte(rgb.blueComponent)
  }

  func present(relativeTo owner: NSWindow) {
    self.owner = owner
    ownerLevel = owner.level
    // 系统拖放窗口低于屏保层；选色期间保持浮层高于菜单栏，并让颜色拖放可命中面板。
    owner.level = .statusBar
    if let screen = owner.screen {
      let frame = screen.visibleFrame
      panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2,
        y: frame.midY - panel.frame.height / 2))
    }
    NSApp.activate(ignoringOtherApps: true)
    panel.makeKeyAndOrderFront(nil)
  }

  @objc func confirm(_ sender: Any?) {
    guard let color = Self.argb(panel.color) else { NSSound.beep(); return }
    finish(color)
  }
  @objc func cancel(_ sender: Any?) { finish(nil) }
  func windowShouldClose(_ sender: NSWindow) -> Bool { finish(nil); return false }

  private func finish(_ color: Int64?) {
    guard let reply = completion else { return }
    completion = nil
    panel.delegate = nil
    panel.orderOut(nil)
    panel.close()
    if let owner, let ownerLevel { owner.level = ownerLevel }
    reply(color)
  }
}
