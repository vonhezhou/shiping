import Cocoa
import ImageIO
import UniformTypeIdentifiers

enum PinImageError: LocalizedError {
  case invalidImage, emptyClipboard, exportFailed, resourceLimit
  var errorDescription: String? {
    switch self {
    case .invalidImage: return NativeStrings.text("pin.error_image")
    case .emptyClipboard: return NativeStrings.text("pin.error_clipboard")
    case .exportFailed: return NativeStrings.text("pin.error_export")
    case .resourceLimit: return NativeStrings.text("pin.error_limit")
    }
  }
}

enum PinnedImageGeometry {
  static func clampedScale(_ value: CGFloat) -> CGFloat {
    value.isFinite ? min(16, max(0.05, value)) : 1
  }

  static func fitScale(size: NSSize, screen: NSRect) -> CGFloat {
    guard size.width > 0, size.height > 0 else { return 1 }
    return min(1, min(screen.width * 0.9 / size.width, screen.height * 0.9 / size.height))
  }

  static func scaledFrame(_ frame: NSRect, size: NSSize, anchor: NSPoint) -> NSRect {
    let fraction = NSPoint(x: (anchor.x - frame.minX) / max(1, frame.width),
      y: (anchor.y - frame.minY) / max(1, frame.height))
    return NSRect(x: anchor.x - size.width * fraction.x, y: anchor.y - size.height * fraction.y,
      width: size.width, height: size.height)
  }

  static func visibleFrame(_ frame: NSRect, screen: NSRect) -> NSRect {
    var result = frame
    // 超大贴图仍保留至少 32 pt 可抓取区域，小图完整限制在屏幕内。
    let horizontal = min(frame.width, 32), vertical = min(frame.height, 32)
    let minX = frame.width <= screen.width ? screen.minX : screen.minX - frame.width + horizontal
    let maxX = frame.width <= screen.width ? screen.maxX - frame.width : screen.maxX - horizontal
    let minY = frame.height <= screen.height ? screen.minY : screen.minY - frame.height + vertical
    let maxY = frame.height <= screen.height ? screen.maxY - frame.height : screen.maxY - vertical
    result.origin.x = min(maxX, max(minX, frame.origin.x))
    result.origin.y = min(maxY, max(minY, frame.origin.y))
    return result
  }

  static func bestScreen(for frame: NSRect, screens: [NSRect]) -> NSRect? {
    screens.max { first, second in
      let firstIntersection = frame.intersection(first)
      let secondIntersection = frame.intersection(second)
      let firstArea = firstIntersection.isNull ? 0 : firstIntersection.width * firstIntersection.height
      let secondArea = secondIntersection.isNull ? 0 : secondIntersection.width * secondIntersection.height
      if firstArea != secondArea { return firstArea < secondArea }
      let firstDistance = pow(first.midX - frame.midX, 2) + pow(first.midY - frame.midY, 2)
      let secondDistance = pow(second.midX - frame.midX, 2) + pow(second.midY - frame.midY, 2)
      return firstDistance > secondDistance
    }
  }
}

/// 旋转与翻转只在原图像素上执行，显示倍率和窗口透明度不进入导出路径。
struct PinnedImageTransform {
  var quarterTurns = 0
  var flipHorizontal = false
  var flipVertical = false

