import 'validation_exception.dart';

class ShortcutChord {
  const ShortcutChord({
    required this.key,
    this.meta = false,
    this.control = false,
    this.alt = false,
    this.shift = false,
  });

  final String key;
  final bool meta;
  final bool control;
  final bool alt;
  final bool shift;
  bool get isValid =>
      RegExp(r'^[A-Z0-9]$').hasMatch(key) &&
      (meta || control || alt) &&
      !(meta &&
          !control &&
          !alt &&
          (['Q', 'W', 'H', 'M', 'S', 'Z'].contains(key) ||
              (!shift && ['A', 'C', 'V', 'X', 'O'].contains(key)) ||
              (shift && ['3', '4', '5'].contains(key))));
  String get label => [
    if (control) '⌃',
    if (alt) '⌥',
    if (shift) '⇧',
    if (meta) '⌘',
    key,
  ].join(' ');
  Map<String, Object> toJson() => {
    'key': key,
    'meta': meta,
    'control': control,
    'alt': alt,
    'shift': shift,
  };
  factory ShortcutChord.fromJson(Object? json) {
    if (json is! Map || json['key'] is! String) {
      throw const ValidationException('shortcut');
    }
    final chord = ShortcutChord(
      key: json['key'] as String,
      meta: json['meta'] == true,
      control: json['control'] == true,
      alt: json['alt'] == true,
      shift: json['shift'] == true,
    );
    if (!chord.isValid) throw const ValidationException('shortcut');
    return chord;
  }
  @override
  bool operator ==(Object other) =>
      other is ShortcutChord &&
      key == other.key &&
      meta == other.meta &&
      control == other.control &&
      alt == other.alt &&
      shift == other.shift;
  @override
  int get hashCode => Object.hash(key, meta, control, alt, shift);
}

class ShortcutBindings {
  const ShortcutBindings({
    required this.picker,
    required this.ruler,
    this.screenshot = const ShortcutChord(key: 'X', meta: true, shift: true),
    this.pinClipboard = const ShortcutChord(key: 'T', meta: true, shift: true),
    this.togglePins = const ShortcutChord(key: 'V', meta: true, shift: true),
  });
  static const defaults = ShortcutBindings(
    picker: ShortcutChord(key: 'C', meta: true, shift: true),
    ruler: ShortcutChord(key: 'R', meta: true, shift: true),
  );
  final ShortcutChord picker;
  final ShortcutChord ruler;
  final ShortcutChord screenshot;
  final ShortcutChord pinClipboard;
  final ShortcutChord togglePins;
  bool get isValid {
    final chords = [picker, ruler, screenshot, pinClipboard, togglePins];
    return chords.every((chord) => chord.isValid) &&
        chords.toSet().length == chords.length;
  }

  Map<String, Object> toJson() => {
    'picker': picker.toJson(),
    'ruler': ruler.toJson(),
    'screenshot': screenshot.toJson(),
    'pinClipboard': pinClipboard.toJson(),
    'togglePins': togglePins.toJson(),
  };
  factory ShortcutBindings.fromJson(Object? json) {
    if (json is! Map) throw const ValidationException('shortcutBindings');
    final picker = ShortcutChord.fromJson(json['picker']);
    final ruler = ShortcutChord.fromJson(json['ruler']);
    // 旧配置缺少新入口时，保留已有组合并从未占用的键中补齐。
    final used = {picker, ruler};
    for (final key in ['screenshot', 'pinClipboard', 'togglePins']) {
      if (json[key] != null) used.add(ShortcutChord.fromJson(json[key]));
    }
    ShortcutChord read(String name, List<String> preferred) {
      if (json[name] != null) return ShortcutChord.fromJson(json[name]);
      final chord =
          [...preferred, ...'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'.split('')]
              .map((key) => ShortcutChord(key: key, meta: true, shift: true))
              .firstWhere((chord) => chord.isValid && !used.contains(chord));
      used.add(chord);
      return chord;
    }

    final value = ShortcutBindings(
      picker: picker,
      ruler: ruler,
      screenshot: read('screenshot', ['X', 'A', 'T']),
      pinClipboard: read('pinClipboard', ['T', 'P']),
      togglePins: read('togglePins', ['V', 'B']),
    );
    if (!value.isValid) throw const ValidationException('shortcutDuplicates');
    return value;
  }
}
