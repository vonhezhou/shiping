import 'dart:convert';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:fruler/core/core.dart';

void main() {
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
