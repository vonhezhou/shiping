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
