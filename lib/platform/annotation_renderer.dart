import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../core/annotation.dart';
import '../core/pixel_frame.dart';
import 'pixel_frame_image.dart';

/// One renderer for both the editable preview and flattened PNG output.
class AnnotationRenderer {
  static const fontFamily = 'PingFang SC';
  static void paint(
    ui.Canvas canvas,
    ui.Image image,
    Map<int, ui.Image> mosaics,
    List<Annotation> items,
  ) {
    final full = ui.Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    canvas.save();
    canvas.clipRect(full);
    canvas.drawImage(image, ui.Offset.zero, ui.Paint());
    for (final a in items) {
      final b = a.bounds;
      final paint = ui.Paint()
        ..color = ui.Color(a.color)
        ..strokeWidth = a.width
        ..style = ui.PaintingStyle.stroke
        ..strokeCap = ui.StrokeCap.round
        ..strokeJoin = ui.StrokeJoin.round;
      switch (a.kind) {
        case AnnotationKind.rectangle:
          paint.style = a.filled
              ? ui.PaintingStyle.fill
              : ui.PaintingStyle.stroke;
          canvas.drawRect(b, paint);
        case AnnotationKind.ellipse:
          paint.style = a.filled
              ? ui.PaintingStyle.fill
              : ui.PaintingStyle.stroke;
          canvas.drawOval(b, paint);
        case AnnotationKind.line:
          final path = ui.Path()..moveTo(a.points.first.dx, a.points.first.dy);
          for (final p in a.points.skip(1)) {
            path.lineTo(p.dx, p.dy);
          }
          canvas.drawPath(path, paint);
        case AnnotationKind.arrow:
          final start = a.points.first, end = a.points.last;
          canvas.drawLine(start, end, paint);
          final angle = math.atan2(end.dy - start.dy, end.dx - start.dx);
          final length = math.max(10.0, a.width * 4);
          final path = ui.Path()
            ..moveTo(
              end.dx - length * math.cos(angle - .45),
              end.dy - length * math.sin(angle - .45),
            )
            ..lineTo(end.dx, end.dy)
            ..lineTo(
              end.dx - length * math.cos(angle + .45),
              end.dy - length * math.sin(angle + .45),
            );
          canvas.drawPath(path, paint);
        case AnnotationKind.pencil:
        case AnnotationKind.marker:
          final path = ui.Path()..moveTo(a.points.first.dx, a.points.first.dy);
          for (final p in a.points.skip(1)) {
            path.lineTo(p.dx, p.dy);
          }
          if (a.kind == AnnotationKind.marker) {
            paint.color = paint.color.withValues(alpha: .35);
          }
          canvas.drawPath(path, paint);
        case AnnotationKind.text:
          if (b.width <= 0 || b.height <= 0) continue;
          final text = TextPainter(
            text: TextSpan(
              text: a.text,
              style: TextStyle(
                color: ui.Color(a.color),
                fontSize: a.fontSize,
                fontFamily: fontFamily,
                fontWeight: a.bold ? FontWeight.bold : FontWeight.normal,
                fontStyle: a.italic ? FontStyle.italic : FontStyle.normal,
                height: 1.2,
              ),
            ),
            textDirection: ui.TextDirection.ltr,
          )..layout(maxWidth: b.width);
          canvas.save();
          canvas.clipRect(b);
          text.paint(canvas, b.topLeft);
          canvas.restore();
          text.dispose();
        case AnnotationKind.mosaic:
        case AnnotationKind.blur:
          canvas.save();
          if (a.effectBrush) {
            canvas.clipPath(effectMask(a));
          } else {
            canvas.clipRect(b);
          }
          if (a.kind == AnnotationKind.mosaic) {
            final mosaic = mosaics[a.effectStrength]!;
            canvas.drawImageRect(
              mosaic,
              ui.Rect.fromLTWH(
                0,
                0,
                mosaic.width.toDouble(),
                mosaic.height.toDouble(),
              ),
              full,
              ui.Paint()..filterQuality = ui.FilterQuality.none,
            );
          } else {
            final sigma = blurRadius[a.effectStrength - 1];
            canvas.saveLayer(
              full,
              ui.Paint()
                ..imageFilter = ui.ImageFilter.blur(
                  sigmaX: sigma,
                  sigmaY: sigma,
                ),
            );
            canvas.drawImage(image, ui.Offset.zero, ui.Paint());
            canvas.restore();
          }
          canvas.restore();
      }
    }
    canvas.restore();
  }

  static const mosaicBlockSize = [4.0, 8.0, 12.0, 20.0, 32.0];
  static const blurRadius = [2.0, 5.0, 10.0, 16.0, 24.0];

  /// Union of round caps and segment strips; also covers a stationary click.
  static ui.Path effectMask(Annotation a) {
    final path = ui.Path();
    final radius = a.width / 2;
    for (final p in a.points) {
      path.addOval(ui.Rect.fromCircle(center: p, radius: radius));
    }
    for (var i = 1; i < a.points.length; i++) {
      final p = a.points[i - 1], q = a.points[i];
      final delta = q - p;
      if (delta.distance == 0) continue;
      final n = ui.Offset(-delta.dy, delta.dx) * (radius / delta.distance);
      path.addPolygon([p - n, q - n, q + n, p + n], true);
    }
    return path;
  }

  static Future<Map<int, ui.Image>> prepareMosaics(ui.Image image) async {
    final result = <int, ui.Image>{};
    try {
      for (var strength = 1; strength <= 5; strength++) {
        result[strength] = await pixelate(
          image,
          blockSize: mosaicBlockSize[strength - 1],
        );
      }
      return result;
    } catch (_) {
      for (final image in result.values) {
        image.dispose();
      }
      rethrow;
    }
  }

  static Future<ui.Image> pixelate(
    ui.Image image, {
    double blockSize = 12,
  }) async {
    final w = math.max(1, (image.width / blockSize).ceil()),
        h = math.max(1, (image.height / blockSize).ceil());
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawImageRect(
      image,
      ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      ui.Paint()..filterQuality = ui.FilterQuality.low,
    );
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(w, h);
    } finally {
      picture.dispose();
    }
  }

  static Future<Uint8List> export(
    PixelFrame frame,
    List<Annotation> items,
  ) async {
    final image = await pixelFrameToImage(frame);
    Map<int, ui.Image>? mosaics;
    try {
      mosaics = await prepareMosaics(image);
      final recorder = ui.PictureRecorder();
      paint(ui.Canvas(recorder), image, mosaics, items);
      final picture = recorder.endRecording();
      ui.Image output;
      try {
        output = await picture.toImage(image.width, image.height);
      } finally {
        picture.dispose();
      }
      try {
        final bytes = await output.toByteData(format: ui.ImageByteFormat.png);
        if (bytes == null) throw const FormatException('PNG 编码失败');
        return bytes.buffer.asUint8List(
          bytes.offsetInBytes,
          bytes.lengthInBytes,
        );
      } finally {
        output.dispose();
      }
    } finally {
      for (final mosaic in mosaics?.values ?? <ui.Image>[]) {
        mosaic.dispose();
      }
      image.dispose();
    }
  }
}
