import 'dart:convert';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:fruler/core/core.dart';

void main() {
  test('橡皮擦序列化保存模式和路径，不作为可选中标注', () {
    for (final brush in [false, true]) {
      final a = Annotation(
        kind: AnnotationKind.eraser,
        points: [
          const Offset(10, 10),
          if (brush) const Offset(30, 20),
          const Offset(80, 80),
        ],
        width: 24,
        effectBrush: brush,
      );
      final decoded = Annotation.decodeList(
        jsonDecode(jsonEncode([a.toJson()])),
        100,
        100,
      ).single;
      expect(decoded.toJson(), a.toJson());
      expect(decoded.isPath, brush);
      expect(decoded.hitTest(const Offset(30, 20), 6), false);
      expect(
        () => Annotation.decodeList([a.toJson()..['width'] = 0], 100, 100),
        throwsFormatException,
      );
      expect(
        () => Annotation.decodeList(
          [
            a.toJson()
              ..['points'] = [
                [-1, 0],
                [10, 20],
              ],
          ],
          100,
          100,
        ),
        throwsFormatException,
      );
    }
  });
  test('旧形状按原始边缘命中，空白内部不抢占新的绘制', () {
    final rectangle = Annotation(
      kind: AnnotationKind.rectangle,
      points: const [Offset(20, 20), Offset(120, 80)],
      width: 4,
    );
    expect(rectangle.hitTest(const Offset(60, 20), 3, edgeOnly: true), true);
    expect(rectangle.hitTest(const Offset(60, 24), 3, edgeOnly: true), true);
    expect(rectangle.hitTest(const Offset(60, 50), 3, edgeOnly: true), false);
    expect(rectangle.hitTest(const Offset(60, 50), 3), true);
    expect(rectangle.hitTest(const Offset(60, 10), 3, edgeOnly: true), false);
    final ellipse = Annotation(
      kind: AnnotationKind.ellipse,
      points: rectangle.points,
      width: 4,
    );
    expect(ellipse.hitTest(const Offset(70, 20), 3, edgeOnly: true), true);
    expect(ellipse.hitTest(const Offset(120, 50), 3, edgeOnly: true), true);
    expect(ellipse.hitTest(const Offset(70, 50), 3, edgeOnly: true), false);
    expect(ellipse.hitTest(const Offset(20, 20), 3, edgeOnly: true), false);
  });

  test('擦除后移动缩放的是完整对象，保留擦除位置、顺序和历史', () {
    for (final kind in AnnotationKind.values.where(
      (k) => k != AnnotationKind.eraser,
    )) {
      final a = Annotation(
        kind: kind,
        points: const [Offset(20, 20), Offset(60, 60)],
        text: '文字',
      );
      final eraser = Annotation(
        kind: AnnotationKind.eraser,
        points: const [Offset(35, 10), Offset(45, 30)],
      );
      final history = AnnotationHistory()..reset([a, eraser]);
      final moved = a.move(const Offset(0, 30), const Size(120, 120));
      history.commit([moved, eraser]);
      expect(history.items.length, 2);
      expect(history.items.last, same(eraser));
      expect(moved.points.length, a.points.length);
      expect(a.bounds, const Rect.fromLTRB(20, 20, 60, 60));
      history.commit([
        moved.resize(const Rect.fromLTRB(10, 40, 90, 100)),
        eraser,
      ]);
      final decoded = Annotation.decodeList(
        jsonDecode(jsonEncode(history.items.map((a) => a.toJson()).toList())),
        120,
        120,
      );
      expect(decoded.last.toJson(), eraser.toJson());
      expect(decoded.first.points.length, 2);
      history.undo();
      expect(history.items, [moved, eraser]);
      history.undo();
      expect(history.items, [a, eraser]);
      history.redo();
      expect(history.items, [moved, eraser]);
    }
  });
  for (final ratio in [1.0, 2.0, 3.0]) {
    test('文字缩放的字号上下限按 pt ${ratio}x', () {
      final a = Annotation(
        kind: AnnotationKind.text,
        points: const [Offset(0, 0), Offset(100, 100)],
        fontSize: 24 * ratio,
        text: 'text',
      );
      expect(
        a.resize(const Rect.fromLTWH(0, 0, 1, 1), fontScale: ratio).fontSize,
        8 * ratio,
      );
      expect(
        a
            .resize(const Rect.fromLTWH(0, 0, 10000, 10000), fontScale: ratio)
            .fontSize,
        200 * ratio,
      );
    });
  }

  test('效果笔刷路径、强度和旧数据兼容，命中与框擦沿笔迹检测', () {
    final json = Annotation(
      kind: AnnotationKind.mosaic,
      points: const [Offset(10, 10), Offset(90, 90)],
      width: 12,
    ).toJson()..addAll({'effectBrush': true, 'effectStrength': 5});
    final a = Annotation.decodeList([json], 100, 100).single;
    expect(a.toJson(), json);
    expect(a.hitTest(const Offset(10, 80), 1), false);
    expect(a.intersects(const Rect.fromLTRB(10, 70, 20, 80)), false);
    expect(a.hitTest(const Offset(50, 50), 1), true);
    expect(
      a
          .move(const Offset(0, 5), const Size(100, 100))
          .toJson()['effectStrength'],
      5,
    );
    final legacy = Map.of(json)
      ..remove('effectBrush')
      ..remove('effectStrength');
    expect(
      Annotation.decodeList([legacy], 100, 100).single.toJson()['effectBrush'],
      false,
    );
    expect(
      Annotation.decodeList(
        [legacy],
        100,
        100,
      ).single.toJson()['effectStrength'],
      3,
    );
    for (final value in [0, 6, 2.5, '3']) {
      expect(
        () => Annotation.decodeList(
          [Map.of(json)..['effectStrength'] = value],
          100,
          100,
        ),
        throwsFormatException,
      );
    }
    final path = Map.of(json)
      ..['points'] = [
        [10, 10],
        [50, 10],
        [90, 90],
      ];
    expect(Annotation.decodeList([path], 100, 100).single.points, hasLength(3));
  });
  Annotation arrow() => Annotation(
    kind: AnnotationKind.arrow,
    points: const [Offset(10, 20), Offset(70, 80)],
  );
  test('标注移动限制在图内；缩放变换所有端点；线段精确命中', () {
    final a = arrow();
    expect(
      a.move(const Offset(-100, 200), const Size(100, 100)).bounds,
      const Rect.fromLTRB(0, 40, 60, 100),
    );
    expect(a.resize(const Rect.fromLTRB(0, 0, 120, 120)).points, [
      Offset.zero,
      const Offset(120, 120),
    ]);
    expect(a.hitTest(const Offset(40, 50), 2), true);
    expect(a.hitTest(const Offset(10, 70), 2), false);
  });
  test('框选擦除精确检测线段、箭头尖、粗线和小标注', () {
    final line = Annotation(
      kind: AnnotationKind.line,
      points: const [Offset(10, 10), Offset(90, 90)],
      width: 2,
    );
    expect(line.intersects(const Rect.fromLTRB(40, 40, 45, 45)), true);
    expect(line.intersects(const Rect.fromLTRB(10, 70, 20, 80)), false);
    final horizontal = line.copyWith(
      points: const [Offset(10, 10), Offset(90, 10)],
      width: 12,
    );
    expect(horizontal.intersects(const Rect.fromLTRB(40, 15, 45, 20)), true);
    expect(horizontal.intersects(const Rect.fromLTRB(40, 20, 45, 25)), false);
    final a = Annotation(
      kind: AnnotationKind.arrow,
      points: const [Offset(10, 50), Offset(90, 50)],
      width: 3,
    );
    expect(a.intersects(const Rect.fromLTRB(79, 54, 82, 56)), true);
    for (final kind in [
      AnnotationKind.text,
      AnnotationKind.mosaic,
      AnnotationKind.blur,
      AnnotationKind.rectangle,
      AnnotationKind.ellipse,
    ]) {
      final small = Annotation(
        kind: kind,
        points: const [Offset(20, 20), Offset(22, 22)],
      );
      expect(small.intersects(const Rect.fromLTRB(19, 19, 23, 23)), true);
      expect(small.intersects(const Rect.fromLTRB(40, 40, 50, 50)), false);
    }
  });
  test('形状填充、字体样式兼容旧标注，折线可包含多个顶点', () {
    final legacy = arrow().toJson()
      ..remove('filled')
      ..remove('bold')
      ..remove('italic');
    final old = Annotation.decodeList([legacy], 100, 100).single;
    expect(old.toJson()['filled'], false);
    final styled = Map<String, Object>.of(legacy)
      ..['filled'] = true
      ..['bold'] = true
      ..['italic'] = true;
    expect(Annotation.decodeList([styled], 100, 100).single.toJson(), styled);
    final polyline = Map<String, Object>.of(legacy)
      ..['kind'] = 'line'
      ..['points'] = [
        [10, 10],
        [30, 20],
        [60, 10],
      ];
    final decoded = Annotation.decodeList([polyline], 100, 100).single;
    expect(decoded.hitTest(const Offset(30, 20), 1), true);
    expect(decoded.points, hasLength(3));
    expect(
      () => Annotation.decodeList([Map.of(styled)..['bold'] = 'yes'], 100, 100),
      throwsFormatException,
    );
  });
  test('Shift 约束正方形和 45 度线，且不越过图像边界', () {
    expect(
      constrainedAnnotationEnd(
        AnnotationKind.rectangle,
        const Offset(90, 90),
        const Offset(100, 95),
        const Size(100, 100),
        shift: true,
      ),
      const Offset(100, 100),
    );
    expect(
      constrainedAnnotationEnd(
        AnnotationKind.ellipse,
        const Offset(30, 30),
        const Offset(5, 20),
        const Size(100, 100),
        shift: true,
      ),
      const Offset(5, 5),
    );
    final line = constrainedAnnotationEnd(
      AnnotationKind.arrow,
      const Offset(10, 10),
      const Offset(50, 15),
      const Size(100, 100),
      shift: true,
    );
    expect(line.dy, closeTo(10, .0001));
    expect(
      constrainedAnnotationEnd(
        AnnotationKind.pencil,
        Offset.zero,
        const Offset(30, 10),
        const Size(100, 100),
        shift: true,
      ),
      const Offset(30, 10),
    );
  });
  test('撤销恢复删除和样式，重做被新编辑截断', () {
    final history = AnnotationHistory();
    addTearDown(history.dispose);
    final a = arrow();
    history.commit([a]);
    history.commit([a.copyWith(color: 0xFF000000)]);
    history.commit([]);
    history.undo();
    expect(history.items.single.color, 0xFF000000);
    history.undo();
    expect(history.items.single.color, 0xFFFF5252);
    history.redo();
    expect(history.items.single.color, 0xFF000000);
    history.commit([a]);
    expect(history.canRedo, false);
    expect(() => history.items.clear(), throwsUnsupportedError);
  });
  test('未知类型、非数坐标、越界、空文字和无效样式整份拒绝', () {
    for (final change in <void Function(Map)>[
      (v) => v['kind'] = 'unknown',
      (v) => v['points'][0][0] = -1,
      (v) => v['points'][0][0] = 1000,
      (v) => v['points'][0][0] = double.nan,
      (v) => v['width'] = 0,
      (v) => v['fontSize'] = 1000,
      (v) => v['color'] = -1,
      (v) {
        v['kind'] = 'text';
        v['text'] = '';
      },
      (v) => v['points'].add([20, 30]),
    ]) {
      final value = jsonDecode(jsonEncode(arrow().toJson())) as Map;
      change(value);
      expect(
        () => Annotation.decodeList([value], 100, 100),
        throwsFormatException,
      );
    }
  });
  test('新增截图快捷键迁移时保留旧取色与测量组合', () {
    final picker = const ShortcutChord(key: 'X', meta: true, shift: true);
    final restored = ShortcutBindings.fromJson({
      'picker': picker.toJson(),
      'ruler': ShortcutBindings.defaults.ruler.toJson(),
    });
    expect(restored.picker, picker);
    expect(restored.screenshot, isNot(picker));
    expect(restored.isValid, true);
  });
}
