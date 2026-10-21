import 'dart:ffi';

import '../core/pixel_frame.dart';
import 'desktop.g.dart' as wire;

/// The external typed-data backing store owns an ARC reference, independent of
/// the native capture session. Its finalizer releases that reference after all
/// Dart views stop using the pixels. Never release it merely on session finish.
class NativePixelBuffers {
  static final _library = DynamicLibrary.process();
  static final _acquire = _library
      .lookupFunction<
        Pointer<Void> Function(Int64),
        Pointer<Void> Function(int)
      >('fruler_frame_acquire');
  static final _data = _library
      .lookupFunction<
        Pointer<Uint8> Function(Pointer<Void>),
        Pointer<Uint8> Function(Pointer<Void>)
      >('fruler_frame_data');
  static final _length = _library
      .lookupFunction<
        Int64 Function(Pointer<Void>),
        int Function(Pointer<Void>)
      >('fruler_frame_length');
  static final _releasePointer = _library.lookup<NativeFinalizerFunction>(
    'fruler_frame_release',
  );
  static final _release = _releasePointer
      .asFunction<void Function(Pointer<Void>)>();

  static PixelFrame read(wire.DisplayFrame metadata) {
    if (metadata.bufferId <= 0 ||
        metadata.width <= 0 ||
        metadata.height <= 0 ||
        metadata.rowBytes < metadata.width * 4 ||
        metadata.rowBytes % 4 != 0 ||
        metadata.byteLength != metadata.rowBytes * metadata.height ||
        !metadata.logicalWidth.isFinite ||
        !metadata.logicalHeight.isFinite ||
        metadata.logicalWidth <= 0 ||
        metadata.logicalHeight <= 0) {
      throw const FormatException('Invalid native pixel metadata');
    }
    final token = _acquire(metadata.bufferId);
    if (token == nullptr) {
      throw const FormatException('Capture buffer is no longer available');
    }
    var ownsToken = true;
    try {
      final address = _data(token);
      if (address == nullptr || _length(token) != metadata.byteLength) {
        throw const FormatException('Native pixel buffer length mismatch');
      }
      final bytes = address.asTypedList(
        metadata.byteLength,
        finalizer: _releasePointer,
        token: token,
      );
      ownsToken = false;
      return PixelFrame(
        width: metadata.width,
        height: metadata.height,
        rgba: bytes.asUnmodifiableView(),
        rowBytes: metadata.rowBytes,
        logicalWidth: metadata.logicalWidth,
        logicalHeight: metadata.logicalHeight,
      );
    } finally {
      if (ownsToken) _release(token);
    }
  }
}
