import 'dart:typed_data';

import 'color_value.dart';

class PixelPoint {
  const PixelPoint(this.x, this.y);
  final int x;
  final int y;
}

/// Packed sRGB RGBA, in rows starting at the display's top-left corner.
class PixelFrame {
  PixelFrame({
    required this.width,
    required this.height,
    required this.rgba,
    required this.logicalWidth,
    required this.logicalHeight,
  }) {
    if (width <= 0 ||
        height <= 0 ||
        rgba.length != width * height * 4 ||
        !logicalWidth.isFinite ||
        !logicalHeight.isFinite ||
        logicalWidth <= 0 ||
        logicalHeight <= 0) {
      throw ArgumentError('Invalid display frame');
    }
  }

  final int width;
  final int height;
  final Uint8List rgba;
  final double logicalWidth;
  final double logicalHeight;
  double get scaleX => width / logicalWidth;
  double get scaleY => height / logicalHeight;

  RgbColor pixelAt(int x, int y) {
    RangeError.checkValueInInterval(x, 0, width - 1, 'x');
    RangeError.checkValueInInterval(y, 0, height - 1, 'y');
    final index = (y * width + x) * 4;
    return RgbColor(rgba[index], rgba[index + 1], rgba[index + 2]);
  }

  PixelPoint logicalToPixel(double x, double y) {
    if (!x.isFinite || !y.isFinite) throw ArgumentError('Invalid coordinates');
    return PixelPoint(
      (x * scaleX).floor().clamp(0, width - 1),
      (y * scaleY).floor().clamp(0, height - 1),
    );
  }

  /// Rectangle endpoints may lie on the right/bottom outer edge.
  PixelPoint logicalToBoundary(double x, double y) => PixelPoint(
    (x * scaleX).round().clamp(0, width),
    (y * scaleY).round().clamp(0, height),
  );
}
