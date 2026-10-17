import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/core.dart';
import '../platform/desktop_service.dart';

enum AppSection { picker, ruler, settings }

class MeasurementRecord {
  const MeasurementRecord({
    required this.measurement,
    required this.createdAt,
    required this.displayName,
  });
  final RulerMeasurement measurement;
  final DateTime createdAt;
  final String displayName;
  String get label => measurement.label;

  Map<String, Object?> toJson() => {
    'rect': measurement.rect.toJson(),
    'mode': measurement.mode.name,
    'logicalWidth': measurement.logicalWidth,
    'logicalHeight': measurement.logicalHeight,
    'createdAt': createdAt.toIso8601String(),
    'displayName': displayName,
  };

  factory MeasurementRecord.fromJson(Map<String, dynamic> json) {
    final rect = json['rect'] as Map;
    final left = rect['left'] as int;
    final top = rect['top'] as int;
    final right = rect['right'] as int;
    final bottom = rect['bottom'] as int;
    final width = (json['logicalWidth'] as num).toDouble();
    final height = (json['logicalHeight'] as num).toDouble();
    if (left < 0 ||
        top < 0 ||
        right <= left ||
        bottom <= top ||
        !width.isFinite ||
        !height.isFinite ||
        width <= 0 ||
        height <= 0) {
      throw const FormatException('Invalid measurement');
    }
    return MeasurementRecord(
      measurement: RulerMeasurement(
        rect: PixelRect(left: left, top: top, right: right, bottom: bottom),
        logicalWidth: width,
        logicalHeight: height,
        mode: RulerMode.values.byName(json['mode'] as String),
      ),
      createdAt: DateTime.parse(json['createdAt'] as String),
      displayName: json['displayName'] as String,
    );
  }
}

class AppController extends ChangeNotifier {
  AppController(this.desktop);
  final DesktopService desktop;
  AppSection section = AppSection.picker;
  RgbColor selectedColor = const RgbColor(215, 250, 107);
  final List<RgbColor> _colors = [];
  final List<MeasurementRecord> _measurements = [];
  List<RgbColor> get colors => List.unmodifiable(_colors);
  List<MeasurementRecord> get measurements => List.unmodifiable(_measurements);
  RulerMode mode = RulerMode.rectangle;
  ColorFormat format = ColorFormat.hex;
  int tolerance = 16;
  bool permissionGranted = false;
  bool shortcutsAvailable = false;
  bool supported = true;
  bool busy = false;
  bool initializing = true;
  String? error;
  String? notice;
  StreamSubscription<Map<Object?, Object?>>? _subscription;
  CaptureSession? _session;
  String? _tool;
  PixelPoint? _anchor;
  int? _anchorDisplay;
  bool _committing = false;
  bool _disposed = false;
  final List<Map<Object?, Object?>> _pending = [];

  Future<void> initialize() async {
    if (_subscription != null) return;
    _subscription = desktop.events.listen(
      _event,
      onError: (Object e) {
        _fail('系统工具连接中断，请重新打开 fruler。');
      },
    );
    try {
      final status = await desktop.initialize();
      permissionGranted = status.permission;
      shortcutsAvailable = status.shortcuts;
      supported = status.supported;
      final saved = await desktop.loadState();
      if (saved != null) _restore(saved);
      if (!supported) error = '当前版本支持 macOS 14 及以上，其他平台的适配尚未实现。';
    } catch (e) {
      error = _message(e);
    } finally {
      initializing = false;
      _notify();
    }
  }

  void selectSection(AppSection value) {
    section = value;
    _notify();
  }

  void selectMode(RulerMode value) {
    mode = value;
    _notify();
    _persist();
  }

  void setFormat(ColorFormat value) {
    format = value;
    _notify();
    _persist();
  }

  void setTolerance(int value) {
    tolerance = value.clamp(0, 80);
    _notify();
    _persist();
  }

  void selectColor(RgbColor value) {
    selectedColor = value;
    _notify();
  }

  void dismissMessage() {
    error = null;
    notice = null;
    _notify();
  }

  Future<void> requestPermission() async {
    try {
      permissionGranted = await desktop.requestPermission();
      notice = permissionGranted
          ? '屏幕访问已授权，可以开始使用。'
          : '请在系统设置中允许 fruler 录制屏幕，然后返回重试。';
      error = null;
      _notify();
    } catch (e) {
      _fail(_message(e));
    }
  }

