import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fruler/app/app_controller.dart';
import 'package:fruler/core/core.dart';
import 'package:fruler/platform/desktop_service.dart';

import '../fake_desktop.dart';
import 'controller_test_host.dart';

Future<void> capture(
  WidgetTester tester,
  AppController c,
  FakeDesktop d,
) async {
  await c.startScreenshot();
  d.pointer(x: 100, y: 100, phase: 'down');
  d.pointer(x: 500, y: 350, phase: 'up');
  for (var i = 0; i < 100; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    final copy = find.byKey(const ValueKey('copy-screenshot'));
    if (copy.evaluate().isNotEmpty &&
        tester.widget<IconButton>(copy).onPressed != null) {
      break;
    }
  }
  await tester.pumpAndSettle();
}

Future<int> chooseColor(WidgetTester tester, FakeDesktop d, int? color) async {
  d.colorChoice = Completer<int?>();
  await tester.tap(
    find.byKey(const ValueKey('annotation-color')),
    kind: ui.PointerDeviceKind.mouse,
  );
  await tester.pumpAndSettle();
  final initial = d.colorRequests.last;
  d.colorChoice!.complete(color);
  await tester.pumpAndSettle();
  return initial;
}

void main() {
  for (final size in [const Size(1100, 760), const Size(920, 680)]) {
    testWidgets('工具颜色在截图关闭和应用重建后分别恢复 $size', (tester) async {
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
              rgba: Uint8List(640 * 480 * 4),
            ),
          ),
        ]);
      addTearDown(d.input.close);
      final c = AppController(d);
      await c.initialize();
      await tester.pumpWidget(ControllerTestHost(controller: c));
      await capture(tester, c, d);
      await tester.tap(
        find.byKey(const ValueKey('annotation-tool-pencil')),
        kind: ui.PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      await chooseColor(tester, d, 0xFF123456);
      await tester.tap(
        find.byKey(const ValueKey('annotation-tool-marker')),
        kind: ui.PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      await chooseColor(tester, d, 0x8012AB34);
      expect(c.markup.items, isEmpty, reason: '修改工具默认颜色不新增标注历史');
      await c.cancelScreenshot();
      await tester.pumpAndSettle();
      await capture(tester, c, d);
      await tester.tap(
        find.byKey(const ValueKey('annotation-tool-pencil')),
        kind: ui.PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(await chooseColor(tester, d, null), 0xFF123456);
      final origin = tester.getTopLeft(
        find.byKey(const ValueKey('annotation-canvas')),
      );
      await tester.dragFrom(
        origin + const Offset(30, 30),
        const Offset(50, 20),
        kind: ui.PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(c.markup.items.single.color, 0xFF123456);
      await c.cancelScreenshot();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      final restarted = AppController(d);
      await restarted.initialize();
      await tester.pumpWidget(ControllerTestHost(controller: restarted));
      await capture(tester, restarted, d);
      await tester.tap(
        find.byKey(const ValueKey('annotation-tool-marker')),
        kind: ui.PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(await chooseColor(tester, d, null), 0x8012AB34);
      await tester.tap(
        find.byKey(const ValueKey('annotation-tool-pencil')),
        kind: ui.PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(await chooseColor(tester, d, null), 0xFF123456);
      expect(tester.takeException(), isNull);
    });
  }
}
