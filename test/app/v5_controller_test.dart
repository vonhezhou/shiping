import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fruler/app/app_controller.dart';
import 'package:fruler/core/core.dart';
import 'package:fruler/platform/image_document.dart';

import '../fake_desktop.dart';

class FixtureCodec extends ImageDocumentCodec {
  @override
  Future<ImageDocument> decode(ImageFileData file) async => ImageDocument(
    file.name,
    file.bytes,
    PixelFrame(
      width: 240,
      height: 160,
      logicalWidth: 240,
      logicalHeight: 160,
      rgba: Uint8List.fromList([
        for (var i = 0; i < 240 * 160; i++) ...[
          i % 240 < 120 ? 255 : 0,
          0,
          i % 240 < 120 ? 0 : 255,
          255,
        ],
      ]),
    ),
  );
}

Future<void> tick() => Future<void>.delayed(Duration.zero);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeDesktop d;
  late AppController c;
  setUp(() async {
    d = FakeDesktop()..permission = false;
    c = AppController(d, imageCodec: FixtureCodec());
    await c.initialize();
  });
  tearDown(() async {
    c.dispose();
    await d.input.close();
  });
  const a = RgbColor(1, 2, 3), b = RgbColor(4, 5, 6), other = RgbColor(7, 8, 9);
  test('旧调色板迁移到未分组；分组创建重命名解散不删颜色', () async {
    c.savePaletteColor(a);
    expect(c.palette.single.group, '');
    expect(c.createPaletteGroup('项目A'), true);
    expect(c.createPaletteGroup('项目A'), false);
    c.savePaletteColor(a, group: '项目A');
    expect(c.renamePaletteGroup('项目A', '项目B'), true);
    expect(c.palette.single.group, '项目B');
    c.dissolvePaletteGroup('项目B');
    expect(c.palette.single.color, a);
    expect(c.palette.single.group, '');
    d.saved = jsonEncode({
      'palette': [
        {
          'color': [1, 2, 3],
          'name': '旧色',
          'favorite': true,
        },
      ],
    });
    final old = AppController(d);
    await old.initialize();
    expect(old.palette.single.group, '');
    old.dispose();
  });
  test('分组排序与搜索不改变其他分组；筛选导出及重启恢复', () async {
    c.createPaletteGroup('空分组');
    c.savePaletteColor(a, name: '品牌', group: 'A');
    c.savePaletteColor(other, group: 'B');
    c.savePaletteColor(b, group: 'A');
    c.filterPalette(group: 'A', setGroup: true);
    c.reorderPalette(b, a);
    expect(c.visiblePalette.map((e) => e.color), [b, a]);
    c.filterPalette(query: '品牌');
    expect(c.visiblePalette.single.color, a);
    c.reorderPalette(a, b);
    expect(c.palette.first.color, b);
    await c.exportColors(PaletteExport.json, saved: true);
    final imported = importPalette(d.exportedText!);
    expect(imported.single.group, 'A');
    expect(imported.single.name, '品牌');
    final restored = AppController(d);
    await restored.initialize();
    expect(restored.palette.first.color, b);
    expect(restored.paletteGroups, contains('空分组'));
    restored.dispose();
    c.filterPalette(group: 'B', setGroup: true, query: '#070809');
    expect(c.visiblePalette.single.color, other);
  });
  test('分组 JSON 往返与已有颜色合并规则保持一致', () {
    c.savePaletteColor(a, group: '原组');
    final entries = importPalette(
      exportPalette([
        const PaletteEntry(color: a, group: '导入组'),
      ], PaletteExport.json),
    );
    c.applyPaletteImport(entries, PaletteMerge.keepExisting);
    expect(c.palette.single.group, '原组');
    c.applyPaletteImport(entries, PaletteMerge.useImported);
    expect(c.palette.single.group, '导入组');
    expect(c.paletteGroups, contains('导入组'));
  });
  test('图片取色和原始像素测量完全不调用屏幕接口', () async {
    final bytes = File('test/fixtures/workspace.png').readAsBytesSync();
    await c.loadImage(ImageFileData('fixture.png', bytes));
    expect(c.section, AppSection.image);
    expect(c.busy, false);
    expect(c.permissionGranted, false);
    c.imageEvent('pointer', {'x': 5.0, 'y': 10.0, 'phase': 'up'});
    await tick();
    expect(c.selectedColor, const RgbColor(255, 0, 0));
    expect(c.imageSessionActive, true);
    c.useImageTool('rectangle');
    c.imageEvent('pointer', {'x': 10.0, 'y': 20.0, 'phase': 'down'});
    c.imageEvent('pointer', {'x': 50.0, 'y': 60.0, 'phase': 'up'});
    await tick();
    expect(c.measurements.single.measurement.rect.width, 40);
    expect(c.measurements.single.imageSource, true);
    expect(c.measurements.single.label, '40 × 40 px');
    expect(c.measurements.single.measurement.logicalWidth, 40);
    c.imageEvent('editPins');
    c.imageEvent('selectPin', {'id': 1});
    c.imageEvent('nudge', {'dx': 1, 'dy': 0, 'resize': true});
    expect((c.imageOverlay['pinned'] as List).single['rect']['right'], 51);
    c.imageEvent('undoPins');
    expect((c.imageOverlay['pinned'] as List).single['rect']['right'], 50);
    expect(d.beginCalls, 0);
    expect(d.finishCalls, 0);
    await c.closeImage();
    expect(c.imageDocument, isNull);
    expect(c.imageSessionActive, false);
  });
  test('拖入事件、取消文件选择和重复打开会话隔离', () async {
    await c.openImage();
    expect(c.imageDocument, isNull);
    final bytes = File('test/fixtures/workspace.png').readAsBytesSync();
    d.event('imageDropped', {'name': 'drop.png', 'bytes': bytes});
    await tick();
    expect(c.imageDocument!.name, 'drop.png');
    final first = c.imageOverlay['sessionId'];
    await c.loadImage(ImageFileData('next.png', bytes));
    expect(c.imageOverlay['sessionId'], isNot(first));
    expect(d.beginCalls, 0);
    d.input.add({
      'type': 'pointer',
      'sessionId': first,
      'displayId': 0,
      'x': 1,
      'y': 1,
      'phase': 'up',
    });
    await tick();
    expect(c.colors, isEmpty);
  });
}
