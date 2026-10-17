import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fruler/app/app_controller.dart';
import 'package:fruler/core/core.dart';
import 'package:fruler/platform/image_document.dart';

import 'controller_test_host.dart';

import '../fake_desktop.dart';

class WidgetImageCodec extends ImageDocumentCodec {
  @override
  Future<Uint8List> renderAnnotations(
    ImageDocument document,
    List<Map<String, Object?>> pins,
  ) async => document.png;
}

void main() {
  late FakeDesktop d;
  late AppController c;
  Future<void> setup(
    WidgetTester tester, {
    Size size = const Size(920, 680),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    d = FakeDesktop()..permission = false;
    c = AppController(d, imageCodec: WidgetImageCodec());
    await c.initialize();
    addTearDown(d.input.close);
    await tester.pumpWidget(ControllerTestHost(controller: c));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('最小窗口可创建分组、搜索和通过菜单排序', (tester) async {
    await setup(tester);
    const a = RgbColor(1, 2, 3), b = RgbColor(4, 5, 6);
    c.savePaletteColor(a, name: '品牌');
    c.savePaletteColor(b, name: '次色');
    await tester.pumpAndSettle();
    await tap(tester, find.text('新建分组'));
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextFormField),
      ),
      '__all__',
    );
    await tester.tap(find.text('保存名称'));
    await tester.pumpAndSettle();
    expect(c.selectedPaletteGroup, '__all__');
    expect(tester.takeException(), isNull);
    c.savePaletteColor(a, group: '__all__');
    c.savePaletteColor(b, group: '__all__');
    await tester.pumpAndSettle();
    await tap(tester, find.byTooltip('颜色操作 #040506'));
    await tester.tap(find.text('向前排序'));
    await tester.pumpAndSettle();
    expect(c.visiblePalette.first.color, b);
    final draggables = find.byType(LongPressDraggable<RgbColor>);
    await tester.ensureVisible(draggables.first);
    final source = tester.getTopLeft(draggables.first) + const Offset(30, 20);
    final destination =
        tester.getTopLeft(draggables.last) + const Offset(30, 20);
    final gesture = await tester.startGesture(source);
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveTo(destination);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(c.visiblePalette.first.color, a);

    await tester.ensureVisible(find.byKey(const ValueKey('palette-search')));
    await tester.enterText(find.byKey(const ValueKey('palette-search')), '品牌');
    await tester.pumpAndSettle();
    expect(c.visiblePalette.single.color, a);
    await tap(tester, find.byTooltip('解散分组并保留颜色'));
    expect(c.palette.length, 2);
    expect(c.palette.every((e) => e.group.isEmpty), true);
    expect(tester.takeException(), isNull);
  });
  testWidgets('未授权也能在图片工作区取色，缩放平移后仍使用原始坐标', (tester) async {
    await setup(tester, size: const Size(1100, 1000));
    await tester.runAsync(
      () => c.loadImage(
        ImageFileData(
          'fixture.png',
          File('test/fixtures/workspace.png').readAsBytesSync(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('首次使用需要屏幕录制权限，才能读取屏幕上的像素。'), findsNothing);
    final canvas = find.byKey(const ValueKey('image-canvas'));
    await tester.ensureVisible(canvas);
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getTopLeft(canvas) + const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(c.selectedColor, const RgbColor(255, 0, 0));
    await tap(tester, find.byTooltip('放大'));
    await tester.ensureVisible(canvas);
    await tester.tapAt(tester.getTopLeft(canvas) + const Offset(175, 25));
    await tester.pumpAndSettle();
    expect(c.selectedColor, const RgbColor(0, 0, 255));
    await tap(tester, find.text('平移'));
    await tester.dragFrom(
      tester.getTopLeft(canvas) + const Offset(50, 50),
      const Offset(30, 20),
    );
    await tester.pumpAndSettle();
    await tap(tester, find.widgetWithText(ChoiceChip, '取色'));
    await tester.ensureVisible(canvas);
    await tester.tapAt(tester.getTopLeft(canvas) + const Offset(25, 25));
    await tester.pumpAndSettle();
    expect(c.selectedColor, const RgbColor(255, 0, 0));
    expect(d.beginCalls, 0);
    expect(tester.takeException(), isNull);
  });
  testWidgets('图片矩形标注、编辑与导出在最小窗口可用', (tester) async {
    await setup(tester);
    await tester.runAsync(
      () => c.loadImage(
        ImageFileData(
          'fixture.png',
          File('test/fixtures/workspace.png').readAsBytesSync(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tap(tester, find.widgetWithText(ChoiceChip, '矩形'));
    final canvas = find.byKey(const ValueKey('image-canvas'));
    await tester.ensureVisible(canvas);
    await tester.dragFrom(
      tester.getTopLeft(canvas) + const Offset(20, 40),
      const Offset(60, 50),
    );
    await tester.pumpAndSettle();
    expect(c.measurements.single.measurement.rect.width, 60);
    expect(c.measurements.single.measurement.rect.height, 50);
    await tap(tester, find.text('编辑标注'));
    await tester.ensureVisible(canvas);
    await tester.tapAt(tester.getTopLeft(canvas) + const Offset(40, 60));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect((c.imageOverlay['pinned'] as List).single['rect']['left'], 21);
    await tap(tester, find.text('导出标注 PNG'));
    expect(c.error, isNull);
    expect(d.exportedImage, isNotNull);
    expect(d.beginCalls, 0);
    expect(tester.takeException(), isNull);
  });
}
