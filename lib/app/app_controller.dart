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
  final List<PaletteEntry> _palette = [];
  List<PaletteEntry> get palette => List.unmodifiable(_palette);
  bool continuousPicker = false;
  int _pickedCount = 0;
  int _nextPinId = 0;
  int? _selectedPin;
  bool _editingPins = false;
  final List<List<Map<String, Object?>>> _pinUndo = [];

  final List<MeasurementRecord> _measurements = [];
  List<RgbColor> get colors => List.unmodifiable(_colors);
  List<MeasurementRecord> get measurements => List.unmodifiable(_measurements);
  RulerMode mode = RulerMode.rectangle;
  ColorFormat format = ColorFormat.hex;
  int tolerance = 16;
  int zoom = CaptureControls.defaultZoom;
  ShortcutBindings shortcuts = ShortcutBindings.defaults;
  bool savingShortcuts = false;
  bool recordingShortcut = false;
  ShortcutChord? recordedShortcut;
  final List<Map<String, Object?>> _pins = [];
  ({int displayId, double x, double y})? _lastPointer;
  bool _keyboardRectangle = false;
  bool _keyboardCursor = false;
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
      if (supported) {
        try {
          shortcutsAvailable = await desktop.configureShortcuts(shortcuts);
        } catch (e) {
          shortcutsAvailable = false;
          error = _message(e);
        }
      }
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
    tolerance = value.clamp(0, 255);
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
    if (busy ||
        initializing ||
        recordingShortcut ||
        savingShortcuts ||
        _disposed) {
      return;
    }
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
    _pins.clear();
    _pinUndo.clear();
    _selectedPin = null;
    _editingPins = false;
    _pickedCount = 0;
    _lastPointer = null;
    _keyboardRectangle = false;
    _keyboardCursor = false;
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
      _redraw();
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
      case 'shortcutRecorded':
        if (recordingShortcut) {
          try {
            recordedShortcut = ShortcutChord.fromJson(event['chord']);
            _notify();
          } catch (_) {
            /* Ignore modifier-only or unsupported keys. */
          }
        }
        return;
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
      final count = _tool == 'picker' ? _pickedCount : 0;
      _resetSession();
      notice = count > 0 ? '取色已结束，已采集 $count 次' : '已取消';
      _notify();
      return;
    }
    if (_committing) return;
    switch (event['type']) {
      case 'continuousChanged':
        setContinuousPicker(event['enabled'] == true);
        return;
      case 'editPins':
        _editingPins = !_editingPins;
        _anchor = null;
        _anchorDisplay = null;
        _redraw();
        return;
      case 'selectPin':
        final id = event['id'];
        _selectedPin = _pins.any((p) => p['id'] == id) ? id as int : null;
        _redraw();
        return;
      case 'deletePin':
        if (_selectedPin != null && _pins.any((p) => p['id'] == _selectedPin)) {
          _rememberPins();
          _pins.removeWhere((p) => p['id'] == _selectedPin);
          _selectedPin = null;
          _redraw();
        }
        return;
      case 'undoPins':
        if (_pinUndo.isNotEmpty) {
          _pins
            ..clear()
            ..addAll(_pinUndo.removeLast());
          _selectedPin = null;
          _redraw();
        }
        return;
      case 'exportPins':
        unawaited(
          _exportPins(event['displayId'] as int, save: event['save'] == true),
        );
        return;
      case 'modeChanged':
        final next = RulerMode.values
            .where((m) => m.name == event['tool'])
            .firstOrNull;
        if (_tool != 'picker' && next != null) {
          _tool = next.name;
          mode = next;
          _editingPins = false;
          _anchor = null;
          _anchorDisplay = null;
          _keyboardRectangle = false;
          _persist();
          _redraw();
          _notify();
        }
        return;
      case 'scroll':
        final steps = (event['steps'] as int).clamp(-32, 32);
        if (_tool == 'picker') {
          zoom = CaptureControls.adjustZoom(zoom, steps);
        } else if (_tool != 'rectangle') {
          tolerance = CaptureControls.adjustTolerance(tolerance, steps);
        }
        _persist();
        _redraw();
        _notify();
        return;
      case 'nudge':
        final position = _lastPointer;
        if (position == null) return;
        final display = _session!.displays
            .where((d) => d.id == position.displayId)
            .first;
        final next = CaptureControls.nudge(
          display.frame,
          position.x,
          position.y,
          (event['dx'] as int).clamp(-1, 1),
          (event['dy'] as int).clamp(-1, 1),
        );
        _pointer({
          'displayId': position.displayId,
          'x': next.x,
          'y': next.y,
          'phase': 'move',
          'keyboard': true,
        });
        return;
      case 'confirm':
        final position = _lastPointer;
        if (position == null) return;
        final start = _tool == 'rectangle' && _anchor == null;
        _pointer({
          'displayId': position.displayId,
          'x': position.x,
          'y': position.y,
          'phase': start ? 'down' : 'up',
          'keep': event['keep'] == true,
          'keyboard': true,
        });
        return;
      case 'clearPins':
        if (_pins.isNotEmpty) _rememberPins();
        _selectedPin = null;
        _pins.clear();
        _redraw();
        return;
      case 'pointer':
        _pointer(event);
        return;
    }
  }

  Map<String, Object?> get _overlayOptions => {
    'sessionId': _session!.id,
    'tool': _tool,
    'tolerance': tolerance,
    'zoom': zoom,
    'continuous': continuousPicker,
    'pickedCount': _pickedCount,
    'selectedPin': _selectedPin,
    'editingPins': _editingPins,
    'canUndoPins': _pinUndo.isNotEmpty,
    'pinned': List<Map<String, Object?>>.of(_pins),
  };

  void _redraw() {
    final pointer = _lastPointer;
    if (pointer == null) {
      if (_session != null) _updateOverlay(_overlayOptions);
    } else {
      _pointer({
        'displayId': pointer.displayId,
        'x': pointer.x,
        'y': pointer.y,
        'phase': 'move',
        'keyboard': _keyboardCursor,
      });
    }
  }

  void _updateOverlay(Map<String, Object?> data) {
    unawaited(
      desktop.updateOverlay(data).catchError((Object e) {
        unawaited(_abort(e));
      }),
    );
  }

  void _pointer(Map<Object?, Object?> event) {
    if (_session == null || _committing) return;
    final display = _session!.displays
        .where((d) => d.id == event['displayId'])
        .firstOrNull;
    if (display == null) return;
    final x = (event['x'] as num).toDouble();
    final y = (event['y'] as num).toDouble();
    if (!x.isFinite || !y.isFinite) return;
    _lastPointer = (displayId: display.id, x: x, y: y);
    _keyboardCursor = event['keyboard'] == true;
    final phase = event['phase'] as String;
    final frame = display.frame;
    final pixel = frame.logicalToPixel(x, y);
    final color = frame.pixelAt(pixel.x, pixel.y);
    RulerMeasurement? measurement;
    if (_tool == RulerMode.rectangle.name) {
      if (phase == 'down') {
        _keyboardRectangle = event['keyboard'] == true;
        _anchor = _keyboardRectangle ? pixel : frame.logicalToBoundary(x, y);
        _anchorDisplay = display.id;
      }
      if (_anchor != null && _anchorDisplay == display.id) {
        measurement = RulerMeasurement.fromRect(
          frame,
          PixelRect.fromPoints(
            _anchor!,
            (_keyboardRectangle || event['keyboard'] == true)
                ? pixel
                : frame.logicalToBoundary(x, y),
          ),
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
    _updateOverlay({
      ..._overlayOptions,
      'displayId': display.id,
      'x': x,
      'y': y,
      'label': label,
      'color': color.toJson(),
      'rect': measurement?.rect.toJson(),
      'keyboard': event['keyboard'] == true,
      'anchored': _anchor != null,
    });
    if (phase != 'up' || _editingPins) return;
    if (_tool == 'picker') {
      unawaited(_commitColor(color));
    } else if (measurement != null &&
        measurement.rect.width > 0 &&
        measurement.rect.height > 0) {
      unawaited(
        _commitMeasurement(
          measurement,
          display,
          keep: _tool == 'rectangle' && event['keep'] == true,
        ),
      );
    } else {
      _anchor = null;
      _anchorDisplay = null;
    }
  }

  Future<void> _commitColor(RgbColor color) async {
    final sessionId = _session!.id;
    _committing = true;
    selectedColor = color;
    _rememberColor(color);
    _pickedCount++;
    if (continuousPicker) {
      try {
        await desktop.writeClipboard(color.formatted(format));
        if (_session?.id == sessionId) {
          notice = '已连续取色 $_pickedCount 次，Esc 结束';
          error = null;
        }
      } catch (e) {
        if (_session?.id == sessionId) error = '颜色已保存，但复制失败：${_message(e)}';
      } finally {
        if (_session?.id == sessionId) {
          _committing = false;
          _redraw();
        }
        _persist();
        _notify();
      }
    } else {
      await _complete(color.formatted(format));
    }
  }

  Future<void> _commitMeasurement(
    RulerMeasurement measurement,
    CapturedDisplay display, {
    bool keep = false,
  }) async {
    final sessionId = _session!.id;
    _committing = true;
    _measurements.insert(
      0,
      MeasurementRecord(
        measurement: measurement,
        createdAt: DateTime.now(),
        displayName: display.name,
      ),
    );
    if (_measurements.length > 32) _measurements.removeLast();
    if (keep) {
      _rememberPins();
      _pins.add({
        'id': ++_nextPinId,
        'displayId': display.id,
        'rect': measurement.rect.toJson(),
        'label': measurement.pixelLabel,
      });
      _anchor = null;
      _anchorDisplay = null;
      _keyboardRectangle = false;
      try {
        await desktop.writeClipboard(measurement.label);
        if (_session?.id == sessionId) {
          notice = '已保留 ${_pins.length} 个测量框，并复制尺寸';
        }
      } catch (e) {
        if (_session?.id == sessionId) error = '标注已保留，但复制失败：${_message(e)}';
      } finally {
        if (_session?.id == sessionId) {
          _committing = false;
          _redraw();
        }
        _persist();
        _notify();
      }
    } else {
      await _complete(measurement.label);
    }
  }

  void _rememberPins() {
    _pinUndo.add(List<Map<String, Object?>>.of(_pins));
    if (_pinUndo.length > 64) _pinUndo.removeAt(0);
  }

  Future<void> _exportPins(int displayId, {required bool save}) async {
    final session = _session;
    if (session == null || _committing) return;
    final selected = _pins
        .where((p) => p['id'] == _selectedPin && p['displayId'] == displayId)
        .toList();
    final pins = selected.isNotEmpty
        ? selected
        : _pins.where((p) => p['displayId'] == displayId).toList();
    if (pins.isEmpty) return;
    _committing = true;
    try {
      final done = await desktop.exportAnnotations(
        session.id,
        displayId,
        pins,
        save: save,
      );
      if (done) {
        notice = save ? '标注图片已导出' : '标注图片已复制';
        error = null;
      }
    } catch (e) {
      _fail('标注图片导出失败：${_message(e)}');
    } finally {
      if (_session?.id == session.id) {
        _committing = false;
        _redraw();
      }
      _notify();
    }
  }

  Future<void> _complete(String text) async {
    final id = _session?.id;
    try {
      await desktop.writeClipboard(text);
      if (_session?.id == id) notice = '已复制 $text';
    } catch (e) {
      if (_session?.id == id) error = '结果已保存，但复制失败：${_message(e)}';
    } finally {
      try {
        if (id != null) await desktop.finish(id);
      } catch (e) {
        if (_session?.id == id) error = '无法关闭测量浮层，请按 Esc：${_message(e)}';
      }
      if (_session?.id == id) _resetSession();
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
    _pins.clear();
    _pinUndo.clear();
    _selectedPin = null;
    _editingPins = false;
    _pickedCount = 0;
    _lastPointer = null;
    _keyboardRectangle = false;
    _keyboardCursor = false;
  }

  Future<bool> beginShortcutRecording() async {
    if (busy || initializing || recordingShortcut || savingShortcuts) {
      return false;
    }
    try {
      if (!await desktop.setShortcutRecording(true)) return false;
      recordedShortcut = null;
      recordingShortcut = true;
      _notify();
      return true;
    } catch (e) {
      _fail(_message(e));
      return false;
    }
  }

  Future<void> endShortcutRecording() async {
    try {
      shortcutsAvailable = await desktop.setShortcutRecording(false);
    } catch (e) {
      _fail(_message(e));
    } finally {
      recordingShortcut = false;
      _notify();
    }
  }

  Future<bool> setShortcut(bool picker, ShortcutChord chord) async {
    if (busy || savingShortcuts || recordingShortcut) return false;
    final candidate = ShortcutBindings(
      picker: picker ? chord : shortcuts.picker,
      ruler: picker ? shortcuts.ruler : chord,
    );
    if (!candidate.isValid) {
      _fail('快捷键需要字母或数字、至少一个主修饰键，且两个工具不能重复。');
      return false;
    }
    savingShortcuts = true;
    _notify();
    try {
      final registered = await desktop.configureShortcuts(candidate);
      if (!registered) {
        _fail('快捷键注册失败，已保留原配置。');
        return false;
      }
      shortcuts = candidate;
      shortcutsAvailable = true;
      error = null;
      notice = '快捷键已更新';
      _persist();
      return true;
    } catch (e) {
      if (e is PlatformException && e.details is Map) {
        final status = (e.details as Map)['shortcuts'];
        if (status is bool) shortcutsAvailable = status;
      }
      _fail(_message(e));
      return false;
    } finally {
      savingShortcuts = false;
      _notify();
    }
  }

  void setContinuousPicker(bool value) {
    continuousPicker = value;
    _persist();
    if (_session != null) _redraw();
    _notify();
  }

  void _rememberColor(RgbColor color) {
    _colors.remove(color);
    _colors.insert(0, color);
    if (_colors.length > 64) _colors.removeLast();
  }

  void addEditedColor(RgbColor color) {
    selectedColor = color;
    _rememberColor(color);
    _persist();
    _notify();
  }

  PaletteEntry? paletteEntry(RgbColor color) =>
      _palette.where((e) => e.color == color).firstOrNull;
  void savePaletteColor(RgbColor color, {String? name, bool? favorite}) {
    final old = paletteEntry(color);
    final entry = PaletteEntry(
      color: color,
      name: name?.trim() ?? old?.name ?? '',
      favorite: favorite ?? old?.favorite ?? false,
    );
    final index = _palette.indexWhere((e) => e.color == color);
    if (index < 0) {
      _palette.add(entry);
    } else {
      _palette[index] = entry;
    }
    _persist();
    _notify();
  }

  void removeRecentColor(RgbColor color) {
    _colors.remove(color);
    _persist();
    _notify();
  }

  void removePaletteColor(RgbColor color) {
    _palette.removeWhere((e) => e.color == color);
    _persist();
    _notify();
  }

  Future<void> exportColors(PaletteExport format, {required bool saved}) async {
    final entries = saved
        ? List<PaletteEntry>.of(_palette)
        : _colors
              .map((c) => paletteEntry(c) ?? PaletteEntry(color: c))
              .toList();
    if (entries.isEmpty) return;
    try {
      if (await desktop.saveTextFile(
        'fruler-${saved ? 'palette' : 'recent'}.${format.name}',
        exportPalette(entries, format),
      )) {
        notice = '颜色已导出';
        error = null;
        _notify();
      }
    } catch (e) {
      _fail('颜色导出失败：${_message(e)}');
    }
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
      'zoom': zoom,
      'continuousPicker': continuousPicker,
      'palette': _palette.map((e) => e.toJson()).toList(),
      'shortcuts': shortcuts.toJson(),
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
      try {
        if (data['shortcuts'] != null) {
          shortcuts = ShortcutBindings.fromJson(data['shortcuts']);
        }
      } catch (_) {
        notice = '快捷键配置无效，已恢复默认值。';
      }
      continuousPicker = data['continuousPicker'] == true;
      for (final value in (data['palette'] as List? ?? [])) {
        try {
          final entry = PaletteEntry.fromJson(value);
          if (!_palette.any((e) => e.color == entry.color)) _palette.add(entry);
        } catch (_) {
          /* Preserve other palette entries. */
        }
      }
      final savedZoom = data['zoom'];
      if (savedZoom is int && CaptureControls.zoomLevels.contains(savedZoom)) {
        zoom = savedZoom;
      }
      final value = data['tolerance'];
      if (value is int) tolerance = value.clamp(0, 255);
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
        'shortcut_conflict' => '快捷键已被占用，已尝试恢复原配置。',
        'shortcut_invalid' => e.message ?? '此快捷键不可用，请使用其他组合。',
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
