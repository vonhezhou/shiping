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
  test('文字描边在 PNG 中保留对比色边缘和原文字填充', () async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawColor(const ui.Color(0xFF223344), ui.BlendMode.src);
    final picture = recorder.endRecording();
    final base = await picture.toImage(100, 100);
    picture.dispose();
    final frame = await rawFrame(base);
    base.dispose();
    final text = Annotation(
      kind: AnnotationKind.text,
      points: const [ui.Offset(10, 10), ui.Offset(90, 90)],
      text: 'M',
      color: 0xFF000000,
      fontSize: 40,
    );
    for (final outlined in [false, true]) {
      final png = await AnnotationRenderer.export(frame, [
        text.copyWith(outlined: outlined),
      ]);
      final codec = await ui.instantiateImageCodec(png);
      final image = (await codec.getNextFrame()).image;
      final pixels = (await rawFrame(image)).rgba;
      var white = 0, black = 0;
      for (var i = 0; i < pixels.length; i += 4) {
        if (pixels[i] == 255 && pixels[i + 1] == 255 && pixels[i + 2] == 255) {
          white++;
        }
        if (pixels[i] == 0 && pixels[i + 1] == 0 && pixels[i + 2] == 0) black++;
      }
      expect(white, outlined ? greaterThan(0) : 0);
      expect(black, greaterThan(0));
      image.dispose();
      codec.dispose();
    }
  });
  test('局部橡皮擦只清除先前标注，保留原图、剩余笔迹和后续绘制', () async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawColor(const ui.Color(0xFF13579B), ui.BlendMode.src);
    final picture = recorder.endRecording();
    final base = await picture.toImage(100, 100);
    picture.dispose();
    addTearDown(base.dispose);
    final frame = await rawFrame(base);
    for (final brush in [false, true]) {
      final eraser = Annotation.decodeList(
        [
          Annotation(
            kind: AnnotationKind.rectangle,
            points: const [ui.Offset(45, 20), ui.Offset(55, 80)],
            width: 10,
            effectBrush: brush,
          ).toJson()..['kind'] = 'eraser',
        ],
        100,
        100,
      ).single;
      final stroke = Annotation(
        kind: AnnotationKind.line,
        points: const [ui.Offset(10, 50), ui.Offset(90, 50)],
        color: 0xFFFF0000,
        width: 8,
      );
      final history = AnnotationHistory()..reset([stroke]);
      history.commit([stroke, eraser]);
      expect(history.items.first, same(stroke));
      history.undo();
      expect(history.items, [stroke]);
      history.redo();
      expect(history.items.last.toJson(), eraser.toJson());
      final png = await AnnotationRenderer.export(frame, history.items);
      final codec = await ui.instantiateImageCodec(png);
      final output = (await codec.getNextFrame()).image;
      final pixels = await rawFrame(output);
      List<int> pixel(int x, int y) =>
          pixels.rgba.sublist((y * 100 + x) * 4, (y * 100 + x) * 4 + 4);
      expect(pixel(50, 50), [19, 87, 155, 255]);
      expect(pixel(20, 50), [255, 0, 0, 255]);
      expect(pixel(80, 50), [255, 0, 0, 255]);
      expect(pixel(50, 10), [19, 87, 155, 255]);
      output.dispose();
      codec.dispose();
      final later = await AnnotationRenderer.export(frame, [
        ...history.items,
        stroke.copyWith(color: 0xFF00FF00),
      ]);
      final laterCodec = await ui.instantiateImageCodec(later);
      final laterImage = (await laterCodec.getNextFrame()).image;
      final laterPixels = await rawFrame(laterImage);
      expect(laterPixels.rgba.sublist(20200, 20204), [0, 255, 0, 255]);
      laterImage.dispose();
      laterCodec.dispose();
    }
  });
  test('完整矩形移出擦除区域恢复笔迹，移入后重新被擦除，后画内容不受影响', () async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawColor(const ui.Color(0xFF13579B), ui.BlendMode.src);
    final picture = recorder.endRecording();
    final base = await picture.toImage(160, 160);
    picture.dispose();
    addTearDown(base.dispose);
    final frame = await rawFrame(base);
    final a = Annotation(
      kind: AnnotationKind.rectangle,
      points: const [ui.Offset(20, 30), ui.Offset(120, 90)],
      width: 4,
      color: 0xFFFF0000,
    );
    for (final brush in [false, true]) {
      final eraser = Annotation(
        kind: AnnotationKind.eraser,
        points: const [ui.Offset(50, 20), ui.Offset(80, 40)],
        width: 24,
        effectBrush: brush,
      );
      final moved = a.move(const ui.Offset(0, 50), const ui.Size(160, 160));
      final resized = moved.resize(const ui.Rect.fromLTRB(20, 30, 140, 140));
      final later = Annotation(
        kind: AnnotationKind.line,
        points: const [ui.Offset(40, 30), ui.Offset(90, 30)],
        color: 0xFF00FF00,
        width: 4,
      );
      Future<List<int>> pixel(List<Annotation> items, int x, int y) async {
        final codec = await ui.instantiateImageCodec(
          await AnnotationRenderer.export(frame, items),
        );
        final output = (await codec.getNextFrame()).image;
        final pixels = await rawFrame(output);
        final result = pixels.rgba.sublist(
          (y * 160 + x) * 4,
          (y * 160 + x) * 4 + 4,
        );
        output.dispose();
        codec.dispose();
        return result;
      }

      expect(await pixel([a, eraser], 65, 30), [19, 87, 155, 255]);
      expect(await pixel([moved, eraser], 65, 80), [255, 0, 0, 255]);
      expect(await pixel([moved, eraser], 65, 30), [19, 87, 155, 255]);
      expect(await pixel([resized, eraser], 65, 30), [19, 87, 155, 255]);
      expect(await pixel([resized, eraser], 30, 30), [255, 0, 0, 255]);
      expect(await pixel([resized, eraser, later], 65, 30), [0, 255, 0, 255]);
      expect(eraser.points, const [ui.Offset(50, 20), ui.Offset(80, 40)]);
    }
  });
  test('笔刷单点、连续路径和矩形擦除适用于所有标注，预览导出一致', () async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    for (var x = 0; x < 100; x++) {
      canvas.drawRect(
        ui.Rect.fromLTWH(x.toDouble(), 0, 1, 100),
        ui.Paint()..color = ui.Color.fromARGB(255, x * 2, 80, 160),
      );
    }
    final picture = recorder.endRecording();
    final base = await picture.toImage(100, 100);
    picture.dispose();
    addTearDown(base.dispose);
    final frame = await rawFrame(base);
    final mosaics = await AnnotationRenderer.prepareMosaics(base);
    addTearDown(() {
      for (final m in mosaics.values) {
        m.dispose();
      }
    });
    for (final kind in AnnotationKind.values.where(
      (k) => k != AnnotationKind.eraser,
    )) {
      final a = Annotation(
        kind: kind,
        points: const [ui.Offset(10, 10), ui.Offset(90, 90)],
        filled: true,
        text: '测试',
        width: 20,
      );
      for (final eraser in [
        Annotation(
          kind: AnnotationKind.eraser,
          points: const [ui.Offset(50, 50), ui.Offset(50, 50)],
          effectBrush: true,
          width: 24,
        ),
        Annotation(
          kind: AnnotationKind.eraser,
          points: const [
            ui.Offset(20, 20),
            ui.Offset(50, 50),
            ui.Offset(80, 80),
          ],
          effectBrush: true,
          width: 24,
        ),
        Annotation(
          kind: AnnotationKind.eraser,
          points: const [ui.Offset(60, 60), ui.Offset(40, 40)],
        ),
      ]) {
        final items = [a, eraser];
        final previewRecorder = ui.PictureRecorder();
        AnnotationRenderer.paint(
          ui.Canvas(previewRecorder),
          base,
          mosaics,
          items,
        );
        final pp = previewRecorder.endRecording();
        final preview = await pp.toImage(100, 100);
        pp.dispose();
        final codec = await ui.instantiateImageCodec(
          await AnnotationRenderer.export(frame, items),
        );
        final output = (await codec.getNextFrame()).image;
        final actual = await rawFrame(output);
        expect(actual.rgba, orderedEquals((await rawFrame(preview)).rgba));
        expect(
          actual.rgba.sublist(20200, 20204),
          frame.rgba.sublist(20200, 20204),
        );
        output.dispose();
        codec.dispose();
        preview.dispose();
      }
    }
    // A diagonal brush must preserve pixels in empty corners of its bounds.
    final fill = Annotation(
      kind: AnnotationKind.rectangle,
      points: const [ui.Offset(0, 0), ui.Offset(100, 100)],
      filled: true,
    );
    final codec = await ui.instantiateImageCodec(
      await AnnotationRenderer.export(frame, [
        fill,
        Annotation(
          kind: AnnotationKind.eraser,
          points: const [ui.Offset(10, 10), ui.Offset(90, 90)],
          width: 10,
          effectBrush: true,
        ),
      ]),
    );
    final output = (await codec.getNextFrame()).image;
    final actual = await rawFrame(output);
    expect(actual.rgba.sublist(32080, 32084), [255, 82, 82, 255]);
    expect(frame.rgba, orderedEquals((await rawFrame(base)).rgba));
    output.dispose();
    codec.dispose();
  });
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
