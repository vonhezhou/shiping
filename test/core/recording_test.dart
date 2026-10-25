import 'package:flutter_test/flutter_test.dart';
import 'package:fruler/core/core.dart';

void main() {
  test('录屏参数完整往返且复制修改保留其他参数', () {
    const options = RecordingOptions(
      codec: 'hevc',
      frameRate: 60,
      quality: 'medium',
      resolution: '1080p',
      showCursor: false,
      systemAudio: true,
    );
    expect(RecordingOptions.fromJson(options.toJson()), options);
    final changed = options.copyWith(frameRate: 24, resolution: '720p');
    expect(changed.toJson(), {
      'codec': 'hevc',
      'frameRate': 24,
      'quality': 'medium',
      'resolution': '720p',
      'showCursor': false,
      'systemAudio': true,
    });
  });

  test('损坏或旧版参数逐项回退默认且保留仍受支持的偏好', () {
    expect(RecordingOptions.fromJson(null), const RecordingOptions());
    expect(RecordingOptions.fromJson(['h264']), const RecordingOptions());
    expect(
      RecordingOptions.fromJson({
        'codec': 'unsupported',
        'frameRate': 120,
        'quality': 'medium',
        'resolution': '4k',
        'showCursor': 'false',
        'systemAudio': true,
      }),
      const RecordingOptions(quality: 'medium', systemAudio: true),
    );
    expect(
      RecordingOptions.fromJson({'codec': 'hevc', 'showCursor': false}),
      const RecordingOptions(codec: 'hevc', showCursor: false),
    );
    expect(
      RecordingOptions.fromJson({'frameRate': 30.5}),
      const RecordingOptions(),
    );
  });
}
