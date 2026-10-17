import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/core.dart';
import '../platform/desktop_service.dart';
import '../platform/image_document.dart';

enum AppSection { picker, ruler, image, settings }

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

class _ImageDraft {
  _ImageDraft(
    this.pins,
    this.undo,
    this.redo,
    this.tool,
    this.selected,
    this.editing,
    this.tolerance,
    this.zoom,
  );
  final List<Map<String, Object?>> pins;
  final List<List<Map<String, Object?>>> undo, redo;
  final String tool;
  final int? selected;
  final bool editing;
  final int tolerance, zoom;
}

class AppController extends ChangeNotifier {
  AppController(this.desktop, {ImageDocumentCodec? imageCodec})
    : imageCodec = imageCodec ?? ImageDocumentCodec();
  final ImageDocumentCodec imageCodec;
  final DesktopService desktop;
  ImageDocument? imageDocument;
  ImageProjectView? imageView;
  String? imageProjectName;
  String? imageProjectPath;
  List<ProjectLocation> recentImageProjects = [];
  String? recoveryDraft;
  bool _recoveryReadFailed = false;
  bool get recoveryPending => recoveryDraft != null || _recoveryReadFailed;
  bool draftSaving = false;
  String? draftError;
  DateTime? draftSavedAt;
  Timer? _draftDebounce, _draftPeriodic;
  String? _observedDraftSignature, _writtenDraftSignature;
  Future<void> _draftWrites = Future.value();
  String? _pendingProjectPath;

  ImageProject _currentImageProject() {
    final document = imageDocument!;
    return ImageProject(
      name: document.name,
      png: document.png,
      width: document.frame.width,
      height: document.frame.height,
      annotations: List.of(_imagePins),
      tool: imageTool,
      view: imageView,
      tolerance: _imageSession
          ? tolerance
          : _imageDraft?.tolerance ?? tolerance,
      zoom: _imageSession ? zoom : _imageDraft?.zoom ?? zoom,
    );
  }

  String _draftSignature() =>
      '${_imageSignature()}|$imageProjectPath|$_savedImageSignature';
  void _scheduleDraft() {
    if (initializing || recoveryPending || imageDocument == null) return;
    final signature = _draftSignature();
    if (signature == _observedDraftSignature) return;
    _observedDraftSignature = signature;
    _draftDebounce?.cancel();
    _draftDebounce = Timer(
      const Duration(seconds: 2),
      () => unawaited(flushImageDraft()),
    );
  }

  Future<void> _writeDraft(String? text) {
    final next = _draftWrites
        .catchError((Object _) {})
        .then((_) => desktop.saveImageDraft(text));
    _draftWrites = next;
    return next;
  }

  Future<bool> flushImageDraft() async {
    if (_disposed || recoveryPending || imageDocument == null || draftSaving) {
      return false;
    }
    final signature = _draftSignature();
    if (signature == _writtenDraftSignature) return true;
    draftSaving = true;
    try {
      final now = DateTime.now();
      final text = jsonEncode({
        'version': 1,
        'savedAt': now.toIso8601String(),
        'project': jsonDecode(_currentImageProject().encode()),
        'location': imageProjectPath == null
            ? null
            : {'name': imageProjectName, 'path': imageProjectPath},
        'dirty': imageProjectDirty,
      });
      await _writeDraft(text);
      _writtenDraftSignature = signature;
      draftSavedAt = now;
      draftError = null;
      return true;
    } catch (_) {
      draftError = '本地草稿保存失败，请手动保存项目；稍后会自动重试。';
      return false;
    } finally {
      draftSaving = false;
      _notify();
    }
  }

  Future<void> _clearImageDraft() async {
    _draftDebounce?.cancel();
    _observedDraftSignature = null;
    _writtenDraftSignature = null;
    await _writeDraft(null);
    _draftDebounce?.cancel();
    _observedDraftSignature = null;
    _writtenDraftSignature = null;
    draftSavedAt = null;
    draftError = null;
  }

  Future<void> discardRecovery() async {
    if (!recoveryPending || imageLoading) return;
    try {
      await _clearImageDraft();
      recoveryDraft = null;
      _recoveryReadFailed = false;
      _notify();
      _openPendingProject();
    } catch (_) {
      _fail('无法清除本地草稿，请重试');
    }
  }

