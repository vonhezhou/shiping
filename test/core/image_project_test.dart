import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fruler/core/core.dart';

void main() {
  ImageProject project() => ImageProject(
    name: '测试.png',
    png: File('test/fixtures/workspace.png').readAsBytesSync(),
    width: 240,
    height: 160,
    annotations: [
      {
        'id': 4,
        'rect': {'left': 10, 'top': 20, 'right': 100, 'bottom': 80},
        'label': '不可信标签',
      },
    ],
    tool: 'rectangle',
    view: const ImageProjectView(scale: 2.5, x: -30, y: 80, pan: true),
  );
  test('项目独立包含图片、标注、工具及视图，标签从可信坐标重建', () {
    final restored = ImageProject.decode(project().encode());
    expect(restored.png, project().png);
    expect(restored.name, '测试.png');
    expect(restored.annotations.single['label'], '90 × 60 px');
    expect(restored.view!.toJson(), {
      'scale': 2.5,
      'x': -30.0,
      'y': 80.0,
      'pan': true,
    });
    expect(restored.tool, 'rectangle');
    expect(jsonDecode(project().encode())['image'].containsKey('path'), false);
  });
  test('损坏、未来版本、非法工具、重复编号及越界均整份拒绝', () {
    for (final change in <void Function(Map)>[
      (v) => v['version'] = 2,
      (v) => v['format'] = 'other',
      (v) => v['tool'] = 'unknown',
      (v) => v['zoom'] = 12.0,
      (v) => v['image']['png'] = 'bad',
      (v) => v['image']['width'] = 20000,
      (v) => v['annotations'].add(v['annotations'][0]),
      (v) => v['annotations'][0]['rect']['right'] = 999,
      (v) => v['annotations'][0]['rect']['left'] = -1,
      (v) => v['view']['scale'] = 0,
      (v) => v['view']['x'] = 1e9,
    ]) {
      final data = jsonDecode(project().encode()) as Map;
      change(data);
      expect(
        () => ImageProject.decode(jsonEncode(data)),
        throwsFormatException,
      );
    }
    expect(
      () => ImageProjectView.fromJson({
        'scale': double.nan,
        'x': 0,
        'y': 0,
        'pan': false,
      }),
      throwsFormatException,
    );
  });
}
