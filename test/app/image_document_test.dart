import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:fruler/core/core.dart';
import 'package:fruler/platform/image_document.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('图片解码保留原始分辨率、方向与颜色；透明区域铺白底', () async {
    final codec = ImageDocumentCodec();
    final doc = await codec.decode(
      ImageFileData(
        'fixture.png',
        File('test/fixtures/workspace.png').readAsBytesSync(),
      ),
    );
    expect(doc.frame.width, 240);
    expect(doc.frame.height, 160);
    expect(doc.frame.pixelAt(10, 10), const RgbColor(255, 0, 0));
    expect(doc.frame.pixelAt(140, 10), const RgbColor(0, 0, 255));
    expect(doc.frame.pixelAt(10, 120), const RgbColor(0, 255, 0));
    expect(doc.frame.pixelAt(140, 120), const RgbColor(255, 255, 255));
    final output = await codec.renderAnnotations(doc, [
      {
        'id': 1,
        'rect': {'left': 20, 'top': 40, 'right': 80, 'bottom': 120},
        'label': '60 × 80 px',
      },
    ]);
    final decoder = await ui.instantiateImageCodec(output);
    final image = (await decoder.getNextFrame()).image;
    expect(image.width, lessThanOrEqualTo(240));
    expect(image.height, lessThanOrEqualTo(160));
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    expect(data, isNotNull);
    final i = (50 * image.width + 30) * 4;
    expect(data!.buffer.asUint8List().sublist(i, i + 3), [255, 0, 0]);
    image.dispose();
    decoder.dispose();
  });
  test('损坏或不支持的文件不进入工作区', () async {
    final codec = ImageDocumentCodec();
    await expectLater(
      codec.decode(ImageFileData('bad.png', Uint8List.fromList([1, 2, 3]))),
      throwsFormatException,
    );
    await expectLater(
      codec.decode(ImageFileData('huge.png', Uint8List(32 * 1024 * 1024 + 1))),
      throwsFormatException,
    );
  });
}
