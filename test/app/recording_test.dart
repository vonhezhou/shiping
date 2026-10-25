import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fruler/app/app_controller.dart';
import 'package:fruler/core/core.dart';

import '../fake_desktop.dart';

class RecordingDesktop extends FakeDesktop {
  int starts = 0, stops = 0;
  PixelRect? region;
  RecordingOptions? options;
  Object? recordingError;
  Completer<void>? pendingStart;
  Completer<bool>? pendingStop;
  int cancels = 0;
  @override
  Future<void> cancelRecording() async {
    cancels++;
  }

  @override
  Future<void> startRecording(
    int sessionId,
    int displayId,
    PixelRect rect,
    RecordingOptions configuration,
  ) async {
    starts++;
    region = rect;
    options = configuration;
    if (pendingStart != null) await pendingStart!.future;
    if (recordingError != null) throw recordingError!;
  }

  @override
  Future<bool> stopRecording() async {
    stops++;
    return pendingStop == null ? fileResult : pendingStop!.future;
  }
}

void main() {
  late RecordingDesktop desktop;
  late AppController c;
  setUp(() async {
    desktop = RecordingDesktop();
    c = AppController(desktop);
    await c.initialize();
  });
  tearDown(() async {
    c.dispose();
    await desktop.input.close();
  });
  Future<void> selectRegion() async {
    await c.startRecording();
    desktop.pointer(x: 0, y: 0, phase: 'down');
    desktop.pointer(x: 3, y: 2, phase: 'drag');
    desktop.pointer(x: 3, y: 2, phase: 'up');
    await Future<void>.delayed(Duration.zero);
  }

  test('选区按截图像素提交参数，录制与其他工具互斥，停止不打开主窗口', () async {
    const options = RecordingOptions(
      codec: 'hevc',
      frameRate: 60,
      systemAudio: true,
    );
    c.setRecordingOptions(options);
    await selectRegion();
    expect(desktop.starts, 1);
    expect(
      desktop.region!.toJson(),
      const PixelRect(left: 0, top: 0, right: 6, bottom: 4).toJson(),
    );
    expect(desktop.options!.toJson(), options.toJson());
    expect(c.screenRecording, true);
    final count = desktop.beginCalls;
    await c.startScreenshot();
    await c.startRecording();
    expect(desktop.beginCalls, count);
    desktop.event('stopRecording');
    await Future<void>.delayed(Duration.zero);
    expect(c.screenRecording, false);
    expect(desktop.stops, 1);
    expect(desktop.showMainCalls, 0);
  });
  test('取消选区不启动录制，开始失败释放选区并可重试', () async {
    await c.startRecording();
    desktop.event('cancelled');
    expect(desktop.starts, 0);
    expect(c.busy, false);
    desktop.recordingError = StateError('encoder');
    await selectRegion();
    expect(c.screenRecording, false);
    expect(c.recordingTransition, false);
    expect(c.busy, false);
    expect(desktop.finishCalls, 1);
    desktop.recordingError = null;
    await selectRegion();
    expect(c.screenRecording, true);
  });
  test('参数持久化且录制期间不能改变，原生失败恢复状态', () async {
    c.setRecordingOptions(
      const RecordingOptions(frameRate: 24, resolution: '720p'),
    );
    expect(jsonDecode(desktop.saved!)['recordingOptions']['frameRate'], 24);
    final restoredDesktop = RecordingDesktop()..saved = desktop.saved;
    final restored = AppController(restoredDesktop);
    await restored.initialize();
    expect(restored.recordingOptions.frameRate, 24);
    restored.dispose();
    await restoredDesktop.input.close();
    await selectRegion();
    c.setRecordingOptions(const RecordingOptions(frameRate: 60));
    expect(c.recordingOptions.frameRate, 24);
    desktop.event('recordingFailed', {'message': 'stream interrupted'});
    expect(c.screenRecording, false);
    expect(c.error, contains('stream interrupted'));
  });
  test('开始过程中重复鼠标释放和停止不会并发录制', () async {
    desktop.pendingStart = Completer<void>();
    await selectRegion();
    expect(c.recordingTransition, true);
    desktop.pointer(phase: 'up');
    await c.stopRecording();
    expect(desktop.starts, 1);
    expect(desktop.stops, 0);
    desktop.pendingStart!.complete();
    await Future<void>.delayed(Duration.zero);
    expect(c.screenRecording, true);
  });
  test('开始中取消不会被迟到成功恢复，停止中原生失败不覆盖新会话', () async {
    desktop.pendingStart = Completer<void>();
    await selectRegion();
    desktop.event('cancelled');
    expect(desktop.cancels, 1);
    desktop.pendingStart!.complete();
    await Future<void>.delayed(Duration.zero);
    expect(c.screenRecording, false);
    expect(c.busy, false);
    desktop.pendingStart = null;
    await selectRegion();
    desktop.pendingStop = Completer<bool>();
    final stopped = c.stopRecording();
    desktop.event('recordingFailed', {'message': 'lost stream'});
    await c.startScreenshot();
    desktop.pendingStop!.complete(true);
    await stopped;
    expect(c.busy, true);
    expect(c.screenRecording, false);
    expect(c.section, AppSection.image);
    desktop.event('recordingFailed', {'message': 'stale stream failure'});
    expect(c.busy, true);
  });
}
