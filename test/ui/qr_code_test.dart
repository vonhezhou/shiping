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
    testWidgets('识别等待与失败不弹中心窗口，单码结果保留供查看和主动复制 $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final desktop = QrUiDesktop()
        ..pendingRecognition = Completer<List<String>>();
      final controller = await editor(tester, desktop);
      final recognize = find.byKey(const ValueKey('recognize-qr-code'));
      await tester.tap(recognize, kind: ui.PointerDeviceKind.mouse);
      await tester.pump();
      expect(
        find.byType(AlertDialog),
        findsNothing,
        reason: '识别中不能弹出会一闪而过的中心窗口',
      );
      expect(
        tester.getRect(find.byKey(const ValueKey('qr-code-progress'))).top,
        24,
      );
      desktop.pendingRecognition!.complete([]);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        find.byKey(const ValueKey('screenshot-error-feedback')),
        findsOneWidget,
      );
      expect(controller.screenshotEditing, true);
      desktop.pendingRecognition = Completer<List<String>>();
      await tester.tap(recognize, kind: ui.PointerDeviceKind.mouse);
      await tester.pump();
      expect(find.byType(AlertDialog), findsNothing);
      const payload = 'https://example.test/查看二维码内容?value=123';
      desktop.pendingRecognition!.complete([payload]);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));
      final panel = find.byKey(const ValueKey('qr-code-results'));
      expect(panel, findsOneWidget);
      expect(
        find.byWidgetPredicate((w) => w is SelectableText && w.data == payload),
        findsOneWidget,
      );
      expect(desktop.clipboard, isNull);
      expect(desktop.finishCalls, 0);
      expect(controller.screenshotEditing, true);
      final originalPanel = tester.element(panel);
      desktop.pendingClipboard = Completer<void>();
      await tester.tap(
        find.byKey(const ValueKey('qr-result-0')),
        kind: ui.PointerDeviceKind.mouse,
      );
      await tester.pump();
      expect(
        identical(tester.element(panel), originalPanel),
        true,
        reason: '复制中保留内容面板，不能切换成等待弹窗',
      );
      expect(find.byKey(const ValueKey('qr-code-progress')), findsNothing);
      expect(
        find.byWidgetPredicate((w) => w is SelectableText && w.data == payload),
        findsOneWidget,
      );
      desktop.pendingClipboard!.complete();
      await tester.pumpAndSettle();
      expect(desktop.clipboard, payload);
      expect(desktop.finishCalls, 1);
      expect(desktop.showMainCalls, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('未识别提示固定顶部居中且不阻挡选区拖动 $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final desktop = QrUiDesktop();
      final controller = await editor(tester, desktop, screenSize: size);
      for (final selection in [
        PixelRect(
          left: size.width ~/ 2 - 140,
          top: 5,
          right: size.width ~/ 2 + 140,
          bottom: 250,
        ),
        PixelRect(
          left: 5,
          top: 5,
          right: size.width.toInt() - 5,
          bottom: size.height.toInt() - 5,
        ),
      ]) {
        await controller.adjustScreenshotSelection(selection);
        await tester.pumpAndSettle();
        final toolbar = find.byKey(const ValueKey('annotation-toolbar'));
        final originalToolbar = tester.getRect(toolbar);
        await tester.tap(
          find.byKey(const ValueKey('recognize-qr-code')),
          kind: ui.PointerDeviceKind.mouse,
        );
        await tester.pumpAndSettle();
        final feedback = find.byKey(
          const ValueKey('screenshot-error-feedback'),
        );
        expect(feedback, findsOneWidget);
        final bounds = tester.getRect(feedback);
        expect(bounds.top, 24);
        expect(bounds.center.dx, closeTo(size.width / 2, 1));
        expect(bounds.width, lessThanOrEqualTo(560));
        expect(bounds.bottom, lessThan(size.height));
        expect(
          find.descendant(of: toolbar, matching: find.text(controller.error!)),
          findsNothing,
        );
        expect(tester.getRect(toolbar), originalToolbar, reason: '错误提示不能推移工具栏');
        expect(find.text(controller.error!), findsOneWidget);
        final before = controller.screenshotSelection!;
        final pointer = await tester.startGesture(
          bounds.center,
          kind: ui.PointerDeviceKind.mouse,
        );
        await pointer.moveBy(const Offset(0, 20));
        await pointer.up();
        await tester.pumpAndSettle();
        expect(
          controller.screenshotSelection!.top,
          greaterThan(before.top),
          reason: '提示条应允许鼠标穿透并移动选区',
        );
        expect(feedback, findsNothing, reason: '调整选区后清除旧提示');
        expect(tester.takeException(), isNull);
      }
    });

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
      desktop.clipboardError = StateError('clipboard unavailable');
      await tester.tap(
        find.byKey(const ValueKey('qr-result-1')),
        kind: ui.PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('qr-code-results')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('screenshot-error-feedback')),
        findsNothing,
      );
      expect(
        find.text(controller.error!),
        findsOneWidget,
        reason: '结果面板内失败提示只显示一次',
      );
      desktop.clipboardError = null;
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
      expect(find.byType(AlertDialog), findsNothing);
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
