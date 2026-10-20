import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fruler/app/app_controller.dart';
import 'package:fruler/core/core.dart';
import 'package:fruler/platform/desktop_service.dart';

import '../fake_desktop.dart';
import 'controller_test_host.dart';

void main() {
  for (final size in [const Size(1100, 760), const Size(920, 680)]) {
    testWidgets('Snipaste 工具分组、原位文字和快捷操作 $size', (tester) async {
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
      await c.startScreenshot();
      d.pointer(x: 100, y: 100, phase: 'down');
      d.pointer(x: 500, y: 350, phase: 'up');
      for (var i = 0; i < 150; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
        final copy = find.byKey(const ValueKey('copy-screenshot'));
        if (copy.evaluate().isNotEmpty &&
            tester.widget<IconButton>(copy).onPressed != null) {
          break;
        }
      }
      await tester.pumpAndSettle();
      final toolbar = find.byKey(const ValueKey('annotation-toolbar'));
      expect(tester.getSize(toolbar).height, lessThanOrEqualTo(40));
      expect(tester.getSize(toolbar).width, lessThan(500));
      expect(tester.getRect(toolbar).right, closeTo(500, 1));
      final redo = find.byKey(const ValueKey('annotation-redo'));
      final cancel = find.byKey(const ValueKey('cancel-screenshot'));
      expect(
        tester.getRect(cancel).left - tester.getRect(redo).right,
        lessThanOrEqualTo(12),
        reason: '历史与完成操作之间只保留紧凑的分隔线',
      );
      for (final id in ['annotation-group-shape', 'annotation-group-line']) {
        final button = tester.widget<IconButton>(find.byKey(ValueKey(id)));
        expect(button.icon, isNot(isA<Stack>()), reason: '工具图标不显示更新红点');
      }
      expect(find.byKey(const ValueKey('annotation-properties')), findsNothing);
      expect(
        find.byKey(const ValueKey('annotation-tool-select')),
        findsNothing,
      );
      // Before annotating, selection movement and handles reuse the frozen frame.
      final cropCanvas = find.byKey(const ValueKey('annotation-canvas'));
      await tester.dragFrom(
        tester.getCenter(cropCanvas),
        const Offset(20, 10),
        kind: ui.PointerDeviceKind.mouse,
      );
      for (var i = 0; i < 100; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
        if (!c.imageLoading && c.screenshotSelection!.left == 120) break;
      }
      expect(c.screenshotSelection!.left, 120);
      expect(c.screenshotSelection!.top, 110);
      final handle = find.byKey(const ValueKey('screenshot-handle-se'));
      await tester.drag(
        handle,
        const Offset(20, 20),
        kind: ui.PointerDeviceKind.mouse,
      );
      for (var i = 0; i < 100; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
        if (!c.imageLoading && c.screenshotSelection!.right == 540) break;
      }
      expect(c.screenshotSelection!.right, 540);
      expect(d.beginCalls, 1);
      expect(d.finishCalls, 0);
      for (var i = 0; i < 150; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
        if (tester
                .widget<IconButton>(
                  find.byKey(const ValueKey('copy-screenshot')),
                )
                .onPressed !=
            null) {
          break;
        }
      }

      await tester.tap(find.byKey(const ValueKey('annotation-group-shape')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('annotation-tool-rectangle')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('annotation-tool-ellipse')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('annotation-fill')));
      await tester.sendKeyEvent(LogicalKeyboardKey.bracketRight);
      final canvas = find.byKey(const ValueKey('annotation-canvas'));
      final origin = tester.getTopLeft(canvas);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.dragFrom(
        origin + const Offset(40, 50),
        const Offset(60, 30),
        kind: ui.PointerDeviceKind.mouse,
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      final shape = c.markup.items.single;
      expect(shape.bounds.width, shape.bounds.height);
      expect(shape.toJson()['filled'], true);
      expect(shape.width, 4);
      expect(
        tester.getRect(cancel).left -
            tester
                .getRect(find.byKey(const ValueKey('annotation-delete')))
                .right,
        lessThanOrEqualTo(12),
      );
      await tester.tap(find.byKey(const ValueKey('annotation-group-line')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('annotation-group-shape')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('annotation-tool-ellipse')));
      await tester.pumpAndSettle();
      await tester.dragFrom(
        origin + const Offset(120, 50),
        const Offset(40, 40),
        kind: ui.PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(c.markup.items.last.filled, true);
      expect(c.markup.items.last.width, 4);
      await tester.tap(find.byKey(const ValueKey('annotation-undo')));
      await tester.pumpAndSettle();
      expect(c.markup.items, hasLength(1));
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(toolbar, findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(toolbar, findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('annotation-group-line')));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey('annotation-tool-line')),
            )
            .isSelected,
        true,
      );
      await tester.tapAt(
        origin + const Offset(160, 70),
        kind: ui.PointerDeviceKind.mouse,
      );
      await tester.tapAt(
        origin + const Offset(190, 100),
        kind: ui.PointerDeviceKind.mouse,
      );
      final right = await tester.createGesture(
        kind: ui.PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await right.down(origin + const Offset(220, 70));
      await right.up();
      await tester.pumpAndSettle();
      expect(c.markup.items.length, 2);
      expect(c.markup.items.last.kind, AnnotationKind.line);
      expect(find.byKey(const ValueKey('annotation-properties')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('annotation-tool-text')));
      await tester.pumpAndSettle();
      await tester.tapAt(
        origin + const Offset(80, 150),
        kind: ui.PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      final input = find.byKey(const ValueKey('annotation-text-input'));
      expect(input, findsOneWidget);
      expect(
        tester.getRect(canvas).contains(tester.getRect(input).topLeft),
        true,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(toolbar, findsOneWidget);
      await tester.enterText(input, '原位文字\n第二行');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
      expect(input, findsNothing);
      expect(c.markup.items.last.text, '原位文字\n第二行');
      await tester.tap(find.byKey(const ValueKey('annotation-bold')));
      await tester.pumpAndSettle();
      expect(c.markup.items.last.toJson()['bold'], true);
      await tester.tap(find.byKey(const ValueKey('annotation-edit-text')));
      await tester.pumpAndSettle();
      await tester.enterText(input, '取消这次编辑');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(c.markup.items.last.text, '原位文字\n第二行');
      await tester.tap(find.byKey(const ValueKey('annotation-edit-text')));
      await tester.pumpAndSettle();
      await tester.enterText(input, '应被撤销的文字编辑');
      await tester.tap(find.byKey(const ValueKey('annotation-undo')));
      await tester.pumpAndSettle();
      expect(input, findsNothing);
      expect(c.markup.items.last.text, '原位文字\n第二行');
      expect(c.screenshotEditing, true);
      for (final kind in ['mosaic', 'blur']) {
        if (find.byKey(ValueKey('annotation-tool-$kind')).evaluate().isEmpty) {
          await tester.tap(
            find.byKey(const ValueKey('annotation-group-effect')),
          );
          await tester.pumpAndSettle();
        }
        await tester.tap(find.byKey(ValueKey('annotation-tool-$kind')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('annotation-effect-brush')));
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.bracketRight);
        await tester.tap(
          find.byKey(const ValueKey('annotation-effect-strength')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('annotation-effect-strength-5')),
        );
        await tester.pumpAndSettle();
        await tester.dragFrom(
          origin + const Offset(30, 30),
          const Offset(120, 80),
          kind: ui.PointerDeviceKind.mouse,
        );
        await tester.pumpAndSettle();
        final brush = c.markup.items.last;
        expect(brush.kind.name, kind);
        expect(brush.toJson()['effectBrush'], true);
        expect(brush.toJson()['effectStrength'], 5);
        expect(brush.width, greaterThan(24));
        expect(brush.points.length, greaterThan(2));
        final count = c.markup.items.length;
        await tester.tap(
          find.byKey(const ValueKey('annotation-effect-strength')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('annotation-effect-strength-1')),
        );
        await tester.pumpAndSettle();
        expect(c.markup.items.length, count);
        expect(c.markup.items.last.toJson()['effectStrength'], 1);
        await tester.tap(find.byKey(const ValueKey('annotation-undo')));
        await tester.pumpAndSettle();
        expect(c.markup.items.last, brush);
        await tester.tap(
          find.byKey(const ValueKey('annotation-effect-rectangle')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('annotation-effect-strength')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('annotation-effect-strength-5')),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('annotation-width')), findsNothing);
        await tester.dragFrom(
          origin + const Offset(200, 30),
          const Offset(60, 50),
          kind: ui.PointerDeviceKind.mouse,
        );
        await tester.pumpAndSettle();
        expect(c.markup.items.last.toJson()['effectBrush'], false);
        expect(c.markup.items.last.toJson()['effectStrength'], 5);
        await tester.tap(find.byKey(const ValueKey('annotation-undo')));
        await tester.pumpAndSettle();
        expect(c.markup.items.last, brush);
        await tester.tap(find.byKey(const ValueKey('annotation-redo')));
        await tester.pumpAndSettle();
        expect(c.markup.items.last.toJson()['effectBrush'], false);
        expect(
          tester
              .getRect(find.byKey(const ValueKey('annotation-properties')))
              .right,
          lessThanOrEqualTo(size.width),
        );
      }
      expect(c.busy, true);
      expect(d.showMainCalls, 0);
      expect(tester.takeException(), isNull);
    });
    testWidgets('工具栏在屏幕右下角翻到选区上方且属性条不溢出 $size', (tester) async {
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
              width: size.width.toInt(),
              height: size.height.toInt(),
              logicalWidth: size.width,
              logicalHeight: size.height,
              rgba: Uint8List(size.width.toInt() * size.height.toInt() * 4),
            ),
          ),
        ]);
      final c = AppController(d);
      await c.initialize();
      addTearDown(d.input.close);
      await tester.pumpWidget(ControllerTestHost(controller: c));
      await tester.pumpAndSettle();
      await c.startScreenshot();
      d.pointer(x: size.width - 200, y: size.height - 100, phase: 'down');
      d.pointer(x: size.width - 12, y: size.height - 12, phase: 'up');
      for (var i = 0; i < 150; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
        final copy = find.byKey(const ValueKey('copy-screenshot'));
        if (copy.evaluate().isNotEmpty &&
            tester.widget<IconButton>(copy).onPressed != null) {
          break;
        }
      }
      await tester.pumpAndSettle();
      final toolbar = find.byKey(const ValueKey('annotation-toolbar'));
      expect(tester.getRect(toolbar).bottom, lessThan(size.height - 100));
      await tester.tap(find.byKey(const ValueKey('annotation-tool-text')));
      await tester.pumpAndSettle();
      final properties = find.byKey(const ValueKey('annotation-properties'));
      expect(
        tester.getRect(properties).bottom,
        lessThanOrEqualTo(tester.getRect(toolbar).top - 4),
      );
      expect(
        (Offset.zero & size).contains(tester.getRect(properties).topLeft),
        true,
      );
      expect(
        (Offset.zero & size).contains(tester.getRect(properties).bottomRight),
        true,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
