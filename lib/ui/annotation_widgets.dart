part of 'fruler_app.dart';

class _AnnotationEditor extends StatefulWidget {
  const _AnnotationEditor({super.key, required this.controller});
  final AppController controller;
  @override
  State<_AnnotationEditor> createState() => _AnnotationEditorState();
}

class _AnnotationEditorState extends State<_AnnotationEditor> {
  final focus = FocusNode();
  ui.Image? image;
  Map<int, ui.Image> mosaics = {};
  bool loadFailed = false;
  String tool = 'select';
  Offset? screenPointer;
  String lastShape = 'rectangle', lastLine = 'arrow', lastEffect = 'mosaic';
  bool filled = false,
      bold = false,
      italic = false,
      outlined = false,
      toolbarVisible = true;
  bool effectBrush = false;
  bool eraserBrush = false;
  int effectStrength = 3;
  final textInput = TextEditingController();
  final textFocus = FocusNode();
  Rect? textRect;
  int? textIndex, textCommitPointer;
  final linePoints = <Offset>[];
  Offset? lineHover;
  final styles =
      <
        String,
        ({
          double width,
          double fontSize,
          String fontFamily,
          bool filled,
          bool bold,
          bool italic,
          bool outlined,
          bool effectBrush,
          int effectStrength,
        })
      >{};
  int color = 0xFFFF0000;
  // Toolbar values are logical points; annotations use bitmap pixels.
  double width = 3, fontSize = 24;
  String fontFamily = Annotation.defaultFontFamily;
  List<String> fontFamilies = [];
  final fontMenuController = MenuController();
  bool fontLoadFailed = false;
  double get pixelWidth => width * c.screenshotScaleX;
  double get pixelFontSize => fontSize * c.screenshotScaleY;
  int? selected, pointerId;
  Annotation? preview, original;
  Offset? start, resizeAnchor, eraserEnd, hoverPosition;
  bool textEditing = false, colorPicking = false;
  ({int pointer, Offset start, PixelRect original, String handle})?
  selectionDrag;
  PixelRect? selectionPreview;
  AppController get c => widget.controller;
  List<Annotation> get items => c.markup.items;
  Size get imageSize => Size(
    c.imageDocument!.frame.width.toDouble(),
    c.imageDocument!.frame.height.toDouble(),
  );
  double get scale => 1 / c.screenshotScaleX;
  bool get editable =>
      c.screenshotEditing &&
      !c.imageLoading &&
      !c.imageSaving &&
      !colorPicking &&
      !c.textMode &&
      !c.qrCodeBusy &&
      c.qrCodeResults.isEmpty;
  List<Annotation> get visibleItems {
    final result = List<Annotation>.of(items);
    if (textEditing && textIndex != null && textIndex! < result.length) {
      result.removeAt(textIndex!);
    }
    if (linePoints.isNotEmpty) {
      result.add(
        makeAnnotation(AnnotationKind.line, [
          ...linePoints,
          lineHover ?? linePoints.last,
        ]),
      );
    }
    if (preview != null) {
      if (original != null && selected != null && selected! < result.length) {
        result[selected!] = preview!;
      } else {
        result.add(preview!);
      }
    }
    return result;
  }

  @override
  void initState() {
    super.initState();
    screenPointer = c.screenshotPointer;
    load();
    loadFonts();
  }

  Future<void> loadFonts() async {
    try {
      final families = await c.desktop.availableFontFamilies();
      if (mounted) setState(() => fontFamilies = families);
    } catch (error, stackTrace) {
      Logger('ui.annotation').warning(
        'Font loading failed: errorType=${error.runtimeType}.',
        null,
        stackTrace,
      );
      if (mounted) setState(() => fontLoadFailed = true);
    }
  }

  Future<void> load() async {
    ui.Image? decoded;
    Map<int, ui.Image> pixels = {};
    try {
      final frame = c.imageDocument!.frame;
      decoded = await c.imageCodec.sourceImage(frame);
      pixels = await AnnotationRenderer.prepareMosaics(
        decoded,
        sourceRect: pixelFrameSourceRect(frame),
      );
      if (!mounted) {
        decoded.dispose();
        for (final image in pixels.values) {
          image.dispose();
        }
        return;
      }
      setState(() {
        image = decoded;
        mosaics = pixels;
      });
    } catch (error, stackTrace) {
      Logger('ui.annotation').warning(
        'Screenshot preview loading failed: errorType=${error.runtimeType}.',
        null,
        stackTrace,
      );
      decoded?.dispose();
      for (final image in pixels.values) {
        image.dispose();
      }
      if (mounted) {
        setState(() => loadFailed = true);
      }
    }
  }

  @override
  void dispose() {
    image?.dispose();
    for (final image in mosaics.values) {
      image.dispose();
    }
    textInput.dispose();
    textFocus.dispose();
    focus.dispose();
    super.dispose();
  }

