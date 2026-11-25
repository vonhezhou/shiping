import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fruler/app/app_controller.dart';
import 'package:fruler/core/core.dart';
import 'package:fruler/platform/desktop_service.dart';

import '../fake_desktop.dart';
import 'annotation_color_memory_test.dart' show capture;
import 'controller_test_host.dart';
import 'snipaste_toolbar_test.dart' show wheel, setSlider;

void main() {
  for (final size in [const Size(1100, 760), const Size(920, 680)]) {
    testWidgets('标注选项在退出重开后恢复，最后工具无需切换 $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final d = FakeDesktop()
        ..capture = CaptureSession(7, [
          CapturedDisplay(
            id: 1,
            name: 'screen',
            frame: PixelFrame(
              width: 640,
              height: 480,
              logicalWidth: 640,
              logicalHeight: 480,
              rgba: Uint8List(640 * 480 * 4),
            ),
          ),
        ]);
      addTearDown(d.input.close);
      var c = AppController(d);
      await c.initialize();
      await tester.pumpWidget(ControllerTestHost(controller: c));
      await capture(tester, c, d);
      Finder key(String value) => find.byKey(ValueKey(value));
      Future<void> click(String value) async {
        await tester.tap(key(value), kind: ui.PointerDeviceKind.mouse);
        await tester.pumpAndSettle();
      }

      Future<void> choose(String tool) async {
        if (key('annotation-tool-$tool').evaluate().isEmpty) {
          await click(
            'annotation-group-${switch (tool) {
              'ellipse' || 'rectangle' => 'shape',
              'line' || 'arrow' => 'line',
              _ => 'effect',
            }}',
          );
        }
        final button = tester.widget<IconButton>(key('annotation-tool-$tool'));
        if (button.isSelected != true) await click('annotation-tool-$tool');
      }

      final widths = <String, int>{};
      for (final tool in [
        'ellipse',
        'line',
        'pencil',
        'marker',
        'blur',
        'eraser',
      ]) {
        await choose(tool);
        if (tool == 'blur') await click('annotation-effect-brush');
        if (tool == 'eraser') await click('annotation-width');
        await wheel(tester, tester.getCenter(key('annotation-width')));
        widths[tool] = int.parse(
          RegExp(r'线宽 (\d+)')
              .firstMatch(
                tester.widget<IconButton>(key('annotation-width')).tooltip!,
              )!
              .group(1)!,
        );
        if (tool == 'ellipse') await click('annotation-fill');
        if (tool == 'blur') {
          await setSlider(tester, 'annotation-effect-strength', 5);
        }
      }
      await choose('text');
      await click('annotation-bold');
      await click('annotation-italic');
      await click('annotation-text-outline');
      await click('annotation-font-family');
      await click('annotation-font-option-Menlo');
      await click('annotation-font');
      await tester.tap(find.text('36 pt'), kind: ui.PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      // 不切换工具，不调用 dispose 保存；模拟重启只从已写入的数据重建。
      final saved = d.saved;
      await c.cancelScreenshot();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      d.saved = saved;
      c = AppController(d);
      await c.initialize();
      await tester.pumpWidget(ControllerTestHost(controller: c));
      await capture(tester, c, d);
      await choose('text');
      expect(
        find.descendant(
          of: key('annotation-font-family'),
          matching: find.text('Menlo'),
        ),
        findsOneWidget,
      );
      for (final option in ['bold', 'italic', 'text-outline']) {
        expect(
          tester.widget<IconButton>(key('annotation-$option')).isSelected,
          true,
        );
      }
      expect(
        find.descendant(of: key('annotation-font'), matching: find.text('36')),
        findsOneWidget,
      );
      for (final entry in widths.entries) {
        await choose(entry.key);
        expect(
          tester.widget<IconButton>(key('annotation-width')).tooltip,
          contains('线宽 ${entry.value} pt'),
          reason: entry.key,
        );
        if (entry.key == 'ellipse') {
          expect(
            tester.widget<IconButton>(key('annotation-fill')).isSelected,
            true,
          );
        }
        if (entry.key == 'blur') {
          expect(
            tester.widget<Slider>(key('annotation-effect-strength')).value,
            5,
          );
          expect(
            tester.widget<IconButton>(key('annotation-width')).isSelected,
            true,
          );
        }
        if (entry.key == 'eraser') {
          expect(
            tester.widget<IconButton>(key('annotation-width')).isSelected,
            true,
          );
        }
      }
      expect(c.markup.items, isEmpty);
      await c.cancelScreenshot();
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
