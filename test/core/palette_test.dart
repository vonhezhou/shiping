import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fruler/core/core.dart';

void main() {
  test('HEX 输入规范化且明确拒绝损坏和透明格式', () {
    expect(RgbColor.parseHex(' #a0F ').hex, '#AA00FF');
    expect(RgbColor.parseHex('010fff'), const RgbColor(1, 15, 255));
    for (final value in ['', '#12', '#11223344', 'GGFFFF', 'rgb(0,0,0)']) {
      expect(() => RgbColor.parseHex(value), throwsFormatException);
    }
  });
  test('HSL 转换覆盖灰度、跨周色相和 RGB 往返', () {
    expect(RgbColor.fromHsl(360, 1, .5), const RgbColor(255, 0, 0));
    expect(RgbColor.fromHsl(-120, 1, .5), const RgbColor(0, 0, 255));
    expect(RgbColor.fromHsl(180, 0, .5), const RgbColor(128, 128, 128));
    for (final color in [
      const RgbColor(215, 250, 107),
      const RgbColor(1, 15, 255),
      const RgbColor(0, 0, 0),
      const RgbColor(255, 255, 255),
    ]) {
      final hsl = color.hslValues;
      expect(RgbColor.fromHsl(hsl.h, hsl.s, hsl.l), color);
    }
    expect(() => RgbColor.fromHsl(double.nan, 0, .5), throwsFormatException);
    expect(() => RgbColor.fromHsl(0, 2, .5), throwsFormatException);
  });
  test('开发代码格式保留前导零与不透明 alpha', () {
    const color = RgbColor(1, 15, 255);
    expect(color.formatted(ColorFormat.flutter), 'Color(0xFF010FFF)');
    expect(color.formatted(ColorFormat.css), 'color: #010FFF;');
  });
  test('JSON 导出保留名称与收藏，CSS 名称不可注入内容且唯一', () {
    const entries = [
      PaletteEntry(
        color: RgbColor(1, 15, 255),
        name: '中文"\n}; body {',
        favorite: true,
      ),
      PaletteEntry(color: RgbColor(0, 0, 0), name: '重复'),
    ];
    final json = jsonDecode(exportPalette(entries, PaletteExport.json));
    expect(json['colors'][0]['name'], entries.first.name);
    expect(json['colors'][0]['favorite'], true);
    expect(json['colors'][0]['hex'], '#010FFF');
    expect(
      exportPalette(entries, PaletteExport.css),
      ':root {\n  --fruler-1: #010FFF;\n  --fruler-2: #000000;\n}\n',
    );
    expect(
      PaletteEntry.fromJson(entries.first.toJson()).color,
      entries.first.color,
    );
    expect(() => PaletteEntry.fromJson({'name': 99}), throwsFormatException);
  });
}
