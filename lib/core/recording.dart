/// 跨 Dart、原生录屏与本地偏好共用的有限参数集合。
class RecordingOptions {
  const RecordingOptions({
    this.codec = 'h264',
    this.frameRate = 30,
    this.quality = 'high',
    this.resolution = 'original',
    this.showCursor = true,
    this.systemAudio = false,
  }) : assert(codec == 'h264' || codec == 'hevc'),
       assert(frameRate == 24 || frameRate == 30 || frameRate == 60),
       assert(quality == 'low' || quality == 'medium' || quality == 'high'),
       assert(
         resolution == 'original' ||
             resolution == '1080p' ||
             resolution == '720p',
       );

  static const codecs = ['h264', 'hevc'];
  static const frameRates = [24, 30, 60];
  static const qualities = ['low', 'medium', 'high'];
  static const resolutions = ['original', '1080p', '720p'];

  final String codec;
  final int frameRate;
  final String quality;
  final String resolution;
  final bool showCursor;
  final bool systemAudio;

  RecordingOptions copyWith({
    String? codec,
    int? frameRate,
    String? quality,
    String? resolution,
    bool? showCursor,
    bool? systemAudio,
  }) => RecordingOptions(
    codec: codec ?? this.codec,
    frameRate: frameRate ?? this.frameRate,
    quality: quality ?? this.quality,
    resolution: resolution ?? this.resolution,
    showCursor: showCursor ?? this.showCursor,
    systemAudio: systemAudio ?? this.systemAudio,
  );

  Map<String, Object> toJson() => {
    'codec': codec,
    'frameRate': frameRate,
    'quality': quality,
    'resolution': resolution,
    'showCursor': showCursor,
    'systemAudio': systemAudio,
  };

  factory RecordingOptions.fromJson(Object? value) {
    if (value is! Map) return const RecordingOptions();
    const defaults = RecordingOptions();
    return RecordingOptions(
      codec: codecs.contains(value['codec'])
          ? value['codec'] as String
          : defaults.codec,
      frameRate:
          value['frameRate'] is int && frameRates.contains(value['frameRate'])
          ? value['frameRate'] as int
          : defaults.frameRate,
      quality: qualities.contains(value['quality'])
          ? value['quality'] as String
          : defaults.quality,
      resolution: resolutions.contains(value['resolution'])
          ? value['resolution'] as String
          : defaults.resolution,
      showCursor: value['showCursor'] is bool
          ? value['showCursor'] as bool
          : defaults.showCursor,
      systemAudio: value['systemAudio'] is bool
          ? value['systemAudio'] as bool
          : defaults.systemAudio,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RecordingOptions &&
      codec == other.codec &&
      frameRate == other.frameRate &&
      quality == other.quality &&
      resolution == other.resolution &&
      showCursor == other.showCursor &&
      systemAudio == other.systemAudio;

  @override
  int get hashCode => Object.hash(
    codec,
    frameRate,
    quality,
    resolution,
    showCursor,
    systemAudio,
  );
}
