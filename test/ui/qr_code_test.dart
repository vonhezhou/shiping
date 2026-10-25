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

class QrUiDesktop extends FakeDesktop {
  List<String> results = [];
  Completer<List<String>>? pendingRecognition;
  @override
  Future<List<String>> recognizeQrCodes(
    int sessionId,
    int displayId,
    PixelRect rect,
  ) async => pendingRecognition?.future ?? results;
}

Future<AppController> editor(
  WidgetTester tester,
  QrUiDesktop desktop, {
  Size screenSize = const Size(640, 480),
}) async {
  desktop.capture = CaptureSession(7, [
    CapturedDisplay(
      id: 1,
      name: 'screen',
      frame: PixelFrame(
        width: screenSize.width.toInt(),
        height: screenSize.height.toInt(),
        logicalWidth: screenSize.width,
        logicalHeight: screenSize.height,
        rgba: Uint8List.fromList(
          List.generate(
            screenSize.width.toInt() * screenSize.height.toInt() * 4,
            (i) => i % 4 == 3 ? 255 : 200,
          ),
        ),
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
  return controller;
}

void main() {
  testWidgets('最小窗口近全屏选区的未识别提示保留在视口内', (tester) async {
    const size = Size(920, 680);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final desktop = QrUiDesktop();
    final controller = await editor(tester, desktop, screenSize: size);
    await controller.adjustScreenshotSelection(
      const PixelRect(left: 5, top: 5, right: 915, bottom: 675),
    );
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
      if (find
          .byKey(const ValueKey('recognize-qr-code'))
          .hitTestable()
          .evaluate()
          .isNotEmpty) {
        break;
      }
    }
    await tester.tap(
      find.byKey(const ValueKey('recognize-qr-code')),
      kind: ui.PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    final feedback = find.text(controller.error!);
    expect(feedback, findsOneWidget);
    final bounds = tester.getRect(feedback);
    expect(bounds.top, greaterThanOrEqualTo(0));
    expect(bounds.bottom, lessThanOrEqualTo(size.height));
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(1100, 760), const Size(920, 680)]) {
    testWidgets('鼠标识别选区内二维码，空结果可重选，多结果须选择 $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final desktop = QrUiDesktop();
      final controller = await editor(tester, desktop);
      final recognize = find.byKey(const ValueKey('recognize-qr-code'));
      expect(recognize, findsOneWidget);
      expect(tester.getRect(recognize).right, lessThan(size.width));
      await tester.tap(recognize, kind: ui.PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(find.textContaining('未识别到二维码'), findsOneWidget);
      expect(controller.canAdjustScreenshotSelection, true);
      expect(desktop.clipboard, isNull);
      desktop.results = [
        'https://selected.example/first',
        'https://selected.example/second',
      ];
      await tester.tap(recognize, kind: ui.PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('qr-code-results')), findsOneWidget);
      expect(desktop.clipboard, isNull);
      await tester.tap(
        find.byKey(const ValueKey('qr-result-1')),
        kind: ui.PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(desktop.clipboard, desktop.results[1]);
      expect(desktop.finishCalls, 1);
      expect(desktop.showMainCalls, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('识别等待时可用鼠标取消，迟到结果不复制 $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final desktop = QrUiDesktop()
        ..pendingRecognition = Completer<List<String>>();
      final controller = await editor(tester, desktop);
      await tester.tap(
        find.byKey(const ValueKey('recognize-qr-code')),
        kind: ui.PointerDeviceKind.mouse,
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('qr-code-progress')), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('cancel-qr-code')),
        kind: ui.PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      desktop.pendingRecognition!.complete(['late']);
      await tester.pumpAndSettle();
      expect(controller.screenshotEditing, false);
      expect(desktop.clipboard, isNull);
      expect(desktop.finishCalls, 1);
    });
  }
}
