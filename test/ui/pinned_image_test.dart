import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fruler/app/app_controller.dart';
import 'package:fruler/core/core.dart';
import 'package:fruler/platform/desktop_service.dart';

import '../fake_desktop.dart';
import 'controller_test_host.dart';

class ObservedPinDesktop extends FakeDesktop {
  VoidCallback? beforePin;
  int pins = 0;

  @override
  Future<void> pinImage(
    Uint8List png, {
    int? sessionId,
    int? displayId,
    PixelRect? rect,
  }) async {
    beforePin?.call();
    await super.pinImage(
      png,
      sessionId: sessionId,
      displayId: displayId,
      rect: rect,
    );
    pins++;
  }
}

Future<void> waitForPinUi(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 150 && !ready(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  expect(ready(), true);
}

void main() {
  for (final size in [const Size(1100, 760), const Size(920, 680)]) {
    testWidgets('贴图提交未完成文字并可从历史再次贴出 $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final desktop = ObservedPinDesktop()
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
      final controller = AppController(desktop);
      await controller.initialize();
      addTearDown(desktop.input.close);
      await tester.pumpWidget(ControllerTestHost(controller: controller));
      await tester.pumpAndSettle();
      await controller.startScreenshot();
      desktop.pointer(x: 100, y: 100, phase: 'down');
      desktop.pointer(x: 500, y: 350, phase: 'up');
      final pin = find.byKey(const ValueKey('pin-screenshot'));
      await waitForPinUi(
        tester,
        () =>
            pin.evaluate().isNotEmpty &&
            tester.widget<IconButton>(pin).onPressed != null,
      );
      await tester.pumpAndSettle();
      final toolbar = tester.getRect(
        find.byKey(const ValueKey('annotation-toolbar')),
      );
      expect(toolbar.left, greaterThanOrEqualTo(0));
      expect(toolbar.right, lessThanOrEqualTo(size.width));
      expect(toolbar.top, greaterThanOrEqualTo(0));
      expect(toolbar.bottom, lessThanOrEqualTo(size.height));
      expect(toolbar.contains(tester.getCenter(pin)), true);
      for (final key in [
        'pin-screenshot',
        'recognize-qr-code',
        'save-screenshot',
        'copy-screenshot',
      ]) {
        final button = find.byKey(ValueKey(key));
        expect(
          tester.getRect(button).right,
          lessThanOrEqualTo(toolbar.right),
          reason: '贴图和二维码同时存在时，所有导出按钮都应完整显示：$key',
        );
        expect(button.hitTestable(), findsOneWidget);
      }
      await tester.tap(
        find.byKey(const ValueKey('annotation-tool-text')),
        kind: ui.PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      await tester.tapAt(
        tester.getTopLeft(find.byKey(const ValueKey('annotation-canvas'))) +
            const Offset(30, 30),
        kind: ui.PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('annotation-text-input')),
        '贴图备注',
      );
      expect(controller.markup.items, isEmpty);
      List<String>? pinnedTexts;
      desktop.beforePin = () {
        pinnedTexts = controller.markup.items
            .where((annotation) => annotation.kind == AnnotationKind.text)
            .map((annotation) => annotation.text)
            .toList();
      };
      await tester.tap(pin, kind: ui.PointerDeviceKind.mouse);
      await waitForPinUi(tester, () => desktop.pins == 1 && !controller.busy);
      await tester.pumpAndSettle();
      expect(pinnedTexts, ['贴图备注']);
      expect(desktop.finishCalls, 1);
      expect(desktop.showMainCalls, 0);
      expect(desktop.exportedImage, isNull);
      expect(controller.screenshots.single, desktop.pinnedImage);
      final original = desktop.pinnedImage;
      desktop.beforePin = null;
      final historyPin = find.byKey(const ValueKey('pin-history-0'));
      await tester.ensureVisible(historyPin);
      await tester.pumpAndSettle();
      await tester.tap(historyPin, kind: ui.PointerDeviceKind.mouse);
      await waitForPinUi(tester, () => desktop.pins == 2);
      expect(desktop.pinnedImage, original);
      expect(desktop.pinSession, isNull);
      expect(desktop.finishCalls, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('贴图管理入口与快捷键录制可用且不申请录屏 $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final desktop = FakeDesktop()..permission = false;
      final controller = AppController(desktop);
      await controller.initialize();
      addTearDown(desktop.input.close);
      await tester.pumpWidget(ControllerTestHost(controller: controller));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('nav-image')),
        kind: ui.PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      for (final key in ['pin-clipboard', 'toggle-pins', 'close-pins']) {
        final button = find.byKey(ValueKey(key));
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        await tester.tap(button, kind: ui.PointerDeviceKind.mouse);
        await tester.pumpAndSettle();
      }
      expect(desktop.pinClipboardCalls, 1);
      expect(desktop.togglePinCalls, 1);
      expect(desktop.closePinCalls, 1);
      expect(desktop.beginCalls, 0);
      expect(controller.permissionGranted, false);
      await tester.tap(
        find.byKey(const ValueKey('nav-settings')),
        kind: ui.PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      final edit = find.widgetWithText(
        OutlinedButton,
        controller.shortcuts.pinClipboard.label,
      );
      await tester.ensureVisible(edit);
      await tester.pumpAndSettle();
      await tester.tap(edit, kind: ui.PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(desktop.recording, true);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(desktop.recording, false);
      expect(controller.shortcuts.pinClipboard.key, 'P');
      expect(controller.shortcuts.togglePins.key, 'V');
      expect(controller.shortcuts.picker.key, 'C');
      expect(tester.takeException(), isNull);
    });
  }
}
