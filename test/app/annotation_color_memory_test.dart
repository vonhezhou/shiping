import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fruler/app/app_controller.dart';

import '../fake_desktop.dart';

void main() {
  test('各工具独立保存 ARGB，重新加载恢复且不写入标注历史', () async {
    final d = FakeDesktop();
    addTearDown(d.input.close);
    final c = AppController(d);
    addTearDown(c.dispose);
    await c.initialize();
    c.setAnnotationColor('rectangle', 0x80123456);
    c.setAnnotationColor('ellipse', 0xFFABCDEF);
    c.setAnnotationColor('pencil', 0xFF234567);
    expect(c.markup.items, isEmpty);
    expect(c.markup.canUndo, false);
    final saved = jsonDecode(d.saved!) as Map;
    expect(saved['annotationColors'], {
      'rectangle': 0x80123456,
      'ellipse': 0xFFABCDEF,
      'pencil': 0xFF234567,
    });
    final restored = AppController(d);
    addTearDown(restored.dispose);
    await restored.initialize();
    expect(restored.annotationColor('rectangle'), 0x80123456);
    expect(restored.annotationColor('ellipse'), 0xFFABCDEF);
    expect(restored.annotationColor('pencil'), 0xFF234567);
    expect(restored.annotationColor('arrow'), 0xFFFF0000);
  });

  test('旧数据使用默认色，损坏或未知工具颜色不影响有效数据', () async {
    final d = FakeDesktop()
      ..saved = jsonEncode({
        'annotationColors': {
          'text': 0xFF123456,
          'pencil': -1,
          'ellipse': 0x100000000,
          'marker': 'red',
          'other': 42,
        },
      });
    addTearDown(d.input.close);
    final c = AppController(d);
    addTearDown(c.dispose);
    await c.initialize();
    expect(c.annotationColor('text'), 0xFF123456);
    for (final tool in ['pencil', 'ellipse', 'marker', 'rectangle']) {
      expect(c.annotationColor(tool), 0xFFFF0000);
    }
    final before = d.saved;
    c.setAnnotationColor('other', 0xFF123456);
    c.setAnnotationColor('text', -1);
    c.setAnnotationColor('text', 0x100000000);
    c.setAnnotationColor('text', 0xFF123456);
    expect(d.saved, before);
  });
}
