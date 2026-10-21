import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:fruler/core/core.dart';
import 'package:fruler/platform/pixel_frame_image.dart';
import 'package:fruler/platform/annotation_renderer.dart';

Future<Uint8List> pixels(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  try {
    final image = (await codec.getNextFrame()).image;
    try {
      final data = (await image.toByteData())!;
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } finally {
      image.dispose();
    }
  } finally {
    codec.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('不同选区复用原图上传，清理缓存不会使已取得的图片失效', () async {
    final frame = PixelFrame(
      width: 3,
      height: 2,
      rowBytes: 16,
      rgba: Uint8List.fromList([
        255,
        0,
        0,
        255,
        0,
        255,
        0,
        255,
        0,
        0,
        255,
        255,
        91,
        91,
        91,
        91,
        255,
        255,
        255,
        255,
        0,
        0,
        0,
        255,
        255,
        255,
        0,
        255,
        92,
        92,
        92,
        92,
      ]),
      logicalWidth: 3,
      logicalHeight: 2,
    );
    final cache = PixelImageCache();
    addTearDown(cache.clear);
    final first = await cache.load(
      frame.view(left: 0, top: 0, width: 1, height: 2),
    );
    final second = await cache.load(
      frame.view(left: 1, top: 0, width: 2, height: 2),
    );
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    expect(first.isCloneOf(second), true);
    expect((first.width, first.height), (3, 2));
    cache.clear();
    expect(await first.toByteData(), isNotNull);
    final third = await cache.load(frame);
    addTearDown(third.dispose);
    expect(first.isCloneOf(third), false);
    final pending = PixelImageCache();
    final lateImage = pending.load(frame);
    pending.clear();
    await expectLater(lateImage, throwsStateError);
  });

  test('共享选区的预览与导出等同紧密图片，效果不读取选区外颜色', () async {
    final bytes = Uint8List(512 * 100);
    for (var y = 0; y < 100; y++) {
      for (var x = 0; x < 120; x++) {
        final inside = x >= 17 && x < 82 && y >= 13 && y < 62;
        bytes.setRange(
          y * 512 + x * 4,
          y * 512 + x * 4 + 4,
          inside
              ? [x * 3 % 256, y * 7 % 256, (x + y) % 2 * 255, 255]
              : [255, 0, 0, 255],
        );
      }
    }
    final root = PixelFrame(
      width: 120,
      height: 100,
      rowBytes: 512,
      rgba: bytes,
      logicalWidth: 120,
      logicalHeight: 100,
    );
    final view = root.view(left: 17, top: 13, width: 65, height: 49);
    final packed = Uint8List(65 * 49 * 4);
    for (var y = 0; y < 49; y++) {
      packed.setRange(y * 260, (y + 1) * 260, bytes, view.byteIndex(0, y));
    }
    final reference = PixelFrame(
      width: 65,
      height: 49,
      rgba: packed,
      logicalWidth: 65,
      logicalHeight: 49,
    );
    final source = await pixelFrameToImage(view);
    addTearDown(source.dispose);
    final rect = pixelFrameSourceRect(view);
    final mosaics = await AnnotationRenderer.prepareMosaics(
      source,
      sourceRect: rect,
    );
    addTearDown(() {
      for (final image in mosaics.values) {
        image.dispose();
      }
    });
    for (final items in [
      <Annotation>[],
      for (final kind in AnnotationKind.values)
        [
          Annotation(
            kind: kind,
            text: '边界',
            width: 5,
            points: const [ui.Offset.zero, ui.Offset(65, 49)],
          ),
        ],
      for (final kind in [AnnotationKind.mosaic, AnnotationKind.blur])
        [
          Annotation(
            kind: kind,
            effectBrush: true,
            effectStrength: 5,
            width: 20,
            points: const [ui.Offset.zero, ui.Offset(65, 49)],
          ),
        ],
    ]) {
      final actual = await pixels(await AnnotationRenderer.export(view, items));
      final expected = await pixels(
        await AnnotationRenderer.export(reference, items),
      );
      expect(
        actual,
        orderedEquals(expected),
        reason: '${items.firstOrNull?.kind}',
      );
      final recorder = ui.PictureRecorder();
      AnnotationRenderer.paint(
        ui.Canvas(recorder),
        source,
        mosaics,
        items,
        sourceRect: rect,
      );
      final picture = recorder.endRecording();
      final preview = await picture.toImage(65, 49);
      picture.dispose();
      try {
        final raw = (await preview.toByteData())!;
        expect(raw.buffer.asUint8List(), orderedEquals(actual));
      } finally {
        preview.dispose();
      }
    }
  });

  test('共享透明像素在渲染时铺白底，不修改原始缓冲', () async {
    final frame = PixelFrame(
      width: 2,
      height: 1,
      rgba: Uint8List.fromList([64, 0, 0, 128, 0, 0, 0, 0]),
      logicalWidth: 2,
      logicalHeight: 1,
    );
    final output = await pixels(await AnnotationRenderer.export(frame, []));
    expect(output, [191, 127, 127, 255, 255, 255, 255, 255]);
    expect(frame.rgba, [64, 0, 0, 128, 0, 0, 0, 0]);
  });
}
