import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

enum AnnotationKind {
  rectangle,
  ellipse,
  line,
  arrow,
  pencil,
  marker,
  text,
  mosaic,
  blur;

  String get label => const {
    rectangle: '矩形',
    ellipse: '椭圆',
    line: '直线',
    arrow: '箭头',
    pencil: '画笔',
    marker: '荧光笔',
    text: '文字',
    mosaic: '马赛克',
    blur: '模糊',
  }[this]!;
}

/// Immutable, image-pixel coordinates shared by preview, export and documents.
class Annotation {
  Annotation({
    required this.kind,
    required List<Offset> points,
    this.color = 0xFFFF5252,
    this.width = 3,
    this.fontSize = 24,
    this.text = '',
  }) : points = List.unmodifiable(points);
  final AnnotationKind kind;
  final List<Offset> points;
  final int color;
  final double width, fontSize;
  final String text;

  Rect get bounds {
    var l = points.first.dx, r = l, t = points.first.dy, b = t;
    for (final p in points.skip(1)) {
      l = math.min(l, p.dx);
      r = math.max(r, p.dx);
      t = math.min(t, p.dy);
      b = math.max(b, p.dy);
    }
    return Rect.fromLTRB(l, t, r, b);
  }

  Annotation copyWith({
    List<Offset>? points,
    int? color,
    double? width,
    double? fontSize,
    String? text,
  }) => Annotation(
    kind: kind,
    points: points ?? this.points,
    color: color ?? this.color,
    width: width ?? this.width,
    fontSize: fontSize ?? this.fontSize,
    text: text ?? this.text,
  );

  Annotation move(Offset delta, Size size) {
    final b = bounds;
    final d = Offset(
      delta.dx.clamp(-b.left, size.width - b.right),
      delta.dy.clamp(-b.top, size.height - b.bottom),
    );
    return copyWith(points: points.map((p) => p + d).toList());
  }

  Annotation resize(Rect next) {
    final b = bounds;
    final sx = next.width / math.max(1, b.width);
    final sy = next.height / math.max(1, b.height);
    return copyWith(
      points: points
          .map(
            (p) => Offset(
              next.left + (p.dx - b.left) * sx,
              next.top + (p.dy - b.top) * sy,
            ),
          )
          .toList(),
      fontSize: kind == AnnotationKind.text
          ? (fontSize * math.min(sx, sy)).clamp(8, 200)
          : fontSize,
    );
  }

  bool hitTest(Offset p, double tolerance) {
    if (!bounds.inflate(tolerance + width / 2).contains(p)) return false;
    if ([
      AnnotationKind.line,
      AnnotationKind.arrow,
      AnnotationKind.pencil,
      AnnotationKind.marker,
    ].contains(kind)) {
      for (var i = 1; i < points.length; i++) {
        final a = points[i - 1], d = points[i] - a;
        final length = d.distanceSquared;
        final u = length == 0
            ? 0.0
            : (((p - a).dx * d.dx + (p - a).dy * d.dy) / length).clamp(
                0.0,
                1.0,
              );
        if ((p - (a + d * u)).distance <= tolerance + width / 2) return true;
      }
      return false;
    }
    return true;
  }

  /// Whole-object marquee selection. Paths use their segments so an empty
  /// corner of a diagonal's bounding box does not erase the stroke.
  bool intersects(Rect region) {
    final r = region.inflate(width / 2);
    bool segment(Offset a, Offset b) {
      var low = 0.0, high = 1.0;
      final d = b - a;
      for (final axis in [
        (a.dx, d.dx, r.left, r.right),
        (a.dy, d.dy, r.top, r.bottom),
      ]) {
        if (axis.$2 == 0) {
          if (axis.$1 < axis.$3 || axis.$1 > axis.$4) return false;
        } else {
          final t1 = (axis.$3 - axis.$1) / axis.$2;
          final t2 = (axis.$4 - axis.$1) / axis.$2;
          low = math.max(low, math.min(t1, t2));
          high = math.min(high, math.max(t1, t2));
          if (low > high) return false;
        }
      }
      return true;
    }

    if ([
      AnnotationKind.line,
      AnnotationKind.arrow,
      AnnotationKind.pencil,
      AnnotationKind.marker,
    ].contains(kind)) {
      for (var i = 1; i < points.length; i++) {
        if (segment(points[i - 1], points[i])) return true;
      }
      if (kind == AnnotationKind.arrow) {
        final a = points.first, b = points.last;
        final angle = math.atan2(b.dy - a.dy, b.dx - a.dx);
        final length = math.max(10.0, width * 4);
        for (final turn in [-.45, .45]) {
          if (segment(
            b,
            b - Offset(math.cos(angle + turn), math.sin(angle + turn)) * length,
          )) {
            return true;
          }
        }
      }
      return false;
    }
    final b = bounds;
    return b.left <= r.right &&
        b.right >= r.left &&
        b.top <= r.bottom &&
        b.bottom >= r.top;
  }