  func render(_ image: CGImage) throws -> CGImage {
    let turns = ((quarterTurns % 4) + 4) % 4
    if turns == 0 && !flipHorizontal && !flipVertical { return image }
    let width = image.width, height = image.height
    var source = [UInt8](repeating: 0, count: width * height * 4)
    let drawn = source.withUnsafeMutableBytes { storage -> Bool in
      guard let context = CGContext(data: storage.baseAddress, width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
      context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
      return true
    }
    guard drawn else { throw PinImageError.exportFailed }
    let outputWidth = turns % 2 == 0 ? width : height
    let outputHeight = turns % 2 == 0 ? height : width
    var output = [UInt8](repeating: 0, count: source.count)
    for y in 0..<height {
      for x in 0..<width {
        var point: (Int, Int)
        switch turns {
        case 1: point = (height - 1 - y, x)
        case 2: point = (width - 1 - x, height - 1 - y)
        case 3: point = (y, width - 1 - x)
        default: point = (x, y)
        }
        if flipHorizontal { point.0 = outputWidth - 1 - point.0 }
        if flipVertical { point.1 = outputHeight - 1 - point.1 }
        let inputOffset = (y * width + x) * 4
        let outputOffset = (point.1 * outputWidth + point.0) * 4
        for channel in 0..<4 { output[outputOffset + channel] = source[inputOffset + channel] }
      }
    }
    guard let provider = CGDataProvider(data: Data(output) as CFData),
      let result = CGImage(width: outputWidth, height: outputHeight, bitsPerComponent: 8,
        bitsPerPixel: 32, bytesPerRow: outputWidth * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
      else { throw PinImageError.exportFailed }
    return result
  }
}

final class PinnedImageManager {
  private(set) var panels: [PinnedImagePanel] = []
  var windows: [PinnedImagePanel] { panels }
  private var nextID = 0
  private var screenObserver: NSObjectProtocol?
  private let maximumCount: Int
  private let maximumPixelCount: Int

  init(maximumCount: Int = 32, maximumPixelCount: Int = 64_000_000) {
    self.maximumCount = maximumCount
    self.maximumPixelCount = maximumPixelCount
    screenObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
    ) { [weak self] _ in self?.keepOnVisibleScreens() }
  }

  deinit {
    if let observer = screenObserver { NotificationCenter.default.removeObserver(observer) }
    closeAll()
  }

  private func keepOnVisibleScreens() {
    let screens = NSScreen.screens.map { $0.visibleFrame }
    for panel in panels {
      if let screen = PinnedImageGeometry.bestScreen(for: panel.frame, screens: screens) {
        panel.setFrame(PinnedImageGeometry.visibleFrame(panel.frame, screen: screen), display: true)
      }
    }
  }

  func pin(png: Data, logicalSize: NSSize? = nil, center: NSPoint? = nil) throws {
    guard let source = CGImageSourceCreateWithData(png as CFData, nil),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
      let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else { throw PinImageError.invalidImage }
    // 先读图像头并检查总预算，超限时不解码，更不驱逐用户仍可恢复的贴图。
    try checkCapacity(width: width.intValue, height: height.intValue)
    guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw PinImageError.invalidImage }
    try pin(image: image, logicalSize: logicalSize, center: center)
  }

  private func checkCapacity(width: Int, height: Int) throws {
    guard width > 0, height > 0 else { throw PinImageError.invalidImage }
    let existingPixels = panels.reduce(0) { $0 + $1.sourceImage.width * $1.sourceImage.height }
    guard panels.count < maximumCount, height <= maximumPixelCount,
      width <= max(0, maximumPixelCount - existingPixels) / height else { throw PinImageError.resourceLimit }
  }

