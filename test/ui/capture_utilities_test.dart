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
    for (final utility in ['picker', 'size']) {
      testWidgets('截图内$utility复用快照并直接复制 $size', (tester) async {
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
        Finder byKey(String key) => find.byKey(ValueKey(key));
        Future<void> click(String key) async {
          await tester.tap(byKey(key), kind: ui.PointerDeviceKind.mouse);
          await tester.pumpAndSettle();
        }

        expect(byKey('annotation-tool-picker'), findsNothing);
        final mouse = await tester.createGesture(
          kind: ui.PointerDeviceKind.mouse,
        );
        await mouse.addPointer(location: const Offset(30, 30));
        await mouse.moveTo(const Offset(40, 40));
        await tester.pump();
        expect(byKey('screenshot-picker-feedback'), findsNothing);
        await mouse.moveTo(const Offset(300, 340));
        await tester.pump();
        expect(byKey('screenshot-picker-feedback'), findsOneWidget);
        expect(byKey('screenshot-magnifier'), findsOneWidget);
        expect(find.textContaining('X: 300'), findsOneWidget);
        expect(
          tester.getSize(byKey('screenshot-color-swatch')),
          const Size(12, 12),
        );
        expect(
          tester.getSize(byKey('screenshot-picker-feedback')).width,
          lessThan(240),
        );
        final stack = tester.widget<Stack>(
          find
              .ancestor(
                of: byKey('screenshot-picker-feedback'),
                matching: find.byType(Stack),
              )
              .first,
        );
        // 放大镜和工具条发生重叠时，最后绘制放大镜。
        expect(
          find.descendant(
            of: find.byWidget(stack.children.last),
            matching: byKey('screenshot-picker-feedback'),
          ),
          findsOneWidget,
        );
        expect(
          tester
              .getRect(byKey('screenshot-picker-feedback'))
              .overlaps(tester.getRect(byKey('annotation-toolbar'))),
          true,
        );
        for (final edge in [
          const Offset(100, 220),
          const Offset(500, 220),
          const Offset(300, 100),
          const Offset(300, 350),
        ]) {
          await mouse.moveTo(edge);
          await tester.pump();
          expect(byKey('screenshot-picker-feedback'), findsOneWidget);
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            byKey('screenshot-magnifier'),
          );
          final pixels = await tester.runAsync(() async {
            final image = await boundary.toImage();
            try {
              return (await image.toByteData())!.buffer.asUint8List();
            } finally {
              image.dispose();
            }
          });
          var bluePixels = 0;
          for (var i = 0; i < pixels!.length; i += 4) {
            if (pixels[i] == 38 &&
                pixels[i + 1] == 131 &&
                pixels[i + 2] == 255) {
              bluePixels++;
            }
          }
          expect(
            c.screenshotColorAt(edge.dx, edge.dy),
            const RgbColor(200, 200, 200),
          );
          expect(bluePixels, greaterThan(30), reason: '放大画面应显示选区边界 $edge');
        }
        await mouse.moveTo(const Offset(501, 220));
        await tester.pump();
        expect(byKey('screenshot-picker-feedback'), findsNothing);

        expect(find.textContaining('400 × 250 px'), findsWidgets);
        await mouse.down(const Offset(500, 225));
        await mouse.moveTo(const Offset(510, 225));
        await tester.pump();
        expect(find.textContaining('410 × 250 px'), findsWidgets);
        expect(byKey('screenshot-magnifier'), findsOneWidget);
        await mouse.cancel();
        await tester.pump();
        expect(c.screenshotSelection!.width, 400);
        await click('annotation-group-shape');
        expect(byKey('screenshot-picker-feedback'), findsNothing);
        final rectangle = Annotation(
          kind: AnnotationKind.rectangle,
          points: [const Offset(20, 20), const Offset(80, 80)],
        );
        c.markup.commit([rectangle]);
        await tester.pump();
        if (utility == 'picker') {
          await mouse.moveTo(const Offset(20, 20));
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
          await tester.pumpAndSettle();
          expect(desktop.clipboard, '#C8C8C8');
        } else {
          await click('copy-screenshot-size');
          expect(desktop.clipboard, contains('400'));
          expect(desktop.clipboard, contains('250'));
          expect(c.measurements, isNotEmpty);
        }
        expect(c.busy, false);
        expect(desktop.beginCalls, 1);
        expect(desktop.finishCalls, 1);
        expect(desktop.showMainCalls, 0);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
