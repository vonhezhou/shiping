import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';

import '../core/core.dart';
import '../l10n/app_language.dart';
import '../l10n/app_localizations.dart';
import '../platform/desktop_service.dart';
import '../platform/image_document.dart';
import '../platform/annotation_renderer.dart';

import 'screen_units.dart';

enum AppSection { picker, ruler, image, recording, settings }

class MeasurementRecord {
  const MeasurementRecord({
    required this.measurement,
    required this.createdAt,
    required this.displayName,
    this.name = '',
    this.favorite = false,
    this.imageSource = false,
  });
  final RulerMeasurement measurement;
  final DateTime createdAt;
  final String displayName;
  final String name;
  final bool favorite;
  final bool imageSource;
  double get scaleX => measurement.rect.width / measurement.logicalWidth;
  double get scaleY => measurement.rect.height / measurement.logicalHeight;
  MeasurementRecord copyWith({String? name, bool? favorite}) =>
      MeasurementRecord(
        measurement: measurement,
        createdAt: createdAt,
        displayName: displayName,
        name: name ?? this.name,
        favorite: favorite ?? this.favorite,
        imageSource: imageSource,
      );

  String get label => imageSource ? measurement.pixelLabel : measurement.label;

  Map<String, Object?> toJson() => {
    'rect': measurement.rect.toJson(),
    'mode': measurement.mode.name,
    'logicalWidth': measurement.logicalWidth,
    'logicalHeight': measurement.logicalHeight,
    'createdAt': createdAt.toIso8601String(),
    'displayName': displayName,
    'name': name,
    'favorite': favorite,
    'imageSource': imageSource,
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
      name: json['name'] is String ? json['name'] as String : '',
      favorite: json['favorite'] == true,
      imageSource: json['imageSource'] == true,
    );
  }
}

class AppController extends ChangeNotifier {
  AppController(this.desktop, {ImageDocumentCodec? imageCodec})
    : imageCodec = imageCodec ?? ImageDocumentCodec() {
    _systemLocale = desktop.systemLocale;
    _localeNotifier = ValueNotifier(AppLanguage.system.resolve(_systemLocale));
    markup.addListener(_notify);
  }
  static final _logger = Logger('app.controller');
  final DesktopService desktop;
  final ImageDocumentCodec imageCodec;
  AppLanguage _language = AppLanguage.system;
  late Locale _systemLocale;
  late final ValueNotifier<Locale> _localeNotifier;
  Future<void> _localeUpdate = Future<void>.value();
  Future<void>? _initialization;
  AppLanguage get language => _language;
  Locale get locale => _localeNotifier.value;
  ValueListenable<Locale> get localeChanges => _localeNotifier;
  AppLocalizations get strings => lookupAppLocalizations(locale);

  Future<void> setLanguage(AppLanguage language) =>
      _queueLocaleUpdate(() => _changeLanguage(language, _systemLocale));

  Future<void> updateSystemLocale(Locale systemLocale) =>
      _queueLocaleUpdate(() => _changeLanguage(_language, systemLocale));

  Future<void> _queueLocaleUpdate(Future<void> Function() action) {
    // 快速切换或系统通知到达时按顺序配置，避免较早的原生回复覆盖新偏好。
    final update = _localeUpdate.then((_) async {
      if (!_disposed) await action();
    });
    _localeUpdate = update.catchError((Object error, StackTrace stackTrace) {
      _logFailure('Language update', error, stackTrace);
    });
    return update;
  }

  Future<void> _changeLanguage(
    AppLanguage nextLanguage,
    Locale systemLocale,
  ) async {
    final nextLocale = nextLanguage.resolve(systemLocale);
    if (nextLanguage == _language && nextLocale == locale) {
      _systemLocale = systemLocale;
      return;
    }
    error = null;
    notice = null;
    final previousLocale = locale;
    try {
      if (nextLocale != previousLocale) {
        await desktop.configureLocale(nextLocale.languageCode);
      }
      if (_disposed) return;
      _language = nextLanguage;
      _systemLocale = systemLocale;
      _localeNotifier.value = nextLocale;
      _logger.info(
        'Application language changed: preference=${_language.name}, locale=${locale.languageCode}.',
      );
      _persist();
      if (_session != null) _redraw();
    } catch (error, stackTrace) {
      _logFailure('Native language configuration', error, stackTrace);
      // 配置可能在部分原生控件更新后失败，显式恢复旧语言以保持两端一致。
      try {
        await desktop.configureLocale(previousLocale.languageCode);
      } catch (restoreError, restoreStackTrace) {
        _logFailure(
          'Native language rollback',
          restoreError,
          restoreStackTrace,
        );
      }
      if (!_disposed) this.error = strings.msgLocaleChangeFailed;
    }
    _notify();
  }

  String pickerActionLabel(PickerMouseAction action) => switch (action) {
    PickerMouseAction.pickAndClose => strings.msgPickAndClose,
    PickerMouseAction.pickAndEdit => strings.msgPickAndEdit,
    PickerMouseAction.pickAndContinue => strings.msgPickAndContinue,
    PickerMouseAction.cancel => strings.msgCancelPicking,
  };
  final markup = AnnotationHistory();
  static const _annotationColorTools = {
    'rectangle',
    'ellipse',
    'line',
    'arrow',
    'pencil',
    'marker',
    'text',
  };
  final _annotationColors = <String, int>{};

  int annotationColor(String tool) => _annotationColors[tool] ?? 0xFFFF0000;

  void setAnnotationColor(String tool, int color) {
    if (!_annotationColorTools.contains(tool) ||
        color < 0 ||
        color > 0xFFFFFFFF ||
        annotationColor(tool) == color) {
      return;
    }
    _annotationColors[tool] = color;
    _persist();
    _notify();
  }

  ImageDocument? imageDocument;
  PixelRect? screenshotSelection;
  int? screenshotDisplayId;
  double screenshotScaleX = 1, screenshotScaleY = 1;
  bool get screenshotEditing =>
      screenshotSelection != null && imageDocument != null;
  bool imageLoading = false;
  bool get imageSaving => screenshotExporting || _screenshotCancelling;
  bool _screenshotCancelling = false;
  bool screenshotExporting = false;
  bool _recognizeQrCodeAfterSelection = false;
  bool qrCodeRecognizing = false;
  bool qrCodeCopying = false;
  bool get qrCodeBusy => qrCodeRecognizing || qrCodeCopying;
  List<String> _qrCodeResults = const [];
  List<String> get qrCodeResults => _qrCodeResults;
  int _qrCodeRequest = 0;

  void _clearQrCodes() {
    _qrCodeRequest++;
    _qrCodeResults = const [];
    qrCodeRecognizing = false;
    qrCodeCopying = false;
  }

  bool _isQrCodeRequestCurrent(int request, int sessionId) =>
      !_disposed &&
      _qrCodeRequest == request &&
      _session?.id == sessionId &&
      screenshotEditing;

  Future<void> recognizeQrCodes() async {
    if (!supports(DesktopFeature.qrCode)) return;
    final sessionId = _session?.id;
    final displayId = screenshotDisplayId;
    final rect = screenshotSelection;
    if (sessionId == null ||
        displayId == null ||
        rect == null ||
        !screenshotEditing ||
        imageLoading ||
        screenshotExporting ||
        _screenshotCancelling ||
        qrCodeBusy ||
        textMode) {
      return;
    }
    _clearQrCodes();
    final request = _qrCodeRequest;
    qrCodeRecognizing = true;
    error = null;
    _notify();
    try {
      // 原生端直接裁切冻结快照，不让标注或选区外的二维码参与识别。
      final results = await desktop.recognizeQrCodes(
        sessionId,
        displayId,
        rect,
      );
      if (!_isQrCodeRequestCurrent(request, sessionId)) return;
      _qrCodeResults = List.unmodifiable(
        results.where((v) => v.isNotEmpty).toSet(),
      );
      qrCodeRecognizing = false;
      if (_qrCodeResults.isEmpty) {
        error = strings.msgQrCodeNotFound;
      }
    } catch (e, stackTrace) {
      _logFailure('QR recognition', e, stackTrace);
      if (_isQrCodeRequestCurrent(request, sessionId)) {
        error = strings.msgQrCodeRecognitionFailed;
      }
    } finally {
      if (_isQrCodeRequestCurrent(request, sessionId)) {
        qrCodeRecognizing = false;
      }
      _notify();
    }
  }

  Future<void> copyQrCode(String value) async {
    final sessionId = _session?.id;
    if (sessionId == null ||
        !screenshotEditing ||
        qrCodeBusy ||
        !_qrCodeResults.contains(value)) {
      return;
    }
    final request = _qrCodeRequest;
    qrCodeCopying = true;
    error = null;
    _notify();
    try {
      await desktop.writeClipboard(value);
      if (!_isQrCodeRequestCurrent(request, sessionId)) return;
      await desktop.finish(sessionId);
      if (!_isQrCodeRequestCurrent(request, sessionId)) return;
      _resetSession();
      notice = strings.msgQrCodeCopied;
    } catch (e, stackTrace) {
      _logFailure('QR clipboard write', e, stackTrace);
      if (_isQrCodeRequestCurrent(request, sessionId)) {
        error = strings.msgQrCodeCopyFailed;
      }
    } finally {
      if (_isQrCodeRequestCurrent(request, sessionId)) qrCodeCopying = false;
      _notify();
    }
  }

  void dismissQrCodes() {
    if (qrCodeBusy) return;
    _clearQrCodes();
    error = null;
    _notify();
  }

  bool textMode = false, textRecognizing = false, textCopying = false;
  RecognizedTextDocument? recognizedText;
  int _textRequest = 0;

  void _clearText() {
    _textRequest++;
    textMode = false;
    textRecognizing = false;
    textCopying = false;
    recognizedText = null;
  }

  void dismissText() {
    if (textCopying) return;
    _clearText();
    error = null;
    _notify();
  }

  bool _isTextRequestCurrent(int request, int sessionId) =>
      !_disposed &&
      _textRequest == request &&
      _session?.id == sessionId &&
      screenshotEditing;

