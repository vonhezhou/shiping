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

        final rectangle = Annotation(
          kind: AnnotationKind.rectangle,
          points: [const Offset(20, 20), const Offset(80, 80)],
        );
        c.markup.commit([rectangle]);
        await tester.pump();
        if (utility == 'picker') {
          await click('annotation-tool-picker');
          expect(c.markup.items, [rectangle]);
          expect(c.markup.canUndo, true);
          await click('annotation-tool-picker');
          expect(c.markup.items, [rectangle]);
          await click('annotation-tool-picker');
          await tester.tapAt(
            const Offset(20, 20),
            kind: ui.PointerDeviceKind.mouse,
          );
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
