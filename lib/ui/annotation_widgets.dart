part of 'fruler_app.dart';

class _AnnotationEditor extends StatefulWidget {
  const _AnnotationEditor({super.key, required this.controller});
  final AppController controller;
  @override
  State<_AnnotationEditor> createState() => _AnnotationEditorState();
}

class _AnnotationEditorState extends State<_AnnotationEditor> {
  final focus = FocusNode();
  ui.Image? image, mosaic;
  String? loadError;
  String tool = 'select';
  String lastShape = 'rectangle', lastLine = 'arrow', lastEffect = 'mosaic';
  bool filled = false, bold = false, italic = false, toolbarVisible = true;
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
          int color,
          double width,
          double fontSize,
          bool filled,
          bool bold,
          bool italic,
        })
      >{};
  int color = 0xFFFF0000;
  double width = 3, fontSize = 24;
  int? selected, pointerId;
  Annotation? preview, original;
  Offset? start, resizeAnchor, eraserEnd, hoverPosition;
  bool textEditing = false;
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
  bool get editable => c.screenshotEditing && !c.imageLoading && !c.imageSaving;
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
    load();
  }

  Future<void> load() async {
    ui.Image? decoded, pixels;
    try {
      final codec = await ui.instantiateImageCodec(c.imageDocument!.png);
      try {
        decoded = (await codec.getNextFrame()).image;
      } finally {
        codec.dispose();
      }
      pixels = await AnnotationRenderer.pixelate(decoded);
      if (!mounted) {
        decoded.dispose();
        pixels.dispose();
        return;
      }
      setState(() {
        image = decoded;
        mosaic = pixels;
      });
    } catch (_) {
      decoded?.dispose();
      pixels?.dispose();
      if (mounted) setState(() => loadError = '截图加载失败，请重新框选');
    }
  }

  @override
  void dispose() {
    image?.dispose();
    mosaic?.dispose();
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
          .showSnackBar(SnackBar(content: Text(e.message)));
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
    width: width,
    fontSize: fontSize,
    text: text,
    filled: filled,
    bold: bold,
    italic: italic,
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
    styles[styleKey(tool)] = (
      color: color,
      width: width,
      fontSize: fontSize,
      filled: filled,
      bold: bold,
      italic: italic,
    );
    cancelGesture();
    final next = styles[styleKey(value)];
    setState(() {
      tool = value;
      selected = null;
      color = next?.color ?? 0xFFFF0000;
      width = next?.width ?? (value == 'marker' ? 12 : 3);
      fontSize = next?.fontSize ?? 24;
      filled = next?.filled ?? false;
      bold = next?.bold ?? false;
      italic = next?.italic ?? false;
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
    } else {
      c.reselectScreenshot();
    }
  }

  void export(bool save) {
    finishText();
    finishLine();
    c.exportScreenshot(save: save);
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
    bool? nextFilled,
    bool? nextBold,
    bool? nextItalic,
  }) {
    setState(() {
      color = nextColor ?? color;
      width = nextWidth ?? width;
      fontSize = nextFont ?? fontSize;
      filled = nextFilled ?? filled;
      bold = nextBold ?? bold;
      italic = nextItalic ?? italic;
    });
    if (!textEditing && selected != null && selected! < items.length) {
      final next = List<Annotation>.of(items);
      next[selected!] = next[selected!].copyWith(
        color: nextColor,
        width: nextWidth,
        fontSize: nextFont,
        filled: nextFilled,
        bold: nextBold,
        italic: nextItalic,
      );
      commit(next);
    }
    textEditing ? textFocus.requestFocus() : focus.requestFocus();
  }

  void beginText(Rect rect, {int? index}) {
    finishText();
    final existing = index == null ? null : items[index];
    final minWidth = math.min(80.0, imageSize.width);
    final w = rect.width < 12 ? math.min(320.0, imageSize.width) : rect.width;
    final left = rect.left.clamp(0.0, imageSize.width - minWidth);
    final top = rect.top.clamp(
      0.0,
      math.max(0.0, imageSize.height - fontSize * 1.4),
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
      width = old.width;
      fontSize = old.fontSize;
      filled = old.filled;
      bold = old.bold;
      italic = old.italic;
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
            fontSize: fontSize,
            fontFamily: AnnotationRenderer.fontFamily,
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
        math.min(rect.width, math.max(24.0, painter.width + 2)),
        math.min(rect.height, math.max(fontSize * 1.3, painter.height + 2)),
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
    width = a.width;
    fontSize = a.fontSize;
    bold = a.bold;
    italic = a.italic;
    beginText(a.bounds, index: selected);
  }

  void adjustWidth(int direction) {
    if (textEditing) return;
    if (tool == 'text' ||
        (selected != null && items[selected!].kind == AnnotationKind.text)) {
      style(nextFont: (fontSize + direction).clamp(8, 200));
    } else if (!['select', 'eraser', 'mosaic', 'blur'].contains(tool)) {
      style(nextWidth: (width + direction).clamp(1, 80));
    }
  }

  Offset clamp(Offset p) =>
      Offset(p.dx.clamp(0, imageSize.width), p.dy.clamp(0, imageSize.height));

  bool get canAdjustSelection =>
      tool == 'select' &&
      c.canAdjustScreenshotSelection &&
      !textEditing &&
      editable;

  void beginSelection(PointerDownEvent event, String handle) {
    if (!canAdjustSelection || event.buttons != kPrimaryMouseButton) return;
    focus.requestFocus();
    setState(() {
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

  MouseCursor get canvasCursor {
    if (!editable || image == null) return SystemMouseCursors.basic;
    if (selectionDrag != null) return SystemMouseCursors.grabbing;
    if (canAdjustSelection) return SystemMouseCursors.grab;
    if (tool != 'select' && selected == null) return SystemMouseCursors.precise;
    if (pointerId != null && original != null) {
      return SystemMouseCursors.grabbing;
    }
    final p = hoverPosition;
    if (p == null) return SystemMouseCursors.basic;
    if (selectedHandle(p)) return SystemMouseCursors.grab;
    final hit = tool == 'select'
        ? items.any((a) => a.hitTest(p, 6 / scale))
        : selected != null && items[selected!].hitTest(p, 6 / scale);
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
    if (canAdjustSelection) {
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
      setState(() => eraserEnd = p);
      return;
    }
    if (tool == 'select' ||
        (selected != null &&
            tool != 'eraser' &&
            (selectedHandle(p) || items[selected!].hitTest(p, 6 / scale)))) {
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
      selected = null;
      for (var i = items.length - 1; i >= 0; i--) {
        if (items[i].hitTest(p, 6 / scale)) {
          selected = i;
          break;
        }
      }
      if (selected != null) {
        original = items[selected!];
        color = original!.color;
        width = original!.width;
        fontSize = original!.fontSize;
        filled = original!.filled;
        bold = original!.bold;
        italic = original!.italic;
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
      setState(() => eraserEnd = p);
      return;
    }
    if (original != null) {
      if (resizeAnchor != null) {
        final b = Rect.fromPoints(resizeAnchor!, p);
        if (b.width >= 1 && b.height >= 1) preview = original!.resize(b);
      } else {
        preview = original!.move(p - start!, imageSize);
      }
    } else if (preview != null) {
      final free = tool == 'pencil' || tool == 'marker';
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
      final origin = start!;
      cancelGesture();
      if ((end - origin).distance < 3 / scale) {
        for (var i = items.length - 1; i >= 0; i--) {
          if (items[i].hitTest(end, 6 / scale)) {
            commit(List<Annotation>.of(items)..removeAt(i));
            break;
          }
        }
      } else {
        final region = Rect.fromPoints(origin, end);
        commit(items.where((a) => !a.intersects(region)).toList());
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
    if (annotation.bounds.width < 1 && annotation.bounds.height < 1) return;
    if ([
          AnnotationKind.rectangle,
          AnnotationKind.ellipse,
          AnnotationKind.mosaic,
          AnnotationKind.blur,
        ].contains(annotation.kind) &&
        annotation.bounds.isEmpty) {
      return;
    }
    if (linePoints.isNotEmpty) finishLine();
    final addedIndex = items.length;
    commit([...items, annotation]);
    setState(() => selected = addedIndex);
  }

  KeyEventResult key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent || !editable) {
      return KeyEventResult.ignored;
    }
    final k = event.logicalKey;
    final meta =
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed;
    final shift = HardwareKeyboard.instance.isShiftPressed;
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
      if (linePoints.isNotEmpty) {
        setState(() {
          linePoints.clear();
          lineHover = null;
        });
        return KeyEventResult.handled;
      }
      cancelGesture();
      selected = null;
      shift ? c.markup.redo() : c.markup.undo();
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
    if (delta != null && canAdjustSelection && selectionDrag == null) {
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
        final b = a.bounds;
        final r = Rect.fromLTRB(
          b.left,
          b.top,
          (b.right + delta.dx).clamp(
            b.left + math.min(1, imageSize.width - b.left),
            imageSize.width,
          ),
          (b.bottom + delta.dy).clamp(
            b.top + math.min(1, imageSize.height - b.top),
            imageSize.height,
          ),
        );
        next[selected!] = a.resize(r);
      } else {
        next[selected!] = a.move(delta, imageSize);
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
    setState(() => selected = null);
    redo ? c.markup.redo() : c.markup.undo();
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
    bool colorDot = false,
    int? dotColor,
  }) => IconButton(
    key: ValueKey(id),
    tooltip: label,
    mouseCursor: action == null
        ? SystemMouseCursors.basic
        : SystemMouseCursors.click,
    isSelected: active,
    iconSize: 18,
    padding: EdgeInsets.zero,
    constraints: const BoxConstraints.tightFor(width: 30, height: 30),
    style: IconButton.styleFrom(
      minimumSize: const Size(30, 30),
      maximumSize: const Size(30, 30),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
      foregroundColor: action == null ? const Color(0xFF777777) : Colors.white,
      backgroundColor: active ? toolbarBlue : Colors.transparent,
    ),
    selectedIcon: toolIcon(icon, Colors.white),
    icon: Stack(
      clipBehavior: Clip.none,
      children: [
        toolIcon(icon, action == null ? const Color(0xFF777777) : Colors.white),
        if (colorDot)
          Positioned(
            right: -4,
            top: -3,
            child: Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: Color(dotColor ?? color),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: .5),
              ),
            ),
          ),
      ],
    ),
    onPressed: action,
  );

  Widget get divider => const SizedBox(
    height: 20,
    child: VerticalDivider(width: 8, thickness: 1, color: Color(0xFF555555)),
  );

  Widget toolbarPanel(Widget child, {Key? key}) => Material(
    key: key,
    color: toolbarSurface,
    elevation: 4,
    shadowColor: Colors.black54,
    borderRadius: BorderRadius.circular(4),
    child: Padding(padding: const EdgeInsets.all(3), child: child),
  );

  String get propertyKind => textEditing
      ? 'text'
      : selected != null && selected! < items.length
      ? items[selected!].kind.name
      : tool;
  bool get hasProperties => !['select', 'eraser'].contains(propertyKind);

  Widget numericMenu({required bool font}) => Tooltip(
    message: font ? '字号' : '线宽 · 滚轮 / 1、2 / [、]',
    child: PopupMenuButton<double>(
      key: ValueKey(font ? 'annotation-font' : 'annotation-width'),
      padding: EdgeInsets.zero,
      color: toolbarSurface,
      tooltip: '',
      constraints: const BoxConstraints(minWidth: 100, maxWidth: 160),
      onSelected: (v) => font ? style(nextFont: v) : style(nextWidth: v),
      itemBuilder: (_) =>
          (font
                  ? <double>{12, 18, 24, 36, 48, 72, fontSize}
                  : <double>{1, 2, 3, 6, 12, 24, 48, width})
              .map(
                (v) => PopupMenuItem(
                  value: v,
                  child: Row(
                    children: [
                      if (!font) ...[
                        Container(
                          width: math.min(16, v + 2),
                          height: math.min(16, v + 2),
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        '${v.toStringAsFixed(0)}${font ? "" : " px"}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: SizedBox(
          width: font ? 44 : 30,
          height: 30,
          child: Center(
            child: font
                ? Text(
                    fontSize.toStringAsFixed(0),
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  )
                : Container(
                    width: math.min(14, width + 2),
                    height: math.min(14, width + 2),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
          ),
        ),
      ),
    ),
  );

  Future<void> customColor() async {
    final value = await _requestName(
      context,
      '标注颜色（6 位 HEX）',
      color.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase(),
    );
    if (!mounted || value == null) return;
    final hex = value.trim().replaceFirst('#', '');
    if (RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(hex)) {
      style(nextColor: 0xFF000000 | int.parse(hex, radix: 16));
    }
  }

  Widget colorPalette() => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Tooltip(
        message: '自定义颜色',
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
        width: 154,
        height: 26,
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
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: Color(value),
                      borderRadius: BorderRadius.circular(2),
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

  Widget propertyBar() {
    final kind = propertyKind;
    final shape = ['rectangle', 'ellipse'].contains(kind);
    final line = ['line', 'arrow'].contains(kind);
    final effect = ['mosaic', 'blur'].contains(kind);
    return toolbarPanel(
      key: const ValueKey('annotation-properties'),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!effect && kind != 'text') numericMenu(font: false),
          if (shape) ...[
            toolbarButton(
              'annotation-fill',
              '填充形状',
              Icons.square,
              () => style(nextFilled: !filled),
              active: filled,
            ),
            divider,
            toolbarButton(
              'annotation-tool-rectangle',
              '矩形',
              Icons.crop_square,
              () => selectTool('rectangle'),
              active: kind == 'rectangle',
            ),
            toolbarButton(
              'annotation-tool-ellipse',
              '椭圆',
              Icons.circle_outlined,
              () => selectTool('ellipse'),
              active: kind == 'ellipse',
            ),
            divider,
          ],
          if (line) ...[
            toolbarButton(
              'annotation-tool-line',
              '直线 / 折线 · Tab 切换箭头',
              Icons.show_chart,
              () => selectTool('line'),
              active: kind == 'line',
            ),
            toolbarButton(
              'annotation-tool-arrow',
              '箭头 · Tab 切换直线',
              Icons.north_east,
              () => selectTool('arrow'),
              active: kind == 'arrow',
            ),
            divider,
          ],
          if (effect) ...[
            toolbarButton(
              'annotation-tool-mosaic',
              '马赛克',
              Icons.grid_view,
              () => selectTool('mosaic'),
              active: kind == 'mosaic',
            ),
            toolbarButton(
              'annotation-tool-blur',
              '高斯模糊',
              Icons.blur_on,
              () => selectTool('blur'),
              active: kind == 'blur',
            ),
          ] else ...[
            if (kind == 'text') ...[
              toolbarButton(
                'annotation-bold',
                '粗体',
                Icons.format_bold,
                () => style(nextBold: !bold),
                active: bold,
              ),
              toolbarButton(
                'annotation-italic',
                '斜体',
                Icons.format_italic,
                () => style(nextItalic: !italic),
                active: italic,
              ),
              numericMenu(font: true),
              if (selected != null && !textEditing)
                toolbarButton(
                  'annotation-edit-text',
                  '编辑文字',
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
          '形状：矩形 / 椭圆',
          Icons.interests_outlined,
          () => selectTool(
            ['rectangle', 'ellipse'].contains(tool) ? 'select' : lastShape,
          ),
          active: ['rectangle', 'ellipse'].contains(tool),
          colorDot: true,
          dotColor: ['rectangle', 'ellipse'].contains(tool)
              ? color
              : styles['shape']?.color ?? 0xFFFF0000,
        ),
        toolbarButton(
          'annotation-group-line',
          '直线 / 折线 / 箭头',
          Icons.timeline,
          () => selectTool(
            ['line', 'arrow'].contains(tool) ? 'select' : lastLine,
          ),
          active: ['line', 'arrow'].contains(tool),
          colorDot: true,
          dotColor: ['line', 'arrow'].contains(tool)
              ? color
              : styles['line']?.color ?? 0xFFFF0000,
        ),
        toolbarButton(
          'annotation-tool-pencil',
          '画笔',
          Icons.edit_outlined,
          () => selectTool(tool == 'pencil' ? 'select' : 'pencil'),
          active: tool == 'pencil',
        ),
        toolbarButton(
          'annotation-tool-marker',
          '荧光笔',
          Icons.border_color_outlined,
          () => selectTool(tool == 'marker' ? 'select' : 'marker'),
          active: tool == 'marker',
        ),
        toolbarButton(
          'annotation-group-effect',
          '马赛克 / 高斯模糊',
          Icons.grid_view,
          () => selectTool(
            ['mosaic', 'blur'].contains(tool) ? 'select' : lastEffect,
          ),
          active: ['mosaic', 'blur'].contains(tool),
        ),
        toolbarButton(
          'annotation-tool-text',
          '文字',
          Icons.title,
          () => selectTool(tool == 'text' ? 'select' : 'text'),
          active: tool == 'text',
        ),
        toolbarButton(
          'annotation-tool-eraser',
          '橡皮擦 · 拖拽框选删除',
          Icons.auto_fix_normal,
          () => selectTool(tool == 'eraser' ? 'select' : 'eraser'),
          active: tool == 'eraser',
        ),
        toolbarButton(
          'annotation-tool-select',
          '选择 / 编辑 · 右键结束当前工具',
          Icons.near_me_outlined,
          () => selectTool('select'),
          active: tool == 'select' && selected != null,
        ),
        divider,
        toolbarButton(
          'annotation-undo',
          '撤销 ⌘Z',
          Icons.undo,
          c.markup.canUndo ? () => history(false) : null,
        ),
        toolbarButton(
          'annotation-redo',
          '重做 ⌘Y / ⇧⌘Z',
          Icons.redo,
          c.markup.canRedo ? () => history(true) : null,
        ),
        if (selected != null)
          toolbarButton(
            'annotation-delete',
            '删除选中 Delete',
            Icons.delete_outline,
            deleteSelected,
          ),
        const Spacer(),
        divider,
        toolbarButton(
          'cancel-screenshot',
          '取消 Esc',
          Icons.close,
          c.cancelScreenshot,
        ),
        toolbarButton(
          'reselect-screenshot',
          '重新框选',
          Icons.crop,
          c.reselectScreenshot,
        ),
        toolbarButton(
          'save-screenshot',
          '保存 PNG ⌘S',
          Icons.save_alt,
          image == null ? null : () => export(true),
        ),
        toolbarButton(
          'copy-screenshot',
          '复制并完成 ↵',
          Icons.copy_all_outlined,
          image == null ? null : () => export(false),
        ),
      ],
    ),
  );

  Widget toolbar({required bool above}) => TextFieldTapRegion(
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
              propertyBar(),
              const SizedBox(height: 4),
            ],
            mainBar(),
            if (!above && hasProperties) ...[
              const SizedBox(height: 4),
              propertyBar(),
            ],
            if (loadError != null) Text(loadError!),
            if (c.error != null)
              Text(c.error!, style: const TextStyle(color: Colors.orange)),
          ],
        ),
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
            fontSize: fontSize / c.screenshotScaleY,
            fontFamily: AnnotationRenderer.fontFamily,
            height: 1.2,
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            fontStyle: italic ? FontStyle.italic : FontStyle.normal,
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
          final toolbarWidth = math.min(488.0, constraints.maxWidth - 24);
          final totalHeight = hasProperties ? 76.0 : 36.0;
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
          return Stack(
            children: [
              Positioned.fromRect(
                rect: rect,
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
                            width: imageSize.width,
                            height: imageSize.height,
                            child: image == null
                                ? const SizedBox.shrink()
                                : CustomPaint(
                                    painter: _AnnotationPainter(
                                      image!,
                                      mosaic!,
                                      visibleItems,
                                      textEditing ? null : selected,
                                      scale,
                                      start != null && eraserEnd != null
                                          ? Rect.fromPoints(start!, eraserEnd!)
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
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _SelectionShadePainter(activeRect),
                  ),
                ),
              ),
              Positioned(
                left: activeRect.left.clamp(4.0, constraints.maxWidth - 160),
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
                      '${activeSelection.width} × ${activeSelection.height} px',
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
              if (textEditing) inlineText(rect),
              if (toolbarVisible && selectionDrag == null)
                Positioned(
                  left: left.toDouble(),
                  top: top.toDouble(),
                  width: toolbarWidth,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.basic,
                    child: toolbar(above: above),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
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
    this.mosaic,
    this.items,
    this.selected,
    this.scale,
    this.eraserRegion,
  );
  final ui.Image image, mosaic;
  final List<Annotation> items;
  final int? selected;
  final double scale;
  final Rect? eraserRegion;
  @override
  void paint(Canvas canvas, Size size) {
    AnnotationRenderer.paint(canvas, image, mosaic, items);
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
  bool shouldRepaint(covariant _AnnotationPainter oldDelegate) => true;
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
