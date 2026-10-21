import 'dart:async';
import 'dart:ui' as ui;

import '../core/pixel_frame.dart';

/// Bounds of a pixel view within its shared source image.
ui.Rect pixelFrameSourceRect(PixelFrame frame) => ui.Rect.fromLTWH(
  frame.originX.toDouble(),
  frame.originY.toDouble(),
  frame.width.toDouble(),
  frame.height.toDouble(),
);

/// Upload the shared SOURCE, not a packed copy of a selection. Caller owns image.
Future<ui.Image> pixelFrameToImage(PixelFrame frame) async {
  final source = frame.source;
  final buffer = await ui.ImmutableBuffer.fromUint8List(source.rgba);
  try {
    final descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: source.width,
      height: source.height,
      rowBytes: source.rowBytes,
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

/// One upload per selected display/session. Callers receive independently owned
/// image handles so clearing the cache cannot invalidate active painters/exports.
class PixelImageCache {
  final _sources = <PixelFrame, _SourceImage>{};
  Future<ui.Image> load(PixelFrame frame) => _sources
      .putIfAbsent(frame.source, () => _SourceImage(frame.source))
      .clone();
  void clear() {
    for (final source in _sources.values) {
      source.dispose();
    }
    _sources.clear();
  }
}

class _SourceImage {
  _SourceImage(PixelFrame frame) : _image = pixelFrameToImage(frame);
  final Future<ui.Image> _image;
  bool _disposed = false;
  Future<ui.Image> clone() async {
    final image = await _image;
    if (_disposed) throw StateError('Capture image was released');
    return image.clone();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(_image.then((image) => image.dispose(), onError: (Object _) {}));
  }
}
