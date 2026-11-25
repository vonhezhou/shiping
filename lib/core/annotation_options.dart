import 'annotation.dart';

/// 标注工具的默认选项使用逻辑点保存，不随截图屏幕的像素倍率变化。
class AnnotationOptions {
  const AnnotationOptions({
    this.width = 3,
    this.fontSize = 24,
    this.fontFamily = Annotation.defaultFontFamily,
    this.filled = false,
    this.bold = false,
    this.italic = false,
    this.outlined = false,
    this.effectBrush = false,
    this.eraserBrush = false,
    this.effectStrength = 3,
  });

  static const groups = {
    'shape',
    'line',
    'pencil',
    'marker',
    'effect',
    'eraser',
    'text',
  };
  static String group(String tool) => switch (tool) {
    'rectangle' || 'ellipse' => 'shape',
    'arrow' => 'line',
    'mosaic' || 'blur' => 'effect',
    _ => tool,
  };
  factory AnnotationOptions.defaults(String tool) => AnnotationOptions(
    width: switch (group(tool)) {
      'marker' => 12,
      'effect' || 'eraser' => 24,
      _ => 3,
    },
  );

  final double width, fontSize;
  final String fontFamily;
  final bool filled, bold, italic, outlined, effectBrush, eraserBrush;
  final int effectStrength;

  AnnotationOptions copyWith({
    double? width,
    double? fontSize,
    String? fontFamily,
    bool? filled,
    bool? bold,
    bool? italic,
    bool? outlined,
    bool? effectBrush,
    bool? eraserBrush,
    int? effectStrength,
  }) => AnnotationOptions(
    width: width ?? this.width,
    fontSize: fontSize ?? this.fontSize,
    fontFamily: fontFamily ?? this.fontFamily,
    filled: filled ?? this.filled,
    bold: bold ?? this.bold,
    italic: italic ?? this.italic,
    outlined: outlined ?? this.outlined,
    effectBrush: effectBrush ?? this.effectBrush,
    eraserBrush: eraserBrush ?? this.eraserBrush,
    effectStrength: effectStrength ?? this.effectStrength,
  );

  Map<String, Object> toJson() => {
    'width': width,
    'fontSize': fontSize,
    'fontFamily': fontFamily,
    'filled': filled,
    'bold': bold,
    'italic': italic,
    'outlined': outlined,
    'effectBrush': effectBrush,
    'eraserBrush': eraserBrush,
    'effectStrength': effectStrength,
  };

  factory AnnotationOptions.fromJson(Object? value, {required String tool}) {
    final defaults = AnnotationOptions.defaults(tool);
    if (value is! Map) return defaults;
    double number(String key, double fallback, double min, double max) {
      final v = value[key];
      return v is num && v.isFinite && v >= min && v <= max
          ? v.toDouble()
          : fallback;
    }

    bool flag(String key) => value[key] is bool ? value[key] as bool : false;
    final family = value['fontFamily'];
    final strength = value['effectStrength'];
    return AnnotationOptions(
      width: number('width', defaults.width, 1, 80),
      fontSize: number('fontSize', defaults.fontSize, 8, 200),
      fontFamily:
          family is String && family.trim().isNotEmpty && family.length <= 256
          ? family
          : defaults.fontFamily,
      filled: flag('filled'),
      bold: flag('bold'),
      italic: flag('italic'),
      outlined: flag('outlined'),
      effectBrush: flag('effectBrush'),
      eraserBrush: flag('eraserBrush'),
      effectStrength: strength is int && strength >= 1 && strength <= 5
          ? strength
          : defaults.effectStrength,
    );
  }
}
