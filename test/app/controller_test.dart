import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fruler/app/app_controller.dart';
import 'package:fruler/core/core.dart';
import 'package:fruler/platform/desktop_service.dart';

import '../fake_desktop.dart';

Future<void> settle() async {
  await Future<void>.delayed(Duration.zero);
}

void main() {
  late FakeDesktop desktop;
  late AppController controller;
  setUp(() async {
    desktop = FakeDesktop();
    controller = AppController(desktop);
    await controller.initialize();
  });
  tearDown(() async {
    controller.dispose();
    await desktop.input.close();
  });

  test('取色按选定格式复制，重复 up 只提交一次', () async {
    controller.setFormat(ColorFormat.hsl);
    await controller.pickColor();
    desktop.pointer(phase: 'up');
    desktop.pointer(phase: 'up');
    await settle();
    expect(desktop.clipboard, 'hsl(0, 100%, 50%)');
    expect(controller.colors, [const RgbColor(255, 0, 0)]);
    expect(desktop.finishCalls, 1);
    expect(controller.busy, false);
    expect(jsonDecode(desktop.saved!)['colors'], [
      [255, 0, 0],
    ]);
  });
  test('反向拖拽区分 backing pixel 和逻辑点', () async {
    await controller.startRuler(RulerMode.rectangle);
    desktop.pointer(x: 4, y: 3, phase: 'down');
    desktop.pointer(x: 1, y: 1, phase: 'up');
    await settle();
    final record = controller.measurements.single;
    expect(record.measurement.rect.toJson(), {
      'left': 2,
      'top': 2,
      'right': 8,
      'bottom': 6,
    });
    expect(desktop.clipboard, '6 × 4 px · 3 × 2 pt');
  });
  test('单击空矩形不制造零尺寸记录，仍可继续框选', () async {
    await controller.startRuler();
    desktop.pointer(phase: 'down');
    desktop.pointer(phase: 'up');
    await settle();
    expect(controller.measurements, isEmpty);
    expect(controller.busy, true);
    desktop.pointer(x: 0, y: 0, phase: 'down');
    desktop.pointer(x: 4, y: 3, phase: 'up');
    await settle();
    expect(controller.measurements.single.measurement.rect.width, 8);
  });
  test('横向边界测量使用同一核心，支持整屏同色', () async {
    await controller.startRuler(RulerMode.horizontal);
    desktop.pointer(phase: 'up');
    await settle();
    expect(desktop.clipboard, '8 px · 4 pt');
    expect(
      controller.measurements.single.measurement.mode,
      RulerMode.horizontal,
    );
  });
  test('旧会话事件、取消和未知显示器不写入历史', () async {
    await controller.pickColor();
    desktop.pointer(session: 6, phase: 'up');
    desktop.pointer(display: 999, phase: 'up');
    expect(controller.colors, isEmpty);
    desktop.input.add({'type': 'cancelled', 'sessionId': 7});
    desktop.pointer(phase: 'up');
    expect(controller.busy, false);
    expect(controller.colors, isEmpty);
    expect(desktop.clipboard, isNull);
  });
  test('截图结果返回前的点击会排队处理，不丢取色', () async {
    desktop.pendingCapture = Completer<CaptureSession>();
    final pending = controller.pickColor();
    desktop.pointer(phase: 'up');
    desktop.pendingCapture!.complete(desktop.capture);
    await pending;
    await settle();
    expect(controller.colors.single, const RgbColor(255, 0, 0));
    expect(desktop.finishCalls, 1);
  });
  test('工具开启期间不会重复请求截图', () async {
    await controller.pickColor();
    await controller.pickColor();
    expect(desktop.beginCalls, 1);
  });
  test('权限拒绝会释放 busy 并给出可操作提示', () async {
    desktop.beginError = PlatformException(code: 'screen_permission');
    await controller.pickColor();
    expect(controller.busy, false);
    expect(controller.permissionGranted, false);
    expect(controller.error, contains('屏幕录制权限'));
  });
  test('复制失败仍保留结果并关闭浮层', () async {
    desktop.clipboardError = PlatformException(code: 'clipboard');
    await controller.pickColor();
    desktop.pointer(phase: 'up');
    await settle();
    expect(controller.colors, isNotEmpty);
    expect(controller.error, contains('复制失败'));
    expect(desktop.finishCalls, 1);
    expect(controller.busy, false);
  });
  test('持久化可恢复设置及两种历史，损坏记录不污染有效记录', () async {
    await controller.startRuler();
    desktop.pointer(x: 0, y: 0, phase: 'down');
    desktop.pointer(x: 4, y: 3, phase: 'up');
    await settle();
    await controller.pickColor();
    desktop.pointer(phase: 'up');
    await settle();
    controller.setTolerance(35);
    controller.setFormat(ColorFormat.rgb);
    final saved = jsonDecode(desktop.saved!) as Map<String, dynamic>;
    (saved['colors'] as List).add([999, 0, 0]);
    desktop.saved = jsonEncode(saved);
    final restored = AppController(desktop);
    await restored.initialize();
    expect(restored.tolerance, 35);
    expect(restored.format, ColorFormat.rgb);
    expect(restored.colors, [const RgbColor(255, 0, 0)]);
    expect(restored.measurements.single.measurement.rect.width, 8);
    restored.dispose();
  });
  test('浮层模式切换复用截图并清理未完成矩形', () async {
    await controller.startRuler();
    desktop.pointer(phase: 'down');
    desktop.event('modeChanged', {'tool': 'horizontal'});
    expect(controller.mode, RulerMode.horizontal);
    expect(desktop.lastOverlay!['tool'], 'horizontal');
    desktop.event('scroll', {'steps': 32});
    expect(controller.tolerance, 255);
    desktop.event('modeChanged', {'tool': 'rectangle'});
    expect(desktop.lastOverlay!['rect'], null);
    expect(desktop.beginCalls, 1);
    desktop.event('scroll', {'steps': -32});
    expect(controller.tolerance, 255);
  });
  test('Shift 连续保留多个标注，清除仅影响浮层，普通确认结束', () async {
    await controller.startRuler();
    for (var i = 0; i < 2; i++) {
      desktop.pointer(x: 0, y: 0, phase: 'down');
      desktop.pointer(x: 2, y: 2, phase: 'up', keep: true);
      await settle();
    }
    expect(controller.busy, true);
    expect(desktop.finishCalls, 0);
    expect(controller.measurements.length, 2);
    expect((desktop.lastOverlay!['pinned'] as List).length, 2);
    desktop.event('clearPins');
    expect(desktop.lastOverlay!['pinned'], isEmpty);
    expect(controller.measurements.length, 2);
    desktop.pointer(x: 0, y: 0, phase: 'down');
    desktop.pointer(x: 2, y: 2, phase: 'up');
    await settle();
    expect(desktop.finishCalls, 1);
    await controller.startRuler();
    expect(desktop.lastOverlay!['pinned'], isEmpty);
  });
  test('键盘矩形以 Enter 定两端，方向键每次一个截图像素', () async {
    await controller.startRuler();
    desktop.pointer(x: 1, y: 1);
    desktop.event('confirm');
    desktop.event('nudge', {'dx': 1, 'dy': 0});
    desktop.event('nudge', {'dx': 0, 'dy': 1});
    expect(desktop.lastOverlay!['rect'], {
      'left': 2,
      'top': 2,
      'right': 3,
      'bottom': 3,
    });
    desktop.event('confirm', {'keep': true});
    await settle();
    expect(controller.measurements.single.measurement.pixelLabel, '1 × 1 px');
    expect(controller.busy, true);
  });
  test('取色滚轮倍率持久化，微调和 Enter 只提交一次', () async {
    await controller.pickColor();
    desktop.pointer(x: 1, y: 1);
    desktop.event('scroll', {'steps': 2});
    expect(controller.zoom, 24);
    desktop.event('nudge', {'dx': 1, 'dy': -1});
    expect(desktop.lastOverlay!['x'], 1.75);
    expect(desktop.lastOverlay!['y'], .75);
    desktop.event('confirm');
    desktop.event('confirm');
    await settle();
    expect(desktop.finishCalls, 1);
    expect(jsonDecode(desktop.saved!)['zoom'], 24);
  });
  test('自定义快捷键成功后保存，冲突与重复不能覆盖旧配置', () async {
    const chord = ShortcutChord(key: '8', control: true, alt: true);
    expect(await controller.setShortcut(true, chord), true);
    expect(desktop.bindings.picker, chord);
    final saved = desktop.saved;
    expect(await controller.setShortcut(false, chord), false);
    desktop.shortcutError = PlatformException(
      code: 'shortcut_conflict',
      details: {'shortcuts': true},
    );
    expect(
      await controller.setShortcut(
        true,
        const ShortcutChord(key: '9', meta: true),
      ),
      false,
    );
    expect(controller.shortcuts.picker, chord);
    expect(controller.shortcutsAvailable, true);
    expect(desktop.saved, saved);
    desktop.shortcutError = null;
    final restored = AppController(desktop);
    await restored.initialize();
    expect(restored.shortcuts.picker, chord);
    restored.dispose();
  });
  test('录制期间暂停工具唤起，取消录制恢复快捷键', () async {
    expect(await controller.beginShortcutRecording(), true);
    expect(desktop.recording, true);
    desktop.event('activate', {'tool': 'picker'});
    await settle();
    expect(desktop.beginCalls, 0);
    await controller.endShortcutRecording();
    expect(desktop.recording, false);
    desktop.event('activate', {'tool': 'picker'});
    await settle();
    expect(desktop.beginCalls, 1);
  });
  test('重启时保存组合被占用，保留偏好并明确显示未注册', () async {
    const chord = ShortcutChord(key: '8', control: true, alt: true);
    await controller.setShortcut(true, chord);
    desktop.shortcutError = PlatformException(
      code: 'shortcut_conflict',
      details: {'shortcuts': false},
    );
    final restored = AppController(desktop);
    await restored.initialize();
    expect(restored.shortcuts.picker, chord);
    expect(restored.shortcutsAvailable, false);
    expect(restored.error, contains('占用'));
    restored.dispose();
  });
}