  Map<String, Object> toJson() => {
    'kind': kind.name,
    'points': points.map((p) => [p.dx, p.dy]).toList(),
    'color': color,
    'width': width,
    'fontSize': fontSize,
    'text': text,
  };

  static List<Annotation> decodeList(Object? value, int width, int height) {
    if (value == null) return [];
    if (value is! List || value.length > 4096) {
      throw const FormatException('通用标注数量无效');
    }
    var totalPoints = 0;
    return value.map((v) {
      if (v is! Map) throw const FormatException('通用标注无效');
      final kind = AnnotationKind.values
          .where((k) => k.name == v['kind'])
          .firstOrNull;
      final raw = v['points'], color = v['color'], stroke = v['width'];
      final font = v['fontSize'], text = v['text'];
      if (kind == null ||
          raw is! List ||
          raw.length < 2 ||
          raw.length > 20000 ||
          color is! int ||
          color < 0 ||
          color > 0xFFFFFFFF ||
          stroke is! num ||
          !stroke.isFinite ||
          stroke < 1 ||
          stroke > 80 ||
          font is! num ||
          !font.isFinite ||
          font < 8 ||
          font > 200 ||
          text is! String ||
          text.length > 4096 ||
          (kind == AnnotationKind.text && text.trim().isEmpty)) {
        throw const FormatException('通用标注类型或样式无效');
      }
      totalPoints += raw.length;
      if (totalPoints > 200000) throw const FormatException('标注笔画过多');
      final points = raw.map((p) {
        if (p is! List || p.length != 2 || p[0] is! num || p[1] is! num) {
          throw const FormatException('标注坐标无效');
        }
        final x = (p[0] as num).toDouble(), y = (p[1] as num).toDouble();
        if (!x.isFinite ||
            !y.isFinite ||
            x < 0 ||
            y < 0 ||
            x > width ||
            y > height) {
          throw const FormatException('标注超出图片边界');
        }
        return Offset(x, y);
      }).toList();
      if (kind != AnnotationKind.pencil &&
          kind != AnnotationKind.marker &&
          points.length != 2) {
        throw const FormatException('标注端点数量无效');
      }
      return Annotation(
        kind: kind,
        points: points,
        color: color,
        width: stroke.toDouble(),
        fontSize: font.toDouble(),
        text: text,
      );
    }).toList();
  }
}

class AnnotationHistory extends ChangeNotifier {
  List<Annotation> _items = const [];
  final _undo = <List<Annotation>>[], _redo = <List<Annotation>>[];
  List<Annotation> get items => _items;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  void reset([List<Annotation> items = const []]) {
    _items = List.unmodifiable(items);
    _undo.clear();
    _redo.clear();
  }

  void commit(List<Annotation> items) {
    if (listEquals(items, _items)) return;
    if (items.length > 4096 ||
        items.fold<int>(0, (n, a) => n + a.points.length) > 200000) {
      throw const FormatException('标注达到数量上限，请删除部分标注');
    }
    _undo.add(_items);
    if (_undo.length > 64) _undo.removeAt(0);
    _items = List.unmodifiable(items);
    _redo.clear();
    notifyListeners();
  }

  void undo() => _restore(_undo, _redo);
  void redo() => _restore(_redo, _undo);
  void _restore(List<List<Annotation>> from, List<List<Annotation>> to) {
    if (from.isEmpty) return;
    to.add(_items);
    _items = from.removeLast();
    notifyListeners();
  }
}