  private func pin(image: CGImage, logicalSize: NSSize?, center: NSPoint?) throws {
    try checkCapacity(width: image.width, height: image.height)
    let point = center ?? NSEvent.mouseLocation
    let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main
    let backingScale = screen?.backingScaleFactor ?? 1
    let proposedSize = logicalSize ?? NSSize(width: CGFloat(image.width) / backingScale,
      height: CGFloat(image.height) / backingScale)
    guard proposedSize.width.isFinite, proposedSize.height.isFinite,
      proposedSize.width > 0, proposedSize.height > 0 else { throw PinImageError.invalidImage }
    nextID += 1
    let panel = PinnedImagePanel(id: nextID, image: image, logicalSize: proposedSize,
      center: point, visibleFrame: screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1100, height: 760))
    panel.onDestroy = { [weak self, weak panel] in
      guard let panel = panel else { return }
      self?.panels.removeAll { $0 === panel }
    }
    panels.append(panel)
    showVisible()
    nativeLogs.log(800, "pin", "Pinned image created: count=\(panels.count), pixels=\(image.width)x\(image.height).")
  }

  func pinClipboard() throws {
    let pasteboard = NSPasteboard.general
    // 图像优先，富文本的字符串表示可作为文本贴图使用。
    for type in [NSPasteboard.PasteboardType.png, .tiff,
      NSPasteboard.PasteboardType("public.jpeg"), NSPasteboard.PasteboardType("public.heic")] {
      if let bytes = pasteboard.data(forType: type) {
        try pin(png: bytes)
        return
      }
    }
    if let image = NSImage(pasteboard: pasteboard) {
      // 其他粘贴板图像格式同样先检查已有表示尺寸，再要求 AppKit 解码像素。
      for representation in image.representations where representation.pixelsWide > 0 && representation.pixelsHigh > 0 {
        try checkCapacity(width: representation.pixelsWide, height: representation.pixelsHigh)
      }
      guard image.size.width.isFinite, image.size.height.isFinite,
        image.size.width > 0, image.size.height > 0,
        image.size.width <= CGFloat(maximumPixelCount), image.size.height <= CGFloat(maximumPixelCount)
        else { throw PinImageError.invalidImage }
      try checkCapacity(width: Int(ceil(image.size.width)), height: Int(ceil(image.size.height)))
      guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { throw PinImageError.invalidImage }
      try pin(image: cgImage, logicalSize: nil, center: nil)
      return
    }
    guard let text = pasteboard.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw PinImageError.emptyClipboard
    }
    let image = try ClipboardPinRenderer.render(text)
    try pin(image: image, logicalSize: NSSize(width: image.width, height: image.height), center: nil)
  }

  func toggleVisibility() {
    let shouldHide = panels.contains { !$0.isPinnedHidden }
    for panel in panels {
      if shouldHide { panel.hidePin() }
      else {
        panel.isPinnedHidden = false
        // 穿透窗口必须能从状态栏恢复交互，否则无法再次打开右键菜单。
        panel.ignoresMouseEvents = false
      }
    }
    if !shouldHide { showVisible() }
  }

  func showVisible() {
    let visible = panels.filter { !$0.isPinnedHidden }
    guard !visible.isEmpty else { return }
    if NSApp.isHidden { NSApp.unhideWithoutActivation() }
    for panel in visible { panel.orderFrontRegardless() }
  }

  func closeAll() {
    let existing = panels
    panels.removeAll()
    for panel in existing { panel.onDestroy = nil; panel.close() }
  }

  func refreshLocale() {
    for panel in panels { panel.refreshLocale() }
  }

  #if FRULER_INTEGRATION_TEST
  var integrationState: [[String: Any]] { panels.map { $0.integrationState } }
  #endif
}

/// 普通文字和 HEX 颜色可直接来自剪贴板，不经过磁盘或图片编辑工作区。
enum ClipboardPinRenderer {
  static func render(_ text: String) throws -> CGImage {
    guard text.utf16.count <= 100_000 else { throw PinImageError.resourceLimit }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let hex = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : ""
    let isColor = [3, 6, 8].contains(hex.count) && hex.allSatisfy { $0.isHexDigit }
    let expanded = hex.count == 3 ? hex.map { "\($0)\($0)" }.joined() : hex
    let colorValue = UInt64(expanded, radix: 16) ?? 0
    let rgb = hex.count == 8 ? colorValue >> 8 : colorValue
    let alpha = hex.count == 8 ? CGFloat(colorValue & 255) / 255 : 1
    let color = NSColor(srgbRed: CGFloat((rgb >> 16) & 255) / 255,
      green: CGFloat((rgb >> 8) & 255) / 255, blue: CGFloat(rgb & 255) / 255, alpha: alpha)
    let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 16),
      .foregroundColor: NSColor(srgbRed: 0.12, green: 0.12, blue: 0.14, alpha: 1)]
    let content = NSAttributedString(string: text, attributes: attributes)
    let measured = content.boundingRect(with: NSSize(width: 600, height: CGFloat.greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading])
    let size = isColor ? NSSize(width: 240, height: 180)
      : NSSize(width: min(640, max(100, ceil(measured.width) + 32)), height: max(56, ceil(measured.height) + 32))
    // 超长内容明确失败，不能静默截断剪贴板正文。
    guard size.width.isFinite, size.height.isFinite, size.width * size.height <= 16 * 1024 * 1024 else {
      throw PinImageError.resourceLimit
    }
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
      colorSpaceName: .deviceRGB, bytesPerRow: Int(size.width) * 4, bitsPerPixel: 32),
      let context = NSGraphicsContext(bitmapImageRep: rep) else { throw PinImageError.invalidImage }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    NSColor.white.setFill(); NSRect(origin: .zero, size: size).fill()
    if isColor {
      color.setFill(); NSRect(x: 0, y: 40, width: size.width, height: size.height - 40).fill()
      (trimmed.uppercased() as NSString).draw(at: NSPoint(x: 16, y: 12), withAttributes: attributes)
    } else {
      content.draw(with: NSRect(x: 16, y: 16, width: size.width - 32, height: size.height - 32),
        options: [.usesLineFragmentOrigin, .usesFontLeading])
    }
    NSGraphicsContext.restoreGraphicsState()
    guard let image = rep.cgImage else { throw PinImageError.invalidImage }
    return image
  }
}

