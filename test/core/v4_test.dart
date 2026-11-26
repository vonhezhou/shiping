import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fruler/core/core.dart';

void main() {
  test('Shift 四角缩放保留比例、固定对角并限制在屏幕内', () {
    const rect = PixelRect(left: 100, top: 100, right: 300, bottom: 200);
    for (final handle in ['nw', 'ne', 'sw', 'se']) {
      final west = handle.contains('w'), north = handle.contains('n');
      final next = transformAnnotation(
        rect,
        west ? -40 : 40,
        north ? -5 : 5,
        640,
        480,
        handle: handle,
        keepAspectRatio: true,
      );
      expect(next.width, 240);
      expect(next.height, 120);
      expect(west ? next.right : next.left, west ? rect.right : rect.left);
      expect(north ? next.bottom : next.top, north ? rect.bottom : rect.top);
      final bounded = transformAnnotation(
        rect,
        west ? -999 : 999,
        north ? -999 : 999,
        640,
        480,
        handle: handle,
        keepAspectRatio: true,
      );
      expect(bounded.width / bounded.height, closeTo(2, .01));
      expect(bounded.left, greaterThanOrEqualTo(0));
      expect(bounded.top, greaterThanOrEqualTo(0));
      expect(bounded.right, lessThanOrEqualTo(640));
      expect(bounded.bottom, lessThanOrEqualTo(480));
    }
    expect(
      transformAnnotation(
        rect,
        40,
        5,
        640,
        480,
        handle: 'e',
        keepAspectRatio: true,
      ).height,
      100,
    );
    final shrink = transformAnnotation(
      rect,
      -999,
      -999,
      640,
      480,
      handle: 'se',
      keepAspectRatio: true,
    );
    expect(shrink.width, 2);
    expect(shrink.height, 1);
  });

  test('WCAG 已知基准、前背景对称及阈值不舍入', () {
    final bw = ColorContrast(
      const RgbColor(0, 0, 0),
      const RgbColor(255, 255, 255),
    );
    expect(bw.ratio, 21);
    expect(bw.normalAAA, true);
    final same = ColorContrast(
      const RgbColor(2, 90, 200),
      const RgbColor(2, 90, 200),
    );
    expect(same.ratio, 1);
    expect(same.largeAA, false);
    final gray = ColorContrast(
      const RgbColor(119, 119, 119),
      const RgbColor(255, 255, 255),
    );
    expect(gray.ratio, closeTo(4.478, .001));
    expect(gray.normalAA, false);
    expect(gray.largeAA, true);
    expect(gray.largeAAA, false);
    expect(ColorContrast(gray.background, gray.foreground).ratio, gray.ratio);
    expect(
      ColorContrast(const RgbColor(118, 118, 118), gray.background).normalAA,
      true,
    );
  });
  test('移动整体夹紧，四角缩放和最小一像素', () {
    const rect = PixelRect(left: 2, top: 3, right: 6, bottom: 7);
    expect(transformAnnotation(rect, -99, 99, 10, 10).toJson(), {
      'left': 0,
      'top': 6,
      'right': 4,
      'bottom': 10,
    });
    expect(transformAnnotation(rect, 99, 99, 10, 10, handle: 'nw').toJson(), {
      'left': 5,
      'top': 6,
      'right': 6,
      'bottom': 7,
    });
    expect(transformAnnotation(rect, -99, -99, 10, 10, handle: 'se').toJson(), {
      'left': 2,
      'top': 3,
      'right': 3,
      'bottom': 4,
    });
    expect(transformAnnotation(rect, 99, -99, 10, 10, handle: 'ne').toJson(), {
      'left': 2,
      'top': 0,
      'right': 10,
      'bottom': 7,
    });
    expect(transformAnnotation(rect, -99, 99, 10, 10, handle: 'sw').toJson(), {
      'left': 0,
      'top': 3,
      'right': 6,
      'bottom': 10,
    });
    expect(transformAnnotation(rect, 1, 1, 10, 10, handle: 'e').height, 4);
  });
  test('调色板导出导入往返，整份拒绝无效、重复与未来版本', () {
    const entries = [
      PaletteEntry(color: RgbColor(1, 2, 3), name: '品牌', favorite: true),
    ];
    final text = exportPalette(entries, PaletteExport.json);
    final restored = importPalette(text).single;
    expect(restored.name, '品牌');
    expect(restored.favorite, true);
    expect(restored.color, entries.single.color);
    final data = jsonDecode(text) as Map<String, dynamic>;
    data['colors'].add({
      'name': '坏数据',
      'rgb': [999, 0, 0],
      'hex': '#FF0000',
      'favorite': false,
    });
    expect(() => importPalette(jsonEncode(data)), throwsFormatException);
    expect(
      () => importPalette(text.replaceFirst('"version": 1', '"version": 2')),
      throwsFormatException,
    );
    expect(
      () => importPalette(
        exportPalette([...entries, ...entries], PaletteExport.json),
      ),
      throwsFormatException,
    );
    expect(
      () => importPalette(text.replaceFirst('#010203', '#FFFFFF')),
      throwsFormatException,
    );
  });
  test('合并颜色冲突规则、同名不同色保留且生成代码不能注入', () {
    const old = PaletteEntry(
      color: RgbColor(1, 2, 3),
      name: '同名',
      favorite: true,
    );
    const incoming = [
      PaletteEntry(color: RgbColor(1, 2, 3), name: '新名'),
      PaletteEntry(color: RgbColor(4, 5, 6), name: '同名'),
    ];
    final keep = mergePalette([old], incoming, PaletteMerge.keepExisting);
    expect(keep.length, 2);
    expect(keep.first.favorite, true);
    expect(keep.first.name, '同名');
    final replace = mergePalette([old], incoming, PaletteMerge.useImported);
    expect(replace.first.name, '新名');
    expect(replace.first.favorite, false);
    expect(copyPalette(keep, flutter: true), contains('Color(0xFF010203)'));
    expect(copyPalette(keep, flutter: false), contains('--shiping-2: #040506;'));
  });
}
