import 'package:flutter_test/flutter_test.dart';
import 'package:fruler/app/app_controller.dart';
import 'package:fruler/core/core.dart';

import 'dart:async';

import 'package:fruler/platform/image_document.dart';

import '../fake_desktop.dart';

class PausedCaptureCodec extends ImageDocumentCodec {
  Completer<void>? pause;
  @override
  Future<ImageDocument> decodeCapturePng(ImageFileData file) async {
    final waiting = pause;
    if (waiting != null) await waiting.future;
    return super.decodeCapturePng(file);
  }
}

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
  test('调整截图选区复用冻结快照，校验边界并保护已存在的标注', () async {
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
      await c.adjustScreenshotSelection(
        const PixelRect(left: 0, top: 0, right: 8, bottom: 6),
      );
      expect(c.imageDocument!.frame.width, 8);
      expect(c.imageDocument!.frame.height, 6);
      expect(c.screenshotSourceSize, (width: 8, height: 6));
      expect(d.beginCalls, 1);
      expect(d.finishCalls, 0);
      expect(d.showMainCalls, 0);
      final doc = c.imageDocument;
      await c.adjustScreenshotSelection(
        const PixelRect(left: 0, top: 0, right: 9, bottom: 6),
      );
      expect(c.imageDocument, same(doc));
      c.markup.commit([
        Annotation(
          kind: AnnotationKind.rectangle,
          points: const [Offset.zero, Offset(2, 2)],
        ),
      ]);
      await c.adjustScreenshotSelection(
        const PixelRect(left: 0, top: 0, right: 4, bottom: 4),
      );
      expect(c.imageDocument, same(doc));
      expect(c.markup.items, hasLength(1));
      expect(c.busy, true);
    } finally {
      c.dispose();
      await d.input.close();
    }
  });
  test('调整选区中取消释放加载状态，迟到的解码不能恢复已取消截图', () async {
    final d = FakeDesktop(), codec = PausedCaptureCodec();
    final c = AppController(d, imageCodec: codec);
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
      codec.pause = Completer<void>();
      final resizing = c.adjustScreenshotSelection(
        const PixelRect(left: 0, top: 0, right: 8, bottom: 6),
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(c.imageLoading, true);
      await c.cancelScreenshot();
      expect(c.imageLoading, false);
      codec.pause!.complete();
      await resizing;
      expect(c.screenshotEditing, false);
      expect(c.busy, false);
      await c.startScreenshot();
      expect(d.beginCalls, 2);
    } finally {
      if (codec.pause != null && !codec.pause!.isCompleted) {
        codec.pause!.complete();
      }
      c.dispose();
      await d.input.close();
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
