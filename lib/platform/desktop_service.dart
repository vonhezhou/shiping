import 'dart:async';
import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';

import '../core/core.dart';
import 'desktop.g.dart' as wire;
import 'desktop_protocol.dart';
import 'native_pixel_buffer.dart';

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
  Locale get systemLocale => PlatformDispatcher.instance.locale;
  Future<void> configureLocale(String languageCode) async {}
  Future<List<String>> availableFontFamilies() async => [];
  Future<int?> pickAnnotationColor(int initialColor) async => null;
  Future<DesktopStatus> initialize();
  Future<bool> requestPermission();
  Future<void> openPrivacySettings();
  Future<void> showMainWindow();
  Future<CaptureSession> begin(String tool);
  Future<void> updateOverlay(Map<String, Object?> data);
  Future<void> finish(int sessionId);
  Future<void> editScreenshot(int sessionId, int displayId) async {}
  Future<void> reselectScreenshot(int sessionId) async {}
  Future<String?> loadState();
  Future<void> saveState(String json);
  Future<void> writeClipboard(String text);
  Future<String?> openPaletteFile();
  Future<void> replyToQuit(bool allow) async {}
  Future<bool> exportImage(Uint8List png, {required bool save});
  Future<void> pinImage(
    Uint8List png, {
    int? sessionId,
    int? displayId,
    PixelRect? rect,
  }) async => throw UnsupportedError('platform_unsupported');
  Future<void> pinClipboard() async =>
      throw UnsupportedError('platform_unsupported');
  Future<void> togglePinnedImages() async {}
  Future<void> closePinnedImages() async {}
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

class MacDesktopService extends DesktopService {
  MacDesktopService({PixelFrame Function(wire.DisplayFrame)? readFrame})
    : _readFrame = readFrame ?? NativePixelBuffers.read {
    wire.DesktopFlutterApi.setUp(_NativeCallbacks(_events));
  }
  final PixelFrame Function(wire.DisplayFrame) _readFrame;
  static final _logger = Logger('platform.desktop');
  final _api = wire.DesktopHostApi();
  @override
  Locale get systemLocale => PlatformDispatcher.instance.locale;
  @override
  Future<void> configureLocale(String languageCode) =>
      _api.configureLocale(languageCode);
  @override
  Future<int?> pickAnnotationColor(int initialColor) =>
      _api.pickAnnotationColor(initialColor);
  @override
  Future<List<String>> availableFontFamilies() => _api.availableFontFamilies();
  final _events = StreamController<Map<Object?, Object?>>.broadcast();
  @override
  Stream<Map<Object?, Object?>> get events => _events.stream;
  @override
  Future<DesktopStatus> initialize() async {
    final status = await _api.initialize();
    return DesktopStatus(
      permission: status.permission,
      shortcuts: status.shortcuts,
    );
  }

  @override
  Future<bool> requestPermission() => _api.requestPermission();
  @override
  Future<void> openPrivacySettings() => _api.openPrivacySettings();
  @override
  Future<void> showMainWindow() => _api.showMainWindow();
  @override
  Future<CaptureSession> begin(String tool) async {
    final nativeTool = wire.CaptureTool.values
        .where((value) => value.name == tool)
        .firstOrNull;
    if (nativeTool == null) {
      throw PlatformException(code: 'invalid_tool');
    }
    final reply = await _api.begin(nativeTool);
    try {
      if (reply.displays.isEmpty) {
        throw const FormatException('No displays available');
      }
      return CaptureSession(reply.sessionId, [
        for (final d in reply.displays)
          CapturedDisplay(id: d.id, name: d.name, frame: _readFrame(d)),
      ]);
    } catch (error, stackTrace) {
      _logger.warning(
        'Capture frame acquisition failed: session=${reply.sessionId}, '
        'errorType=${error.runtimeType}.',
        null,
        stackTrace,
      );
      // Don't strand native overlays if decoding/acquiring any display fails.
      try {
        await _api.finish(reply.sessionId);
      } catch (error, stackTrace) {
        _logger.warning(
          'Capture acquisition cleanup failed: session=${reply.sessionId}, '
          'errorType=${error.runtimeType}.',
          null,
          stackTrace,
        );
      }
      rethrow;
    }
  }

  @override
  Future<void> updateOverlay(Map<String, Object?> data) =>
      _api.updateOverlay(overlayToWire(data));
  @override
  Future<void> finish(int sessionId) => _api.finish(sessionId);
  @override
  Future<void> editScreenshot(int sessionId, int displayId) =>
      _api.editScreenshot(sessionId, displayId);
  @override
  Future<void> reselectScreenshot(int sessionId) =>
      _api.reselectScreenshot(sessionId);
  @override
  Future<String?> loadState() => _api.loadState();
  @override
  Future<void> saveState(String json) => _api.saveState(json);
  @override
  Future<void> writeClipboard(String text) =>
      Clipboard.setData(ClipboardData(text: text));
  @override
  Future<String?> openPaletteFile() => _api.openPaletteFile();
  @override
  Future<void> replyToQuit(bool allow) => _api.replyToQuit(allow);
  @override
  Future<bool> exportImage(Uint8List png, {required bool save}) =>
      _api.exportImage(png, save);
  @override
  Future<void> pinImage(
    Uint8List png, {
    int? sessionId,
    int? displayId,
    PixelRect? rect,
  }) => _api.pinImage(
    png,
    sessionId,
    displayId,
    rect == null ? null : boundsToWire(rect.toJson()),
  );
  @override
  Future<void> pinClipboard() => _api.pinClipboard();
  @override
  Future<void> togglePinnedImages() => _api.togglePinnedImages();
  @override
  Future<void> closePinnedImages() => _api.closePinnedImages();
  @override
  Future<bool> saveTextFile(String filename, String text) =>
      _api.saveTextFile(filename, text);
  @override
  Future<bool> exportAnnotations(
    int sessionId,
    int displayId,
    List<Map<String, Object?>> annotations, {
    required bool save,
  }) => _api.exportAnnotations(
    sessionId,
    displayId,
    annotations.map(pinToWire).toList(),
    save,
  );
  @override
  Future<bool> configureShortcuts(ShortcutBindings bindings) =>
      _api.configureShortcuts(
        wire.NativeBindings(
          picker: chordToWire(bindings.picker),
          ruler: chordToWire(bindings.ruler),
          screenshot: chordToWire(bindings.screenshot),
          pinClipboard: chordToWire(bindings.pinClipboard),
          togglePins: chordToWire(bindings.togglePins),
        ),
      );
  @override
  Future<bool> setShortcutRecording(bool recording) =>
      _api.setShortcutRecording(recording);
}

class _NativeCallbacks implements wire.DesktopFlutterApi {
  _NativeCallbacks(this.events);
  final StreamController<Map<Object?, Object?>> events;
  @override
  void onEvent(wire.NativeEvent event) => events.add(eventFromWire(event));
  @override
  void onLog(wire.NativeLogEntry entry) {
    final level =
        Level.LEVELS.where((l) => l.value == entry.level).firstOrNull ??
        Level('NATIVE', entry.level);
    Logger('native.${entry.category}').log(level, entry.message);
  }
}

class UnsupportedDesktopService extends DesktopService {
  @override
  Future<void> showMainWindow() async {}
  @override
  Future<void> replyToQuit(bool allow) async {}
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
      throw UnsupportedError('platform_unsupported');
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
