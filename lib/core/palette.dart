import 'dart:convert';

import 'color_value.dart';

class PaletteEntry {
  const PaletteEntry({
    required this.color,
    this.name = '',
    this.favorite = false,
  });
  final RgbColor color;
  final String name;
  final bool favorite;
  Map<String, Object> toJson() => {
    'color': color.toJson(),
    'name': name,
    'favorite': favorite,
  };
  factory PaletteEntry.fromJson(Object? value) {
    if (value is! Map ||
        value['name'] is! String ||
        value['favorite'] is! bool) {
      throw const FormatException('Invalid palette entry');
    }
    return PaletteEntry(
      color: RgbColor.fromJson(value['color']),
      name: (value['name'] as String).trim(),
      favorite: value['favorite'] as bool,
    );
  }
}

enum PaletteExport { json, css }

String exportPalette(List<PaletteEntry> entries, PaletteExport format) {
  if (format == PaletteExport.json) {
    return const JsonEncoder.withIndent('  ').convert({
      'version': 1,
      'colors': entries
          .map(
            (e) => {
              'name': e.name,
              'hex': e.color.hex,
              'rgb': e.color.toJson(),
              'favorite': e.favorite,
            },
          )
          .toList(),
    });
  }
  // Names stay in JSON; numeric CSS identifiers avoid injection and duplicate names.
  return ':root {\n${[for (var i = 0; i < entries.length; i++) '  --fruler-${i + 1}: ${entries[i].color.hex};'].join('\n')}\n}\n';
}

/// Strictly validate the whole file before showing a merge preview.
List<PaletteEntry> importPalette(String text) {
  final data = jsonDecode(text);
  if (data is! Map || data['version'] != 1 || data['colors'] is! List) {
    throw const FormatException('请选择 fruler 导出的 version 1 JSON 文件');
  }
  final colors = data['colors'] as List;
  if (colors.length > 4096) throw const FormatException('一次最多导入 4096 个颜色');
  final entries = <PaletteEntry>[];
  for (final item in colors) {
    if (item is! Map ||
        item['name'] is! String ||
        item['favorite'] is! bool ||
        (item['name'] as String).length > 200) {
      throw const FormatException('颜色条目的名称或收藏状态无效');
    }
    final color = RgbColor.fromJson(item['rgb']);
    if (RgbColor.parseHex(item['hex'] is String ? item['hex'] as String : '') !=
        color) {
      throw const FormatException('HEX 与 RGB 不一致，未导入任何颜色');
    }
    if (entries.any((e) => e.color == color)) {
      throw const FormatException('文件含重复颜色，请先去重');
    }
    entries.add(
      PaletteEntry(
        color: color,
        name: (item['name'] as String).trim(),
        favorite: item['favorite'] as bool,
      ),
    );
  }
  return entries;
}

enum PaletteMerge { keepExisting, useImported }

List<PaletteEntry> mergePalette(
  List<PaletteEntry> current,
  List<PaletteEntry> incoming,
  PaletteMerge policy,
) {
  final result = List<PaletteEntry>.of(current);
  for (final entry in incoming) {
    final index = result.indexWhere((e) => e.color == entry.color);
    if (index < 0) {
      result.add(entry);
    } else if (policy == PaletteMerge.useImported) {
      result[index] = entry;
    }
  }
  return result;
}

String copyPalette(List<PaletteEntry> entries, {required bool flutter}) =>
    flutter
    ? '<Color>[\n${entries.map((e) => '  ${e.color.formatted(ColorFormat.flutter)},').join('\n')}\n]'
    : exportPalette(entries, PaletteExport.css);
