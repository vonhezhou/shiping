import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../core/annotation.dart';
import '../core/pixel_frame.dart';
import '../core/ruler.dart';

/// One renderer for both the editable preview and flattened PNG output.
class AnnotationRenderer {
  static void paint(
    ui.Canvas canvas,
    ui.Image image,
    ui.Image mosaic,
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
          canvas.drawRect(b, paint);
        case AnnotationKind.ellipse:
          canvas.drawOval(b, paint);
        case AnnotationKind.line:
          canvas.drawLine(a.points.first, a.points.last, paint);
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
          canvas.save();
          canvas.clipRect(b);
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
          canvas.restore();
        case AnnotationKind.blur:
          canvas.save();
          canvas.clipRect(b);
          canvas.saveLayer(
            full,
            ui.Paint()
              ..imageFilter = ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          );
          canvas.drawImage(image, ui.Offset.zero, ui.Paint());
          canvas.restore();
          canvas.restore();
      }
    }
    canvas.restore();
  }

  static Future<ui.Image> pixelate(ui.Image image) async {
    final w = math.max(1, (image.width / 12).ceil()),
        h = math.max(1, (image.height / 12).ceil());
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

  static Future<Uint8List> export(Uint8List png, List<Annotation> items) async {
    final codec = await ui.instantiateImageCodec(png);
    final image = (await codec.getNextFrame()).image;
    codec.dispose();
    ui.Image? mosaic;
    try {
      mosaic = await pixelate(image);
      final recorder = ui.PictureRecorder();
      paint(ui.Canvas(recorder), image, mosaic, items);
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
      mosaic?.dispose();
      image.dispose();
    }
  }

  /// Crop before crossing into a document; no rulers, labels or padding.
  static Future<Uint8List> crop(PixelFrame frame, PixelRect rect) async {
    final bytes = Uint8List(rect.width * rect.height * 4);
    for (var y = 0; y < rect.height; y++) {
      final start = ((rect.top + y) * frame.width + rect.left) * 4;
      bytes.setRange(
        y * rect.width * 4,
        (y + 1) * rect.width * 4,
        frame.rgba,
        start,
      );
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: rect.width,
      height: rect.height,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final codec = await descriptor.instantiateCodec();
    try {
      final image = (await codec.getNextFrame()).image;
      try {
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        if (png == null) throw const FormatException('截图编码失败');
        return png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes);
      } finally {
        image.dispose();
      }
    } finally {
      codec.dispose();
      descriptor.dispose();
      buffer.dispose();
    }
  }
}
