import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fruler/app/app_controller.dart';
import 'package:fruler/core/core.dart';

import '../fake_desktop.dart';

Future<void> tick() => Future<void>.delayed(Duration.zero);
void main() {
  late FakeDesktop d;
  late AppController c;
  setUp(() async {
    d = FakeDesktop();
    c = AppController(d);
    await c.initialize();
  });
  tearDown(() async {
    c.dispose();
    await d.input.close();
  });
  Future<void> pin() async {
    await c.startRuler();
    d.pointer(x: 0, y: 0, phase: 'down');
    d.pointer(x: 2, y: 2, phase: 'up', keep: true);
    await tick();
  }

  Map rect() => (d.lastOverlay!['pinned'] as List).single['rect'] as Map;
  test('Retina 拖动按原始框计算，一次手势一次撤销，不改历史', () async {
    await pin();
    final original = Map.of(rect());
    d.event('editPins');
    d.event('selectPin', {'id': 1});
    d.event('pinDrag', {'id': 1, 'displayId': 1, 'phase': 'start'});
    d.event('pinDrag', {
      'id': 1,
      'displayId': 1,
      'phase': 'update',
      'dx': .5,
      'dy': .5,
      'handle': 'move',
    });
    d.event('pinDrag', {
      'id': 1,
      'displayId': 1,
      'phase': 'end',
      'dx': 1.0,
      'dy': 1.0,
      'handle': 'move',
    });
    expect(rect(), {'left': 2, 'top': 2, 'right': 6, 'bottom': 6});
    d.event('undoPins');
    expect(rect(), original);
    expect(c.measurements.length, 1);
    d.event('undoPins');
    expect(d.lastOverlay!['pinned'], isEmpty);
  });
  test('编辑键盘移动和 Shift 缩放、屏幕边界与撤销', () async {
    await pin();
    d.event('editPins');
    d.event('selectPin', {'id': 1});
    d.event('nudge', {'dx': 1, 'dy': 0});
    expect(rect()['left'], 1);
    d.event('nudge', {'dx': 1, 'dy': 0, 'resize': true});
    expect(rect()['right'], 6);
    d.event('undoPins');
    expect(rect()['right'], 5);
    d.event('selectPin', {'id': 1});
    d.event('confirm');
    await tick();
    expect(c.busy, true);
  });
  test('同屏依次取两色覆盖连续模式，Esc 后不污染普通取色', () async {
    c.setContinuousPicker(true);
    await c.pickContrast(foreground: true, pair: true);
    d.pointer(phase: 'up');
    await tick();
    expect(c.busy, true);
    expect(d.lastOverlay!['capturePurpose'], '选取背景色');
    expect(c.contrastForeground, const RgbColor(255, 0, 0));
    d.pointer(phase: 'up');
    await tick();
    expect(c.busy, false);
    expect(c.contrast.ratio, 1);
    expect(c.continuousPicker, true);
    final restored = AppController(d);
    await restored.initialize();
    expect(restored.contrast.ratio, 1);
    restored.dispose();
    await c.pickContrast(foreground: false);
    d.event('cancelled');
    await c.pickColor();
    expect(d.lastOverlay!['capturePurpose'], '');
  });
  test('历史命名收藏搜索、导出、兼容迁移与单条删除', () async {
    await pin();
    final record = c.measurements.single;
    c.updateMeasurement(record, name: '=SUM(1,2)', favorite: true);
    expect(c.filterMeasurements('SUM', favoritesOnly: true).length, 1);
    final named = c.measurements.single;
    await c.exportMeasurements([named], csv: true);
    expect(d.exportedText, contains("'=SUM(1,2)"));
    expect(d.exportedText, contains('"2.0","2.0"'));
    await c.exportMeasurements([named], csv: false);
    final json = jsonDecode(d.exportedText!);
    expect(json['measurements'][0]['scaleX'], 2.0);
    final restored = AppController(d);
    await restored.initialize();
    expect(restored.measurements.single.name, named.name);
    restored.dispose();
    final old = Map<String, dynamic>.from(named.toJson())
      ..remove('name')
      ..remove('favorite');
    expect(MeasurementRecord.fromJson(old).favorite, false);
    c.removeMeasurement(named);
    expect(c.measurements, isEmpty);
  });
  test('导入取消和无效文件不改数据；合并与多选复制', () async {
    const a = RgbColor(1, 2, 3), b = RgbColor(4, 5, 6);
    c.savePaletteColor(a, name: '旧名', favorite: true);
    expect(await c.readPaletteImport(), isNull);
    expect(c.palette.length, 1);
    d.importText = '{}';
    expect(await c.readPaletteImport(), isNull);
    expect(c.palette.single.name, '旧名');
    d.importText = exportPalette([
      const PaletteEntry(color: a, name: '新名'),
      const PaletteEntry(color: b),
    ], PaletteExport.json);
    final preview = await c.readPaletteImport();
    expect(c.palette.length, 1);
    c.applyPaletteImport(preview!, PaletteMerge.useImported);
    expect(c.palette.first.name, '新名');
    await c.copyPaletteSelection({b}, flutter: true);
    expect(d.clipboard, contains('Color(0xFF040506)'));
    expect(d.clipboard, isNot(contains('010203')));
    expect(c.notice, '已复制 1 色的 Flutter 代码');
  });
  test('收藏记录不被最近32条淘汰', () async {
    await pin();
    c.updateMeasurement(c.measurements.single, name: '保留', favorite: true);
    for (var i = 0; i < 35; i++) {
      d.pointer(x: 0, y: 0, phase: 'down');
      d.pointer(x: 1, y: 1, phase: 'up', keep: true);
      await tick();
    }
    expect(c.measurements.length, 33);
    expect(c.measurements.last.name, '保留');
  });
}
