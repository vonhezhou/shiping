import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:fruler/app/app_controller.dart';
import 'package:fruler/core/core.dart';
import 'package:fruler/platform/desktop_service.dart';
import 'package:fruler/ui/fruler_app.dart';

const driver = MethodChannel('dev.fruler/integration');
int mouseSequence = 10000;
TestGesture mouse(WidgetTester tester) {
  final id = ++mouseSequence;
  return TestGesture(
    dispatcher: tester.sendEventToBinding,
    pointer: id,
    device: id,
    kind: ui.PointerDeviceKind.mouse,
  );
}

Future<void> mouseDrag(
  WidgetTester tester,
  ui.Offset start,
  ui.Offset delta,
) async {
  final gesture = mouse(tester);
  await gesture.addPointer(location: start);
  await gesture.down(start);
  await gesture.moveTo(start + delta / 2);
  await gesture.moveTo(start + delta);
  await gesture.up();
  await gesture.removePointer();
}

Future<void> setParameterSlider(
  WidgetTester tester,
  String key,
  double value,
) async {
  final finder = find.byKey(ValueKey(key));
  final slider = tester.widget<Slider>(finder);
  final rect = tester.getRect(finder);
  ui.Offset at(double v) => ui.Offset(
    (rect.left +
            6 +
            (rect.width - 12) * (v - slider.min) / (slider.max - slider.min))
        .clamp(rect.left + 6.01, rect.right - 6.01),
    rect.center.dy,
  );
  final gesture = mouse(tester);
  await gesture.addPointer(location: at(slider.value));
  await gesture.down(at(slider.value));
  await tester.pump(const Duration(milliseconds: 30));
  await gesture.moveTo(at((slider.value + value) / 2));
  await tester.pump(const Duration(milliseconds: 30));
  await gesture.moveTo(at(value));
  await tester.pump(const Duration(milliseconds: 30));
  await gesture.up();
  await gesture.removePointer();
  await tester.pumpAndSettle();
  expect(tester.widget<Slider>(finder).value, closeTo(value, .5));
}

Future<void> nativeWheel(
  WidgetTester tester,
  Offset position,
  int delta,
  int expectedWidth,
) async {
  final old = tester.binding.shouldPropagateDevicePointerEvents;
  tester.binding.shouldPropagateDevicePointerEvents = true;
  try {
    await driver.invokeMethod<void>('scroll', {
      'x': position.dx,
      'y': position.dy,
      'delta': delta,
    });
    await waitFor(
      tester,
      () => find
          .byTooltip('线宽 $expectedWidth pt · 滚轮 / 1、2 / [、]')
          .evaluate()
          .isNotEmpty,
    );
  } finally {
    tester.binding.shouldPropagateDevicePointerEvents = old;
  }
}

/// Only global shortcut registration is suppressed to avoid taking shortcuts
/// away from the interactive app. Capture, events, storage and clipboard are real.
class NativeDesktop extends MacDesktopService {
  CaptureSession? lastCapture;
  @override
  Future<CaptureSession> begin(String tool) async {
    lastCapture = await super.begin(tool);
    return lastCapture!;
  }

  @override
  Future<bool> configureShortcuts(ShortcutBindings bindings) async => true;
}