  Future<void> restoreImageDraft() async {
    if (!recoveryPending || busy || imageLoading || imageSaving) return;
    imageLoading = true;
    _notify();
    try {
      if (_recoveryReadFailed) {
        recoveryDraft = await desktop.loadImageDraft();
        _recoveryReadFailed = false;
        if (recoveryDraft == null) {
          _notify();
          return;
        }
      }
      final value = jsonDecode(recoveryDraft!);
      if (value is! Map || value['version'] != 1 || value['dirty'] is! bool) {
        throw const FormatException('草稿格式无效');
      }
      final project = ImageProject.decode(jsonEncode(value['project']));
      final document = await _decodeProject(project);
      final location = value['location'];
      if (location != null &&
          (location is! Map ||
              location['path'] is! String ||
              location['name'] is! String)) {
        throw const FormatException('草稿位置无效');
      }
      if (_disposed) return;
      _installProject(
        project,
        document,
        name: location?['name'] as String?,
        path: location?['path'] as String?,
      );
      if (value['dirty'] == true) _savedImageSignature = null;
      draftSavedAt = DateTime.tryParse(value['savedAt']?.toString() ?? '');
      recoveryDraft = null;
      notice = '已恢复上次图片工作；原项目文件未被自动覆盖';
      error = null;
    } catch (_) {
      _fail('无法恢复本地草稿，可保留后重试，或选择丢弃草稿');
    } finally {
      imageLoading = false;
      _notify();
    }
    _openPendingProject();
  }

  void _openPendingProject() {
    if (recoveryPending || _pendingProjectPath == null) return;
    final path = _pendingProjectPath!;
    _pendingProjectPath = null;
    unawaited(openImageProject(path: path));
  }

  Future<ImageDocument> _decodeProject(ImageProject project) async {
    final document = await imageCodec.decodeProjectPng(
      ImageFileData(project.name, project.png),
    );
    if (document.frame.width != project.width ||
        document.frame.height != project.height) {
      throw const FormatException('项目图片尺寸与元数据不一致');
    }
    return document;
  }

  void _installProject(
    ImageProject project,
    ImageDocument document, {
    String? name,
    String? path,
  }) {
    _imageDraft = null;
    if (_imageSession) _resetSession();
    imageDocument = document;
    _imageEpoch++;
    imageView = project.view;
    imageProjectName = name;
    imageProjectPath = path;
    draftSavedAt = null;
    draftError = null;
    useImageTool(project.tool);
    tolerance = project.tolerance;
    zoom = project.zoom;
    _pins.addAll(project.annotations);
    for (final pin in _pins) {
      if ((pin['id'] as int) > _nextPinId) _nextPinId = pin['id'] as int;
    }
    _savedImageSignature = _imageSignature();
    _redraw();
  }

  void _rememberProject(ProjectLocation location) {
    recentImageProjects = [
      location,
      ...recentImageProjects.where((e) => e.path != location.path),
    ].take(12).toList();
  }

  bool imageSaving = false;
  Future<bool> Function()? confirmImageReplacement;
  Future<bool> Function()? confirmImageQuit;
  bool _retainDraftForQuit = false;
  Future<bool> keepImageDraftForQuit() async {
    if (draftSaving) await _draftWrites;
    _retainDraftForQuit = await flushImageDraft();
    return _retainDraftForQuit;
  }

  bool _confirming = false, _askingToQuit = false;
  int _imageEpoch = 0;
  String? _savedImageSignature;
  _ImageDraft? _imageDraft;
  List<Map<String, Object?>> get _imagePins =>
      _imageSession ? _pins : _imageDraft?.pins ?? [];
  String _imageSignature() => jsonEncode({
    'epoch': _imageEpoch,
    'pins': _imagePins,
    'tool': imageTool,
    'view': imageView?.toJson(),
    'zoom': _imageSession ? zoom : _imageDraft?.zoom ?? zoom,
    'tolerance': _imageSession
        ? tolerance
        : _imageDraft?.tolerance ?? tolerance,
  });
  bool get imageProjectDirty =>
      imageDocument != null && _imageSignature() != _savedImageSignature;
  Future<bool> allowImageReplacement() async {
    if (!imageProjectDirty || confirmImageReplacement == null) return true;
    if (_confirming) return false;
    _confirming = true;
    try {
      return await confirmImageReplacement!();
    } finally {
      _confirming = false;
    }
  }

  void updateImageView(ImageProjectView view) {
    if (imageDocument == null ||
        jsonEncode(imageView?.toJson()) == jsonEncode(view.toJson())) {
      return;
    }
    imageView = view;
    _notify();
  }

