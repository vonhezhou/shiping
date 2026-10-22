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
    testWidgets('截图标注无尺子切换入口，R 不改变标注与选区 $size', (tester) async {
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
              rgba: Uint8List.fromList(
                List.generate(640 * 480 * 4, (i) => i % 4 == 3 ? 255 : 200),
              ),
            ),
          ),
        ]);
      final c = AppController(d);
      await c.initialize();
      addTearDown(d.input.close);
      await tester.pumpWidget(ControllerTestHost(controller: c));
      await c.startScreenshot();
      d.pointer(x: 100, y: 100, phase: 'down');
      d.pointer(x: 500, y: 350, phase: 'up');
      for (
        var i = 0;
        i < 100 &&
            find.byKey(const ValueKey('annotation-toolbar')).evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();
      final line = find.byKey(const ValueKey('annotation-group-line'));
      await tester.tap(line, kind: ui.PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      final selection = c.screenshotSelection!.toJson();
      final mark = Annotation(
        kind: AnnotationKind.arrow,
        points: [const Offset(20, 20), const Offset(80, 50)],
      );
      c.markup.commit([mark]);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
      await tester.pump();
      expect(tester.widget<IconButton>(line).isSelected, true);
      expect(c.markup.items, [mark]);
      expect(c.screenshotSelection!.toJson(), selection);
      expect(find.byKey(const ValueKey('screenshot-ruler')), findsNothing);
      expect(
        find.byKey(const ValueKey('screenshot-measurement-bar')),
        findsNothing,
      );
      expect(d.beginCalls, 1);
      expect(d.finishCalls, 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(tester.widget<IconButton>(line).isSelected, true);
      expect(tester.takeException(), isNull);
    });
  }
}
