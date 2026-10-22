import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fruler/app/app_controller.dart';
import 'package:fruler/core/core.dart';
import 'package:fruler/platform/desktop_service.dart';
import 'package:fruler/platform/annotation_renderer.dart';

import '../fake_desktop.dart';
import 'controller_test_host.dart';

void main() {
  for (final size in [const Size(1100, 760), const Size(920, 680)]) {
    for (final ratio in [1, 2]) {
      testWidgets('标注后缩放和移动选区保留标注、历史与原图位置 $size ${ratio}x', (tester) async {
        tester.view.physicalSize = size * ratio.toDouble();
        tester.view.devicePixelRatio = ratio.toDouble();
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final d = FakeDesktop()
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
        final c = AppController(d);
        await c.initialize();
        addTearDown(d.input.close);
        await tester.pumpWidget(ControllerTestHost(controller: c));
        await tester.pumpAndSettle();
        await c.startScreenshot();
        d.pointer(x: 100, y: 100, phase: 'down');
        d.pointer(x: 500, y: 350, phase: 'up');
        Finder key(String id) => find.byKey(ValueKey(id));
        Future<void> ready() async {
          for (var i = 0; i < 150; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 10)),
            );
            await tester.pump();
            final copy = key('copy-screenshot');
            if (!c.imageLoading &&
                copy.evaluate().isNotEmpty &&
                tester.widget<IconButton>(copy).onPressed != null) {
              break;
            }
          }
          await tester.pumpAndSettle();
        }

        await ready();
        expect(key('reselect-screenshot'), findsNothing);
        await tester.tap(key('annotation-group-shape'));
        await tester.pumpAndSettle();
        await tester.tap(key('annotation-fill'));
        await tester.pumpAndSettle();
        await tester.dragFrom(
          const Offset(140, 140),
          const Offset(180, 100),
          kind: ui.PointerDeviceKind.mouse,
        );
        await tester.pumpAndSettle();
        final original = c.markup.items.single;
        final selection = c.screenshotSelection!;
        expect(key('screenshot-handle-nw'), findsOneWidget);
        final drag = await tester.startGesture(
          tester.getCenter(key('screenshot-handle-nw')),
          kind: ui.PointerDeviceKind.mouse,
        );
        await drag.moveBy(const Offset(100, 80));
        await tester.pump();
        expect(c.markup.items.single, original, reason: '拖动预览不能改写标注历史');
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          key('annotation-content'),
        );
        final previewPixels = await tester.runAsync(() async {
          final image = await boundary.toImage();
          try {
            expect((image.width, image.height), (300 * ratio, 170 * ratio));
            final raw = (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!;
            return raw.buffer.asUint8List(raw.offsetInBytes, raw.lengthInBytes);
          } finally {
            image.dispose();
          }
        });
        expect(previewPixels!.sublist(0, 4), [255, 0, 0, 255]);
        await drag.up();
        await ready();
        await tester.runAsync(() async {
          final png = await AnnotationRenderer.export(
            c.imageDocument!.frame,
            c.markup.items,
          );
          final codec = await ui.instantiateImageCodec(png);
          final output = (await codec.getNextFrame()).image;
          try {
            final raw = (await output.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!;
            expect(
              raw.buffer.asUint8List(raw.offsetInBytes, raw.lengthInBytes),
              previewPixels,
              reason: '拖动中的裁切预览与最终 PNG 输出一致',
            );
          } finally {
            output.dispose();
            codec.dispose();
          }
        });
        expect(c.screenshotSelection!.left, selection.left + 100 * ratio);
        expect(
          c.markup.items.single.points,
          original.points.map((p) => p - Offset(100.0 * ratio, 80.0 * ratio)),
        );
        expect(c.markup.items.single.bounds.left, lessThan(0));
        // 跨越新选区边界的标注仍可移动，不跳到边界。
        await tester.dragFrom(
          const Offset(230, 220),
          const Offset(10, 0),
          kind: ui.PointerDeviceKind.mouse,
        );
        await tester.pumpAndSettle();
        expect(
          c.markup.items.single.bounds.left,
          original.bounds.left - 90 * ratio,
        );
        c.markup.undo();
        await tester.pumpAndSettle();
        await tester.dragFrom(
          tester.getCenter(key('screenshot-handle-nw')),
          const Offset(-100, -80),
          kind: ui.PointerDeviceKind.mouse,
        );
        await ready();
        expect(c.screenshotSelection!.toJson(), selection.toJson());
        expect(c.markup.items.single, original);
        // 空白处拖动选区，标注固定在原图位置。
        await tester.tapAt(
          const Offset(400, 300),
          kind: ui.PointerDeviceKind.mouse,
        );
        await tester.pumpAndSettle();
        await tester.dragFrom(
          const Offset(400, 300),
          const Offset(20, 10),
          kind: ui.PointerDeviceKind.mouse,
        );
        await ready();
        expect(c.screenshotSelection!.left, selection.left + 20 * ratio);
        expect(
          c.markup.items.single.bounds.left,
          original.bounds.left - 20 * ratio,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await ready();
        expect(c.screenshotSelection!.left, selection.left + 20 * ratio + 1);
        c.markup.undo();
        expect(c.markup.items, isEmpty);
        c.markup.redo();
        expect(
          c.markup.items.single.bounds.left,
          original.bounds.left - 20 * ratio - 1,
        );
        expect(d.beginCalls, 1);
        expect(d.finishCalls, 0);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
