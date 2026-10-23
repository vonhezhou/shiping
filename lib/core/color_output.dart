import 'dart:math' as math;

import 'color_value.dart';
import 'validation_exception.dart';

/// A bounded, plain-text template. No expressions, file access or evaluation.
class ColorOutput {
  const ColorOutput({
    required this.id,
    required this.name,
    required this.template,
    this.enabled = true,
  });
  final String id, name, template;
  final bool enabled;
  static const defaults = [
    ColorOutput(id: 'hex', name: 'HEX', template: '#%ReX%GrX%BlX'),
    ColorOutput(id: 'rgb', name: 'RGB', template: 'rgb(%Re, %Gr, %Bl)'),
    ColorOutput(id: 'hsl', name: 'HSL', template: 'hsl(%Hu, %Sl%, %Ll%)'),
    ColorOutput(
      id: 'flutter',
      name: 'Flutter',
      template: 'Color(0xFF%ReX%GrX%BlX)',
    ),
    ColorOutput(id: 'css', name: 'CSS', template: 'color: #%ReX%GrX%BlX;'),
  ];
  ColorOutput copyWith({String? name, String? template, bool? enabled}) =>
      ColorOutput(
        id: id,
        name: name ?? this.name,
        template: template ?? this.template,
        enabled: enabled ?? this.enabled,
      );
  Map<String, Object> toJson() => {
    'id': id,
    'name': name,
    'template': template,
    'enabled': enabled,
  };
  factory ColorOutput.fromJson(Object? value) {
    if (value is! Map ||
        value['id'] is! String ||
        value['name'] is! String ||
        value['template'] is! String ||
        value['enabled'] is! bool) {
      throw const ValidationException('outputInvalid');
    }
    final result = ColorOutput(
      id: value['id'] as String,
      name: value['name'] as String,
      template: value['template'] as String,
      enabled: value['enabled'] as bool,
    );
    result.validate();
    return result;
  }
  void validate() {
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,80}$').hasMatch(id) ||
        name.trim().isEmpty ||
        name.length > 40) {
      throw const ValidationException('outputName');
    }
    render(const RgbColor(13, 127, 255));
  }

  String render(RgbColor color) {
    if (template.trim().isEmpty ||
        template.length > 1024 ||
        template.contains(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'))) {
      throw const ValidationException('outputTemplate');
    }
    final out = StringBuffer();
    final hsl = color.hslValues;
    final maximum = math.max(color.r, math.max(color.g, color.b));
    final minimum = math.min(color.r, math.min(color.g, color.b));
    final channels = {'Re': color.r, 'Gr': color.g, 'Bl': color.b, 'Al': 255};
    final values = <String, num>{
      'Hu': hsl.h.round() % 360,
      'Sl': (hsl.s * 100).round(),
      'Ll': (hsl.l * 100).round(),
      'Sb': maximum == 0 ? 0 : ((maximum - minimum) / maximum * 100).round(),
      'Va': (maximum / 255 * 100).round(),
      'Br': (maximum / 255 * 100).round(),
      'Dr': color.r * 65536 + color.g * 256 + color.b,
      'Dv': color.b * 65536 + color.g * 256 + color.r,
    };
    var substitutions = 0;
    for (var i = 0; i < template.length;) {
      if (template[i] != '%') {
        out.write(template[i++]);
        continue;
      }
      if (i + 1 < template.length && template[i + 1] == '%') {
        out.write('%');
        i += 2;
        continue;
      }
      final token = i + 3 <= template.length
          ? template.substring(i + 1, i + 3)
          : '';
      if (channels.containsKey(token)) {
        i += 3;
        var modifier = 'b';
        if (i < template.length && 'bhHxXfF'.contains(template[i])) {
          modifier = template[i++];
        }
        final value = channels[token]!;
        final hex = (modifier == 'h' || modifier == 'H' ? value ~/ 16 : value)
            .toRadixString(16);
        out.write(switch (modifier) {
          'h' => hex,
          'H' => hex.toUpperCase(),
          'x' => hex.padLeft(2, '0'),
          'X' => hex.padLeft(2, '0').toUpperCase(),
          'f' || 'F' => _fraction(value / 255, leadingZero: modifier == 'f'),
          _ => value.toString(),
        });
        substitutions++;
      } else if (values.containsKey(token)) {
        out.write(values[token]);
        i += 3;
        substitutions++;
      } else if (i + 1 == template.length ||
          !RegExp(r'[A-Za-z]').hasMatch(template[i + 1])) {
        out.write('%');
        i++;
      } else {
        throw ValidationException('outputPlaceholder', {'token': token});
      }
    }
    if (substitutions == 0) {
      throw const ValidationException('outputSubstitution');
    }
    return out.toString();
  }

  static String _fraction(double value, {required bool leadingZero}) {
    var text = value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
    if (text.isEmpty) text = '0';
    if (!leadingZero && text.startsWith('0.')) text = text.substring(1);
    return text;
  }
}

enum PickerActivation { picker, editor }

enum PickerMouseAction { pickAndClose, pickAndEdit, pickAndContinue, cancel }

class PickerBehavior {
  const PickerBehavior({
    this.activation = PickerActivation.picker,
    this.primary = PickerMouseAction.pickAndClose,
    this.middle = PickerMouseAction.pickAndClose,
    this.secondary = PickerMouseAction.cancel,
  });
  final PickerActivation activation;
  final PickerMouseAction primary, middle, secondary;
  PickerMouseAction forButton(String button) => switch (button) {
    'middle' => middle,
    'secondary' => secondary,
    _ => primary,
  };
  PickerBehavior copyWith({
    PickerActivation? activation,
    PickerMouseAction? primary,
    PickerMouseAction? middle,
    PickerMouseAction? secondary,
  }) => PickerBehavior(
    activation: activation ?? this.activation,
    primary: primary ?? this.primary,
    middle: middle ?? this.middle,
    secondary: secondary ?? this.secondary,
  );
  Map<String, String> toJson() => {
    'activation': activation.name,
    'primary': primary.name,
    'middle': middle.name,
    'secondary': secondary.name,
  };
  factory PickerBehavior.fromJson(Object? value) {
    if (value is! Map) throw const ValidationException('pickerBehavior');
    return PickerBehavior(
      activation: PickerActivation.values.byName(value['activation'] as String),
      primary: PickerMouseAction.values.byName(value['primary'] as String),
      middle: PickerMouseAction.values.byName(value['middle'] as String),
      secondary: PickerMouseAction.values.byName(value['secondary'] as String),
    );
  }
}
