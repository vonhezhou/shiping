import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fruler/core/core.dart';

void main() {
  test('窗口候选必须包含光标并位于截图像素范围，拒绝损坏边界', () {
    final frame = PixelFrame(
      width: 60,
      height: 30,
      logicalWidth: 40,
      logicalHeight: 20,
      rgba: Uint8List(60 * 30 * 4),
    );
    const valid = {'left': 15, 'top': 6, 'right': 45, 'bottom': 24};
    expect(
      CaptureControls.suggestedRect(frame, valid, 20, 10)!.toJson(),
      valid,
    );
    for (final value in [
      null,
      {'left': -1, 'top': 0, 'right': 61, 'bottom': 30},
      {'left': 15, 'top': 6, 'right': 15, 'bottom': 24},
      {'left': 15.0, 'top': 6, 'right': 45, 'bottom': 24},
    ]) {
      expect(CaptureControls.suggestedRect(frame, value, 20, 10), isNull);
    }
    expect(CaptureControls.suggestedRect(frame, valid, 1, 1), isNull);
  });

  test('非整数缩放连续微调无累计误差，边界钳制到像素中心', () {
    final frame = PixelFrame(
      width: 60,
      height: 30,
      logicalWidth: 40,
      logicalHeight: 20,
      rgba: Uint8List(60 * 30 * 4),
    );
    var p = (x: 0.0, y: 0.0);
    for (var i = 1; i <= 59; i++) {
      p = CaptureControls.nudge(frame, p.x, p.y, 1, 0);
      expect(frame.logicalToPixel(p.x, p.y).x, i);
    }
    p = CaptureControls.nudge(frame, p.x, p.y, 1, -1);
    expect(frame.logicalToPixel(p.x, p.y).x, 59);
    expect(frame.logicalToPixel(p.x, p.y).y, 0);
    for (var i = 58; i >= 0; i--) {
      p = CaptureControls.nudge(frame, p.x, p.y, -1, 0);
      expect(frame.logicalToPixel(p.x, p.y).x, i);
    }
  });
  test('滚轮倍率和容差在极限处保持有效范围', () {
    expect(CaptureControls.adjustZoom(12, 1), 16);
    expect(CaptureControls.adjustZoom(12, -99), 4);
    expect(CaptureControls.adjustZoom(12, 99), 32);
    expect(CaptureControls.adjustTolerance(16, 1), 31);
    expect(CaptureControls.adjustTolerance(16, -99), 0);
    expect(CaptureControls.adjustTolerance(16, 99), 255);
  });
  test('快捷键序列化和重复组合验证', () {
    const chord = ShortcutChord(key: '8', control: true, alt: true);
    expect(ShortcutChord.fromJson(chord.toJson()), chord);
    expect(chord.isValid, true);
    expect(const ShortcutChord(key: 'A', shift: true).isValid, false);
    expect(ShortcutBindings(picker: chord, ruler: chord).isValid, false);
    expect(
      () => ShortcutBindings.fromJson({'picker': null}),
      throwsFormatException,
    );
  });
}
