import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fruler/app/app_controller.dart';
import 'package:fruler/core/core.dart';
import 'package:fruler/platform/desktop_service.dart';

import '../fake_desktop.dart';
import 'controller_test_host.dart';

void main() {
  for (final size in [const Size(1100, 760), const Size(920, 680)]) {
    testWidgets('屏幕原位标注 ${size.width}：无项目入口、鼠标绘制、文字、撤销和完成', (tester) async {
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
              rgba: Uint8List.fromList([
                for (var i = 0; i < 640 * 480; i++) ...[200, 210, 220, 255],
              ]),
            ),
          ),
        ]);
      final c = AppController(d);
      await c.initialize();
      addTearDown(d.input.close);
      await tester.pumpWidget(ControllerTestHost(controller: c));
      await tester.pumpAndSettle();
      expect(find.textContaining('项目'), findsNothing);
      expect(find.textContaining('工作区'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('start-screenshot')));
      await tester.pumpAndSettle();
      d.pointer(x: 100, y: 100, phase: 'down');
      d.pointer(x: 500, y: 350, phase: 'up');
      for (
        var i = 0;
        i < 100 && (!c.screenshotEditing || c.imageLoading);
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(c.screenshotEditing, true, reason: '${c.error}');
      for (var i = 0; i < 100; i++) {
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
      expect(c.busy, true);
      expect(find.text('fruler'), findsNothing);
      expect(find.textContaining('项目'), findsNothing);
      expect(
        tester.getSize(find.byKey(const ValueKey('annotation-toolbar'))).height,
        lessThan(100),
      );
      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.byKey(const ValueKey('annotation-width')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('annotation-group-line')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('annotation-font')), findsNothing);
      final canvas = find.byKey(const ValueKey('annotation-canvas'));
      await tester.dragFrom(
        tester.getCenter(canvas) - const Offset(50, 20),
        const Offset(80, 40),
        kind: ui.PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(c.markup.items.single.kind, AnnotationKind.arrow);
      await tester.tap(find.byKey(const ValueKey('annotation-undo')));
      await tester.pumpAndSettle();
      expect(c.markup.items, isEmpty);
      await tester.tap(find.byKey(const ValueKey('annotation-redo')));
      await tester.pumpAndSettle();
      expect(c.markup.items.length, 1);
      // Desktop cursor feedback follows hit targets and active drags.
      await tester.tap(find.byKey(const ValueKey('annotation-tool-select')));
      await tester.pumpAndSettle();
      final cursorMouse = TestGesture(
        dispatcher: tester.sendEventToBinding,
        pointer: 9001,
        device: 9001,
        kind: ui.PointerDeviceKind.mouse,
      );
      final strokeCenter = tester.getTopLeft(canvas) + const Offset(190, 125);
      await cursorMouse.addPointer(location: strokeCenter);
      await cursorMouse.moveTo(strokeCenter);
      await tester.pump();
      MouseCursor? activeCursor() =>
          RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(9001);
      expect(activeCursor(), SystemMouseCursors.grab);
      await cursorMouse.down(strokeCenter);
      await tester.pump();
      expect(activeCursor(), SystemMouseCursors.grabbing);
      await cursorMouse.moveTo(strokeCenter + const Offset(5, 5));
      await cursorMouse.up();
      await tester.pump();
      expect(activeCursor(), SystemMouseCursors.grab);
      c.markup.undo();
      await tester.pump();
      final corner = tester.getTopLeft(canvas) + const Offset(150, 105);
      await cursorMouse.moveTo(corner);
      await tester.pump();
      expect(activeCursor(), SystemMouseCursors.grab);
      await cursorMouse.down(corner);
      await tester.pump();
      expect(activeCursor(), SystemMouseCursors.grabbing);
      await cursorMouse.cancel();
      await tester.pump();
      await cursorMouse.moveTo(
        tester.getCenter(find.byKey(const ValueKey('copy-screenshot'))),
      );
      await tester.pump();
      expect(activeCursor(), SystemMouseCursors.click);
      await cursorMouse.moveTo(
        tester.getTopLeft(canvas) + const Offset(20, 200),
      );
      await tester.pump();
      expect(activeCursor(), SystemMouseCursors.basic);
      await cursorMouse.removePointer();
      // A marquee must not mutate history until mouse release.
      final saved = List<Annotation>.of(c.markup.items);
      await tester.tap(find.byKey(const ValueKey('annotation-tool-eraser')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('annotation-properties')), findsNothing);
      final origin = tester.getTopLeft(canvas);
      final gesture = await tester.startGesture(
        origin + const Offset(140, 105),
        kind: ui.PointerDeviceKind.mouse,
      );
      await gesture.moveTo(origin + const Offset(240, 170));
      await tester.pump();
      expect(c.markup.items, saved);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(c.markup.items, isEmpty);
      await tester.tap(find.byKey(const ValueKey('annotation-undo')));
      await tester.pumpAndSettle();
      expect(c.markup.items, saved);
      final cancelled = await tester.startGesture(
        origin + const Offset(140, 105),
        kind: ui.PointerDeviceKind.mouse,
      );
      await cancelled.moveTo(origin + const Offset(240, 170));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await cancelled.up();
      await tester.pumpAndSettle();
      expect(c.markup.items, saved);
      expect(c.screenshotEditing, true);
      // Reverse marquee deletes multiple tiny objects in a single undo step.
      final tiny = [
        for (final x in [20.0, 30.0])
          Annotation(
            kind: AnnotationKind.line,
            points: [Offset(x, 25), Offset(x + 2, 25)],
            width: 1,
          ),
      ];
      c.markup.commit([...saved, ...tiny]);
      await tester.pump();
      await tester.dragFrom(
        origin + const Offset(40, 35),
        const Offset(-25, -20),
        kind: ui.PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(c.markup.items, saved);
      await tester.tap(find.byKey(const ValueKey('annotation-undo')));
      await tester.pumpAndSettle();
      expect(c.markup.items, [...saved, ...tiny]);
      await tester.tap(find.byKey(const ValueKey('annotation-redo')));
      await tester.pumpAndSettle();
      expect(c.markup.items, saved);
      // An empty box does not consume history or clear redo.
      await tester.tap(find.byKey(const ValueKey('annotation-undo')));
      await tester.pumpAndSettle();
      await tester.dragFrom(
        origin + const Offset(60, 30),
        const Offset(15, 15),
        kind: ui.PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(c.markup.canRedo, true);
      final aborted = await tester.startGesture(
        origin + const Offset(15, 15),
        kind: ui.PointerDeviceKind.mouse,
      );
      await aborted.moveTo(origin + const Offset(40, 35));
      await aborted.cancel();
      await tester.pumpAndSettle();
      expect(c.markup.items, [...saved, ...tiny]);
      await tester.tap(find.byKey(const ValueKey('annotation-redo')));
      await tester.pumpAndSettle();
      final textTool = find.byKey(const ValueKey('annotation-tool-text'));
      await tester.ensureVisible(textTool);
      await tester.tap(textTool);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('annotation-font')), findsOneWidget);
      expect(find.byKey(const ValueKey('annotation-width')), findsNothing);
      await tester.tap(canvas);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('annotation-text-input')),
        '屏幕上完成',
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
      expect(c.markup.items.length, 2);
      final done = find.byKey(const ValueKey('copy-screenshot'));
      await tester.ensureVisible(done);
      await tester.runAsync(() => c.exportScreenshot(save: false));
      await tester.pumpAndSettle();
      expect(c.busy, false);
      expect(d.showMainCalls, 0);
      expect(d.finishCalls, 1);
      expect(c.screenshots.length, 1);
      expect(find.textContaining('项目'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('录屏拒绝有授权入口，普通历史没有项目或草稿恢复', (tester) async {
    final d = FakeDesktop()
      ..permission = false
      ..beginError = PlatformException(code: 'screen_permission');
    final c = AppController(d);
    await c.initialize();
    addTearDown(d.input.close);
    await tester.pumpWidget(ControllerTestHost(controller: c));
    await tester.pumpAndSettle();
    expect(find.textContaining('草稿'), findsNothing);
    expect(find.textContaining('项目'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('start-screenshot')));
    await tester.pumpAndSettle();
    expect(c.busy, false);
    expect(find.text('前往授权 →'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
