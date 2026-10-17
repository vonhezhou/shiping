import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fruler/core/core.dart';

PixelFrame frame(
  int width,
  int height,
  List<RgbColor> colors, {
  double scale = 1,
}) => PixelFrame(
  width: width,
  height: height,
  rgba: Uint8List.fromList([
    for (final c in colors) ...[c.r, c.g, c.b, 255],
  ]),
  logicalWidth: width / scale,
  logicalHeight: height / scale,
);

void main() {
  group('颜色格式', () {
    test('HEX 保留前导零，RGB 保持通道顺序', () {
      const c = RgbColor(1, 15, 255);
      expect(c.hex, '#010FFF');
      expect(c.rgb, 'rgb(1, 15, 255)');
      expect(RgbColor.fromJson(c.toJson()), c);
    });
    test('HSL 覆盖主色和无彩色', () {
      expect(const RgbColor(255, 0, 0).hsl, 'hsl(0, 100%, 50%)');
      expect(const RgbColor(0, 255, 0).hsl, 'hsl(120, 100%, 50%)');
      expect(const RgbColor(0, 0, 255).hsl, 'hsl(240, 100%, 50%)');
      expect(const RgbColor(255, 0, 255).hsl, 'hsl(300, 100%, 50%)');
      expect(const RgbColor(0, 0, 0).hsl, 'hsl(0, 0%, 0%)');
      expect(const RgbColor(255, 255, 255).hsl, 'hsl(0, 0%, 100%)');
      expect(const RgbColor(128, 128, 128).hsl, 'hsl(0, 0%, 50%)');
    });
    test('损坏历史不能制造越界颜色', () {
      for (final data in [
        null,
        [0, 0],
        [-1, 0, 0],
        [256, 0, 0],
        [1.2, 0, 0],
      ]) {
        expect(() => RgbColor.fromJson(data), throwsFormatException);
      }
    });
  });

  group('像素和坐标', () {
    test('RGBA 行以左上为原点', () {
      final image = frame(2, 2, const [
        RgbColor(255, 0, 0),
        RgbColor(0, 255, 0),
        RgbColor(0, 0, 255),
        RgbColor(1, 2, 3),
      ]);
      expect(image.pixelAt(0, 0), const RgbColor(255, 0, 0));
      expect(image.pixelAt(0, 1), const RgbColor(0, 0, 255));
      expect(image.pixelAt(1, 1), const RgbColor(1, 2, 3));
      expect(() => image.pixelAt(2, 0), throwsRangeError);
      expect(() => image.pixelAt(0, -1), throwsRangeError);
    });
    test('Retina 和非整数缩放区分取样坐标与矩形外边界', () {
      final image = frame(
        6,
        3,
        List.filled(18, const RgbColor(0, 0, 0)),
        scale: 1.5,
      );
      expect(image.logicalToPixel(1, 1).x, 1);
      expect(image.logicalToPixel(99, 99).x, 5);
      expect(image.logicalToPixel(-1, -1).y, 0);
      expect(image.logicalToBoundary(4, 2).x, 6);
      expect(image.logicalToBoundary(4, 2).y, 3);
      final rect = PixelRect.fromPoints(
        const PixelPoint(6, 3),
        const PixelPoint(0, 0),
      );
      final result = RulerMeasurement.fromRect(
        image,
        rect,
        RulerMode.rectangle,
      );
      expect(result.rect.width, 6);
      expect(result.logicalWidth, 4);
      expect(result.logicalHeight, 2);
      expect(result.label, '6 × 3 px · 4 × 2 pt');
    });
    test('拒绝损坏的缓冲区与非法逻辑尺寸', () {
      expect(
        () => PixelFrame(
          width: 2,
          height: 2,
          rgba: Uint8List(8),
          logicalWidth: 2,
          logicalHeight: 2,
        ),
        throwsArgumentError,
      );
      expect(
        () => PixelFrame(
          width: 1,
          height: 1,
          rgba: Uint8List(4),
          logicalWidth: double.nan,
          logicalHeight: 1,
        ),
        throwsArgumentError,
      );
    });
  });

  group('自动边界', () {
    const black = RgbColor(0, 0, 0);
    const white = RgbColor(255, 255, 255);
    final image = frame(5, 5, [
      for (var y = 0; y < 5; y++)
        for (var x = 0; x < 5; x++)
          x >= 1 && x <= 3 && y >= 1 && y <= 3 ? white : black,
    ], scale: 2);
    test('半开边界精确覆盖完整连续区域', () {
      final result = EdgeDetector.measure(image, 2, 2, RulerMode.cross);
      expect(result.rect.toJson(), {
        'left': 1,
        'top': 1,
        'right': 4,
        'bottom': 4,
      });
      expect(result.logicalWidth, 1.5);
      expect(result.logicalHeight, 1.5);
    });
    test('横向和纵向模式只扫描相应方向', () {
      final horizontal = EdgeDetector.measure(
        image,
        2,
        2,
        RulerMode.horizontal,
      );
      final vertical = EdgeDetector.measure(image, 2, 2, RulerMode.vertical);
      expect(horizontal.rect.width, 3);
      expect(horizontal.rect.height, 1);
      expect(horizontal.label, '3 px · 1.5 pt');
      expect(vertical.rect.width, 1);
      expect(vertical.rect.height, 3);
    });
    test('每个通道相对种子比较，渐变不会累积漂移', () {
      final image = frame(5, 1, const [
        RgbColor(0, 0, 0),
        RgbColor(10, 0, 0),
        RgbColor(20, 0, 0),
        RgbColor(30, 0, 0),
        RgbColor(40, 0, 0),
      ]);
      final result = EdgeDetector.measure(
        image,
        2,
        0,
        RulerMode.horizontal,
        tolerance: 10,
      );
      expect(result.rect.left, 1);
      expect(result.rect.right, 4);
    });
    test('单像素与屏幕边缘没有越界或少算一像素', () {
      final single = frame(1, 1, [white]);
      expect(EdgeDetector.measure(single, 0, 0, RulerMode.cross).rect.width, 1);
      expect(EdgeDetector.measure(image, 0, 0, RulerMode.cross).rect.width, 5);
      expect(
        () => EdgeDetector.measure(
          single,
          0,
          0,
          RulerMode.horizontal,
          tolerance: -1,
        ),
        throwsRangeError,
      );
    });
  });
}
