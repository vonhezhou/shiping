import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/core.dart';
import 'image_document.dart';

class DesktopStatus {
  const DesktopStatus({
    required this.permission,
    required this.shortcuts,
    this.supported = true,
  });
  final bool permission;
  final bool shortcuts;
  final bool supported;
}

class CapturedDisplay {
  const CapturedDisplay({
    required this.id,
    required this.name,
    required this.frame,
  });
  final int id;
  final String name;
  final PixelFrame frame;
}

class CaptureSession {
  const CaptureSession(this.id, this.displays);
  final int id;
  final List<CapturedDisplay> displays;
}

/// Platform boundary: Windows/Linux implementations can replace this adapter.
abstract class DesktopService {
  static DesktopService create() =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS
      ? MacDesktopService()
      : UnsupportedDesktopService();

  Stream<Map<Object?, Object?>> get events;
  Future<DesktopStatus> initialize();
  Future<bool> requestPermission();
  Future<void> openPrivacySettings();
  Future<CaptureSession> begin(String tool);
  Future<void> updateOverlay(Map<String, Object?> data);
  Future<void> finish(int sessionId);
  Future<String?> loadState();
  Future<void> saveState(String json);
  Future<void> writeClipboard(String text);
  Future<String?> openPaletteFile();
  Future<ImageFileData?> openImageFile();
  Future<ImageProjectFileData?> openProjectFile();
  Future<bool> saveProjectFile(String text);
  Future<void> replyToQuit(bool allow) async {}
  Future<bool> exportImage(Uint8List png, {required bool save});
  Future<bool> saveTextFile(String filename, String text);
  Future<bool> exportAnnotations(
    int sessionId,
    int displayId,
    List<Map<String, Object?>> annotations, {
    required bool save,
  });
  Future<bool> configureShortcuts(ShortcutBindings bindings);
  Future<bool> setShortcutRecording(bool recording);
}

class MacDesktopService implements DesktopService {
  static const _methods = MethodChannel('dev.fruler/desktop');
  static const _events = EventChannel('dev.fruler/events');
  late final Stream<Map<Object?, Object?>> _stream = _events
      .receiveBroadcastStream()
      .map((event) => Map<Object?, Object?>.from(event as Map));

  @override
  Stream<Map<Object?, Object?>> get events => _stream;

  @override
  Future<DesktopStatus> initialize() async {
    final value = await _methods.invokeMapMethod<String, Object?>('initialize');
    return DesktopStatus(
      permission: value?['permission'] == true,
      shortcuts: value?['shortcuts'] == true,
    );
  }

  @override
  Future<bool> requestPermission() async =>
      await _methods.invokeMethod<bool>('requestPermission') ?? false;
  @override
  Future<void> openPrivacySettings() =>
      _methods.invokeMethod<void>('openPrivacySettings');

  @override
  Future<CaptureSession> begin(String tool) async {
    final data = await _methods.invokeMapMethod<String, Object?>('begin', {
      'tool': tool,
    });
    if (data == null) throw const FormatException('Empty capture response');
    final displays = (data['frames'] as List).map((value) {
      final v = Map<Object?, Object?>.from(value as Map);
      return CapturedDisplay(
        id: v['id'] as int,
        name: v['name'] as String? ?? '显示器 ${v['id']}',
        frame: PixelFrame(
          width: v['width'] as int,
          height: v['height'] as int,
          rgba: v['rgba'] as Uint8List,
          logicalWidth: (v['logicalWidth'] as num).toDouble(),
          logicalHeight: (v['logicalHeight'] as num).toDouble(),
        ),
      );
    }).toList();
    if (displays.isEmpty) throw const FormatException('No displays available');
    return CaptureSession(data['sessionId'] as int, displays);
  }

  @override
  Future<void> updateOverlay(Map<String, Object?> data) =>
      _methods.invokeMethod<void>('updateOverlay', data);
  @override
  Future<void> finish(int sessionId) =>
      _methods.invokeMethod<void>('finish', {'sessionId': sessionId});
  @override
  Future<String?> loadState() => _methods.invokeMethod<String>('loadState');
  @override
  Future<void> saveState(String json) =>
      _methods.invokeMethod<void>('saveState', {'json': json});
  @override
  Future<void> writeClipboard(String text) =>
      Clipboard.setData(ClipboardData(text: text));