  Future<void> recognizeText() async {
    if (!supports(DesktopFeature.textRecognition)) return;
    final sessionId = _session?.id, displayId = screenshotDisplayId;
    final rect = screenshotSelection;
    if (sessionId == null ||
        displayId == null ||
        rect == null ||
        !screenshotEditing ||
        imageLoading ||
        imageSaving ||
        qrCodeBusy ||
        qrCodeResults.isNotEmpty ||
        textMode) {
      return;
    }
    _clearText();
    final request = _textRequest;
    textMode = textRecognizing = true;
    error = null;
    _notify();
    try {
      final lines = await desktop.recognizeText(sessionId, displayId, rect);
      if (!_isTextRequestCurrent(request, sessionId)) return;
      if (lines.isEmpty || lines.every((line) => line.text.isEmpty)) {
        _clearText();
        error = strings.msgTextNotFound;
      } else {
        recognizedText = RecognizedTextDocument(lines);
      }
    } catch (e) {
      // 识别内容与原生异常详情不写入日志。
      _logger.warning('Text recognition failed: type=${e.runtimeType}.');
      if (_isTextRequestCurrent(request, sessionId)) {
        _clearText();
        error = strings.msgTextRecognitionFailed;
      }
    } finally {
      if (_isTextRequestCurrent(request, sessionId)) textRecognizing = false;
      _notify();
    }
  }

  Future<void> copyRecognizedText({
    String? selectedText,
    bool finish = false,
  }) async {
    final sessionId = _session?.id;
    final value = finish ? recognizedText?.text : selectedText;
    if (sessionId == null ||
        !textMode ||
        textRecognizing ||
        textCopying ||
        recognizedText == null ||
        value == null ||
        value.isEmpty) {
      return;
    }
    final request = _textRequest;
    textCopying = true;
    error = null;
    _notify();
    try {
      await desktop.writeClipboard(value);
      if (!_isTextRequestCurrent(request, sessionId)) return;
      if (finish) {
        await desktop.finish(sessionId);
        if (!_isTextRequestCurrent(request, sessionId)) return;
        _resetSession();
      }
      notice = strings.msgTextCopied;
    } catch (e) {
      _logger.warning('Text copy failed: type=${e.runtimeType}.');
      if (_isTextRequestCurrent(request, sessionId)) {
        error = strings.msgTextCopyFailed;
      }
    } finally {
      if (_isTextRequestCurrent(request, sessionId)) textCopying = false;
      _notify();
    }
  }

  final List<Uint8List> _screenshots = [];
  List<Uint8List> get screenshots => List.unmodifiable(_screenshots);
  int _screenshotBytes = 0;

  ({int width, int height})? get screenshotSourceSize {
    final frame = _session?.displays
        .where((d) => d.id == screenshotDisplayId)
        .firstOrNull
        ?.frame;
    return frame == null ? null : (width: frame.width, height: frame.height);
  }

  bool get canAdjustScreenshotSelection =>
      screenshotEditing &&
      !imageLoading &&
      !imageSaving &&
      !qrCodeBusy &&
      !textMode;

  Future<void> adjustScreenshotSelection(PixelRect rect) async {
    final session = _session;
    if (session == null || !canAdjustScreenshotSelection) return;
    final display = session.displays.firstWhere(
      (d) => d.id == screenshotDisplayId,
    );
    if (rect.left < 0 ||
        rect.top < 0 ||
        rect.right > display.frame.width ||
        rect.bottom > display.frame.height ||
        rect.width < 1 ||
        rect.height < 1) {
      return;
    }
    _clearQrCodes();
    imageLoading = true;
    _notify();
    try {
      final doc = await imageCodec.cropCapture(display.frame, rect);
      if (_disposed || _session?.id != session.id || !screenshotEditing) return;
      final previous = screenshotSelection!;
      markup.translate(
        Offset(
          (previous.left - rect.left).toDouble(),
          (previous.top - rect.top).toDouble(),
        ),
      );
      imageDocument = doc;
      screenshotSelection = rect;
      error = null;
    } catch (e, stackTrace) {
      _logFailure('Screenshot selection adjustment', e, stackTrace);
      if (_session?.id == session.id) {
        error = strings.msgScreenshotSelectionFailed(describeError(e));
      }
    } finally {
      if (_session?.id == session.id) imageLoading = false;
      _notify();
    }
  }

  Future<void> pinScreenshot() => exportScreenshot(save: false, pin: true);

  Future<void> exportScreenshot({required bool save, bool pin = false}) async {
    if (pin && !supports(DesktopFeature.pinnedImages)) return;
    final doc = imageDocument;
    if (doc == null ||
        imageLoading ||
        screenshotExporting ||
        qrCodeBusy ||
        textMode ||
        qrCodeResults.isNotEmpty ||
        _screenshotCancelling ||
        !screenshotEditing) {
      return;
    }
    final sessionId = _session!.id;
    screenshotExporting = true;
    _notify();
    try {
      final png = await AnnotationRenderer.export(
        doc.frame,
        List.of(markup.items),
        loadImage: imageCodec.sourceImage,
      );
      if (_disposed || _session?.id != sessionId) return;
      if (pin) {
        await desktop.pinImage(
          png,
          sessionId: sessionId,
          displayId: screenshotDisplayId,
          rect: screenshotSelection,
        );
      } else if (!await desktop.exportImage(png, save: save)) {
        _logger.info(
          'Screenshot export cancelled: session=$sessionId, save=$save.',
        );
        return;
      }
      _logger.info(
        'Screenshot export completed: session=$sessionId, save=$save, pin=$pin.',
      );
      _screenshots.insert(0, png);
      _screenshotBytes += png.length;
      while (_screenshots.length > 12 || _screenshotBytes > 64 * 1024 * 1024) {
        _screenshotBytes -= _screenshots.removeLast().length;
      }
      await desktop.finish(sessionId);
      _resetSession();
      notice = pin
          ? strings.msgImagePinned
          : save
          ? strings.msgScreenshotSaved
          : strings.msgScreenshotCopied;
      error = null;
    } catch (e, stackTrace) {
      _logFailure('Screenshot export', e, stackTrace);
      _fail(strings.msgScreenshotExportFailed(describeError(e)));
    } finally {
      screenshotExporting = false;
      _notify();
    }
  }

  bool pinningImage = false;

  Future<void> _pinAction(Future<void> Function() action) async {
    if (!supports(DesktopFeature.pinnedImages)) return;
    if (busy ||
        pinningImage ||
        initializing ||
        recordingShortcut ||
        savingShortcuts ||
        _disposed) {
      return;
    }
    pinningImage = true;
    _notify();
    try {
      await action();
      error = null;
    } catch (e, stackTrace) {
      _logFailure('Pinned image action', e, stackTrace);
      _fail(describeError(e));
      // 菜单或全局快捷键失败时，让隐藏窗口中的错误也能被用户看到。
      try {
        await desktop.showMainWindow();
      } catch (windowError, windowStack) {
        _logFailure(
          'Pinned image error presentation',
          windowError,
          windowStack,
        );
      }
    } finally {
      pinningImage = false;
      _notify();
    }
  }

  Future<void> pinScreenshotFromHistory(Uint8List png) =>
      _pinAction(() => desktop.pinImage(png));
  Future<void> pinClipboard() => _pinAction(desktop.pinClipboard);
  Future<void> togglePinnedImages() => _pinAction(desktop.togglePinnedImages);
  Future<void> closePinnedImages() => _pinAction(desktop.closePinnedImages);

  Future<void> copyScreenshot(Uint8List png) async {
    try {
      await desktop.exportImage(png, save: false);
      _logger.info('Screenshot clipboard write completed.');
      notice = strings.msgCopiedScreenshot;
      _notify();
    } catch (e, stackTrace) {
      _logFailure('Screenshot clipboard write', e, stackTrace);
      _fail(describeError(e));
    }
  }

  Future<void> cancelScreenshot() async {
    if (screenshotExporting ||
        qrCodeCopying ||
        textCopying ||
        _screenshotCancelling) {
      return;
    }
    final id = _session?.id;
    _screenshotCancelling = true;
    // 取消意图立即生效，不能等原生关闭浮层后才丢弃已在途的识别回复。
    _clearQrCodes();
    _clearText();
    _notify();
    try {
      if (id != null) await desktop.finish(id);
      if (_session?.id == id) _resetSession();
    } catch (e, stackTrace) {
      _logFailure('Screenshot cancellation', e, stackTrace);
      if (_session?.id == id) error = strings.msgScreenshotCancelFailed;
    } finally {
      _screenshotCancelling = false;
      _notify();
    }
  }

  Future<void> reselectScreenshot() async {
    if (!screenshotEditing ||
        imageLoading ||
        imageSaving ||
        qrCodeBusy ||
        textMode) {
      return;
    }
    _clearQrCodes();
    await desktop.reselectScreenshot(_session!.id);
    imageDocument = null;
    screenshotSelection = null;
    screenshotDisplayId = null;
    markup.reset();
    _anchor = null;
    _anchorDisplay = null;
    _selectionPress = null;
    _pressedCandidate = null;
    _captureMeasurement = null;
    _redraw();
    _notify();
  }

  AppSection section = AppSection.settings;
  RgbColor selectedColor = const RgbColor(215, 250, 107);
  final List<RgbColor> _colors = [];
  final List<PaletteEntry> _palette = [];
  List<PaletteEntry> get palette => List.unmodifiable(_palette);
  final List<String> _paletteGroups = [];
  List<String> get paletteGroups => List.unmodifiable(_paletteGroups);
  String? selectedPaletteGroup;
  String paletteQuery = '';
  List<PaletteEntry> get visiblePalette => _palette
      .where(
        (e) =>
            (selectedPaletteGroup == null || e.group == selectedPaletteGroup) &&
            '${e.name} ${e.color.hex} ${e.group}'.toLowerCase().contains(
              paletteQuery.trim().toLowerCase(),
            ),
      )
      .toList();
  void filterPalette({String? query, String? group, bool setGroup = false}) {
    if (query != null) paletteQuery = query;
    if (setGroup) selectedPaletteGroup = group;
    _notify();
  }

