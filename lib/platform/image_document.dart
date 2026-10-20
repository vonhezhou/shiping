import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../core/core.dart';
import 'pixel_frame_image.dart';

class ImageFileData {
  const ImageFileData(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

class ImageDocument {
  const ImageDocument(this.name, this.frame);
  final String name;
  final PixelFrame frame;
}

/// Flutter decoding keeps image tools available to future desktop adapters.
class ImageDocumentCodec {
  Future<ImageDocument> decode(ImageFileData file) =>
      _decode(file, 32 * 1024 * 1024);

  /// Copy the frozen selection directly; PNG is only needed at export time.
  Future<ImageDocument> cropCapture(PixelFrame source, PixelRect rect) async {
    if (rect.left < 0 ||
        rect.top < 0 ||
        rect.right > source.width ||
        rect.bottom > source.height ||
        rect.width <= 0 ||
        rect.height <= 0) {
      throw ArgumentError('Invalid capture rectangle');
    }
    _validateSize(rect.width, rect.height);
    final bytes = Uint8List(rect.width * rect.height * 4);
    for (var y = 0; y < rect.height; y++) {
      final start = ((rect.top + y) * source.width + rect.left) * 4;
      bytes.setRange(
        y * rect.width * 4,
        (y + 1) * rect.width * 4,
        source.rgba,
        start,
      );
    }
    // Native capture uses premultiplied RGBA. Keep the previous white backing.
    for (var i = 0; i < bytes.length; i += 4) {
      final white = 255 - bytes[i + 3];
      if (white == 0) continue;
      for (var c = 0; c < 3; c++) {
        bytes[i + c] = (bytes[i + c] + white).clamp(0, 255);
      }
      bytes[i + 3] = 255;
    }
    return ImageDocument(
      '截图.png',
      PixelFrame(
        width: rect.width,
        height: rect.height,
        logicalWidth: rect.width.toDouble(),
        logicalHeight: rect.height.toDouble(),
        rgba: bytes,
      ),
    );
  }

  static void _validateSize(int width, int height) {
    if (width > 16384 || height > 16384 || width * height > 16000000) {
      throw const FormatException('图片最多 1600 万像素，单边不超过 16384 像素');
    }
  }

  Future<ImageDocument> _decode(ImageFileData file, int limit) async {
    if (file.bytes.length > limit) {
      throw FormatException('图片文件不能超过 ${limit ~/ (1024 * 1024)} MB');
    }
    final b = file.bytes;
    final png =
        b.length >= 8 &&
        listEquals(b.sublist(0, 8), [137, 80, 78, 71, 13, 10, 26, 10]);
    final jpeg = b.length >= 3 && b[0] == 255 && b[1] == 216 && b[2] == 255;
    final webp =
        b.length >= 12 &&
        String.fromCharCodes(b.sublist(0, 4)) == 'RIFF' &&
        String.fromCharCodes(b.sublist(8, 12)) == 'WEBP';
    if (!png && !jpeg && !webp) {
      throw const FormatException('仅支持 PNG、JPEG 和 WebP 图片');
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(b);
    final codec = await ui.instantiateImageCodecWithSize(
      buffer,
      getTargetSize: (w, h) {
        _validateSize(w, h);
        return ui.TargetImageSize(width: w, height: h);
      },
    );
    try {
      final frame = await codec.getNextFrame();
      final image = frame.image;
      try {
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder);
        canvas.drawColor(const ui.Color(0xFFFFFFFF), ui.BlendMode.src);
        canvas.drawImage(image, ui.Offset.zero, ui.Paint());
        final picture = recorder.endRecording();
        final opaque = await picture.toImage(image.width, image.height);
        picture.dispose();
        try {
          final raw = await opaque.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          if (raw == null) {
            throw const FormatException('无法解码图片');
          }
          return ImageDocument(
            file.name,
            PixelFrame(
              width: image.width,
              height: image.height,
              logicalWidth: image.width.toDouble(),
              logicalHeight: image.height.toDouble(),
              rgba: raw.buffer.asUint8List(),
            ),
          );
        } finally {
          opaque.dispose();
        }
      } finally {
        image.dispose();
      }
    } finally {
      codec.dispose();
    }
  }

  Future<Uint8List> renderAnnotations(
    ImageDocument document,
    List<Map<String, Object?>> pins,
  ) async {
    final image = await pixelFrameToImage(document.frame);
    final bounds = ui.Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    final rects = <ui.Rect>[];
    final labels = <({ui.Rect rect, TextPainter painter})>[];
    ui.Rect? union;
    for (final pin in pins) {
      final value = pin['rect'] as Map;
      final rect = ui.Rect.fromLTRB(
        (value['left'] as num).toDouble(),
        (value['top'] as num).toDouble(),
        (value['right'] as num).toDouble(),
        (value['bottom'] as num).toDouble(),
      ).intersect(bounds);
      if (rect.isEmpty) continue;
      final painter = TextPainter(
        text: TextSpan(
          text: '${pin['id']} · ${pin['label']}',
          style: const TextStyle(
            color: ui.Color(0xFFD7FA6B),
            fontSize: 12,
            fontFamily: 'Menlo',
          ),
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      var label = ui.Rect.fromLTWH(
        rect.left.clamp(0, math.max(0, bounds.width - painter.width - 8)),
        math.max(0, rect.top - painter.height - 8),
        painter.width + 8,
        painter.height + 4,
      );
      for (
        var attempt = 0;
        attempt < pins.length + 1 && labels.any((e) => e.rect.overlaps(label));
        attempt++
      ) {
        label = label.shift(ui.Offset(0, label.height + 2));
      }
      rects.add(rect);
      labels.add((rect: label, painter: painter));
      final combined = rect.expandToInclude(label);
      union = union == null ? combined : union.expandToInclude(combined);
    }
    if (union == null) {
      image.dispose();
      throw const FormatException('没有可导出的图片标注');
    }
    final crop = union.inflate(16);
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawColor(const ui.Color(0xFF111315), ui.BlendMode.src);
    canvas.translate(-crop.left.floorToDouble(), -crop.top.floorToDouble());
    canvas.drawImage(image, ui.Offset.zero, ui.Paint());
    for (var i = 0; i < rects.length; i++) {
      canvas.drawRect(
        rects[i],
        ui.Paint()
          ..color = const ui.Color(0xFFD7FA6B)
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = 1,
      );
      canvas.drawRect(
        labels[i].rect,
        ui.Paint()..color = const ui.Color(0xE6000000),
      );
      labels[i].painter.paint(
        canvas,
        labels[i].rect.topLeft + const ui.Offset(4, 2),
      );
      labels[i].painter.dispose();
    }
    final picture = recorder.endRecording();
    final output = await picture.toImage(
      crop.right.ceil() - crop.left.floor(),
      crop.bottom.ceil() - crop.top.floor(),
    );
    picture.dispose();
    image.dispose();
    try {
      final bytes = await output.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw const FormatException('图片导出失败');
      return bytes.buffer.asUint8List();
    } finally {
      output.dispose();
    }
  }
}
