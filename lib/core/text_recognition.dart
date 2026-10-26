import 'dart:math' as math;
import 'dart:ui';

/// 一个不可再细分的识别单词、词组或标点范围。
class RecognizedTextGlyph {
  const RecognizedTextGlyph(this.start, this.end, this.bounds);
  final int start, end;
  final Rect bounds;
}

class RecognizedTextLine {
  RecognizedTextLine({
    required this.text,
    required List<RecognizedTextGlyph> glyphs,
  }) : glyphs = List.unmodifiable(glyphs);
  final String text;
  final List<RecognizedTextGlyph> glyphs;
}

class RecognizedTextPosition {
  const RecognizedTextPosition(this.line, this.offset);
  final int line, offset;
  int compareTo(RecognizedTextPosition other) => line == other.line
      ? offset.compareTo(other.offset)
      : line.compareTo(other.line);
}

/// 位置和文字范围均来自原生 OCR；偏移使用 Dart 与 NSString 共用的 UTF-16 单位。
class RecognizedTextDocument {
  RecognizedTextDocument(List<RecognizedTextLine> lines)
    : lines = List.unmodifiable(lines);
  final List<RecognizedTextLine> lines;
  String get text => lines.map((line) => line.text).join('\n');
  RecognizedTextPosition get start => const RecognizedTextPosition(0, 0);
  RecognizedTextPosition get end =>
      RecognizedTextPosition(lines.length - 1, lines.last.text.length);

  RecognizedTextPosition? hit(Offset point, {bool nearest = false}) {
    RecognizedTextPosition? result;
    var verticalDistance = double.infinity,
        horizontalDistance = double.infinity;
    for (var index = 0; index < lines.length; index++) {
      for (final glyph in lines[index].glyphs) {
        final box = glyph.bounds;
        final inside = box.contains(point);
        if (!nearest && !inside) continue;
        final dx = math.max(
          0.0,
          math.max(box.left - point.dx, point.dx - box.right),
        );
        final dy = math.max(
          0.0,
          math.max(box.top - point.dy, point.dy - box.bottom),
        );
        // 拖到短行右侧时优先匹配所在行，不能跳回横向更接近的上一长行。
        if (dy < verticalDistance ||
            (dy == verticalDistance && dx < horizontalDistance)) {
          verticalDistance = dy;
          horizontalDistance = dx;
          result = RecognizedTextPosition(
            index,
            point.dx < box.center.dx ? glyph.start : glyph.end,
          );
        }
      }
    }
    return result;
  }

  String selectedText(
    RecognizedTextPosition anchor,
    RecognizedTextPosition extent,
  ) {
    final (a, b) = anchor.compareTo(extent) <= 0
        ? (anchor, extent)
        : (extent, anchor);
    return [
      for (var i = a.line; i <= b.line; i++)
        lines[i].text.substring(
          i == a.line ? a.offset : 0,
          i == b.line ? b.offset : lines[i].text.length,
        ),
    ].join('\n');
  }

  List<Rect> selectionBoxes(
    RecognizedTextPosition anchor,
    RecognizedTextPosition extent,
  ) {
    final (a, b) = anchor.compareTo(extent) <= 0
        ? (anchor, extent)
        : (extent, anchor);
    return [
      for (var i = a.line; i <= b.line; i++)
        for (final glyph in lines[i].glyphs)
          if (glyph.end > (i == a.line ? a.offset : 0) &&
              glyph.start < (i == b.line ? b.offset : lines[i].text.length))
            glyph.bounds,
    ];
  }
}