  bool createPaletteGroup(String name) {
    name = name.trim();
    if (name.isEmpty || name.length > 60 || _paletteGroups.contains(name)) {
      _fail(strings.msgGroupNameInvalid);
      return false;
    }
    _paletteGroups.add(name);
    _persist();
    _notify();
    return true;
  }

  bool renamePaletteGroup(String old, String name) {
    name = name.trim();
    if (old == name) return true;
    if (!_paletteGroups.contains(old) ||
        name.isEmpty ||
        name.length > 60 ||
        _paletteGroups.contains(name)) {
      _fail(strings.msgGroupNameInvalid);
      return false;
    }
    _paletteGroups[_paletteGroups.indexOf(old)] = name;
    for (var i = 0; i < _palette.length; i++) {
      if (_palette[i].group == old) {
        _palette[i] = _palette[i].copyWith(group: name);
      }
    }
    if (selectedPaletteGroup == old) selectedPaletteGroup = name;
    _persist();
    _notify();
    return true;
  }

  void dissolvePaletteGroup(String group) {
    if (!_paletteGroups.remove(group)) return;
    for (var i = 0; i < _palette.length; i++) {
      if (_palette[i].group == group) {
        _palette[i] = _palette[i].copyWith(group: '');
      }
    }
    if (selectedPaletteGroup == group) selectedPaletteGroup = '';
    _persist();
    _notify();
  }

  void reorderPalette(RgbColor source, RgbColor target) {
    if (paletteQuery.trim().isNotEmpty) return;
    final from = _palette.indexWhere((e) => e.color == source),
        to = _palette.indexWhere((e) => e.color == target);
    if (from < 0 || to < 0 || from == to) return;
    final entry = _palette.removeAt(from);
    _palette.insert(to, entry);
    _persist();
    _notify();
  }

  bool continuousPicker = false;
  RgbColor contrastForeground = const RgbColor(0, 0, 0);
  RgbColor contrastBackground = const RgbColor(255, 255, 255);
  ColorContrast get contrast =>
      ColorContrast(contrastForeground, contrastBackground);
  String? _contrastTarget;
  bool _contrastPair = false;
  ({int id, PixelRect original, List<Map<String, Object?>> snapshot})? _pinDrag;

  int _pickedCount = 0;
  int _nextPinId = 0;
  int? _selectedPin;
  bool _editingPins = false;
  final List<List<Map<String, Object?>>> _pinUndo = [];
  final List<List<Map<String, Object?>>> _pinRedo = [];

  final List<MeasurementRecord> _measurements = [];
  List<RgbColor> get colors => List.unmodifiable(_colors);
  List<MeasurementRecord> get measurements => List.unmodifiable(_measurements);
  static const historyLimitChoices = [16, 32, 64, 128, 256];
  int _colorHistoryLimit = 64;
  int _measurementHistoryLimit = 32;
  int get colorHistoryLimit => _colorHistoryLimit;
  int get measurementHistoryLimit => _measurementHistoryLimit;

  void setColorHistoryLimit(int value) {
    if (!historyLimitChoices.contains(value) || value == _colorHistoryLimit) {
      return;
    }
    _colorHistoryLimit = value;
    if (_colors.length > value) {
      _colors.removeRange(value, _colors.length);
    }
    _logger.info('History limit changed: tool=picker, limit=$value.');
    _persist();
    _notify();
  }

  void setMeasurementHistoryLimit(int value) {
    if (!historyLimitChoices.contains(value) ||
        value == _measurementHistoryLimit) {
      return;
    }
    _measurementHistoryLimit = value;
    _trimMeasurements();
    _logger.info('History limit changed: tool=ruler, limit=$value.');
    _persist();
    _notify();
  }

  RulerMode mode = RulerMode.rectangle;
  ColorFormat format = ColorFormat.hex;
  final List<ColorOutput> _colorOutputs = List.of(ColorOutput.defaults);
  List<ColorOutput> get colorOutputs => List.unmodifiable(_colorOutputs);
  List<ColorOutput> get enabledColorOutputs =>
      _colorOutputs.where((e) => e.enabled).toList();
  String selectedOutputId = 'hex';
  ColorOutput get activeColorOutput => enabledColorOutputs.firstWhere(
    (e) => e.id == selectedOutputId,
    orElse: () => enabledColorOutputs.first,
  );
  String formatColor(RgbColor color) => activeColorOutput.render(color);
  PickerBehavior pickerBehavior = const PickerBehavior();
  RgbColor? pendingPickedEditorColor;
  bool colorEditorActive = false;
  final bool _openingColorEditor = false;
  RgbColor? takePickedEditorColor() {
    final color = pendingPickedEditorColor;
    pendingPickedEditorColor = null;
    if (color != null) colorEditorActive = true;
    return color;
  }

  void finishPickedEditor() {
    colorEditorActive = false;
  }

  void selectColorOutput(String id) {
    if (!enabledColorOutputs.any((e) => e.id == id)) return;
    selectedOutputId = id;
    format =
        ColorFormat.values.where((e) => e.name == id).firstOrNull ?? format;
    _persist();
    _notify();
  }

  bool saveColorOutput({
    String? id,
    required String name,
    required String template,
  }) {
    try {
      if (id == null && _colorOutputs.length >= 24) {
        throw const ValidationException('outputLimit');
      }
      name = name.trim();
      if (_colorOutputs.any(
        (e) => e.id != id && e.name.toLowerCase() == name.toLowerCase(),
      )) {
        throw const ValidationException('outputNameDuplicate');
      }
      var index = 1;
      while (_colorOutputs.any((e) => e.id == 'custom-$index')) {
        index++;
      }
      final old = _colorOutputs.where((e) => e.id == id).firstOrNull;
      if (id != null && old == null) return false;
      final value = ColorOutput(
        id: id ?? 'custom-$index',
        name: name,
        template: template,
        enabled: old?.enabled ?? true,
      );
      value.validate();
      if (old == null) {
        _colorOutputs.add(value);
      } else {
        _colorOutputs[_colorOutputs.indexOf(old)] = value;
      }
      _persist();
      _logger.info('Color output saved: created=${old == null}.');
      _notify();
      return true;
    } on FormatException catch (e, stackTrace) {
      _logFailure('Color output validation', e, stackTrace);
      _fail(describeError(e));
      return false;
    }
  }

  bool enableColorOutput(String id, bool enabled) {
    final index = _colorOutputs.indexWhere((e) => e.id == id);
    if (index < 0) return false;
    if (!enabled &&
        enabledColorOutputs.length == 1 &&
        _colorOutputs[index].enabled) {
      _fail(strings.msgOutputRequired);
      return false;
    }
    _colorOutputs[index] = _colorOutputs[index].copyWith(enabled: enabled);
    _logger.info('Color output enabled state changed: enabled=$enabled.');
    _ensureActiveOutput();
    _persist();
    _notify();
    return true;
  }

  bool deleteColorOutput(String id) {
    final entry = _colorOutputs.where((e) => e.id == id).firstOrNull;
    if (entry == null) return false;
    if (entry.enabled && enabledColorOutputs.length == 1) {
      _fail(strings.msgOutputRequired);
      return false;
    }
    _colorOutputs.remove(entry);
    _ensureActiveOutput();
    _persist();
    _notify();
    return true;
  }

  void moveColorOutput(String id, int delta) {
    final from = _colorOutputs.indexWhere((e) => e.id == id);
    final to = from + delta;
    if (from < 0 || to < 0 || to >= _colorOutputs.length) return;
    _colorOutputs.insert(to, _colorOutputs.removeAt(from));
    _persist();
    _notify();
  }

  void _ensureActiveOutput() {
    if (!enabledColorOutputs.any((e) => e.id == selectedOutputId)) {
      selectedOutputId = enabledColorOutputs.first.id;
      format =
          ColorFormat.values
              .where((e) => e.name == selectedOutputId)
              .firstOrNull ??
          format;
    }
  }

  void setPickerBehavior(PickerBehavior value) {
    pickerBehavior = value;
    _logger.info(
      'Picker mouse actions changed: primary=${value.primary.name}, middle=${value.middle.name}, secondary=${value.secondary.name}.',
    );
    continuousPicker = value.primary == PickerMouseAction.pickAndContinue;
    _persist();
    if (_session != null) _redraw();
    _notify();
  }

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
  bool screenshotPermissionRequired = false;
  bool shortcutsAvailable = false;
  bool supported = true;

  bool supports(DesktopFeature feature) {
    if (!supported || !desktop.capabilities.contains(feature)) return false;
    return switch (feature) {
      DesktopFeature.qrCode || DesktopFeature.textRecognition =>
        desktop.capabilities.contains(DesktopFeature.screenshot),
      _ => true,
    };
  }

  bool supportsSection(AppSection value) => switch (value) {
    AppSection.settings => true,
    AppSection.picker => supports(DesktopFeature.picker),
    AppSection.ruler => supports(DesktopFeature.ruler),
    AppSection.image => supports(DesktopFeature.screenshot),
    AppSection.recording => supports(DesktopFeature.recording),
  };
  bool busy = false;
  bool initializing = true;
  String? error;
  String? notice;
  StreamSubscription<Map<Object?, Object?>>? _subscription;
  CaptureSession? _session;
  String? _tool;
  PixelPoint? _anchor;
  ({double x, double y})? _selectionPress;
  PixelRect? _pressedCandidate;
  RulerMeasurement? _captureMeasurement;

  int? _anchorDisplay;
  bool _committing = false;
  bool _disposed = false;
  final List<Map<Object?, Object?>> _pending = [];

  Future<void> initialize() =>
      _initialization ??= _queueLocaleUpdate(_initialize);