final class PinnedImagePanel: NSPanel {
  let pinID: Int
  let sourceImage: CGImage
  let originalLogicalSize: NSSize
  private(set) var renderedImage: CGImage
  private(set) var transform = PinnedImageTransform()
  private(set) var scale: CGFloat = 1
  var isPinnedHidden = false
  var onDestroy: (() -> Void)?
  var imageView: PinnedImageView { contentView as! PinnedImageView }
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
  override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
    // 初始位置和适屏由工具显式限制；缩放时 AppKit 的菜单栏避让会破坏鼠标锚点。
    frameRect
  }

  init(id: Int, image: CGImage, logicalSize: NSSize, center: NSPoint, visibleFrame: NSRect) {
    pinID = id
    sourceImage = image
    renderedImage = image
    originalLogicalSize = logicalSize
    let initialScale = PinnedImageGeometry.fitScale(size: logicalSize, screen: visibleFrame)
    let size = NSSize(width: logicalSize.width * initialScale, height: logicalSize.height * initialScale)
    let frame = PinnedImageGeometry.visibleFrame(NSRect(x: center.x - size.width / 2,
      y: center.y - size.height / 2, width: size.width, height: size.height), screen: visibleFrame)
    super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    scale = initialScale
    isReleasedWhenClosed = false
    isFloatingPanel = true
    hidesOnDeactivate = false
    becomesKeyOnlyIfNeeded = true
    level = .floating
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    isOpaque = false
    backgroundColor = .clear
    hasShadow = true
    acceptsMouseMovedEvents = true
    contentView = PinnedImageView(frame: NSRect(origin: .zero, size: size))
    makeFirstResponder(contentView)
    refreshLocale()
  }

  func refreshLocale() {
    title = NativeStrings.text("pin.hint")
    imageView.toolTip = NativeStrings.text("pin.hint")
  }

  func hidePin() {
    isPinnedHidden = true
    orderOut(nil)
  }

  override func close() {
    orderOut(nil)
    super.close()
    let callback = onDestroy
    onDestroy = nil
    callback?()
  }

  func setScale(_ value: CGFloat, anchor: NSPoint? = nil) {
    scale = PinnedImageGeometry.clampedScale(value)
    let turned = transform.quarterTurns % 2 != 0
    let size = NSSize(width: (turned ? originalLogicalSize.height : originalLogicalSize.width) * scale,
      height: (turned ? originalLogicalSize.width : originalLogicalSize.height) * scale)
    let point = anchor ?? NSPoint(x: frame.midX, y: frame.midY)
    let newFrame = PinnedImageGeometry.scaledFrame(frame, size: size, anchor: point)
    // 几何保留小数；AppKit 最终会对齐窗口逻辑整点，锚点存在最多 1 pt 的显示误差。
    setFrame(newFrame, display: true)
  }

  func adjustOpacity(_ amount: CGFloat) { alphaValue = min(1, max(0.1, alphaValue + amount)) }

  func resetImage() {
    transform = PinnedImageTransform()
    renderedImage = sourceImage
    alphaValue = 1
    setScale(1)
    imageView.needsDisplay = true
  }

  func exportPNG() throws -> Data {
    guard let data = NSBitmapImageRep(cgImage: renderedImage).representation(using: .png, properties: [:])
      else { throw PinImageError.exportFailed }
    return data
  }

  @discardableResult func performAction(_ action: String) -> Bool {
    var previousApplication: NSRunningApplication?
    defer {
      if let previous = previousApplication, !previous.isTerminated,
        previous.processIdentifier != ProcessInfo.processInfo.processIdentifier {
        previous.activate(options: [])
      }
    }
    do {
      switch action {
      case "copy":
        let bytes = try exportPNG()
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.setData(bytes, forType: .png) else { throw PinImageError.exportFailed }
      case "save":
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "拾屏-pin.png"
        // 临时激活以显示系统面板；取消保存仍保留原贴图。
        previousApplication = NSWorkspace.shared.frontmostApplication
        NSApp.activate(ignoringOtherApps: true)
        #if FRULER_INTEGRATION_TEST
        if integrationCancelNextSave {
          integrationCancelNextSave = false
          DispatchQueue.main.async { panel.cancel(nil) }
        }
        #endif
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        try exportPNG().write(to: url, options: .atomic)
      case "actual_size": setScale(1)
      case "fit_screen":
        let visible = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? frame
        let turned = transform.quarterTurns % 2 != 0
        let size = turned ? NSSize(width: originalLogicalSize.height, height: originalLogicalSize.width) : originalLogicalSize
        setScale(PinnedImageGeometry.fitScale(size: size, screen: visible))
        setFrame(PinnedImageGeometry.visibleFrame(frame, screen: visible), display: true)
      case "rotate_left", "rotate_right", "flip_horizontal", "flip_vertical":
        var updated = transform
        if action == "rotate_left" || action == "rotate_right" {
          updated.quarterTurns = (updated.quarterTurns + (action == "rotate_left" ? 3 : 1)) % 4
          // 翻转基于屏幕方向；再次旋转整个可见图像时必须交换翻转轴。
          let horizontal = updated.flipHorizontal
          updated.flipHorizontal = updated.flipVertical
          updated.flipVertical = horizontal
        }
        if action == "flip_horizontal" { updated.flipHorizontal.toggle() }
        if action == "flip_vertical" { updated.flipVertical.toggle() }
        renderedImage = try updated.render(sourceImage)
        transform = updated
        setScale(scale)
        imageView.needsDisplay = true
      case "click_through": ignoresMouseEvents.toggle()
      case "hide": hidePin()
      case "close": close()
      default: return false
      }
      return true
    } catch {
      nativeLogs.log(1000, "pin", "Pinned image action failed: action=\(action), errorType=\(String(reflecting: type(of: error))).")
      let alert = NSAlert()
      alert.messageText = error.localizedDescription
      alert.runModal()
      return false
    }
  }

  #if FRULER_INTEGRATION_TEST
  var integrationCancelNextSave = false
  var integrationState: [String: Any] {
    ["id": pinID, "visible": isVisible, "windowNumber": windowNumber,
     "x": frame.minX, "y": frame.minY, "width": frame.width, "height": frame.height,
     "scale": scale, "opacity": alphaValue, "rotation": transform.quarterTurns * 90,
     "flippedHorizontal": transform.flipHorizontal, "flippedVertical": transform.flipVertical,
     "pixelWidth": renderedImage.width, "pixelHeight": renderedImage.height,
     "level": level.rawValue, "clickThrough": ignoresMouseEvents]
  }
  #endif
}

