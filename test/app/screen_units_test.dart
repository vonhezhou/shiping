import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fruler/app/screen_units.dart';
import 'package:fruler/core/core.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('macOS 独立换算两轴、保留小数；Windows 保留截图像素', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    expect(
      ScreenUnits.dimensions(201, 122, scaleX: 2, scaleY: 1.5),
      '100.5 × 81.3 pt',
    );
    expect(
      ScreenUnits.position(321, 361, scaleX: 2, scaleY: 1.5),
      'X: 160.5  Y: 240.7 pt',
    );
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    expect(
      ScreenUnits.dimensions(201, 122, scaleX: 2, scaleY: 1.5),
      '201 × 122 px',
    );
    expect(
      ScreenUnits.position(321, 361, scaleX: 2, scaleY: 1.5),
      'X: 321  Y: 361 px',
    );
  });

  for (final mode in RulerMode.values) {
    test('测量模式使用平台单位且保留复制格式 $mode', () {
      final measurement = RulerMeasurement(
        rect: const PixelRect(left: 0, top: 0, right: 201, bottom: 122),
        logicalWidth: 100.5,
        logicalHeight: 122 / 1.5,
        mode: mode,
      );
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      expect(ScreenUnits.measurement(measurement), switch (mode) {
        RulerMode.horizontal => '100.5 pt',
        RulerMode.vertical => '81.3 pt',
        _ => '100.5 × 81.3 pt',
      });
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      expect(ScreenUnits.measurement(measurement), switch (mode) {
        RulerMode.horizontal => '201 px',
        RulerMode.vertical => '122 px',
        _ => '201 × 122 px',
      });
      expect(
        measurement.label,
        '${measurement.pixelLabel} · ${measurement.pointLabel}',
      );
    });
  }
}