  Future<void> openImageProject({String? path}) async {
    if (recoveryPending) {
      _pendingProjectPath = path;
      section = AppSection.image;
      notice = '已保留待打开项目，请先恢复或丢弃上次的草稿';
      error = null;
      _notify();
      return;
    }
    if (busy || imageLoading || imageSaving) {
      if (path != null) _pendingProjectPath = path;
      return;
    }
    imageLoading = true;
    _notify();
    try {
      final file = await desktop.openProjectFile(path: path);
      if (file == null) return;
      final project = ImageProject.decode(file.text);
      final document = await _decodeProject(project);
      if (_disposed || !await allowImageReplacement() || _disposed) return;
      _installProject(project, document, name: file.name, path: file.path);
      if (file.path != null) {
        _rememberProject(ProjectLocation(file.name, file.path!));
      }
      notice = '项目已打开：${file.name}';
      error = null;
    } catch (e) {
      _fail(
        e is FormatException
            ? e.message
            : '无法打开图片项目：${_message(e)}。可重新选择文件获取访问权限。',
      );
    } finally {
      imageLoading = false;
      _notify();
      _openPendingProject();
    }
  }

  Future<bool> saveImageProject({bool saveAs = false}) async {
    final document = imageDocument;
    if (document == null || imageSaving || busy) return false;
    _finishPinDrag();
    if (_imageSession) _redraw();
    final signature = _imageSignature();
    imageSaving = true;
    _notify();
    try {
      final text = _currentImageProject().encode();
      if (utf8.encode(text).length > ImageProject.maxFileBytes) {
        throw const FormatException('项目文件超过 128 MB，无法保存');
      }
      final location = await desktop.saveProjectFile(
        text,
        path: saveAs ? null : imageProjectPath,
      );
      if (location != null && identical(imageDocument, document)) {
        _savedImageSignature = signature;
        imageProjectName = location.name;
        imageProjectPath = location.path;
        _rememberProject(location);
        notice = '图片项目已保存';
        error = null;
      }
      return location != null;
    } catch (e) {
      _fail(
        e is FormatException ? e.message : '图片项目保存失败：${_message(e)}。可尝试另存为。',
      );
      return false;
    } finally {
      imageSaving = false;
      _notify();
      _openPendingProject();
    }
  }

  void _suspendImage() {
    if (!_imageSession) return;
    _finishPinDrag();
    _imageDraft = _ImageDraft(
      List.of(_pins),
      List.of(_pinUndo),
      List.of(_pinRedo),
      _tool ?? 'picker',
      _selectedPin,
      _editingPins,
      tolerance,
      zoom,
    );
  }

  Map<String, Object?> imageOverlay = {};
  bool imageLoading = false;
  bool _imageSession = false;
  int _nextImageSession = -1;
  bool get imageSessionActive => _imageSession;
  String get imageTool =>
      _imageSession ? _tool ?? 'picker' : _imageDraft?.tool ?? 'picker';
  Future<void> openImage() async {
    if (busy || imageLoading || imageSaving || recoveryPending) return;
    imageLoading = true;
    _notify();
    try {
      final file = await desktop.openImageFile();
      imageLoading = false;
      if (file != null) await loadImage(file);
    } catch (e) {
      _fail(e is FormatException ? e.message : _message(e));
    } finally {
      imageLoading = false;
      _notify();
    }
  }

  Future<void> loadImage(ImageFileData file) async {
    if (busy || imageLoading || imageSaving || _disposed || recoveryPending) {
      return;
    }
    imageLoading = true;
    error = null;
    _notify();
    try {
      final document = await imageCodec.decode(file);
      if (_disposed || !await allowImageReplacement() || _disposed) return;
      _imageDraft = null;
      imageView = null;
      imageProjectName = null;
      imageProjectPath = null;
      draftSavedAt = null;
      draftError = null;
      _savedImageSignature = null;
      _imageEpoch++;
      if (_imageSession) _resetSession();
      imageDocument = document;
      section = AppSection.image;
      useImageTool('picker');
      notice = '图片已打开：${document.name}';
    } catch (e) {
      _fail(e is FormatException ? e.message : '无法读取图片，请检查格式或文件内容');
    } finally {
      imageLoading = false;
      _notify();
      _openPendingProject();
    }
  }

