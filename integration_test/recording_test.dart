import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fruler/app/app_controller.dart';
import 'package:fruler/core/core.dart';
import 'package:fruler/platform/desktop_service.dart';
import 'package:integration_test/integration_test.dart';

const channel = MethodChannel('dev.fruler/integration');
late WidgetTester currentTester;
final driver = RecordingDriver();

class RecordingDriver {
  Future<T?> invokeMethod<T>(String method, [Object? arguments]) =>
      currentTester.runAsync<T?>(
        () => channel.invokeMethod<T>(method, arguments),
      );
  Future<Map<K, V>?> invokeMapMethod<K, V>(
    String method, [
    Object? arguments,
  ]) => currentTester.runAsync<Map<K, V>?>(
    () => channel.invokeMapMethod<K, V>(method, arguments),
  );
}

/// 仅免去全局快捷键抢占；采集、NSPanel 输入、编码和文件均走真实平台。
class RecordingDesktop extends MacDesktopService {
  @override
  Locale get systemLocale => const Locale('zh');
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
  // 录屏按产品流程隐藏所有 Flutter 窗口，不能等待只在可见视图产生的帧。
  await tester.runAsync(() async {
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (!ready() && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  });
  expect(ready(), true, reason: '真实录屏流程未在 20 秒内完成');
}

Future<Map<String, Object?>> nativeStatus() async =>
    (await driver.invokeMapMethod<String, Object?>('status'))!;

Future<Map<String, Object?>> recordingStatus() async =>
    (await driver.invokeMapMethod<String, Object?>('recordingState'))!;

Future<({int width, int height})> selectRegion(
  WidgetTester tester,
  RecordingDesktop desktop,
  AppController controller,
) async {
  await waitFor(
    tester,
    () => desktop.lastCapture != null || controller.error != null,
  );
  expect(controller.error, isNull);
  final display = desktop.lastCapture!.displays.first;
  final frame = display.frame;
  const left = 120.0, top = 170.0;
  final right = (frame.logicalWidth - 120).clamp(left + 80, 880.0);
  final bottom = (frame.logicalHeight - 120).clamp(top + 80, 610.0);
  final selectionStatus = await nativeStatus();
  expect(selectionStatus['panels'], greaterThan(0));
  expect(selectionStatus['editing'], false);
  for (final event in [
    {'phase': 'down', 'x': left, 'y': top},
    {'phase': 'drag', 'x': right, 'y': bottom},
    {'phase': 'up', 'x': right, 'y': bottom},
  ]) {
    await driver.invokeMethod<void>('pointer', {
      'displayId': display.id,
      ...event,
    });
  }
  await waitFor(
    tester,
    () => controller.screenRecording || controller.error != null,
  );
  expect(controller.error, isNull);
  expect(controller.screenRecording, true);
  final status = await nativeStatus();
  expect(status['mainVisible'], false, reason: '录制应回到原应用，不能自动打开主窗口');
  expect(status['panels'], 0, reason: '选择完成后必须移除冻结选区浮层');
  expect(status['editing'], false, reason: '录屏选区不能进入截图标注编辑器');
  expect((await recordingStatus())['active'], true);
  final rect = frame.logicalToBoundary(right, bottom);
  final origin = frame.logicalToBoundary(left, top);
  return (
    width: (rect.x - origin.x) ~/ 2 * 2,
    height: (rect.y - origin.y) ~/ 2 * 2,
  );
}

Future<void> realTime(WidgetTester tester, Duration duration) async {
  await tester.runAsync(() => Future<void>.delayed(duration));
}

void assertFixtureColors(Map<String, Object?> metadata) {
  final top = (metadata['topRGB'] as List).cast<num>();
  final bottom = (metadata['bottomRGB'] as List).cast<num>();
  expect(top[0], greaterThan(170), reason: '视频上半部应为真实外部窗口的红色');
  expect(top[1], lessThan(100));
  expect(top[2], lessThan(100));
  expect(bottom[0], lessThan(100));
  expect(bottom[1], greaterThan(150), reason: '视频下半部应为真实外部窗口的绿色');
  expect(bottom[2], lessThan(100));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('真实 NSPanel 选区录屏保存 MP4，编码、分辨率与内容正确', (tester) async {
    currentTester = tester;
    final desktop = RecordingDesktop();
    final controller = AppController(desktop);
    final directory = Directory.systemTemp.createTempSync(
      'fruler-recording-test-',
    );
    final originalState = await desktop.loadState();
    await controller.initialize();
    try {
      expect(
        controller.permissionGranted,
        true,
        reason: 'dev.fruler.integration 需要真实屏幕录制权限；缺少权限不能跳过录屏验收',
      );
      expect((await nativeStatus())['bundleId'], 'dev.fruler.integration');
      for (final options in [
        const RecordingOptions(),
        const RecordingOptions(
          codec: 'hevc',
          frameRate: 24,
          quality: 'low',
          resolution: '720p',
          showCursor: false,
          systemAudio: true,
        ),
      ]) {
        controller.setRecordingOptions(options);
        await driver.invokeMethod<void>('raiseRegionFixture');
        await realTime(tester, const Duration(milliseconds: 150));
        desktop.lastCapture = null;
        expect(
          await driver.invokeMethod<bool>('clickMenu', {'name': 'recording'}),
          true,
        );
        final source = await selectRegion(tester, desktop, controller);
        await realTime(tester, const Duration(milliseconds: 1200));
        final path = '${directory.path}/output.mp4';
        await driver.invokeMethod<void>('setRecordingSavePath', {
          'path': options.codec == 'h264'
              ? '${directory.path}/missing/output.mp4'
              : path,
          'retryPaths': options.codec == 'h264' ? [path] : <String>[],
        });
        expect(
          await driver.invokeMethod<bool>('clickMenu', {
            'name': 'stopRecording',
          }),
          true,
        );
        await waitFor(
          tester,
          () => !controller.screenRecording && !controller.recordingTransition,
        );
        expect(controller.error, isNull);
        expect(
          (await recordingStatus())['saveFailureCount'],
          options.codec == 'h264' ? 1 : 0,
          reason: '目标目录不存在时保留录制，重新选择位置后应保存成功',
        );
        expect(File(path).lengthSync(), greaterThan(1000));
        final metadata = (await driver.invokeMapMethod<String, Object?>(
          'recordingMetadata',
          {'path': path},
        ))!;
        var width = source.width, height = source.height;
        if (options.resolution == '720p') {
          final factor = [
            1.0,
            1280 / width,
            720 / height,
          ].reduce((a, b) => a < b ? a : b);
          width = (width * factor).floor() ~/ 2 * 2;
          height = (height * factor).floor() ~/ 2 * 2;
        }
        expect(metadata['width'], width);
        expect(metadata['height'], height);
        expect(metadata['codec'], options.codec == 'h264' ? 'avc1' : 'hvc1');
        expect(metadata['duration'] as num, greaterThan(.7));
        expect(
          metadata['frameRate'] as num,
          inInclusiveRange(1, options.frameRate + 1),
        );
        expect(metadata['audioTracks'], options.systemAudio ? 1 : 0);
        assertFixtureColors(metadata);
        expect((await nativeStatus())['mainVisible'], false);
        expect(
          (await recordingStatus())['temporaryFileCount'],
          0,
          reason: '保存成功必须释放录屏临时文件',
        );
      }
    } catch (error, stack) {
      debugPrintStack(label: '真实录屏测试失败：$error', stackTrace: stack);
      rethrow;
    } finally {
      if (controller.screenRecording) {
        await driver.invokeMethod<void>('cancelNextSave');
        await controller.stopRecording();
      }
      controller.dispose();
      await desktop.saveState(originalState ?? '{"version":1}');
      directory.deleteSync(recursive: true);
    }
  });

  testWidgets('录屏选区 Esc 取消，停止后的保存取消会清理临时视频', (tester) async {
    currentTester = tester;
    final desktop = RecordingDesktop();
    final controller = AppController(desktop);
    await controller.initialize();
    try {
      expect(
        controller.permissionGranted,
        true,
        reason: 'dev.fruler.integration 需要真实屏幕录制权限',
      );
      await controller.startRecording();
      expect((await nativeStatus())['active'], true);
      await driver.invokeMethod<void>('key', {'keyCode': 53});
      await waitFor(tester, () => !controller.busy);
      expect(controller.screenRecording, false);
      expect((await recordingStatus())['active'], false);
      expect((await nativeStatus())['panels'], 0);

      await driver.invokeMethod<void>('raiseRegionFixture');
      await realTime(tester, const Duration(milliseconds: 150));
      desktop.lastCapture = null;
      await controller.startRecording();
      await selectRegion(tester, desktop, controller);
      await realTime(tester, const Duration(milliseconds: 900));
      await driver.invokeMethod<void>('cancelNextSave');
      await controller.stopRecording();
      await waitFor(
        tester,
        () => !controller.screenRecording && !controller.recordingTransition,
      );
      expect(controller.error, isNull);
      expect((await recordingStatus())['active'], false);
      expect(
        (await recordingStatus())['temporaryFileCount'],
        0,
        reason: '取消保存不得把测试视频留在磁盘',
      );
      expect((await nativeStatus())['mainVisible'], false);
    } finally {
      if (controller.screenRecording) {
        await driver.invokeMethod<void>('cancelNextSave');
        await controller.stopRecording();
      }
      controller.dispose();
    }
  });

  testWidgets('真实停止编码期间销毁控制器，停止 Future 完成且释放临时媒体', (tester) async {
    currentTester = tester;
    final desktop = RecordingDesktop();
    final controller = AppController(desktop);
    var disposed = false;
    await controller.initialize();
    try {
      expect(
        controller.permissionGranted,
        true,
        reason: 'dev.fruler.integration 需要真实屏幕录制权限',
      );
      await driver.invokeMethod<void>('raiseRegionFixture');
      await realTime(tester, const Duration(milliseconds: 150));
      await controller.startRecording();
      await selectRegion(tester, desktop, controller);
      await realTime(tester, const Duration(milliseconds: 600));
      // 编码极快时可能先完成正常停止，此保护也保证不弹出人工保存面板。
      await driver.invokeMethod<void>('cancelNextSave');
      final stopping = controller.stopRecording();
      expect(controller.recordingTransition, true);
      controller.dispose();
      disposed = true;
      await tester.runAsync(
        () => stopping.timeout(const Duration(seconds: 10)),
      );

      var state = await recordingStatus();
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while ((state['active'] == true ||
              state['transitioning'] == true ||
              state['temporaryFileCount'] != 0) &&
          DateTime.now().isBefore(deadline)) {
        await realTime(tester, const Duration(milliseconds: 50));
        state = await recordingStatus();
      }
      expect(state['active'], false);
      expect(state['transitioning'], false);
      expect(
        state['temporaryFileCount'],
        0,
        reason: '取消正在停止的真实录制时应移除 MP4 及编码侧文件',
      );
      expect((await nativeStatus())['mainVisible'], false);
    } finally {
      if (!disposed) controller.dispose();
      await desktop.cancelRecording();
    }
  });
}
