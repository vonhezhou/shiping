import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:fruler/core/text_recognition.dart';

void main() {
  final document = RecognizedTextDocument([
    RecognizedTextLine(
      text: 'Hello World',
      glyphs: const [
        RecognizedTextGlyph(0, 5, Rect.fromLTWH(0, 0, 50, 20)),
        RecognizedTextGlyph(6, 11, Rect.fromLTWH(60, 0, 50, 20)),
      ],
    ),
    RecognizedTextLine(
      text: '你好世界',
      glyphs: const [
        RecognizedTextGlyph(0, 2, Rect.fromLTWH(0, 30, 40, 20)),
        RecognizedTextGlyph(2, 4, Rect.fromLTWH(40, 30, 40, 20)),
      ],
    ),
  ]);
  test('按词跨行和反向选择得到相同文本和高亮，保留词间空格', () {
    const a = RecognizedTextPosition(0, 0), b = RecognizedTextPosition(1, 2);
    expect(document.selectedText(a, b), 'Hello World\n你好');
    expect(document.selectedText(b, a), 'Hello World\n你好');
    expect(document.selectionBoxes(a, b), hasLength(3));
    expect(document.selectedText(a, a), '');
    expect(document.text, 'Hello World\n你好世界');
  });
  test('命中只返回完整单词边界，空白不命中，拖出文字选择最近位置', () {
    expect(document.hit(const Offset(24, 10))?.offset, 0);
    expect(document.hit(const Offset(26, 10))?.offset, 5);
    expect(document.hit(const Offset(55, 10)), isNull);
    expect(document.hit(const Offset(200, 10)), isNull);
    expect(document.hit(const Offset(200, 40), nearest: true)?.line, 1);
    expect(document.hit(const Offset(200, 10), nearest: true)?.offset, 11);
    expect(document.hit(const Offset(-20, 50), nearest: true)?.line, 1);
  });
  test('UTF-16 范围保留完整 emoji，不拆代理对或组合字符', () {
    final emoji = RecognizedTextDocument([
      RecognizedTextLine(
        text: 'A👩‍💻B',
        glyphs: const [
          RecognizedTextGlyph(0, 1, Rect.fromLTWH(0, 0, 10, 20)),
          RecognizedTextGlyph(1, 6, Rect.fromLTWH(10, 0, 20, 20)),
          RecognizedTextGlyph(6, 7, Rect.fromLTWH(30, 0, 10, 20)),
        ],
      ),
    ]);
    expect(emoji.hit(const Offset(15, 10))?.offset, 1);
    expect(emoji.hit(const Offset(25, 10))?.offset, 6);
    expect(
      emoji.selectedText(
        const RecognizedTextPosition(0, 1),
        const RecognizedTextPosition(0, 6),
      ),
      '👩‍💻',
    );
  });
}
