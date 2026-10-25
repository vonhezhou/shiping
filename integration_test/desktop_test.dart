import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:logging/logging.dart';
import 'package:fruler/app/app_controller.dart';
import 'package:fruler/app/logging/app_logging.dart';
import 'package:fruler/core/core.dart';
import 'package:fruler/l10n/app_language.dart';
import 'package:fruler/platform/desktop_service.dart';
import 'package:fruler/platform/annotation_renderer.dart';
import 'package:fruler/platform/desktop.g.dart' as wire;
import 'package:fruler/platform/native_pixel_buffer.dart';
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

/// 只转发真实滚轮，避免临时开关真实设备输入丢失 Added/Removed 生命周期。
class NativeScrollDispatcher implements HitTestDispatcher {
  NativeScrollDispatcher(this.binding);
  final IntegrationTestWidgetsFlutterBinding binding;
  @override
  void dispatchEvent(PointerEvent event, HitTestResult result) {
    if (event is! PointerScrollEvent) return;
    // integration_test 驱动预先创建了绑定，无法替换为子类；这里只桥接滚轮信号。
    // ignore: invalid_use_of_protected_member
    binding.withPointerEventSource(
      TestBindingEventSource.test,
      () => binding.dispatchEvent(event, result),
    );
  }
}

Future<void> nativeWheel(
  WidgetTester tester,
  Offset position,
  int delta,
  int expectedWidth,
) async {
  // WidgetTester 在每个用例开始时重置 dispatcher，需在真实滚轮验收前接入。
  final binding = tester.binding as IntegrationTestWidgetsFlutterBinding;
  binding.deviceEventDispatcher = NativeScrollDispatcher(binding);
  // 桌面测试视口可能居中缩放，Cocoa 接收的是 FlutterView 的实际逻辑坐标。
  final view = tester.binding.renderViews.firstWhere(
    (view) => view.flutterView.viewId == tester.view.viewId,
  );
  final nativePosition = tester.binding.localToGlobal(position, view);
  await driver.invokeMethod<void>('scroll', {
    'x': nativePosition.dx,
    'y': nativePosition.dy,
    'delta': delta,
  });
  // 数值不变时也需等真实事件到达，不能把原有提示当作处理完成。
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 150)),
  );
  await tester.pump();
  await waitFor(
    tester,
    () => find
        .byTooltip('线宽 $expectedWidth pt · 滚轮 / 1、2 / [、]')
        .evaluate()
        .isNotEmpty,
  );
}

/// Only global shortcut registration is suppressed to avoid taking shortcuts
/// away from the interactive app. Capture, events, storage and clipboard are real.
class NativeDesktop extends MacDesktopService {
  @override
  Locale get systemLocale => const Locale('zh');

  CaptureSession? lastCapture;
  int captureCount = 0;
  Map<String, Object?>? overlay;
  bool screenshotHosted = false;
  @override
  Future<void> updateOverlay(Map<String, Object?> data) async {
    await super.updateOverlay(data);
    // 回归断言只观察已经得到原生确认的选项，避免跨通道竞态。
    if (data['sessionId'] == lastCapture?.id) overlay = data;
  }

  @override
  Future<void> editScreenshot(int sessionId, int displayId) async {
    await super.editScreenshot(sessionId, displayId);
    if (sessionId == lastCapture?.id) screenshotHosted = true;
  }

