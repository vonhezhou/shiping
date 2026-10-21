import 'dart:math' as math;

import 'pixel_frame.dart';

enum RulerMode { rectangle, horizontal, vertical, cross }

class PixelRect {
  const PixelRect({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  }) : assert(right >= left),
       assert(bottom >= top);
  factory PixelRect.fromPoints(PixelPoint a, PixelPoint b) => PixelRect(
    left: math.min(a.x, b.x),
    top: math.min(a.y, b.y),
    right: math.max(a.x, b.x),
    bottom: math.max(a.y, b.y),
  );
  final int left;
  final int top;
  final int right;
  final int bottom;
  int get width => right - left;
  int get height => bottom - top;
  Map<String, int> toJson() => {
    'left': left,
    'top': top,
    'right': right,
    'bottom': bottom,
  };
}

class RulerMeasurement {
  const RulerMeasurement({
    required this.rect,
    required this.logicalWidth,
    required this.logicalHeight,
    required this.mode,
  });
  factory RulerMeasurement.fromRect(
    PixelFrame frame,
    PixelRect rect,
    RulerMode mode,
  ) => RulerMeasurement(
    rect: rect,
    logicalWidth: rect.width / frame.scaleX,
    logicalHeight: rect.height / frame.scaleY,
    mode: mode,
  );
  final PixelRect rect;
  final double logicalWidth;
  final double logicalHeight;
  final RulerMode mode;

  String get pixelLabel => switch (mode) {
    RulerMode.horizontal => '${rect.width} px',
    RulerMode.vertical => '${rect.height} px',
    _ => '${rect.width} × ${rect.height} px',
  };
  String get pointLabel => switch (mode) {
    RulerMode.horizontal => '${_number(logicalWidth)} pt',
    RulerMode.vertical => '${_number(logicalHeight)} pt',
    _ => '${_number(logicalWidth)} × ${_number(logicalHeight)} pt',
  };
  String get label => '$pixelLabel · $pointLabel';
  static String _number(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
}

/// Measures uninterrupted spans relative to the seed, not neighbouring pixels.
class EdgeDetector {
  static RulerMeasurement measure(
    PixelFrame frame,
    int x,
    int y,
    RulerMode mode, {
    int tolerance = 16,
  }) {
    RangeError.checkValueInInterval(tolerance, 0, 255, 'tolerance');
    if (mode == RulerMode.rectangle) {
      throw ArgumentError('Rectangle requires a drag');
    }
    final seed = frame.pixelAt(x, y);
    bool matches(int px, int py) {
      final i = frame.byteIndex(px, py);
      return (frame.rgba[i] - seed.r).abs() <= tolerance &&
          (frame.rgba[i + 1] - seed.g).abs() <= tolerance &&
          (frame.rgba[i + 2] - seed.b).abs() <= tolerance;
    }

    var left = x;
    var right = x + 1;
    var top = y;
    var bottom = y + 1;
    if (mode != RulerMode.vertical) {
      while (left > 0 && matches(left - 1, y)) {
        left--;
      }
      while (right < frame.width && matches(right, y)) {
        right++;
      }
    }
    if (mode != RulerMode.horizontal) {
      while (top > 0 && matches(x, top - 1)) {
        top--;
      }
      while (bottom < frame.height && matches(x, bottom)) {
        bottom++;
      }
    }
    return RulerMeasurement.fromRect(
      frame,
      PixelRect(left: left, top: top, right: right, bottom: bottom),
      mode,
    );
  }
}

/// Move as a whole or resize named edges; preserve at least one screenshot pixel.
PixelRect transformAnnotation(
  PixelRect rect,
  int dx,
  int dy,
  int width,
  int height, {
  String handle = 'move',
}) {
  if (handle == 'move') {
    final x = dx.clamp(-rect.left, width - rect.right);
    final y = dy.clamp(-rect.top, height - rect.bottom);
    return PixelRect(
      left: rect.left + x,
      top: rect.top + y,
      right: rect.right + x,
      bottom: rect.bottom + y,
    );
  }
  final left = handle.contains('w')
      ? (rect.left + dx).clamp(0, rect.right - 1)
      : rect.left;
  final right = handle.contains('e')
      ? (rect.right + dx).clamp(rect.left + 1, width)
      : rect.right;
  final top = handle.contains('n')
      ? (rect.top + dy).clamp(0, rect.bottom - 1)
      : rect.top;
  final bottom = handle.contains('s')
      ? (rect.bottom + dy).clamp(rect.top + 1, height)
      : rect.bottom;
  return PixelRect(left: left, top: top, right: right, bottom: bottom);
}
