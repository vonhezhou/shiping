import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fruler/core/core.dart';

void main() {
  test('带行跨度的嵌套选区共享缓冲，索引与边界扫描不读行间填充', () {
    final bytes = Uint8List(24 * 4);
    for (var y = 0; y < 4; y++) {
      for (var x = 0; x < 5; x++) {
        bytes.setRange(y * 24 + x * 4, y * 24 + x * 4 + 4, [
          x == 2 || x == 3 ? 80 : x,
          y * 30,
          20,
          255,
        ]);
      }
    }
    final root = PixelFrame(
      width: 5,
      height: 4,
      rowBytes: 24,
      rgba: bytes,
      logicalWidth: 2.5,
      logicalHeight: 2,
    );
    final view = root.view(left: 1, top: 1, width: 4, height: 3);
    final inner = view.view(left: 1, top: 1, width: 2, height: 2);
    expect(inner.rgba, same(root.rgba));
    expect(inner.source, same(root));
    expect((inner.originX, inner.originY, inner.offsetBytes), (2, 2, 56));
    expect(inner.pixelAt(0, 0), const RgbColor(80, 60, 20));
    expect(inner.pixelAt(1, 1), const RgbColor(80, 90, 20));
    expect(inner.scaleX, 2);
    final measured = EdgeDetector.measure(
      inner,
      0,
      0,
      RulerMode.horizontal,
      tolerance: 0,
    );
    expect(measured.rect.width, 2);
    expect(() => inner.pixelAt(2, 0), throwsRangeError);
    expect(
      () => inner.view(left: -1, top: 0, width: 1, height: 1),
      throwsArgumentError,
    );
    expect(
      () => view.view(left: 3, top: 0, width: 2, height: 1),
      throwsArgumentError,
    );
  });
  test('拒绝无效行跨度、缓冲长度与空选区', () {
    for (final stride in [7, 9, 12]) {
      expect(
        () => PixelFrame(
          width: 2,
          height: 2,
          rowBytes: stride,
          rgba: Uint8List(16),
          logicalWidth: 2,
          logicalHeight: 2,
        ),
        throwsArgumentError,
      );
    }
    final root = PixelFrame(
      width: 2,
      height: 2,
      rgba: Uint8List(16),
      logicalWidth: 2,
      logicalHeight: 2,
    );
    expect(
      () => root.view(left: 0, top: 0, width: 0, height: 1),
      throwsArgumentError,
    );
  });
}
