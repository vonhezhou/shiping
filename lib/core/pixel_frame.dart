import 'dart:typed_data';

import 'color_value.dart';

class PixelPoint {
  const PixelPoint(this.x, this.y);
  final int x;
  final int y;
}

/// sRGB RGBA view. Rows may include padding; all views retain the full buffer.
class PixelFrame {
  PixelFrame({
    required this.width,
    required this.height,
    required this.rgba,
    required this.logicalWidth,
    required this.logicalHeight,
    int? rowBytes,
  }) : rowBytes = rowBytes ?? width * 4,
       originX = 0,
       originY = 0,
       _source = null {
    if (width <= 0 ||
        height <= 0 ||
        this.rowBytes < width * 4 ||
        this.rowBytes % 4 != 0 ||
        rgba.length != this.rowBytes * height ||
        !logicalWidth.isFinite ||
        !logicalHeight.isFinite ||
        logicalWidth <= 0 ||
        logicalHeight <= 0) {
      throw ArgumentError('Invalid display frame');
    }
  }

  PixelFrame._view(
    PixelFrame parent,
    int left,
    int top,
    this.width,
    this.height,
  ) : rgba = parent.rgba,
      rowBytes = parent.rowBytes,
      originX = parent.originX + left,
      originY = parent.originY + top,
      logicalWidth = width / parent.scaleX,
      logicalHeight = height / parent.scaleY,
      _source = parent.source;

  PixelFrame view({
    required int left,
    required int top,
    required int width,
    required int height,
  }) {
    if (left < 0 ||
        top < 0 ||
        width <= 0 ||
        height <= 0 ||
        left + width > this.width ||
        top + height > this.height) {
      throw ArgumentError('Invalid pixel view');
    }
    return PixelFrame._view(this, left, top, width, height);
  }

  final PixelFrame? _source;
  PixelFrame get source => _source ?? this;
  final int rowBytes, originX, originY;
  int get offsetBytes => originY * rowBytes + originX * 4;
  int byteIndex(int x, int y) => offsetBytes + y * rowBytes + x * 4;

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
    final index = byteIndex(x, y);
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
