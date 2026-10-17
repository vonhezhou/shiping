import 'dart:math' as math;

import 'color_value.dart';

/// WCAG 2.x sRGB contrast; use the unrounded ratio for threshold comparisons.
class ColorContrast {
  ColorContrast(this.foreground, this.background);
  final RgbColor foreground;
  final RgbColor background;
  static double luminance(RgbColor color) {
    double linear(int channel) {
      final c = channel / 255;
      return c <= .04045
          ? c / 12.92
          : math.pow((c + .055) / 1.055, 2.4).toDouble();
    }

    return .2126 * linear(color.r) +
        .7152 * linear(color.g) +
        .0722 * linear(color.b);
  }

  double get ratio {
    final a = luminance(foreground), b = luminance(background);
    return (math.max(a, b) + .05) / (math.min(a, b) + .05);
  }

  bool get normalAA => ratio >= 4.5;
  bool get normalAAA => ratio >= 7;
  bool get largeAA => ratio >= 3;
  bool get largeAAA => ratio >= 4.5;
}
