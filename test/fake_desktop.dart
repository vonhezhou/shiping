import 'dart:async';
import 'dart:typed_data';

import 'package:fruler/core/core.dart';
import 'package:fruler/platform/desktop_service.dart';

class FakeDesktop extends DesktopService {
  final input = StreamController<Map<Object?, Object?>>.broadcast(sync: true);
  String? saved;
  String? clipboard;
  int beginCalls = 0;
  int finishCalls = 0;
  int? finishedSession;
  bool permission = true;
  Object? beginError;
  Object? clipboardError;
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
  }) => input.add({
    'type': 'pointer',
    'sessionId': session,
    'displayId': display,
    'x': x,
    'y': y,
    'phase': phase,
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
  }

  @override
  Future<bool> requestPermission() async => permission;
  @override
  Future<void> openPrivacySettings() async {}
}
