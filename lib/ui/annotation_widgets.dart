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
  String tool = 'arrow';
  int color = 0xFFFF5252;
  double width = 3, fontSize = 24;
  int? selected, pointerId;
  Annotation? preview, original;
  Offset? start, resizeAnchor, eraserEnd;
  bool textEditing = false;
  AppController get c => widget.controller;
  List<Annotation> get items => c.markup.items;
  Size get imageSize => Size(
    c.imageDocument!.frame.width.toDouble(),
    c.imageDocument!.frame.height.toDouble(),
  );
  double get scale => 1 / c.screenshotScaleX;
  bool get editable =>
      c.screenshotEditing && !c.imageLoading && !c.imageSaving && !textEditing;
  List<Annotation> get visibleItems {
    final result = List<Annotation>.of(items);
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
      if (mounted) setState(() => loadError = '图片预览加载失败，请切换页面后重试');
    }
  }

  @override
  void dispose() {
    image?.dispose();
    mosaic?.dispose();
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
    });
  }

  void selectTool(String value) {
    cancelGesture();
    setState(() {
      tool = value;
      selected = null;
    });
    focus.requestFocus();
  }

  void deleteSelected() {
    if (selected == null || selected! >= items.length) return;
    final next = List<Annotation>.of(items)..removeAt(selected!);
    cancelGesture();
    selected = null;
    commit(next);
  }

  void style({int? nextColor, double? nextWidth, double? nextFont}) {
    setState(() {
      color = nextColor ?? color;
      width = nextWidth ?? width;
      fontSize = nextFont ?? fontSize;
    });
    if (selected != null && selected! < items.length) {
      final next = List<Annotation>.of(items);
      next[selected!] = next[selected!].copyWith(
        color: nextColor,
        width: nextWidth,
        fontSize: nextFont,
      );
      commit(next);
    }
    focus.requestFocus();
  }

  Future<String?> askText(String initial) async {
    textEditing = true;
    final input = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('文字标注'),
        content: SizedBox(
          width: 400,
          child: TextField(
            controller: input,
            autofocus: true,
            minLines: 3,
            maxLines: 8,
            maxLength: 4096,
            decoration: const InputDecoration(hintText: '输入文字，支持多行'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (input.text.trim().isNotEmpty) {
                Navigator.pop(context, input.text);
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
    // The dialog's reverse transition can still be using its text controller.
    Future<void>.delayed(const Duration(milliseconds: 300), input.dispose);
    textEditing = false;
    if (mounted) {
      setState(() {});
      focus.requestFocus();
    }
    return result;
  }

  Future<void> editText() async {
    final index = selected;
    if (index == null ||
        index >= items.length ||
        items[index].kind != AnnotationKind.text) {
      return;
    }
    final old = items[index];
    final value = await askText(old.text);
    if (!mounted ||
        value == null ||
        index >= items.length ||
        items[index] != old) {
      return;
    }
    final next = List<Annotation>.of(items);
    next[index] = old.copyWith(text: value);
    commit(next);
  }

  Offset clamp(Offset p) =>
      Offset(p.dx.clamp(0, imageSize.width), p.dy.clamp(0, imageSize.height));

  void down(PointerDownEvent event) {
    if (!editable || image == null || tool == 'pan') return;
    if (event.buttons != kPrimaryMouseButton) {
      cancelGesture();
      return;
    }
    focus.requestFocus();
    final p = clamp(event.localPosition);
    pointerId = event.pointer;
    start = p;
    original = null;
    resizeAnchor = null;
    if (tool == 'eraser') {
      selected = null;
      setState(() => eraserEnd = p);
      return;
    }
    if (tool == 'select') {
      if (tool == 'select' && selected != null && selected! < items.length) {
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
      }
    } else {
      selected = null;
      preview = Annotation(
        kind: AnnotationKind.values.byName(tool),
        points: [p, p],
        color: color,
        width: tool == 'marker' ? math.max(12, width) : width,
        fontSize: fontSize,
      );
    }
    setState(() {});
  }

  void move(PointerMoveEvent event) {
    if (pointerId != event.pointer || start == null || !editable) return;
    final p = clamp(event.localPosition);
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
      if (!free || (p - preview!.points.last).distance >= .5) {
        preview = preview!.copyWith(
          points: free ? [...preview!.points.take(19999), p] : [start!, p],
        );
      }
    }
    setState(() {});
  }

  Future<void> up(PointerUpEvent event) async {
    if (pointerId != event.pointer) return;
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
      final document = c.imageDocument;
      final value = await askText('');
      if (!mounted || value == null || c.imageDocument != document) return;
      var b = annotation.bounds;
      if (b.width < 12 || b.height < 12) {
        final w = math.min(imageSize.width, 320.0);
        final h = math.min(
          imageSize.height,
          math.max(
            fontSize * 1.3,
            (value.split('\n').length + 1) * fontSize * 1.3,
          ),
        );
        final left = b.left.clamp(0.0, imageSize.width - w);
        final top = b.top.clamp(0.0, imageSize.height - h);
        b = Rect.fromLTWH(left, top, w, h);
      }
      commit([
        ...items,
        annotation.copyWith(points: [b.topLeft, b.bottomRight], text: value),
      ]);
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
    commit([...items, annotation]);
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
    if (meta && k == LogicalKeyboardKey.keyZ) {
      cancelGesture();
      selected = null;
      shift ? c.markup.redo() : c.markup.undo();
      return KeyEventResult.handled;
    }
    if ((meta && k == LogicalKeyboardKey.keyS) ||
        k == LogicalKeyboardKey.enter) {
      c.exportScreenshot(save: meta && k == LogicalKeyboardKey.keyS);
      return KeyEventResult.handled;
    }
    if (meta && k == LogicalKeyboardKey.keyC) {
      c.exportScreenshot(save: false);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.delete || k == LogicalKeyboardKey.backspace) {
      deleteSelected();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.escape) {
      if (start != null) {
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
    cancelGesture();
    setState(() => selected = null);
    redo ? c.markup.redo() : c.markup.undo();
    focus.requestFocus();
  }

  Widget toolbarButton(
    String id,
    String label,
    IconData icon,
    VoidCallback? action, {
    bool active = false,
  }) => IconButton(
    key: ValueKey(id),
    tooltip: label,
    isSelected: active,
    selectedIcon: Icon(icon, color: _accent),
    style: IconButton.styleFrom(
      backgroundColor: active
          ? _accent.withValues(alpha: .18)
          : Colors.transparent,
      padding: EdgeInsets.zero,
      minimumSize: const Size(32, 32),
      maximumSize: const Size(32, 32),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
    iconSize: 19,
    onPressed: action,
    icon: Icon(icon),
  );

  Widget get divider => const SizedBox(
    height: 24,
    child: VerticalDivider(width: 12, color: _line),
  );

  Widget toolbar() {
    final kind = tool == 'select' && selected != null
        ? items[selected!].kind.name
        : tool;
    final hasColor = !['select', 'eraser', 'mosaic', 'blur'].contains(kind);
    final hasWidth = hasColor && kind != 'text';
    return Padding(
      padding: const EdgeInsets.all(6),
      child: AbsorbPointer(
        absorbing: !editable,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final entry in <String, (String, IconData)>{
                  'select': ('选择 / 编辑', Icons.near_me_outlined),
                  'rectangle': ('矩形', Icons.crop_square),
                  'ellipse': ('椭圆', Icons.circle_outlined),
                  'line': ('直线', Icons.horizontal_rule),
                  'arrow': ('箭头', Icons.north_east),
                  'pencil': ('画笔', Icons.edit_outlined),
                  'marker': ('荧光笔', Icons.border_color_outlined),
                  'text': ('文字', Icons.title),
                  'mosaic': ('马赛克', Icons.grid_on),
                  'blur': ('模糊', Icons.blur_on),
                  'eraser': ('橡皮擦', Icons.auto_fix_normal),
                }.entries)
                  toolbarButton(
                    'annotation-tool-${entry.key}',
                    entry.value.$1,
                    entry.value.$2,
                    () => selectTool(entry.key),
                    active: tool == entry.key,
                  ),
                divider,
                toolbarButton(
                  'annotation-undo',
                  '撤销',
                  Icons.undo,
                  c.markup.canUndo ? () => history(false) : null,
                ),
                toolbarButton(
                  'annotation-redo',
                  '重做',
                  Icons.redo,
                  c.markup.canRedo ? () => history(true) : null,
                ),
                if (selected != null)
                  toolbarButton(
                    'annotation-delete',
                    '删除选中',
                    Icons.delete_outline,
                    deleteSelected,
                  ),
                divider,
                toolbarButton(
                  'reselect-screenshot',
                  '重新框选',
                  Icons.crop,
                  c.reselectScreenshot,
                ),
                toolbarButton(
                  'cancel-screenshot',
                  '取消 Esc',
                  Icons.close,
                  c.cancelScreenshot,
                ),
                toolbarButton(
                  'save-screenshot',
                  '保存 PNG ⌘S',
                  Icons.save_alt,
                  image == null ? null : () => c.exportScreenshot(save: true),
                ),
                toolbarButton(
                  'copy-screenshot',
                  '复制并完成 ↵',
                  Icons.check,
                  image == null ? null : () => c.exportScreenshot(save: false),
                ),
              ],
            ),
            if (hasColor) ...[
              const Divider(height: 9, color: _line),
              SizedBox(
                key: const ValueKey('annotation-properties'),
                height: 32,
                child: Row(
                  children: [
                    for (final value in [
                      0xFFFF5252,
                      0xFFFFC107,
                      0xFF69F0AE,
                      0xFF40C4FF,
                      0xFFB388FF,
                      0xFFFFFFFF,
                      0xFF000000,
                    ])
                      Tooltip(
                        message:
                            '#${value.toRadixString(16).substring(2).toUpperCase()}',
                        child: InkWell(
                          onTap: () => style(nextColor: value),
                          child: Container(
                            width: 22,
                            height: 22,
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            decoration: BoxDecoration(
                              color: Color(value),
                              borderRadius: BorderRadius.circular(3),
                              border: Border.all(
                                width: value == color ? 2 : 1,
                                color: value == color ? _accent : _muted,
                              ),
                            ),
                          ),
                        ),
                      ),
                    toolbarButton(
                      'annotation-color',
                      '自定义颜色',
                      Icons.palette_outlined,
                      () async {
                        final value = await _requestName(
                          context,
                          '标注颜色（6 位 HEX）',
                          color
                              .toRadixString(16)
                              .padLeft(8, '0')
                              .substring(2)
                              .toUpperCase(),
                        );
                        if (!mounted || !context.mounted || value == null) {
                          return;
                        }
                        final hex = value.trim().replaceFirst('#', '');
                        if (RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(hex)) {
                          style(
                            nextColor: 0xFF000000 | int.parse(hex, radix: 16),
                          );
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('请输入 6 位 HEX 颜色')),
                          );
                        }
                      },
                    ),
                    divider,
                    Text(
                      hasWidth ? '线宽' : '字号',
                      style: const TextStyle(fontSize: 12, color: _muted),
                    ),
                    const SizedBox(width: 8),
                    DropdownButtonHideUnderline(
                      child: DropdownButton<double>(
                        key: ValueKey(
                          hasWidth ? 'annotation-width' : 'annotation-font',
                        ),
                        value: hasWidth ? width : fontSize,
                        isDense: true,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white,
                        ),
                        items:
                            ({
                                  if (hasWidth) ...[
                                    1.0,
                                    3.0,
                                    6.0,
                                    12.0,
                                    24.0,
                                    48.0,
                                    width,
                                  ] else ...[
                                    12.0,
                                    18.0,
                                    24.0,
                                    36.0,
                                    48.0,
                                    72.0,
                                    fontSize,
                                  ],
                                }.toList()..sort())
                                .map(
                                  (v) => DropdownMenuItem(
                                    value: v,
                                    child: Text(
                                      '${v.toStringAsFixed(0)}${hasWidth ? " px" : ""}',
                                    ),
                                  ),
                                )
                                .toList(),
                        onChanged: (v) {
                          if (v != null) {
                            hasWidth ? style(nextWidth: v) : style(nextFont: v);
                          }
                        },
                      ),
                    ),
                    if (kind == 'text' && selected != null)
                      toolbarButton(
                        'annotation-edit-text',
                        '编辑文字',
                        Icons.edit_note,
                        editText,
                      ),
                  ],
                ),
              ),
            ],
            if (loadError != null) Text(loadError!),
            if (c.error != null)
              Text(c.error!, style: const TextStyle(color: Colors.orange)),
          ],
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
    return Focus(
      focusNode: focus,
      autofocus: true,
      onKeyEvent: key,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final toolbarWidth = math.min(644.0, constraints.maxWidth - 24);
          final left = rect.left.clamp(
            12.0,
            math.max(12.0, constraints.maxWidth - toolbarWidth - 12),
          );
          final top = rect.bottom + 100 < constraints.maxHeight
              ? rect.bottom + 10
              : rect.top > 100
              ? rect.top - 94
              : math.max(12.0, constraints.maxHeight - 94.0);
          return Stack(
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(painter: _SelectionShadePainter(rect)),
                ),
              ),
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
                        child: MouseRegion(
                          cursor: SystemMouseCursors.precise,
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
                                      tool == 'select' ? selected : null,
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
              Positioned(
                left: left.toDouble(),
                top: top,
                width: toolbarWidth,
                child: Material(
                  color: _panel,
                  elevation: 12,
                  borderRadius: BorderRadius.circular(10),
                  key: const ValueKey('annotation-toolbar'),
                  child: toolbar(),
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
        ..color = _accent
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
        Paint()..color = _accent.withValues(alpha: .14),
      );
      canvas.drawRect(
        eraserRegion!,
        Paint()
          ..color = _accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1 / scale,
      );
    }
    if (selected != null && selected! < items.length) {
      final b = items[selected!].bounds;
      final pen = Paint()
        ..color = _accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1 / scale;
      canvas.drawRect(b, pen);
      for (final p in [b.topLeft, b.topRight, b.bottomLeft, b.bottomRight]) {
        canvas.drawRect(
          Rect.fromCenter(center: p, width: 8 / scale, height: 8 / scale),
          Paint()..color = _accent,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _AnnotationPainter oldDelegate) => true;
}