  @override
  Future<CaptureSession> begin(String tool) async {
    screenshotHosted = false;
    overlay = null;
    lastCapture = null;
    captureCount++;
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
  await waitFor(tester, () => finder.evaluate().isNotEmpty);
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

Future<List<Map<String, Object?>>> nativePinnedImages() async {
  final items = await driver.invokeListMethod<Object?>('pinState');
  return [for (final item in items!) Map<String, Object?>.from(item as Map)];
}

Future<({int width, int height, Uint8List pixels})> pngPixels(
  Uint8List png,
) async {
  final codec = await ui.instantiateImageCodec(png);
  try {
    final image = (await codec.getNextFrame()).image;
    try {
      final raw = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      return (
        width: image.width,
        height: image.height,
        pixels: Uint8List.fromList(
          raw.buffer.asUint8List(raw.offsetInBytes, raw.lengthInBytes),
        ),
      );
    } finally {
      image.dispose();
    }
  } finally {
    codec.dispose();
  }
}

// A separate isolate makes external-data finalization deterministic at shutdown.
void pixelReaderIsolate(List<Object> args) async {
  final parent = args[0] as SendPort;
  final messages = ReceivePort();
  final frame = NativePixelBuffers.read(
    wire.DisplayFrame(
      id: 1,
      name: 'worker',
      width: 3,
      height: 2,
      logicalWidth: 3,
      logicalHeight: 2,
      bufferId: args[1] as int,
      byteLength: 32,
      rowBytes: 16,
    ),
  );
  final view = frame.view(left: 1, top: 0, width: 2, height: 2);
  parent.send(messages.sendPort);
  await messages.first;
  final color = view.pixelAt(1, 1);
  parent.send([color.r, color.g, color.b]);
  messages.close();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const samplePhase = String.fromEnvironment('FRULER_SAMPLE_PHASE');
  if (samplePhase.isNotEmpty) {
    testWidgets('native color samples $samplePhase', (tester) async {
      final desktop = NativeDesktop();
      final c = AppController(desktop);
      await c.initialize();
      await driver.invokeMethod<void>('backupClipboard');
      try {
        await tester.pumpWidget(FrulerApp(controller: c));
        await c.startScreenshot();
        final id = desktop.lastCapture!.displays.first.id;
        for (final phase in ['down', 'drag', 'up']) {
          await driver.invokeMethod<void>('pointer', {
            'displayId': id,
            'x': phase == 'down' ? 40.0 : 500.0,
            'y': phase == 'down' ? 180.0 : 450.0,
            'phase': phase,
            'warp': true,
          });
          await tester.pump();
        }
        await waitFor(
          tester,
          () =>
              desktop.screenshotHosted &&
              c.screenshotEditing &&
              !c.imageLoading,
        );
        await tester.pumpAndSettle();
        await click(
          tester,
          find.byKey(const ValueKey('annotation-tool-pencil')),
        );
        Future<void> open() =>
            click(tester, find.byKey(const ValueKey('annotation-color')));
        Future<void> close() async {
          await driver.invokeMethod<void>('colorPanelAction', {
            'action': 'cancel',
          });
          await tester.pumpAndSettle();
        }

        Future<int?> selected() async =>
            (await driver.invokeMapMethod<String, Object?>(
                  'colorPanelState',
                ))?['color']
                as int?;
        await open();
        final expected = samplePhase == 'store'
            ? 0xFF000000 | (DateTime.now().microsecondsSinceEpoch & 0xFFFFFF)
            : (await driver.invokeMethod<int>('colorSampleExpected'))!;
        if (samplePhase == 'restore') {
          expect(
            c.annotationColor('pencil'),
            expected,
            reason: '新应用进程必须恢复画笔确认过的当前颜色',
          );
        }
        if (samplePhase == 'store') {
          await driver.invokeMethod<void>('colorPanelSelect', {
            'color': expected,
          });
          await driver.invokeMethod<void>('colorSampleInput', {
            'action': 'drag',
          });
        }
        await driver.invokeMethod<void>('colorPanelSelect', {
          'color': 0xFF000000,
        });
        await driver.invokeMethod<void>('colorSampleInput', {
          'action': 'click',
        });
        expect(await selected(), expected, reason: '点击真实样本网格必须恢复拖入的颜色');
        await close();
        await open();
        await driver.invokeMethod<void>('colorPanelSelect', {
          'color': 0xFFFFFFFF,
        });
        await driver.invokeMethod<void>('colorSampleInput', {
          'action': 'click',
        });
        expect(await selected(), expected, reason: '重新创建调色盘仍须保留自定义色块');
        await driver.invokeMethod<void>('colorPanelAction', {
          'action': 'confirm',
        });
        await tester.pumpAndSettle();
        expect(c.annotationColor('pencil'), expected);
        expect(
          jsonDecode(
            (await desktop.loadState())!,
          )['annotationColors']['pencil'],
          expected,
        );
      } finally {
        await c.cancelScreenshot();
        c.dispose();
        await driver.invokeMethod<void>('restoreClipboard');
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });
    return;
  }
  testWidgets('真实屏幕二维码严格限定选区，单码复制、多码选择并回原应用', (tester) async {
    final desktop = NativeDesktop();
    final c = AppController(desktop);
    await c.initialize();
    await driver.invokeMethod<void>('backupClipboard');
    try {
      expect(c.permissionGranted, true, reason: '真实二维码截图集成测试需要录屏权限');
      await tester.pumpWidget(FrulerApp(controller: c));
      await driver.invokeMethod<void>('qrFixture', {'action': 'show'});
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );

      Future<({int id, PixelFrame frame, Rect content})> begin({
        bool fromMenu = false,
        String area = 'blank',
      }) async {
        if (fromMenu) {
          final before = desktop.captureCount;
          expect(
            await driver.invokeMethod<bool>('clickMenu', {'name': 'qrCode'}),
            true,
          );
          await waitFor(
            tester,
            () =>
                desktop.captureCount == before + 1 &&
                desktop.lastCapture != null &&
                desktop.overlay != null,
          );
          expect(desktop.overlay!['tool'], 'screenshot');
          expect(desktop.overlay!['capturePurpose'], contains('二维码'));
        } else {
          await c.startScreenshot();
        }
        expect(c.error, isNull);
        final status = (await driver.invokeMapMethod<String, Object?>(
          'status',
        ))!;
        Map? target;
        int? id;
        for (final view in (status['rulerViews'] as List).cast<Map>()) {
          for (final region in (view['regions'] as List).cast<Map>()) {
            if (region['title'] == 'fruler-qr-fixture') {
              target = region;
              id = (view['displayId'] as num).toInt();
              break;
            }
          }
          if (target != null) break;
        }
        expect(target, isNotNull, reason: '必须找到独立 AppKit 进程的真实双二维码窗口');
        final frame = desktop.lastCapture!.displays
            .firstWhere((d) => d.id == id)
            .frame;
        final content = Rect.fromLTWH(
          (target!['x'] as num).toDouble(),
          (target['y'] as num).toDouble() +
              (target['height'] as num).toDouble() -
              360,
          640,
          360,
        );
        final selection = area == 'blank'
            ? Rect.fromLTWH(content.left + 20, content.top + 280, 600, 60)
            : Rect.fromLTWH(
                content.left + 20,
                content.top + 40,
                area == 'left' ? 240 : 580,
                220,
              );
        if (fromMenu) {
          await desktop.writeClipboard('fruler:before-menu-selection');
        }
        for (final phase in ['down', 'drag', 'up']) {
          await driver.invokeMethod<void>('pointer', {
            'displayId': id,
            'x': phase == 'down' ? selection.left : selection.right,
            'y': phase == 'down' ? selection.top : selection.bottom,
            'phase': phase,
            'warp': true,
          });
          await tester.pump();
        }
        await waitFor(
          tester,
          () =>
              desktop.screenshotHosted &&
              (c.screenshotEditing || !c.busy) &&
              !c.imageLoading,
        );
        if (fromMenu) await waitFor(tester, () => !c.qrCodeBusy);
        await tester.pumpAndSettle();
        return (id: id!, frame: frame, content: content);
      }

      PixelRect pixels(PixelFrame frame, Rect rect) {
        final tl = frame.logicalToBoundary(rect.left, rect.top);
        final br = frame.logicalToBoundary(rect.right, rect.bottom);
        return PixelRect(left: tl.x, top: tl.y, right: br.x, bottom: br.y);
      }

      final first = await begin();
      final session = desktop.lastCapture!.id;
      final left = pixels(
        first.frame,
        Rect.fromLTWH(
          first.content.left + 20,
          first.content.top + 40,
          240,
          220,
        ),
      );
      final right = pixels(
        first.frame,
        Rect.fromLTWH(
          first.content.left + 360,
          first.content.top + 40,
          240,
          220,
        ),
      );
      final both = pixels(
        first.frame,
        Rect.fromLTWH(
          first.content.left + 20,
          first.content.top + 40,
          580,
          220,
        ),
      );
      expect(await desktop.recognizeQrCodes(session, first.id, left), [
        'fruler:selected-left',
      ]);
      expect(await desktop.recognizeQrCodes(session, first.id, right), [
        'fruler:outside-right',
      ]);
      expect(await desktop.recognizeQrCodes(session, first.id, both), [
        'fruler:selected-left',
        'fruler:outside-right',
      ]);
      await expectLater(
        desktop.recognizeQrCodes(
          session,
          first.id,
          const PixelRect(left: -1, top: 0, right: 100, bottom: 100),
        ),
        throwsA(isA<PlatformException>()),
      );
      await expectLater(
        desktop.recognizeQrCodes(session, -1, left),
        throwsA(isA<PlatformException>()),
      );
      await Clipboard.setData(
        const ClipboardData(text: 'fruler:keep-clipboard'),
      );
      await click(tester, find.byKey(const ValueKey('recognize-qr-code')));
      await waitFor(tester, () => !c.qrCodeBusy);
      expect(c.screenshotEditing, true, reason: '空白选区必须保留浮层供调整');
      expect(
        await driver.invokeMethod<String>('clipboardText'),
        'fruler:keep-clipboard',
      );
      expect(c.error, isNotNull);
      await c.adjustScreenshotSelection(left);
      await tester.pumpAndSettle();
      await click(tester, find.byKey(const ValueKey('recognize-qr-code')));
      await waitFor(tester, () => !c.busy);
      expect(
        await driver.invokeMethod<String>('clipboardText'),
        'fruler:selected-left',
      );
      final finished = (await driver.invokeMapMethod<String, Object?>(
        'status',
      ))!;
      expect(finished['panels'], 0);
      expect(finished['mainVisible'], false);
      await expectLater(
        desktop.recognizeQrCodes(session, first.id, left),
        throwsA(isA<PlatformException>()),
      );

      final second = await begin();
      await c.adjustScreenshotSelection(
        pixels(
          second.frame,
          Rect.fromLTWH(
            second.content.left + 20,
            second.content.top + 40,
            580,
            220,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await desktop.writeClipboard('fruler:before-multiple');
      await click(tester, find.byKey(const ValueKey('recognize-qr-code')));
      await waitFor(tester, () => !c.qrCodeBusy);
      expect(c.qrCodeResults, ['fruler:selected-left', 'fruler:outside-right']);
      expect(
        await driver.invokeMethod<String>('clipboardText'),
        'fruler:before-multiple',
        reason: '多个结果不能自动挑一个覆盖剪贴板',
      );
      expect(c.screenshotEditing, true);
      await click(tester, find.byKey(const ValueKey('qr-result-1')));
      await waitFor(tester, () => !c.busy);
      expect(
        await driver.invokeMethod<String>('clipboardText'),
        'fruler:outside-right',
      );
      final finalStatus = (await driver.invokeMapMethod<String, Object?>(
        'status',
      ))!;
      expect(finalStatus['panels'], 0);
      expect(finalStatus['mainVisible'], false);
      expect(desktop.captureCount, 2, reason: '二维码识别与调整选区应复用每次冻结快照');

      // 从真实状态栏入口启动，松开框选立即识别，不再点工具栏按钮。
      await begin(fromMenu: true, area: 'left');
      await waitFor(tester, () => !c.busy);
      expect(
        await driver.invokeMethod<String>('clipboardText'),
        'fruler:selected-left',
      );
      await begin(fromMenu: true, area: 'both');
      expect(c.qrCodeResults, ['fruler:selected-left', 'fruler:outside-right']);
      expect(
        await driver.invokeMethod<String>('clipboardText'),
        'fruler:before-menu-selection',
      );
      await click(tester, find.byKey(const ValueKey('qr-result-1')));
      await waitFor(tester, () => !c.busy);
      expect(
        await driver.invokeMethod<String>('clipboardText'),
        'fruler:outside-right',
      );
      await begin(fromMenu: true);
      expect(c.error, isNotNull);
      expect(c.screenshotEditing, true);
      expect(
        await driver.invokeMethod<String>('clipboardText'),
        'fruler:before-menu-selection',
      );
      await c.cancelScreenshot();
      final menuFinished = (await driver.invokeMapMethod<String, Object?>(
        'status',
      ))!;
      expect(menuFinished['panels'], 0);
      expect(menuFinished['mainVisible'], false);
      expect(desktop.captureCount, 5);
      expect(tester.takeException(), isNull);
    } finally {
      await c.cancelScreenshot();
      c.dispose();
      await driver.invokeMethod<void>('qrFixture', {'action': 'hide'});
      await driver.invokeMethod<void>('restoreClipboard');
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('native system font families render distinct exported text', (
    tester,
  ) async {
    final families = await MacDesktopService().availableFontFamilies();
    expect(families, isNotEmpty);
    expect(families.toSet().length, families.length);
    expect(families, containsAll(['Menlo', 'Helvetica']));
    final frame = PixelFrame(
      width: 300,
      height: 100,
      logicalWidth: 300,
      logicalHeight: 100,
      rgba: Uint8List.fromList([
        for (var i = 0; i < 300 * 100; i++) ...[34, 51, 68, 255],
      ]),
    );
    Future<Uint8List> render(String family, {bool outlined = false}) =>
        AnnotationRenderer.export(frame, [
          Annotation(
            kind: AnnotationKind.text,
            points: [const Offset(0, 0), const Offset(300, 100)],
            text: 'Comic Wi 123',
            outlined: outlined,
            fontFamily: family,
            fontSize: 36,
          ),
        ]);
    final mono = await render('Menlo');
    final sans = await render('Helvetica');
    expect(
      await render('Helvetica', outlined: true),
      isNot(orderedEquals(sans)),
      reason: '真实系统字形的描边必须写入 PNG',
    );
    expect(mono, isNot(orderedEquals(sans)), reason: '真实系统字体应改变导出 PNG 的字形');
  });

  testWidgets('launch stays in menu bar without opening main window', (
    tester,
  ) async {
    final status = (await driver.invokeMapMethod<String, Object?>('status'))!;
    expect(status['mainVisible'], false);
    expect(status['statusItemCount'], 1);
    expect(status['accessory'], true);
  });

  testWidgets('真实原生日志与 Dart 诊断汇入同一沙盒文件', (tester) async {
    final handle = await initializeAppLogging(
      appVersion: 'integration-test',
      isReleaseMode: true,
    );
    expect(handle, isNotNull, reason: '真实 Application Support 日志目录必须可写');
    final desktop = NativeDesktop();
    final controller = AppController(desktop);
    final marker =
        'Unified diagnostics marker ${DateTime.now().microsecondsSinceEpoch}';
    final nativeRecords = <LogRecord>[];
    final subscription = Logger.root.onRecord.listen((record) {
      if (record.loggerName == 'native.desktop') nativeRecords.add(record);
    });
    try {
      Logger('app.integration').info(marker);
      await controller.initialize();
      await waitFor(
        tester,
        () => nativeRecords.any(
          (record) => record.message.contains('Desktop initialized:'),
        ),
      );
      await handle!.flush();
      final allContent = await File('${handle.directory.path}/$appLogFileName')
          .readAsString();
      final markerOffset = allContent.indexOf(marker);
      expect(markerOffset, greaterThanOrEqualTo(0));
      final content = allContent.substring(markerOffset);
      expect(allContent, contains('app.integration'));
      expect(content, contains('native.desktop'));
      expect(content, contains('Desktop initialized:'));
      final status = (await driver.invokeMapMethod<String, Object?>('status'))!;
      expect(status['bundleId'], 'dev.fruler.integration');
      expect(handle.directory.path, contains('dev.fruler.integration'));
      var exitRequested = false;
      final exitMarker =
          'Exit flush marker ${DateTime.now().microsecondsSinceEpoch}';
      final listener = AppLifecycleListener(
        onExitRequested: () async {
          Logger('app.integration').info(exitMarker);
          await handle.flush();
          exitRequested = true;
          // 验收真实退出握手，但保留测试进程继续执行截图回归。
          return ui.AppExitResponse.cancel;
        },
      );
      try {
        await driver.invokeMethod<void>('requestExit');
        await waitFor(tester, () => exitRequested);
        final flushed = await File('${handle.directory.path}/$appLogFileName')
            .readAsString();
        expect(flushed, contains(exitMarker));
      } finally {
        listener.dispose();
      }
    } finally {
      await subscription.cancel();
      controller.dispose();
      await handle?.dispose();
    }
  });

  testWidgets(
    'real external-data finalizer releases the last FFI reader (30 rounds)',
    (tester) async {
      final baseline = await driver.invokeMethod<int>('pixelBufferCount');
      for (var iteration = 0; iteration < 30; iteration++) {
        final info = (await driver.invokeMapMethod<String, Object?>(
          'createPixelFixture',
        ))!;
        final received = ReceivePort();
        final messages = StreamIterator<Object?>(received);
        final exited = ReceivePort();
        Isolate? worker;
        try {
          worker = await Isolate.spawn(pixelReaderIsolate, <Object>[
            received.sendPort,
            info['bufferId'] as int,
          ], onExit: exited.sendPort);
          expect(
            await messages.moveNext().timeout(const Duration(seconds: 10)),
            true,
          );
          final gate = messages.current as SendPort;
          await driver.invokeMethod<void>('releasePixelFixture');
          expect(
            await driver.invokeMethod<int>('pixelBufferCount'),
            baseline! + 1,
          );
          gate.send(null);
          expect(
            await messages.moveNext().timeout(const Duration(seconds: 10)),
            true,
          );
          expect(messages.current, [80, 90, 60]);
          await exited.first.timeout(const Duration(seconds: 10));
          var count = await driver.invokeMethod<int>('pixelBufferCount');
          final deadline = DateTime.now().add(const Duration(seconds: 10));
          while (count != baseline && DateTime.now().isBefore(deadline)) {
            await tester.pump(const Duration(milliseconds: 50));
            count = await driver.invokeMethod<int>('pixelBufferCount');
          }
          expect(
            count,
            baseline,
            reason: 'External typed-data finalizer must release native ARC reference',
          );
        } finally {
          worker?.kill(priority: Isolate.immediate);
          await messages.cancel();
          received.close();
          exited.close();
          await driver.invokeMethod<void>('releasePixelFixture');
        }
      }
    },
  );

  testWidgets('real FFI pixels retain native storage after session release', (
    tester,
  ) async {
    final info = (await driver.invokeMapMethod<String, Object?>(
      'createPixelFixture',
    ))!;
    final metadata = wire.DisplayFrame(
      id: 1,
      name: 'FFI fixture',
      width: 3,
      height: 2,
      logicalWidth: 1.5,
      logicalHeight: 1,
      bufferId: info['bufferId'] as int,
      byteLength: 32,
      rowBytes: 16,
    );
    try {
      final frame = NativePixelBuffers.read(metadata);
      expect(frame.pixelAt(2, 1), const RgbColor(80, 90, 60));
      expect(() => frame.rgba[0] = 0, throwsUnsupportedError);
      final view = frame.view(left: 1, top: 0, width: 2, height: 2);
      expect(view.rgba, same(frame.rgba));
      expect(view.pixelAt(1, 1), const RgbColor(80, 90, 60));
      final wrongLength = wire.DisplayFrame(
        id: 1,
        name: 'bad length',
        width: 1,
        height: 2,
        logicalWidth: 1,
        logicalHeight: 2,
        bufferId: metadata.bufferId,
        byteLength: 16,
        rowBytes: 8,
      );
      expect(() => NativePixelBuffers.read(wrongLength), throwsFormatException);
      await driver.invokeMethod<void>('releasePixelFixture');
      expect(() => NativePixelBuffers.read(metadata), throwsFormatException);
      // Several replacements must not reuse or invalidate the Dart-owned memory.
      for (var i = 0; i < 5; i++) {
        await driver.invokeMethod<void>('createPixelFixture');
        await driver.invokeMethod<void>('releasePixelFixture');
        expect(view.pixelAt(0, 1), const RgbColor(50, 90, 60));
      }
      expect(frame.pixelAt(0, 0), const RgbColor(20, 40, 60));
    } finally {
      await driver.invokeMethod<void>('releasePixelFixture');
    }
  });

  testWidgets('未激活的取色浮层接受首次点击并立即复制', (tester) async {
    final records = <String>[];
    final logs = Logger.root.onRecord.listen(
      (record) => records.add('${record.loggerName}: ${record.message}'),
    );
    final desktop = NativeDesktop();
    final controller = AppController(desktop);
    await controller.initialize();
    await driver.invokeMethod<void>('backupClipboard');
    try {
      await desktop.showMainWindow();
      await tester.pumpWidget(FrulerApp(controller: controller));
      await tester.pumpAndSettle();
      controller.setContinuousPicker(false);
      await controller.pickColor();
      if (controller.error != null) debugPrint(records.join('\n'));
      expect(controller.error, isNull);
      final display = desktop.lastCapture!.displays.first;
      final point = display.frame.logicalToPixel(180, 240);
      final expected = controller.formatColor(
        display.frame.pixelAt(point.x, point.y),
      );
      await driver.invokeMethod<void>('raiseRegionFixture');
      var status = (await driver.invokeMapMethod<String, Object?>('status'))!;
      final deadline = DateTime.now().add(const Duration(seconds: 20));
      while (status['applicationActive'] != false &&
          DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 50));
        status = (await driver.invokeMapMethod<String, Object?>('status'))!;
      }
      expect(status['applicationActive'], false, reason: '必须实际处于未激活状态才能验证首击');
      for (final phase in ['down', 'up']) {
        await driver.invokeMethod<void>('pointer', {
          'displayId': display.id,
          'x': 180.0,
          'y': 240.0,
          'phase': phase,
        });
      }
      await waitFor(tester, () => !controller.busy);
      expect((await Clipboard.getData(Clipboard.kTextPlain))?.text, expected);
      final diagnostics = (await driver.invokeListMethod<String>(
        'inputDiagnostics',
      ))!.join('\n');
      expect(
        diagnostics,
        contains(
          'driver down session=${desktop.lastCapture!.id} before[active=false,key=false]',
        ),
      );
      expect(diagnostics, contains('firstMouse tool=picker'));
      expect(diagnostics, contains('accepted=true'));
      expect(
        (await driver.invokeMapMethod<String, Object?>(
          'status',
        ))!['mainVisible'],
        false,
      );
    } finally {
      await logs.cancel();
      controller.dispose();
      await driver.invokeMethod<void>('restoreClipboard');
    }
  });

  testWidgets('运行中切换语言同步 Flutter、原生菜单与现有浮层，并恢复偏好', (tester) async {
    final desktop = NativeDesktop();
    final original = await desktop.loadState();
    final controller = AppController(desktop);
    await controller.initialize();
    await driver.invokeMethod<void>('backupClipboard');
    try {
      await controller.setLanguage(AppLanguage.zh);
      controller.selectSection(AppSection.settings);
      await desktop.showMainWindow();
      await tester.pumpWidget(FrulerApp(controller: controller));
      await click(tester, find.byKey(const ValueKey('app-language')));
      await click(tester, find.text('English').last);
      await waitFor(tester, () => controller.locale.languageCode == 'en');
      expect(find.text('Language'), findsOneWidget);
      final saved = jsonDecode((await desktop.loadState())!) as Map;
      expect(saved['language'], 'en');
      final restored = AppController(desktop);
      try {
        await restored.initialize();
        expect(restored.language, AppLanguage.en);
        expect(restored.locale, const Locale('en'));
      } finally {
        restored.dispose();
      }
      Future<Map<String, Object?>> status() async =>
          (await driver.invokeMapMethod<String, Object?>('status'))!;
      expect(
        ((await status())['menu'] as List)
            .cast<Map>()
            .where((item) => item['tool'] != '')
            .map((item) => item['title']),
        [
          'Screenshot',
          'Recognize QR Code',
          'Screen recording…',
          'Color Picker',
          'Screen Ruler',
        ],
      );
      const sample = RgbColor(13, 127, 255);
      await controller.copyColor(sample);
      final englishCopy = (await Clipboard.getData('text/plain'))!.text;
      await controller.startRuler(RulerMode.rectangle);
      var view = ((await status())['rulerViews'] as List).cast<Map>().first;
      expect(
        ((view['modes'] as Map)['rectangle'] as Map)['tooltip'],
        contains('Rectangle'),
      );
      await controller.setLanguage(AppLanguage.zh);
      final chinese = await status();
      view = (chinese['rulerViews'] as List).cast<Map>().first;
      expect(
        ((view['modes'] as Map)['rectangle'] as Map)['tooltip'],
        contains('矩形'),
      );
      expect(
        (chinese['menu'] as List)
            .cast<Map>()
            .where((item) => item['tool'] != '')
            .map((item) => item['title']),
        ['截图', '识别二维码', '录屏…', '取色器', '尺子'],
      );
      expect(chinese['mainVisible'], false);
      await controller.cancelScreenshot();
      await controller.copyColor(sample);
      expect((await Clipboard.getData('text/plain'))!.text, englishCopy);
      controller.selectSection(AppSection.settings);
      await desktop.showMainWindow();
      await tester.pumpAndSettle();
      expect(find.text('语言'), findsOneWidget);
    } finally {
      await controller.cancelScreenshot();
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      await desktop.saveState(original ?? '{}');
      await desktop.configureLocale('zh');
      await driver.invokeMethod<void>('restoreClipboard');
    }
  });

  testWidgets('选项窗口的取色和尺子配置通过真实通道应用到屏幕工具', (tester) async {
    final desktop = NativeDesktop();
    final original = await desktop.loadState();
    final controller = AppController(desktop);
    await controller.initialize();
    try {
      await controller.setLanguage(AppLanguage.zh);
      await desktop.showMainWindow();
      await tester.pumpWidget(FrulerApp(controller: controller));
      await click(tester, find.byKey(const ValueKey('nav-picker')));
      await click(tester, find.byKey(const ValueKey('picker-format')));
      await click(tester, find.text('RGB').last);
      await click(tester, find.byKey(const ValueKey('picker-zoom')));
      await click(tester, find.text('24×').last);
      if (!controller.continuousPicker) {
        await click(tester, find.byKey(const ValueKey('picker-continuous')));
      }
      expect(controller.zoom, 24);
      expect(controller.selectedOutputId, 'rgb');
      expect(controller.continuousPicker, true);
      await click(tester, find.byKey(const ValueKey('start-picker')));
      await waitFor(tester, () => desktop.overlay?['tool'] == 'picker');
      expect(desktop.overlay!['zoom'], 24);
      expect(desktop.overlay!['continuous'], true);
      expect(desktop.overlay!['colorOutputName'], 'RGB');
      await controller.cancelScreenshot();
      expect(
        (await driver.invokeMapMethod<String, Object?>(
          'status',
        ))!['mainVisible'],
        false,
      );
      await desktop.showMainWindow();
      await click(tester, find.byKey(const ValueKey('nav-ruler')));
      await click(tester, find.byKey(const ValueKey('ruler-mode')));
      await click(tester, find.text(controller.strings.uiModeCross).last);
      await setParameterSlider(tester, 'ruler-tolerance', 128);
      await click(tester, find.byKey(const ValueKey('start-ruler')));
      await waitFor(tester, () => desktop.overlay?['tool'] == 'cross');
      expect(desktop.overlay!['tolerance'], 128);
      await controller.cancelScreenshot();
      expect(
        (await driver.invokeMapMethod<String, Object?>(
          'status',
        ))!['mainVisible'],
        false,
      );
      final restored = AppController(desktop);
      try {
        await restored.initialize();
        expect(restored.zoom, 24);
        expect(restored.selectedOutputId, 'rgb');
        expect(restored.mode, RulerMode.cross);
        expect(restored.tolerance, 128);
      } finally {
        restored.dispose();
      }
    } finally {
      await controller.cancelScreenshot();
      await desktop.showMainWindow();
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      await desktop.saveState(original ?? '{}');
    }
  });

  testWidgets('新增设置经原生存储恢复，右键连续取色使用自定义格式，中键取消', (tester) async {
    final desktop = NativeDesktop();
    final original = await desktop.loadState();
    final controller = AppController(desktop);
    await driver.invokeMethod<void>('backupClipboard');
    try {
      final record = MeasurementRecord(
        measurement: const RulerMeasurement(
          rect: PixelRect(left: 0, top: 0, right: 10, bottom: 20),
          logicalWidth: 10,
          logicalHeight: 20,
          mode: RulerMode.rectangle,
        ),
        createdAt: DateTime.utc(2026, 10, 23),
        displayName: 'History fixture',
        favorite: true,
      );
      await desktop.saveState(
        jsonEncode({
          'version': 1,
          'language': 'zh',
          'colors': [
            for (var i = 0; i < 80; i++) [i, 1, 2],
          ],
          'measurements': [for (var i = 0; i < 80; i++) record.toJson()],
        }),
      );
      await controller.initialize();
      expect(controller.colors, hasLength(64));
      expect(controller.measurements, hasLength(32));
      final compacted = jsonDecode((await desktop.loadState())!) as Map;
      expect(compacted['colors'], hasLength(64));
      expect(compacted['measurements'], hasLength(32));
      await desktop.showMainWindow();
      await tester.pumpWidget(FrulerApp(controller: controller));
      Future<void> select(String key, String label) async {
        await click(tester, find.byKey(ValueKey(key)));
        await click(tester, find.text(label).last);
      }

      await click(tester, find.byKey(const ValueKey('nav-picker')));
      await select(
        'picker-history-limit',
        controller.strings.uiHistoryItemCount(16),
      );
      await select(
        'picker-right-action',
        controller.pickerActionLabel(PickerMouseAction.pickAndContinue),
      );
      await select(
        'picker-middle-action',
        controller.pickerActionLabel(PickerMouseAction.cancel),
      );
      await click(tester, find.byKey(const ValueKey('color-format-settings')));
      await click(tester, find.byKey(const ValueKey('format-add')));
      await tester.enterText(
        find.byKey(const ValueKey('format-name')),
        'Native channels',
      );
      await tester.enterText(
        find.byKey(const ValueKey('format-template')),
        '%Re/%Gr/%Bl',
      );
      await click(tester, find.byKey(const ValueKey('format-save')));
      await select('picker-format', 'Native channels');
      await click(tester, find.byKey(const ValueKey('nav-ruler')));
      await select(
        'ruler-history-limit',
        controller.strings.uiHistoryItemCount(16),
      );
      await click(tester, find.byKey(const ValueKey('nav-picker')));
      await click(tester, find.byKey(const ValueKey('start-picker')));
      await waitFor(tester, () => desktop.overlay?['tool'] == 'picker');
      expect(desktop.overlay!['colorOutputName'], 'Native channels');
      final display = desktop.lastCapture!.displays.first;
      const x = 160.0, y = 220.0;
      final point = display.frame.logicalToPixel(x, y);
      final color = display.frame.pixelAt(point.x, point.y);
      final expected = '${color.r}/${color.g}/${color.b}';
      Future<void> nativeClick(String button) async {
        for (final phase in ['down', 'up']) {
          await driver.invokeMethod<void>('pointer', {
            'displayId': display.id,
            'x': x,
            'y': y,
            'phase': phase,
            'button': button,
          });
        }
      }

      Future<void> waitNative(bool Function() ready) async {
        // 原生工具隐藏主窗口后不依赖 Flutter 重绘推进；只等待真实通道状态。
        await tester.runAsync(() async {
          final deadline = DateTime.now().add(const Duration(seconds: 20));
          while (!ready() && DateTime.now().isBefore(deadline)) {
            await Future<void>.delayed(const Duration(milliseconds: 50));
          }
        });
        expect(ready(), true, reason: 'Native mouse action did not complete');
      }

      await nativeClick('secondary');
      await waitNative(
        () => desktop.overlay?['pickedCount'] == 1 || !controller.busy,
      );
      expect(desktop.overlay?['pickedCount'], 1);
      expect(controller.busy, true);
      expect(controller.error, isNull);
      expect((await Clipboard.getData('text/plain'))!.text, expected);
      expect(controller.colors, hasLength(16));
      await nativeClick('middle');
      await waitNative(() => !controller.busy);
      expect((await Clipboard.getData('text/plain'))!.text, expected);
      expect(
        (await driver.invokeMapMethod<String, Object?>(
          'status',
        ))!['mainVisible'],
        false,
      );
      final restored = AppController(desktop);
      try {
        await restored.initialize();
        expect(restored.colorHistoryLimit, 16);
        expect(restored.measurementHistoryLimit, 16);
        expect(restored.measurements, hasLength(16));
        expect(restored.colors, hasLength(16));
        expect(
          restored.pickerBehavior.secondary,
          PickerMouseAction.pickAndContinue,
        );
        expect(restored.pickerBehavior.middle, PickerMouseAction.cancel);
        expect(restored.activeColorOutput.template, '%Re/%Gr/%Bl');
      } finally {
        restored.dispose();
      }
    } finally {
      await controller.cancelScreenshot();
      await desktop.showMainWindow();
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      await desktop.saveState(original ?? '{}');
      await driver.invokeMethod<void>('restoreClipboard');
    }
  });

  testWidgets(
    'real window hover suggests bounds and a click selects the same frozen capture',
    (tester) async {
      final desktop = NativeDesktop();
      final c = AppController(desktop);
      await driver.invokeMethod<void>('backupClipboard');
      await c.initialize();
      try {
        await tester.pumpWidget(FrulerApp(controller: c));
        await driver.invokeMethod<void>('raiseRegionFixture');
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)),
        );
        await c.startScreenshot();
        final status = (await driver.invokeMapMethod<String, Object?>(
          'status',
        ))!;
        final views = (status['rulerViews'] as List).cast<Map>();
        Map? target, view;
        for (final v in views) {
          for (final region in v['regions'] as List) {
            if ((region as Map)['title'] == 'fruler-region-fixture') {
              target = region;
              view = v;
              break;
            }
          }
          if (target != null) break;
        }
        expect(
          target,
          isNotNull,
          reason:
              'Must detect an actual window from the separate AppKit fixture',
        );
        final id = (view!['displayId'] as num).toInt();
        final x = (target!['x'] as num).toDouble(),
            y = (target['y'] as num).toDouble();
        final w = (target['width'] as num).toDouble(),
            h = (target['height'] as num).toDouble();
        final frame = desktop.lastCapture!.displays
            .firstWhere((d) => d.id == id)
            .frame;
        final tl = frame.logicalToBoundary(x, y),
            br = frame.logicalToBoundary(x + w, y + h);
        for (final phase in ['move', 'down', 'up']) {
          await driver.invokeMethod<void>('pointer', {
            'displayId': id,
            'x': x + w / 2,
            'y': y + h / 2,
            'phase': phase,
            'warp': true,
          });
          await tester.pump();
        }
        await waitFor(
          tester,
          () =>
              desktop.screenshotHosted &&
              c.screenshotEditing &&
              !c.imageLoading,
        );
        expect(c.screenshotSelection!.toJson(), {
          'left': tl.x,
          'top': tl.y,
          'right': br.x,
          'bottom': br.y,
        });
        expect(
          (await driver.invokeMapMethod<String, Object?>(
            'status',
          ))!['mainVisible'],
          false,
        );
      } finally {
        await c.cancelScreenshot();
        c.dispose();
        await driver.invokeMethod<void>('restoreClipboard');
      }
    },
  );

  testWidgets('状态栏工具分组入口与独立模式，历史和设置直接打开', (tester) async {
    final d = NativeDesktop();
    final c = AppController(d);
    await c.initialize();
    await driver.invokeMethod<void>('backupClipboard');
    try {
      await tester.pumpWidget(FrulerApp(controller: c));
      final initial = (await driver.invokeMapMethod<String, Object?>(
        'status',
      ))!;
      final menu = (initial['menu'] as List).cast<Map>();
      expect(menu.where((i) => i['tool'] != '').map((i) => i['title']), [
        '截图',
        '识别二维码',
        '录屏…',
        '取色器',
        '尺子',
      ]);
      expect(menu.where((i) => i['separator'] == true), hasLength(3));
      expect(menu.take(5).every((i) => i['hasImage'] == true), true);
      expect(menu.skip(6).take(3).map((i) => i['title']), [
        '剪贴板贴图',
        '显示／隐藏全部贴图',
        '销毁全部贴图',
      ]);
      expect(menu.skip(6).take(3).every((i) => i['hasImage'] == true), true);
      expect(menu.singleWhere((i) => i['tool'] == 'qrCode')['key'], isEmpty);
      final nativeShortcutsAvailable = (await d.initialize()).shortcuts;
      final chords = {
        'screenshot': c.shortcuts.screenshot,
        'picker': c.shortcuts.picker,
        'rectangle': c.shortcuts.ruler,
      };
      for (final entry in chords.entries) {
        expect(
          menu.singleWhere((i) => i['tool'] == entry.key)['key'],
          nativeShortcutsAvailable ? entry.value.key.toLowerCase() : '',
          reason: '菜单遵循原生快捷键实际注册状态，冲突时不展示不可用快捷键',
        );
      }
      Future<void> clickMenu(String name) async {
        expect(
          await driver.invokeMethod<bool>('clickMenu', {'name': name}),
          true,
        );
        await tester.pumpAndSettle();
      }

      await clickMenu('settings');
      await waitFor(tester, () => c.section == AppSection.settings);
      expect(
        (await driver.invokeMapMethod<String, Object?>(
          'status',
        ))!['mainVisible'],
        true,
      );
      await clickMenu('history');
      await waitFor(tester, () => c.section != AppSection.settings);
      for (final tool in ['picker', 'rectangle', 'screenshot', 'recording']) {
        final before = d.captureCount;
        if (tool == 'picker') c.selectColorOutput('rgb');
        await clickMenu(tool);
        await waitFor(
          tester,
          () => c.busy && d.captureCount == before + 1 && d.overlay != null,
        );
        expect(
          (await driver.invokeMapMethod<String, Object?>(
            'status',
          ))!['mainVisible'],
          false,
        );
        var status = (await driver.invokeMapMethod<String, Object?>('status'))!;
        var view = (status['rulerViews'] as List).cast<Map>().first;
        if (tool != 'screenshot' && tool != 'recording') {
          expect(view['toolbarTop'], 22);
          expect(
            (view['toolbarWidth'] as num) -
                (view['toolbarContentWidth'] as num),
            closeTo(20, .1),
          );
          expect(view['editbarTop'], 60);
        }
        if (tool == 'picker') expect(view['colorOutputName'], 'RGB');
        final modes = view['modes'] as Map;
        expect(modes.keys.toSet(), {
          'rectangle',
          'horizontal',
          'vertical',
          'cross',
        });
        if (tool == 'rectangle') {
          for (final mode in ['horizontal', 'vertical', 'cross', 'rectangle']) {
            expect((modes[mode] as Map)['hasImage'], true);
            expect((modes[mode] as Map)['title'], isEmpty);
            expect((modes[mode] as Map)['tooltip'], isNotEmpty);
            expect(
              await driver.invokeMethod<bool>('clickRulerControl', {
                'name': mode,
              }),
              true,
            );
            await waitFor(tester, () => d.overlay?['tool'] == mode);
            if (mode != 'rectangle') {
              for (final value in ['37', '0', '255', '256', '-1', 'abc']) {
                expect(
                  await driver.invokeMethod<bool>('setRulerTolerance', {
                    'value': value,
                  }),
                  true,
                );
                await tester.pumpAndSettle();
                final expected = int.tryParse(value);
                expect(
                  c.tolerance,
                  expected != null && expected >= 0 && expected <= 255
                      ? expected
                      : 255,
                );
              }
            }
          }
        } else {
          expect(modes.values.every((v) => (v as Map)['hidden'] == true), true);
          expect(
            await driver.invokeMethod<bool>('clickRulerControl', {
              'name': 'rectangle',
            }),
            false,
          );
        }
        expect(
          await driver.invokeMethod<bool>('clickRulerControl', {
            'name': 'picker',
          }),
          false,
        );
        expect(
          await driver.invokeMethod<bool>('clickRulerControl', {
            'name': 'screenshot',
          }),
          false,
        );
        for (final size in [const Size(1100, 760), const Size(920, 680)]) {
          expect(
            await driver.invokeMethod<bool>('rulerLayout', {
              'width': size.width,
              'height': size.height,
            }),
            true,
          );
        }
        await c.cancelScreenshot();
        await tester.pumpAndSettle();
      }
    } finally {
      await c.cancelScreenshot();
      c.dispose();
      await driver.invokeMethod<void>('restoreClipboard');
    }
  });

  testWidgets('截图保留轻量 C/M 复制，不能切入独立取色器或尺子', (tester) async {
    final d = NativeDesktop();
    final c = AppController(d);
    await driver.invokeMethod<void>('backupClipboard');
    await c.initialize();
    try {
      await tester.pumpWidget(FrulerApp(controller: c));
      await c.startScreenshot();
      final display = d.lastCapture!.displays.first;
      final id = display.id;
      final initial = (await driver.invokeMapMethod<String, Object?>(
        'status',
      ))!;
      for (final name in ['picker', 'rectangle', 'screenshot', 'recording']) {
        expect(
          await driver.invokeMethod<bool>('clickRulerControl', {'name': name}),
          false,
        );
      }
      expect(d.overlay?['tool'], 'screenshot');
      expect(d.captureCount, 1);
      expect(
        (await driver.invokeMapMethod<String, Object?>(
          'status',
        ))!['windowNumber'],
        initial['windowNumber'],
      );
      await driver.invokeMethod<void>('pointer', {
        'displayId': id,
        'x': 60.0,
        'y': 180.0,
        'phase': 'move',
        'warp': true,
      });
      await tester.pumpAndSettle();
      final p = display.frame.logicalToPixel(60, 180);
      final expected = c.formatColor(display.frame.pixelAt(p.x, p.y));
      await driver.invokeMethod<void>('key', {'keyCode': 8});
      await waitFor(tester, () => !c.busy);
      expect(await driver.invokeMethod<String>('clipboardText'), expected);
      expect(
        (await driver.invokeMapMethod<String, Object?>(
          'status',
        ))!['mainVisible'],
        false,
      );
      await c.startScreenshot();
      final second = d.lastCapture!.displays.first;
      await tester.pumpAndSettle();
      for (final phase in ['down', 'drag']) {
        await driver.invokeMethod<void>('pointer', {
          'displayId': second.id,
          'x': phase == 'down' ? 40.0 : 240.0,
          'y': phase == 'down' ? 180.0 : 280.0,
          'phase': phase,
          'warp': true,
        });
        await tester.pumpAndSettle();
      }
      await waitFor(
        tester,
        () =>
            d.overlay?['anchored'] == true &&
            (d.overlay?['rect'] as Map?)?['right'] ==
                second.frame.logicalToBoundary(240, 280).x,
      );
      await driver.invokeMethod<void>('key', {'keyCode': 46});
      await waitFor(tester, () => !c.busy);
      expect(c.measurements.first.measurement.logicalWidth, 200);
      expect(c.measurements.first.measurement.logicalHeight, 100);
      expect(
        await driver.invokeMethod<String>('clipboardText'),
        c.measurements.first.label,
      );
      expect(
        (await driver.invokeMapMethod<String, Object?>(
          'status',
        ))!['mainVisible'],
        false,
      );
    } finally {
      await c.cancelScreenshot();
      c.dispose();
      await driver.invokeMethod<void>('restoreClipboard');
    }
  });

  testWidgets('Cocoa Delete in text input preserves annotations', (
    tester,
  ) async {
    final d = NativeDesktop();
    final c = AppController(d);
    await driver.invokeMethod<void>('backupClipboard');
    await c.initialize();
    try {
      // 虚拟鼠标交互依赖 Flutter 帧调度，先激活宿主；启动截图会立即隐藏它。
      await d.showMainWindow();
      await tester.pumpWidget(FrulerApp(controller: c));
      await c.startScreenshot();
      final id = d.lastCapture!.displays.first.id;
      for (final phase in ['down', 'drag', 'up']) {
        await driver.invokeMethod<void>('pointer', {
          'displayId': id,
          'x': phase == 'down' ? 40.0 : 500.0,
          'y': phase == 'down' ? 180.0 : 450.0,
          'phase': phase,
          'warp': true,
        });
        await tester.pump();
      }
      await waitFor(
        tester,
        () => d.screenshotHosted && c.screenshotEditing && !c.imageLoading,
      );
      await tester.pumpAndSettle();
      await click(tester, find.byKey(const ValueKey('annotation-tool-text')));
      await click(tester, find.byKey(const ValueKey('annotation-canvas')));
      await driver.invokeMethod<void>('insertText', {'text': 'probe!'});
      await waitFor(
        tester,
        () =>
            tester
                .widget<TextField>(
                  find.byKey(const ValueKey('annotation-text-input')),
                )
                .controller!
                .text ==
            'probe!',
      );
      await driver.invokeMethod<void>('key', {'keyCode': 51});
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 250)),
      );
      await tester.pump();
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('annotation-text-input')),
            )
            .controller!
            .text,
        'probe',
      );
      expect(c.markup.items, isEmpty);
    } finally {
      await c.cancelScreenshot();
      c.dispose();
      await driver.invokeMethod<void>('restoreClipboard');
    }
  });

  testWidgets('Pigeon native persistence and shortcut errors round trip', (
    tester,
  ) async {
    final desktop = MacDesktopService();
    final original = await desktop.loadState();
    try {
      await desktop.saveState('{"protocolTest":"中文 ∆"}');
      expect(await desktop.loadState(), '{"protocolTest":"中文 ∆"}');
      final colors = AppController(NativeDesktop());
      await colors.initialize();
      try {
        colors.setAnnotationColor('pencil', 0x8012AB34);
        colors.setAnnotationColor('marker', 0xFF234567);
        final stored = jsonDecode((await desktop.loadState())!) as Map;
        expect(stored['annotationColors'], {
          'pencil': 0x8012AB34,
          'marker': 0xFF234567,
        });
        final restored = AppController(NativeDesktop());
        await restored.initialize();
        try {
          expect(restored.annotationColor('pencil'), 0x8012AB34);
          expect(restored.annotationColor('marker'), 0xFF234567);
          expect(restored.annotationColor('text'), 0xFFFF0000);
        } finally {
          restored.dispose();
        }
      } finally {
        colors.dispose();
      }
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
            final retainedFrame = session.displays.first.frame;
            final retainedColor = retainedFrame.pixelAt(0, 0);
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
            expect(retainedFrame.pixelAt(0, 0), retainedColor);
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
        await click(tester, find.byKey(const ValueKey('nav-image')));
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
        await waitFor(
          tester,
          () =>
              desktop.screenshotHosted &&
              c.screenshotEditing &&
              !c.imageLoading,
        );
        await tester.pumpAndSettle();
        // The editor receives the frozen selection's raw pixels directly.
        final rawSelection = c.screenshotSelection!;
        final rawDocument = c.imageDocument!.frame;
        expect(rawDocument.rgba, same(display.frame.rgba));
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
        expect(find.byKey(const ValueKey('reselect-screenshot')), findsNothing);
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
            await click(tester, find.byKey(const ValueKey('annotation-fill')));
            expect(
              tester
                  .widget<IconButton>(
                    find.byKey(const ValueKey('annotation-fill')),
                  )
                  .isSelected,
              true,
            );
            expect(
              tester
                  .widget<IconButton>(
                    find.byKey(const ValueKey('annotation-width')),
                  )
                  .isSelected,
              false,
            );
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
            // Cocoa Delete / Forward Delete must reach the Flutter editor.
            await driver.invokeMethod<void>('key', {'keyCode': 51});
            await waitFor(tester, () => c.markup.items.isEmpty);
            await click(tester, find.byKey(const ValueKey('annotation-undo')));
            expect(c.markup.items, hasLength(1));
            expect(
              find.byKey(const ValueKey('annotation-delete')),
              findsOneWidget,
            );
            await driver.invokeMethod<void>('key', {'keyCode': 117});
            await waitFor(tester, () => c.markup.items.isEmpty);
            await click(tester, find.byKey(const ValueKey('annotation-undo')));
            await click(tester, find.byKey(const ValueKey('annotation-width')));
            expect(c.markup.items.last.filled, false);
            expect(
              tester
                  .widget<IconButton>(
                    find.byKey(const ValueKey('annotation-fill')),
                  )
                  .isSelected,
              false,
            );
            await nativeWheel(
              tester,
              tester.getCenter(find.byKey(const ValueKey('annotation-width'))),
              1,
              4,
            );
            expect(c.markup.items.last.width / c.screenshotScaleX, 4);
            await nativeWheel(tester, tester.getCenter(canvas), -1, 3);
            await click(tester, find.byKey(const ValueKey('annotation-fill')));
            expect(c.markup.items.last.filled, true);
          }
          if (kind == AnnotationKind.marker) {
            final widthControl = find.byKey(const ValueKey('annotation-width'));
            await click(tester, widthControl);
            await click(tester, widthControl);
            expect(tester.widget<IconButton>(widthControl).isSelected, true);
            expect(find.byType(PopupMenuItem<double>), findsNothing);
            await nativeWheel(tester, tester.getCenter(widthControl), 1, 13);
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
            final canvasRect = tester.getRect(canvas);
            final shade = Offset(canvasRect.left / 2, canvasRect.top / 2);
            expect(canvasRect.contains(shade), false);
            await nativeWheel(tester, shade, 1, 13);
            expect(c.markup.items.last.width / c.screenshotScaleX, 13);
            await nativeWheel(tester, shade, -1, 12);
            await nativeWheel(
              tester,
              tester.getCenter(find.byKey(const ValueKey('annotation-undo'))),
              1,
              12,
            );
            await nativeWheel(
              tester,
              tester.getTopLeft(
                    find.byKey(const ValueKey('annotation-toolbar')),
                  ) +
                  const Offset(1, 1),
              1,
              12,
            );
            await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
            await tester.pumpAndSettle();
            expect(c.markup.items.last.width / c.screenshotScaleX, 13);
            await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
            await tester.pumpAndSettle();
            expect(c.markup.items.last.width / c.screenshotScaleX, 12);
            expect(
              find.descendant(
                of: find.byKey(const ValueKey('annotation-width')),
                matching: find.text('12'),
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
              tester.getCenter(find.byKey(const ValueKey('annotation-width'))),
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
              .endsWith('第二行'),
        );
        await driver.invokeMethod<void>('insertText', {'text': '!'});
        await waitFor(
          tester,
          () => tester
              .widget<TextField>(
                find.byKey(const ValueKey('annotation-text-input')),
              )
              .controller!
              .text
              .endsWith('!'),
        );
        await driver.invokeMethod<void>('key', {'keyCode': 51});
        await waitFor(
          tester,
          () => tester
              .widget<TextField>(
                find.byKey(const ValueKey('annotation-text-input')),
              )
              .controller!
              .text
              .endsWith('第二行'),
        );
        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        await tester.pumpAndSettle();
        expect(c.markup.items.length, 11);
        expect(c.markup.items.last.text, '原位标注\n第二行');
        await click(
          tester,
          find.byKey(const ValueKey('annotation-text-outline')),
        );
        expect(c.markup.items.last.outlined, true);
        expect(c.markup.items.last.fontSize / c.screenshotScaleY, 24);
        final beforeColor = List<Annotation>.of(c.markup.items);
        Future<Map<String, Object?>> colorPanel() async =>
            (await driver.invokeMapMethod<String, Object?>('colorPanelState'))!;
        await click(tester, find.byKey(const ValueKey('annotation-color')));
        final panelState = await colorPanel();
        expect(panelState['nativeClass'], 'NSColorPanel');
        expect(panelState['visible'], true);
        expect(panelState['showsAlpha'], true);
        expect(panelState['pickerCount'], 5);
        expect(panelState['aboveScreenshot'], true);
        expect(panelState['color'], beforeColor.last.color);
        // 系统颜色轮、RGB/HSB 滑杆、色板和蜡笔均使用真实 NSColorPanel。
        for (final mode in [1, 3, 5, 7, 6]) {
          await driver.invokeMethod<void>('colorPanelSelect', {
            'mode': mode,
            'color': 0x8012AB34,
          });
          expect((await colorPanel())['mode'], mode);
          expect((await colorPanel())['color'], 0x8012AB34);
        }
        expect(c.markup.items, beforeColor);
        await driver.invokeMethod<void>('colorPanelAction', {
          'action': 'cancel',
        });
        await tester.pumpAndSettle();
        expect(c.markup.items, beforeColor);
        expect(await driver.invokeMethod<Object?>('colorPanelState'), isNull);
        // 持久化颜色可能与固定测试色一致，确保确认动作实际产生一次颜色修改。
        final confirmedColor = beforeColor.last.color == 0x8012AB34
            ? 0x80AB1234
            : 0x8012AB34;
        await click(tester, find.byKey(const ValueKey('annotation-color')));
        await driver.invokeMethod<void>('colorPanelSelect', {
          'color': confirmedColor,
        });
        await driver.invokeMethod<void>('colorPanelAction', {
          'action': 'confirm',
        });
        await waitFor(
          tester,
          () => c.markup.items.last.color == confirmedColor,
        );
        expect(
          (await driver.invokeMapMethod<String, Object?>(
            'status',
          ))?['mainVisible'],
          false,
        );
        await click(tester, find.byKey(const ValueKey('annotation-undo')));
        expect(c.markup.items, beforeColor);
        await click(tester, find.byKey(const ValueKey('annotation-redo')));
        expect(c.markup.items.last.color, confirmedColor);
        await click(tester, find.byKey(const ValueKey('annotation-undo')));
        await click(tester, find.byKey(const ValueKey('annotation-color')));
        await driver.invokeMethod<void>('colorPanelAction', {
          'action': 'close',
        });
        await tester.pumpAndSettle();
        expect(c.markup.items, beforeColor);
        expect(await driver.invokeMethod<Object?>('colorPanelState'), isNull);
        final families = await desktop.availableFontFamilies();
        final family = families.lastWhere(
          (value) => value != Annotation.defaultFontFamily,
        );
        await click(
          tester,
          find.byKey(const ValueKey('annotation-font-family')),
        );
        final search = find.byKey(const ValueKey('annotation-font-search'));
        await click(tester, search);
        await driver.invokeMethod<void>('insertText', {'text': family});
        await waitFor(
          tester,
          () => find
              .byKey(ValueKey('annotation-font-option-$family'))
              .evaluate()
              .isNotEmpty,
        );
        final familyItem = find.byKey(
          ValueKey('annotation-font-option-$family'),
        );
        await click(tester, familyItem);
        expect(
          find.byKey(const ValueKey('annotation-font-search')),
          findsNothing,
        );
        expect(c.markup.items.last.fontFamily, family);
        await click(tester, find.byKey(const ValueKey('annotation-undo')));
        expect(c.markup.items.last.fontFamily, Annotation.defaultFontFamily);
        expect(c.markup.items.last.outlined, true);
        await click(tester, find.byKey(const ValueKey('annotation-undo')));
        expect(c.markup.items.last.outlined, false);
        await click(tester, find.byKey(const ValueKey('annotation-undo')));
        expect(c.markup.items.length, 10);
        await click(tester, find.byKey(const ValueKey('annotation-redo')));
        expect(c.markup.items.length, 11);
        await click(tester, find.byKey(const ValueKey('annotation-redo')));
        expect(c.markup.items.last.outlined, true);
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
        expect(
          tester
              .widget<IconButton>(
                find.byKey(const ValueKey('annotation-width')),
              )
              .isSelected,
          true,
        );
        expect(
          tester
              .widget<IconButton>(
                find.byKey(const ValueKey('annotation-eraser-rectangle')),
              )
              .isSelected,
          false,
        );
        await nativeWheel(
          tester,
          tester.getCenter(find.byKey(const ValueKey('annotation-width'))),
          1,
          25,
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
          final inputEvents = <Map<Object?, Object?>>[];
          final inputSubscription = desktop.events.listen((event) {
            if (event['type'] == 'pointer') inputEvents.add(event);
          });
          if (tool == 'picker') {
            c.setContinuousPicker(false);
            await c.pickColor();
          } else {
            await c.startRuler();
          }
          final d = desktop.lastCapture!.displays.first;
          await driver.invokeMethod<void>('pointer', {
            'displayId': d.id,
            'warp': true,
            'phase': 'down',
            'x': 80.0,
            'y': 180.0,
          });
          await driver.invokeMethod<void>('pointer', {
            'displayId': d.id,
            'warp': true,
            'phase': 'up',
            'x': 180.0,
            'y': 240.0,
          });
          try {
            await waitFor(tester, () => !c.busy);
          } catch (_) {
            debugPrint(
              'picker completion: busy=${c.busy}, error=${c.error}, '
              'events=${inputEvents.map((e) => '${e['phase']}/${e['sessionId']}').toList()}, '
              'session=${desktop.lastCapture?.id}, behavior=${c.pickerBehavior.primary.name}, '
              'input=${await driver.invokeMethod<Object?>('inputDiagnostics')}',
            );
            rethrow;
          } finally {
            await inputSubscription.cancel();
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
    'annotated selection resizes without losing cropped marks or history, native clipboard exports crop',
    (tester) async {
      final desktop = NativeDesktop();
      final c = AppController(desktop);
      await c.initialize();
      await driver.invokeMethod<void>('backupClipboard');
      try {
        // 虚拟鼠标交互依赖 Flutter 帧调度，先激活宿主；启动截图会立即隐藏它。
        await desktop.showMainWindow();
        await tester.pumpWidget(FrulerApp(controller: c));
        expect(
          c.permissionGranted,
          true,
          reason: 'Real screen-recording permission is required',
        );
        await c.startScreenshot();
        final display = desktop.lastCapture!.displays.first;
        for (final event in [
          {'phase': 'down', 'x': 100.0, 'y': 180.0},
          {'phase': 'drag', 'x': 500.0, 'y': 430.0},
          {'phase': 'up', 'x': 500.0, 'y': 430.0},
        ]) {
          await driver.invokeMethod<void>('pointer', {
            'displayId': display.id,
            'warp': true,
            ...event,
          });
          await tester.pump();
        }
        Future<void> ready() => waitFor(tester, () {
          final copy = find.byKey(const ValueKey('copy-screenshot'));
          return !c.imageLoading &&
              copy.evaluate().isNotEmpty &&
              tester.widget<IconButton>(copy).onPressed != null;
        });
        await ready();
        final panel = await driver.invokeMapMethod<String, Object?>('status');
        final initial = c.screenshotSelection!;
        await chooseAnnotationTool(tester, AnnotationKind.rectangle);
        await click(tester, find.byKey(const ValueKey('annotation-fill')));
        await mouseDrag(tester, const Offset(140, 220), const Offset(180, 100));
        await tester.pumpAndSettle();
        expect(c.markup.items, hasLength(1), reason: '真实选区内的鼠标拖动应提交一个标注');
        final original = c.markup.items.single;
        await mouseDrag(
          tester,
          tester.getCenter(find.byKey(const ValueKey('screenshot-handle-nw'))),
          const Offset(100, 80),
        );
        await ready();
        expect(
          c.screenshotSelection!.left,
          initial.left + (100 * display.frame.scaleX).round(),
        );
        expect(c.markup.items.single.bounds.left, lessThan(0));
        expect(c.markup.items.single.bounds.width, original.bounds.width);
        c.markup.undo();
        expect(c.markup.items, isEmpty);
        c.markup.redo();
        expect(c.markup.items, hasLength(1));
        await tester.pumpAndSettle();
        await mouseDrag(
          tester,
          tester.getCenter(find.byKey(const ValueKey('screenshot-handle-nw'))),
          const Offset(-100, -80),
        );
        await ready();
        expect(c.screenshotSelection!.toJson(), initial.toJson());
        expect(c.markup.items.single, original);
        await mouseDrag(
          tester,
          tester.getCenter(find.byKey(const ValueKey('screenshot-handle-nw'))),
          const Offset(100, 80),
        );
        await ready();
        final crop = c.screenshotSelection!;
        final status = await driver.invokeMapMethod<String, Object?>('status');
        expect(status?['windowNumber'], panel?['windowNumber']);
        expect(status?['mainVisible'], false);
        expect(desktop.captureCount, 1);
        await click(tester, find.byKey(const ValueKey('copy-screenshot')));
        await waitFor(tester, () => !c.busy);
        final bytes = (await driver.invokeMethod<Uint8List>('clipboardPng'))!;
        final codec = await ui.instantiateImageCodec(bytes);
        final output = (await codec.getNextFrame()).image;
        try {
          expect((output.width, output.height), (crop.width, crop.height));
          final raw = (await output.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          final pixels = raw.buffer.asUint8List(
            raw.offsetInBytes,
            raw.lengthInBytes,
          );
          expect(pixels.sublist(0, 4), [
            (original.color >> 16) & 255,
            (original.color >> 8) & 255,
            original.color & 255,
            255,
          ], reason: '跨边界的填充标注只输出选区内部分');
          final x = output.width - 1, y = output.height - 1;
          final background = display.frame.pixelAt(
            crop.right - 1,
            crop.bottom - 1,
          );
          final index = (y * output.width + x) * 4;
          expect(pixels.sublist(index, index + 4), [
            background.r,
            background.g,
            background.b,
            255,
          ]);
        } finally {
          output.dispose();
          codec.dispose();
        }
        expect(
          (await driver.invokeMapMethod<String, Object?>(
            'status',
          ))?['mainVisible'],
          false,
        );
      } finally {
        await c.cancelScreenshot();
        await driver.invokeMethod<void>('restoreClipboard');
        c.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );
  testWidgets(
    'screenshot defaults to sampling before annotation and C copies frozen color',
    (tester) async {
      final desktop = NativeDesktop();
      final c = AppController(desktop);
      await c.initialize();
      // 虚拟鼠标交互依赖 Flutter 帧调度，先激活宿主；启动截图会立即隐藏它。
      await desktop.showMainWindow();
      await tester.pumpWidget(FrulerApp(controller: c));
      await tester.pumpAndSettle();
      await driver.invokeMethod<void>('backupClipboard');
      try {
        expect(
          c.permissionGranted,
          true,
          reason: 'Real screen-recording permission is required',
        );
        // 未开始标注的截图选区默认提供取色信息，C 直接输出真实快照颜色。
        await c.startScreenshot();
        final colorDisplay = desktop.lastCapture!.displays.first;
        for (final event in [
          {'phase': 'down', 'x': 40.0, 'y': 180.0},
          {'phase': 'drag', 'x': 240.0, 'y': 340.0},
          {'phase': 'up', 'x': 240.0, 'y': 340.0},
        ]) {
          await driver.invokeMethod<void>('pointer', {
            'displayId': colorDisplay.id,
            'warp': true,
            ...event,
          });
          await tester.pump();
        }
        await waitFor(
          tester,
          () =>
              desktop.screenshotHosted &&
              c.screenshotEditing &&
              !c.imageLoading,
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('annotation-tool-picker')),
          findsNothing,
        );
        final samplingMouse = mouse(tester);
        await samplingMouse.addPointer(location: const Offset(100, 220));
        await samplingMouse.moveTo(const Offset(20, 220));
        await tester.pump();
        expect(
          find.byKey(const ValueKey('screenshot-magnifier')),
          findsNothing,
        );
        await samplingMouse.moveTo(const Offset(40, 220));
        await tester.pump();
        expect(
          find.byKey(const ValueKey('screenshot-magnifier')),
          findsOneWidget,
        );
        expect(
          tester.getSize(find.byKey(const ValueKey('screenshot-color-swatch'))),
          const Size(12, 12),
        );
        // 从右边控制点外半边开始缩放，拖动中即使光标在选区外也持续显示。
        await samplingMouse.down(const Offset(244, 260));
        await tester.pump();
        expect(
          find.byKey(const ValueKey('screenshot-magnifier')),
          findsOneWidget,
        );
        await samplingMouse.moveTo(const Offset(254, 260));
        await tester.pump();
        expect(
          find.byKey(const ValueKey('screenshot-magnifier')),
          findsOneWidget,
        );
        await samplingMouse.cancel();
        await tester.pump();
        expect(
          find.byKey(const ValueKey('screenshot-magnifier')),
          findsNothing,
        );
        await samplingMouse.moveTo(const Offset(101, 221));
        await tester.pump();
        expect(
          find.byKey(const ValueKey('screenshot-magnifier')),
          findsOneWidget,
        );
        expect(find.textContaining('X:'), findsOneWidget);
        final expectedColor = c.screenshotColorAt(101, 221)!;
        await samplingMouse.removePointer();
        await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
        await waitFor(tester, () => !c.busy);
        expect(
          await tester.runAsync(
            () => driver.invokeMethod<String>('clipboardText'),
          ),
          c.formatColor(expectedColor),
        );
        expect(
          (await tester.runAsync(
            () => driver.invokeMapMethod<String, Object?>('status'),
          ))?['mainVisible'],
          false,
        );
      } finally {
        if (c.busy) await driver.invokeMethod<void>('key', {'keyCode': 53});
        await tester.runAsync(
          () => driver.invokeMethod<void>('restoreClipboard'),
        );
        // 断言产品不会打开主窗口后，清理时恢复测试窗口的帧调度。
        await desktop.showMainWindow();
        c.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );
  testWidgets('贴图状态栏入口无需录屏权限且不启动截图', (tester) async {
    final desktop = NativeDesktop();
    final c = AppController(desktop);
    await c.initialize();
    await tester.pumpWidget(FrulerApp(controller: c));
    await tester.pumpAndSettle();
    await driver.invokeMethod<void>('backupClipboard');
    try {
      await desktop.closePinnedImages();
      // 权限状态不应阻断这三个入口；该用例从不申请或使用录屏。
      c.permissionGranted = false;
      await driver.invokeMethod<void>('pinClipboardFixture', {'kind': 'text'});
      Future<void> clickPinMenu(String name) async {
        expect(
          await driver.invokeMethod<bool>('clickMenu', {'name': name}),
          true,
        );
        await tester.pumpAndSettle();
        expect(c.error, isNull);
      }

      await clickPinMenu('pinClipboard');
      expect(await nativePinnedImages(), hasLength(1));
      expect((await nativePinnedImages()).single['visible'], true);
      await clickPinMenu('togglePinnedImages');
      expect((await nativePinnedImages()).single['visible'], false);
      await clickPinMenu('togglePinnedImages');
      expect((await nativePinnedImages()).single['visible'], true);
      await clickPinMenu('closePinnedImages');
      expect(await nativePinnedImages(), isEmpty);
      expect(desktop.captureCount, 0);
      expect(c.busy, false);
    } finally {
      await desktop.closePinnedImages();
      await driver.invokeMethod<void>('restoreClipboard');
      c.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
  testWidgets('原生协议接受全部五组默认快捷键并恢复原配置', (tester) async {
    final desktop = MacDesktopService();
    final controller = AppController(NativeDesktop());
    await controller.initialize();
    final original = controller.shortcuts;
    try {
      // 暂停注册，只经过真实 Swift 校验，不抢占交互应用的全局快捷键。
      expect(await desktop.setShortcutRecording(true), true);
      expect(await desktop.configureShortcuts(ShortcutBindings.defaults), true);
    } finally {
      await desktop.configureShortcuts(original);
      await desktop.setShortcutRecording(false);
      controller.dispose();
    }
  });
  testWidgets(
    'real screenshot pins annotated pixels in a separate floating window',
    (tester) async {
      final desktop = NativeDesktop();
      final c = AppController(desktop);
      await c.initialize();
      await tester.pumpWidget(FrulerApp(controller: c));
      await tester.pumpAndSettle();
      await driver.invokeMethod<void>('backupClipboard');
      try {
        await desktop.closePinnedImages();
        await Clipboard.setData(
          const ClipboardData(
            text: 'fruler screenshot pin preserves clipboard',
          ),
        );
        expect(
          c.permissionGranted,
          true,
          reason: 'Real screen-recording permission is required',
        );
        await c.startScreenshot();
        final display = desktop.lastCapture!.displays.first;
        for (final event in [
          {'phase': 'down', 'x': 40.0, 'y': 180.0},
          {'phase': 'drag', 'x': 300.0, 'y': 340.0},
          {'phase': 'up', 'x': 300.0, 'y': 340.0},
        ]) {
          await driver.invokeMethod<void>('pointer', {
            'displayId': display.id,
            ...event,
          });
          await tester.pump();
        }
        await waitFor(
          tester,
          () =>
              desktop.screenshotHosted &&
              c.screenshotEditing &&
              !c.imageLoading,
        );
        await tester.pumpAndSettle();
        final captureStatus = await driver.invokeMapMethod<String, Object?>(
          'status',
        );
        final selection = c.screenshotSelection!;
        final document = c.imageDocument!;
        await chooseAnnotationTool(tester, AnnotationKind.rectangle);
        final canvas = tester.getRect(
          find.byKey(const ValueKey('annotation-canvas')),
        );
        await mouseDrag(
          tester,
          canvas.topLeft + const Offset(35, 35),
          const Offset(90, 55),
        );
        expect(c.markup.items, hasLength(1));
        final expectedPng = await AnnotationRenderer.export(
          document.frame,
          List.of(c.markup.items),
          loadImage: c.imageCodec.sourceImage,
        );
        // 通过真实 Cocoa 快捷键提交贴图，不用假平台或直接改控制器状态。
        await driver.invokeMethod<void>('key', {
          'keyCode': 17,
          'command': true,
        });
        await waitFor(tester, () => !c.busy);
        final pins = await nativePinnedImages();
        expect(pins, hasLength(1));
        final pin = pins.single;
        expect(pin['visible'], true);
        expect(pin['level'] as num, greaterThan(0));
        expect(pin['windowNumber'], isNot(captureStatus?['windowNumber']));
        expect(pin['pixelWidth'], selection.width);
        expect(pin['pixelHeight'], selection.height);
        expect(
          pin['width'] as num,
          closeTo(selection.width / display.frame.scaleX, .01),
        );
        expect(
          pin['height'] as num,
          closeTo(selection.height / display.frame.scaleY, .01),
        );
        final done = await driver.invokeMapMethod<String, Object?>('status');
        expect(done?['panels'], 0);
        expect(done?['editing'], false);
        expect(done?['mainVisible'], false);
        expect(c.imageDocument, isNull);
        expect(c.screenshots, hasLength(1));
        expect(c.screenshots.single, orderedEquals(expectedPng));
        expect(
          await driver.invokeMethod<String>('clipboardText'),
          'fruler screenshot pin preserves clipboard',
        );
        await driver.invokeMethod<void>('pinInput', {
          'id': pin['id'],
          'action': 'key',
          'keyCode': 8,
          'command': true,
        });
        final copiedPng = await driver.invokeMethod<Uint8List>('clipboardPng');
        expect(copiedPng, isNotNull);
        final copied = await pngPixels(copiedPng!);
        final expected = await pngPixels(expectedPng);
        expect(
          (copied.width, copied.height),
          (expected.width, expected.height),
        );
        expect(copied.pixels, orderedEquals(expected.pixels));
        // 历史重新贴图不消耗已有窗口，也不打开主窗口或编辑工作区。
        await c.pinScreenshotFromHistory(c.screenshots.single);
        final restored = await nativePinnedImages();
        expect(restored, hasLength(2));
        expect(restored.every((item) => item['visible'] == true), true);
        expect(restored.map((item) => item['id']).toSet(), hasLength(2));
        expect(
          (await driver.invokeMapMethod<String, Object?>(
            'status',
          ))?['mainVisible'],
          false,
        );
      } finally {
        await c.cancelScreenshot();
        await desktop.closePinnedImages();
        await driver.invokeMethod<void>('restoreClipboard');
        await desktop.showMainWindow();
        c.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );
  testWidgets(
    'real clipboard pins support Cocoa input, visibility and destruction',
    (tester) async {
      final desktop = NativeDesktop();
      await desktop.initialize();
      await driver.invokeMethod<void>('backupClipboard');
      Future<void> input(Map<String, Object?> args) async {
        await driver.invokeMethod<void>('pinInput', args);
        await tester.pump();
      }

      try {
        await desktop.closePinnedImages();
        await driver.invokeMethod<void>('pinClipboardFixture', {
          'kind': 'image',
        });
        final fixturePng = await driver.invokeMethod<Uint8List>('clipboardPng');
        expect(fixturePng, isNotNull);
        final fixture = await pngPixels(fixturePng!);
        await desktop.pinClipboard();
        var pins = await nativePinnedImages();
        expect(pins, hasLength(1));
        final id = pins.single['id'];
        final original = pins.single;
        expect(original['visible'], true);
        expect(original['pixelWidth'], fixture.width);
        expect(original['pixelHeight'], fixture.height);
        final anchorX =
            (original['x'] as num) + (original['width'] as num) * .25;
        final anchorY =
            (original['y'] as num) + (original['height'] as num) * .75;
        await input({
          'id': id,
          'action': 'scroll',
          'delta': 1,
          'x': (original['width'] as num).toDouble() * .25,
          'y': (original['height'] as num).toDouble() * .75,
        });
        var pin = (await nativePinnedImages()).single;
        expect(pin['scale'] as num, greaterThan(original['scale'] as num));
        // AppKit 将真实窗口原点对齐到整逻辑点；精确数学换算另由原生单元测试覆盖。
        expect(
          (pin['x'] as num) + (pin['width'] as num) * .25,
          closeTo(anchorX, 1),
          reason: '缩放必须固定鼠标下的图像位置，不能因全局坐标误换算跳屏',
        );
        expect(
          (pin['y'] as num) + (pin['height'] as num) * .75,
          closeTo(anchorY, 1),
        );
        await input({
          'id': id,
          'action': 'scroll',
          'delta': -1,
          'command': true,
        });
        pin = (await nativePinnedImages()).single;
        expect(pin['opacity'] as num, lessThan(1));
        final beforeDrag = pin;
        final dragX = (pin['width'] as num).toDouble() / 2;
        final dragY = (pin['height'] as num).toDouble() / 2;
        for (final event in [
          {'phase': 'down', 'x': dragX, 'y': dragY},
          {'phase': 'drag', 'x': dragX + 30, 'y': dragY + 20},
          {'phase': 'up', 'x': dragX + 30, 'y': dragY + 20},
        ]) {
          await input({'id': id, 'action': 'mouse', ...event});
        }
        pin = (await nativePinnedImages()).single;
        expect((pin['x'], pin['y']), isNot((beforeDrag['x'], beforeDrag['y'])));
        await input({'id': id, 'action': 'key', 'keyCode': 18}); // 1
        pin = (await nativePinnedImages()).single;
        expect(pin['rotation'], 90);
        expect(
          (pin['pixelWidth'], pin['pixelHeight']),
          (fixture.height, fixture.width),
        );
        await input({'id': id, 'action': 'key', 'keyCode': 20}); // 3
        await input({'id': id, 'action': 'key', 'keyCode': 21}); // 4
        pin = (await nativePinnedImages()).single;
        expect(pin['flippedHorizontal'], true);
        expect(pin['flippedVertical'], true);
        await input({'id': id, 'action': 'key', 'keyCode': 19}); // 2
        expect((await nativePinnedImages()).single['rotation'], 0);
        await input({
          'id': id,
          'action': 'mouse',
          'phase': 'down',
          'button': 'middle',
          'x': (pin['width'] as num).toDouble() / 2,
          'y': (pin['height'] as num).toDouble() / 2,
        });
        pin = (await nativePinnedImages()).single;
        expect(pin['scale'], 1);
        expect(pin['opacity'], 1);
        expect(pin['rotation'], 0);
        expect(pin['flippedHorizontal'], false);
        expect(pin['flippedVertical'], false);
        await input({'id': id, 'action': 'key', 'keyCode': 8, 'command': true});
        final copied = await pngPixels(
          (await driver.invokeMethod<Uint8List>('clipboardPng'))!,
        );
        expect((copied.width, copied.height), (fixture.width, fixture.height));
        expect(copied.pixels, orderedEquals(fixture.pixels));
        expect(
          await driver.invokeMethod<bool>('pinInput', {
            'id': id,
            'action': 'menu',
            'name': 'save',
            'cancelSave': true,
          }),
          false,
        );
        final afterCancelSave = (await nativePinnedImages()).single;
        expect(afterCancelSave['visible'], true);
        expect(afterCancelSave['pixelWidth'], fixture.width);
        expect(afterCancelSave['pixelHeight'], fixture.height);
        final beforeNudge = (await nativePinnedImages()).single['x'] as num;
        await input({'id': id, 'action': 'key', 'keyCode': 124});
        expect(
          (await nativePinnedImages()).single['x'] as num,
          greaterThan(beforeNudge),
        );
        for (final kind in ['text', 'color']) {
          await driver.invokeMethod<void>('pinClipboardFixture', {
            'kind': kind,
          });
          await desktop.pinClipboard();
        }
        pins = await nativePinnedImages();
        expect(pins, hasLength(3));
        expect(pins.every((item) => item['visible'] == true), true);
        await desktop.togglePinnedImages();
        expect(
          (await nativePinnedImages()).every(
            (item) => item['visible'] == false,
          ),
          true,
        );
        await desktop.togglePinnedImages();
        expect(
          (await nativePinnedImages()).every((item) => item['visible'] == true),
          true,
        );
        await input({'id': id, 'action': 'key', 'keyCode': 53});
        pins = await nativePinnedImages();
        expect(pins, hasLength(3));
        expect(pins.singleWhere((item) => item['id'] == id)['visible'], false);
        await desktop.togglePinnedImages();
        await desktop.togglePinnedImages();
        expect(
          (await nativePinnedImages()).singleWhere(
            (item) => item['id'] == id,
          )['visible'],
          true,
        );
        await input({
          'id': id,
          'action': 'mouse',
          'phase': 'down',
          'x': (original['width'] as num).toDouble() / 2,
          'y': (original['height'] as num).toDouble() / 2,
          'clickCount': 2,
        });
        expect(
          (await nativePinnedImages()).singleWhere(
            (item) => item['id'] == id,
          )['visible'],
          false,
        );
        await desktop.togglePinnedImages();
        await desktop.togglePinnedImages();
        await input({'id': id, 'action': 'key', 'keyCode': 53, 'shift': true});
        pins = await nativePinnedImages();
        expect(pins, hasLength(2));
        expect(pins.any((item) => item['id'] == id), false);
        await driver.invokeMethod<void>('pinClipboardFixture', {
          'kind': 'invalid',
        });
        await expectLater(
          desktop.pinClipboard(),
          throwsA(isA<PlatformException>()),
        );
        expect(await nativePinnedImages(), hasLength(2));
      } finally {
        await desktop.closePinnedImages();
        await driver.invokeMethod<void>('restoreClipboard');
        await desktop.showMainWindow();
      }
    },
  );
  testWidgets('冻结截图包含可见贴图并排除隐藏贴图', (tester) async {
    final desktop = NativeDesktop();
    final status = await desktop.initialize();
    CaptureSession? active;
    await driver.invokeMethod<void>('backupClipboard');
    try {
      expect(
        status.permission,
        true,
        reason: 'Real screen-recording permission is required',
      );
      await desktop.closePinnedImages();
      await driver.invokeMethod<void>('raiseRegionFixture');
      active = await desktop.begin('screenshot');
      final display = active.displays.first;
      // 独立夹具的内容区左上方，避开标题、按钮及鼠标指针。
      final point = display.frame.logicalToPixel(200, 350);
      final background = display.frame.pixelAt(point.x, point.y);
      final color = RgbColor(
        255 - background.r,
        255 - background.g,
        255 - background.b,
      );
      final bounds = PixelRect.fromPoints(
        display.frame.logicalToBoundary(150, 300),
        display.frame.logicalToBoundary(250, 400),
      );
      final frame = PixelFrame(
        width: bounds.width,
        height: bounds.height,
        logicalWidth: bounds.width / display.frame.scaleX,
        logicalHeight: bounds.height / display.frame.scaleY,
        rgba: Uint8List.fromList([
          for (var i = 0; i < bounds.width * bounds.height; i++) ...[
            color.r,
            color.g,
            color.b,
            255,
          ],
        ]),
      );
      final png = await AnnotationRenderer.export(frame, []);
      await desktop.pinImage(
        png,
        sessionId: active.id,
        displayId: display.id,
        rect: bounds,
      );
      await desktop.finish(active.id);
      active = null;
      expect((await nativePinnedImages()).single['visible'], true);
      active = await desktop.begin('screenshot');
      final visible = active.displays
          .singleWhere((d) => d.id == display.id)
          .frame;
      expect(
        visible.pixelAt(point.x, point.y),
        color,
        reason: '屏幕上可见的贴图必须进入真实 ScreenCaptureKit 冻结快照',
      );
      await desktop.finish(active.id);
      active = null;
      await desktop.togglePinnedImages();
      expect((await nativePinnedImages()).single['visible'], false);
      active = await desktop.begin('screenshot');
      final hidden = active.displays
          .singleWhere((d) => d.id == display.id)
          .frame;
      expect(hidden.pixelAt(point.x, point.y), background);
      expect(hidden.pixelAt(point.x, point.y), isNot(color));
    } finally {
      if (active != null) await desktop.finish(active.id);
      await desktop.closePinnedImages();
      await driver.invokeMethod<void>('restoreClipboard');
      await desktop.showMainWindow();
    }
  });
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
              reason: '原生测量框拖动阶段 $e，当前状态 ${await state()}',
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
        await c.startRuler(RulerMode.rectangle);
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
