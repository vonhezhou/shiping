import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fruler/app/app_controller.dart';
import 'package:fruler/core/core.dart';

import '../fake_desktop.dart';

class WaitingPinDesktop extends FakeDesktop {
  final releasePin = Completer<void>();
  @override
  Future<void> pinClipboard() async {
    await releasePin.future;
    await super.pinClipboard();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('贴图成功才结束截图，带上Retina选区并加入历史且不改剪贴板', () async {
    final d = FakeDesktop();
    final c = AppController(d);
    await c.initialize();
    addTearDown(() async {
      c.dispose();
      await d.input.close();
    });
    await c.startScreenshot();
    d.pointer(x: 1, y: 1, phase: 'down');
    d.pointer(x: 3, y: 2.5, phase: 'up');
    while (c.imageDocument == null || c.imageLoading) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    final selection = c.screenshotSelection;
    d.pinError = PlatformException(code: 'pin_failed');
    await c.pinScreenshot();
    expect(c.screenshotEditing, true);
    expect(d.finishCalls, 0);
    expect(c.screenshots, isEmpty);
    d.pinError = null;
    await c.pinScreenshot();
    expect(d.pinnedImage, isNotNull);
    expect(d.pinBounds, selection);
    expect(d.pinSession, 7);
    expect(d.pinDisplay, 1);
    expect(c.screenshots.single, d.pinnedImage);
    expect(c.busy, false);
    expect(d.finishCalls, 1);
    expect(d.exportedImage, isNull);
    expect(d.showMainCalls, 0);
  });

  test('历史和剪贴板贴图不申请录屏且失败保留错误', () async {
    final d = FakeDesktop()..permission = false;
    final c = AppController(d);
    await c.initialize();
    addTearDown(() async {
      c.dispose();
      await d.input.close();
    });
    await c.pinClipboard();
    expect(d.pinClipboardCalls, 1);
    final png = Uint8List.fromList([1, 2]);
    await c.pinScreenshotFromHistory(png);
    expect(d.pinnedImage, png);
    expect(d.pinSession, isNull);
    expect(d.beginCalls, 0);
    await c.togglePinnedImages();
    await c.closePinnedImages();
    expect(d.togglePinCalls, 1);
    expect(d.closePinCalls, 1);
    d.pinError = PlatformException(code: 'empty_clipboard');
    await c.pinClipboard();
    expect(c.error, isNotNull);
    expect(d.beginCalls, 0);
    expect(d.showMainCalls, 1, reason: '全局入口失败时展示现有错误横幅');
  });

  test('贴图跨通道等待期间全局截图入口和快捷键录制保持互斥', () async {
    final d = WaitingPinDesktop();
    final c = AppController(d);
    await c.initialize();
    final pending = c.pinClipboard();
    try {
      expect(c.pinningImage, true);
      d.event('activate', {'tool': 'screenshot'});
      await c.startScreenshot();
      expect(d.beginCalls, 0);
      expect(await c.beginShortcutRecording(), false);
    } finally {
      d.releasePin.complete();
      await pending;
      c.dispose();
      await d.input.close();
    }
  });

  test('修改原有快捷键保留贴图组合并拒绝五组间冲突', () async {
    final d = FakeDesktop();
    final c = AppController(d);
    await c.initialize();
    addTearDown(() async {
      c.dispose();
      await d.input.close();
    });
    expect(await c.setShortcut(true, c.shortcuts.pinClipboard), false);
    expect(
      await c.setShortcut(
        false,
        const ShortcutChord(key: 'J', meta: true, shift: true),
        pinClipboard: true,
      ),
      true,
    );
    expect(c.shortcuts.pinClipboard.key, 'J');
    expect(
      await c.setShortcut(
        true,
        const ShortcutChord(key: 'K', meta: true, shift: true),
      ),
      true,
    );
    expect(c.shortcuts.pinClipboard.key, 'J');
  });
}
