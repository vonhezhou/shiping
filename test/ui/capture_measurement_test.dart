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
    testWidgets('选区后仅自动测距，保留多框和标注，重新框选恢复手动 $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final d = FakeDesktop()
        ..capture = CaptureSession(7, [
          CapturedDisplay(
            id: 1,
            name: 'Retina',
            frame: PixelFrame(
              width: 1200,
              height: 900,
              logicalWidth: 600,
              logicalHeight: 450,
              rgba: Uint8List.fromList(
                List.generate(1200 * 900 * 4, (i) => i % 4 == 3 ? 255 : 200),
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
      d.event('modeChanged', {'tool': 'rectangle'});
      for (final x in [50.0, 150.0]) {
        d.pointer(x: x, y: 100, phase: 'down');
        d.pointer(x: x + 80, y: 160, phase: 'up');
      }
      expect(c.captureMeasurementPins, hasLength(2));
      expect(
        c.captureMeasurementPins.first.measurement.label,
        '160 × 120 px · 80 × 60 pt',
      );
      await c.useMeasurementSelection();
      for (
        var i = 0;
        i < 100 &&
            find.byKey(const ValueKey('copy-screenshot')).evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();
      final selection = c.screenshotSelection!.toJson();
      c.markup.commit([
        Annotation(
          kind: AnnotationKind.rectangle,
          points: [const Offset(5, 5), const Offset(30, 30)],
        ),
      ]);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
      await tester.pumpAndSettle();
      expect(c.captureRulerMode, RulerMode.cross);
      final manual = find.byKey(const ValueKey('screenshot-manual-measure'));
      expect(tester.widget<IconButton>(manual).onPressed, isNull);
      for (final mode in [
        RulerMode.horizontal,
        RulerMode.vertical,
        RulerMode.cross,
      ]) {
        final button = tester.widget<IconButton>(
          find.byKey(ValueKey('screenshot-measure-${mode.name}')),
        );
        expect(button.tooltip, contains('自动测距'));
        expect(button.isSelected, mode == RulerMode.cross);
      }
      c.setCaptureRulerMode(RulerMode.rectangle);
      expect(c.captureRulerMode, RulerMode.cross);
      expect(find.byKey(const ValueKey('screenshot-handle-se')), findsNothing);
      final mouse = await tester.createGesture(
        kind: ui.PointerDeviceKind.mouse,
      );
      await mouse.addPointer(location: const Offset(30, 100));
      await mouse.moveTo(const Offset(40, 120));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('screenshot-picker-feedback')),
        findsOneWidget,
      );
      await mouse.down(const Offset(40, 120));
      await mouse.up();
      await tester.pump();
      expect(c.captureMeasurementPins, hasLength(3));
      expect(c.screenshotSelection!.toJson(), selection);
      expect(c.markup.items, hasLength(1));
      expect(d.clipboard, isNull);
      // 删除／撤销只影响测量，不修改标注。
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();
      expect(c.captureMeasurementPins, hasLength(2));
      c.captureMeasurementHistory(false);
      await tester.pump();
      expect(c.captureMeasurementPins, hasLength(3));
      expect(c.markup.items, hasLength(1));
      await tester.tap(
        find.byKey(const ValueKey('annotation-undo')),
        kind: ui.PointerDeviceKind.mouse,
      );
      await tester.pump();
      expect(c.captureMeasurementPins, hasLength(2));
      expect(c.markup.items, hasLength(1));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(c.busy, true);
      expect(c.captureRulerMode, isNull);
      await c.reselectScreenshot();
      c.setCaptureRulerMode(RulerMode.rectangle);
      expect(c.captureRulerMode, RulerMode.rectangle);
      expect(c.captureMeasurementPins, hasLength(2));
      expect(c.markup.items, isEmpty);
      expect(d.beginCalls, 1);
      expect(tester.takeException(), isNull);
      await mouse.removePointer();
    });
  }
}