  Future<void> openPrivacySettings() async {
    try {
      await desktop.openPrivacySettings();
    } catch (e) {
      _fail(_message(e));
    }
  }

  Future<void> pickColor() => _begin('picker');
  Future<void> startRuler([RulerMode? value]) {
    if (value != null) selectMode(value);
    return _begin(mode.name);
  }

  Future<void> _begin(String tool) async {
    if (busy || initializing || _disposed) return;
    if (!supported) {
      _fail('当前版本仅支持 macOS 14 及以上。');
      return;
    }
    busy = true;
    _tool = tool;
    _committing = false;
    _anchor = null;
    _anchorDisplay = null;
    _pending.clear();
    error = null;
    notice = null;
    section = tool == 'picker' ? AppSection.picker : AppSection.ruler;
    _notify();
    try {
      final session = await desktop.begin(tool);
      if (_disposed) {
        await desktop.finish(session.id);
        return;
      }
      _session = session;
      permissionGranted = true;
      final pending = List<Map<Object?, Object?>>.of(_pending);
      _pending.clear();
      for (final event in pending) {
        _event(event);
      }
    } catch (e) {
      busy = false;
      _session = null;
      _pending.clear();
      if (e is PlatformException && e.code == 'screen_permission') {
        permissionGranted = false;
      }
      _fail(_message(e));
    }
  }

  void _event(Map<Object?, Object?> event) {
    if (_disposed) return;
    switch (event['type']) {
      case 'activate':
        final tool = event['tool'];
        if (tool == 'picker') {
          unawaited(pickColor());
        } else {
          final value = RulerMode.values
              .where((v) => v.name == tool)
              .firstOrNull;
          if (value != null) unawaited(startRuler(value));
        }
        return;
      case 'permissionChanged':
        permissionGranted = event['permission'] == true;
        _notify();
        return;
    }
    if (!busy) return;
    if (_session == null) {
      // Native input may arrive while the capture response crosses the channel.
      if (_pending.length < 128) _pending.add(event);
      return;
    }
    if (event['sessionId'] != _session!.id) return;
    if (event['type'] == 'cancelled') {
      _resetSession();
      notice = '已取消';
      _notify();
      return;
    }
    if (event['type'] != 'pointer' || _committing) return;
    final display = _session!.displays
        .where((d) => d.id == event['displayId'])
        .firstOrNull;
    if (display == null) return;
    final x = (event['x'] as num).toDouble();
    final y = (event['y'] as num).toDouble();
    if (!x.isFinite || !y.isFinite) return;
    final phase = event['phase'] as String;
    final frame = display.frame;
    final pixel = frame.logicalToPixel(x, y);
    final color = frame.pixelAt(pixel.x, pixel.y);
    RulerMeasurement? measurement;
    if (_tool == RulerMode.rectangle.name) {
      if (phase == 'down') {
        _anchor = frame.logicalToBoundary(x, y);
        _anchorDisplay = display.id;
      }
      if (_anchor != null && _anchorDisplay == display.id) {
        measurement = RulerMeasurement.fromRect(
          frame,
          PixelRect.fromPoints(_anchor!, frame.logicalToBoundary(x, y)),
          RulerMode.rectangle,
        );
      }
    } else if (_tool != 'picker') {
      measurement = EdgeDetector.measure(
        frame,
        pixel.x,
        pixel.y,
        RulerMode.values.byName(_tool!),
        tolerance: tolerance,
      );
    }
    final label = _tool == 'picker'
        ? '${color.hex}  ·  ${color.rgb}'
        : measurement?.label ?? '按住并拖拽，测量矩形区域';
    unawaited(
      desktop
          .updateOverlay({
            'sessionId': _session!.id,
            'displayId': display.id,
            'x': x,
            'y': y,
            'label': label,
            'color': color.toJson(),
            'rect': measurement?.rect.toJson(),
          })
          .catchError((Object e) {
            unawaited(_abort(e));
          }),
    );
    if (phase != 'up') return;
    if (_tool == 'picker') {
      unawaited(_commitColor(color));
    } else if (measurement != null &&
        measurement.rect.width > 0 &&
        measurement.rect.height > 0) {
      unawaited(_commitMeasurement(measurement, display.name));
    } else {
      _anchor = null;
      _anchorDisplay = null;
    }
  }

  Future<void> _commitColor(RgbColor color) async {
    _committing = true;
    selectedColor = color;
    _colors.remove(color);
    _colors.insert(0, color);
    if (_colors.length > 64) _colors.removeLast();
    await _complete(color.formatted(format));
  }

