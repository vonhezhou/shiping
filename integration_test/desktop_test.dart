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

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

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
            await driver.invokeMethod<void>('key', {
              'keyCode': 125,
            }); // Cocoa down arrow
            await waitFor(
              tester,
              () => events.any((e) => e['type'] == 'nudge'),
            );
            expect(events.lastWhere((e) => e['type'] == 'nudge')['dy'], 1);
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
        final doc = c.imageDocument!;
        final canvas = find.byKey(const ValueKey('annotation-canvas'));
        for (final kind in AnnotationKind.values.where(
          (k) => k != AnnotationKind.text,
        )) {
          await click(
            tester,
            find.byKey(ValueKey('annotation-tool-${kind.name}')),
          );
          await mouseDrag(
            tester,
            tester.getCenter(canvas) - const Offset(60, 30),
            const Offset(80, 50),
          );
          await tester.pumpAndSettle();
          expect(c.markup.items.last.kind, kind);
        }
        await click(tester, find.byKey(const ValueKey('annotation-tool-text')));
        await click(tester, canvas);
        await tester.enterText(find.byType(TextField), '原位标注');
        await click(tester, find.text('确定').last);
        expect(c.markup.items.length, 9);
        await click(tester, find.byKey(const ValueKey('annotation-undo')));
        expect(c.markup.items.length, 8);
        await click(tester, find.byKey(const ValueKey('annotation-redo')));
        expect(c.markup.items.length, 9);
        // Erase all intersecting objects in the same native capture panel.
        final beforeErase = List<Annotation>.of(c.markup.items);
        await click(
          tester,
          find.byKey(const ValueKey('annotation-tool-eraser')),
        );
        expect(
          find.byKey(const ValueKey('annotation-properties')),
          findsNothing,
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
        expect(c.markup.items, isEmpty);
        await click(tester, find.byKey(const ValueKey('annotation-undo')));
        expect(c.markup.items, beforeErase);
        await click(tester, find.byKey(const ValueKey('annotation-redo')));
        expect(c.markup.items, isEmpty);
        await click(tester, find.byKey(const ValueKey('annotation-undo')));
        expect(c.markup.items, beforeErase);
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
        expect(c.markup.items.length, 9);
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
        image.dispose();
        codec.dispose();
        final done = await driver.invokeMapMethod<String, Object?>('status');
        expect(done?['panels'], 0);
        expect(done?['mainVisible'], false);
        expect(done?['editing'], false);
        expect(c.imageDocument, isNull);
        expect(c.screenshots.length, 1);
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
        // Picker and ruler must also complete on-screen without reopening history.
        for (final tool in ['picker', 'rectangle']) {
          if (tool == 'picker') {
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
          await waitFor(tester, () => !c.busy);
          expect(
            (await driver.invokeMapMethod<String, Object?>(
              'status',
            ))?['mainVisible'],
            false,
          );
        }
        expect(c.colors, isNotEmpty);
        expect(c.measurements, isNotEmpty);
      } finally {
        await driver.invokeMethod<void>('restoreClipboard');
        c.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );
}
