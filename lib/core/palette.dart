import 'dart:convert';

import 'color_value.dart';
import 'validation_exception.dart';

class PaletteEntry {
  const PaletteEntry({
    required this.color,
    this.name = '',
    this.favorite = false,
    this.group = '',
  });
  final RgbColor color;
  final String name;
  final bool favorite;
  final String group;
  PaletteEntry copyWith({String? name, bool? favorite, String? group}) =>
      PaletteEntry(
        color: color,
        name: name ?? this.name,
        favorite: favorite ?? this.favorite,
        group: group ?? this.group,
      );

  Map<String, Object> toJson() => {
    'color': color.toJson(),
    'name': name,
    'favorite': favorite,
    'group': group,
  };
  factory PaletteEntry.fromJson(Object? value) {
    if (value is! Map ||
        value['name'] is! String ||
        value['favorite'] is! bool) {
      throw const ValidationException('paletteEntry');
    }
    return PaletteEntry(
      color: RgbColor.fromJson(value['color']),
      name: (value['name'] as String).trim(),
      favorite: value['favorite'] as bool,
      group: value['group'] is String ? (value['group'] as String).trim() : '',
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
              'group': e.group,
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
    throw const ValidationException('paletteVersion');
  }
  final colors = data['colors'] as List;
  if (colors.length > 4096) throw const ValidationException('paletteLimit');
  final entries = <PaletteEntry>[];
  for (final item in colors) {
    if (item is! Map ||
        item['name'] is! String ||
        item['favorite'] is! bool ||
        (item['name'] as String).length > 200 ||
        (item['group'] != null &&
            (item['group'] is! String ||
                (item['group'] as String).trim().length > 60))) {
      throw const ValidationException('paletteMetadata');
    }
    final color = RgbColor.fromJson(item['rgb']);
    if (RgbColor.parseHex(item['hex'] is String ? item['hex'] as String : '') !=
        color) {
      throw const ValidationException('paletteChannels');
    }
    if (entries.any((e) => e.color == color)) {
      throw const ValidationException('paletteDuplicates');
    }
    entries.add(
      PaletteEntry(
        color: color,
        name: (item['name'] as String).trim(),
        favorite: item['favorite'] as bool,
        group: (item['group'] as String? ?? '').trim(),
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
