import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fruler/app/app_controller.dart';
import 'package:fruler/core/core.dart';
import 'package:fruler/platform/desktop_service.dart';

import '../fake_desktop.dart';

class QrDesktop extends FakeDesktop {
  List<String> results = [];
  Completer<List<String>>? pendingRecognition;
  Object? recognitionError;
  Completer<void>? pendingFinish;
  Object? finishError;

  @override
  Future<void> finish(int sessionId) async {
    await super.finish(sessionId);
    if (finishError != null) throw finishError!;
    await pendingFinish?.future;
  }

  final begunTools = <String>[];
  Completer<void>? pendingHosting;

  @override
  Future<CaptureSession> begin(String tool) {
    begunTools.add(tool);
    return super.begin(tool);
  }

  @override
  Future<void> editScreenshot(int sessionId, int displayId) async {
    await pendingHosting?.future;
  }

  final requests = <(int, int, PixelRect)>[];

  @override
  Future<List<String>> recognizeQrCodes(
    int sessionId,
    int displayId,
    PixelRect rect,
  ) async {
    requests.add((sessionId, displayId, rect));
    if (recognitionError != null) throw recognitionError!;
    return pendingRecognition?.future ?? results;
  }
}

Future<AppController> selection(QrDesktop desktop) async {
  final controller = AppController(desktop);
  await controller.initialize();
  await controller.startScreenshot();
  desktop.pointer(x: 1, y: 0.5, phase: 'down');
  desktop.pointer(x: 3, y: 2.5, phase: 'up');
  for (
    var i = 0;
    i < 100 && (!controller.screenshotEditing || controller.imageLoading);
    i++
  ) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(controller.screenshotEditing, true);
  return controller;
}

