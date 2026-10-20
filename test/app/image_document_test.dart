import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:fruler/core/core.dart';
import 'package:fruler/platform/image_document.dart';
import 'package:fruler/platform/pixel_frame_image.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('原始截图裁剪保留尺寸方向颜色且不修改冻结快照', () async {
    final bytes = Uint8List.fromList([
      for (var y = 0; y < 3; y++)
        for (var x = 0; x < 4; x++) ...[x * 40, y * 60, 30, 255],
    ]);
    final before = Uint8List.fromList(bytes);
    final source = PixelFrame(
      width: 4,
      height: 3,
      rgba: bytes,
      logicalWidth: 2,
      logicalHeight: 1.5,
    );
    final doc = await ImageDocumentCodec().cropCapture(
      source,
      const PixelRect(left: 1, top: 1, right: 4, bottom: 3),
    );
    expect((doc.frame.width, doc.frame.height), (3, 2));
    expect(doc.frame.pixelAt(0, 0), const RgbColor(40, 60, 30));
    expect(doc.frame.pixelAt(2, 1), const RgbColor(120, 120, 30));
    final image = await pixelFrameToImage(doc.frame);
    try {
      final data = (await image.toByteData())!;
      expect(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        orderedEquals(doc.frame.rgba),
      );
    } finally {
      image.dispose();
    }
    doc.frame.rgba[0] = 0;
    expect(source.rgba, orderedEquals(before));
  });
  test('截图裁剪延续透明像素铺白底并在分配前检查边界和尺寸限制', () async {
    final codec = ImageDocumentCodec();
    final source = PixelFrame(
      width: 16385,
      height: 1,
      rgba: Uint8List(16385 * 4),
      logicalWidth: 16385,
      logicalHeight: 1,
    );
    source.rgba.setRange(0, 4, [64, 0, 0, 128]);
    final doc = await codec.cropCapture(
      source,
      const PixelRect(left: 0, top: 0, right: 2, bottom: 1),
    );
    expect(doc.frame.rgba, [191, 127, 127, 255, 255, 255, 255, 255]);
    for (final rect in [
      const PixelRect(left: -1, top: 0, right: 1, bottom: 1),
      const PixelRect(left: 0, top: 0, right: 16386, bottom: 1),
      const PixelRect(left: 0, top: 0, right: 1, bottom: 2),
      const PixelRect(left: 1, top: 0, right: 1, bottom: 1),
    ]) {
      await expectLater(codec.cropCapture(source, rect), throwsArgumentError);
    }
    await expectLater(
      codec.cropCapture(
        source,
        const PixelRect(left: 0, top: 0, right: 16385, bottom: 1),
      ),
      throwsFormatException,
    );
  });
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