  void commit(List<Annotation> next) {
    try {
      c.markup.commit(next);
    } on FormatException catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(c.describeError(e))));
    }
  }

  void cancelGesture() {
    setState(() {
      preview = null;
      original = null;
      start = null;
      resizeAnchor = null;
      pointerId = null;
      eraserEnd = null;
      selectionDrag = null;
      selectionPreview = null;
    });
  }

  Annotation makeAnnotation(
    AnnotationKind kind,
    List<Offset> points, {
    String text = '',
  }) => Annotation(
    kind: kind,
    points: points,
    color: color,
    width: pixelWidth,
    fontSize: pixelFontSize,
    fontFamily: fontFamily,
    text: text,
    filled: filled,
    bold: bold,
    italic: italic,
    outlined: outlined,
    effectBrush: effectBrush,
    effectStrength: effectStrength,
  );

  String styleKey(String value) => ['rectangle', 'ellipse'].contains(value)
      ? 'shape'
      : ['line', 'arrow'].contains(value)
      ? 'line'
      : ['mosaic', 'blur'].contains(value)
      ? 'effect'
      : value;

  void selectTool(String value) {
    finishText();
    finishLine();
    styles[styleKey(propertyKind)] = (
      width: width,
      fontSize: fontSize,
      fontFamily: fontFamily,
      filled: filled,
      bold: bold,
      italic: italic,
      outlined: outlined,
      effectBrush: effectBrush,
      effectStrength: effectStrength,
    );
    cancelGesture();
    final next = styles[styleKey(value)];
    setState(() {
      tool = value;
      selected = null;
      color = c.annotationColor(value);
      width =
          next?.width ??
          (value == 'marker'
              ? 12
              : ['mosaic', 'blur', 'eraser'].contains(value)
              ? 24
              : 3);
      fontSize = next?.fontSize ?? 24;
      fontFamily = next?.fontFamily ?? Annotation.defaultFontFamily;
      filled = next?.filled ?? false;
      bold = next?.bold ?? false;
      italic = next?.italic ?? false;
      outlined = next?.outlined ?? false;
      effectBrush = next?.effectBrush ?? false;
      effectStrength = next?.effectStrength ?? 3;
      if (['rectangle', 'ellipse'].contains(value)) lastShape = value;
      if (['line', 'arrow'].contains(value)) lastLine = value;
      if (['mosaic', 'blur'].contains(value)) lastEffect = value;
      toolbarVisible = true;
    });
    focus.requestFocus();
  }

  void finishLine() {
    if (linePoints.length >= 2) {
      commit([
        ...items,
        makeAnnotation(AnnotationKind.line, List.of(linePoints)),
      ]);
    }
    if (linePoints.isNotEmpty) {
      setState(() {
        linePoints.clear();
        lineHover = null;
      });
    }
  }

  void endTool() {
    if (textEditing) finishText();
    finishLine();
    if (start != null) cancelGesture();
    if (tool != 'select' || selected != null) {
      selectTool('select');
    }
  }

  void export(bool save, {bool pin = false}) {
    finishText();
    finishLine();
    c.exportScreenshot(save: save, pin: pin);
  }

  void recognizeText() {
    finishText();
    finishLine();
    cancelGesture();
    c.recognizeText();
  }

  void recognizeQrCodes() {
    finishText();
    finishLine();
    c.recognizeQrCodes();
  }

  void deleteSelected() {
    if (textEditing) finishText(cancel: true);
    if (selected == null || selected! >= items.length) return;
    final next = List<Annotation>.of(items)..removeAt(selected!);
    cancelGesture();
    selected = null;
    commit(next);
  }

  void style({
    int? nextColor,
    double? nextWidth,
    double? nextFont,
    String? nextFontFamily,
    bool? nextFilled,
    bool? nextBold,
    bool? nextItalic,
    bool? nextOutlined,
    int? nextEffectStrength,
  }) {
    if (nextColor != null) c.setAnnotationColor(propertyKind, nextColor);
    setState(() {
      color = nextColor ?? color;
      width = nextWidth ?? width;
      fontSize = nextFont ?? fontSize;
      fontFamily = nextFontFamily ?? fontFamily;
      filled = nextFilled ?? filled;
      bold = nextBold ?? bold;
      italic = nextItalic ?? italic;
      outlined = nextOutlined ?? outlined;
      effectStrength = nextEffectStrength ?? effectStrength;
    });
    if (!textEditing && selected != null && selected! < items.length) {
      final next = List<Annotation>.of(items);
      next[selected!] = next[selected!].copyWith(
        color: nextColor,
        fontFamily: nextFontFamily,
        width: nextWidth == null ? null : nextWidth * c.screenshotScaleX,
        fontSize: nextFont == null ? null : nextFont * c.screenshotScaleY,
        filled: nextFilled,
        bold: nextBold,
        italic: nextItalic,
        outlined: nextOutlined,
        effectStrength: nextEffectStrength,
      );
      final annotation = next[selected!];
      if (annotation != items[selected!] &&
          annotation.kind == AnnotationKind.text &&
          (nextFont != null ||
              nextFontFamily != null ||
              nextBold != null ||
              nextItalic != null)) {
        final bounds = annotation.bounds;
        final textWidth = math.min(
          imageSize.width - bounds.left,
          bounds.width * annotation.fontSize / items[selected!].fontSize,
        );
        final painter = TextPainter(
          text: TextSpan(
            text: annotation.text,
            style: TextStyle(
              fontSize: annotation.fontSize,
              fontFamily: annotation.fontFamily,
              fontWeight: annotation.bold ? FontWeight.bold : FontWeight.normal,
              fontStyle: annotation.italic
                  ? FontStyle.italic
                  : FontStyle.normal,
              height: 1.2,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: textWidth);
        // 字形或字号变化后重新计算高度，避免导出时按旧文本框裁掉文字。
        final height = math.min(
          imageSize.height - bounds.top,
          math.max(
            annotation.fontSize * 1.3,
            painter.height + 2 * c.screenshotScaleY,
          ),
        );
        painter.dispose();
        next[selected!] = annotation.copyWith(
          points: [bounds.topLeft, bounds.topLeft + Offset(textWidth, height)],
        );
      }
      commit(next);
    }
    textEditing ? textFocus.requestFocus() : focus.requestFocus();
  }

  void beginText(Rect rect, {int? index}) {
    finishText();
    final existing = index == null ? null : items[index];
    final minWidth = math.min(80.0 * c.screenshotScaleX, imageSize.width);
    final w = rect.width < 12 * c.screenshotScaleX
        ? math.min(320.0 * c.screenshotScaleX, imageSize.width)
        : rect.width;
    final left = rect.left.clamp(0.0, imageSize.width - minWidth);
    final top = rect.top.clamp(
      0.0,
      math.max(0.0, imageSize.height - pixelFontSize * 1.4),
    );
    textInput.text = existing?.text ?? '';
    setState(() {
      selected = index;
      textIndex = index;
      textRect = Rect.fromLTWH(
        left,
        top.toDouble(),
        math.min(w, imageSize.width - left),
        imageSize.height - top,
      );
      textEditing = true;
    });
    textFocus.requestFocus();
  }

  void finishText({bool cancel = false}) {
    if (!textEditing) return;
    final value = textInput.text;
    final rect = textRect!;
    final index = textIndex;
    if (cancel && index != null && index < items.length) {
      final old = items[index];
      color = old.color;
      width = old.width / c.screenshotScaleX;
      fontSize = old.fontSize / c.screenshotScaleY;
      fontFamily = old.fontFamily;
      filled = old.filled;
      bold = old.bold;
      italic = old.italic;
      outlined = old.outlined;
    }
    setState(() {
      textEditing = false;
      textRect = null;
      textIndex = null;
    });
    if (!cancel && value.trim().isNotEmpty) {
      final painter = TextPainter(
        text: TextSpan(
          text: value,
          style: TextStyle(
            fontSize: pixelFontSize,
            fontFamily: fontFamily,
            height: 1.2,
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            fontStyle: italic ? FontStyle.italic : FontStyle.normal,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: rect.width);
      final b = Rect.fromLTWH(
        rect.left,
        rect.top,
        math.min(
          rect.width,
          math.max(
            24.0 * c.screenshotScaleX,
            painter.width + 2 * c.screenshotScaleX,
          ),
        ),
        math.min(
          rect.height,
          math.max(
            pixelFontSize * 1.3,
            painter.height + 2 * c.screenshotScaleY,
          ),
        ),
      );
      painter.dispose();
      final annotation = makeAnnotation(AnnotationKind.text, [
        b.topLeft,
        b.bottomRight,
      ], text: value);
      final next = List<Annotation>.of(items);
      if (index != null && index < next.length) {
        next[index] = annotation;
        selected = index;
      } else {
        selected = next.length;
        next.add(annotation);
      }
      commit(next);
    }
    textFocus.unfocus();
    focus.requestFocus();
  }

  void editText() {
    if (selected == null ||
        selected! >= items.length ||
        items[selected!].kind != AnnotationKind.text) {
      return;
    }
    final a = items[selected!];
    color = a.color;
    width = a.width / c.screenshotScaleX;
    fontSize = a.fontSize / c.screenshotScaleY;
    fontFamily = a.fontFamily;
    bold = a.bold;
    italic = a.italic;
    outlined = a.outlined;
    beginText(a.bounds, index: selected);
  }

  bool get strokeActive {
    final kind = propertyKind;
    if (['rectangle', 'ellipse'].contains(kind)) return !filled;
    if (['mosaic', 'blur'].contains(kind)) return effectBrush;
    if (kind == 'eraser') return eraserBrush;
    return ['line', 'arrow', 'pencil', 'marker'].contains(kind);
  }

  void activateStroke() {
    final kind = propertyKind;
    if (['rectangle', 'ellipse'].contains(kind)) {
      if (filled) style(nextFilled: false);
    } else if (['mosaic', 'blur'].contains(kind)) {
      setEffectMode(true);
    } else if (kind == 'eraser') {
      setEraserMode(true);
    }
    focus.requestFocus();
  }

  void selectFill() {
    if (!filled) style(nextFilled: true);
    focus.requestFocus();
  }

  void adjustWidth(int direction) {
    if (textEditing) return;
    if (propertyKind == 'text') {
      final next = (fontSize + direction).clamp(8.0, 200.0);
      if (next != fontSize) style(nextFont: next);
    } else if (strokeActive) {
      final next = (width + direction).clamp(1.0, 80.0);
      if (next != width) style(nextWidth: next);
    }
  }

  void widthScroll(PointerSignalEvent event) {
    if (event is PointerScrollEvent &&
        event.scrollDelta.dy != 0 &&
        editable &&
        !textEditing &&
        strokeActive) {
      GestureBinding.instance.pointerSignalResolver.register(
        event,
        (_) => adjustWidth(event.scrollDelta.dy < 0 ? 1 : -1),
      );
    }
  }

  Offset clamp(Offset p) =>
      Offset(p.dx.clamp(0, imageSize.width), p.dy.clamp(0, imageSize.height));

  Annotation moveAnnotation(Annotation annotation, Offset delta) {
    final source = c.screenshotSourceSize!, selection = c.screenshotSelection!;
    return annotation.move(
      delta,
      Size(source.width.toDouble(), source.height.toDouble()),
      origin: Offset(selection.left.toDouble(), selection.top.toDouble()),
    );
  }

  bool get canAdjustSelection =>
      c.canAdjustScreenshotSelection && !textEditing && editable;

  void beginSelection(PointerDownEvent event, String handle) {
    if (!canAdjustSelection || event.buttons != kPrimaryMouseButton) return;
    finishLine();
    focus.requestFocus();
    setState(() {
      selected = null;
      selectionDrag = (
        pointer: event.pointer,
        start: event.position,
        original: c.screenshotSelection!,
        handle: handle,
      );
    });
  }

  PixelRect selectionAt(Offset position) {
    final drag = selectionDrag!, size = c.screenshotSourceSize!;
    final delta = position - drag.start;
    return transformAnnotation(
      drag.original,
      (delta.dx * c.screenshotScaleX).round(),
      (delta.dy * c.screenshotScaleY).round(),
      size.width,
      size.height,
      handle: drag.handle,
    );
  }

  void moveSelection(PointerMoveEvent event) {
    if (selectionDrag?.pointer == event.pointer) {
      setState(() => selectionPreview = selectionAt(event.position));
    }
  }

  Future<void> endSelection(PointerUpEvent event) async {
    if (selectionDrag?.pointer != event.pointer) return;
    final rect = selectionAt(event.position);
    setState(() {
      selectionPreview = rect;
      selectionDrag = null;
    });
    await c.adjustScreenshotSelection(rect);
    if (mounted) setState(() => selectionPreview = null);
  }

  Widget selectionHandle(String handle, Offset position) => Positioned(
    left: position.dx - 5,
    top: position.dy - 5,
    width: 10,
    height: 10,
    child: MouseRegion(
      cursor: SystemMouseCursors.grab,
      child: Listener(
        key: ValueKey('screenshot-handle-$handle'),
        onPointerDown: (event) => beginSelection(event, handle),
        onPointerMove: moveSelection,
        onPointerUp: endSelection,
        onPointerCancel: (_) => cancelGesture(),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: toolbarBlue,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 1),
          ),
        ),
      ),
    ),
  );

  bool selectedHandle(Offset p) {
    if (selected == null || selected! >= items.length) return false;
    final b = items[selected!].bounds;
    return [
      b.topLeft,
      b.topRight,
      b.bottomRight,
      b.bottomLeft,
    ].any((corner) => (p - corner).distance < 9 / scale);
  }

  // Pick complete objects in reverse paint order. Eraser mode always draws
  // an independent erasure, even over an existing object's edge.
  int? annotationAt(Offset p) {
    if (tool == 'eraser') return null;
    for (var i = items.length - 1; i >= 0; i--) {
      final a = items[i];
      if (tool != 'select' && selected != i && a.kind.name != tool) continue;
      if (a.hitTest(
        p,
        6 / scale,
        edgeOnly: tool != 'select' && selected != i,
      )) {
        return i;
      }
    }
    return null;
  }

  MouseCursor get canvasCursor {
    if (!editable || image == null) return SystemMouseCursors.basic;
    if (selectionDrag != null) return SystemMouseCursors.grabbing;
    if (canAdjustSelection &&
        tool == 'select' &&
        selected == null &&
        (hoverPosition == null || annotationAt(hoverPosition!) == null)) {
      return SystemMouseCursors.grab;
    }
    if (pointerId != null && original != null) {
      return SystemMouseCursors.grabbing;
    }
    final p = hoverPosition;
    if (p == null || tool == 'eraser') {
      return tool == 'select'
          ? SystemMouseCursors.basic
          : SystemMouseCursors.precise;
    }
    if (selectedHandle(p)) return SystemMouseCursors.grab;
    final hit = annotationAt(p) != null;
    return hit
        ? SystemMouseCursors.grab
        : tool == 'select'
        ? SystemMouseCursors.basic
        : SystemMouseCursors.precise;
  }

  void hover(Offset? p) {
    if (p != hoverPosition) {
      setState(() {
        hoverPosition = p;
        if (linePoints.isNotEmpty && p != null) lineHover = clamp(p);
      });
    }
  }

  void down(PointerDownEvent event) {
    if (!editable || image == null) return;
    if (event.buttons == kSecondaryMouseButton) {
      endTool();
      return;
    }
    if (textCommitPointer == event.pointer) return;
    if (textEditing) {
      finishText();
      return;
    }
    if (event.buttons != kPrimaryMouseButton) {
      cancelGesture();
      return;
    }
    if (canAdjustSelection &&
        tool == 'select' &&
        !selectedHandle(event.localPosition) &&
        annotationAt(event.localPosition) == null) {
      setState(() => selected = null);
      beginSelection(event, 'move');
      return;
    }
    focus.requestFocus();
    final p = clamp(event.localPosition);
    hoverPosition = p;
    pointerId = event.pointer;
    start = p;
    original = null;
    resizeAnchor = null;
    if (tool == 'eraser') {
      selected = null;
      setState(() {
        eraserEnd = p;
        preview = makeAnnotation(AnnotationKind.eraser, [
          p,
          p,
        ]).copyWith(effectBrush: eraserBrush);
      });
      return;
    }
    final hit = annotationAt(p);
    if (tool == 'select' || selectedHandle(p) || hit != null) {
      if (selected != null && selected! < items.length) {
        final b = items[selected!].bounds;
        final corners = [b.topLeft, b.topRight, b.bottomRight, b.bottomLeft];
        for (var i = 0; i < 4; i++) {
          if ((p - corners[i]).distance < 9 / scale) {
            original = items[selected!];
            resizeAnchor = corners[(i + 2) % 4];
            setState(() {});
            return;
          }
        }
      }
      selected = hit;
      if (selected != null) {
        original = items[selected!];
        color = original!.color;
        width = original!.width / c.screenshotScaleX;
        fontSize = original!.fontSize / c.screenshotScaleY;
        fontFamily = original!.fontFamily;
        filled = original!.filled;
        bold = original!.bold;
        italic = original!.italic;
        outlined = original!.outlined;
        effectBrush = original!.effectBrush;
        effectStrength = original!.effectStrength;
      }
    } else {
      selected = null;
      preview = makeAnnotation(AnnotationKind.values.byName(tool), [p, p]);
    }
    setState(() {});
  }

  void move(PointerMoveEvent event) {
    if (selectionDrag != null) {
      moveSelection(event);
      return;
    }
    if (pointerId != event.pointer || start == null || !editable) return;
    final p = clamp(event.localPosition);
    hoverPosition = p;
    if (tool == 'eraser') {
      setState(() {
        eraserEnd = p;
        preview = preview!.copyWith(
          points: eraserBrush
              ? [...preview!.points.take(19999), p]
              : [start!, p],
        );
      });
      return;
    }
    if (original != null) {
      if (resizeAnchor != null) {
        final b = Rect.fromPoints(resizeAnchor!, p);
        if (b.width >= 1 && b.height >= 1) {
          preview = original!.resize(b, fontScale: c.screenshotScaleY);
        }
      } else {
        preview = moveAnnotation(original!, p - start!);
      }
    } else if (preview != null) {
      final free = preview!.isPath && tool != 'line' && tool != 'arrow';
      final end = constrainedAnnotationEnd(
        preview!.kind,
        start!,
        p,
        imageSize,
        shift: HardwareKeyboard.instance.isShiftPressed,
      );
      if (!free || (p - preview!.points.last).distance >= .5) {
        preview = preview!.copyWith(
          points: free ? [...preview!.points.take(19999), p] : [start!, end],
        );
      }
    }
    setState(() {});
  }

  Future<void> up(PointerUpEvent event) async {
    if (selectionDrag != null) {
      await endSelection(event);
      return;
    }
    if (pointerId != event.pointer) return;
    hoverPosition = clamp(event.localPosition);
    if (tool == 'eraser' && start != null && editable) {
      final end = clamp(event.localPosition);
      final erased = preview!.copyWith(
        points: eraserBrush
            ? [...preview!.points.take(19999), end]
            : [start!, end],
      );
      cancelGesture();
      final region = eraserBrush
          ? erased.bounds.inflate(erased.width / 2)
          : erased.bounds;
      if (!region.isEmpty &&
          items.any(
            (a) => a.kind != AnnotationKind.eraser && a.intersects(region),
          )) {
        commit([...items, erased]);
      }
      return;
    }
    final annotation = preview;
    if (tool == 'line' &&
        original == null &&
        start != null &&
        (event.localPosition - start!).distance < 3 / scale) {
      final p = clamp(event.localPosition);
      cancelGesture();
      setState(() {
        linePoints.add(p);
        lineHover = p;
      });
      return;
    }
    final wasEditing = original != null;
    final index = selected;
    cancelGesture();
    if (!editable || annotation == null) return;
    if (wasEditing && index != null && index < items.length) {
      final next = List<Annotation>.of(items);
      next[index] = annotation;
      commit(next);
      return;
    }
    if (annotation.kind == AnnotationKind.text) {
      beginText(annotation.bounds);
      return;
    }
    if (!annotation.effectBrush &&
        annotation.bounds.width < 1 &&
        annotation.bounds.height < 1) {
      return;
    }
    if ([
          AnnotationKind.rectangle,
          AnnotationKind.ellipse,
          AnnotationKind.mosaic,
          AnnotationKind.blur,
        ].contains(annotation.kind) &&
        !annotation.effectBrush &&
        annotation.bounds.isEmpty) {
      return;
    }
    if (linePoints.isNotEmpty) finishLine();
    final addedIndex = items.length;
    commit([...items, annotation]);
    setState(() => selected = addedIndex);
  }

  KeyEventResult key(FocusNode node, KeyEvent event) {
    if (c.textMode) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.escape) {
        c.dismissText();
      }
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent && (c.qrCodeBusy || c.qrCodeResults.isNotEmpty)) {
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        if (!c.qrCodeBusy || c.qrCodeRecognizing) {
          c.cancelScreenshot();
        }
      }
      return KeyEventResult.handled;
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent || !editable) {
      return KeyEventResult.ignored;
    }
    if (fontMenuController.isOpen) return KeyEventResult.ignored;
    final k = event.logicalKey;
    final meta =
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    if (meta && k == LogicalKeyboardKey.keyT) {
      export(false, pin: true);
      return KeyEventResult.handled;
    }
    if (textEditing) {
      if (k == LogicalKeyboardKey.escape) {
        finishText(cancel: true);
        return KeyEventResult.handled;
      }
      if (meta && k == LogicalKeyboardKey.enter) {
        finishText();
        return KeyEventResult.handled;
      }
      if (meta && k == LogicalKeyboardKey.keyS) {
        export(true);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (!meta && k == LogicalKeyboardKey.keyC && screenPointer != null) {
      final p = screenPointer!;
      c.sampleCaptureColor(c.screenshotDisplayId!, p.dx, p.dy);
      return KeyEventResult.handled;
    }
    if (!meta && k == LogicalKeyboardKey.keyM) {
      c.copyCaptureSize(c.screenshotDisplayId!, c.screenshotSelection!);
      return KeyEventResult.handled;
    }
    if (!meta && k == LogicalKeyboardKey.space) {
      setState(() => toolbarVisible = !toolbarVisible);
      return KeyEventResult.handled;
    }
    if (!meta &&
        k == LogicalKeyboardKey.tab &&
        ['line', 'arrow'].contains(tool)) {
      selectTool(tool == 'line' ? 'arrow' : 'line');
      return KeyEventResult.handled;
    }
    if (!meta &&
        [
          LogicalKeyboardKey.digit1,
          LogicalKeyboardKey.bracketLeft,
          LogicalKeyboardKey.digit2,
          LogicalKeyboardKey.bracketRight,
        ].contains(k)) {
      adjustWidth(
        [LogicalKeyboardKey.digit1, LogicalKeyboardKey.bracketLeft].contains(k)
            ? -1
            : 1,
      );
      return KeyEventResult.handled;
    }
    if (meta && k == LogicalKeyboardKey.keyY) {
      history(true);
      return KeyEventResult.handled;
    }
    if (meta && k == LogicalKeyboardKey.keyZ) {
      history(shift);
      return KeyEventResult.handled;
    }
    if ((meta && k == LogicalKeyboardKey.keyS) ||
        k == LogicalKeyboardKey.enter) {
      export(meta && k == LogicalKeyboardKey.keyS);
      return KeyEventResult.handled;
    }
    if (meta && k == LogicalKeyboardKey.keyC) {
      export(false);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.delete || k == LogicalKeyboardKey.backspace) {
      deleteSelected();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.escape) {
      if (start != null || selectionDrag != null || linePoints.isNotEmpty) {
        linePoints.clear();
        lineHover = null;
        cancelGesture();
      } else {
        c.cancelScreenshot();
      }
      return KeyEventResult.handled;
    }
    final delta = {
      LogicalKeyboardKey.arrowLeft: const Offset(-1, 0),
      LogicalKeyboardKey.arrowRight: const Offset(1, 0),
      LogicalKeyboardKey.arrowUp: const Offset(0, -1),
      LogicalKeyboardKey.arrowDown: const Offset(0, 1),
    }[k];
    if (delta != null &&
        tool == 'select' &&
        selected == null &&
        canAdjustSelection &&
        selectionDrag == null) {
      final size = c.screenshotSourceSize!;
      final handle = (shift || meta)
          ? {
              LogicalKeyboardKey.arrowLeft: 'w',
              LogicalKeyboardKey.arrowRight: 'e',
              LogicalKeyboardKey.arrowUp: 'n',
              LogicalKeyboardKey.arrowDown: 's',
            }[k]!
          : 'move';
      final d = shift ? -delta : delta;
      final next = transformAnnotation(
        c.screenshotSelection!,
        d.dx.toInt(),
        d.dy.toInt(),
        size.width,
        size.height,
        handle: handle,
      );
      c.adjustScreenshotSelection(next);
      return KeyEventResult.handled;
    }
    if (delta != null && selected != null && selected! < items.length) {
      final next = List<Annotation>.of(items);
      final a = next[selected!];
      if (shift) {
        final source = c.screenshotSourceSize!,
            selection = c.screenshotSelection!;
        final maxWidth = (source.width - selection.left).toDouble();
        final maxHeight = (source.height - selection.top).toDouble();
        final b = a.bounds;
        final r = Rect.fromLTRB(
          b.left,
          b.top,
          (b.right + delta.dx).clamp(
            b.left + math.min(1, maxWidth - b.left),
            maxWidth,
          ),
          (b.bottom + delta.dy).clamp(
            b.top + math.min(1, maxHeight - b.top),
            maxHeight,
          ),
        );
        next[selected!] = a.resize(r, fontScale: c.screenshotScaleY);
      } else {
        next[selected!] = moveAnnotation(a, delta);
      }
      commit(next);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void history(bool redo) {
    if (linePoints.isNotEmpty) {
      setState(() {
        linePoints.clear();
        lineHover = null;
      });
      return;
    }
    finishText();
    cancelGesture();
    if (!(redo ? c.markup.canRedo : c.markup.canUndo)) {
      focus.requestFocus();
      return;
    }
    final before = List<Annotation>.of(items);
    redo ? c.markup.redo() : c.markup.undo();
    final restored = items.indexWhere(
      (a) => a.kind != AnnotationKind.eraser && !before.contains(a),
    );
    setState(() {
      selected = restored < 0 ? null : restored;
      if (selected != null) {
        final a = items[selected!];
        color = a.color;
        width = a.width / c.screenshotScaleX;
        fontSize = a.fontSize / c.screenshotScaleY;
        fontFamily = a.fontFamily;
        filled = a.filled;
        bold = a.bold;
        italic = a.italic;
        outlined = a.outlined;
        effectBrush = a.effectBrush;
        effectStrength = a.effectStrength;
      }
    });
    focus.requestFocus();
  }

  static const toolbarBlue = Color(0xFF2683FF),
      toolbarSurface = Color(0xFF292929);
  static const palette = [
    0xFF000000,
    0xFF555555,
    0xFF888888,
    0xFFB00020,
    0xFFFF0000,
    0xFFFF7A00,
    0xFFFFD600,
    0xFF42D83B,
    0xFF00C8D7,
    0xFF1677FF,
    0xFF9641AF,
    0xFFFFFFFF,
    0xFFCCCCCC,
    0xFFEEEEEE,
    0xFFFFA9AD,
    0xFFFFC2D2,
    0xFFFFD3AD,
    0xFFFFF4A3,
    0xFFCFF4A0,
    0xFFA6ECF2,
    0xFFA9D7FF,
    0xFFDEC5EF,
  ];

  Widget toolIcon(IconData icon, Color color) {
    final kind = icon == Icons.interests_outlined
        ? 'shape'
        : icon == Icons.timeline
        ? 'line'
        : icon == Icons.auto_fix_normal
        ? 'eraser'
        : null;
    return kind == null
        ? Icon(icon, color: color)
        : SizedBox(
            width: 18,
            height: 18,
            child: CustomPaint(painter: _ToolbarGlyphPainter(kind, color)),
          );
  }

  Widget toolbarButton(
    String id,
    String label,
    IconData icon,
    VoidCallback? action, {
    bool active = false,
    bool compact = false,
  }) => IconButton(
    key: ValueKey(id),
    tooltip: label,
    mouseCursor: action == null
        ? SystemMouseCursors.basic
        : SystemMouseCursors.click,
    isSelected: active,
    iconSize: 18,
    padding: EdgeInsets.zero,
    constraints: BoxConstraints.tightFor(
      width: compact ? 28 : 30,
      height: compact ? 28 : 30,
    ),
    style: IconButton.styleFrom(
      minimumSize: Size.square(compact ? 28 : 30),
      maximumSize: Size.square(compact ? 28 : 30),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
      foregroundColor: action == null ? const Color(0xFF777777) : Colors.white,
      backgroundColor: active ? toolbarBlue : Colors.transparent,
    ),
    selectedIcon: toolIcon(icon, Colors.white),
    icon: toolIcon(
      icon,
      action == null ? const Color(0xFF777777) : Colors.white,
    ),
    onPressed: action,
  );

  Widget get divider => const SizedBox(
    height: 20,
    child: VerticalDivider(width: 8, thickness: 1, color: Color(0xFF555555)),
  );

  Widget toolbarPanel(Widget child, {Key? key, bool compact = false}) =>
      Material(
        key: key,
        color: toolbarSurface,
        elevation: 4,
        shadowColor: Colors.black54,
        borderRadius: BorderRadius.circular(4),
        child: Padding(padding: EdgeInsets.all(compact ? 2 : 3), child: child),
      );

  String get propertyKind => textEditing
      ? 'text'
      : selected != null && selected! < items.length
      ? items[selected!].kind.name
      : tool;
  bool get hasProperties => !['select', 'picker'].contains(propertyKind);

  Widget widthButton({String? modeKey}) => Listener(
    key: modeKey == null ? null : ValueKey(modeKey),
    onPointerSignal: widthScroll,
    child: IconButton(
      key: const ValueKey('annotation-width'),
      tooltip: context.l10n.uiLineWidthTooltip(width.round()),
      isSelected: strokeActive,
      mouseCursor: SystemMouseCursors.click,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 28, height: 28),
      style: IconButton.styleFrom(
        minimumSize: const Size.square(28),
        maximumSize: const Size.square(28),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        backgroundColor: strokeActive ? toolbarBlue : Colors.transparent,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
      ),
      onPressed: activateStroke,
      icon: SizedBox(
        width: 18,
        height: 18,
        child: Center(
          child: width > 12
              ? Text(
                  width.toStringAsFixed(0),
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                )
              : Container(
                  width: width + 2,
                  height: width + 2,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
        ),
      ),
    ),
  );

  Widget fontFamilyMenu() => MenuAnchor(
    controller: fontMenuController,
    consumeOutsideTap: true,
    style: const MenuStyle(
      backgroundColor: WidgetStatePropertyAll(toolbarSurface),
      padding: WidgetStatePropertyAll(EdgeInsets.zero),
    ),
    onClose: () =>
        textEditing ? textFocus.requestFocus() : focus.requestFocus(),
    menuChildren: [
      FontFamilyPicker(
        key: const ValueKey('annotation-font-picker'),
        families: fontFamilies,
        selected: fontFamily,
        onSelected: (value) {
          fontMenuController.close();
          style(nextFontFamily: value);
        },
      ),
    ],
    builder: (context, controller, child) => Tooltip(
      message: fontLoadFailed
          ? context.l10n.uiFontLoadingFailed
          : (fontFamilies.isEmpty
                ? context.l10n.uiNoSystemFonts
                : context.l10n.uiFontFamilyTooltip(fontFamily)),
      child: InkWell(
        key: const ValueKey('annotation-font-family'),
        onTap: fontFamilies.isEmpty
            ? null
            : () => controller.isOpen ? controller.close() : controller.open(),
        child: SizedBox(
          width: 132,
          height: 28,
          child: Row(
            children: [
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  fontFamily,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
              const Icon(Icons.arrow_drop_down, size: 14, color: Colors.white),
            ],
          ),
        ),
      ),
    ),
  );

  Widget fontMenu() => Tooltip(
    message: context.l10n.uiFontSize,
    child: PopupMenuButton<double>(
      key: const ValueKey('annotation-font'),
      padding: EdgeInsets.zero,
      color: toolbarSurface,
      tooltip: '',
      menuPadding: const EdgeInsets.all(4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      constraints: const BoxConstraints(minWidth: 100, maxWidth: 160),
      onSelected: (v) => style(nextFont: v),
      itemBuilder: (_) =>
          (<double>{
                8,
                10,
                12,
                14,
                16,
                18,
                20,
                24,
                28,
                32,
                36,
                48,
                60,
                72,
                96,
                120,
                144,
                200,
                fontSize,
              }.toList()..sort())
              .map(
                (v) => PopupMenuItem(
                  value: v,
                  height: 28,
                  child: Text(
                    '${v.toStringAsFixed(0)} pt',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              )
              .toList(),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: SizedBox(
          width: 52,
          height: 28,
          child: Center(
            child: Container(
              height: 22,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF454545),
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: const Color(0xFF666666)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    fontSize.toStringAsFixed(0),
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                  const Icon(
                    Icons.arrow_drop_down,
                    size: 14,
                    color: Colors.white,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Future<void> customColor() async {
    if (colorPicking) return;
    setState(() => colorPicking = true);
    try {
      final value = await c.desktop.pickAnnotationColor(color);
      if (!mounted) return;
      if (value != null) style(nextColor: value);
    } catch (error, stackTrace) {
      Logger('ui.annotation').warning(
        'Color panel failed: errorType=${error.runtimeType}.',
        null,
        stackTrace,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.uiColorPanelFailed)),
        );
      }
    } finally {
      if (mounted) {
        setState(() => colorPicking = false);
        textEditing ? textFocus.requestFocus() : focus.requestFocus();
      }
    }
  }

  Widget colorPalette() => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Tooltip(
        message: context.l10n.uiCustomColor,
        child: InkWell(
          key: const ValueKey('annotation-color'),
          onTap: customColor,
          mouseCursor: SystemMouseCursors.click,
          child: Container(
            width: 24,
            height: 24,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              color: Color(color),
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: Colors.white, width: 1),
            ),
          ),
        ),
      ),
      SizedBox(
        width: 130,
        height: 22,
        child: Wrap(
          spacing: 2,
          runSpacing: 2,
          children: [
            for (final value in palette)
              Tooltip(
                message:
                    '#${value.toRadixString(16).substring(2).toUpperCase()}',
                child: InkWell(
                  key: ValueKey('annotation-color-${value.toRadixString(16)}'),
                  onTap: () => style(nextColor: value),
                  mouseCursor: SystemMouseCursors.click,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: Color(value),
                      borderRadius: BorderRadius.circular(1),
                      border: Border.all(
                        color: value == color
                            ? toolbarBlue
                            : const Color(0xFFB0B0B0),
                        width: value == color ? 2 : .5,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ],
  );

  void setEffectMode(bool brush) {
    final kind = propertyKind;
    if (effectBrush == brush) {
      focus.requestFocus();
      return;
    }
    cancelGesture();
    setState(() {
      tool = kind;
      selected = null;
      effectBrush = brush;
    });
    focus.requestFocus();
  }

  void setEraserMode(bool brush) {
    if (eraserBrush != brush) {
      cancelGesture();
      setState(() => eraserBrush = brush);
    }
    focus.requestFocus();
  }

  // Sliders preview continuously but commit a selected mark once per gesture.
  void beginParameter() {
    cancelGesture();
    if (selected != null && selected! < items.length) {
      original = items[selected!];
    }
    focus.requestFocus();
  }

  void updateParameter(double value, {required bool strength}) {
    setState(() {
      if (strength) {
        effectStrength = value.round();
      } else {
        width = value.roundToDouble();
      }
      if (original != null) {
        preview = original!.copyWith(
          width: strength ? null : pixelWidth,
          effectStrength: strength ? effectStrength : null,
        );
      }
    });
  }

  void finishParameter() {
    final next = preview, index = selected;
    cancelGesture();
    if (next != null && index != null && index < items.length) {
      commit(List.of(items)..[index] = next);
    }
  }

  Widget effectParameter({required bool strength}) {
    final label = strength
        ? (propertyKind == 'mosaic'
              ? context.l10n.uiMosaicSize
              : context.l10n.uiBlurStrength)
        : context.l10n.uiBrushWidth;
    final value = strength ? effectStrength.toDouble() : width;
    return Tooltip(
      message: context.l10n.uiParameterTooltip(
        label,
        value.round(),
        strength ? '/5' : ' pt',
      ),
      child: SizedBox(
        height: 28,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: strength
                  ? const Icon(Icons.tune, size: 14, color: Color(0xFFCCCCCC))
                  : const Icon(Icons.circle, size: 8, color: Colors.white),
            ),
            SizedBox(
              width: strength ? 72 : 88,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 2,
                  activeTrackColor: toolbarBlue,
                  inactiveTrackColor: const Color(0xFF666666),
                  thumbColor: Colors.white,
                  overlayColor: toolbarBlue.withValues(alpha: .16),
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 4,
                  ),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 7),
                  tickMarkShape: SliderTickMarkShape.noTickMark,
                ),
                child: Slider(
                  key: ValueKey(
                    strength
                        ? 'annotation-effect-strength'
                        : 'annotation-effect-width',
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  min: 1,
                  max: strength ? 5 : 80,
                  divisions: strength ? 4 : 79,
                  value: value,
                  mouseCursor: SystemMouseCursors.click,
                  semanticFormatterCallback: (v) =>
                      context.l10n.uiParameterValue(label, v.round()),
                  onChangeStart: (_) => beginParameter(),
                  onChanged: (v) => updateParameter(v, strength: strength),
                  onChangeEnd: (_) => finishParameter(),
                ),
              ),
            ),
            SizedBox(
              width: 22,
              child: Text(
                '${value.round()}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget propertyButton(
    String id,
    String label,
    IconData icon,
    VoidCallback? action, {
    bool active = false,
  }) => toolbarButton(id, label, icon, action, active: active, compact: true);

  bool get showBrushCursor =>
      hoverPosition != null &&
      editable &&
      canvasCursor == SystemMouseCursors.precise &&
      (tool == 'marker' ||
          (tool == 'eraser' && eraserBrush) ||
          (['mosaic', 'blur'].contains(tool) && effectBrush));

  Widget brushCursor(Rect rect) => Positioned.fromRect(
    rect: rect,
    child: IgnorePointer(
      child: ClipRect(
        child: Stack(
          children: [
            Positioned(
              left:
                  hoverPosition!.dx / c.screenshotScaleX -
                  math.max(3.0, width) / 2,
              top:
                  hoverPosition!.dy / c.screenshotScaleY -
                  math.max(3.0, width) / 2,
              child: Container(
                key: const ValueKey('annotation-brush-cursor'),
                width: math.max(3.0, width),
                height: math.max(3.0, width),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white),
                  boxShadow: const [
                    BoxShadow(color: Colors.black54, spreadRadius: 1),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget propertyBar() {
    final kind = propertyKind;
    final shape = ['rectangle', 'ellipse'].contains(kind);
    final line = ['line', 'arrow'].contains(kind);
    final effect = ['mosaic', 'blur'].contains(kind);
    return toolbarPanel(
      key: const ValueKey('annotation-properties'),
      compact: true,
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (kind == 'eraser') ...[
            widthButton(modeKey: 'annotation-eraser-brush'),
            propertyButton(
              'annotation-eraser-rectangle',
              context.l10n.uiRectangleEraser,
              Icons.rectangle_outlined,
              () => setEraserMode(false),
              active: !eraserBrush,
            ),
          ],
          if (!effect && kind != 'text' && kind != 'eraser') widthButton(),
          if (shape) ...[
            propertyButton(
              'annotation-fill',
              context.l10n.uiFillShape,
              Icons.square,
              selectFill,
              active: filled,
            ),
            divider,
            propertyButton(
              'annotation-tool-rectangle',
              context.l10n.uiModeRectangle,
              Icons.crop_square,
              () => selectTool('rectangle'),
              active: kind == 'rectangle',
            ),
            propertyButton(
              'annotation-tool-ellipse',
              context.l10n.uiEllipse,
              Icons.circle_outlined,
              () => selectTool('ellipse'),
              active: kind == 'ellipse',
            ),
            divider,
          ],
          if (line) ...[
            propertyButton(
              'annotation-tool-line',
              context.l10n.uiLineTooltip,
              Icons.show_chart,
              () => selectTool('line'),
              active: kind == 'line',
            ),
            propertyButton(
              'annotation-tool-arrow',
              context.l10n.uiArrowTooltip,
              Icons.north_east,
              () => selectTool('arrow'),
              active: kind == 'arrow',
            ),
            divider,
          ],
          if (effect) ...[
            widthButton(modeKey: 'annotation-effect-brush'),
            propertyButton(
              'annotation-effect-rectangle',
              context.l10n.uiRectangleSelection,
              Icons.rectangle,
              () => setEffectMode(false),
              active: !effectBrush,
            ),
            divider,
            propertyButton(
              'annotation-tool-mosaic',
              context.l10n.uiMosaic,
              Icons.grid_view,
              () => selectTool('mosaic'),
              active: kind == 'mosaic',
            ),
            propertyButton(
              'annotation-tool-blur',
              context.l10n.uiGaussianBlur,
              Icons.blur_on,
              () => selectTool('blur'),
              active: kind == 'blur',
            ),
            divider,
            effectParameter(strength: true),
          ] else if (kind != 'eraser') ...[
            if (kind == 'text') ...[
              propertyButton(
                'annotation-bold',
                context.l10n.uiBold,
                Icons.format_bold,
                () => style(nextBold: !bold),
                active: bold,
              ),
              propertyButton(
                'annotation-italic',
                context.l10n.uiItalic,
                Icons.format_italic,
                () => style(nextItalic: !italic),
                active: italic,
              ),
              propertyButton(
                'annotation-text-outline',
                context.l10n.uiTextOutline,
                Icons.format_color_text,
                () => style(nextOutlined: !outlined),
                active: outlined,
              ),
              fontFamilyMenu(),
              fontMenu(),
              if (selected != null && !textEditing)
                propertyButton(
                  'annotation-edit-text',
                  context.l10n.uiEditText,
                  Icons.edit_note,
                  editText,
                ),
              divider,
            ],
            colorPalette(),
          ],
        ],
      ),
    );
  }

  Widget mainBar() => toolbarPanel(
    key: const ValueKey('annotation-toolbar'),
    Row(
      children: [
        toolbarButton(
          'annotation-group-shape',
          context.l10n.uiShapeTools,
          Icons.interests_outlined,
          () => selectTool(
            ['rectangle', 'ellipse'].contains(tool) ? 'select' : lastShape,
          ),
          active: ['rectangle', 'ellipse'].contains(tool),
        ),
        toolbarButton(
          'annotation-group-line',
          context.l10n.uiLineTools,
          Icons.timeline,
          () => selectTool(
            ['line', 'arrow'].contains(tool) ? 'select' : lastLine,
          ),
          active: ['line', 'arrow'].contains(tool),
        ),
        toolbarButton(
          'annotation-tool-pencil',
          context.l10n.uiPencil,
          Icons.edit_outlined,
          () => selectTool(tool == 'pencil' ? 'select' : 'pencil'),
          active: tool == 'pencil',
        ),
        toolbarButton(
          'annotation-tool-marker',
          context.l10n.uiMarker,
          Icons.border_color_outlined,
          () => selectTool(tool == 'marker' ? 'select' : 'marker'),
          active: tool == 'marker',
        ),
        toolbarButton(
          'annotation-group-effect',
          context.l10n.uiEffectTools,
          Icons.grid_view,
          () => selectTool(
            ['mosaic', 'blur'].contains(tool) ? 'select' : lastEffect,
          ),
          active: ['mosaic', 'blur'].contains(tool),
        ),
        toolbarButton(
          'annotation-tool-text',
          context.l10n.uiText,
          Icons.title,
          () => selectTool(tool == 'text' ? 'select' : 'text'),
          active: tool == 'text',
        ),
        toolbarButton(
          'annotation-tool-eraser',
          context.l10n.uiEraserTools,
          Icons.auto_fix_normal,
          () => selectTool(tool == 'eraser' ? 'select' : 'eraser'),
          active: tool == 'eraser',
        ),
        divider,
        toolbarButton(
          'annotation-undo',
          context.l10n.uiUndo,
          Icons.undo,
          c.markup.canUndo ? () => history(false) : null,
        ),
        toolbarButton(
          'annotation-redo',
          context.l10n.uiRedo,
          Icons.redo,
          c.markup.canRedo ? () => history(true) : null,
        ),
        if (selected != null)
          toolbarButton(
            'annotation-delete',
            context.l10n.uiDeleteSelected,
            Icons.delete_outline,
            deleteSelected,
          ),
        divider,
        toolbarButton(
          'cancel-screenshot',
          context.l10n.uiCancelScreenshot,
          Icons.close,
          c.cancelScreenshot,
        ),
        if (c.supports(DesktopFeature.pinnedImages))
          toolbarButton(
            'pin-screenshot',
            context.l10n.uiPinScreenshot,
            Icons.push_pin_outlined,
            image == null ? null : () => export(false, pin: true),
          ),
        if (c.supports(DesktopFeature.textRecognition))
          toolbarButton(
            'recognize-text',
            context.l10n.uiRecognizeText,
            Icons.text_fields,
            recognizeText,
          ),
        if (c.supports(DesktopFeature.qrCode))
          toolbarButton(
            'recognize-qr-code',
            context.l10n.uiRecognizeQrCode,
            Icons.qr_code_scanner,
            recognizeQrCodes,
          ),
        toolbarButton(
          'save-screenshot',
          context.l10n.uiSavePng,
          Icons.save_alt,
          image == null ? null : () => export(true),
        ),
        toolbarButton(
          'copy-screenshot',
          context.l10n.uiCopyAndFinish,
          Icons.copy_all_outlined,
          image == null ? null : () => export(false),
        ),
      ],
    ),
  );

  Widget toolbar({
    required bool above,
    required double mainWidth,
    required double anchorX,
  }) => TextFieldTapRegion(
    child: Theme(
      data: Theme.of(context).copyWith(
        colorScheme: Theme.of(context).colorScheme.copyWith(
          primary: toolbarBlue,
          onPrimary: Colors.white,
          surface: toolbarSurface,
        ),
      ),
      child: AbsorbPointer(
        absorbing: !editable,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (above && hasProperties) ...[
              SizedBox(
                height: 32,
                width: double.infinity,
                child: CustomSingleChildLayout(
                  delegate: _PropertyBarLayout(anchorX),
                  child: propertyBar(),
                ),
              ),
              const SizedBox(height: 4),
            ],
            Padding(
              padding: EdgeInsets.only(left: anchorX),
              child: SizedBox(width: mainWidth, child: mainBar()),
            ),
            if (!above && hasProperties) ...[
              const SizedBox(height: 4),
              SizedBox(
                height: 32,
                width: double.infinity,
                child: CustomSingleChildLayout(
                  delegate: _PropertyBarLayout(anchorX),
                  child: propertyBar(),
                ),
              ),
            ],
            if (loadFailed) Text(context.l10n.uiScreenshotLoadingFailed),
          ],
        ),
      ),
    ),
  );

  Widget captureFeedback({bool recognizing = false}) => Positioned(
    top: 24,
    left: 24,
    right: 24,
    child: IgnorePointer(
      ignoring: !recognizing,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Semantics(
            liveRegion: true,
            child: toolbarPanel(
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                child: Row(
                  children: [
                    if (recognizing)
                      const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      const Icon(
                        Icons.info_outline,
                        color: Colors.orange,
                        size: 20,
                      ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        recognizing
                            ? context.l10n.uiQrCodeRecognizing
                            : c.error!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          height: 1.5,
                        ),
                      ),
                    ),
                    if (recognizing) ...[
                      const SizedBox(width: 8),
                      toolbarButton(
                        'cancel-qr-code',
                        context.l10n.uiCancelScreenshot,
                        Icons.close,
                        c.cancelScreenshot,
                      ),
                    ],
                  ],
                ),
              ),
              key: ValueKey(
                recognizing ? 'qr-code-progress' : 'screenshot-error-feedback',
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget qrCodePanel() => Positioned.fill(
    // 光标放大镜会动态插入同一 Stack，固定身份以保留当前结果和滚动位置。
    key: const ValueKey('qr-code-panel'),
    child: Material(
      color: Colors.black54,
      child: _QrCodeResultsDialog(
        results: c.qrCodeResults,
        copying: c.qrCodeCopying,
        error: c.error,
        onCopy: c.copyQrCode,
        onAdjust: c.dismissQrCodes,
        onClose: c.cancelScreenshot,
      ),
    ),
  );

  Widget inlineText(Rect selection) {
    final b = textRect!;
    return Positioned(
      left: selection.left + b.left / c.screenshotScaleX,
      top: selection.top + b.top / c.screenshotScaleY,
      width: b.width / c.screenshotScaleX,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: b.height / c.screenshotScaleY),
        child: TextField(
          key: const ValueKey('annotation-text-input'),
          controller: textInput,
          focusNode: textFocus,
          autofocus: true,
          maxLines: null,
          maxLength: 4096,
          cursorColor: Color(color),
          style: TextStyle(
            color: Color(color),
            fontSize: fontSize,
            fontFamily: fontFamily,
            height: 1.2,
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            fontStyle: italic ? FontStyle.italic : FontStyle.normal,
            shadows: outlined
                ? [
                    for (var i = 0; i < 8; i++)
                      Shadow(
                        color: AnnotationRenderer.textOutlineColor(color),
                        offset:
                            Offset(
                              math.cos(i * math.pi / 4),
                              math.sin(i * math.pi / 4),
                            ) *
                            (fontSize / 24),
                      ),
                  ]
                : null,
          ),
          decoration: InputDecoration(
            isDense: true,
            counterText: '',
            filled: false,
            contentPadding: EdgeInsets.zero,
            enabledBorder: OutlineInputBorder(
              borderSide: const BorderSide(color: toolbarBlue, width: 1),
              borderRadius: BorderRadius.zero,
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: const BorderSide(color: toolbarBlue, width: 1),
              borderRadius: BorderRadius.zero,
            ),
          ),
          onTapOutside: (event) {
            textCommitPointer = event.pointer;
            finishText();
            Future<void>.microtask(() => textCommitPointer = null);
          },
        ),
      ),
    );
  }

  // 静止时只在选区内及边界取色；拖动期间持续显示，允许从控制点外半边操作。
  bool get sampling => tool == 'select' && c.canAdjustScreenshotSelection;

  Widget pickerFeedback(BoxConstraints constraints) {
    final p = screenPointer!;
    final sample = c.screenshotColorAt(p.dx, p.dy);
    final source = c.imageDocument!.frame.source;
    final pixel = source.logicalToPixel(p.dx, p.dy);
    final selection = selectionPreview ?? c.screenshotSelection!;
    const panelWidth = 220.0, panelHeight = 224.0;
    final x = p.dx + 24 + panelWidth > constraints.maxWidth
        ? p.dx - panelWidth - 24
        : p.dx + 24;
    final y = p.dy + 24 + panelHeight > constraints.maxHeight
        ? p.dy - panelHeight - 24
        : p.dy + 24;
    return Positioned(
      left: x.clamp(8.0, math.max(8.0, constraints.maxWidth - panelWidth - 8)),
      top: y.clamp(8.0, math.max(8.0, constraints.maxHeight - panelHeight - 8)),
      child: IgnorePointer(
        child: Container(
          key: const ValueKey('screenshot-picker-feedback'),
          width: panelWidth,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: toolbarSurface,
            borderRadius: BorderRadius.circular(4),
          ),
          child: DefaultTextStyle.merge(
            style: const TextStyle(
              fontSize: 11,
              height: 1.45,
              fontFamily: 'monospace',
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                RepaintBoundary(
                  key: const ValueKey('screenshot-magnifier'),
                  child: SizedBox(
                    width: 200,
                    height: 112,
                    child: CustomPaint(
                      painter: _CaptureLoupePainter(
                        image,
                        Offset(pixel.x.toDouble(), pixel.y.toDouble()),
                        c.zoom.toDouble() / c.screenshotScaleX,
                        Rect.fromLTRB(
                          selection.left.toDouble(),
                          selection.top.toDouble(),
                          selection.right.toDouble(),
                          selection.bottom.toDouble(),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      key: const ValueKey('screenshot-color-swatch'),
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: Color.fromARGB(
                          255,
                          sample?.r ?? 0,
                          sample?.g ?? 0,
                          sample?.b ?? 0,
                        ),
                        border: Border.all(color: Colors.white54, width: .5),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(sample?.hex ?? ''),
                  ],
                ),
                Text(sample?.rgb ?? ''),
                Text(
                  ScreenUnits.position(
                    pixel.x,
                    pixel.y,
                    scaleX: c.screenshotScaleX,
                    scaleY: c.screenshotScaleY,
                  ),
                ),
                Text(
                  context.l10n.uiCaptureRegion(
                    ScreenUnits.dimensions(
                      selection.width,
                      selection.height,
                      scaleX: c.screenshotScaleX,
                      scaleY: c.screenshotScaleY,
                    ),
                  ),
                ),
                Text(context.l10n.uiCaptureCopyHint),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (selected != null && selected! >= items.length) selected = null;
    final selection = c.screenshotSelection!;
    final rect = Rect.fromLTRB(
      selection.left / c.screenshotScaleX,
      selection.top / c.screenshotScaleY,
      selection.right / c.screenshotScaleX,
      selection.bottom / c.screenshotScaleY,
    );
    final activeSelection = selectionPreview ?? selection;
    final selectionOffset = Offset(
      (selection.left - activeSelection.left).toDouble(),
      (selection.top - activeSelection.top).toDouble(),
    );
    final displayedItems = selectionOffset == Offset.zero
        ? visibleItems
        : visibleItems
              .map(
                (a) => a.copyWith(
                  points: a.points.map((p) => p + selectionOffset).toList(),
                ),
              )
              .toList();
    final activeRect = Rect.fromLTRB(
      activeSelection.left / c.screenshotScaleX,
      activeSelection.top / c.screenshotScaleY,
      activeSelection.right / c.screenshotScaleX,
      activeSelection.bottom / c.screenshotScaleY,
    );
    return Focus(
      focusNode: focus,
      autofocus: true,
      onKeyEvent: key,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 按平台能力收紧工具栏；选中标注时增加删除按钮。
          final buttonCount =
              12 +
              [
                DesktopFeature.pinnedImages,
                DesktopFeature.textRecognition,
                DesktopFeature.qrCode,
              ].where(c.supports).length;
          final toolbarWidth = math.min(
            buttonCount * 30.0 + 2 * 8 + 2 * 3 + (selected != null ? 30 : 0),
            constraints.maxWidth - 24,
          );
          var feedbackHeight = 0.0;
          for (final message in [
            if (loadFailed) context.l10n.uiScreenshotLoadingFailed,
          ]) {
            final painter = TextPainter(
              text: TextSpan(
                text: message,
                style: DefaultTextStyle.of(context).style,
              ),
              textDirection: Directionality.of(context),
              textScaler: MediaQuery.textScalerOf(context),
            )..layout(maxWidth: constraints.maxWidth - 24);
            feedbackHeight += painter.height.ceilToDouble();
            painter.dispose();
          }
          final totalHeight = (hasProperties ? 72.0 : 36.0) + feedbackHeight;
          final above =
              rect.bottom + totalHeight + 8 > constraints.maxHeight &&
              rect.top > totalHeight + 8;
          final left = (activeRect.right - toolbarWidth).clamp(
            12.0,
            math.max(12.0, constraints.maxWidth - toolbarWidth - 12),
          );
          final top = above
              ? rect.top - totalHeight - 8
              : (rect.bottom + 8).clamp(
                  8.0,
                  math.max(8.0, constraints.maxHeight - totalHeight - 8),
                );
          return MouseRegion(
            onHover: (event) {
              if (sampling) {
                setState(() => screenPointer = event.localPosition);
              } else {
                screenPointer = event.localPosition;
              }
            },
            child: Listener(
              onPointerDown: (event) {
                if (sampling) {
                  setState(() => screenPointer = event.localPosition);
                }
              },
              onPointerMove: (event) {
                if (sampling) {
                  setState(() => screenPointer = event.localPosition);
                }
              },
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerSignal: widthScroll,
                    ),
                  ),
                  Positioned.fromRect(
                    rect: activeRect,
                    child: ClipRect(
                      child: OverflowBox(
                        alignment: Alignment.topLeft,
                        minWidth: 0,
                        minHeight: 0,
                        maxWidth: double.infinity,
                        maxHeight: double.infinity,
                        child: Transform(
                          alignment: Alignment.topLeft,
                          transform: Matrix4.diagonal3Values(
                            1 / c.screenshotScaleX,
                            1 / c.screenshotScaleY,
                            1,
                          ),
                          child: Listener(
                            key: const ValueKey('annotation-canvas'),
                            onPointerDown: down,
                            onPointerMove: move,
                            onPointerUp: up,
                            onPointerCancel: (_) => cancelGesture(),
                            onPointerSignal: (event) {
                              if (event is PointerScrollEvent &&
                                  event.scrollDelta.dy != 0 &&
                                  editable &&
                                  !textEditing) {
                                GestureBinding.instance.pointerSignalResolver
                                    .register(
                                      event,
                                      (_) => adjustWidth(
                                        event.scrollDelta.dy < 0 ? 1 : -1,
                                      ),
                                    );
                              }
                            },
                            child: MouseRegion(
                              cursor: canvasCursor,
                              onEnter: (event) => hover(event.localPosition),
                              onHover: (event) => hover(event.localPosition),
                              onExit: (_) => hover(null),
                              child: SizedBox(
                                width: activeSelection.width.toDouble(),
                                height: activeSelection.height.toDouble(),
                                child: image == null
                                    ? const SizedBox.shrink()
                                    : RepaintBoundary(
                                        key: const ValueKey(
                                          'annotation-content',
                                        ),
                                        child: CustomPaint(
                                          painter: _AnnotationPainter(
                                            image!,
                                            Rect.fromLTWH(
                                              activeSelection.left.toDouble(),
                                              activeSelection.top.toDouble(),
                                              activeSelection.width.toDouble(),
                                              activeSelection.height.toDouble(),
                                            ),
                                            mosaics,
                                            displayedItems,
                                            textEditing ? null : selected,
                                            scale,
                                            !eraserBrush &&
                                                    start != null &&
                                                    eraserEnd != null
                                                ? Rect.fromPoints(
                                                    start!,
                                                    eraserEnd!,
                                                  )
                                                : null,
                                          ),
                                        ),
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _SelectionShadePainter(activeRect),
                      ),
                    ),
                  ),
                  Positioned(
                    left: activeRect.left.clamp(
                      4.0,
                      constraints.maxWidth - 160,
                    ),
                    top: math.max(4.0, activeRect.top - 24),
                    child: IgnorePointer(
                      child: Container(
                        key: const ValueKey('screenshot-size-label'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          ScreenUnits.dimensions(
                            activeSelection.width,
                            activeSelection.height,
                            scaleX: c.screenshotScaleX,
                            scaleY: c.screenshotScaleY,
                          ),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (canAdjustSelection) ...[
                    selectionHandle('nw', activeRect.topLeft),
                    selectionHandle('n', activeRect.topCenter),
                    selectionHandle('ne', activeRect.topRight),
                    selectionHandle('e', activeRect.centerRight),
                    selectionHandle('se', activeRect.bottomRight),
                    selectionHandle('s', activeRect.bottomCenter),
                    selectionHandle('sw', activeRect.bottomLeft),
                    selectionHandle('w', activeRect.centerLeft),
                  ],
                  if (showBrushCursor) brushCursor(rect),
                  if (textEditing) inlineText(rect),
                  if (toolbarVisible && selectionDrag == null && !c.textMode)
                    Positioned(
                      left: 12,
                      top: top.toDouble(),
                      width: constraints.maxWidth - 24,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.basic,
                        child: toolbar(
                          above: above,
                          mainWidth: toolbarWidth,
                          anchorX: left.toDouble() - 12,
                        ),
                      ),
                    ),
                  // 放在工具条之后绘制；IgnorePointer 保留底下按钮的交互。
                  if (sampling &&
                      screenPointer != null &&
                      (selectionDrag != null ||
                          (screenPointer!.dx >= activeRect.left &&
                              screenPointer!.dx <= activeRect.right &&
                              screenPointer!.dy >= activeRect.top &&
                              screenPointer!.dy <= activeRect.bottom)))
                    pickerFeedback(constraints),
                  if (c.textMode)
                    Positioned.fill(
                      child: _TextRecognitionOverlay(
                        controller: c,
                        rect: rect,
                        toolbarTop: top.toDouble(),
                      ),
                    ),
                  // 独立提示不挤压工具栏，也不拦截下面的选区调整。
                  if (c.error != null &&
                      !c.qrCodeBusy &&
                      c.qrCodeResults.isEmpty)
                    captureFeedback(),
                  if (c.qrCodeRecognizing) captureFeedback(recognizing: true),
                  if (c.qrCodeResults.isNotEmpty) qrCodePanel(),
                  if (colorPicking)
                    const Positioned.fill(
                      child: ModalBarrier(
                        key: ValueKey('annotation-color-barrier'),
                        dismissible: false,
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CaptureLoupePainter extends CustomPainter {
  const _CaptureLoupePainter(this.image, this.pixel, this.cell, this.selection);
  final ui.Image? image;
  final Offset pixel;
  final double cell;
  final Rect selection;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.drawColor(Colors.black, BlendMode.src);
    final center = size.center(Offset.zero);
    if (image != null) {
      canvas.save();
      canvas.translate(
        center.dx - (pixel.dx + .5) * cell,
        center.dy - (pixel.dy + .5) * cell,
      );
      canvas.scale(cell);
      canvas.drawImage(
        image!,
        Offset.zero,
        Paint()..filterQuality = FilterQuality.none,
      );
      // 使用原图像素坐标叠加选区遮罩和边界，不把辅助线混入取色结果。
      final visible = Rect.fromLTWH(
        0,
        0,
        image!.width.toDouble(),
        image!.height.toDouble(),
      );
      canvas.drawPath(
        Path.combine(
          PathOperation.difference,
          Path()..addRect(visible),
          Path()..addRect(selection),
        ),
        Paint()..color = Colors.black.withValues(alpha: .45),
      );
      canvas.drawRect(
        selection,
        Paint()
          ..color = const Color(0xFF2683FF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1 / cell
          ..isAntiAlias = false,
      );
      canvas.restore();
    }
    canvas.drawRect(
      Rect.fromCenter(center: center, width: cell, height: cell),
      Paint()
        ..color = const Color(0xFFD7FA6B)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CaptureLoupePainter old) =>
      old.image != image ||
      old.pixel != pixel ||
      old.cell != cell ||
      old.selection != selection;
}

class _SelectionShadePainter extends CustomPainter {
  const _SelectionShadePainter(this.selection);
  final Rect selection;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withValues(alpha: .45);
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        Path()..addRect(selection),
      ),
      paint,
    );
    canvas.drawRect(
      selection,
      Paint()
        ..color = const Color(0xFF2683FF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _SelectionShadePainter old) =>
      old.selection != selection;
}

class _AnnotationPainter extends CustomPainter {
  _AnnotationPainter(
    this.image,
    this.sourceRect,
    this.mosaics,
    this.items,
    this.selected,
    this.scale,
    this.eraserRegion,
  );
  final ui.Image image;
  final Rect sourceRect;
  final Map<int, ui.Image> mosaics;
  final List<Annotation> items;
  final int? selected;
  final double scale;
  final Rect? eraserRegion;
  @override
  void paint(Canvas canvas, Size size) {
    AnnotationRenderer.paint(
      canvas,
      image,
      mosaics,
      items,
      sourceRect: sourceRect,
    );
    if (eraserRegion != null) {
      canvas.drawRect(
        eraserRegion!,
        Paint()..color = const Color(0xFF2683FF).withValues(alpha: .14),
      );
      canvas.drawRect(
        eraserRegion!,
        Paint()
          ..color = const Color(0xFF2683FF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1 / scale,
      );
    }
    if (selected != null && selected! < items.length) {
      final b = items[selected!].bounds;
      final pen = Paint()
        ..color = const Color(0xFF2683FF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1 / scale;
      canvas.drawRect(b, pen);
      for (final p in [b.topLeft, b.topRight, b.bottomLeft, b.bottomRight]) {
        canvas.drawRect(
          Rect.fromCenter(center: p, width: 8 / scale, height: 8 / scale),
          Paint()..color = const Color(0xFF2683FF),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _AnnotationPainter old) =>
      old.image != image ||
      old.sourceRect != sourceRect ||
      old.mosaics != mosaics ||
      old.selected != selected ||
      old.scale != scale ||
      old.eraserRegion != eraserRegion ||
      !listEquals(old.items, items);
}

class _ToolbarGlyphPainter extends CustomPainter {
  const _ToolbarGlyphPainter(this.kind, this.color);
  final String kind;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 18, size.height / 18);
    final pen = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.35
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    switch (kind) {
      case 'shape':
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(1.5, 2.5, 11, 9),
            const Radius.circular(1.5),
          ),
          pen,
        );
        canvas.drawOval(const Rect.fromLTWH(8, 9, 8.5, 6.5), pen);
      case 'line':
        canvas.drawPath(
          Path()
            ..moveTo(1.5, 13)
            ..lineTo(6, 8.5)
            ..lineTo(10.5, 11)
            ..lineTo(16, 4.5),
          pen,
        );
        canvas.drawPath(
          Path()
            ..moveTo(12, 4.5)
            ..lineTo(16, 4.5)
            ..lineTo(16, 8.5),
          pen,
        );
      case 'eraser':
        canvas.drawPath(
          Path()
            ..moveTo(2, 11)
            ..lineTo(9, 3.5)
            ..lineTo(16, 10)
            ..lineTo(10, 16)
            ..lineTo(7.5, 16)
            ..close(),
          pen,
        );
        canvas.drawLine(const Offset(5.5, 7.3), const Offset(12.6, 13.5), pen);
        canvas.drawLine(const Offset(7.5, 16), const Offset(16.5, 16), pen);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ToolbarGlyphPainter old) =>
      old.kind != kind || old.color != color;
}

class _PropertyBarLayout extends SingleChildLayoutDelegate {
  _PropertyBarLayout(this.anchorX);
  final double anchorX;
  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();
  @override
  Offset getPositionForChild(Size size, Size childSize) =>
      Offset(math.min(anchorX, size.width - childSize.width), 0);
  @override
  bool shouldRelayout(_PropertyBarLayout oldDelegate) =>
      anchorX != oldDelegate.anchorX;
}