final class PinnedImageView: NSView {
  private var dragOrigin: NSPoint?
  private var dragFrame: NSRect?
  private var panel: PinnedImagePanel? { window as? PinnedImagePanel }
  override var acceptsFirstResponder: Bool { true }
  override var needsPanelToBecomeKey: Bool { true }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func draw(_ dirtyRect: NSRect) {
    guard let panel = panel, let context = NSGraphicsContext.current?.cgContext else { return }
    context.interpolationQuality = .high
    context.draw(panel.renderedImage, in: bounds)
  }

  override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }

  override func mouseDown(with event: NSEvent) {
    guard let panel = panel else { return }
    if event.clickCount >= 2 { panel.hidePin(); return }
    panel.makeKey()
    panel.makeFirstResponder(self)
    dragOrigin = panel.convertPoint(toScreen: event.locationInWindow)
    dragFrame = panel.frame
    NSCursor.closedHand.set()
  }

  override func mouseDragged(with event: NSEvent) {
    guard let panel = panel, let origin = dragOrigin, let originalFrame = dragFrame else { return }
    let current = panel.convertPoint(toScreen: event.locationInWindow)
    panel.setFrameOrigin(NSPoint(x: originalFrame.minX + current.x - origin.x,
      y: originalFrame.minY + current.y - origin.y))
  }

  override func mouseUp(with event: NSEvent) {
    dragOrigin = nil
    dragFrame = nil
    NSCursor.openHand.set()
  }

  override func otherMouseDown(with event: NSEvent) {
    if event.buttonNumber == 2 { panel?.resetImage() }
  }

  override func scrollWheel(with event: NSEvent) {
    guard let panel = panel, abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX), event.scrollingDeltaY != 0 else { return }
    let amount = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY / 10 : event.scrollingDeltaY
    if event.modifierFlags.contains(.command) { panel.adjustOpacity(amount * 0.05) }
    else {
      let factor = pow(1.1, max(-10, min(10, amount)))
      // 无窗口的 Cocoa 滚轮事件使用屏幕坐标；普通窗口事件使用窗口坐标。
      let anchor = event.window == nil ? event.locationInWindow : panel.convertPoint(toScreen: event.locationInWindow)
      panel.setScale(panel.scale * factor, anchor: anchor)
    }
  }

  override func keyDown(with event: NSEvent) {
    guard let panel = panel else { return }
    let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
    if event.modifierFlags.contains(.command) {
      if key == "c" { panel.performAction("copy"); return }
      if key == "s" { panel.performAction("save"); return }
      if key == "w" { panel.close(); return }
    }
    switch event.keyCode {
    case 53: if event.modifierFlags.contains(.shift) { panel.close() } else { panel.hidePin() }
    case 123, 124, 125, 126:
      let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
      let dx: CGFloat = event.keyCode == 123 ? -step : event.keyCode == 124 ? step : 0
      let dy: CGFloat = event.keyCode == 125 ? -step : event.keyCode == 126 ? step : 0
      panel.setFrameOrigin(NSPoint(x: panel.frame.minX + dx, y: panel.frame.minY + dy))
    default:
      switch key {
      case "1": panel.performAction("rotate_right")
      case "2": panel.performAction("rotate_left")
      case "3": panel.performAction("flip_horizontal")
      case "4": panel.performAction("flip_vertical")
      case "0": panel.performAction("actual_size")
      case "9": panel.performAction("fit_screen")
      case "+", "=": panel.setScale(panel.scale * 1.1)
      case "-": panel.setScale(panel.scale / 1.1)
      default: super.keyDown(with: event)
      }
    }
  }

  override func rightMouseDown(with event: NSEvent) {
    guard let panel = panel else { return }
    panel.makeKey()
    panel.makeFirstResponder(self)
    NSMenu.popUpContextMenu(makeMenu(), with: event, for: self)
  }

  private func makeMenu() -> NSMenu {
    let menu = NSMenu()
    for group in [["copy", "save"], ["actual_size", "fit_screen"],
      ["rotate_left", "rotate_right", "flip_horizontal", "flip_vertical"],
      ["opacity", "click_through"], ["hide", "close"]] {
      if !menu.items.isEmpty { menu.addItem(.separator()) }
      for action in group {
        let item = menu.addItem(withTitle: NativeStrings.text("pin.\(action)"),
          action: action == "opacity" ? nil : #selector(menuAction(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = action
        if action == "click_through" { item.state = panel?.ignoresMouseEvents == true ? .on : .off }
        if action == "opacity" {
          let submenu = NSMenu()
          for percent in [100, 90, 75, 50, 25, 10] {
            let option = submenu.addItem(withTitle: "\(percent)%", action: #selector(opacityAction(_:)), keyEquivalent: "")
            option.target = self
            option.tag = percent
            option.state = abs((panel?.alphaValue ?? 1) * 100 - CGFloat(percent)) < 0.5 ? .on : .off
          }
          item.submenu = submenu
        }
      }
    }
    return menu
  }

  @objc private func menuAction(_ sender: NSMenuItem) {
    if let action = sender.representedObject as? String { panel?.performAction(action) }
  }
  @objc private func opacityAction(_ sender: NSMenuItem) { panel?.alphaValue = CGFloat(sender.tag) / 100 }
}