  void useImageTool(String tool) {
    final restoring = !_imageSession ? _imageDraft : null;
    if (busy ||
        imageDocument == null ||
        !['picker', ...RulerMode.values.map((e) => e.name)].contains(tool)) {
      return;
    }
    if (!_imageSession) {
      _resetSession();
      _imageSession = true;
      final draft = _imageDraft;
      if (draft != null) {
        _pins.addAll(draft.pins);
        _pinUndo.addAll(draft.undo);
        _pinRedo.addAll(draft.redo);
        tolerance = draft.tolerance;
        zoom = draft.zoom;
      }
      _session = CaptureSession(_nextImageSession--, [
        CapturedDisplay(
          id: 0,
          name: '图片：${imageDocument!.name}',
          frame: imageDocument!.frame,
        ),
      ]);
    }
    _tool = tool;
    _contrastTarget = null;
    _contrastPair = false;
    if (tool != 'picker') mode = RulerMode.values.byName(tool);
    _anchor = null;
    _anchorDisplay = null;
    _editingPins = restoring?.editing ?? false;
    _selectedPin = restoring?.selected ?? _selectedPin;
    _keyboardRectangle = false;
    section = AppSection.image;
    _redraw();
    _notify();
  }

  void imageEvent(String type, [Map<String, Object?> data = const {}]) {
    if (!_imageSession || imageSaving) return;
    _event({'type': type, 'sessionId': _session!.id, 'displayId': 0, ...data});
  }

  Future<void> closeImage() async {
    if (imageSaving || imageLoading || !await allowImageReplacement()) return;
    imageLoading = true;
    try {
      await _clearImageDraft();
    } catch (_) {
      imageLoading = false;
      _fail('无法清除本地草稿，图片仍保留，请重试');
      return;
    }
    imageLoading = false;
    if (_imageSession) _resetSession();
    imageDocument = null;
    imageView = null;
    imageProjectName = null;
    imageProjectPath = null;
    _imageDraft = null;
    _savedImageSignature = null;
    imageOverlay = {};
    _notify();
  }