  Future<void> _initialize() async {
    if (_subscription != null) return;
    _logger.info('Controller initialization started.');
    _subscription = desktop.events.listen(
      _event,
      onError: (Object e, StackTrace stackTrace) {
        _logFailure('Desktop event stream', e, stackTrace);
        _fail(strings.msgDesktopDisconnected);
      },
    );
    try {
      final status = await desktop.initialize();
      permissionGranted = status.permission;
      shortcutsAvailable = status.shortcuts;
      supported = status.supported;
      if (!supportsSection(section)) section = AppSection.settings;
      final saved = await desktop.loadState();
      if (saved != null) _restore(saved);
      try {
        await desktop.configureLocale(locale.languageCode);
      } catch (error, stackTrace) {
        _logFailure('Initial language configuration', error, stackTrace);
        _language = AppLanguage.system;
        _localeNotifier.value = _language.resolve(_systemLocale);
        try {
          await desktop.configureLocale(locale.languageCode);
        } catch (restoreError, restoreStackTrace) {
          _logFailure(
            'Initial language fallback',
            restoreError,
            restoreStackTrace,
          );
        }
        this.error = strings.msgLocaleChangeFailed;
        notice = null;
        _persist();
      }
      _logger.info('State loaded: present=${saved != null}.');
      if (supported) {
        try {
          shortcutsAvailable = await desktop.configureShortcuts(shortcuts);
        } catch (e, stackTrace) {
          _logFailure('Initial shortcut registration', e, stackTrace);
          shortcutsAvailable = false;
          error = describeError(e);
        }
      }
      if (!supported) error = strings.msgPlatformUnsupported;
    } catch (e, stackTrace) {
      _logFailure('Controller initialization', e, stackTrace);
      error = describeError(e);
    } finally {
      _logger.info(
        'Controller initialized: supported=$supported, permission=$permissionGranted, shortcuts=$shortcutsAvailable.',
      );
      initializing = false;
      _notify();
    }
  }

  void selectSection(AppSection value) {
    if (!supportsSection(value)) return;
    section = value;
    _notify();
  }

  void selectMode(RulerMode value) {
    mode = value;
    _notify();
    _persist();
  }

  void setFormat(ColorFormat value) {
    if (!enabledColorOutputs.any((e) => e.id == value.name)) return;
    selectColorOutput(value.name);
  }

  void setTolerance(int value) {
    tolerance = value.clamp(0, 255);
    _notify();
    _persist();
  }

