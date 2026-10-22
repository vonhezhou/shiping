import 'package:flutter_test/flutter_test.dart';
import 'package:fruler/app/app_controller.dart';
import 'package:fruler/core/core.dart';

import '../fake_desktop.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('截图内手动多框只固定结果，不复制、不写历史、不结束会话', () async {
    final d = FakeDesktop();
    final c = AppController(d);
    await c.initialize();
    try {
      await c.startScreenshot();
      d.event('modeChanged', {'tool': 'rectangle'});
      for (final x in [0.0, 2.0]) {
        d.pointer(x: x, y: 0, phase: 'down');
        d.pointer(x: x + 1, y: 1, phase: 'up');
        await Future<void>.delayed(Duration.zero);
      }
      expect((d.lastOverlay!['pinned'] as List).length, 2);
      expect(d.clipboard, isNull);
      expect(c.measurements, isEmpty);
      expect(c.busy, true);
      expect(d.beginCalls, 1);
      d.event('undoPins');
      expect((d.lastOverlay!['pinned'] as List).length, 1);
      d.event('redoPins');
      expect((d.lastOverlay!['pinned'] as List).length, 2);
      d.event('modeChanged', {'tool': 'screenshot'});
      expect((d.lastOverlay!['pinned'] as List).length, 2);
    } finally {
      c.dispose();
      await d.input.close();
    }
  });

  test('截图内自动测距单击固定，保留方向，M 复制后结束', () async {
    final d = FakeDesktop();
    final c = AppController(d);
    await c.initialize();
    try {
      await c.startScreenshot();
      d.event('modeChanged', {'tool': 'horizontal'});
      d.pointer(x: 1, y: 1, phase: 'down');
      d.pointer(x: 1, y: 1, phase: 'up');
      await Future<void>.delayed(Duration.zero);
      expect(c.busy, true);
      expect(d.clipboard, isNull);
      final pins = d.lastOverlay!['pinned'] as List;
      expect(pins, hasLength(1));
      expect((pins.single as Map)['mode'], 'horizontal');
      d.event('copyCaptureSize');
      await Future<void>.delayed(Duration.zero);
      expect(c.busy, false);
      expect(d.clipboard, '8 px · 4 pt');
      expect(c.measurements.single.measurement.mode.name, 'horizontal');
      expect(d.showMainCalls, 0);
    } finally {
      c.dispose();
      await d.input.close();
    }
  });
  test('自动交叉固定保留取样点，复制失败保留会话并允许重试', () async {
    final d = FakeDesktop();
    final c = AppController(d);
    await c.initialize();
    try {
      await c.startScreenshot();
      d.event('modeChanged', {'tool': 'cross'});
      d.pointer(x: 1, y: 0.5, phase: 'up');
      final pin = c.captureMeasurementPins.single;
      expect(pin.seed!.x, 2);
      expect(pin.seed!.y, 1);
      d.clipboardError = StateError('clipboard unavailable');
      await c.copyCaptureMeasurements(all: true);
      expect(c.busy, true);
      expect(c.captureMeasurementPins, hasLength(1));
      expect(c.measurements, isEmpty);
      expect(d.finishCalls, 0);
      d.clipboardError = null;
      await c.copyCaptureMeasurements(all: true);
      expect(d.clipboard, '#${pin.id} 8 × 6 px · 4 × 3 pt');
      expect(c.busy, false);
      expect(c.measurements, hasLength(1));
    } finally {
      c.dispose();
      await d.input.close();
    }
  });

  test('Esc 取消手动拖动和测量状态，不产生结果或关闭截图', () async {
    final d = FakeDesktop();
    final c = AppController(d);
    await c.initialize();
    try {
      await c.startScreenshot();
      d.event('toggleCaptureRuler');
      d.pointer(x: 0, y: 0, phase: 'down');
      d.pointer(x: 2, y: 2, phase: 'drag');
      d.event('cancelCaptureInteraction');
      expect(c.captureMeasurementPins, isEmpty);
      expect(c.canUndoCaptureMeasurements, false);
      expect(c.captureRulerMode?.name, 'rectangle');
      expect(c.busy, true);
      d.event('cancelCaptureInteraction');
      expect(c.captureRulerMode, isNull);
      expect(c.busy, true);
      expect(d.beginCalls, 1);
    } finally {
      c.dispose();
      await d.input.close();
    }
  });
  test('独立尺子切入截图后复用会话，并启用截图测量规则', () async {
    final d = FakeDesktop();
    final c = AppController(d);
    await c.initialize();
    try {
      await c.startRuler();
      d.event('modeChanged', {'tool': 'screenshot'});
      d.event('toggleCaptureRuler');
      d.pointer(x: 0, y: 0, phase: 'down');
      d.pointer(x: 1, y: 1, phase: 'up');
      expect(c.captureMeasurementPins, hasLength(1));
      expect(c.measurements, isEmpty);
      expect(d.clipboard, isNull);
      expect(d.beginCalls, 1);
    } finally {
      c.dispose();
      await d.input.close();
    }
  });

  test('自动测距结果在手动模式下保持原边界和取样点', () async {
    final d = FakeDesktop();
    final c = AppController(d);
    await c.initialize();
    try {
      await c.startScreenshot();
      d.event('modeChanged', {'tool': 'cross'});
      d.pointer(x: 1, y: 1, phase: 'up');
      final pin = c.captureMeasurementPins.single;
      c.setCaptureRulerMode(RulerMode.rectangle);
      d.event('pinDrag', {'id': pin.id, 'phase': 'start'});
      d.event('pinDrag', {
        'id': pin.id,
        'phase': 'end',
        'displayId': 1,
        'dx': 1.0,
        'dy': 1.0,
        'handle': 'move',
      });
      expect(
        c.captureMeasurementPins.single.measurement.rect.toJson(),
        pin.measurement.rect.toJson(),
      );
      expect(c.captureMeasurementPins.single.seed!.x, pin.seed!.x);
    } finally {
      c.dispose();
      await d.input.close();
    }
  });
}
