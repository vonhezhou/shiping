import 'package:flutter_test/flutter_test.dart';
import 'package:fruler/app/app_controller.dart';

import '../fake_desktop.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('截图选区完成后留在原生浮层，不结束会话或返回主窗口', () async {
    final desktop = FakeDesktop();
    final c = AppController(desktop);
    await c.initialize();
    try {
      await c.startScreenshot();
      desktop.pointer(x: 1, y: 1, phase: 'down');
      desktop.pointer(x: 3, y: 2.5, phase: 'up');
      for (var i = 0; i < 100 && c.imageDocument == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(c.imageDocument, isNotNull);
      expect(desktop.finishCalls, 0);
      expect(desktop.showMainCalls, 0);
      expect(c.busy, true);
    } finally {
      c.dispose();
      await desktop.input.close();
    }
  });
  test('保存取消继续标注，重新框选不退出屏幕，复制后才结束并记历史', () async {
    final d = FakeDesktop();
    final c = AppController(d);
    await c.initialize();
    try {
      await c.startScreenshot();
      d.pointer(x: 1, y: 1, phase: 'down');
      d.pointer(x: 3, y: 2.5, phase: 'up');
      for (
        var i = 0;
        i < 100 && (c.imageDocument == null || c.imageLoading);
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      d.fileResult = false;
      await c.exportScreenshot(save: true);
      expect(c.screenshotEditing, true);
      expect(c.busy, true);
      expect(d.finishCalls, 0);
      expect(c.screenshots, isEmpty);
      await c.reselectScreenshot();
      expect(c.screenshotEditing, false);
      expect(c.busy, true);
      expect(d.finishCalls, 0);
      d.pointer(x: 1, y: 1, phase: 'down');
      d.pointer(x: 3, y: 2.5, phase: 'up');
      for (
        var i = 0;
        i < 100 && (c.imageDocument == null || c.imageLoading);
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      d.fileResult = true;
      await c.exportScreenshot(save: false);
      expect(c.busy, false);
      expect(c.imageDocument, isNull);
      expect(c.screenshots.length, 1);
      expect(d.showMainCalls, 0);
      expect(d.finishCalls, 1);
    } finally {
      c.dispose();
      await d.input.close();
    }
  });
  test('启动不读取旧图片草稿，取消截图不产生历史或打开主窗口', () async {
    final d = FakeDesktop();
    final c = AppController(d);
    await c.initialize();
    try {
      expect(c.error, isNull);
      await c.startScreenshot();
      await c.cancelScreenshot();
      expect(c.busy, false);
      expect(c.screenshots, isEmpty);
      expect(d.showMainCalls, 0);
    } finally {
      c.dispose();
      await d.input.close();
    }
  });
}