Future<void> waitFor(WidgetTester tester, bool Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (!ready() && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(
    ready(),
    true,
    reason: 'Native workflow did not complete within 20 seconds',
  );
}

Future<void> click(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  final gesture = mouse(tester);
  await gesture.addPointer(location: tester.getCenter(finder));
  await gesture.down(tester.getCenter(finder));
  await gesture.up();
  await gesture.removePointer();
  await tester.pumpAndSettle();
}

Future<void> chooseAnnotationTool(
  WidgetTester tester,
  AnnotationKind kind,
) async {
  final button = find.byKey(ValueKey('annotation-tool-${kind.name}'));
  if (button.evaluate().isEmpty) {
    final group =
        [AnnotationKind.rectangle, AnnotationKind.ellipse].contains(kind)
        ? 'shape'
        : [AnnotationKind.line, AnnotationKind.arrow].contains(kind)
        ? 'line'
        : 'effect';
    await click(tester, find.byKey(ValueKey('annotation-group-$group')));
  }
  await click(tester, button);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Pigeon native persistence and shortcut errors round trip', (
    tester,
  ) async {
    final desktop = MacDesktopService();
    final original = await desktop.loadState();
    try {
      await desktop.saveState('{"protocolTest":"中文 ∆"}');
      expect(await desktop.loadState(), '{"protocolTest":"中文 ∆"}');
      const duplicate = ShortcutChord(key: 'C', meta: true, shift: true);
      await expectLater(
        desktop.configureShortcuts(
          const ShortcutBindings(picker: duplicate, ruler: duplicate),
        ),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'shortcut_invalid',
          ),
        ),
      );
    } finally {
      await desktop.saveState(original ?? '{}');
    }
  });

  testWidgets(
    'native screenshot command is accepted before permission checks',
    (tester) async {
      final status = await driver.invokeMapMethod<String, Object?>('status');
      expect(
        status?['bundleId'],
        'dev.fruler.integration',
        reason: 'Use tool/test_macos_integration.py to isolate test data',
      );
      final desktop = MacDesktopService();
      final events = <Map<Object?, Object?>>[];
      final subscription = desktop.events.listen(events.add);
      try {
        final status = await desktop.initialize();
        if (!status.permission) {
          await expectLater(
            desktop.begin('screenshot'),
            throwsA(
              isA<PlatformException>().having(
                (e) => e.code,
                'code',
                'screen_permission',
              ),
            ),
          );
        } else {
          final session = await desktop.begin('screenshot');
          try {
            expect(session.displays, isNotEmpty);
            for (final display in session.displays) {
              expect(display.frame.width, greaterThan(0));
              expect(
                display.frame.rgba.length,
                display.frame.width * display.frame.height * 4,
              );
            }
            final beforeKey = events.length;
            await driver.invokeMethod<void>('key', {
              'keyCode': 125,
            }); // Cocoa down arrow
            await waitFor(
              tester,
              () => events
                  .skip(beforeKey)
                  .any(
                    (e) => e['type'] == 'nudge' && e['dx'] == 0 && e['dy'] == 1,
                  ),
            );
            await driver.invokeMethod<void>('key', {
              'keyCode': 53,
            }); // Cocoa Escape
            await waitFor(
              tester,
              () => events.any((e) => e['type'] == 'cancelled'),
            );
            expect(
              (await driver.invokeMapMethod<String, Object?>(
                'status',
              ))?['panels'],
              0,
            );
          } finally {
            await desktop.finish(session.id);
          }
        }
        await expectLater(
          desktop.begin('invalid-test-tool'),
          throwsA(
            isA<PlatformException>().having(
              (e) => e.code,
              'code',
              'invalid_tool',
            ),
          ),
        );
      } finally {
        await subscription.cancel();
        await desktop.showMainWindow();
      }
    },
  );

  testWidgets(
    'same capture panel: select -> annotate -> copy; no main window or projects',
    (tester) async {
      final desktop = NativeDesktop();
      final c = AppController(desktop);
      await c.initialize();
      await tester.pumpWidget(FrulerApp(controller: c));
      await tester.pumpAndSettle();
      try {
        await driver.invokeMethod<void>('backupClipboard');
        expect(
          c.permissionGranted,
          true,
          reason: 'Real screen-recording permission is required',
        );
        expect(find.textContaining('项目'), findsNothing);
        await click(tester, find.byKey(const ValueKey('start-screenshot')));
        await waitFor(
          tester,
          () => desktop.lastCapture != null || c.error != null,
        );
        expect(c.error, isNull);
        final selectionStatus = await driver.invokeMapMethod<String, Object?>(
          'status',
        );
        final display = desktop.lastCapture!.displays.first;
        final endX = (display.frame.logicalWidth - 40).clamp(80.0, 420.0);
        final endY = (display.frame.logicalHeight - 40).clamp(220.0, 400.0);
        for (final event in [
          {'phase': 'down', 'x': 40.0, 'y': 180.0},
          {'phase': 'drag', 'x': endX, 'y': endY},
          {'phase': 'up', 'x': endX, 'y': endY},
        ]) {
          await driver.invokeMethod<void>('pointer', {
            'displayId': display.id,
            ...event,
          });
          await tester.pump();
        }
        await waitFor(tester, () => c.screenshotEditing && !c.imageLoading);
        await tester.pumpAndSettle();
        // The editor receives the frozen selection's raw pixels directly.
        final rawSelection = c.screenshotSelection!;
        final rawDocument = c.imageDocument!.frame;
        expect(
          (rawDocument.width, rawDocument.height),
          (rawSelection.width, rawSelection.height),
        );
        for (final point in [
          const PixelPoint(0, 0),
          PixelPoint(rawDocument.width - 1, rawDocument.height - 1),
          PixelPoint(rawDocument.width ~/ 2, rawDocument.height ~/ 2),
        ]) {
          expect(
            rawDocument.pixelAt(point.x, point.y),
            display.frame.pixelAt(
              rawSelection.left + point.x,
              rawSelection.top + point.y,
            ),
          );
        }
        final editStatus = await driver.invokeMapMethod<String, Object?>(
          'status',
        );
        expect(editStatus?['windowNumber'], selectionStatus?['windowNumber']);
        expect(editStatus?['editing'], true);
        expect(editStatus?['mainVisible'], false);
        expect(c.busy, true);
        expect(find.textContaining('项目'), findsNothing);
        await click(tester, find.byKey(const ValueKey('reselect-screenshot')));
        expect(c.screenshotEditing, false);
        expect(c.busy, true);
        expect(
          (await driver.invokeMapMethod<String, Object?>(
            'status',
          ))?['mainVisible'],
          false,
        );
        for (final event in [
          {'phase': 'down', 'x': 40.0, 'y': 180.0},
          {'phase': 'drag', 'x': endX, 'y': endY},
          {'phase': 'up', 'x': endX, 'y': endY},
        ]) {
          await driver.invokeMethod<void>('pointer', {
            'displayId': display.id,
            ...event,
          });
          await tester.pump();
        }
        await waitFor(tester, () => c.screenshotEditing && !c.imageLoading);
        await tester.pumpAndSettle();
        expect(
          (await driver.invokeMapMethod<String, Object?>(
            'status',
          ))?['windowNumber'],
          selectionStatus?['windowNumber'],
        );
        final canvas = find.byKey(const ValueKey('annotation-canvas'));
        final oldSelection = c.screenshotSelection!;
        await mouseDrag(tester, tester.getCenter(canvas), const Offset(12, 8));
        await waitFor(
          tester,
          () =>
              !c.imageLoading &&
              c.screenshotSelection!.left != oldSelection.left,
        );
        await waitFor(
          tester,
          () =>
              find.byKey(ObjectKey(c.imageDocument)).evaluate().isNotEmpty &&
              tester
                      .widget<IconButton>(
                        find.byKey(const ValueKey('copy-screenshot')),
                      )
                      .onPressed !=
                  null,
        );
        await mouseDrag(
          tester,
          tester.getCenter(find.byKey(const ValueKey('screenshot-handle-se'))),
          const Offset(10, 10),
        );
        await waitFor(
          tester,
          () =>
              !c.imageLoading &&
              c.imageDocument!.frame.width > oldSelection.width,
        );
        await waitFor(
          tester,
          () =>
              find.byKey(ObjectKey(c.imageDocument)).evaluate().isNotEmpty &&
              tester
                      .widget<IconButton>(
                        find.byKey(const ValueKey('copy-screenshot')),
                      )
                      .onPressed !=
                  null,
        );
        expect(
          (await driver.invokeMapMethod<String, Object?>(
            'status',
          ))?['windowNumber'],
          selectionStatus?['windowNumber'],
        );
        final doc = c.imageDocument!;
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await waitFor(
          tester,
          () => find
              .byKey(const ValueKey('annotation-toolbar'))
              .evaluate()
              .isEmpty,
        );
        expect(find.byKey(const ValueKey('annotation-toolbar')), findsNothing);
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await waitFor(
          tester,
          () => find
              .byKey(const ValueKey('annotation-toolbar'))
              .evaluate()
              .isNotEmpty,
        );
        for (final kind in AnnotationKind.values.where(
          (k) => k != AnnotationKind.text && k != AnnotationKind.eraser,
        )) {
          await chooseAnnotationTool(tester, kind);
          if (kind == AnnotationKind.rectangle) {
            await click(tester, find.byKey(const ValueKey('annotation-fill')));
          }
          await mouseDrag(
            tester,
            tester.getCenter(canvas) - const Offset(60, 30),
            const Offset(80, 50),
          );
          await tester.pumpAndSettle();
          expect(c.markup.items.last.kind, kind);
          if (kind == AnnotationKind.rectangle) {
            expect(c.markup.items.last.filled, true);
          }
          if (kind == AnnotationKind.marker) {
            await nativeWheel(tester, tester.getCenter(canvas), 1, 13);
            expect(c.markup.items.last.width / c.screenshotScaleX, 13);
            expect(
              find.descendant(
                of: find.byKey(const ValueKey('annotation-width')),
                matching: find.text('13'),
              ),
              findsOneWidget,
            );
            await nativeWheel(tester, tester.getCenter(canvas), -1, 12);
            expect(c.markup.items.last.width / c.screenshotScaleX, 12);
            expect(
              find.descendant(
                of: find.byKey(const ValueKey('annotation-width')),
                matching: find.byType(Text),
              ),
              findsNothing,
            );
          }
          if ([AnnotationKind.mosaic, AnnotationKind.blur].contains(kind)) {
            expect(c.markup.items.last.effectBrush, false);
            expect(
              find.byKey(const ValueKey('annotation-effect-width')),
              findsNothing,
            );
            expect(find.byType(Slider), findsOneWidget);
            await setParameterSlider(tester, 'annotation-effect-strength', 5);
            await click(
              tester,
              find.byKey(const ValueKey('annotation-effect-brush')),
            );
            expect(
              find.byKey(const ValueKey('annotation-effect-width')),
              findsNothing,
            );
            expect(
              find.byKey(const ValueKey('annotation-width')),
              findsOneWidget,
            );
            await nativeWheel(
              tester,
              tester.getCenter(canvas),
              1,
              kind == AnnotationKind.mosaic ? 25 : 26,
            );
            expect(
              tester
                  .getSize(find.byKey(const ValueKey('annotation-properties')))
                  .height,
              32,
            );
            expect(
              find.byKey(const ValueKey('annotation-effect-strength')),
              findsOneWidget,
            );
            expect(find.byType(Slider), findsOneWidget);
            expect(
              tester
                  .widget<Slider>(
                    find.byKey(const ValueKey('annotation-effect-strength')),
                  )
                  .value,
              5,
            );
            await mouseDrag(
              tester,
              tester.getCenter(canvas) - const Offset(100, 60),
              const Offset(60, 40),
            );
            await tester.pumpAndSettle();
            final brush = c.markup.items.last;
            expect(brush.kind, kind);
            expect(brush.effectBrush, true);
            expect(brush.effectStrength, 5);
            expect(brush.width / c.screenshotScaleX, greaterThan(24));
            expect(brush.points.length, greaterThan(2));
            await click(tester, find.byKey(const ValueKey('annotation-undo')));
            expect(c.markup.items.last.effectBrush, false);
            await click(tester, find.byKey(const ValueKey('annotation-redo')));
            expect(c.markup.items.last, brush);
            await click(
              tester,
              find.byKey(const ValueKey('annotation-effect-rectangle')),
            );
          }
        }
        expect(
          find.byKey(const ValueKey('annotation-tool-select')),
          findsNothing,
        );
        await click(tester, find.byKey(const ValueKey('annotation-tool-text')));
        await click(tester, canvas);
        expect(find.byType(AlertDialog), findsNothing);
        await driver.invokeMethod<void>('insertText', {'text': '原位标注\n第二行'});
        await waitFor(
          tester,
          () => tester
              .widget<TextField>(
                find.byKey(const ValueKey('annotation-text-input')),
              )
              .controller!
              .text
              .contains('第二行'),
        );
        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        await tester.pumpAndSettle();
        expect(c.markup.items.length, 11);
        expect(c.markup.items.last.text, '原位标注\n第二行');
        expect(c.markup.items.last.fontSize / c.screenshotScaleY, 24);
        await click(tester, find.byKey(const ValueKey('annotation-undo')));
        expect(c.markup.items.length, 10);
        await click(tester, find.byKey(const ValueKey('annotation-redo')));
        expect(c.markup.items.length, 11);
        // Re-pick and transform a whole old rectangle after a local erasure.
        // Both edits stay in this real native capture panel.
        final beforeObjectEditing = List<Annotation>.of(c.markup.items);
        final rectangle = beforeObjectEditing.firstWhere(
          (a) => a.kind == AnnotationKind.rectangle,
        );
        c.markup.commit([rectangle]);
        await tester.pumpAndSettle();
        final canvasOrigin = tester.getTopLeft(canvas);
        Offset onCanvas(Offset p) =>
            canvasOrigin +
            Offset(p.dx / c.screenshotScaleX, p.dy / c.screenshotScaleY);
        await click(
          tester,
          find.byKey(const ValueKey('annotation-tool-eraser')),
        );
        await mouseDrag(
          tester,
          onCanvas(rectangle.bounds.topCenter) - const Offset(12, 8),
          const Offset(24, 16),
        );
        await tester.pumpAndSettle();
        expect(c.markup.items.length, 2);
        final stationaryErasure = c.markup.items.last;
        expect(c.markup.items.first, same(rectangle));
        await chooseAnnotationTool(tester, AnnotationKind.rectangle);
        await mouseDrag(
          tester,
          onCanvas(rectangle.bounds.centerLeft),
          const Offset(30, 0),
        );
        await tester.pumpAndSettle();
        expect(c.markup.items.length, 2);
        final movedRectangle = c.markup.items.first;
        expect(
          movedRectangle.points,
          rectangle.points.map((p) => p + Offset(30 * c.screenshotScaleX, 0)),
        );
        expect(c.markup.items.last, same(stationaryErasure));
        await mouseDrag(
          tester,
          onCanvas(movedRectangle.bounds.bottomRight),
          const Offset(10, 15),
        );
        await tester.pumpAndSettle();
        expect(c.markup.items.first.points.length, 2);
        expect(
          c.markup.items.first.bounds.topLeft,
          movedRectangle.bounds.topLeft,
        );
        expect(
          c.markup.items.first.bounds.bottomRight,
          movedRectangle.bounds.bottomRight +
              Offset(10 * c.screenshotScaleX, 15 * c.screenshotScaleY),
        );
        expect(c.markup.items.last, same(stationaryErasure));
        await click(tester, find.byKey(const ValueKey('annotation-undo')));
        expect(c.markup.items, [movedRectangle, stationaryErasure]);
        await click(tester, find.byKey(const ValueKey('annotation-undo')));
        expect(c.markup.items, [rectangle, stationaryErasure]);
        await click(tester, find.byKey(const ValueKey('annotation-redo')));
        expect(c.markup.items, [movedRectangle, stationaryErasure]);
        expect(
          (await driver.invokeMapMethod<String, Object?>(
            'status',
          ))?['windowNumber'],
          selectionStatus?['windowNumber'],
        );
        c.markup.commit(beforeObjectEditing);
        await tester.pumpAndSettle();
        // Partially erase annotation pixels in the same native capture panel.
        final beforeErase = List<Annotation>.of(c.markup.items);
        await click(
          tester,
          find.byKey(const ValueKey('annotation-tool-eraser')),
        );
        expect(
          find.byKey(const ValueKey('annotation-eraser-rectangle')),
          findsOneWidget,
        );
        final erase = mouse(tester);
        final center = tester.getCenter(canvas);
        await erase.addPointer(location: center - const Offset(80, 60));
        await erase.down(center - const Offset(80, 60));
        await erase.moveTo(center + const Offset(100, 100));
        await tester.pump();
        expect(c.markup.items, beforeErase);
        await erase.up();
        await erase.removePointer();
        await tester.pumpAndSettle();
        expect(c.markup.items.take(beforeErase.length), beforeErase);
        expect(c.markup.items.last.kind, AnnotationKind.eraser);
        await click(tester, find.byKey(const ValueKey('annotation-undo')));
        expect(c.markup.items, beforeErase);
        await click(tester, find.byKey(const ValueKey('annotation-redo')));
        expect(c.markup.items.take(beforeErase.length), beforeErase);
        expect(c.markup.items.last.kind, AnnotationKind.eraser);
        await click(tester, find.byKey(const ValueKey('annotation-undo')));
        expect(c.markup.items, beforeErase);
        await click(
          tester,
          find.byKey(const ValueKey('annotation-eraser-brush')),
        );
        await mouseDrag(
          tester,
          center - const Offset(20, 40),
          const Offset(0, 80),
        );
        await tester.pumpAndSettle();
        expect(c.markup.items.take(beforeErase.length), beforeErase);
        expect(c.markup.items.last.kind, AnnotationKind.eraser);
        expect(c.markup.items.last.effectBrush, true);
        await click(tester, find.byKey(const ValueKey('annotation-undo')));
        expect(c.markup.items, beforeErase);
        await click(tester, find.byKey(const ValueKey('annotation-redo')));
        final erasedX = (doc.frame.width / 2 - 20 * c.screenshotScaleX).round();
        final erasedY = (doc.frame.height / 2).round();
        final originalPixel = doc.frame.pixelAt(erasedX, erasedY);
        expect(
          (await driver.invokeMapMethod<String, Object?>(
            'status',
          ))?['windowNumber'],
          selectionStatus?['windowNumber'],
        );
        await driver.invokeMethod<void>('cancelNextSave');
        await c.exportScreenshot(save: true);
        await tester.pumpAndSettle();
        expect(c.screenshotEditing, true);
        expect(c.busy, true);
        expect(c.markup.items.length, 12);
        expect(
          (await driver.invokeMapMethod<String, Object?>(
            'status',
          ))?['mainVisible'],
          false,
        );
        await click(tester, find.byKey(const ValueKey('copy-screenshot')));
        await waitFor(tester, () => !c.busy);
        final png = await driver.invokeMethod<Uint8List>('clipboardPng');
        expect(png, isNotNull);
        final codec = await ui.instantiateImageCodec(png!);
        final image = (await codec.getNextFrame()).image;
        expect(
          (image.width, image.height),
          (doc.frame.width, doc.frame.height),
        );
        final raw = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        final pixels = raw.buffer.asUint8List(
          raw.offsetInBytes,
          raw.lengthInBytes,
        );
        final pixelOffset = (erasedY * image.width + erasedX) * 4;
        expect(pixels.sublist(pixelOffset, pixelOffset + 4), [
          originalPixel.r,
          originalPixel.g,
          originalPixel.b,
          255,
        ]);
        image.dispose();
        codec.dispose();
        final done = await driver.invokeMapMethod<String, Object?>('status');
        expect(done?['panels'], 0);
        expect(done?['mainVisible'], false);
        expect(done?['editing'], false);
        expect(c.imageDocument, isNull);
        expect(c.screenshots.length, 1);
        expect(c.screenshots.single, orderedEquals(png));
        desktop.lastCapture = null;
        await c.startScreenshot();
        await driver.invokeMethod<void>('key', {'keyCode': 53});
        await waitFor(tester, () => !c.busy);
        expect(c.screenshots.length, 1);
        expect(
          (await driver.invokeMapMethod<String, Object?>(
            'status',
          ))?['mainVisible'],
          false,
        );
        // Picker completes on-screen without reopening history.
        for (final tool in ['picker']) {
          if (tool == 'picker') {
            c.setContinuousPicker(false);
            await c.pickColor();
          } else {
            await c.startRuler();
          }
          final d = desktop.lastCapture!.displays.first;
          await driver.invokeMethod<void>('pointer', {
            'displayId': d.id,
            'phase': 'down',
            'x': 80.0,
            'y': 180.0,
          });
          await driver.invokeMethod<void>('pointer', {
            'displayId': d.id,
            'phase': 'up',
            'x': 180.0,
            'y': 240.0,
          });
          try {
            await waitFor(tester, () => !c.busy);
          } catch (_) {
            debugPrint(
              'picker completion: busy=${c.busy}, error=${c.error}, colors=${c.colors.length}, native=${await driver.invokeMethod<Object?>("status")}',
            );
            rethrow;
          }
          expect(
            (await driver.invokeMapMethod<String, Object?>(
              'status',
            ))?['mainVisible'],
            false,
          );
        }
        expect(c.colors, isNotEmpty);
      } finally {
        await driver.invokeMethod<void>('restoreClipboard');
        c.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );
  testWidgets(
    'rectangle ruler retains results, moves/resizes and adds multiple regions',
    (tester) async {
      final desktop = NativeDesktop();
      final c = AppController(desktop);
      await c.initialize();
      await tester.pumpWidget(FrulerApp(controller: c));
      await tester.pumpAndSettle();
      Future<Map> state() async {
        final data = await driver.invokeMapMethod<String, Object?>('status');
        return (data!['rulerViews'] as List).cast<Map>().firstWhere(
          (view) => view['displayId'] == desktop.lastCapture!.displays.first.id,
        );
      }

      Future<void> drag(
        double x,
        double y,
        double endX,
        double endY, {
        bool adjust = false,
      }) async {
        for (final e in [
          {'phase': 'down', 'x': x, 'y': y},
          {'phase': 'drag', 'x': endX, 'y': endY},
          {'phase': 'up', 'x': endX, 'y': endY},
        ]) {
          await driver.invokeMethod<void>('pointer', {
            'displayId': desktop.lastCapture!.displays.first.id,
            'warp': true,
            ...e,
          });
          await tester.pumpAndSettle();
          if (adjust) {
            expect(
              (await state())['cursor'],
              e['phase'] == 'up' ? 'openHand' : 'closedHand',
            );
          }
        }
      }

      Future<void> hoverNative(num x, num y, String cursor) async {
        await driver.invokeMethod<void>('pointer', {
          'displayId': desktop.lastCapture!.displays.first.id,
          'warp': true,
          'phase': 'move',
          'x': x.toDouble(),
          'y': y.toDouble(),
        });
        await tester.pumpAndSettle();
        expect((await state())['cursor'], cursor);
      }

      try {
        await driver.invokeMethod<void>('backupClipboard');
        expect(
          c.permissionGranted,
          true,
          reason: 'Real screen-recording permission is required',
        );
        await c.startRuler();
        await tester.pumpAndSettle();
        final before = await driver.invokeMapMethod<String, Object?>('status');
        for (final size in [const Size(1100, 760), const Size(920, 680)]) {
          expect(
            await driver.invokeMethod<bool>('rulerLayout', {
              'width': size.width,
              'height': size.height,
            }),
            true,
            reason: 'Native ruler controls must fit $size',
          );
        }
        await drag(80, 180, 180, 240);
        expect(c.busy, true);
        var native = await state();
        expect(native['pins'], hasLength(1));
        expect(native['selectedPin'], 1);
        expect(native['copySizeEnabled'], true);
        var pin = (native['pins'] as List).single as Map;
        expect(pin['width'], 100.0);
        expect(pin['label'], contains('pt'));
        // Result remains on screen even after the pointer moves away.
        await driver.invokeMethod<void>('pointer', {
          'displayId': desktop.lastCapture!.displays.first.id,
          'warp': true,
          'phase': 'move',
          'x': 600.0,
          'y': 450.0,
        });
        await tester.pumpAndSettle();
        expect((await state())['pins'], hasLength(1));
        await hoverNative(130, 210, 'openHand');
        final copy = ((await state())['controls'] as Map)['copySize'] as Map;
        await hoverNative(copy['x'] as num, copy['y'] as num, 'pointingHand');
        await hoverNative(600, 450, 'crosshair');
        await drag(130, 210, 150, 230, adjust: true);
        pin = ((await state())['pins'] as List).single as Map;
        expect(pin['x'], 100.0);
        expect(pin['y'], 200.0);
        await drag(200, 260, 230, 280, adjust: true);
        pin = ((await state())['pins'] as List).single as Map;
        expect(pin['width'], 130.0);
        expect(pin['height'], 80.0);
        await driver.invokeMethod<void>('key', {'keyCode': 8, 'command': true});
        await tester.pumpAndSettle();
        final text = await driver.invokeMethod<String>('clipboardText');
        expect(text, contains('130 × 80 pt'));
        expect(c.busy, true);
        await drag(300, 300, 360, 350);
        expect((await state())['pins'], hasLength(2));
        await driver.invokeMethod<void>('key', {'keyCode': 6, 'command': true});
        await tester.pumpAndSettle();
        expect((await state())['pins'], hasLength(1));
        await driver.invokeMethod<void>('key', {
          'keyCode': 6,
          'command': true,
          'shift': true,
        });
        await tester.pumpAndSettle();
        expect((await state())['pins'], hasLength(2));
        final recordsBeforeDelete = List<MeasurementRecord>.of(c.measurements);
        // Delete works without entering a separate edit mode, with undo.
        await drag(330, 325, 330, 325, adjust: true);
        await driver.invokeMethod<void>('key', {'keyCode': 51});
        await tester.pumpAndSettle();
        expect((await state())['pins'], hasLength(1));
        expect(c.busy, true);
        final disabledDelete =
            ((await state())['controls'] as Map)['delete'] as Map;
        expect(disabledDelete['enabled'], false);
        await hoverNative(
          disabledDelete['x'] as num,
          disabledDelete['y'] as num,
          'arrow',
        );
        await driver.invokeMethod<void>('key', {'keyCode': 6, 'command': true});
        await tester.pumpAndSettle();
        expect((await state())['pins'], hasLength(2));
        await drag(330, 325, 330, 325, adjust: true);
        final delete = ((await state())['controls'] as Map)['delete'] as Map;
        await hoverNative(
          delete['x'] as num,
          delete['y'] as num,
          'pointingHand',
        );
        expect(
          await driver.invokeMethod<bool>('clickRulerControl', {
            'name': 'delete',
          }),
          true,
        );
        await tester.pumpAndSettle();
        expect((await state())['pins'], hasLength(1));
        await drag(140, 230, 140, 230, adjust: true);
        await driver.invokeMethod<void>('key', {'keyCode': 117});
        await tester.pumpAndSettle();
        expect((await state())['pins'], isEmpty);
        expect(c.busy, true);
        expect(c.measurements, recordsBeforeDelete);
        await hoverNative(140, 230, 'crosshair');
        await driver.invokeMethod<void>('key', {'keyCode': 6, 'command': true});
        await tester.pumpAndSettle();
        expect((await state())['pins'], hasLength(1));
        // Select the first region again; arrows move a backing pixel.
        await drag(140, 230, 140, 230);
        pin = ((await state())['pins'] as List).first as Map;
        final left = pin['x'] as num;
        await driver.invokeMethod<void>('key', {'keyCode': 124});
        await tester.pumpAndSettle();
        pin = ((await state())['pins'] as List).first as Map;
        expect(
          pin['x'],
          closeTo(
            left + 1 / desktop.lastCapture!.displays.first.frame.scaleX,
            .001,
          ),
        );
        final active = await driver.invokeMapMethod<String, Object?>('status');
        expect(active?['windowNumber'], before?['windowNumber']);
        expect(active?['mainVisible'], false);
        await driver.invokeMethod<void>('key', {'keyCode': 36});
        await waitFor(tester, () => !c.busy);
        expect(
          (await driver.invokeMapMethod<String, Object?>('status'))?['panels'],
          0,
        );
        expect(
          (await driver.invokeMapMethod<String, Object?>(
            'status',
          ))?['mainVisible'],
          false,
        );
        await c.startRuler();
        await drag(80, 180, 180, 240);
        await driver.invokeMethod<void>('key', {'keyCode': 53});
        await waitFor(tester, () => !c.busy);
      } finally {
        if (c.busy) await driver.invokeMethod<void>('key', {'keyCode': 53});
        await driver.invokeMethod<void>('restoreClipboard');
        c.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );
}
