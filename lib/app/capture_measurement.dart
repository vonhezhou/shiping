part of 'app_controller.dart';

class CaptureMeasurementPin {
  const CaptureMeasurementPin(
    this.id,
    this.displayId,
    this.measurement, [
    this.seed,
  ]);
  final PixelPoint? seed;
  final int id, displayId;
  final RulerMeasurement measurement;
}

extension CaptureMeasurements on AppController {
  List<CaptureMeasurementPin> get captureMeasurementPins => _pins.map((pin) {
    final display = _session!.displays.firstWhere(
      (d) => d.id == pin['displayId'],
    );
    return CaptureMeasurementPin(
      pin['id'] as int,
      display.id,
      RulerMeasurement.fromRect(
        display.frame,
        _pinRect(pin),
        RulerMode.values.byName(pin['mode'] as String? ?? 'rectangle'),
      ),
      pin['seedX'] == null
          ? null
          : PixelPoint(pin['seedX'] as int, pin['seedY'] as int),
    );
  }).toList();

  int? get selectedCaptureMeasurement => _selectedPin;
  RulerMeasurement? get captureRulerPreview => _captureRulerPreview;
  PixelPoint? get captureRulerSeed => _captureRulerSeed;
  bool get canUndoCaptureMeasurements => _pinUndo.isNotEmpty;
  bool get canRedoCaptureMeasurements => _pinRedo.isNotEmpty;

  void toggleCaptureRuler() => setCaptureRulerMode(
    captureRulerMode == null
        ? (screenshotEditing ? RulerMode.cross : RulerMode.rectangle)
        : null,
  );

  void setCaptureRulerMode(RulerMode? mode) {
    if (!_captureSession ||
        _committing ||
        screenshotExporting ||
        imageLoading ||
        (screenshotEditing && mode == RulerMode.rectangle)) {
      return;
    }
    _finishPinDrag();
    captureRulerMode = mode;
    _captureRulerPreview = null;
    _captureRulerDisplay = null;
    _selectedPin = null;
    _anchor = null;
    _anchorDisplay = null;
    _selectionPress = null;
    _pressedCandidate = null;
    _captureMeasurement = null;
    _editingPins = false;
    if (!screenshotEditing) {
      _tool = mode?.name ?? 'screenshot';
      _redraw();
    }
    _notify();
  }

  void cancelCaptureInteraction() {
    if (_anchor != null || _pinDrag != null) {
      final drag = _pinDrag;
      if (drag != null) {
        _pins
          ..clear()
          ..addAll(drag.snapshot);
        _pinDrag = null;
      }
      _anchor = null;
      _anchorDisplay = null;
      _selectionPress = null;
      _pressedCandidate = null;
      _captureRulerPreview = null;
      _redraw();
      _notify();
    } else if (captureRulerMode != null) {
      setCaptureRulerMode(null);
    } else {
      unawaited(cancelScreenshot());
    }
  }

  void updateCaptureRulerPointer(double x, double y) {
    if (!screenshotEditing ||
        captureRulerMode == null ||
        captureRulerMode == RulerMode.rectangle ||
        !x.isFinite ||
        !y.isFinite) {
      return;
    }
    final display = _session!.displays.firstWhere(
      (d) => d.id == screenshotDisplayId,
    );
    final point = display.frame.logicalToPixel(x, y);
    _captureRulerPreview = EdgeDetector.measure(
      display.frame,
      point.x,
      point.y,
      captureRulerMode!,
      tolerance: tolerance,
    );
    _captureRulerDisplay = display.id;
    _captureRulerSeed = point;
    _selectedPin = null;
    _notify();
  }

  void fixCaptureRulerPreview() {
    final measurement = _captureRulerPreview, display = _captureRulerDisplay;
    if (captureRulerMode == null || measurement == null || display == null) {
      return;
    }
    _fixCaptureMeasurement(measurement, display);
  }

  void _fixCaptureMeasurement(RulerMeasurement measurement, int displayId) {
    _rememberPins();
    _pins.add({
      'id': ++_nextPinId,
      'displayId': displayId,
      'rect': measurement.rect.toJson(),
      'label': measurement.label,
      'mode': measurement.mode.name,
      if (_captureRulerSeed != null) 'seedX': _captureRulerSeed!.x,
      if (_captureRulerSeed != null) 'seedY': _captureRulerSeed!.y,
    });
    _selectedPin = _nextPinId;
    _anchor = null;
    _anchorDisplay = null;
    _selectionPress = null;
    _captureRulerPreview = null;
    if (!screenshotEditing) _redraw();
    _notify();
  }

  void selectCaptureMeasurement(int? id) {
    _selectedPin = _pins.any((p) => p['id'] == id) ? id : null;
    _captureRulerPreview = null;
    _notify();
  }

  void deleteCaptureMeasurement() {
    if (_selectedPin == null) return;
    _rememberPins();
    _pins.removeWhere((p) => p['id'] == _selectedPin);
    _selectedPin = null;
    _notify();
  }

  void captureMeasurementHistory(bool redo) {
    final from = redo ? _pinRedo : _pinUndo, to = redo ? _pinUndo : _pinRedo;
    if (from.isEmpty) return;
    to.add(List.of(_pins));
    if (to.length > 64) to.removeAt(0);
    _pins
      ..clear()
      ..addAll(from.removeLast());
    _selectedPin = null;
    _notify();
  }

  void toggleCaptureMeasurementsVisibility() {
    captureMeasurementsVisible = !captureMeasurementsVisible;
    _notify();
  }

  void adjustCaptureTolerance(int steps) {
    setTolerance(CaptureControls.adjustTolerance(tolerance, steps));
  }

  Future<void> useMeasurementSelection() async {
    if (!_captureSession || screenshotEditing || _committing) return;
    final pin = captureMeasurementPins
        .where((p) => p.id == _selectedPin)
        .firstOrNull;
    if (pin == null || pin.measurement.mode != RulerMode.rectangle) return;
    final display = _session!.displays.firstWhere((d) => d.id == pin.displayId);
    await _commitScreenshot(pin.measurement, display);
  }

  Future<void> copyCaptureMeasurements({bool all = false}) async {
    if (!_captureSession || _committing || screenshotExporting) return;
    final pins = captureMeasurementPins;
    final selected = pins.where((p) => p.id == _selectedPin).firstOrNull;
    final values = all
        ? pins
        : selected != null
        ? [selected]
        : _captureRulerPreview != null && _captureRulerDisplay != null
        ? [
            CaptureMeasurementPin(
              0,
              _captureRulerDisplay!,
              _captureRulerPreview!,
            ),
          ]
        : <CaptureMeasurementPin>[];
    if (values.isEmpty) return;
    final sessionId = _session!.id;
    _committing = true;
    try {
      final text = all
          ? values.map((p) => '#${p.id} ${p.measurement.label}').join('\n')
          : values.single.measurement.label;
      await desktop.writeClipboard(text);
      if (_session?.id != sessionId) return;
      for (final pin in values) {
        _measurements.insert(
          0,
          MeasurementRecord(
            measurement: pin.measurement,
            createdAt: DateTime.now(),
            displayName: _session!.displays
                .firstWhere((d) => d.id == pin.displayId)
                .name,
          ),
        );
      }
      _trimMeasurements();
      _persist();
      await desktop.finish(sessionId);
      _resetSession();
      notice = '尺寸已复制';
      error = null;
    } catch (e) {
      if (_session?.id == sessionId) error = '尺寸复制失败：${_message(e)}';
    } finally {
      if (_session?.id == sessionId) _committing = false;
      _notify();
    }
  }
}
