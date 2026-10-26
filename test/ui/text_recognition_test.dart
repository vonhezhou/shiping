import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fruler/core/core.dart';

import 'qr_code_test.dart' show QrUiDesktop, editor;

class TextUiDesktop extends QrUiDesktop {
  Completer<List<RecognizedTextLine>>? pending;
  final copies = <String>[];
  final lines = [
    RecognizedTextLine(
      text: 'Hello',
      glyphs: const [RecognizedTextGlyph(0, 5, Rect.fromLTWH(20, 20, 100, 20))],
    ),
    RecognizedTextLine(
      text: '你好世界',
      glyphs: const [
        RecognizedTextGlyph(0, 2, Rect.fromLTWH(20, 60, 40, 20)),
        RecognizedTextGlyph(2, 4, Rect.fromLTWH(60, 60, 40, 20)),
      ],
    ),
  ];
  bool failCopy = false;
  @override
  Future<List<RecognizedTextLine>> recognizeText(
    int sessionId,
    int displayId,
    PixelRect rect,
  ) async => pending?.future ?? lines;
  @override
  Future<void> writeClipboard(String text) async {
    if (failCopy) throw StateError('copy failed');
    copies.add(text);
  }
}

Future<void> command(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  await tester.pumpAndSettle();
}

void main() {
  for (final size in [const Size(1100, 760), const Size(920, 680)]) {
    testWidgets('图上鼠标跨行选字、重复复制、全选、退出恢复标注 $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final desktop = TextUiDesktop();
      final c = await editor(tester, desktop);
      // 验证像素坐标按两轴倍率独立映射到屏幕。
      c.screenshotScaleX = 2;
      c.screenshotScaleY = 1.5;
      await tester.tap(
        find.byKey(const ValueKey('recognize-text')),
        kind: ui.PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('copy-screenshot')), findsNothing);
      expect(c.canAdjustScreenshotSelection, false);
      await command(tester, LogicalKeyboardKey.keyC);
      expect(desktop.copies, isEmpty);
      Offset at(double x, double y) => Offset(
        (c.screenshotSelection!.left + x) / c.screenshotScaleX,
        (c.screenshotSelection!.top + y) / c.screenshotScaleY,
      );
      final mouse = TestGesture(
        dispatcher: tester.sendEventToBinding,
        kind: ui.PointerDeviceKind.mouse,
        device: 800,
        pointer: 800,
      );
      await mouse.addPointer(location: at(25, 30));
      await mouse.down(at(25, 30));
      await mouse.moveTo(at(59, 70));
      await mouse.up();
      await tester.pumpAndSettle();
      await command(tester, LogicalKeyboardKey.keyC);
      expect(desktop.copies, ['Hello\n你好']);
      expect(c.textMode, true);
      desktop.failCopy = true;
      await command(tester, LogicalKeyboardKey.keyC);
      expect(c.error, isNotNull);
      expect(c.textMode, true);
      desktop.failCopy = false;
      await command(tester, LogicalKeyboardKey.keyC);
      expect(desktop.copies.last, 'Hello\n你好');
      await command(tester, LogicalKeyboardKey.keyA);
      await command(tester, LogicalKeyboardKey.keyC);
      expect(desktop.copies.last, 'Hello\n你好世界');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(c.textMode, false);
      expect(c.screenshotEditing, true);
      expect(find.byKey(const ValueKey('recognize-text')), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(c.screenshotEditing, false);
      await mouse.removePointer();
    });
  }
  testWidgets('最小窗口近全屏选区的文字操作仍可点击', (tester) async {
    const size = Size(920, 680);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final desktop = TextUiDesktop();
    final c = await editor(tester, desktop, screenSize: size);
    await c.adjustScreenshotSelection(
      const PixelRect(left: 5, top: 5, right: 915, bottom: 675),
    );
    await tester.pumpAndSettle();
    await c.recognizeText();
    await tester.pumpAndSettle();
    final button = find.byKey(const ValueKey('copy-all-text-finish'));
    expect(tester.getRect(button).bottom, lessThanOrEqualTo(size.height));
    expect(button.hitTestable(), findsOneWidget);
  });
  testWidgets('Esc 取消识别不结束截图，迟到结果不显示；完成按钮复制全部并结束', (tester) async {
    final desktop = TextUiDesktop()..pending = Completer();
    final c = await editor(tester, desktop);
    await tester.tap(find.byKey(const ValueKey('recognize-text')));
    await tester.pump();
    expect(c.textRecognizing, true);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    desktop.pending!.complete(desktop.lines);
    await tester.pumpAndSettle();
    expect(c.textMode, false);
    expect(c.screenshotEditing, true);
    desktop.pending = null;
    await tester.tap(find.byKey(const ValueKey('recognize-text')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('copy-all-text-finish')));
    await tester.pumpAndSettle();
    expect(desktop.copies, ['Hello\n你好世界']);
    expect(c.screenshotEditing, false);
    expect(desktop.showMainCalls, 0);
  });
}
