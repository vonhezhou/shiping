import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/platform/desktop.g.dart',
    swiftOut: 'macos/Runner/Desktop.g.swift',
    dartPackageName: 'fruler',
  ),
)
enum CaptureTool {
  picker,
  rectangle,
  horizontal,
  vertical,
  cross,
  screenshot,
  recording,
}

enum EventKind {
  activate,
  showHistory,
  showSettings,
  permissionChanged,
  shortcutRecorded,
  cancelled,
  continuousChanged,
  pinDrag,
  copyMeasurement,
  editPins,
  selectPin,
  deletePin,
  undoPins,
  redoPins,
  exportPins,
  modeChanged,
  toleranceChanged,
  scroll,
  nudge,
  confirm,
  clearPins,
  pointer,
  sampleColor,
  copyCaptureSize,
  pinClipboard,
  togglePinnedImages,
  closePinnedImages,
  stopRecording,
  recordingFailed,
}

enum InputPhase { move, down, drag, up, start, update, end }

enum MouseButton { primary, secondary, middle }

class NativeStatus {
  NativeStatus({required this.permission, required this.shortcuts});
  bool permission;
  bool shortcuts;
}

class RecordingConfiguration {
  RecordingConfiguration({
    required this.codec,
    required this.frameRate,
    required this.quality,
    required this.resolution,
    required this.showCursor,
    required this.systemAudio,
  });
  String codec;
  int frameRate;
  String quality;
  String resolution;
  bool showCursor;
  bool systemAudio;
}

class DisplayFrame {
  DisplayFrame({
    required this.id,
    required this.name,
    required this.width,
    required this.height,
    required this.logicalWidth,
    required this.logicalHeight,
    required this.bufferId,
    required this.byteLength,
    required this.rowBytes,
  });
  int id;
  String name;
  int width;
  int height;
  double logicalWidth;
  double logicalHeight;
  int bufferId;
  int byteLength;
  int rowBytes;
}

class CaptureReply {
  CaptureReply({required this.sessionId, required this.displays});
  int sessionId;
  List<DisplayFrame> displays;
}

class PixelBounds {
  PixelBounds({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });
  int left;
  int top;
  int right;
  int bottom;
}

class NativeColor {
  NativeColor({required this.red, required this.green, required this.blue});
  int red;
  int green;
  int blue;
}

class NativeChord {
  NativeChord({
    required this.key,
    required this.meta,
    required this.control,
    required this.alt,
    required this.shift,
  });
  String key;
  bool meta;
  bool control;
  bool alt;
  bool shift;
}

class NativeBindings {
  NativeBindings({
    required this.picker,
    required this.ruler,
    required this.screenshot,
    required this.pinClipboard,
    required this.togglePins,
  });
  NativeChord picker;
  NativeChord ruler;
  NativeChord screenshot;
  NativeChord pinClipboard;
  NativeChord togglePins;
}

class MeasurementPin {
  MeasurementPin({
    required this.id,
    required this.displayId,
    required this.rect,
    required this.label,
  });
  int id;
  int displayId;
  PixelBounds rect;
  String label;
}

class OverlayState {
  OverlayState({
    required this.sessionId,
    required this.tool,
    required this.tolerance,
    required this.zoom,
    required this.continuous,
    required this.pickerActions,
    required this.capturePurpose,
    required this.pickedCount,
    this.selectedPin,
    required this.editingPins,
    required this.canUndoPins,
    required this.canRedoPins,
    required this.pinned,
    this.displayId,
    this.x,
    this.y,
    this.label,
    this.color,
    this.rect,
    this.keyboard,
    this.anchored,
    this.colorOutputName,
  });
  int sessionId;
  CaptureTool tool;
  int tolerance;
  int zoom;
  bool continuous;
  String pickerActions;
  String capturePurpose;
  int pickedCount;
  int? selectedPin;
  bool editingPins;
  bool canUndoPins;
  bool canRedoPins;
  List<MeasurementPin> pinned;
  int? displayId;
  double? x;
  double? y;
  String? label;
  NativeColor? color;
  PixelBounds? rect;
  bool? keyboard;
  bool? anchored;
  String? colorOutputName;
}

class NativeEvent {
  NativeEvent({
    required this.kind,
    this.sessionId,
    this.displayId,
    this.tool,
    this.permission,
    this.chord,
    this.x,
    this.y,
    this.phase,
    this.button,
    this.keep,
    this.keyboard,
    this.enabled,
    this.id,
    this.handle,
    this.dx,
    this.dy,
    this.resize,
    this.steps,
    this.tolerance,
    this.save,
    this.suggestedRect,
    this.message,
  });
  EventKind kind;
  int? sessionId;
  int? displayId;
  CaptureTool? tool;
  bool? permission;
  NativeChord? chord;
  double? x;
  double? y;
  InputPhase? phase;
  MouseButton? button;
  bool? keep;
  bool? keyboard;
  bool? enabled;
  int? id;
  String? handle;
  double? dx;
  double? dy;
  bool? resize;
  int? steps;
  int? tolerance;
  bool? save;
  PixelBounds? suggestedRect;
  String? message;
}

class NativeLogEntry {
  NativeLogEntry({
    required this.level,
    required this.category,
    required this.message,
  });
  int level;
  String category;
  String message;
}

@HostApi()
abstract class DesktopHostApi {
  @async
  void configureLocale(String languageCode);
  @async
  int? pickAnnotationColor(int initialColor);
  @async
  List<String> availableFontFamilies();
  @async
  NativeStatus initialize();
  @async
  bool requestPermission();
  @async
  void openPrivacySettings();
  @async
  void showMainWindow();
  @async
  CaptureReply begin(CaptureTool tool);
  @async
  void updateOverlay(OverlayState state);
  @async
  void finish(int sessionId);
  @async
  void startRecording(
    int sessionId,
    int displayId,
    PixelBounds rect,
    RecordingConfiguration options,
  );
  @async
  bool stopRecording();
  @async
  void cancelRecording();
  @async
  void editScreenshot(int sessionId, int displayId);
  @async
  void reselectScreenshot(int sessionId);
  @async
  List<String> recognizeQrCodes(int sessionId, int displayId, PixelBounds rect);
  @async
  String? loadState();
  @async
  void saveState(String json);
  @async
  String? openPaletteFile();
  @async
  void replyToQuit(bool allow);
  @async
  bool exportImage(Uint8List png, bool save);
  @async
  void pinImage(
    Uint8List png,
    int? sessionId,
    int? displayId,
    PixelBounds? rect,
  );
  @async
  void pinClipboard();
  @async
  void togglePinnedImages();
  @async
  void closePinnedImages();
  @async
  bool saveTextFile(String filename, String text);
  @async
  bool exportAnnotations(
    int sessionId,
    int displayId,
    List<MeasurementPin> annotations,
    bool save,
  );
  @async
  bool configureShortcuts(NativeBindings bindings);
  @async
  bool setShortcutRecording(bool recording);
}

@FlutterApi()
abstract class DesktopFlutterApi {
  void onEvent(NativeEvent event);
  void onLog(NativeLogEntry entry);
}
