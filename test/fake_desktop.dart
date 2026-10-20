import 'dart:async';
import 'dart:typed_data';

import 'package:fruler/core/core.dart';
import 'package:fruler/platform/desktop_service.dart';

class FakeDesktop extends DesktopService {
  final input = StreamController<Map<Object?, Object?>>.broadcast(sync: true);
  ShortcutBindings bindings = ShortcutBindings.defaults;
  bool recording = false;
  Object? shortcutError;
  @override
  Future<bool> configureShortcuts(ShortcutBindings value) async {
    if (shortcutError != null) throw shortcutError!;
    bindings = value;
    return true;
  }

  @override
  Future<bool> setShortcutRecording(bool value) async {
    recording = value;
    return true;
  }

  void event(String type, [Map<String, Object?> data = const {}]) =>
      input.add({'type': type, 'sessionId': 7, ...data});
  bool? quitAllowed;
  @override
  Future<void> replyToQuit(bool allow) async {
    quitAllowed = allow;
  }

  int showMainCalls = 0;
  @override
  Future<void> showMainWindow() async {
    showMainCalls++;
  }

  Uint8List? exportedImage;
  @override
  Future<bool> exportImage(Uint8List png, {required bool save}) async {
    exportedImage = png;
    return fileResult;
  }

  String? importText;
  @override
  Future<String?> openPaletteFile() async => importText;
  String? exportedName;
  String? exportedText;
  List<Map<String, Object?>>? exportedAnnotations;
  bool fileResult = true;
  Object? exportError;
  @override
  Future<bool> saveTextFile(String filename, String text) async {
    exportedName = filename;
    exportedText = text;
    return fileResult;
  }

  @override
  Future<bool> exportAnnotations(
    int sessionId,
    int displayId,
    List<Map<String, Object?>> annotations, {
    required bool save,
  }) async {
    if (exportError != null) throw exportError!;
    exportedAnnotations = annotations;
    return fileResult;
  }

  String? saved;
  String? clipboard;
  int beginCalls = 0;
  int finishCalls = 0;
  int? finishedSession;
  bool permission = true;
  Object? beginError;
  Object? clipboardError;
  Completer<void>? pendingClipboard;
  Completer<CaptureSession>? pendingCapture;
  Map<String, Object?>? lastOverlay;
  CaptureSession capture = CaptureSession(7, [
    CapturedDisplay(
      id: 1,
      name: '测试 Retina 显示器',
      frame: PixelFrame(
        width: 8,
        height: 6,
        logicalWidth: 4,
        logicalHeight: 3,
        rgba: Uint8List.fromList([
          for (var i = 0; i < 48; i++) ...[255, 0, 0, 255],
        ]),
      ),
    ),
  ]);
  @override
  Stream<Map<Object?, Object?>> get events => input.stream;
  @override
  Future<DesktopStatus> initialize() async =>
      DesktopStatus(permission: permission, shortcuts: true);
  @override
  Future<CaptureSession> begin(String tool) async {
    beginCalls++;
    if (beginError != null) throw beginError!;
    return pendingCapture == null ? capture : pendingCapture!.future;
  }

  void pointer({
    double x = 1,
    double y = 1,
    String phase = 'move',
    int session = 7,
    int display = 1,
    bool keep = false,
    String button = 'primary',
  }) => input.add({
    'type': 'pointer',
    'sessionId': session,
    'displayId': display,
    'x': x,
    'y': y,
    'phase': phase,
    'keep': keep,
    'button': button,
  });
  @override
  Future<void> updateOverlay(Map<String, Object?> data) async {
    lastOverlay = data;
  }

  @override
  Future<void> finish(int sessionId) async {
    finishCalls++;
    finishedSession = sessionId;
  }

  @override
  Future<String?> loadState() async => saved;
  @override
  Future<void> saveState(String json) async {
    saved = json;
  }

  @override
  Future<void> writeClipboard(String text) async {
    if (clipboardError != null) throw clipboardError!;
    clipboard = text;
    if (pendingClipboard != null) await pendingClipboard!.future;
  }

  @override
  Future<bool> requestPermission() async => permission;
  @override
  Future<void> openPrivacySettings() async {}
}