  void setZoom(int value) {
    if (value == zoom || !CaptureControls.zoomLevels.contains(value)) return;
    zoom = value;
    _persist();
    _redraw();
    _notify();
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
      _logger.info('Screen permission requested: granted=$permissionGranted.');
      if (permissionGranted) screenshotPermissionRequired = false;
      notice = permissionGranted
          ? strings.msgPermissionGranted
          : strings.msgPermissionDenied;
      error = null;
      _notify();
    } catch (e, stackTrace) {
      _logFailure('Permission request', e, stackTrace);
      _fail(describeError(e));
    }
  }

  Future<void> openPrivacySettings() async {
    try {
      await desktop.openPrivacySettings();
    } catch (e, stackTrace) {
      _logFailure('Privacy settings open', e, stackTrace);
      _fail(describeError(e));
    }
  }

  Future<void> pickColor() {
    if (busy ||
        initializing ||
        recordingShortcut ||
        savingShortcuts ||
        colorEditorActive ||
        _openingColorEditor ||
        pendingPickedEditorColor != null) {
      return Future.value();
    }
    _contrastTarget = null;
    _contrastPair = false;
    return _begin('picker');
  }

  Future<void> pickNewColor() {
    if (busy || initializing || recordingShortcut || savingShortcuts) {
      return Future.value();
    }
    _contrastTarget = null;
    _contrastPair = false;
    return _begin('picker');
  }

  Future<void> pickContrast({
    required bool foreground,
    bool pair = false,
  }) async {
    if (busy || initializing || recordingShortcut || savingShortcuts) return;
    _contrastTarget = foreground ? 'foreground' : 'background';
    _contrastPair = pair;
    await _begin('picker');
    if (!busy) {
      _contrastTarget = null;
      _contrastPair = false;
    }
  }

  void setContrastColor(RgbColor color, {required bool foreground}) {
    if (foreground) {
      contrastForeground = color;
    } else {
      contrastBackground = color;
    }
    _persist();
    _notify();
  }

  void swapContrast() {
    final old = contrastForeground;
    contrastForeground = contrastBackground;
    contrastBackground = old;
    _persist();
    _notify();
  }

  Future<void> startScreenshot() => _begin('screenshot');

  RecordingOptions recordingOptions = const RecordingOptions();
  bool screenRecording = false;
  bool recordingTransition = false;
  int _recordingGeneration = 0;

  void setRecordingOptions(RecordingOptions value) {
    if (busy || recordingTransition || screenRecording) return;
    recordingOptions = RecordingOptions.fromJson(value.toJson());
    _persist();
    _notify();
  }

  Future<void> startRecording() => _begin('recording');

  Future<void> _commitRecording(
    RulerMeasurement measurement,
    CapturedDisplay display,
  ) async {
    final id = _session!.id;
    final generation = ++_recordingGeneration;
    _committing = true;
    recordingTransition = true;
    _notify();
    try {
      await desktop.startRecording(
        id,
        display.id,
        measurement.rect,
        recordingOptions,
      );
      if (_disposed || generation != _recordingGeneration) return;
      _resetSession();
      screenRecording = true;
      busy = true;
      notice = strings.msgRecordingStarted;
      _logger.info('Screen recording started.');
    } catch (e, stackTrace) {
      _logFailure('Screen recording start', e, stackTrace);
      if (_disposed || generation != _recordingGeneration) return;
      try {
        await desktop.finish(id);
      } catch (error, stackTrace) {
        _logFailure('Screen recording selection cleanup', error, stackTrace);
      }
      if (_disposed || generation != _recordingGeneration) return;
      _resetSession();
      _fail(strings.msgRecordingFailed(describeError(e)));
    } finally {
      if (generation == _recordingGeneration) {
        recordingTransition = false;
        _notify();
      }
    }
  }

  Future<void> stopRecording() async {
    if (!screenRecording || recordingTransition) return;
    final generation = _recordingGeneration;
    recordingTransition = true;
    _notify();
    try {
      final saved = await desktop.stopRecording();
      if (_disposed || generation != _recordingGeneration) return;
      notice = saved
          ? strings.msgRecordingSaved
          : strings.msgRecordingDiscarded;
      error = null;
      _logger.info('Screen recording stopped: saved=$saved.');
    } catch (e, stackTrace) {
      _logFailure('Screen recording stop', e, stackTrace);
      if (_disposed || generation != _recordingGeneration) return;
      _fail(strings.msgRecordingFailed(describeError(e)));
    } finally {
      if (generation == _recordingGeneration) {
        screenRecording = false;
        recordingTransition = false;
        busy = false;
        _notify();
      }
    }
  }

  Future<void> startQrCodeRecognition() =>
      _begin('screenshot', recognizeQrCodeAfterSelection: true);

  Offset? get screenshotPointer {
    final p = _lastPointer;
    return p != null && p.displayId == screenshotDisplayId
        ? Offset(p.x, p.y)
        : null;
  }

  RgbColor? screenshotColorAt(double x, double y) {
    final display = _session?.displays
        .where((d) => d.id == screenshotDisplayId)
        .firstOrNull;
    if (display == null || !x.isFinite || !y.isFinite) return null;
    final point = display.frame.logicalToPixel(x, y);
    return display.frame.pixelAt(point.x, point.y);
  }

  Future<void> sampleCaptureColor(int displayId, double x, double y) async {
    if (_session == null ||
        _committing ||
        imageSaving ||
        qrCodeBusy ||
        textMode) {
      return;
    }
    final display = _session!.displays
        .where((d) => d.id == displayId)
        .firstOrNull;
    if (display == null || !x.isFinite || !y.isFinite) return;
    final p = display.frame.logicalToPixel(x, y);
    await _commitColor(
      display.frame.pixelAt(p.x, p.y),
      action: PickerMouseAction.pickAndClose,
    );
  }

  Future<void> copyCaptureSize(int displayId, PixelRect rect) async {
    if (_session == null ||
        _committing ||
        imageSaving ||
        qrCodeBusy ||
        textMode) {
      return;
    }
    final display = _session!.displays
        .where((d) => d.id == displayId)
        .firstOrNull;
    if (display == null ||
        rect.left < 0 ||
        rect.top < 0 ||
        rect.right > display.frame.width ||
        rect.bottom > display.frame.height ||
        rect.width < 1 ||
        rect.height < 1) {
      return;
    }
    await _commitMeasurement(
      RulerMeasurement.fromRect(display.frame, rect, RulerMode.rectangle),
      display,
    );
  }

  Future<void> _commitScreenshot(
    RulerMeasurement measurement,
    CapturedDisplay display,
  ) async {
    final id = _session!.id;
    _committing = true;
    imageLoading = true;
    try {
      final doc = await imageCodec.cropCapture(display.frame, measurement.rect);
      if (_disposed || _session?.id != id) return;
      imageDocument = doc;
      screenshotSelection = measurement.rect;
      screenshotDisplayId = display.id;
      screenshotScaleX = display.frame.scaleX;
      screenshotScaleY = display.frame.scaleY;
      markup.reset();
      _notify();
      await desktop.editScreenshot(id, display.id);
    } catch (e, stackTrace) {
      _logFailure('Screenshot crop', e, stackTrace);
      await _abortScreenshot(e, id);
    } finally {
      _committing = false;
      imageLoading = false;
      _notify();
    }
    if (!_disposed &&
        _session?.id == id &&
        screenshotEditing &&
        _recognizeQrCodeAfterSelection) {
      // 先让原生面板完成编辑器托管，再自动识别本次框选的二维码。
      await recognizeQrCodes();
    }
  }

  Future<void> _abortScreenshot(Object error, int id) async {
    try {
      await desktop.finish(id);
    } catch (e, stackTrace) {
      _logFailure('Screenshot abort cleanup', e, stackTrace);
    }
    _resetSession();
    _fail(strings.msgScreenshotFailed(describeError(error)));
    await desktop.showMainWindow();
  }

  Future<void> startRuler([RulerMode? value]) {
    if (value != null) selectMode(value);
    return _begin(mode.name);
  }

  Future<void> _begin(
    String tool, {
    bool recognizeQrCodeAfterSelection = false,
  }) async {
    if (busy ||
        pinningImage ||
        imageLoading ||
        imageSaving ||
        initializing ||
        recordingShortcut ||
        savingShortcuts ||
        _disposed) {
      return;
    }
    if (!supported) {
      _fail(strings.msgMacOSRequired);
      return;
    }
    final feature = switch (tool) {
      'picker' => DesktopFeature.picker,
      'screenshot' => DesktopFeature.screenshot,
      'recording' => DesktopFeature.recording,
      _ => DesktopFeature.ruler,
    };
    if (!supports(feature) ||
        (recognizeQrCodeAfterSelection && !supports(DesktopFeature.qrCode))) {
      return;
    }
    _recognizeQrCodeAfterSelection = recognizeQrCodeAfterSelection;
    busy = true;
    if (tool == 'screenshot') screenshotPermissionRequired = false;
    _tool = tool;
    _committing = false;
    _anchor = null;
    _anchorDisplay = null;
    _selectionPress = null;
    _pressedCandidate = null;
    _captureMeasurement = null;
    _pending.clear();
    _pins.clear();
    _pinUndo.clear();
    _pinRedo.clear();
    _selectedPin = null;
    _editingPins = false;
    _pickedCount = 0;
    _lastPointer = null;
    _keyboardRectangle = false;
    _keyboardCursor = false;
    error = null;
    notice = null;
    section = tool == 'recording'
        ? AppSection.recording
        : tool == 'screenshot'
        ? AppSection.image
        : tool == 'picker'
        ? AppSection.picker
        : AppSection.ruler;
    _notify();
    try {
      _logger.info('Capture begin requested: tool=$tool.');
      final session = await desktop.begin(tool);
      _logger.info(
        'Capture began: tool=$tool, session=${session.id}, displays=${session.displays.length}.',
      );
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
    } catch (e, stackTrace) {
      _logFailure('Capture begin', e, stackTrace);
      _recognizeQrCodeAfterSelection = false;
      busy = false;
      _session = null;
      _pending.clear();
      if (e is PlatformException && e.code == 'screen_permission') {
        permissionGranted = false;
        screenshotPermissionRequired = tool == 'screenshot';
      }
      _fail(describeError(e));
    }
  }

  void _event(Map<Object?, Object?> event) {
    if (_disposed) return;
    switch (event['type']) {
      case 'quitRequested':
        unawaited(desktop.replyToQuit(true));
        return;
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
      case 'activateQrCode':
        unawaited(startQrCodeRecognition());
        return;
      case 'activate':
        final tool = event['tool'];
        if (tool == 'recording') {
          unawaited(startRecording());
        } else if (tool == 'picker') {
          unawaited(pickColor());
        } else if (tool == 'rectangle') {
          unawaited(startRuler());
        } else if (tool == 'screenshot') {
          unawaited(startScreenshot());
        } else {
          final value = RulerMode.values
              .where((v) => v.name == tool)
              .firstOrNull;
          if (value != null) unawaited(startRuler(value));
        }
        return;
      case 'stopRecording':
        unawaited(stopRecording());
        return;
      case 'recordingFailed':
        if (!screenRecording && !recordingTransition) return;
        _recordingGeneration++;
        screenRecording = false;
        recordingTransition = false;
        _resetSession();
        _fail(strings.msgRecordingFailed(event['message'] as String? ?? ''));
        return;
      case 'pinClipboard':
        unawaited(pinClipboard());
        return;
      case 'togglePinnedImages':
        unawaited(togglePinnedImages());
        return;
      case 'closePinnedImages':
        unawaited(closePinnedImages());
        return;
      case 'showSettings':
        selectSection(AppSection.settings);
        return;
      case 'showHistory':
        if (section == AppSection.settings) selectSection(AppSection.picker);
        return;
      case 'permissionChanged':
        permissionGranted = event['permission'] == true;
        if (permissionGranted) screenshotPermissionRequired = false;
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
      if (_tool == 'recording' && recordingTransition) {
        _recordingGeneration++;
        recordingTransition = false;
        unawaited(desktop.cancelRecording());
      }
      _logger.info('Capture cancelled: session=${_session!.id}, tool=$_tool.');
      final count = _tool == 'picker' ? _pickedCount : 0;
      _resetSession();
      notice = count > 0
          ? strings.msgPickingFinished(count)
          : strings.msgCancelled;
      _notify();
      return;
    }
    if (_committing || screenshotEditing) return;
    switch (event['type']) {
      case 'sampleColor':
        final p = _lastPointer;
        if (_tool == 'screenshot' && p != null) {
          unawaited(sampleCaptureColor(p.displayId, p.x, p.y));
        }
        return;
      case 'copyCaptureSize':
        final p = _lastPointer;
        if (_tool == 'screenshot' && p != null && _captureMeasurement != null) {
          unawaited(copyCaptureSize(p.displayId, _captureMeasurement!.rect));
        }
        return;
      case 'continuousChanged':
        setContinuousPicker(event['enabled'] == true);
        return;
      case 'pinDrag':
        _dragPin(event);
        return;
      case 'copyMeasurement':
        unawaited(_copySelectedMeasurement());
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
      case 'redoPins':
        _finishPinDrag();
        final from = event['type'] == 'undoPins' ? _pinUndo : _pinRedo;
        final to = event['type'] == 'undoPins' ? _pinRedo : _pinUndo;
        if (from.isNotEmpty) {
          to.add(List.of(_pins));
          if (to.length > 64) to.removeAt(0);
          _pins
            ..clear()
            ..addAll(from.removeLast());
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
        // 工具会话相互独立，只有尺子内部可以切换测量模式。
        if (_contrastTarget == null &&
            next != null &&
            RulerMode.values.any((m) => m.name == _tool)) {
          mode = next;
          _tool = next.name;
          _pressedCandidate = null;
          _selectionPress = null;
          _captureMeasurement = null;
          _editingPins = false;
          _anchor = null;
          _anchorDisplay = null;
          _keyboardRectangle = false;
          _persist();
          _redraw();
          _notify();
        }
        return;
      case 'toleranceChanged':
        if (['horizontal', 'vertical', 'cross'].contains(_tool) &&
            event['tolerance'] is int) {
          setTolerance(event['tolerance'] as int);
          _redraw();
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
        if (_editingPins ||
            (_tool == 'rectangle' && _selectedPin != null && _anchor == null)) {
          _nudgePin(
            (event['dx'] as int).clamp(-1, 1),
            (event['dy'] as int).clamp(-1, 1),
            event['resize'] == true,
          );
          return;
        }
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
        if (_tool == 'rectangle' && _selectedPin != null && _anchor == null) {
          unawaited(_copySelectedMeasurement(finish: true));
          return;
        }
        if (_editingPins) return;
        final position = _lastPointer;
        if (position == null) return;
        final start =
            (_tool == 'rectangle' ||
                _tool == 'screenshot' ||
                _tool == 'recording') &&
            _anchor == null;
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
    'colorOutputName': activeColorOutput.name,
    'continuous': _contrastTarget == null && continuousPicker,
    'pickerActions': _contrastTarget == null
        ? strings.msgPickerActions(
            pickerActionLabel(pickerBehavior.primary),
            pickerActionLabel(pickerBehavior.middle),
            pickerActionLabel(pickerBehavior.secondary),
          )
        : strings.msgConfirmActions,
    'capturePurpose': _recognizeQrCodeAfterSelection
        ? strings.uiQrCodeSelectionHint
        : _contrastTarget == null
        ? ''
        : (_contrastTarget == 'foreground'
              ? strings.msgPickForeground
              : strings.msgPickBackground),
    'pickedCount': _pickedCount,
    'selectedPin': _selectedPin,
    'editingPins': _editingPins,
    'canUndoPins': _pinUndo.isNotEmpty,
    'canRedoPins': _pinRedo.isNotEmpty,
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
      desktop.updateOverlay(data).catchError((Object e, StackTrace stackTrace) {
        _logFailure('Overlay update', e, stackTrace);
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
    if (_editingPins) {
      _updateOverlay({..._overlayOptions, 'displayId': display.id});
      return;
    }
    final pixel = frame.logicalToPixel(x, y);
    final color = frame.pixelAt(pixel.x, pixel.y);
    RulerMeasurement? measurement;
    if (_tool == RulerMode.rectangle.name ||
        _tool == 'screenshot' ||
        _tool == 'recording') {
      final candidate = _tool == 'screenshot' && event['keyboard'] != true
          ? CaptureControls.suggestedRect(frame, event['suggestedRect'], x, y)
          : null;
      if (phase == 'down') {
        _selectionPress = (x: x, y: y);
        _pressedCandidate = candidate;
        _selectedPin = null;
        _keyboardRectangle = event['keyboard'] == true;
        _anchor = _keyboardRectangle ? pixel : frame.logicalToBoundary(x, y);
        _anchorDisplay = display.id;
      }
      final press = _selectionPress;
      if (press != null &&
          ((x - press.x) * (x - press.x) + (y - press.y) * (y - press.y) > 4)) {
        _pressedCandidate = null;
      }
      if (_anchor == null && candidate != null) {
        measurement = RulerMeasurement.fromRect(
          frame,
          candidate,
          RulerMode.rectangle,
        );
      } else if (_anchor != null && _anchorDisplay == display.id) {
        measurement = RulerMeasurement.fromRect(
          frame,
          _pressedCandidate ??
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
    if (_tool == 'screenshot' || _tool == 'recording') {
      _captureMeasurement = measurement;
    }
    final position = ScreenUnits.position(
      pixel.x,
      pixel.y,
      scaleX: frame.scaleX,
      scaleY: frame.scaleY,
    );
    final dimensions = measurement == null
        ? null
        : ScreenUnits.measurement(measurement);
    final label = _tool == 'picker'
        ? '${color.hex}  ·  ${color.rgb}\n$position'
        : _tool == 'recording'
        ? dimensions ?? strings.msgRecordingSelectRegion
        : _tool == 'screenshot'
        ? '${color.hex} · ${color.rgb}\n$position · ${dimensions ?? strings.msgDragScreenshot}'
        : dimensions ?? strings.msgDragMeasurement;
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
      final button = event['button'] as String? ?? 'primary';
      final action = _contrastTarget != null
          ? (button == 'secondary'
                ? PickerMouseAction.cancel
                : PickerMouseAction.pickAndClose)
          : pickerBehavior.forButton(button);
      unawaited(_commitColor(color, action: action));
    } else if (measurement != null &&
        measurement.rect.width > 0 &&
        measurement.rect.height > 0) {
      if (_tool == 'recording') {
        unawaited(_commitRecording(measurement, display));
        return;
      }
      if (_tool == 'screenshot') {
        unawaited(_commitScreenshot(measurement, display));
        return;
      }
      unawaited(
        _commitMeasurement(measurement, display, keep: _tool == 'rectangle'),
      );
    } else {
      _anchor = null;
      _anchorDisplay = null;
    }
  }

  Future<void> _commitColor(
    RgbColor color, {
    required PickerMouseAction action,
  }) async {
    final sessionId = _session!.id;
    if (action == PickerMouseAction.cancel) {
      _committing = true;
      try {
        await desktop.finish(sessionId);
        notice = strings.msgPickingCancelled;
        error = null;
      } catch (e, stackTrace) {
        _logFailure('Color picker finish', e, stackTrace);
        _fail(strings.msgPickerFinishFailed(describeError(e)));
      } finally {
        if (_session?.id == sessionId) _resetSession();
        _notify();
      }
      return;
    }
    _committing = true;
    selectedColor = color;
    _rememberColor(color);
    _pickedCount++;
    if (_contrastTarget != null) {
      final foreground = _contrastTarget == 'foreground';
      setContrastColor(color, foreground: foreground);
      if (_contrastPair && foreground) {
        _contrastTarget = 'background';
        _committing = false;
        _redraw();
      } else {
        await _complete(formatColor(color));
      }
      return;
    }
    if (action == PickerMouseAction.pickAndContinue) {
      try {
        await desktop.writeClipboard(formatColor(color));
        _logger.info('Color clipboard write completed: session=$sessionId.');
        if (_session?.id == sessionId) {
          notice = strings.msgPickingContinues(_pickedCount);
          error = null;
        }
      } catch (e, stackTrace) {
        _logFailure('Continuous color clipboard write', e, stackTrace);
        if (_session?.id == sessionId) {
          error = strings.msgColorClipboardFailed(describeError(e));
        }
      } finally {
        if (_session?.id == sessionId) {
          _committing = false;
          _redraw();
        }
        _persist();
        _notify();
      }
    } else {
      await _complete(formatColor(color));
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
        imageSource: false,
      ),
    );
    _trimMeasurements();
    if (keep) {
      _rememberPins();
      _pins.add({
        'id': ++_nextPinId,
        'displayId': display.id,
        'rect': measurement.rect.toJson(),
        'label': ScreenUnits.measurement(measurement),
      });
      _selectedPin = _nextPinId;
      _anchor = null;
      _anchorDisplay = null;
      _keyboardRectangle = false;
      try {
        await desktop.writeClipboard(measurement.label);
        _logger.info(
          'Measurement clipboard write completed: session=$sessionId.',
        );
        if (_session?.id == sessionId) {
          notice = strings.msgMeasurementsRetained(_pins.length);
        }
      } catch (e, stackTrace) {
        _logFailure('Measurement clipboard write', e, stackTrace);
        if (_session?.id == sessionId) {
          error = strings.msgMeasurementClipboardFailed(describeError(e));
        }
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

  Future<void> _copySelectedMeasurement({bool finish = false}) async {
    final session = _session;
    if (session == null || _committing) return;
    final pin = _pins.where((p) => p['id'] == _selectedPin).firstOrNull;
    if (pin == null) return;
    final frame = session.displays
        .firstWhere((d) => d.id == pin['displayId'])
        .frame;
    final result = RulerMeasurement.fromRect(
      frame,
      _pinRect(pin),
      RulerMode.rectangle,
    );
    _committing = true;
    if (finish) {
      await _complete(result.label);
      return;
    }
    try {
      await desktop.writeClipboard(result.label);
      if (_session?.id == session.id) {
        notice = strings.msgCopied(result.label);
        error = null;
      }
    } catch (e, stackTrace) {
      _logFailure('Selected measurement clipboard write', e, stackTrace);
      if (_session?.id == session.id) {
        error = strings.msgSizeClipboardFailed(describeError(e));
      }
    } finally {
      if (_session?.id == session.id) _committing = false;
      _notify();
    }
  }

  PixelRect _pinRect(Map<String, Object?> pin) {
    final r = pin['rect'] as Map;
    return PixelRect(
      left: r['left'] as int,
      top: r['top'] as int,
      right: r['right'] as int,
      bottom: r['bottom'] as int,
    );
  }

  void _replacePin(int index, PixelRect rect) {
    _pins[index] = {
      ..._pins[index],
      'rect': rect.toJson(),
      'label': ScreenUnits.measurement(
        RulerMeasurement.fromRect(
          _session!.displays
              .firstWhere((d) => d.id == _pins[index]['displayId'])
              .frame,
          rect,
          RulerMode.rectangle,
        ),
      ),
    };
  }

  void _dragPin(Map<Object?, Object?> event) {
    if (!_editingPins && _tool != 'rectangle') return;
    final index = _pins.indexWhere(
      (p) => p['id'] == event['id'] && p['displayId'] == event['displayId'],
    );
    if (index < 0) return;
    if (event['phase'] == 'start') {
      _selectedPin = event['id'] as int;
      _pinDrag = (
        id: _selectedPin!,
        original: _pinRect(_pins[index]),
        snapshot: List.of(_pins),
      );
    } else {
      final drag = _pinDrag;
      if (drag == null || drag.id != event['id']) return;
      final display = _session!.displays.firstWhere(
        (d) => d.id == event['displayId'],
      );
      final dx = (event['dx'] as num?)?.toDouble() ?? 0,
          dy = (event['dy'] as num?)?.toDouble() ?? 0;
      if (!dx.isFinite || !dy.isFinite) return;
      final rect = transformAnnotation(
        drag.original,
        (dx * display.frame.scaleX).round(),
        (dy * display.frame.scaleY).round(),
        display.frame.width,
        display.frame.height,
        handle: event['handle'] as String? ?? 'move',
      );
      _replacePin(index, rect);
      if (event['phase'] == 'end') {
        if (jsonEncode(drag.original.toJson()) != jsonEncode(rect.toJson())) {
          _recordPinUndo(drag.snapshot);
        }
        _pinDrag = null;
      }
    }
    _redraw();
  }

  void _nudgePin(int dx, int dy, bool resize) {
    final index = _pins.indexWhere((p) => p['id'] == _selectedPin);
    if (index < 0) return;
    final frame = _session!.displays
        .firstWhere((d) => d.id == _pins[index]['displayId'])
        .frame;
    final old = _pinRect(_pins[index]);
    final rect = transformAnnotation(
      old,
      dx,
      dy,
      frame.width,
      frame.height,
      handle: resize ? 'se' : 'move',
    );
    if (jsonEncode(old.toJson()) == jsonEncode(rect.toJson())) return;
    _rememberPins();
    _replacePin(index, rect);
    _redraw();
  }

  void _recordPinUndo(List<Map<String, Object?>> snapshot) {
    _pinUndo.add(snapshot);
    if (_pinUndo.length > 64) _pinUndo.removeAt(0);
    _pinRedo.clear();
  }

  void _finishPinDrag() {
    final drag = _pinDrag;
    if (drag == null) return;
    if (jsonEncode(drag.snapshot) != jsonEncode(_pins)) {
      _recordPinUndo(drag.snapshot);
    }
    _pinDrag = null;
  }

  void _rememberPins() {
    _finishPinDrag();
    _recordPinUndo(List.of(_pins));
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
      if (done && _session?.id == session.id) {
        notice = save
            ? strings.msgAnnotationImageExported
            : strings.msgAnnotationImageCopied;
        error = null;
      }
    } catch (e, stackTrace) {
      _logFailure('Measurement image export', e, stackTrace);
      if (_session?.id == session.id) {
        _fail(strings.msgAnnotationImageExportFailed(describeError(e)));
      }
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
      _logger.info('Clipboard write completed.');
      if (_session?.id == id) notice = strings.msgCopied(text);
    } catch (e, stackTrace) {
      _logFailure('Result clipboard write', e, stackTrace);
      if (_session?.id == id) {
        error = strings.msgResultClipboardFailed(describeError(e));
      }
    } finally {
      try {
        if (id != null) await desktop.finish(id);
      } catch (e, stackTrace) {
        _logFailure('Capture finish', e, stackTrace);
        if (_session?.id == id) {
          error = strings.msgRulerFinishFailed(describeError(e));
        }
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
    } catch (error, stackTrace) {
      _logFailure('Capture abort cleanup', error, stackTrace);
      /* Preserve original failure. */
    }
    _resetSession();
    _fail(describeError(e));
  }

  void _resetSession() {
    _clearText();
    _recognizeQrCodeAfterSelection = false;
    _clearQrCodes();
    imageCodec.clearCaptureImages();
    if (_session != null) {
      _logger.info(
        'Capture session released: session=${_session!.id}, tool=$_tool.',
      );
    }
    _session = null;
    imageDocument = null;
    screenshotSelection = null;
    screenshotDisplayId = null;
    imageLoading = false;
    markup.reset();
    _tool = null;
    _contrastTarget = null;
    _contrastPair = false;
    _pinDrag = null;
    busy = false;
    _anchor = null;
    _anchorDisplay = null;
    _selectionPress = null;
    _pressedCandidate = null;
    _captureMeasurement = null;
    _committing = false;
    _pending.clear();
    _pins.clear();
    _pinUndo.clear();
    _pinRedo.clear();
    _selectedPin = null;
    _editingPins = false;
    _pickedCount = 0;
    _lastPointer = null;
    _keyboardRectangle = false;
    _keyboardCursor = false;
  }

  Future<bool> beginShortcutRecording() async {
    if (busy ||
        pinningImage ||
        initializing ||
        recordingShortcut ||
        savingShortcuts) {
      return false;
    }
    try {
      if (!await desktop.setShortcutRecording(true)) return false;
      recordedShortcut = null;
      recordingShortcut = true;
      _notify();
      return true;
    } catch (e, stackTrace) {
      _logFailure('Shortcut recording start', e, stackTrace);
      _fail(describeError(e));
      return false;
    }
  }

  Future<void> endShortcutRecording() async {
    try {
      shortcutsAvailable = await desktop.setShortcutRecording(false);
    } catch (e, stackTrace) {
      _logFailure('Shortcut recording finish', e, stackTrace);
      _fail(describeError(e));
    } finally {
      recordingShortcut = false;
      _notify();
    }
  }

  Future<bool> setShortcut(
    bool picker,
    ShortcutChord chord, {
    bool screenshot = false,
    bool pinClipboard = false,
    bool togglePins = false,
  }) async {
    if (busy || pinningImage || savingShortcuts || recordingShortcut) {
      return false;
    }
    final candidate = ShortcutBindings(
      picker: !screenshot && !pinClipboard && !togglePins && picker
          ? chord
          : shortcuts.picker,
      ruler: !screenshot && !pinClipboard && !togglePins && !picker
          ? chord
          : shortcuts.ruler,
      screenshot: screenshot ? chord : shortcuts.screenshot,
      pinClipboard: pinClipboard ? chord : shortcuts.pinClipboard,
      togglePins: togglePins ? chord : shortcuts.togglePins,
    );
    if (!candidate.isValid) {
      _fail(strings.msgShortcutInvalid);
      return false;
    }
    savingShortcuts = true;
    _notify();
    try {
      final registered = await desktop.configureShortcuts(candidate);
      if (!registered) {
        _fail(strings.msgShortcutRegistrationFailed);
        return false;
      }
      _logger.info('Shortcut configuration completed.');
      shortcuts = candidate;
      shortcutsAvailable = true;
      error = null;
      notice = strings.msgShortcutsUpdated;
      _persist();
      return true;
    } catch (e, stackTrace) {
      _logFailure('Shortcut configuration', e, stackTrace);
      if (e is PlatformException && e.details is Map) {
        final status = (e.details as Map)['shortcuts'];
        if (status is bool) shortcutsAvailable = status;
      }
      _fail(describeError(e));
      return false;
    } finally {
      savingShortcuts = false;
      _notify();
    }
  }

  void setContinuousPicker(bool value) => setPickerBehavior(
    pickerBehavior.copyWith(
      primary: value
          ? PickerMouseAction.pickAndContinue
          : PickerMouseAction.pickAndClose,
    ),
  );

  void _rememberColor(RgbColor color) {
    _colors.remove(color);
    _colors.insert(0, color);
    if (_colors.length > colorHistoryLimit) _colors.removeLast();
  }

  void addEditedColor(RgbColor color) {
    selectedColor = color;
    _rememberColor(color);
    _persist();
    _notify();
  }

  PaletteEntry? paletteEntry(RgbColor color) =>
      _palette.where((e) => e.color == color).firstOrNull;
  void savePaletteColor(
    RgbColor color, {
    String? name,
    bool? favorite,
    String? group,
  }) {
    final old = paletteEntry(color);
    final entry = PaletteEntry(
      color: color,
      name: name?.trim() ?? old?.name ?? '',
      favorite: favorite ?? old?.favorite ?? false,
      group: group ?? old?.group ?? selectedPaletteGroup ?? '',
    );
    if (entry.group.isNotEmpty && !_paletteGroups.contains(entry.group)) {
      _paletteGroups.add(entry.group);
    }
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
        ? visiblePalette
        : _colors
              .map((c) => paletteEntry(c) ?? PaletteEntry(color: c))
              .toList();
    if (entries.isEmpty) return;
    try {
      if (await desktop.saveTextFile(
        'fruler-${saved ? 'palette' : 'recent'}.${format.name}',
        exportPalette(entries, format),
      )) {
        notice = strings.msgColorsExported;
        error = null;
        _notify();
      }
    } catch (e, stackTrace) {
      _logFailure('Palette export', e, stackTrace);
      _fail(strings.msgColorsExportFailed(describeError(e)));
    }
  }

  Future<List<PaletteEntry>?> readPaletteImport() async {
    try {
      final text = await desktop.openPaletteFile();
      return text == null ? null : importPalette(text);
    } catch (e, stackTrace) {
      _logFailure('Palette import', e, stackTrace);
      _fail(
        e is FormatException
            ? describeError(e)
            : strings.msgPaletteReadFailed(describeError(e)),
      );
      return null;
    }
  }

  void applyPaletteImport(List<PaletteEntry> entries, PaletteMerge policy) {
    final merged = mergePalette(_palette, entries, policy);
    _palette
      ..clear()
      ..addAll(merged);
    for (final e in _palette) {
      if (e.group.isNotEmpty && !_paletteGroups.contains(e.group)) {
        _paletteGroups.add(e.group);
      }
    }
    notice = strings.msgColorsMerged(entries.length);
    error = null;
    _persist();
    _notify();
  }

  Future<void> copyPaletteSelection(
    Set<RgbColor> colors, {
    required bool flutter,
  }) async {
    final entries = _palette.where((e) => colors.contains(e.color)).toList();
    if (entries.isNotEmpty) {
      await _copy(
        copyPalette(entries, flutter: flutter),
        message: () => strings.msgPaletteCodeCopied(
          entries.length,
          flutter ? 'Flutter' : 'CSS',
        ),
      );
    }
  }

  List<MeasurementRecord> filterMeasurements(
    String query, {
    bool favoritesOnly = false,
  }) {
    final q = query.trim().toLowerCase();
    return _measurements
        .where(
          (r) =>
              (!favoritesOnly || r.favorite) &&
              '${r.name} ${r.label} ${r.displayName} ${r.measurement.mode.name} ${r.createdAt.toIso8601String()}'
                  .toLowerCase()
                  .contains(q),
        )
        .toList();
  }

  void updateMeasurement(
    MeasurementRecord record, {
    String? name,
    bool? favorite,
  }) {
    final i = _measurements.indexOf(record);
    if (i < 0) return;
    _measurements[i] = record.copyWith(name: name?.trim(), favorite: favorite);
    _trimMeasurements();
    _persist();
    _notify();
  }

  void removeMeasurement(MeasurementRecord record) {
    _measurements.remove(record);
    _persist();
    _notify();
  }

  void _trimMeasurements() {
    while (_measurements.length > measurementHistoryLimit) {
      // 始终保留最新测量，其余优先保留收藏；收藏不能绕过总量限制。
      final index = _measurements.lastIndexWhere((r) => !r.favorite);
      _measurements.removeAt(index <= 0 ? _measurements.length - 1 : index);
    }
  }

  Future<void> exportMeasurements(
    List<MeasurementRecord> records, {
    required bool csv,
  }) async {
    if (records.isEmpty) return;
    String cell(Object value) {
      var text = value.toString();
      if (RegExp(r'^[=+@\-\t\r]').hasMatch(text)) text = "'$text";
      return '"${text.replaceAll('"', '""')}"';
    }

    final text = csv
        ? [
            'name,favorite,mode,width_px,height_px,width_pt,height_pt,scale_x,scale_y,display,created_at',
            for (final r in records)
              [
                r.name,
                r.favorite,
                r.measurement.mode.name,
                r.measurement.rect.width,
                r.measurement.rect.height,
                r.measurement.logicalWidth,
                r.measurement.logicalHeight,
                r.scaleX,
                r.scaleY,
                r.displayName,
                r.createdAt.toIso8601String(),
              ].map(cell).join(','),
          ].join('\r\n')
        : const JsonEncoder.withIndent('  ').convert({
            'version': 1,
            'measurements': records
                .map(
                  (r) => {
                    ...r.toJson(),
                    'scaleX': r.scaleX,
                    'scaleY': r.scaleY,
                  },
                )
                .toList(),
          });
    try {
      if (await desktop.saveTextFile(
        'fruler-measurements.${csv ? 'csv' : 'json'}',
        text,
      )) {
        notice = strings.msgMeasurementsExported(records.length);
        error = null;
        _notify();
      }
    } catch (e, stackTrace) {
      _logFailure('Measurement history export', e, stackTrace);
      _fail(strings.msgMeasurementsExportFailed(describeError(e)));
    }
  }

  Future<void> copyColor([RgbColor? color]) async {
    final value = color ?? selectedColor;
    selectedColor = value;
    await _copy(formatColor(value));
  }

  Future<void> copyMeasurement(MeasurementRecord record) => _copy(record.label);
  Future<void> _copy(String text, {String Function()? message}) async {
    try {
      await desktop.writeClipboard(text);
      _logger.info('Clipboard write completed.');
      notice = message?.call() ?? strings.msgCopied(text);
      error = null;
      _notify();
    } catch (e, stackTrace) {
      _logFailure('Clipboard write', e, stackTrace);
      _fail(describeError(e));
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
      'language': _language.name,
      'recordingOptions': recordingOptions.toJson(),
      'colorHistoryLimit': colorHistoryLimit,
      'measurementHistoryLimit': measurementHistoryLimit,
      'annotationColors': _annotationColors,
      'format': format.name,
      'colorOutputs': _colorOutputs.map((e) => e.toJson()).toList(),
      'selectedOutputId': selectedOutputId,
      'pickerBehavior': pickerBehavior.toJson(),
      'mode': mode.name,
      'tolerance': tolerance,
      'zoom': zoom,
      'continuousPicker': continuousPicker,
      'contrastForeground': contrastForeground.toJson(),
      'contrastBackground': contrastBackground.toJson(),
      'palette': _palette.map((e) => e.toJson()).toList(),
      'paletteGroups': _paletteGroups,
      'shortcuts': shortcuts.toJson(),
      'colors': _colors.map((c) => c.toJson()).toList(),
      'measurements': _measurements.map((r) => r.toJson()).toList(),
    });
    unawaited(
      desktop.saveState(json).catchError((Object e, StackTrace stackTrace) {
        _logFailure('State save', e, stackTrace);
        _fail(strings.msgHistorySaveFailed(describeError(e)));
      }),
    );
  }

  void _restore(String saved) {
    try {
      final data = jsonDecode(saved) as Map<String, dynamic>;
      recordingOptions = RecordingOptions.fromJson(data['recordingOptions']);
      _language = AppLanguage.parse(data['language']);
      _localeNotifier.value = _language.resolve(_systemLocale);
      var ignoredRecords = 0;
      var trimmedHistory = false;
      final colorLimit = data['colorHistoryLimit'];
      final measurementLimit = data['measurementHistoryLimit'];
      if (colorLimit is int && historyLimitChoices.contains(colorLimit)) {
        _colorHistoryLimit = colorLimit;
      }
      if (measurementLimit is int &&
          historyLimitChoices.contains(measurementLimit)) {
        _measurementHistoryLimit = measurementLimit;
      }
      final annotationColors = data['annotationColors'];
      if (annotationColors is Map) {
        for (final tool in _annotationColorTools) {
          final color = annotationColors[tool];
          if (color is int && color >= 0 && color <= 0xFFFFFFFF) {
            _annotationColors[tool] = color;
          }
        }
      }
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
      } catch (e, stackTrace) {
        _logFailure('Shortcut restore', e, stackTrace);
        notice = strings.msgShortcutsRestored;
      }
      continuousPicker = data['continuousPicker'] == true;
      selectedOutputId = format.name;
      if (data['colorOutputs'] is List) {
        final restored = <ColorOutput>[];
        for (final value in (data['colorOutputs'] as List).take(24)) {
          try {
            final output = ColorOutput.fromJson(value);
            if (!restored.any(
              (e) =>
                  e.id == output.id ||
                  e.name.toLowerCase() == output.name.toLowerCase(),
            )) {
              restored.add(output);
            }
          } catch (_) {
            ignoredRecords++;
          }
        }
        if (restored.any((e) => e.enabled)) {
          _colorOutputs
            ..clear()
            ..addAll(restored);
        }
        selectedOutputId = data['selectedOutputId'] is String
            ? data['selectedOutputId'] as String
            : selectedOutputId;
      }
      _ensureActiveOutput();
      pickerBehavior = PickerBehavior(
        primary: continuousPicker
            ? PickerMouseAction.pickAndContinue
            : PickerMouseAction.pickAndClose,
      );
      try {
        if (data['pickerBehavior'] != null) {
          pickerBehavior = PickerBehavior.fromJson(data['pickerBehavior']);
        }
      } catch (_) {}
      continuousPicker =
          pickerBehavior.primary == PickerMouseAction.pickAndContinue;
      try {
        contrastForeground = RgbColor.fromJson(data['contrastForeground']);
      } catch (_) {}
      try {
        contrastBackground = RgbColor.fromJson(data['contrastBackground']);
      } catch (_) {}
      for (final value in (data['paletteGroups'] as List? ?? [])) {
        if (value is String &&
            value.trim().isNotEmpty &&
            value.trim().length <= 60 &&
            !_paletteGroups.contains(value.trim())) {
          _paletteGroups.add(value.trim());
        }
      }
      for (final value in (data['palette'] as List? ?? [])) {
        try {
          final entry = PaletteEntry.fromJson(value);
          if (!_palette.any((e) => e.color == entry.color)) _palette.add(entry);
          if (entry.group.isNotEmpty && !_paletteGroups.contains(entry.group)) {
            _paletteGroups.add(entry.group);
          }
        } catch (_) {
          ignoredRecords++;
        }
      }
      final savedZoom = data['zoom'];
      if (savedZoom is int && CaptureControls.zoomLevels.contains(savedZoom)) {
        zoom = savedZoom;
      }
      final value = data['tolerance'];
      if (value is int) tolerance = value.clamp(0, 255);
      for (final value in (data['colors'] as List? ?? [])) {
        try {
          final c = RgbColor.fromJson(value);
          if (!_colors.contains(c)) {
            if (_colors.length < colorHistoryLimit) {
              _colors.add(c);
            } else {
              trimmedHistory = true;
            }
          }
        } catch (_) {
          ignoredRecords++;
        }
      }
      for (final value in (data['measurements'] as List? ?? [])) {
        try {
          _measurements.add(
            MeasurementRecord.fromJson(value as Map<String, dynamic>),
          );
          if (_measurements.length > measurementHistoryLimit) {
            trimmedHistory = true;
            _trimMeasurements();
          }
        } catch (_) {
          ignoredRecords++;
        }
      }
      if (ignoredRecords > 0) {
        _logger.warning(
          'State restored with invalid records ignored: count=$ignoredRecords.',
        );
      }
      if (_colors.isNotEmpty) selectedColor = _colors.first;
      if (trimmedHistory) {
        _logger.info('Restored history compacted to configured limits.');
        _persist();
      }
    } catch (e, stackTrace) {
      _logFailure('State restore', e, stackTrace);
      notice = strings.msgHistoryRestoreFailed;
    }
  }

  void _logFailure(String operation, Object error, StackTrace stackTrace) {
    // 平台错误可能包含用户路径或剪贴板内容，只保留错误类型和稳定代码。
    final code = error is PlatformException ? ', code=${error.code}' : '';
    _logger.warning(
      '$operation failed: errorType=${error.runtimeType}$code.',
      null,
      stackTrace,
    );
  }

  String describeError(Object e) {
    if (e is ValidationException) {
      return switch (e.code) {
        'annotationCount' => strings.validationAnnotationCount,
        'annotationInvalid' => strings.validationAnnotationInvalid,
        'annotationStyle' => strings.validationAnnotationStyle,
        'annotationPoints' => strings.validationAnnotationPoints,
        'annotationCoordinates' => strings.validationAnnotationCoordinates,
        'annotationBounds' => strings.validationAnnotationBounds,
        'annotationEndpoints' => strings.validationAnnotationEndpoints,
        'annotationLimit' => strings.validationAnnotationLimit,
        'hexColor' => strings.validationHexColor,
        'hslValue' => strings.validationHslValue,
        'rgbValue' => strings.validationRgbValue,
        'paletteEntry' => strings.validationPaletteEntry,
        'paletteVersion' => strings.validationPaletteVersion,
        'paletteLimit' => strings.validationPaletteLimit,
        'paletteMetadata' => strings.validationPaletteMetadata,
        'paletteChannels' => strings.validationPaletteChannels,
        'paletteDuplicates' => strings.validationPaletteDuplicates,
        'outputInvalid' => strings.validationOutputInvalid,
        'outputName' => strings.validationOutputName,
        'outputTemplate' => strings.validationOutputTemplate,
        'outputSubstitution' => strings.validationOutputSubstitution,
        'pickerBehavior' => strings.validationPickerBehavior,
        'outputLimit' => strings.validationOutputLimit,
        'outputNameDuplicate' => strings.validationOutputNameDuplicate,
        'imageSize' => strings.validationImageSize,
        'imageFormat' => strings.validationImageFormat,
        'imageDecode' => strings.validationImageDecode,
        'imageAnnotationsEmpty' => strings.validationImageAnnotationsEmpty,
        'imageExport' => strings.validationImageExport,
        'shortcut' => strings.validationShortcut,
        'shortcutBindings' => strings.validationShortcutBindings,
        'shortcutDuplicates' => strings.validationShortcutDuplicates,
        'outputPlaceholder' => strings.validationOutputPlaceholder(
          e.arguments['token'] as String,
        ),
        'imageFileLimit' => strings.validationImageFileLimit(
          e.arguments['limit'] as int,
        ),
        _ => strings.msgOperationFailed,
      };
    }
    if (e is PlatformException) {
      return switch (e.code) {
        'screen_permission' => strings.msgScreenPermissionRequired,
        'capture_cancelled' => strings.msgCaptureCancelled,
        'shortcut_conflict' => strings.msgShortcutConflict,
        'shortcut_invalid' => strings.msgShortcutUnavailable,
        'capture_busy' => strings.msgCaptureBusy,
        'pin_failed' => e.message ?? strings.msgSystemOperationFailed,
        'recording_failed' ||
        'recording_options' ||
        'recording_region' ||
        'recording_save' ||
        'recording_busy' => e.message ?? strings.msgSystemOperationFailed,
        _ => strings.msgSystemOperationFailed,
      };
    }
    if (e is UnsupportedError) return strings.msgUnsupportedPlatform;
    return strings.msgOperationFailed;
  }

  void _fail(String message) {
    error = message;
    notice = null;
    _notify();
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _logger.info('Controller disposed.');
    _disposed = true;
    _recordingGeneration++;
    if (screenRecording || recordingTransition) {
      unawaited(
        desktop.cancelRecording().catchError((Object e, StackTrace stackTrace) {
          _logFailure('Disposed recording cleanup', e, stackTrace);
        }),
      );
    }
    _subscription?.cancel();
    final id = _session?.id;
    _resetSession();
    if (id != null) {
      unawaited(
        desktop.finish(id).catchError((Object e, StackTrace stackTrace) {
          _logFailure('Disposed capture cleanup', e, stackTrace);
        }),
      );
    }
    markup.removeListener(_notify);
    markup.dispose();
    _localeNotifier.dispose();
    super.dispose();
  }
}
