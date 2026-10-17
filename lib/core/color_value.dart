import 'dart:math' as math;

enum ColorFormat { hex, rgb, hsl }

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

  String get hsl {
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
    return 'hsl(${hue.round() % 360}, ${(saturation * 100).round()}%, ${(lightness * 100).round()}%)';
  }

  String formatted(ColorFormat format) => switch (format) {
    ColorFormat.hex => hex,
    ColorFormat.rgb => rgb,
    ColorFormat.hsl => hsl,
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
