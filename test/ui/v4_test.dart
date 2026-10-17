import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fruler/app/app_controller.dart';
import 'package:fruler/core/core.dart';
import 'package:fruler/ui/fruler_app.dart';

import '../fake_desktop.dart';

void main() {
  late FakeDesktop d;
  late AppController c;
  Future<void> setup(WidgetTester tester) async {
    tester.view.physicalSize = const Size(920, 680);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    d = FakeDesktop();
    c = AppController(d);
    await c.initialize();
    addTearDown(c.dispose);
    addTearDown(d.input.close);
    await tester.pumpWidget(FrulerApp(controller: c));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder target) async {
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  testWidgets('最小窗口导入预览取消、合并及多选复制', (tester) async {
    await setup(tester);
    d.importText = exportPalette(const [
      PaletteEntry(color: RgbColor(1, 2, 3), name: '品牌'),
    ], PaletteExport.json);
    await tap(tester, find.text('导入 JSON'));
    expect(find.text('预览调色板导入'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(c.palette, isEmpty);
    await tap(tester, find.text('导入 JSON'));
    await tester.tap(find.text('合并导入'));
    await tester.pumpAndSettle();
    expect(c.palette.single.name, '品牌');
    await tap(tester, find.text('批量复制'));
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '复制 CSS'))
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('全选'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('复制 Flutter'));
    await tester.pumpAndSettle();
    expect(d.clipboard, contains('Color(0xFF010203)'));
    expect(tester.takeException(), isNull);
  });
  testWidgets('对比度编辑、交换与依次取两色入口', (tester) async {
    await setup(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('contrast-ratio')));
    await tester.pumpAndSettle();
    expect(find.text('21.00 : 1'), findsOneWidget);
    await tap(tester, find.text('前景色 #000000'));
    await tester.enterText(find.byKey(const ValueKey('hex-editor')), '#FFF');
    await tester.tap(find.text('保存颜色'));
    await tester.pumpAndSettle();
    expect(c.contrast.ratio, 1);
    await tap(tester, find.text('依次取两色'));
    expect(c.busy, true);
    expect(d.lastOverlay!['capturePurpose'], '选取前景色');
    expect(tester.takeException(), isNull);
  });
  testWidgets('历史搜索收藏与单条删除可达且不溢出', (tester) async {
    await setup(tester);
    await c.startRuler();
    d.pointer(x: 0, y: 0, phase: 'down');
    d.pointer(x: 1, y: 1, phase: 'up');
    await tester.pumpAndSettle();
    await tap(tester, find.byTooltip('收藏测量'));
    expect(c.measurements.single.favorite, true);
    await tap(tester, find.byTooltip('测量记录操作'));
    await tester.tap(find.text('命名测量'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '面板');
    await tester.tap(find.text('保存名称'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('measurement-search')),
    );
    await tester.enterText(
      find.byKey(const ValueKey('measurement-search')),
      '无匹配',
    );
    await tester.pumpAndSettle();
    expect(find.text('暂无匹配记录'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('measurement-search')),
      '面板',
    );
    await tester.pumpAndSettle();
    await tap(tester, find.text('导出当前结果 JSON'));
    expect(d.exportedText, contains('面板'));
    await tap(tester, find.byTooltip('测量记录操作'));
    await tester.tap(find.text('删除记录'));
    await tester.pumpAndSettle();
    expect(c.measurements, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
