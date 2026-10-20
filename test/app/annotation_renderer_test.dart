import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:fruler/core/core.dart';
import 'package:fruler/platform/annotation_renderer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('填充形状和多段折线真正写入导出像素，不依赖 UI 预览', () async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawColor(const ui.Color(0xFF000000), ui.BlendMode.src);
    final picture = recorder.endRecording();
    final base = await picture.toImage(96, 96);
    picture.dispose();
    final png = (await base.toByteData(format: ui.ImageByteFormat.png))!.buffer
        .asUint8List();
    base.dispose();
    for (final kind in [AnnotationKind.rectangle, AnnotationKind.ellipse]) {
      final bytes = await AnnotationRenderer.export(png, [
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
    final png = (await original.toByteData(format: ui.ImageByteFormat.png))!
        .buffer
        .asUint8List();
    final before = (await original.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!.buffer.asUint8List();
    original.dispose();
    for (final kind in [AnnotationKind.mosaic, AnnotationKind.blur]) {
      final output = await AnnotationRenderer.export(png, [
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
