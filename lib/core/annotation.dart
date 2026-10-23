import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'validation_exception.dart';

enum AnnotationKind {
  rectangle,
  ellipse,
  line,
  arrow,
  pencil,
  marker,
  text,
  mosaic,
  blur,
  eraser,
}

/// Immutable, image-pixel coordinates shared by preview, export and documents.
class Annotation {
  Annotation({
    required this.kind,
    required List<Offset> points,
    this.color = 0xFFFF5252,
    this.width = 3,
    this.fontSize = 24,
    this.fontFamily = defaultFontFamily,
    this.text = '',
    this.filled = false,
    this.bold = false,
    this.italic = false,
    this.outlined = false,
    this.effectBrush = false,
    this.effectStrength = 3,
  }) : points = List.unmodifiable(points);
  final AnnotationKind kind;
  final List<Offset> points;
  final int color;
  final double width, fontSize;
  static const defaultFontFamily = 'PingFang SC';
  final String text, fontFamily;
  final bool filled, bold, italic, outlined;
  final bool effectBrush;

  /// 1–5: mosaic block size or Gaussian blur radius, independent of brush width.
  final int effectStrength;
  bool get isEffect =>
      kind == AnnotationKind.mosaic || kind == AnnotationKind.blur;
  bool get isPath =>
      effectBrush && (isEffect || kind == AnnotationKind.eraser) ||
      [
        AnnotationKind.line,
        AnnotationKind.arrow,
        AnnotationKind.pencil,
        AnnotationKind.marker,
      ].contains(kind);

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
    String? fontFamily,
    bool? filled,
    bool? bold,
    bool? italic,
    bool? outlined,
    bool? effectBrush,
    int? effectStrength,
  }) => Annotation(
    kind: kind,
    points: points ?? this.points,
    color: color ?? this.color,
    width: width ?? this.width,
    fontSize: fontSize ?? this.fontSize,
    text: text ?? this.text,
    fontFamily: fontFamily ?? this.fontFamily,
    filled: filled ?? this.filled,
    bold: bold ?? this.bold,
    italic: italic ?? this.italic,
    outlined: outlined ?? this.outlined,
    effectBrush: effectBrush ?? this.effectBrush,
    effectStrength: effectStrength ?? this.effectStrength,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Annotation &&
          kind == other.kind &&
          listEquals(points, other.points) &&
          color == other.color &&
          width == other.width &&
          fontSize == other.fontSize &&
          text == other.text &&
          fontFamily == other.fontFamily &&
          filled == other.filled &&
          bold == other.bold &&
          italic == other.italic &&
          outlined == other.outlined &&
          effectBrush == other.effectBrush &&
          effectStrength == other.effectStrength;

  @override
  int get hashCode => Object.hash(
    kind,
    Object.hashAll(points),
    color,
    width,
    fontSize,
    fontFamily,
    text,
    filled,
    bold,
    italic,
    outlined,
    effectBrush,
    effectStrength,
  );

  Annotation move(Offset delta, Size size, {Offset origin = Offset.zero}) {
    final b = bounds;
    final d = Offset(
      delta.dx.clamp(-origin.dx - b.left, size.width - origin.dx - b.right),
      delta.dy.clamp(-origin.dy - b.top, size.height - origin.dy - b.bottom),
    );
    return copyWith(points: points.map((p) => p + d).toList());
  }

  Annotation resize(Rect next, {double fontScale = 1}) {
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
          ? (fontSize * math.min(sx, sy)).clamp(8 * fontScale, 200 * fontScale)
          : fontSize,
    );
  }

  /// Edge picking lets a drawing tool edit old shapes without capturing their
  /// empty interiors. Erasure is a separate operation, never a split or mask
  /// attached to this object's geometry.
  bool hitTest(Offset p, double tolerance, {bool edgeOnly = false}) {
    if (kind == AnnotationKind.eraser) return false;
    if (!bounds.inflate(tolerance + width / 2).contains(p)) return false;
    if (edgeOnly && !isPath) {
      final b = bounds, radius = tolerance + width / 2;
      if (kind == AnnotationKind.ellipse) {
        bool inside(Rect r) {
          if (r.isEmpty) return false;
          final x = (p.dx - r.center.dx) / (r.width / 2);
          final y = (p.dy - r.center.dy) / (r.height / 2);
          return x * x + y * y <= 1;
        }

        return inside(b.inflate(radius)) && !inside(b.deflate(radius));
      }
      if (kind != AnnotationKind.text) {
        return b.inflate(radius).contains(p) && !b.deflate(radius).contains(p);
      }
    }
    if (isPath) {
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

    if (isPath) {
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
    'fontFamily': fontFamily,
    'text': text,
    'filled': filled,
    'bold': bold,
    'italic': italic,
    'outlined': outlined,
    'effectBrush': effectBrush,
    'effectStrength': effectStrength,
  };

  static List<Annotation> decodeList(Object? value, int width, int height) {
    if (value == null) return [];
    if (value is! List || value.length > 4096) {
      throw const ValidationException('annotationCount');
    }
    var totalPoints = 0;
    return value.map((v) {
      if (v is! Map) throw const ValidationException('annotationInvalid');
      final kind = AnnotationKind.values
          .where((k) => k.name == v['kind'])
          .firstOrNull;
      final raw = v['points'], color = v['color'], stroke = v['width'];
      final font = v['fontSize'], text = v['text'];
      final family = v['fontFamily'] ?? defaultFontFamily;
      final effectBrush = v['effectBrush'] ?? false;
      final strength = v['effectStrength'] ?? 3;
      final outlined = v['outlined'] ?? false;
      final filled = v['filled'] ?? false,
          bold = v['bold'] ?? false,
          italic = v['italic'] ?? false;
      if (outlined is! bool ||
          effectBrush is! bool ||
          strength is! int ||
          strength < 1 ||
          strength > 5 ||
          filled is! bool ||
          bold is! bool ||
          italic is! bool ||
          kind == null ||
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
          family is! String ||
          family.trim().isEmpty ||
          family.length > 256 ||
          text is! String ||
          text.length > 4096 ||
          (kind == AnnotationKind.text && text.trim().isEmpty)) {
        throw const ValidationException('annotationStyle');
      }
      totalPoints += raw.length;
      if (totalPoints > 200000) {
        throw const ValidationException('annotationPoints');
      }
      final points = raw.map((p) {
        if (p is! List || p.length != 2 || p[0] is! num || p[1] is! num) {
          throw const ValidationException('annotationCoordinates');
        }
        final x = (p[0] as num).toDouble(), y = (p[1] as num).toDouble();
        if (!x.isFinite ||
            !y.isFinite ||
            x < 0 ||
            y < 0 ||
            x > width ||
            y > height) {
          throw const ValidationException('annotationBounds');
        }
        return Offset(x, y);
      }).toList();
      if (kind != AnnotationKind.pencil &&
          kind != AnnotationKind.marker &&
          kind != AnnotationKind.line &&
          !(effectBrush &&
              (kind == AnnotationKind.mosaic ||
                  kind == AnnotationKind.blur ||
                  kind == AnnotationKind.eraser)) &&
          points.length != 2) {
        throw const ValidationException('annotationEndpoints');
      }
      return Annotation(
        kind: kind,
        points: points,
        color: color,
        width: stroke.toDouble(),
        fontSize: font.toDouble(),
        text: text,
        fontFamily: family,
        filled: filled,
        bold: bold,
        italic: italic,
        outlined: outlined,
        effectBrush: effectBrush,
        effectStrength: strength,
      );
    }).toList();
  }
}

/// Shift constrains shape proportions or snaps lines to 45-degree increments.
Offset constrainedAnnotationEnd(
  AnnotationKind kind,
  Offset start,
  Offset end,
  Size size, {
  bool shift = false,
}) {
  if (!shift) return end;
  final delta = end - start;
  if ([AnnotationKind.rectangle, AnnotationKind.ellipse].contains(kind)) {
    final sx = delta.dx < 0 ? -1.0 : 1.0, sy = delta.dy < 0 ? -1.0 : 1.0;
    final distance = math.min(
      math.max(delta.dx.abs(), delta.dy.abs()),
      math.min(
        sx > 0 ? size.width - start.dx : start.dx,
        sy > 0 ? size.height - start.dy : start.dy,
      ),
    );
    return start + Offset(sx * distance, sy * distance);
  }
  if ([AnnotationKind.line, AnnotationKind.arrow].contains(kind)) {
    final angle =
        (math.atan2(delta.dy, delta.dx) / (math.pi / 4)).round() *
        (math.pi / 4);
    final dx = math.cos(angle), dy = math.sin(angle);
    var length = delta.distance;
    if (dx.abs() > 1e-9) {
      length = math.min(
        length,
        (dx > 0 ? size.width - start.dx : start.dx) / dx.abs(),
      );
    }
    if (dy.abs() > 1e-9) {
      length = math.min(
        length,
        (dy > 0 ? size.height - start.dy : start.dy) / dy.abs(),
      );
    }
    return start + Offset(dx, dy) * length;
  }
  return end;
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

  /// 选区原点变化时同步平移所有历史，不产生撤销步骤，也不丢弃重做。
  void translate(Offset delta) {
    if (delta == Offset.zero) return;
    List<Annotation> shift(List<Annotation> items) => List.unmodifiable(
      items.map(
        (a) => a.copyWith(points: a.points.map((p) => p + delta).toList()),
      ),
    );
    _items = shift(_items);
    for (final stack in [_undo, _redo]) {
      for (var i = 0; i < stack.length; i++) {
        stack[i] = shift(stack[i]);
      }
    }
  }

  void commit(List<Annotation> items) {
    if (listEquals(items, _items)) return;
    if (items.length > 4096 ||
        items.fold<int>(0, (n, a) => n + a.points.length) > 200000) {
      throw const ValidationException('annotationLimit');
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
