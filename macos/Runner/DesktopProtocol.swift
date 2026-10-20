import Cocoa
import FlutterMacOS

// Conversion to private AppKit view models; channel values are generated types.
extension CaptureTool {
  var name: String {
    switch self {
    case .picker: return "picker"
    case .rectangle: return "rectangle"
    case .horizontal: return "horizontal"
    case .vertical: return "vertical"
    case .cross: return "cross"
    case .screenshot: return "screenshot"
    }
  }
  init?(name: String) {
    switch name {
    case "picker": self = .picker
    case "rectangle": self = .rectangle
    case "horizontal": self = .horizontal
    case "vertical": self = .vertical
    case "cross": self = .cross
    case "screenshot": self = .screenshot
    default: return nil
    }
  }
}
extension EventKind {
  var name: String {
    switch self {
    case .activate: return "activate"
    case .permissionChanged: return "permissionChanged"
    case .shortcutRecorded: return "shortcutRecorded"
    case .cancelled: return "cancelled"
    case .continuousChanged: return "continuousChanged"
    case .pinDrag: return "pinDrag"
    case .copyMeasurement: return "copyMeasurement"
    case .editPins: return "editPins"
    case .selectPin: return "selectPin"
    case .deletePin: return "deletePin"
    case .undoPins: return "undoPins"
    case .redoPins: return "redoPins"
    case .exportPins: return "exportPins"
    case .modeChanged: return "modeChanged"
    case .scroll: return "scroll"
    case .nudge: return "nudge"
    case .confirm: return "confirm"
    case .clearPins: return "clearPins"
    case .pointer: return "pointer"
    }
  }
  init?(name: String) {
    switch name {
    case "activate": self = .activate
    case "permissionChanged": self = .permissionChanged
    case "shortcutRecorded": self = .shortcutRecorded
    case "cancelled": self = .cancelled
    case "continuousChanged": self = .continuousChanged
    case "pinDrag": self = .pinDrag
    case "copyMeasurement": self = .copyMeasurement
    case "editPins": self = .editPins
    case "selectPin": self = .selectPin
    case "deletePin": self = .deletePin
    case "undoPins": self = .undoPins
    case "redoPins": self = .redoPins
    case "exportPins": self = .exportPins
    case "modeChanged": self = .modeChanged
    case "scroll": self = .scroll
    case "nudge": self = .nudge
    case "confirm": self = .confirm
    case "clearPins": self = .clearPins
    case "pointer": self = .pointer
    default: return nil
    }
  }
}
extension InputPhase {
  var name: String {
    switch self {
    case .move: return "move"
    case .down: return "down"
    case .drag: return "drag"
    case .up: return "up"
    case .start: return "start"
    case .update: return "update"
    case .end: return "end"
    }
  }
  init?(name: String) {
    switch name {
    case "move": self = .move
    case "down": self = .down
    case "drag": self = .drag
    case "up": self = .up
    case "start": self = .start
    case "update": self = .update
    case "end": self = .end
    default: return nil
    }
  }
}
extension MouseButton {
  var name: String {
    switch self {
    case .primary: return "primary"
    case .secondary: return "secondary"
    case .middle: return "middle"
    }
  }
  init?(name: String) {
    switch name {
    case "primary": self = .primary
    case "secondary": self = .secondary
    case "middle": self = .middle
    default: return nil
    }
  }
}
extension PixelBounds {
  var local: [String: Any] {
    var data: [String: Any] = [:]
    data["left"] = Int(left)
    data["top"] = Int(top)
    data["right"] = Int(right)
    data["bottom"] = Int(bottom)
    return data
  }
}
extension NativeChord {
  var local: [String: Any] {
    var data: [String: Any] = [:]
    data["key"] = key
    data["meta"] = meta
    data["control"] = control
    data["alt"] = alt
    data["shift"] = shift
    return data
  }
}
extension NativeBindings {
  var local: [String: Any] {
    var data: [String: Any] = [:]
    data["picker"] = picker.local
    data["ruler"] = ruler.local
    data["screenshot"] = screenshot.local
    return data
  }
}
extension MeasurementPin {
  var local: [String: Any] {
    var data: [String: Any] = [:]
    data["id"] = Int(id)
    data["displayId"] = NSNumber(value: displayId)
    data["rect"] = rect.local
    data["label"] = label
    return data
  }
}
extension OverlayState {
  var local: [String: Any] {
    var data: [String: Any] = [:]
    data["sessionId"] = Int(sessionId)
    data["tool"] = tool.name
    data["tolerance"] = Int(tolerance)
    data["zoom"] = Int(zoom)
    data["continuous"] = continuous
    data["pickerActions"] = pickerActions
    data["capturePurpose"] = capturePurpose
    data["pickedCount"] = Int(pickedCount)
    if let selectedPin = selectedPin { data["selectedPin"] = Int(selectedPin) }
    data["editingPins"] = editingPins
    data["canUndoPins"] = canUndoPins
    data["canRedoPins"] = canRedoPins
    data["pinned"] = pinned.map { $0.local }
    if let displayId = displayId { data["displayId"] = NSNumber(value: displayId) }
    if let x = x { data["x"] = x }
    if let y = y { data["y"] = y }
    if let label = label { data["label"] = label }
    if let color = color { data["color"] = [Int(color.red), Int(color.green), Int(color.blue)] }
    if let rect = rect { data["rect"] = rect.local }
    if let keyboard = keyboard { data["keyboard"] = keyboard }
    if let anchored = anchored { data["anchored"] = anchored }
    return data
  }
}
func nativeEvent(_ d: [String: Any]) -> NativeEvent {
  // All inputs originate in the native overlay; unknown names are programmer errors.
  var e = NativeEvent(kind: EventKind(name: d["type"] as! String)!)
  e.sessionId = (d["sessionId"] as? NSNumber)?.int64Value
  e.displayId = (d["displayId"] as? NSNumber)?.int64Value
  if let v = d["tool"] as? String { e.tool = CaptureTool(name: v) }
  e.permission = d["permission"] as? Bool
  if let v = d["chord"] as? [String: Any] {
    e.chord = NativeChord(key: v["key"] as! String, meta: v["meta"] as? Bool ?? false,
      control: v["control"] as? Bool ?? false, alt: v["alt"] as? Bool ?? false, shift: v["shift"] as? Bool ?? false)
  }
  e.x = (d["x"] as? NSNumber)?.doubleValue
  e.y = (d["y"] as? NSNumber)?.doubleValue
  if let v = d["phase"] as? String { e.phase = InputPhase(name: v) }
  if let v = d["button"] as? String { e.button = MouseButton(name: v) }
  e.keep = d["keep"] as? Bool
  e.keyboard = d["keyboard"] as? Bool
  e.enabled = d["enabled"] as? Bool
  e.id = (d["id"] as? NSNumber)?.int64Value
  e.handle = d["handle"] as? String
  e.dx = (d["dx"] as? NSNumber)?.doubleValue
  e.dy = (d["dy"] as? NSNumber)?.doubleValue
  e.resize = d["resize"] as? Bool
  e.steps = (d["steps"] as? NSNumber)?.int64Value
  e.save = d["save"] as? Bool
  return e
}
