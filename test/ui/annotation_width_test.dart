import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fruler/app/app_controller.dart';
import 'package:fruler/core/core.dart';
import 'package:fruler/platform/desktop_service.dart';

import '../fake_desktop.dart';
import 'controller_test_host.dart';
import 'snipaste_toolbar_test.dart' show wheel;

void main() {
  for (final size in [const Size(1100, 760), const Size(920, 680)]) {
    testWidgets('宽度持续选中与工具模式互斥矩阵 $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final desktop = FakeDesktop()
        ..capture = CaptureSession(7, [
          CapturedDisplay(
            id: 1,
            name: 'screen',
            frame: PixelFrame(
              width: 640,
              height: 480,
              logicalWidth: 640,
              logicalHeight: 480,
              rgba: Uint8List.fromList(
                List.generate(640 * 480 * 4, (i) => i % 4 == 3 ? 255 : 200),
              ),
            ),
          ),
        ]);
      final c = AppController(desktop);
      await c.initialize();
      addTearDown(desktop.input.close);
      await tester.pumpWidget(ControllerTestHost(controller: c));
      await tester.pumpAndSettle();
      await c.startScreenshot();
      desktop.pointer(x: 100, y: 100, phase: 'down');
      desktop.pointer(x: 500, y: 350, phase: 'up');
      for (var i = 0; i < 150; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
        final button = find.byKey(const ValueKey('copy-screenshot'));
        if (button.evaluate().isNotEmpty &&
            tester.widget<IconButton>(button).onPressed != null) {
          break;
        }
      }
      await tester.pumpAndSettle();
      final origin = tester.getTopLeft(
        find.byKey(const ValueKey('annotation-canvas')),
      );
      Finder byKey(String key) => find.byKey(ValueKey(key));
      bool active(String key) =>
          tester.widget<IconButton>(byKey(key)).isSelected!;
      Future<void> click(String key) async {
        await tester.tap(byKey(key), kind: ui.PointerDeviceKind.mouse);
        await tester.pumpAndSettle();
      }

      for (final kind in [
        'rectangle',
        'ellipse',
        'line',
        'arrow',
        'pencil',
        'marker',
        'mosaic',
        'blur',
        'eraser',
      ]) {
        if (byKey('annotation-tool-$kind').evaluate().isEmpty) {
          await click(
            'annotation-group-${['rectangle', 'ellipse'].contains(kind)
                ? 'shape'
                : ['line', 'arrow'].contains(kind)
                ? 'line'
                : 'effect'}',
          );
        }
        await click('annotation-tool-$kind');
        if (kind == 'pencil') {
          final tooltip = tester
              .widget<IconButton>(byKey('annotation-width'))
              .tooltip!;
          final before = int.parse(
            RegExp(r'线宽 (\d+)').firstMatch(tooltip)!.group(1)!,
          );
          await wheel(tester, const Offset(20, 20));
          expect(
            find.byTooltip('线宽 ${before + 1} pt · 滚轮 / 1、2 / [、]'),
            findsOneWidget,
            reason: '无需先点击宽度按钮，选区外遮罩也能滚轮调宽',
          );
          await wheel(tester, const Offset(20, 20), dy: 20);
        }
        await click('annotation-width');
        await click('annotation-width');
        expect(active('annotation-width'), true, reason: kind);
        expect(find.byType(PopupMenuItem<double>), findsNothing);
        await wheel(tester, tester.getCenter(byKey('annotation-width')));
        await tester.dragFrom(
          origin + const Offset(50, 60),
          const Offset(80, 40),
          kind: ui.PointerDeviceKind.mouse,
        );
        await tester.pumpAndSettle();
        final mark = c.markup.items.last;
        expect(mark.kind.name, kind);
        await wheel(tester, const Offset(20, 20));
        if (kind != 'eraser') {
          expect(
            c.markup.items.last.width,
            mark.width + 1,
            reason: '$kind 选区外遮罩调整选中对象宽度',
          );
        }
        await wheel(tester, const Offset(20, 20), dy: 20);
        await wheel(tester, tester.getCenter(byKey('annotation-undo')));
        await wheel(
          tester,
          tester.getTopLeft(byKey('annotation-toolbar')) + const Offset(1, 1),
        );
        expect(
          c.markup.items.last.width,
          mark.width,
          reason: '工具栏普通按钮和面板留白不调整宽度',
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
        await tester.pumpAndSettle();
        if (kind != 'eraser') expect(c.markup.items.last.width, mark.width + 1);
        await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
        await tester.pumpAndSettle();

        await click('annotation-width');
        await wheel(tester, tester.getCenter(byKey('annotation-width')));
        if (kind == 'eraser') {
          expect(
            c.markup.items.last,
            same(mark),
            reason: '已完成的擦除保持独立记录，新宽度用于下一次擦除',
          );
          await tester.dragFrom(
            origin + const Offset(50, 60),
            const Offset(80, 40),
            kind: ui.PointerDeviceKind.mouse,
          );
          await tester.pumpAndSettle();
        }
        expect(c.markup.items.last.width, mark.width + 1, reason: kind);
        if (kind == 'marker') {
          await click('annotation-tool-marker');
          await tester.tapAt(
            origin + const Offset(90, 80),
            kind: ui.PointerDeviceKind.mouse,
          );
          await tester.pumpAndSettle();
          final oldWidth = c.markup.items.last.width;
          await click('annotation-width');
          await wheel(tester, tester.getCenter(byKey('annotation-width')));
          expect(
            c.markup.items.last.width,
            oldWidth + 1,
            reason: '选择模式中调宽也必须修改选中的对象',
          );
        }
        if (['rectangle', 'ellipse'].contains(kind)) {
          await click('annotation-fill');
          final filled = c.markup.items.last;
          expect(filled.filled, true);
          await click('annotation-fill');
          expect(
            c.markup.items.last,
            same(filled),
            reason: '重复点击填充不取消选择、不新增历史',
          );
          expect(active('annotation-width'), false);
          expect(active('annotation-fill'), true);
          await wheel(tester, const Offset(20, 20));
          await wheel(tester, origin + const Offset(20, 200));
          await wheel(tester, tester.getCenter(byKey('annotation-width')));
          expect(c.markup.items.last, same(filled));
          await click('annotation-width');
          expect(active('annotation-width'), true);
          expect(active('annotation-fill'), false);
          expect(c.markup.items.last.filled, false);
          expect(c.markup.items.last.width, filled.width);
          await tester.sendKeyEvent(LogicalKeyboardKey.bracketRight);
          await tester.pumpAndSettle();
          expect(
            c.markup.items.last.width,
            filled.width + 1,
            reason: '点击后键盘快捷键仍由编辑器处理',
          );
        }
        if (['mosaic', 'blur', 'eraser'].contains(kind)) {
          final prefix = kind == 'eraser' ? 'eraser' : 'effect';
          expect(active('annotation-$prefix-rectangle'), false);
          final before = List<Annotation>.of(c.markup.items);
          await click('annotation-$prefix-rectangle');
          await click('annotation-$prefix-rectangle');
          expect(active('annotation-width'), false);
          expect(active('annotation-$prefix-rectangle'), true);
          await wheel(tester, const Offset(20, 20));
          await wheel(tester, origin + const Offset(20, 200));
          await wheel(tester, tester.getCenter(byKey('annotation-width')));
          expect(c.markup.items, before, reason: '框选模式不改宽度或旧标注');
          if (kind != 'eraser') expect(find.byType(Slider), findsOneWidget);
          await click('annotation-width');
          expect(active('annotation-width'), true);
          expect(active('annotation-$prefix-rectangle'), false);
        }
      }
      await c.cancelScreenshot();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