  Future<void> _commitMeasurement(
    RulerMeasurement measurement,
    String displayName,
  ) async {
    _committing = true;
    _measurements.insert(
      0,
      MeasurementRecord(
        measurement: measurement,
        createdAt: DateTime.now(),
        displayName: displayName,
      ),
    );
    if (_measurements.length > 32) _measurements.removeLast();
    await _complete(measurement.label);
  }

  Future<void> _complete(String text) async {
    try {
      await desktop.writeClipboard(text);
      notice = '已复制 $text';
    } catch (e) {
      error = '结果已保存，但复制失败：${_message(e)}';
    } finally {
      final id = _session?.id;
      try {
        if (id != null) await desktop.finish(id);
      } catch (e) {
        error = '无法关闭测量浮层，请按 Esc：${_message(e)}';
      }
      _resetSession();
      _persist();
      _notify();
    }
  }

  Future<void> _abort(Object e) async {
    if (!busy || _committing) return;
    _committing = true;
    final id = _session?.id;
    try {
      if (id != null) await desktop.finish(id);
    } catch (_) {
      /* Preserve original failure. */
    }
    _resetSession();
    _fail(_message(e));
  }

  void _resetSession() {
    _session = null;
    _tool = null;
    busy = false;
    _anchor = null;
    _anchorDisplay = null;
    _committing = false;
    _pending.clear();
  }

  Future<void> copyColor([RgbColor? color]) async {
    final value = color ?? selectedColor;
    selectedColor = value;
    await _copy(value.formatted(format));
  }

  Future<void> copyMeasurement(MeasurementRecord record) => _copy(record.label);
  Future<void> _copy(String text) async {
    try {
      await desktop.writeClipboard(text);
      notice = '已复制 $text';
      error = null;
      _notify();
    } catch (e) {
      _fail(_message(e));
    }
  }

  void clearColors() {
    _colors.clear();
    _persist();
    _notify();
  }

  void clearMeasurements() {
    _measurements.clear();
    _persist();
    _notify();
  }

  void _persist() {
    final json = jsonEncode({
      'version': 1,
      'format': format.name,
      'mode': mode.name,
      'tolerance': tolerance,
      'colors': _colors.map((c) => c.toJson()).toList(),
      'measurements': _measurements.map((r) => r.toJson()).toList(),
    });
    unawaited(
      desktop.saveState(json).catchError((Object e) {
        _fail('历史记录保存失败：${_message(e)}');
      }),
    );
  }

  void _restore(String saved) {
    try {
      final data = jsonDecode(saved) as Map<String, dynamic>;
      format =
          ColorFormat.values
              .where((v) => v.name == data['format'])
              .firstOrNull ??
          format;
      mode =
          RulerMode.values.where((v) => v.name == data['mode']).firstOrNull ??
          mode;
      final value = data['tolerance'];
      if (value is int) tolerance = value.clamp(0, 80);
      for (final value in (data['colors'] as List? ?? []).take(64)) {
        try {
          final c = RgbColor.fromJson(value);
          if (!_colors.contains(c)) _colors.add(c);
        } catch (_) {
          /* Ignore a corrupt record, preserving other history. */
        }
      }
      for (final value in (data['measurements'] as List? ?? []).take(32)) {
        try {
          _measurements.add(
            MeasurementRecord.fromJson(value as Map<String, dynamic>),
          );
        } catch (_) {
          /* Ignore a corrupt record. */
        }
      }
      if (_colors.isNotEmpty) selectedColor = _colors.first;
    } catch (_) {
      notice = '历史记录无法读取，已使用默认设置。';
    }
  }

  String _message(Object e) {
    if (e is PlatformException) {
      return switch (e.code) {
        'screen_permission' => '需要屏幕录制权限。请前往偏好设置授权，再重新打开工具。',
        'capture_cancelled' => '屏幕状态发生变化，请重新开始。',
        'capture_busy' => '已有工具正在使用，请先按 Esc 退出。',
        _ => e.message ?? '系统操作失败，请重试。',
      };
    }
    if (e is UnsupportedError) return e.message?.toString() ?? '当前平台尚未支持';
    return '操作失败，请重试。';
  }

  void _fail(String message) {
    error = message;
    notice = null;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _subscription?.cancel();
    final id = _session?.id;
    if (id != null) unawaited(desktop.finish(id).catchError((Object _) {}));
    super.dispose();
  }
}
