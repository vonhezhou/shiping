import 'dart:convert';
import 'dart:typed_data';

class ImageProjectView {
  const ImageProjectView({
    required this.scale,
    required this.x,
    required this.y,
    this.pan = false,
  });
  final double scale, x, y;
  final bool pan;
  Map<String, Object> toJson() => {'scale': scale, 'x': x, 'y': y, 'pan': pan};
  factory ImageProjectView.fromJson(Object? value) {
    if (value is! Map) throw const FormatException('项目视图无效');
    final scale = value['scale'], x = value['x'], y = value['y'];
    if (scale is! num ||
        x is! num ||
        y is! num ||
        !scale.isFinite ||
        scale < .01 ||
        scale > 32 ||
        !x.isFinite ||
        !y.isFinite ||
        x.abs() > 1e7 ||
        y.abs() > 1e7 ||
        value['pan'] is! bool) {
      throw const FormatException('项目缩放或平移位置无效');
    }
    return ImageProjectView(
      scale: scale.toDouble(),
      x: x.toDouble(),
      y: y.toDouble(),
      pan: value['pan'] as bool,
    );
  }
}

/// Portable, self-contained document. No file paths, preferences or screen history.
class ImageProject {
  const ImageProject({
    required this.name,
    required this.png,
    required this.width,
    required this.height,
    required this.annotations,
    required this.tool,
    this.view,
    this.tolerance = 16,
    this.zoom = 12,
  });
  static const maxFileBytes = 128 * 1024 * 1024;
  final String name, tool;
  final Uint8List png;
  final int width, height, tolerance, zoom;
  final List<Map<String, Object?>> annotations;
  final ImageProjectView? view;
  String encode() => jsonEncode({
    'format': 'dev.fruler.image-project',
    'version': 1,
    'image': {
      'name': name,
      'width': width,
      'height': height,
      'png': base64Encode(png),
    },
    'annotations': annotations
        .map((e) => {'id': e['id'], 'rect': e['rect']})
        .toList(),
    'tool': tool,
    'view': view?.toJson(),
    'tolerance': tolerance,
    'zoom': zoom,
  });
  factory ImageProject.decode(String text) {
    if (text.length > maxFileBytes) {
      throw const FormatException('项目文件不能超过 128 MB');
    }
    final data = jsonDecode(text);
    if (data is! Map ||
        data['format'] != 'dev.fruler.image-project' ||
        data['version'] != 1) {
      throw const FormatException('不支持的 fruler 项目格式或版本');
    }
    final image = data['image'];
    if (image is! Map ||
        image['name'] is! String ||
        (image['name'] as String).length > 1024 ||
        image['png'] is! String) {
      throw const FormatException('项目图片信息无效');
    }
    final width = image['width'], height = image['height'];
    if (width is! int ||
        height is! int ||
        width <= 0 ||
        height <= 0 ||
        width > 16384 ||
        height > 16384 ||
        width * height > 16000000) {
      throw const FormatException('项目图片尺寸超出限制');
    }
    final png = base64Decode(image['png'] as String);
    if (png.length > 96 * 1024 * 1024 ||
        png.length < 8 ||
        png[0] != 137 ||
        png[1] != 80 ||
        png[2] != 78 ||
        png[3] != 71 ||
        png[4] != 13 ||
        png[5] != 10 ||
        png[6] != 26 ||
        png[7] != 10) {
      throw const FormatException('项目必须内嵌有效的 PNG 图片');
    }
    final raw = data['annotations'];
    if (raw is! List || raw.length > 4096) {
      throw const FormatException('项目最多支持 4096 个标注');
    }
    final ids = <int>{};
    final annotations = <Map<String, Object?>>[];
    for (final pin in raw) {
      if (pin is! Map ||
          pin['id'] is! int ||
          (pin['id'] as int) <= 0 ||
          (pin['id'] as int) > 2147483647 ||
          !ids.add(pin['id'] as int)) {
        throw const FormatException('项目标注编号无效或重复');
      }
      final rect = pin['rect'];
      if (rect is! Map ||
          ['left', 'top', 'right', 'bottom'].any((k) => rect[k] is! int)) {
        throw const FormatException('项目标注坐标无效');
      }
      final l = rect['left'] as int,
          t = rect['top'] as int,
          r = rect['right'] as int,
          b = rect['bottom'] as int;
      if (l < 0 || t < 0 || r <= l || b <= t || r > width || b > height) {
        throw const FormatException('项目标注超出图片边界');
      }
      annotations.add({
        'id': pin['id'],
        'displayId': 0,
        'rect': {'left': l, 'top': t, 'right': r, 'bottom': b},
        'label': '${r - l} × ${b - t} px',
      });
    }
    final tool = data['tool'];
    final tolerance = data['tolerance'], zoom = data['zoom'];
    if (![
          'picker',
          'rectangle',
          'horizontal',
          'vertical',
          'cross',
        ].contains(tool) ||
        tolerance is! int ||
        tolerance < 0 ||
        tolerance > 255 ||
        zoom is! int ||
        ![4, 8, 12, 16, 24, 32].contains(zoom)) {
      throw const FormatException('项目工具设置无效');
    }
    return ImageProject(
      name: image['name'] as String,
      png: png,
      width: width,
      height: height,
      annotations: annotations,
      tool: tool as String,
      view: data['view'] == null
          ? null
          : ImageProjectView.fromJson(data['view']),
      tolerance: tolerance,
      zoom: zoom,
    );
  }
}
