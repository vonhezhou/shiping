import 'dart:math' as math;

enum ColorFormat {
  hex,
  rgb,
  hsl,
  flutter,
  css;

  String get label => switch (this) {
    ColorFormat.flutter => 'Flutter',
    ColorFormat.css => 'CSS',
    _ => name.toUpperCase(),
  };
}

class RgbColor {
  const RgbColor(this.r, this.g, this.b)
    : assert(r >= 0 && r <= 255),
      assert(g >= 0 && g <= 255),
      assert(b >= 0 && b <= 255);

  final int r;
  final int g;
  final int b;

  String get hex =>
      '#${[r, g, b].map((v) => v.toRadixString(16).padLeft(2, '0')).join().toUpperCase()}';
  String get rgb => 'rgb($r, $g, $b)';

  ({double h, double s, double l}) get hslValues {
    final red = r / 255;
    final green = g / 255;
    final blue = b / 255;
    final max = math.max(red, math.max(green, blue));
    final min = math.min(red, math.min(green, blue));
    final delta = max - min;
    final lightness = (max + min) / 2;
    var hue = 0.0;
    var saturation = 0.0;
    if (delta != 0) {
      saturation = delta / (1 - (2 * lightness - 1).abs());
      if (max == red) {
        hue = ((green - blue) / delta) % 6;
      } else if (max == green) {
        hue = (blue - red) / delta + 2;
      } else {
        hue = (red - green) / delta + 4;
      }
      hue = (hue * 60) % 360;
    }
    return (h: hue, s: saturation, l: lightness);
  }

  String get hsl {
    final value = hslValues;
    return 'hsl(${value.h.round() % 360}, ${(value.s * 100).round()}%, ${(value.l * 100).round()}%)';
  }

  factory RgbColor.parseHex(String text) {
    var hex = text.trim().replaceFirst(RegExp(r'^#'), '');
    if (RegExp(r'^[0-9a-fA-F]{3}$').hasMatch(hex)) {
      hex = hex.split('').map((c) => '$c$c').join();
    }
    if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(hex)) {
      throw const FormatException('请输入 3 位或 6 位 HEX 颜色');
    }
    final value = int.parse(hex, radix: 16);
    return RgbColor((value >> 16) & 255, (value >> 8) & 255, value & 255);
  }
  factory RgbColor.fromHsl(double hue, double saturation, double lightness) {
    if (!hue.isFinite ||
        !saturation.isFinite ||
        !lightness.isFinite ||
        saturation < 0 ||
        saturation > 1 ||
        lightness < 0 ||
        lightness > 1) {
      throw const FormatException('Invalid HSL value');
    }
    final h = (hue % 360) / 60;
    final c = (1 - (2 * lightness - 1).abs()) * saturation;
    final x = c * (1 - (h % 2 - 1).abs());
    final m = lightness - c / 2;
    final (r, g, b) = switch (h.floor()) {
      0 => (c, x, 0.0),
      1 => (x, c, 0.0),
      2 => (0.0, c, x),
      3 => (0.0, x, c),
      4 => (x, 0.0, c),
      _ => (c, 0.0, x),
    };
    return RgbColor(
      ((r + m) * 255).round().clamp(0, 255),
      ((g + m) * 255).round().clamp(0, 255),
      ((b + m) * 255).round().clamp(0, 255),
    );
  }

  String formatted(ColorFormat format) => switch (format) {
    ColorFormat.hex => hex,
    ColorFormat.rgb => rgb,
    ColorFormat.hsl => hsl,
    ColorFormat.flutter => 'Color(0xFF${hex.substring(1)})',
    ColorFormat.css => 'color: $hex;',
  };

  List<int> toJson() => [r, g, b];

  factory RgbColor.fromJson(Object? value) {
    if (value is! List ||
        value.length != 3 ||
        value.any((v) => v is! int || v < 0 || v > 255)) {
      throw const FormatException('Invalid RGB value');
    }
    return RgbColor(value[0] as int, value[1] as int, value[2] as int);
  }

  @override
  bool operator ==(Object other) =>
      other is RgbColor && r == other.r && g == other.g && b == other.b;
  @override
  int get hashCode => Object.hash(r, g, b);
}
