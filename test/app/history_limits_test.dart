import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fruler/app/app_controller.dart';
import 'package:fruler/core/core.dart';

import '../fake_desktop.dart';

MeasurementRecord record(int index, {bool favorite = false}) =>
    MeasurementRecord(
      name: 'record-$index',
      favorite: favorite,
      measurement: const RulerMeasurement(
        rect: PixelRect(left: 0, top: 0, right: 10, bottom: 20),
        logicalWidth: 10,
        logicalHeight: 20,
        mode: RulerMode.rectangle,
      ),
      createdAt: DateTime.utc(2026, 1, 1).subtract(Duration(minutes: index)),
      displayName: 'display',
    );

void main() {
  for (final favorite in [false, true]) {
    test('旧尺子历史恢复即限制总量，收藏也不能绕过上限 favorite=$favorite', () async {
      final desktop = FakeDesktop()
        ..saved = jsonEncode({
          'version': 1,
          'measurements': [
            for (var i = 0; i < 100; i++)
              record(i, favorite: favorite).toJson(),
          ],
        });
      final controller = AppController(desktop);
      addTearDown(controller.dispose);
      addTearDown(desktop.input.close);
      await controller.initialize();
      expect(controller.measurements, hasLength(32));
      expect(controller.measurements.first.name, 'record-0');
      expect(controller.measurements.last.name, 'record-31');
      await Future<void>.delayed(Duration.zero);
      expect(jsonDecode(desktop.saved!)['measurements'], hasLength(32));
    });
  }

  test('调低上限立即淘汰最旧非收藏，全部收藏时仍保持有界', () async {
    final desktop = FakeDesktop()
      ..saved = jsonEncode({
        'version': 1,
        'measurementHistoryLimit': 128,
        'measurements': [
          for (var i = 0; i < 100; i++) record(i, favorite: i >= 90).toJson(),
        ],
      });
    final controller = AppController(desktop);
    addTearDown(controller.dispose);
    addTearDown(desktop.input.close);
    await controller.initialize();
    controller.setMeasurementHistoryLimit(16);
    expect(controller.measurements, hasLength(16));
    expect(controller.measurements.take(6).map((r) => r.name), [
      for (var i = 0; i < 6; i++) 'record-$i',
    ]);
    expect(controller.measurements.where((r) => r.favorite), hasLength(10));
    expect(jsonDecode(desktop.saved!)['measurementHistoryLimit'], 16);
    final restored = AppController(desktop);
    addTearDown(restored.dispose);
    await restored.initialize();
    expect(
      restored.measurements.map((r) => r.name),
      controller.measurements.map((r) => r.name),
    );
    expect(restored.measurementHistoryLimit, 16);
  });

  test('取色去重保留最新顺序，修改上限及运行中新增都受限', () async {
    final desktop = FakeDesktop();
    final controller = AppController(desktop);
    addTearDown(controller.dispose);
    addTearDown(desktop.input.close);
    await controller.initialize();
    controller.setColorHistoryLimit(16);
    for (var i = 0; i < 40; i++) {
      controller.addEditedColor(RgbColor(i, 0, 0));
    }
    expect(controller.colors, hasLength(16));
    expect(controller.colors.first, const RgbColor(39, 0, 0));
    expect(controller.colors.last, const RgbColor(24, 0, 0));
    controller.addEditedColor(const RgbColor(24, 0, 0));
    expect(controller.colors.first, const RgbColor(24, 0, 0));
    expect(controller.colors, hasLength(16));
    controller.setColorHistoryLimit(256);
    for (var i = 0; i < 300; i++) {
      controller.addEditedColor(RgbColor(i % 256, i ~/ 256, 0));
    }
    expect(controller.colors, hasLength(256));
    controller.setColorHistoryLimit(16);
    expect(controller.colors, hasLength(16));
    final restored = AppController(desktop);
    addTearDown(restored.dispose);
    await restored.initialize();
    expect(restored.colorHistoryLimit, 16);
    expect(restored.colors, controller.colors);
  });

  test('损坏或越界上限回退默认值，恢复时忽略坏颜色并继续填满有效历史', () async {
    final desktop = FakeDesktop()
      ..saved = jsonEncode({
        'colorHistoryLimit': 100000,
        'measurementHistoryLimit': 'unlimited',
        'colors': [
          for (var i = 0; i < 70; i++) null,
          for (var i = 0; i < 80; i++) [i, 0, 0],
        ],
      });
    final controller = AppController(desktop);
    addTearDown(controller.dispose);
    addTearDown(desktop.input.close);
    await controller.initialize();
    expect(controller.colors, hasLength(64));
    expect(controller.colors.first, const RgbColor(0, 0, 0));
    expect(controller.colors.last, const RgbColor(63, 0, 0));
    expect(controller.colorHistoryLimit, 64);
    expect(controller.measurementHistoryLimit, 32);
    final saved = desktop.saved;
    for (final invalid in [-1, 0, 1, 257, 100000]) {
      controller.setColorHistoryLimit(invalid);
      controller.setMeasurementHistoryLimit(invalid);
    }
    expect(desktop.saved, saved);
  });

  test('浮点上限回退默认值，不中断其余历史恢复', () async {
    final desktop = FakeDesktop()
      ..saved = jsonEncode({
        'colorHistoryLimit': 16.0,
        'measurementHistoryLimit': 32.0,
        'colors': [
          [1, 2, 3],
        ],
        'measurements': [record(0).toJson()],
      });
    final controller = AppController(desktop);
    addTearDown(controller.dispose);
    addTearDown(desktop.input.close);
    await controller.initialize();
    expect(controller.colorHistoryLimit, 64);
    expect(controller.measurementHistoryLimit, 32);
    expect(controller.colors.single, const RgbColor(1, 2, 3));
    expect(controller.measurements.single.name, 'record-0');
    expect(controller.notice, isNull);
  });

  test('收藏占满上限时仍保留本次新测量，并淘汰最旧收藏', () async {
    final desktop = FakeDesktop()
      ..saved = jsonEncode({
        'measurementHistoryLimit': 16,
        'measurements': [
          for (var i = 0; i < 16; i++) record(i, favorite: true).toJson(),
        ],
      });
    final controller = AppController(desktop);
    addTearDown(controller.dispose);
    addTearDown(desktop.input.close);
    await controller.initialize();
    await controller.startRuler(RulerMode.rectangle);
    desktop.pointer(x: 0, y: 0, phase: 'down');
    desktop.pointer(x: 1, y: 1, phase: 'up');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(controller.measurements, hasLength(16));
    expect(controller.measurements.first.measurement.logicalWidth, 1);
    expect(controller.measurements.where((r) => r.favorite), hasLength(15));
    expect(controller.measurements.last.name, 'record-14');
    expect(jsonDecode(desktop.saved!)['measurements'], hasLength(16));
  });
}