Future<void> waitUntil(bool Function() ready) async {
  for (var i = 0; i < 100 && !ready(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(ready(), true);
}

void selectQrRegion(QrDesktop desktop) {
  desktop.pointer(x: 1, y: 0.5, phase: 'down');
  desktop.pointer(x: 3, y: 2.5, phase: 'up');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('状态栏二维码入口使用截图框选，松手并托管浮层后自动识别复制', () async {
    final desktop = QrDesktop()
      ..results = ['menu-selection']
      ..pendingHosting = Completer<void>();
    final controller = AppController(desktop);
    await controller.initialize();
    addTearDown(controller.dispose);
    addTearDown(desktop.input.close);
    desktop.event('activateQrCode');
    await waitUntil(() => desktop.lastOverlay != null);
    expect(desktop.begunTools, ['screenshot']);
    expect(desktop.lastOverlay!['capturePurpose'], '拖动框选二维码 · 松开识别 · Esc 取消');
    selectQrRegion(desktop);
    await waitUntil(() => controller.screenshotEditing);
    expect(desktop.requests, isEmpty, reason: '原生尚未托管编辑器时不能开始识别');
    desktop.pendingHosting!.complete();
    await waitUntil(() => desktop.clipboard != null && !controller.busy);
    expect(desktop.clipboard, 'menu-selection');
    expect(desktop.requests.single.$3.toJson(), {
      'left': 2,
      'top': 1,
      'right': 6,
      'bottom': 5,
    });
    expect(desktop.finishCalls, 1);
    expect(desktop.showMainCalls, 0);
  });

  test('菜单框选包含多个二维码时保留结果供选择', () async {
    final desktop = QrDesktop()..results = ['first', 'second'];
    final controller = AppController(desktop);
    await controller.initialize();
    addTearDown(controller.dispose);
    addTearDown(desktop.input.close);
    desktop.event('activateQrCode');
    await waitUntil(() => desktop.lastOverlay != null);
    selectQrRegion(desktop);
    await waitUntil(() => controller.qrCodeResults.isNotEmpty);
    expect(controller.qrCodeResults, ['first', 'second']);
    expect(controller.screenshotEditing, true);
    expect(desktop.clipboard, isNull);
    expect(desktop.finishCalls, 0);
  });

  for (final interrupted in ['failed', 'cancelled', 'busy']) {
    test('二维码入口$interrupted后普通截图不会自动识别', () async {
      final desktop = QrDesktop()..results = ['must-not-copy'];
      final controller = AppController(desktop);
      await controller.initialize();
      addTearDown(controller.dispose);
      addTearDown(desktop.input.close);
      if (interrupted == 'failed') {
        desktop.beginError = StateError('capture unavailable');
        desktop.event('activateQrCode');
        await waitUntil(() => controller.error != null);
        desktop.beginError = null;
      } else if (interrupted == 'cancelled') {
        desktop.event('activateQrCode');
        await waitUntil(() => desktop.lastOverlay != null);
        desktop.event('cancelled');
        expect(controller.busy, false);
      }
      await controller.startScreenshot();
      if (interrupted == 'busy') desktop.event('activateQrCode');
      selectQrRegion(desktop);
      await waitUntil(
        () => controller.screenshotEditing && !controller.imageLoading,
      );
      expect(desktop.requests, isEmpty);
      expect(desktop.clipboard, isNull);
      expect(desktop.lastOverlay!['capturePurpose'], '');
      expect(controller.busy, true);
    });
  }

  test('精确传递冻结会话、显示器与Retina像素选区，唯一结果复制后退出', () async {
    final desktop = QrDesktop()..results = ['https://example.test/选中的二维码'];
    final controller = await selection(desktop);
    addTearDown(controller.dispose);
    addTearDown(desktop.input.close);
    final rect = controller.screenshotSelection!;
    expect(rect.toJson(), {'left': 2, 'top': 1, 'right': 6, 'bottom': 5});
    controller.markup.commit([
      Annotation(
        kind: AnnotationKind.rectangle,
        points: const [Offset.zero, Offset(2, 2)],
      ),
    ]);
    await controller.recognizeQrCodes();
    expect(desktop.requests, hasLength(1));
    expect(desktop.requests.single.$1, 7);
    expect(desktop.requests.single.$2, 1);
    expect(desktop.requests.single.$3.toJson(), rect.toJson());
    expect(desktop.clipboard, desktop.results.single);
    expect(desktop.finishCalls, 1);
    expect(desktop.showMainCalls, 0);
    expect(desktop.exportedImage, isNull);
    expect(controller.screenshotEditing, false);
  });

  test('无结果保留选区并提示，多个结果等待显式选择，选区变化清除结果', () async {
    final desktop = QrDesktop();
    final controller = await selection(desktop);
    addTearDown(controller.dispose);
    addTearDown(desktop.input.close);
    await controller.recognizeQrCodes();
    expect(controller.error, contains('未识别到二维码'));
    expect(controller.screenshotEditing, true);
    expect(desktop.clipboard, isNull);
    desktop.results = ['first', 'second'];
    await controller.recognizeQrCodes();
    expect(controller.qrCodeResults, ['first', 'second']);
    expect(desktop.clipboard, isNull);
    expect(desktop.finishCalls, 0);
    controller.dismissQrCodes();
    await controller.adjustScreenshotSelection(
      const PixelRect(left: 0, top: 0, right: 8, bottom: 6),
    );
    expect(controller.qrCodeResults, isEmpty);
    await controller.copyQrCode('second');
    expect(desktop.clipboard, isNull, reason: '旧选区的结果不能复制');
    await controller.recognizeQrCodes();
    await controller.copyQrCode('second');
    expect(desktop.clipboard, 'second');
    expect(desktop.finishCalls, 1);
  });

  test('识别异常和剪贴板失败保留浮层，失败结果可以重试复制', () async {
    final desktop = QrDesktop()
      ..recognitionError = PlatformException(code: 'qr_failed');
    final controller = await selection(desktop);
    addTearDown(controller.dispose);
    addTearDown(desktop.input.close);
    await controller.recognizeQrCodes();
    expect(controller.error, contains('识别失败'));
    expect(controller.screenshotEditing, true);
    desktop.recognitionError = null;
    desktop.results = ['retry'];
    desktop.clipboardError = StateError('clipboard unavailable');
    await controller.recognizeQrCodes();
    expect(controller.qrCodeResults, ['retry']);
    expect(controller.error, contains('复制失败'));
    expect(controller.qrCodeBusy, false);
    expect(desktop.finishCalls, 0);
    desktop.clipboardError = null;
    await controller.copyQrCode('retry');
    expect(desktop.clipboard, 'retry');
    expect(controller.screenshotEditing, false);
  });

  test('取消关闭浮层失败后可重试，迟到识别回复不能复制或卡住忙态', () async {
    final desktop = QrDesktop()
      ..pendingRecognition = Completer<List<String>>()
      ..finishError = StateError('finish unavailable');
    final controller = await selection(desktop);
    addTearDown(controller.dispose);
    addTearDown(desktop.input.close);
    final recognition = controller.recognizeQrCodes();
    await controller.cancelScreenshot();
    expect(controller.screenshotEditing, true);
    expect(controller.qrCodeBusy, false);
    expect(controller.canAdjustScreenshotSelection, true);
    expect(controller.error, contains('取消失败'));
    desktop.pendingRecognition!.complete(['late-after-cancel-failed']);
    await recognition;
    expect(desktop.clipboard, isNull);
    expect(controller.qrCodeResults, isEmpty);
    desktop.finishError = null;
    await controller.cancelScreenshot();
    expect(controller.screenshotEditing, false);
    expect(desktop.finishCalls, 2);
  });

  test('取消开始立即使识别失效，不等待原生finish返回', () async {
    final desktop = QrDesktop()
      ..pendingRecognition = Completer<List<String>>()
      ..pendingFinish = Completer<void>();
    final controller = await selection(desktop);
    addTearDown(controller.dispose);
    addTearDown(desktop.input.close);
    final recognition = controller.recognizeQrCodes();
    final cancellation = controller.cancelScreenshot();
    desktop.pendingRecognition!.complete(['late-during-finish']);
    await Future<void>.delayed(Duration.zero);
    final clipboard = desktop.clipboard;
    desktop.pendingFinish!.complete();
    await Future.wait([recognition, cancellation]);
    expect(clipboard, isNull);
    expect(desktop.finishCalls, 1);
    expect(controller.screenshotEditing, false);
  });

  test('识别期间防重入与选区变化，取消后迟到结果不能复制或恢复浮层', () async {
    final desktop = QrDesktop()..pendingRecognition = Completer<List<String>>();
    final controller = await selection(desktop);
    addTearDown(controller.dispose);
    addTearDown(desktop.input.close);
    final pending = controller.recognizeQrCodes();
    expect(controller.qrCodeBusy, true);
    expect(controller.canAdjustScreenshotSelection, false);
    await controller.recognizeQrCodes();
    await controller.exportScreenshot(save: false);
    await controller.adjustScreenshotSelection(
      const PixelRect(left: 0, top: 0, right: 8, bottom: 6),
    );
    expect(desktop.requests, hasLength(1));
    expect(desktop.exportedImage, isNull);
    expect(controller.screenshotSelection!.left, 2);
    await controller.cancelScreenshot();
    desktop.pendingRecognition!.complete(['late']);
    await pending;
    expect(desktop.clipboard, isNull);
    expect(desktop.finishCalls, 1);
    expect(controller.qrCodeResults, isEmpty);
    expect(controller.qrCodeBusy, false);
    expect(controller.screenshotEditing, false);
  });
}
