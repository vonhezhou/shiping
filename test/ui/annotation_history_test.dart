import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fruler/app/app_controller.dart';
import 'package:fruler/core/core.dart';
import 'package:fruler/platform/desktop_service.dart';

import '../fake_desktop.dart';
import 'controller_test_host.dart';

void main() {
  for (final size in [const Size(1100, 760), const Size(920, 680)]) {
    testWidgets('选择不占历史，移动删除可撤销，重做后可继续键盘编辑 $size', (tester) async {
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
      Future<void> click(String key) async {
        await tester.tap(byKey(key), kind: ui.PointerDeviceKind.mouse);
        await tester.pumpAndSettle();
      }

      await click('annotation-group-shape');
      await tester.dragFrom(
        origin + const Offset(40, 40),
        const Offset(140, 100),
        kind: ui.PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      final first = c.markup.items.single;
      await click('annotation-group-shape');
      await tester.tapAt(
        origin + const Offset(60, 40),
        kind: ui.PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(byKey('annotation-delete'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pumpAndSettle();
      expect(c.markup.items, isEmpty);
      await click('annotation-undo');
      expect(c.markup.items, [first]);
      expect(
        byKey('annotation-delete'),
        findsOneWidget,
        reason: '撤销删除恢复选中，允许直接继续调整',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(c.markup.items.single.bounds.left, first.bounds.left + 1);
      await click('annotation-undo');
      expect(c.markup.items, [first]);
      // A drag returning to its starting point must preserve the redo branch.
      final mouse = await tester.startGesture(
        origin + const Offset(70, 40),
        kind: ui.PointerDeviceKind.mouse,
      );
      await mouse.moveBy(const Offset(20, 10));
      await mouse.moveBy(const Offset(-20, -10));
      await mouse.up();
      await tester.pumpAndSettle();
      expect(c.markup.canRedo, true);
      await click('annotation-redo');
      expect(c.markup.items.single.bounds.left, first.bounds.left + 1);
      expect(byKey('annotation-delete'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();
      expect(c.markup.items, isEmpty);
      await click('annotation-undo');
      await click('annotation-undo');
      expect(c.markup.items, [first]);
      await click('annotation-undo');
      expect(c.markup.items, isEmpty, reason: '选择本身不消耗一次撤销');
      await click('annotation-redo');
      expect(byKey('annotation-delete'), findsOneWidget, reason: '重做绘制后继续编辑');
      await c.cancelScreenshot();
      await tester.pumpAndSettle();
    });
  }
}
