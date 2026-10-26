import 'package:flutter/foundation.dart';

import '../core/ruler.dart';

/// 屏幕几何的展示单位；采样、选区和导出始终保留截图像素。
abstract final class ScreenUnits {
  static bool get usesPoints => defaultTargetPlatform == TargetPlatform.macOS;
  static String get symbol => usesPoints ? 'pt' : 'px';

  static String measurement(RulerMeasurement value) =>
      usesPoints ? value.pointLabel : value.pixelLabel;

  static String dimensions(
    int width,
    int height, {
    required double scaleX,
    required double scaleY,
  }) => '${_axis(width, scaleX)} × ${_axis(height, scaleY)} $symbol';

  static String position(
    int x,
    int y, {
    required double scaleX,
    required double scaleY,
  }) => 'X: ${_axis(x, scaleX)}  Y: ${_axis(y, scaleY)} $symbol';

  static String _axis(int pixels, double scale) {
    final value = usesPoints ? pixels / scale : pixels.toDouble();
    return value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toStringAsFixed(1);
  }
}
