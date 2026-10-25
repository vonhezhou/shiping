// Maps below are local controller models, never channel payloads.
import '../core/core.dart';
import 'desktop.g.dart' as wire;

wire.NativeChord chordToWire(ShortcutChord c) => wire.NativeChord(
  key: c.key,
  meta: c.meta,
  control: c.control,
  alt: c.alt,
  shift: c.shift,
);
wire.PixelBounds boundsToWire(Object value) {
  final r = value as Map;
  return wire.PixelBounds(
    left: r['left'] as int,
    top: r['top'] as int,
    right: r['right'] as int,
    bottom: r['bottom'] as int,
  );
}

wire.MeasurementPin pinToWire(Map<String, Object?> p) => wire.MeasurementPin(
  id: p['id'] as int,
  displayId: p['displayId'] as int,
  rect: boundsToWire(p['rect']!),
  label: p['label'] as String,
);
wire.OverlayState overlayToWire(Map<String, Object?> d) {
  final color = d['color'] as List?;
  return wire.OverlayState(
    sessionId: d['sessionId'] as int,
    tool: wire.CaptureTool.values.byName(d['tool'] as String),
    tolerance: d['tolerance'] as int,
    zoom: d['zoom'] as int,
    continuous: d['continuous'] as bool,
    pickerActions: d['pickerActions'] as String,
    capturePurpose: d['capturePurpose'] as String,
    pickedCount: d['pickedCount'] as int,
    selectedPin: d['selectedPin'] as int?,
    editingPins: d['editingPins'] as bool,
    canUndoPins: d['canUndoPins'] as bool,
    canRedoPins: d['canRedoPins'] as bool,
    pinned: (d['pinned'] as List)
        .map((p) => pinToWire(Map<String, Object?>.from(p as Map)))
        .toList(),
    displayId: d['displayId'] as int?,
    x: (d['x'] as num?)?.toDouble(),
    y: (d['y'] as num?)?.toDouble(),
    label: d['label'] as String?,
    color: color == null
        ? null
        : wire.NativeColor(
            red: color[0] as int,
            green: color[1] as int,
            blue: color[2] as int,
          ),
    rect: d['rect'] == null ? null : boundsToWire(d['rect']!),
    keyboard: d['keyboard'] as bool?,
    anchored: d['anchored'] as bool?,
    colorOutputName: d['colorOutputName'] as String?,
  );
}

Map<Object?, Object?> eventFromWire(wire.NativeEvent e) => {
  'message': e.message,
  'type': e.kind.name,
  'sessionId': e.sessionId,
  'displayId': e.displayId,
  'tool': e.tool?.name,
  'permission': e.permission,
  'chord': e.chord == null
      ? null
      : {
          'key': e.chord!.key,
          'meta': e.chord!.meta,
          'control': e.chord!.control,
          'alt': e.chord!.alt,
          'shift': e.chord!.shift,
        },
  'x': e.x,
  'y': e.y,
  'phase': e.phase?.name,
  'button': e.button?.name,
  'keep': e.keep,
  'keyboard': e.keyboard,
  'enabled': e.enabled,
  'id': e.id,
  'handle': e.handle,
  'dx': e.kind == wire.EventKind.nudge ? e.dx?.toInt() : e.dx,
  'dy': e.kind == wire.EventKind.nudge ? e.dy?.toInt() : e.dy,
  'resize': e.resize,
  'steps': e.steps,
  'tolerance': e.tolerance,
  'save': e.save,
  'suggestedRect': e.suggestedRect == null
      ? null
      : {
          'left': e.suggestedRect!.left,
          'top': e.suggestedRect!.top,
          'right': e.suggestedRect!.right,
          'bottom': e.suggestedRect!.bottom,
        },
};