  AppSection section = AppSection.picker;
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
      _fail('分组名称需为 1–60 个字符，且不能重复');
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
      _fail('分组名称需为 1–60 个字符，且不能重复');
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
  bool _openingColorEditor = false;
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
        throw const FormatException('最多保留 24 种颜色格式');
      }
      name = name.trim();
      if (_colorOutputs.any(
        (e) => e.id != id && e.name.toLowerCase() == name.toLowerCase(),
      )) {
        throw const FormatException('格式名称不能重复');
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
      _notify();
      return true;
    } on FormatException catch (e) {
      _fail(e.message);
      return false;
    }
  }

  bool enableColorOutput(String id, bool enabled) {
    final index = _colorOutputs.indexWhere((e) => e.id == id);
    if (index < 0) return false;
    if (!enabled &&
        enabledColorOutputs.length == 1 &&
        _colorOutputs[index].enabled) {
      _fail('至少保留一种启用的颜色格式');
      return false;
    }
    _colorOutputs[index] = _colorOutputs[index].copyWith(enabled: enabled);
    _ensureActiveOutput();
    _persist();
    _notify();
    return true;
  }

  bool deleteColorOutput(String id) {
    final entry = _colorOutputs.where((e) => e.id == id).firstOrNull;
    if (entry == null) return false;
    if (entry.enabled && enabledColorOutputs.length == 1) {
      _fail('至少保留一种启用的颜色格式');
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
    continuousPicker = value.primary == PickerMouseAction.pickAndContinue;
    _persist();
    if (_session != null) _redraw();
    _notify();
  }

  Future<void> _openPickedEditor(RgbColor color) async {
    if (_disposed ||
        colorEditorActive ||
        _openingColorEditor ||
        pendingPickedEditorColor != null) {
      return;
    }
    _openingColorEditor = true;
    try {
      await desktop.showMainWindow();
      if (_disposed) return;
      section = AppSection.picker;
      pendingPickedEditorColor = color;
      _notify();
    } catch (e) {
      _fail('无法打开颜色编辑器：${_message(e)}');
    } finally {
      _openingColorEditor = false;
    }
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
      try {
        recentImageProjects = await desktop.recentProjects();
        recoveryDraft = await desktop.loadImageDraft();
        if (recoveryPending) section = AppSection.image;
      } catch (_) {
        _recoveryReadFailed = true;
        section = AppSection.image;
        draftError = '无法读取本地草稿或最近项目，请检查本地存储后重试。';
      }
      await desktop.projectEventsReady();
      _draftPeriodic = Timer.periodic(
        const Duration(seconds: 15),
        (_) => unawaited(flushImageDraft()),
      );
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
    if (value == AppSection.image &&
        imageDocument != null &&
        !_imageSession &&
        !busy) {
      useImageTool(imageTool);
    }
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
    if (pickerBehavior.activation == PickerActivation.editor) {
      return _openPickedEditor(selectedColor);
    }
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

  Future<void> startRuler([RulerMode? value]) {
    if (value != null) selectMode(value);
    return _begin(mode.name);
  }

  Future<void> _begin(String tool) async {
    if (busy ||
        imageLoading ||
        imageSaving ||
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
    if (_imageSession) {
      _suspendImage();
      _resetSession();
    }
    busy = true;
    _tool = tool;
    _committing = false;
    _anchor = null;
    _anchorDisplay = null;
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
      case 'openProject':
        if (event['path'] is String) {
          unawaited(openImageProject(path: event['path'] as String));
        }
        return;
      case 'projectCommand':
        if (recordingShortcut) return;
        switch (event['action']) {
          case 'open':
            unawaited(openImageProject());
          case 'save':
            unawaited(saveImageProject());
          case 'saveAs':
            unawaited(saveImageProject(saveAs: true));
        }
        return;
      case 'quitRequested':
        if (!_askingToQuit) {
          _askingToQuit = true;
          unawaited(() async {
            try {
              _retainDraftForQuit = false;
              final allow = imageProjectDirty && confirmImageQuit != null
                  ? await confirmImageQuit!()
                  : await allowImageReplacement();
              if (allow && !recoveryPending) {
                if (imageProjectDirty && !_retainDraftForQuit) {
                  await _clearImageDraft();
                } else if (imageDocument != null) {
                  if (draftSaving) await _draftWrites;
                  if (!await flushImageDraft()) throw StateError('draft');
                }
              }
              await desktop.replyToQuit(allow);
            } catch (e) {
              await desktop.replyToQuit(false);
              _fail('无法确认退出，请先保存图片项目后重试');
            } finally {
              _askingToQuit = false;
            }
          }());
        }
        return;
      case 'imageDropped':
        if (event['name'] is String && event['bytes'] is Uint8List) {
          unawaited(
            loadImage(
              ImageFileData(
                event['name'] as String,
                event['bytes'] as Uint8List,
              ),
            ),
          );
        }
        return;
      case 'imageDropFailed':
        _fail(event['message'] as String? ?? '无法读取拖入的图片');
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
    if (!busy && !_imageSession) return;
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
      _openPendingProject();
      return;
    }
    if (_committing) return;
    switch (event['type']) {
      case 'continuousChanged':
        setContinuousPicker(event['enabled'] == true);
        return;
      case 'pinDrag':
        _dragPin(event);
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
        if (_editingPins) {
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
        if (_editingPins) return;
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
    'continuous': _contrastTarget == null && continuousPicker,
    'pickerActions': _contrastTarget == null
        ? '左键：${pickerBehavior.primary.label} · 中键：${pickerBehavior.middle.label} · 右键：${pickerBehavior.secondary.label}'
        : '左键 / Enter 确认 · 右键取消',
    'capturePurpose': _contrastTarget == null
        ? ''
        : (_contrastTarget == 'foreground' ? '选取前景色' : '选取背景色'),
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
    if (_imageSession) {
      imageOverlay = {...imageOverlay, ...data};
      _notify();
      return;
    }
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
    if (_editingPins) {
      _updateOverlay({..._overlayOptions, 'displayId': display.id});
      return;
    }
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
        : (_imageSession ? measurement?.pixelLabel : measurement?.label) ??
              '按住并拖拽，测量矩形区域';
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
      if (_imageSession && button != 'primary') return;
      final action = _imageSession
          ? PickerMouseAction.pickAndContinue
          : _contrastTarget != null
          ? (button == 'secondary'
                ? PickerMouseAction.cancel
                : PickerMouseAction.pickAndClose)
          : pickerBehavior.forButton(button);
      unawaited(_commitColor(color, action: action));
    } else if (measurement != null &&
        measurement.rect.width > 0 &&
        measurement.rect.height > 0) {
      unawaited(
        _commitMeasurement(
          measurement,
          display,
          keep:
              _imageSession || (_tool == 'rectangle' && event['keep'] == true),
        ),
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
        notice = '已取消取色';
        error = null;
      } catch (e) {
        _fail('无法关闭取色浮层：${_message(e)}');
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
    if (action == PickerMouseAction.pickAndContinue || _imageSession) {
      try {
        await desktop.writeClipboard(formatColor(color));
        if (_session?.id == sessionId) {
          notice = _imageSession
              ? '已从图片复制 ${color.hex}'
              : '已连续取色 $_pickedCount 次，Esc 结束';
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
      await _complete(formatColor(color));
      if (action == PickerMouseAction.pickAndEdit && !busy) {
        await _openPickedEditor(color);
      }
    }
  }

  Future<void> _commitMeasurement(
    RulerMeasurement measurement,
    CapturedDisplay display, {
    bool keep = false,
  }) async {
    if (_imageSession && keep && _pins.length >= 4096) {
      _fail('图片项目最多支持 4096 个标注');
      return;
    }
    final sessionId = _session!.id;
    _committing = true;
    _measurements.insert(
      0,
      MeasurementRecord(
        measurement: measurement,
        createdAt: DateTime.now(),
        displayName: display.name,
        imageSource: _imageSession,
      ),
    );
    _trimMeasurements();
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
        await desktop.writeClipboard(
          _imageSession ? measurement.pixelLabel : measurement.label,
        );
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
      'label': '${rect.width} × ${rect.height} px',
    };
  }

  void _dragPin(Map<Object?, Object?> event) {
    if (!_editingPins) return;
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
      final done = _imageSession && imageDocument != null
          ? await desktop.exportImage(
              await imageCodec.renderAnnotations(imageDocument!, pins),
              save: save,
            )
          : await desktop.exportAnnotations(
              session.id,
              displayId,
              pins,
              save: save,
            );
      if (done && _session?.id == session.id) {
        notice = save ? '标注图片已导出' : '标注图片已复制';
        error = null;
      }
    } catch (e) {
      if (_session?.id == session.id) _fail('标注图片导出失败：${_message(e)}');
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
        if (id != null && !_imageSession) await desktop.finish(id);
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
      if (id != null && !_imageSession) await desktop.finish(id);
    } catch (_) {
      /* Preserve original failure. */
    }
    _resetSession();
    _fail(_message(e));
  }

  void _resetSession() {
    _session = null;
    _imageSession = false;
    imageOverlay = {};
    _tool = null;
    _contrastTarget = null;
    _contrastPair = false;
    _pinDrag = null;
    busy = false;
    _anchor = null;
    _anchorDisplay = null;
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
        notice = '颜色已导出';
        error = null;
        _notify();
      }
    } catch (e) {
      _fail('颜色导出失败：${_message(e)}');
    }
  }

  Future<List<PaletteEntry>?> readPaletteImport() async {
    try {
      final text = await desktop.openPaletteFile();
      return text == null ? null : importPalette(text);
    } catch (e) {
      _fail(e is FormatException ? e.message : '无法读取调色板文件：${_message(e)}');
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
    notice = '已合并 ${entries.length} 个颜色';
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
        message: '已复制 ${entries.length} 色的 ${flutter ? 'Flutter' : 'CSS'} 代码',
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
    while (_measurements.where((r) => !r.favorite).length > 32) {
      _measurements.removeAt(_measurements.lastIndexWhere((r) => !r.favorite));
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
        notice = '已导出 ${records.length} 条测量记录';
        error = null;
        _notify();
      }
    } catch (e) {
      _fail('测量记录导出失败：${_message(e)}');
    }
  }

  Future<void> copyColor([RgbColor? color]) async {
    final value = color ?? selectedColor;
    selectedColor = value;
    await _copy(formatColor(value));
  }

  Future<void> copyMeasurement(MeasurementRecord record) => _copy(record.label);
  Future<void> _copy(String text, {String? message}) async {
    try {
      await desktop.writeClipboard(text);
      notice = message ?? '已复制 $text';
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
            /* Keep other valid formats and history. */
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
      for (final value in (data['measurements'] as List? ?? [])) {
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
    if (!_disposed) {
      _scheduleDraft();
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _draftDebounce?.cancel();
    _draftPeriodic?.cancel();
    _disposed = true;
    _subscription?.cancel();
    final id = _session?.id;
    if (id != null && !_imageSession) {
      unawaited(desktop.finish(id).catchError((Object _) {}));
    }
    super.dispose();
  }
}
