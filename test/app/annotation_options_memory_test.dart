import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fruler/app/app_controller.dart';
import 'package:fruler/core/core.dart';

import '../fake_desktop.dart';

void main() {
  test('各组标注选项和子工具通过序列化恢复，保持逻辑点且不写入历史', () async {
    final desktop = FakeDesktop();
    addTearDown(desktop.input.close);
    final c = AppController(desktop);
    addTearDown(c.dispose);
    await c.initialize();
    final expected = <String, Map<String, Object>>{};
    var index = 0;
    for (final tool in [
      'ellipse',
      'line',
      'pencil',
      'marker',
      'blur',
      'eraser',
      'text',
    ]) {
      final options = AnnotationOptions(
        width: 5.0 + index++,
        fontSize: 36,
        fontFamily: 'Menlo',
        filled: true,
        bold: true,
        italic: true,
        outlined: true,
        effectBrush: true,
        eraserBrush: true,
        effectStrength: 5,
      );
      c.setAnnotationOptions(tool, options);
      c.rememberAnnotationTool(tool);
      expected[tool] = options.toJson();
    }
    final restartedDesktop = FakeDesktop()..saved = desktop.saved;
    addTearDown(restartedDesktop.input.close);
    final restarted = AppController(restartedDesktop);
    addTearDown(restarted.dispose);
    await restarted.initialize();
    for (final entry in expected.entries) {
      expect(
        restarted.annotationOptions(entry.key).toJson(),
        entry.value,
        reason: entry.key,
      );
    }
    expect(
      restarted.annotationOptions('rectangle').toJson(),
      expected['ellipse'],
    );
    expect(restarted.annotationTool('shape'), 'ellipse');
    expect(restarted.annotationTool('line'), 'line');
    expect(restarted.annotationTool('effect'), 'blur');
    expect(restarted.markup.items, isEmpty);
    expect(restarted.markup.canUndo, false);
  });

  test('损坏字段单独回退，旧配置保留工具默认值和有效选项', () async {
    final desktop = FakeDesktop()
      ..saved = jsonEncode({
        'annotationOptions': {
          'shape': {
            'width': 0,
            'filled': true,
            'fontSize': 201,
            'fontFamily': '',
          },
          'marker': {'width': 'wide'},
          'effect': {'width': 33, 'effectStrength': 6, 'effectBrush': 'true'},
          'text': {'fontFamily': 'Menlo', 'italic': true, 'bold': 1},
          'unknown': {'width': 40},
        },
        'annotationTools': {'shape': 'text', 'line': 1, 'effect': 'blur'},
        'annotationColors': {'text': 0xFF123456},
      });
    addTearDown(desktop.input.close);
    final c = AppController(desktop);
    addTearDown(c.dispose);
    await c.initialize();
    expect(c.annotationOptions('rectangle').width, 3);
    expect(c.annotationOptions('ellipse').filled, true);
    expect(c.annotationOptions('marker').width, 12);
    expect(c.annotationOptions('mosaic').width, 33);
    expect(c.annotationOptions('mosaic').effectStrength, 3);
    expect(c.annotationOptions('mosaic').effectBrush, false);
    expect(c.annotationOptions('eraser').width, 24);
    expect(c.annotationOptions('text').fontFamily, 'Menlo');
    expect(c.annotationOptions('text').italic, true);
    expect(c.annotationOptions('text').bold, false);
    expect(c.annotationColor('text'), 0xFF123456);
    expect(c.annotationTool('shape'), 'rectangle');
    expect(c.annotationTool('line'), 'arrow');
    expect(c.annotationTool('effect'), 'blur');
  });
}
