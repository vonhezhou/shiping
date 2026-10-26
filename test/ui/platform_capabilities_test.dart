import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fruler/app/app_controller.dart';
import 'package:fruler/platform/desktop_service.dart';

import '../fake_desktop.dart';
import 'controller_test_host.dart';
import 'qr_code_test.dart' show editor, QrUiDesktop;

void main() {
  for (final size in [const Size(1100, 760), const Size(920, 680)]) {
    testWidgets('按能力隐藏导航和贴图入口，截图仍可使用 $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final desktop = FakeDesktop()..capabilities = {DesktopFeature.screenshot};
      final c = AppController(desktop);
      await c.initialize();
      addTearDown(desktop.input.close);
      await tester.pumpWidget(ControllerTestHost(controller: c));
      await tester.pumpAndSettle();
      for (final name in ['picker', 'ruler', 'recording']) {
        expect(find.byKey(ValueKey('nav-$name')), findsNothing);
      }
      expect(find.text(c.shortcuts.picker.label), findsNothing);
      expect(find.text(c.shortcuts.ruler.label), findsNothing);
      expect(find.text(c.shortcuts.pinClipboard.label), findsNothing);
      expect(find.text(c.shortcuts.togglePins.label), findsNothing);
      expect(find.text(c.shortcuts.screenshot.label), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('nav-image')),
        kind: ui.PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('start-screenshot')), findsOneWidget);
      expect(find.byKey(const ValueKey('pin-clipboard')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('截图不依赖 OCR、二维码或贴图，工具栏隐藏缺失能力 $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final desktop = QrUiDesktop()..capabilities = {DesktopFeature.screenshot};
      final c = await editor(tester, desktop);
      for (final key in [
        'recognize-text',
        'recognize-qr-code',
        'pin-screenshot',
      ]) {
        expect(find.byKey(ValueKey(key)), findsNothing);
      }
      await c.recognizeText();
      await c.recognizeQrCodes();
      await c.pinScreenshot();
      expect(c.error, isNull);
      expect(c.screenshotEditing, isTrue);
      expect(desktop.pinnedImage, isNull);
      expect(find.byKey(const ValueKey('copy-screenshot')), findsOneWidget);
      expect(find.byKey(const ValueKey('save-screenshot')), findsOneWidget);
      final compactWidth = tester
          .getSize(find.byKey(const ValueKey('annotation-toolbar')))
          .width;
      desktop.capabilities = DesktopFeature.values.toSet();
      c.selectSection(AppSection.image);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('recognize-text')), findsOneWidget);
      expect(find.byKey(const ValueKey('recognize-qr-code')), findsOneWidget);
      expect(find.byKey(const ValueKey('pin-screenshot')), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const ValueKey('annotation-toolbar'))).width,
        greaterThan(compactWidth),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('未适配的平台只保留通用设置入口', (tester) async {
    final c = AppController(UnsupportedDesktopService());
    await c.initialize();
    await tester.pumpWidget(ControllerTestHost(controller: c));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('nav-settings')), findsOneWidget);
    for (final name in ['picker', 'ruler', 'image', 'recording']) {
      expect(find.byKey(ValueKey('nav-$name')), findsNothing);
    }
  });
}
