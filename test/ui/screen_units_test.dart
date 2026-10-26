import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fruler/app/app_controller.dart';
import 'package:fruler/core/core.dart';
import 'package:fruler/platform/desktop_service.dart';

import '../fake_desktop.dart';
import 'controller_test_host.dart';

void main() {
  for (final platform in [TargetPlatform.macOS, TargetPlatform.windows]) {
    for (final size in [const Size(1100, 760), const Size(920, 680)]) {
      testWidgets('坐标和选区使用平台单位 $platform $size', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final desktop = FakeDesktop()
          ..capture = CaptureSession(7, [
            CapturedDisplay(
              id: 1,
              name: 'scaled screen',
              frame: PixelFrame(
                width: 1280,
                height: 720,
                logicalWidth: 640,
                logicalHeight: 480,
                rgba: Uint8List(1280 * 720 * 4),
              ),
            ),
          ]);
        final c = AppController(desktop);
        await c.initialize();
        addTearDown(desktop.input.close);
        await tester.pumpWidget(ControllerTestHost(controller: c));
        await c.startScreenshot();
        desktop.pointer(x: 100, y: 180, phase: 'down');
        desktop.pointer(x: 300, y: 300, phase: 'up');
        for (var i = 0; i < 150; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
          if (find
              .byKey(const ValueKey('screenshot-size-label'))
              .evaluate()
              .isNotEmpty) {
            break;
          }
        }
        await tester.pumpAndSettle();
        final mac = platform == TargetPlatform.macOS;
        final label = find.descendant(
          of: find.byKey(const ValueKey('screenshot-size-label')),
          matching: find.byType(Text),
        );
        expect(
          tester.widget<Text>(label).data,
          mac ? '200 × 120 pt' : '400 × 180 px',
        );
        final mouse = await tester.createGesture(
          kind: ui.PointerDeviceKind.mouse,
        );
        await mouse.addPointer(location: const Offset(150, 240));
        await mouse.moveTo(const Offset(160, 240));
        await tester.pump();
        expect(
          find.text(mac ? 'X: 160  Y: 240 pt' : 'X: 320  Y: 360 px'),
          findsOneWidget,
        );
        expect(
          find.text(mac ? '区域: 200 × 120 pt' : '区域: 400 × 180 px'),
          findsOneWidget,
        );
        await mouse.removePointer();
        await c.cancelScreenshot();
        await c.startRuler();
        desktop.pointer(x: 100, y: 180, phase: 'down');
        desktop.pointer(x: 300, y: 300, phase: 'up');
        await tester.pumpAndSettle();
        final pin = (desktop.lastOverlay!['pinned'] as List).single as Map;
        expect(pin['label'], mac ? '200 × 120 pt' : '400 × 180 px');
        expect(desktop.clipboard, '400 × 180 px · 200 × 120 pt');
        desktop.event('confirm');
        await tester.pumpAndSettle();
        c.selectSection(AppSection.ruler);
        await tester.pumpAndSettle();
        expect(
          find.text(mac ? '200 × 120 pt' : '400 × 180 px'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      }, variant: TargetPlatformVariant({platform}));
    }
  }
}
