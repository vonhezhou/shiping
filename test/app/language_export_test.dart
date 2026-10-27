import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fruler/app/app_controller.dart';
import 'package:fruler/core/core.dart';
import 'package:fruler/l10n/app_language.dart';

import '../fake_desktop.dart';

void main() {
  test('切换语言不改变测量 CSV / JSON 契约及用户名称', () async {
    final desktop = FakeDesktop();
    final controller = AppController(desktop);
    addTearDown(controller.dispose);
    addTearDown(desktop.input.close);
    await controller.initialize();
    final record = MeasurementRecord(
      measurement: const RulerMeasurement(
        rect: PixelRect(left: 1, top: 2, right: 101, bottom: 62),
        logicalWidth: 50,
        logicalHeight: 30,
        mode: RulerMode.rectangle,
      ),
      createdAt: DateTime.utc(2026, 10, 23),
      displayName: '用户的 Display',
      name: '中文尺寸, "Sample"',
      favorite: true,
    );
    for (final csv in [true, false]) {
      await controller.setLanguage(AppLanguage.zh);
      await controller.exportMeasurements([record], csv: csv);
      final before = desktop.exportedText!;
      final filename = desktop.exportedName;
      expect(filename, '拾屏-measurements.${csv ? 'csv' : 'json'}');
      await controller.setLanguage(AppLanguage.en);
      await controller.exportMeasurements([record], csv: csv);
      expect(desktop.exportedText, before);
      expect(desktop.exportedName, filename);
      if (csv) {
        expect(before, startsWith('name,favorite,mode,width_px,'));
        expect(before, contains('"中文尺寸, ""Sample"""'));
      } else {
        final data = jsonDecode(before) as Map;
        expect(data['version'], 1);
        expect(data['measurements'].single['mode'], 'rectangle');
        expect(data['measurements'].single['name'], record.name);
      }
    }
  });
}
