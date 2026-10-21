import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fruler/app/app_controller.dart';
import 'package:fruler/core/core.dart';
import 'package:fruler/platform/desktop_service.dart';

import '../fake_desktop.dart';
import 'controller_test_host.dart';

void main() {
  for (final ratio in [1, 2]) {
    for (final size in [const Size(1100, 760), const Size(920, 680)]) {
      testWidgets('局部擦除后从旧矩形边缘移动整个对象，擦除区域独立 ${ratio}x $size', (tester) async {
        tester.view.physicalSize = size * ratio.toDouble();
        tester.view.devicePixelRatio = ratio.toDouble();
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final desktop = FakeDesktop()
          ..capture = CaptureSession(7, [
            CapturedDisplay(
              id: 1,
              name: 'screen',
              frame: PixelFrame(
                width: 640 * ratio,
                height: 480 * ratio,
                logicalWidth: 640,
                logicalHeight: 480,
                rgba: Uint8List.fromList(
                  List.generate(
                    640 * 480 * ratio * ratio * 4,
                    (i) => i % 4 == 3 ? 255 : 200,
                  ),
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
        final canvas = find.byKey(const ValueKey('annotation-canvas'));
        final origin = tester.getTopLeft(canvas);
        final rectangle = Annotation(
          kind: AnnotationKind.rectangle,
          points: [
            const Offset(40, 40) * ratio.toDouble(),
            const Offset(180, 140) * ratio.toDouble(),
          ],
          width: 4 * ratio.toDouble(),
        );
        c.markup.commit([rectangle]);
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('annotation-tool-eraser')));
        await tester.pumpAndSettle();
        await tester.dragFrom(
          origin + const Offset(90, 30),
          const Offset(40, 20),
          kind: ui.PointerDeviceKind.mouse,
        );
        await tester.pumpAndSettle();
        expect(c.markup.items.length, 2);
        final eraser = c.markup.items.last;
        expect(eraser.kind, AnnotationKind.eraser);
        expect(c.markup.items.first, same(rectangle));
        await tester.tap(find.byKey(const ValueKey('annotation-group-shape')));
        await tester.pumpAndSettle();
        final mouse = TestGesture(
          dispatcher: tester.sendEventToBinding,
          pointer: 91001,
          device: 91001,
          kind: ui.PointerDeviceKind.mouse,
        );
        await mouse.addPointer(location: origin + const Offset(60, 40));
        await mouse.moveTo(origin + const Offset(60, 40));
        await tester.pump();
        expect(
          RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(91001),
          SystemMouseCursors.grab,
        );
        await mouse.down(origin + const Offset(60, 40));
        await mouse.moveTo(origin + const Offset(60, 100));
        await tester.pump();
        expect(c.markup.items, [rectangle, eraser], reason: '拖动期间仅预览，不能改写历史');
        await mouse.up();
        await tester.pumpAndSettle();
        expect(c.markup.items.length, 2, reason: '移动完整对象，不拆分也不新建标注');
        final moved = c.markup.items.first;
        expect(
          moved.points,
          rectangle.points.map((p) => p + Offset(0, 60 * ratio.toDouble())),
        );
        expect(c.markup.items.last, same(eraser));
        expect(
          rectangle.points.first,
          Offset(40 * ratio.toDouble(), 40 * ratio.toDouble()),
        );
        // The selected object's corner resizes the complete rectangle.
        await mouse.moveTo(origin + const Offset(180, 200));
        await mouse.down(origin + const Offset(180, 200));
        await mouse.moveTo(origin + const Offset(220, 220));
        await mouse.up();
        await tester.pumpAndSettle();
        expect(c.markup.items.first.points.length, 2);
        expect(
          c.markup.items.first.bounds,
          Rect.fromLTRB(40, 100, 220, 220).scaleForTest(ratio),
        );
        expect(c.markup.items.last, same(eraser));
        await tester.tap(find.byKey(const ValueKey('annotation-undo')));
        await tester.pumpAndSettle();
        expect(c.markup.items, [moved, eraser]);
        await tester.tap(find.byKey(const ValueKey('annotation-undo')));
        await tester.pumpAndSettle();
        expect(c.markup.items, [rectangle, eraser]);
        await tester.tap(find.byKey(const ValueKey('annotation-redo')));
        await tester.pumpAndSettle();
        expect(c.markup.items, [moved, eraser]);
        // Hover changes only cursor feedback, not the composed annotation layer.
        final content = find.byKey(const ValueKey('annotation-content'));
        final paintFinder = find.descendant(
          of: content,
          matching: find.byType(CustomPaint),
        );
        final before = tester.widget<CustomPaint>(paintFinder).painter!;
        await mouse.moveTo(origin + const Offset(60, 100));
        await tester.pump();
        final after = tester.widget<CustomPaint>(paintFinder).painter!;
        expect(after.shouldRepaint(before), false);
        await mouse.removePointer();
        await c.cancelScreenshot();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
}

extension on Rect {
  Rect scaleForTest(int n) =>
      Rect.fromLTRB(left * n, top * n, right * n, bottom * n);
}
