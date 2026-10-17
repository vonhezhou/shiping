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
      RegExp(r'^[A-Z0-9]$').hasMatch(key) && (meta || control || alt);
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
      throw const FormatException('Invalid shortcut');
    }
    final chord = ShortcutChord(
      key: json['key'] as String,
      meta: json['meta'] == true,
      control: json['control'] == true,
      alt: json['alt'] == true,
      shift: json['shift'] == true,
    );
    if (!chord.isValid) throw const FormatException('Invalid shortcut');
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
  const ShortcutBindings({required this.picker, required this.ruler});
  static const defaults = ShortcutBindings(
    picker: ShortcutChord(key: 'C', meta: true, shift: true),
    ruler: ShortcutChord(key: 'R', meta: true, shift: true),
  );
  final ShortcutChord picker;
  final ShortcutChord ruler;
  bool get isValid => picker.isValid && ruler.isValid && picker != ruler;
  Map<String, Object> toJson() => {
    'picker': picker.toJson(),
    'ruler': ruler.toJson(),
  };
  factory ShortcutBindings.fromJson(Object? json) {
    if (json is! Map) throw const FormatException('Invalid bindings');
    final value = ShortcutBindings(
      picker: ShortcutChord.fromJson(json['picker']),
      ruler: ShortcutChord.fromJson(json['ruler']),
    );
    if (!value.isValid) throw const FormatException('Duplicate shortcuts');
    return value;
  }
}
