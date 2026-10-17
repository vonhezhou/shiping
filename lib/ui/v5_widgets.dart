part of 'fruler_app.dart';

Future<String?> _chooseGroup(
  BuildContext context,
  AppController c,
  String current,
) => showDialog<String>(
  context: context,
  builder: (context) => SimpleDialog(
    title: const Text('移动到分组'),
    children: [
      for (final group in ['', ...c.paletteGroups])
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context, group),
          child: Text(
            '${group == current ? '✓ ' : ''}${group.isEmpty ? '未分组' : group}',
          ),
        ),
    ],
  ),
);

class _GroupedPalette extends StatelessWidget {
  const _GroupedPalette({required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context) {
    final c = controller, entries = c.visiblePalette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          key: const ValueKey('palette-search'),
          initialValue: c.paletteQuery,
          decoration: const InputDecoration(
            labelText: '搜索颜色名称或 HEX',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (v) => c.filterPalette(query: v),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 190,
              child: DropdownButton<String>(
                key: const ValueKey('palette-group'),
                isExpanded: true,
                value: c.selectedPaletteGroup == null
                    ? 'all'
                    : 'g:${c.selectedPaletteGroup}',
                items: [
                  const DropdownMenuItem(value: 'all', child: Text('全部分组')),
                  const DropdownMenuItem(value: 'g:', child: Text('未分组')),
                  for (final group in c.paletteGroups)
                    DropdownMenuItem(
                      value: 'g:$group',
                      child: Text(group, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) => c.filterPalette(
                  group: v == 'all' ? null : v?.substring(2),
                  setGroup: true,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: () async {
                final name = await _requestName(context, '新建分组', '');
                if (name != null && c.createPaletteGroup(name)) {
                  c.filterPalette(group: name.trim(), setGroup: true);
                }
              },
              icon: const Icon(Icons.create_new_folder_outlined, size: 16),
              label: const Text('新建分组'),
            ),
            if (c.selectedPaletteGroup?.isNotEmpty == true) ...[
              IconButton(
                tooltip: '重命名分组',
                onPressed: () async {
                  final name = await _requestName(
                    context,
                    '重命名分组',
                    c.selectedPaletteGroup!,
                  );
                  if (name != null) {
                    c.renamePaletteGroup(c.selectedPaletteGroup!, name);
                  }
                },
                icon: const Icon(Icons.edit_outlined, size: 18),
              ),
              IconButton(
                tooltip: '解散分组并保留颜色',
                onPressed: () =>
                    c.dissolvePaletteGroup(c.selectedPaletteGroup!),
                icon: const Icon(Icons.folder_off_outlined, size: 18),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        Text(
          '${entries.length} 色 · 长按拖动排序，或使用色卡菜单；搜索时暂停排序。导出和批量复制使用当前筛选结果。',
          style: const TextStyle(color: _muted, fontSize: 11),
        ),
        const SizedBox(height: 12),
        if (entries.isEmpty)
          const _Empty(
            icon: Icons.palette_outlined,
            title: '暂无匹配颜色',
            description: '调整筛选，或把最近颜色保存到当前分组。',
          )
        else
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final entry in entries)
                DragTarget<RgbColor>(
                  onWillAcceptWithDetails: (d) =>
                      d.data != entry.color && c.paletteQuery.trim().isEmpty,
                  onAcceptWithDetails: (d) =>
                      c.reorderPalette(d.data, entry.color),
                  builder: (context, candidates, rejected) => DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: candidates.isEmpty
                            ? Colors.transparent
                            : _accent,
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: LongPressDraggable<RgbColor>(
                      data: entry.color,
                      maxSimultaneousDrags: c.paletteQuery.trim().isEmpty
                          ? 1
                          : 0,
                      feedback: Material(
                        color: Colors.transparent,
                        child: SizedBox(
                          width: 142,
                          child: _ColorTile(
                            controller: c,
                            color: entry.color,
                            saved: true,
                          ),
                        ),
                      ),
                      childWhenDragging: Opacity(
                        opacity: .35,
                        child: _ColorTile(
                          controller: c,
                          color: entry.color,
                          saved: true,
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _ColorTile(
                            controller: c,
                            color: entry.color,
                            saved: true,
                          ),
                          SizedBox(
                            width: 142,
                            child: Text(
                              entry.group.isEmpty ? '未分组' : entry.group,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _muted,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

class _ImageWorkspace extends StatefulWidget {
  const _ImageWorkspace({required this.controller});
  final AppController controller;
  @override
  State<_ImageWorkspace> createState() => _ImageWorkspaceState();
}

class _ImageWorkspaceState extends State<_ImageWorkspace> {
  final transform = TransformationController();
  final focus = FocusNode();
  bool pan = false;
  bool applyingView = false;
  @override
  void initState() {
    super.initState();
    transform.addListener(storeView);
  }

  void storeView() {
    if (applyingView || fitted != c.imageDocument || c.imageDocument == null) {
      return;
    }
    final matrix = transform.value;
    c.updateImageView(
      ImageProjectView(
        scale: matrix.getMaxScaleOnAxis(),
        x: matrix.entry(0, 3),
        y: matrix.entry(1, 3),
        pan: pan,
      ),
    );
  }

  void restoreView() {
    final view = c.imageView;
    applyingView = true;
    setState(() => pan = view?.pan ?? false);
    if (view == null) {
      fit();
    } else {
      transform.value = Matrix4.identity()
        ..translateByDouble(view.x, view.y, 0, 1)
        ..scaleByDouble(view.scale, view.scale, 1, 1);
    }
    applyingView = false;
    if (view == null) storeView();
  }

  Object? fitted;
  Size viewport = Size.zero;
  ({int id, Offset start, String handle})? dragging;
  AppController get c => widget.controller;
  @override
  void dispose() {
    transform.dispose();
    focus.dispose();
    super.dispose();
  }

  void fit() {
    final doc = c.imageDocument;
    if (doc == null || viewport.isEmpty) return;
    final scale = math
        .min(
          viewport.width / doc.frame.width,
          viewport.height / doc.frame.height,
        )
        .clamp(.01, 1.0);
    transform.value = Matrix4.identity()
      ..translateByDouble(
        (viewport.width - doc.frame.width * scale) / 2,
        (viewport.height - doc.frame.height * scale) / 2,
        0,
        1,
      )
      ..scaleByDouble(scale, scale, 1, 1);
  }

  void zoom(double factor) {
    final next = (transform.value.getMaxScaleOnAxis() * factor).clamp(
      .01,
      32.0,
    );
    final ratio = next / transform.value.getMaxScaleOnAxis();
    transform.value = Matrix4.copy(transform.value)
      ..scaleByDouble(ratio, ratio, 1, 1);
  }

  Rect pinRect(Map pin) {
    final r = pin['rect'] as Map;
    return Rect.fromLTRB(
      (r['left'] as num).toDouble(),
      (r['top'] as num).toDouble(),
      (r['right'] as num).toDouble(),
      (r['bottom'] as num).toDouble(),
    );
  }

  void pointer(PointerEvent event, String phase) {
    if (pan || !c.imageSessionActive) return;
    final p = event.localPosition;
    final frame = c.imageDocument!.frame;
    if (phase == 'down') focus.requestFocus();
    if (c.imageOverlay['editingPins'] == true) {
      if (phase == 'down') {
        Map? selected;
        final pins = (c.imageOverlay['pinned'] as List? ?? []).cast<Map>();
        for (final pin in pins.reversed) {
          if (pin['id'] == c.imageOverlay['selectedPin']) selected = pin;
        }
        var handle = 'move';
        final hit = 6 / transform.value.getMaxScaleOnAxis();
        if (selected != null) {
          final r = pinRect(selected);
          final handles = {
            'nw': r.topLeft,
            'ne': r.topRight,
            'sw': r.bottomLeft,
            'se': r.bottomRight,
            'n': r.topCenter,
            's': r.bottomCenter,
            'w': r.centerLeft,
            'e': r.centerRight,
          };
          for (final h in handles.entries) {
            if ((p - h.value).distance <= hit) {
              handle = h.key;
              break;
            }
          }
        }
        Map? pin = handle != 'move' ? selected : null;
        for (final candidate in pins.reversed) {
          if (pin == null && pinRect(candidate).inflate(hit).contains(p)) {
            pin = candidate;
          }
        }
        c.imageEvent('selectPin', {'id': pin?['id']});
        if (pin != null) {
          dragging = (id: pin['id'] as int, start: p, handle: handle);
          c.imageEvent('pinDrag', {'id': dragging!.id, 'phase': 'start'});
        }
      } else if (dragging != null && (phase == 'drag' || phase == 'up')) {
        final d = dragging!;
        c.imageEvent('pinDrag', {
          'id': d.id,
          'phase': phase == 'up' ? 'end' : 'update',
          'handle': d.handle,
          'dx': p.dx - d.start.dx,
          'dy': p.dy - d.start.dy,
        });
        if (phase == 'up') dragging = null;
      }
      return;
    }
    if (phase == 'down' &&
        (p.dx < 0 || p.dy < 0 || p.dx >= frame.width || p.dy >= frame.height)) {
      return;
    }
    c.imageEvent('pointer', {
      'x': p.dx,
      'y': p.dy,
      'phase': phase,
      'keep': true,
    });
  }

  KeyEventResult key(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final k = event.logicalKey;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final meta =
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed;
    if (k == LogicalKeyboardKey.keyS && meta) {
      c.saveImageProject();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.keyZ && meta) {
      c.imageEvent(shift ? 'redoPins' : 'undoPins');
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.delete || k == LogicalKeyboardKey.backspace) {
      c.imageEvent('deletePin');
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.escape) {
      if (pan) {
        setState(() => pan = false);
        storeView();
      }
      c.imageEvent('selectPin', {'id': null});
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.enter) {
      c.imageEvent('confirm', {'keep': true});
      return KeyEventResult.handled;
    }
    final delta = {
      LogicalKeyboardKey.arrowLeft: const Offset(-1, 0),
      LogicalKeyboardKey.arrowRight: const Offset(1, 0),
      LogicalKeyboardKey.arrowUp: const Offset(0, -1),
      LogicalKeyboardKey.arrowDown: const Offset(0, 1),
    }[k];
    if (delta != null) {
      c.imageEvent('nudge', {
        'dx': delta.dx.toInt(),
        'dy': delta.dy.toInt(),
        'resize': shift,
      });
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final doc = c.imageDocument, overlay = c.imageOverlay;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PageHeading(
          index: '03 / IMAGE WORKSPACE',
          title: '从原图捕捉细节',
          description: '拖入 PNG、JPEG、WebP，或打开本地图片。透明部分铺白底，不需要录屏权限。',
          action: FilledButton.icon(
            onPressed: c.busy || c.imageLoading ? null : c.openImage,
            icon: const Icon(Icons.folder_open, size: 18),
            label: Text(c.imageLoading ? '正在解码…' : '打开图片'),
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: c.busy || c.imageLoading || c.imageSaving
                  ? null
                  : c.openImageProject,
              icon: const Icon(Icons.folder_open, size: 16),
              label: const Text('打开项目'),
            ),
            OutlinedButton.icon(
              onPressed:
                  doc == null || c.busy || c.imageSaving || c.imageLoading
                  ? null
                  : c.saveImageProject,
              icon: const Icon(Icons.save_outlined, size: 16),
              label: Text(c.imageSaving ? '正在保存…' : '保存项目'),
            ),
            if (doc != null)
              Text(
                c.imageProjectDirty ? '● 有未保存修改' : '已保存',
                style: const TextStyle(color: _muted, fontSize: 11),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (doc == null)
          const _Empty(
            icon: Icons.image_outlined,
            title: '把图片拖到 fruler 窗口',
            description: '按原始像素取色和测量；支持缩放、平移，以及标注编辑与 PNG 导出。',
          )
        else ...[
          Text(
            '${doc.name} · ${doc.frame.width} × ${doc.frame.height} px',
            style: const TextStyle(fontFamily: 'Menlo', fontSize: 12),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final tool in [
                'picker',
                ...RulerMode.values.map((m) => m.name),
              ])
                ChoiceChip(
                  label: Text(
                    tool == 'picker'
                        ? '取色'
                        : _modeLabels[RulerMode.values.byName(tool)]!,
                  ),
                  selected: !pan && c.imageTool == tool,
                  onSelected: c.busy
                      ? null
                      : (_) {
                          c.useImageTool(tool);
                          setState(() => pan = false);
                          storeView();
                          focus.requestFocus();
                        },
                ),
              ChoiceChip(
                label: const Text('平移'),
                selected: pan,
                onSelected: (v) {
                  setState(() => pan = v);
                  storeView();
                },
              ),
              IconButton(
                tooltip: '缩小',
                onPressed: () => zoom(.8),
                icon: const Icon(Icons.remove),
              ),
              IconButton(
                tooltip: '放大',
                onPressed: () => zoom(1.25),
                icon: const Icon(Icons.add),
              ),
              TextButton(onPressed: fit, child: const Text('适应窗口')),
              TextButton(
                onPressed: () {
                  transform.value = Matrix4.identity();
                },
                child: const Text('100%'),
              ),
              TextButton(
                onPressed: c.busy ? null : c.closeImage,
                child: const Text('关闭图片'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 440,
            child: LayoutBuilder(
              builder: (context, constraints) {
                viewport = constraints.biggest;
                if (fitted != doc) {
                  fitted = doc;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) restoreView();
                  });
                }
                return Focus(
                  focusNode: focus,
                  onKeyEvent: key,
                  child: ClipRect(
                    child: ColoredBox(
                      color: const Color(0xFF080A0C),
                      child: InteractiveViewer(
                        transformationController: transform,
                        constrained: false,
                        minScale: .01,
                        maxScale: 32,
                        panEnabled: pan,
                        scaleEnabled: true,
                        boundaryMargin: const EdgeInsets.all(double.infinity),
                        child: Listener(
                          key: const ValueKey('image-canvas'),
                          onPointerHover: (e) => pointer(e, 'move'),
                          onPointerDown: (e) => pointer(e, 'down'),
                          onPointerMove: (e) => pointer(e, 'drag'),
                          onPointerUp: (e) => pointer(e, 'up'),
                          onPointerCancel: (e) {
                            final d = dragging;
                            if (d != null) {
                              c.imageEvent('pinDrag', {
                                'id': d.id,
                                'phase': 'end',
                                'handle': d.handle,
                                'dx': 0,
                                'dy': 0,
                              });
                            }
                            dragging = null;
                          },
                          child: MouseRegion(
                            cursor: pan
                                ? SystemMouseCursors.grab
                                : SystemMouseCursors.precise,
                            child: SizedBox(
                              width: doc.frame.width.toDouble(),
                              height: doc.frame.height.toDouble(),
                              child: Stack(
                                children: [
                                  Positioned.fill(
                                    child: Image.memory(
                                      doc.png,
                                      fit: BoxFit.fill,
                                      filterQuality: FilterQuality.none,
                                      gaplessPlayback: true,
                                    ),
                                  ),
                                  Positioned.fill(
                                    child: ValueListenableBuilder<Matrix4>(
                                      valueListenable: transform,
                                      builder: (_, matrix, child) =>
                                          CustomPaint(
                                            painter: _ImageOverlayPainter(
                                              overlay,
                                              matrix.getMaxScaleOnAxis(),
                                            ),
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder<Matrix4>(
            valueListenable: transform,
            builder: (_, matrix, child) => Text(
              '${(matrix.getMaxScaleOnAxis() * 100).toStringAsFixed(0)}% · 原图坐标 ${(overlay['x'] as num?)?.toStringAsFixed(1) ?? '—'}, ${(overlay['y'] as num?)?.toStringAsFixed(1) ?? '—'} · ${overlay['label'] ?? ''}',
              style: const TextStyle(fontFamily: 'Menlo', fontSize: 11),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              TextButton(
                onPressed: () => c.imageEvent('editPins'),
                child: Text(overlay['editingPins'] == true ? '返回绘制' : '编辑标注'),
              ),
              TextButton(
                onPressed: overlay['canUndoPins'] == true
                    ? () => c.imageEvent('undoPins')
                    : null,
                child: const Text('撤销'),
              ),
              TextButton(
                onPressed: overlay['canRedoPins'] == true
                    ? () => c.imageEvent('redoPins')
                    : null,
                child: const Text('重做'),
              ),
              TextButton(
                onPressed: (overlay['pinned'] as List? ?? []).isEmpty
                    ? null
                    : () => c.imageEvent('clearPins'),
                child: const Text('清空标注'),
              ),
              TextButton(
                onPressed: overlay['selectedPin'] != null
                    ? () => c.imageEvent('deletePin')
                    : null,
                child: const Text('删除选中'),
              ),
              TextButton(
                onPressed: (overlay['pinned'] as List? ?? []).isEmpty
                    ? null
                    : () => c.imageEvent('exportPins', {'save': false}),
                child: const Text('复制标注图'),
              ),
              TextButton(
                onPressed: (overlay['pinned'] as List? ?? []).isEmpty
                    ? null
                    : () => c.imageEvent('exportPins', {'save': true}),
                child: const Text('导出标注 PNG'),
              ),
              TextButton(
                onPressed: () =>
                    c.setContrastColor(c.selectedColor, foreground: true),
                child: const Text('当前色设为前景'),
              ),
              TextButton(
                onPressed: () =>
                    c.setContrastColor(c.selectedColor, foreground: false),
                child: const Text('当前色设为背景'),
              ),
            ],
          ),
          Text(
            '对比度 ${c.contrast.ratio.toStringAsFixed(2)} : 1 · 普通 AA ${c.contrast.normalAA ? '通过' : '未通过'} · 普通 AAA ${c.contrast.normalAAA ? '通过' : '未通过'}',
          ),
          const SizedBox(height: 8),
          const _Hint(
            icon: Icons.info_outline,
            text: '取色可连续点击；矩形拖拽后自动保留。滚轮/触控板缩放，选择平移后拖动；方向键逐像素移动，Enter 确认，编辑时 Shift + 方向键调尺寸。使用保存项目保留图片、标注和视图；⌘Z 撤销，⌘⇧Z 重做。切换屏幕工具会保留当前图片草稿，关闭或替换前会提示未保存修改。',
          ),
        ],
      ],
    );
  }
}

class _ImageOverlayPainter extends CustomPainter {
  _ImageOverlayPainter(this.data, this.scale);
  final Map<String, Object?> data;
  final double scale;
  Rect rect(Map r) => Rect.fromLTRB(
    (r['left'] as num).toDouble(),
    (r['top'] as num).toDouble(),
    (r['right'] as num).toDouble(),
    (r['bottom'] as num).toDouble(),
  );
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 / scale;
    for (final pin in (data['pinned'] as List? ?? []).cast<Map>()) {
      final r = rect(pin['rect'] as Map);
      canvas.drawRect(r, paint);
      final text = TextPainter(
        text: TextSpan(
          text: '${pin['id']} · ${pin['label']}',
          style: TextStyle(
            color: _accent,
            fontSize: 11 / scale,
            backgroundColor: Colors.black87,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      text.paint(canvas, Offset(r.left, math.max(0, r.top - text.height)));
      text.dispose();
      if (pin['id'] == data['selectedPin']) {
        for (final p in [
          r.topLeft,
          r.topRight,
          r.bottomLeft,
          r.bottomRight,
          r.topCenter,
          r.bottomCenter,
          r.centerLeft,
          r.centerRight,
        ]) {
          canvas.drawRect(
            Rect.fromCenter(center: p, width: 6 / scale, height: 6 / scale),
            Paint()..color = _accent,
          );
        }
      }
    }
    if (data['editingPins'] != true && data['rect'] is Map) {
      canvas.drawRect(rect(data['rect'] as Map), paint);
    }
    if (data['editingPins'] != true && data['x'] is num && data['y'] is num) {
      final x = (data['x'] as num).toDouble(),
          y = (data['y'] as num).toDouble();
      canvas.drawLine(
        Offset(x - 6 / scale, y),
        Offset(x + 6 / scale, y),
        paint,
      );
      canvas.drawLine(
        Offset(x, y - 6 / scale),
        Offset(x, y + 6 / scale),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_ImageOverlayPainter old) =>
      old.data != data || old.scale != scale;
}
