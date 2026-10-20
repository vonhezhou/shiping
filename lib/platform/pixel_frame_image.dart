import 'dart:ui' as ui;

import '../core/pixel_frame.dart';

/// The caller owns the returned image. Temporary decoding resources stay local.
Future<ui.Image> pixelFrameToImage(PixelFrame frame) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(frame.rgba);
  try {
    final descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: frame.width,
      height: frame.height,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    try {
      final codec = await descriptor.instantiateCodec();
      try {
        return (await codec.getNextFrame()).image;
      } finally {
        codec.dispose();
      }
    } finally {
      descriptor.dispose();
    }
  } finally {
    buffer.dispose();
  }
}
