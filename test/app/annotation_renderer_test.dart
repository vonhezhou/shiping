import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:fruler/core/core.dart';
import 'package:fruler/platform/annotation_renderer.dart';

Future<PixelFrame> rawFrame(ui.Image image) async {
  final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  return PixelFrame(
    width: image.width,
    height: image.height,
    logicalWidth: image.width.toDouble(),
    logicalHeight: image.height.toDouble(),
    rgba: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('原始像素导出保留无标注画面，边缘标注预览与输出一致', () async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawColor(const ui.Color(0xFF13579B), ui.BlendMode.src);
    final picture = recorder.endRecording();
    final base = await picture.toImage(40, 30);
    picture.dispose();
    addTearDown(base.dispose);
    final frame = await rawFrame(base);
    final mosaics = await AnnotationRenderer.prepareMosaics(base);
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
            points: const [ui.Offset(0, 0), ui.Offset(40, 30)],
            text: '边缘',
            color: 0xFFFF0000,
          ),
        ],
    ]) {
      final png = await AnnotationRenderer.export(frame, items);
      final codec = await ui.instantiateImageCodec(png);
      final output = (await codec.getNextFrame()).image;
      codec.dispose();
      final previewRecorder = ui.PictureRecorder();
      AnnotationRenderer.paint(
        ui.Canvas(previewRecorder),
        base,
        mosaics,
        items,
      );
      final previewPicture = previewRecorder.endRecording();
      final preview = await previewPicture.toImage(40, 30);
      previewPicture.dispose();
      try {
        expect((output.width, output.height), (40, 30));
        final actual = await rawFrame(output);
        expect(actual.rgba, orderedEquals((await rawFrame(preview)).rgba));
        if (items.isEmpty) expect(actual.rgba, orderedEquals(frame.rgba));
      } finally {
        preview.dispose();
        output.dispose();
      }
    }
  });
  test('效果强度改变像素，笔刷保留空白角落、支持单点，预览与导出一致', () async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawColor(const ui.Color(0xFF000000), ui.BlendMode.src);
    for (var x = 0; x < 96; x += 10) {
      canvas.drawRect(
        ui.Rect.fromLTWH(x.toDouble(), 0, 5, 96),
        ui.Paint()..color = const ui.Color(0xFFFFFFFF),
      );
    }
    final picture = recorder.endRecording();
    final base = await picture.toImage(96, 96);
    picture.dispose();
    final frame = await rawFrame(base);
    final before = (await base.toByteData())!.buffer.asUint8List();
    addTearDown(base.dispose);
    final mosaics = await AnnotationRenderer.prepareMosaics(base);
    addTearDown(() {
      for (final image in mosaics.values) {
        image.dispose();
      }
    });
    for (final kind in [AnnotationKind.mosaic, AnnotationKind.blur]) {
      final outputs = <List<int>>[];
      for (final strength in [1, 5]) {
        final a = Annotation.decodeList(
          [
            Annotation(
                kind: kind,
                points: const [ui.Offset(20, 20), ui.Offset(70, 70)],
                width: 16,
              ).toJson()
              ..addAll({'effectBrush': true, 'effectStrength': strength}),
          ],
          96,
          96,
        ).single;
        final codec = await ui.instantiateImageCodec(
          await AnnotationRenderer.export(frame, [a]),
        );
        final image = (await codec.getNextFrame()).image;
        final pixels = (await image.toByteData())!.buffer.asUint8List();
        final previewRecorder = ui.PictureRecorder();
        AnnotationRenderer.paint(ui.Canvas(previewRecorder), base, mosaics, [
          a,
        ]);
        final previewPicture = previewRecorder.endRecording();
        final preview = await previewPicture.toImage(96, 96);
        expect(
          (await preview.toByteData())!.buffer.asUint8List(),
          orderedEquals(pixels),
        );
        preview.dispose();
        previewPicture.dispose();
        outputs.add(pixels.toList());
        final untouched = (65 * 96 + 25) * 4;
        expect(
          pixels.sublist(untouched, untouched + 4),
          before.sublist(untouched, untouched + 4),
        );
        expect(pixels, isNot(orderedEquals(before)));
        image.dispose();
        codec.dispose();
      }
      expect(outputs.first, isNot(orderedEquals(outputs.last)));
      final dot = Annotation.decodeList(
        [
          Annotation(
            kind: kind,
            points: const [ui.Offset(40, 40), ui.Offset(40, 40)],
            width: 24,
          ).toJson()..['effectBrush'] = true,
        ],
        96,
        96,
      ).single;
      final codec = await ui.instantiateImageCodec(
        await AnnotationRenderer.export(frame, [dot]),
      );
      final image = (await codec.getNextFrame()).image;
      expect(
        (await image.toByteData())!.buffer.asUint8List(),
        isNot(orderedEquals(before)),
      );
      image.dispose();
      codec.dispose();
    }
  });
  test('填充形状和多段折线真正写入导出像素，不依赖 UI 预览', () async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawColor(const ui.Color(0xFF000000), ui.BlendMode.src);
    final picture = recorder.endRecording();
    final base = await picture.toImage(96, 96);
    picture.dispose();
    final frame = await rawFrame(base);
    base.dispose();
    for (final kind in [AnnotationKind.rectangle, AnnotationKind.ellipse]) {
      final bytes = await AnnotationRenderer.export(frame, [
        Annotation(
          kind: kind,
          points: const [ui.Offset(10, 10), ui.Offset(40, 40)],
          color: 0xFF00FF00,
          filled: true,
        ),
        Annotation(
          kind: AnnotationKind.line,
          points: const [
            ui.Offset(50, 10),
            ui.Offset(80, 50),
            ui.Offset(50, 80),
          ],
          color: 0xFFFFFFFF,
        ),
      ]);
      final codec = await ui.instantiateImageCodec(bytes);
      final image = (await codec.getNextFrame()).image;
      codec.dispose();
      final pixels = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();
      expect(pixels.sublist((25 * 96 + 25) * 4, (25 * 96 + 25) * 4 + 4), [
        0,
        255,
        0,
        255,
      ]);
      expect(pixels[(50 * 96 + 80) * 4], greaterThan(200));
      expect(pixels[(90 * 96 + 90) * 4], 0);
      image.dispose();
    }
  });
  test('马赛克与模糊写入导出像素，保持选区外像素和原图尺寸', () async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawColor(const ui.Color(0xFF000000), ui.BlendMode.src);
    for (var x = 0; x < 96; x += 2) {
      canvas.drawRect(
        ui.Rect.fromLTWH(x.toDouble(), 0, 1, 96),
        ui.Paint()..color = const ui.Color(0xFFFFFFFF),
      );
    }
    final picture = recorder.endRecording();
    final original = await picture.toImage(96, 96);
    picture.dispose();
    final frame = await rawFrame(original);
    final before = (await original.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!.buffer.asUint8List();
    original.dispose();
    for (final kind in [AnnotationKind.mosaic, AnnotationKind.blur]) {
      final output = await AnnotationRenderer.export(frame, [
        Annotation(
          kind: kind,
          points: const [ui.Offset(24, 24), ui.Offset(72, 72)],
        ),
      ]);
      final codec = await ui.instantiateImageCodec(output);
      final image = (await codec.getNextFrame()).image;
      try {
        expect((image.width, image.height), (96, 96));
        final pixels = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!.buffer.asUint8List();
        expect(pixels[(48 * 96 + 48) * 4], isNot(before[(48 * 96 + 48) * 4]));
        expect(
          pixels.sublist((10 * 96 + 10) * 4, (10 * 96 + 10) * 4 + 4),
          before.sublist((10 * 96 + 10) * 4, (10 * 96 + 10) * 4 + 4),
        );
      } finally {
        image.dispose();
        codec.dispose();
      }
    }
  });
}