  @override
  Future<ImageProjectFileData?> openProjectFile() async {
    final data = await _methods.invokeMapMethod<String, Object?>(
      'openProjectFile',
    );
    return data == null
        ? null
        : ImageProjectFileData(data['name'] as String, data['text'] as String);
  }

  @override
  Future<bool> saveProjectFile(String text) async =>
      await _methods.invokeMethod<bool>('saveProjectFile', {'text': text}) ??
      false;
  @override
  Future<void> replyToQuit(bool allow) =>
      _methods.invokeMethod<void>('replyToQuit', {'allow': allow});
  @override
  Future<ImageFileData?> openImageFile() async {
    final data = await _methods.invokeMapMethod<String, Object?>(
      'openImageFile',
    );
    return data == null
        ? null
        : ImageFileData(data['name'] as String, data['bytes'] as Uint8List);
  }

  @override
  Future<bool> exportImage(Uint8List png, {required bool save}) async =>
      await _methods.invokeMethod<bool>('exportImage', {
        'png': png,
        'save': save,
      }) ??
      false;
  @override
  Future<String?> openPaletteFile() async =>
      await _methods.invokeMethod<String>('openPaletteFile');
  @override
  Future<bool> saveTextFile(String filename, String text) async =>
      await _methods.invokeMethod<bool>('saveTextFile', {
        'filename': filename,
        'text': text,
      }) ??
      false;
  @override
  Future<bool> exportAnnotations(
    int sessionId,
    int displayId,
    List<Map<String, Object?>> annotations, {
    required bool save,
  }) async =>
      await _methods.invokeMethod<bool>('exportAnnotations', {
        'sessionId': sessionId,
        'displayId': displayId,
        'annotations': annotations,
        'save': save,
      }) ??
      false;
  @override
  Future<bool> configureShortcuts(ShortcutBindings bindings) async =>
      await _methods.invokeMethod<bool>(
        'configureShortcuts',
        bindings.toJson(),
      ) ??
      false;
  @override
  Future<bool> setShortcutRecording(bool recording) async =>
      await _methods.invokeMethod<bool>('setShortcutRecording', {
        'recording': recording,
      }) ??
      false;
}

class UnsupportedDesktopService implements DesktopService {
  @override
  Future<void> replyToQuit(bool allow) async {}
  @override
  Future<ImageProjectFileData?> openProjectFile() async => null;
  @override
  Future<bool> saveProjectFile(String text) async => false;
  @override
  Future<ImageFileData?> openImageFile() async => null;
  @override
  Future<bool> exportImage(Uint8List png, {required bool save}) async => false;
  @override
  Future<String?> openPaletteFile() async => null;
  @override
  Future<bool> saveTextFile(String filename, String text) async => false;
  @override
  Future<bool> exportAnnotations(
    int sessionId,
    int displayId,
    List<Map<String, Object?>> annotations, {
    required bool save,
  }) async => false;
  @override
  Future<bool> configureShortcuts(ShortcutBindings bindings) async => false;
  @override
  Future<bool> setShortcutRecording(bool recording) async => false;
  @override
  Stream<Map<Object?, Object?>> get events => const Stream.empty();
  @override
  Future<DesktopStatus> initialize() async => const DesktopStatus(
    permission: false,
    shortcuts: false,
    supported: false,
  );
  @override
  Future<CaptureSession> begin(String tool) async =>
      throw UnsupportedError('当前版本仅支持 macOS 14 及以上');
  @override
  Future<bool> requestPermission() async => false;
  @override
  Future<void> openPrivacySettings() async {}
  @override
  Future<void> updateOverlay(Map<String, Object?> data) async {}
  @override
  Future<void> finish(int sessionId) async {}
  @override
  Future<String?> loadState() async => null;
  @override
  Future<void> saveState(String json) async {}
  @override
  Future<void> writeClipboard(String text) =>
      Clipboard.setData(ClipboardData(text: text));
}
