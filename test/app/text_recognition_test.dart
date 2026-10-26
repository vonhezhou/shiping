import 'dart:async';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:fruler/core/core.dart';

import 'qr_code_test.dart' show QrDesktop, selection;

class TextDesktop extends QrDesktop {
  Completer<List<RecognizedTextLine>>? pendingText;
  bool copyFails = false;
  final copies = <String>[];
  List<RecognizedTextLine> textLines = [
    RecognizedTextLine(
      text: 'Hello',
      glyphs: const [RecognizedTextGlyph(0, 5, Rect.fromLTWH(0, 0, 20, 10))],
    ),
  ];
  @override
  Future<List<RecognizedTextLine>> recognizeText(
    int sessionId,
    int displayId,
    PixelRect rect,
  ) async => pendingText?.future ?? textLines;
  @override
  Future<void> writeClipboard(String text) async {
    if (copyFails) throw StateError('clipboard unavailable');
    copies.add(text);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('只在主动选择后复制，重复复制保留会话，完成复制才结束', () async {
    final desktop = TextDesktop();
    final c = await selection(desktop);
    addTearDown(c.dispose);
    addTearDown(desktop.input.close);
    await c.recognizeText();
    expect(c.textMode, true);
    expect(c.canAdjustScreenshotSelection, false);
    await c.copyRecognizedText();
    expect(desktop.copies, isEmpty);
    await c.copyRecognizedText(selectedText: 'ell');
    await c.copyRecognizedText(selectedText: 'Hello');
    expect(desktop.copies, ['ell', 'Hello']);
    expect(c.screenshotEditing, true);
    await c.copyRecognizedText(finish: true);
    expect(desktop.copies.last, 'Hello');
    expect(c.screenshotEditing, false);
  });
  test('退出文字模式立即丢弃迟到识别结果，保留截图', () async {
    final desktop = TextDesktop()..pendingText = Completer();
    final c = await selection(desktop);
    addTearDown(c.dispose);
    addTearDown(desktop.input.close);
    final task = c.recognizeText();
    c.dismissText();
    desktop.pendingText!.complete(desktop.textLines);
    await task;
    expect(c.textMode, false);
    expect(c.recognizedText, isNull);
    expect(c.screenshotEditing, true);
  });
  test('取消截图丢弃迟到识别结果', () async {
    final desktop = TextDesktop()..pendingText = Completer();
    final c = await selection(desktop);
    addTearDown(c.dispose);
    addTearDown(desktop.input.close);
    final task = c.recognizeText();
    await c.cancelScreenshot();
    desktop.pendingText!.complete(desktop.textLines);
    await task;
    expect(c.recognizedText, isNull);
    expect(c.textMode, false);
  });
  test('空白和识别失败返回标注；复制失败保留模式供重试', () async {
    final desktop = TextDesktop()..textLines = [];
    final c = await selection(desktop);
    addTearDown(c.dispose);
    addTearDown(desktop.input.close);
    await c.recognizeText();
    expect(c.textMode, false);
    expect(c.error, isNotNull);
    desktop.pendingText = Completer()
      ..completeError(StateError('Vision failed'));
    await c.recognizeText();
    expect(c.textMode, false);
    expect(c.error, isNotNull);
    desktop.pendingText = null;
    desktop.textLines = [RecognizedTextLine(text: '重试', glyphs: const [])];
    await c.recognizeText();
    desktop.copyFails = true;
    await c.copyRecognizedText(finish: true);
    expect(c.textMode, true);
    expect(c.error, isNotNull);
    desktop.copyFails = false;
    await c.copyRecognizedText(finish: true);
    expect(c.screenshotEditing, false);
  });
}
