part of 'fruler_app.dart';

Color _rgbPaint(RgbColor c) => Color.fromARGB(255, c.r, c.g, c.b);

Future<String?> _requestName(
  BuildContext context,
  String title,
  String initial,
) {
  var name = initial;
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 320,
        child: TextFormField(
          initialValue: initial,
          autofocus: true,
          maxLength: 60,
          decoration: const InputDecoration(labelText: '名称'),
          onChanged: (v) => name = v,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, name),
          child: const Text('保存名称'),
        ),
      ],
    ),
  );
}

class _ContrastPanel extends StatelessWidget {
  const _ContrastPanel({required this.controller});
  final AppController controller;
  Future<void> _edit(BuildContext context, bool foreground) async {
    final color = await showDialog<RgbColor>(
      context: context,
      builder: (_) => _ColorEditorDialog(
        initial: foreground
            ? controller.contrastForeground
            : controller.contrastBackground,
      ),
    );
    if (color != null) {
      controller.setContrastColor(color, foreground: foreground);
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = controller.contrast;
    Widget badge(String title, bool pass) => Chip(
      label: Text('$title · ${pass ? '通过' : '未通过'}'),
      avatar: Icon(
        pass ? Icons.check_circle_outline : Icons.cancel_outlined,
        size: 16,
        color: pass ? _accent : Colors.orangeAccent,
      ),
    );
    Widget colorInput(bool foreground) {
      final color = foreground ? result.foreground : result.background;
      final label = foreground ? '前景色' : '背景色';
      return Wrap(
        spacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          OutlinedButton.icon(
            onPressed: () => _edit(context, foreground),
            icon: Container(width: 16, height: 16, color: _rgbPaint(color)),
            label: Text('$label ${color.hex}'),
          ),
          IconButton(
            tooltip: '从屏幕选取$label',
            onPressed: controller.busy
                ? null
                : () => controller.pickContrast(foreground: foreground),
            icon: const Icon(Icons.colorize, size: 18),
          ),
          TextButton(
            onPressed: () => controller.setContrastColor(
              controller.selectedColor,
              foreground: foreground,
            ),
            child: const Text('使用当前颜色'),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(title: '颜色对比度', subtitle: 'WCAG 2.x · sRGB'),
        const SizedBox(height: 12),
        colorInput(true),
        colorInput(false),
        Wrap(
          spacing: 8,
          children: [
            TextButton.icon(
              onPressed: controller.swapContrast,
              icon: const Icon(Icons.swap_vert),
              label: const Text('交换前景与背景'),
            ),
            OutlinedButton.icon(
              onPressed: controller.busy
                  ? null
                  : () => controller.pickContrast(foreground: true, pair: true),
              icon: const Icon(Icons.colorize),
              label: const Text('依次取两色'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          color: _rgbPaint(result.background),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Aa 文字预览',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: _rgbPaint(result.foreground),
                ),
              ),
              Text(
                '普通文字与背景的可读性',
                style: TextStyle(
                  fontSize: 14,
                  color: _rgbPaint(result.foreground),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '${result.ratio.toStringAsFixed(2)} : 1',
          key: const ValueKey('contrast-ratio'),
          style: const TextStyle(fontFamily: 'Menlo', fontSize: 24),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            badge('普通 AA', result.normalAA),
            badge('普通 AAA', result.normalAAA),
            badge('大号 AA', result.largeAA),
            badge('大号 AAA', result.largeAAA),
          ],
        ),
        const Text(
          '普通文字：AA ≥ 4.5，AAA ≥ 7；大号文字：AA ≥ 3，AAA ≥ 4.5。大号指至少 18pt，或粗体 14pt。按未舍入比值判断；只检查当前两种不透明颜色。',
          style: TextStyle(color: _muted, fontSize: 11),
        ),
      ],
    );
  }
}

class _PaletteTools extends StatelessWidget {
  const _PaletteTools({required this.controller});
  final AppController controller;
  Future<void> _import(BuildContext context) async {
    final entries = await controller.readPaletteImport();
    if (entries == null || !context.mounted) return;
    var policy = PaletteMerge.keepExisting;
    final conflicts = entries
        .where((e) => controller.paletteEntry(e.color) != null)
        .length;
    final duplicateNames = entries
        .where(
          (e) =>
              e.name.isNotEmpty &&
              controller.palette.any(
                (p) => p.name == e.name && p.color != e.color,
              ),
        )
        .length;
    final accepted = await showDialog<PaletteMerge>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('预览调色板导入'),
          content: SizedBox(
            width: 540,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${entries.length} 色 · $conflicts 个已有颜色 · $duplicateNames 个与现有调色板同名的不同颜色',
                ),
                const Text(
                  '按 RGB 去重；不同颜色的同名条目均保留。已有颜色的名称和收藏按以下规则合并。',
                  style: TextStyle(color: _muted, fontSize: 11),
                ),
                const SizedBox(height: 12),
                DropdownButton<PaletteMerge>(
                  value: policy,
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(
                      value: PaletteMerge.keepExisting,
                      child: Text('相同颜色：保留已有名称和收藏'),
                    ),
                    DropdownMenuItem(
                      value: PaletteMerge.useImported,
                      child: Text('相同颜色：使用导入的名称和收藏'),
                    ),
                  ],
                  onChanged: (v) => setState(() => policy = v!),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 200,
                  child: ListView(
                    children: [
                      for (final entry in entries)
                        ListTile(
                          dense: true,
                          leading: Container(
                            width: 20,
                            height: 20,
                            color: _rgbPaint(entry.color),
                          ),
                          title: Text(
                            '${entry.name.isEmpty ? '未命名' : entry.name} · ${entry.color.hex}',
                          ),
                          subtitle: controller.paletteEntry(entry.color) == null
                              ? null
                              : Text(
                                  '已有：${controller.paletteEntry(entry.color)!.name} · ${controller.paletteEntry(entry.color)!.favorite ? '已收藏' : '未收藏'}；导入：${entry.favorite ? '已收藏' : '未收藏'}',
                                ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: entries.isEmpty
                  ? null
                  : () => Navigator.pop(context, policy),
              child: const Text('合并导入'),
            ),
          ],
        ),
      ),
    );
    if (accepted != null) controller.applyPaletteImport(entries, accepted);
  }

  Future<void> _batch(BuildContext context) async {
    final selected = <RgbColor>{};
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('批量复制 · 已选 ${selected.length} 色'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    TextButton(
                      onPressed: () => setState(
                        () => selected.addAll(
                          controller.palette.map((e) => e.color),
                        ),
                      ),
                      child: const Text('全选'),
                    ),
                    TextButton(
                      onPressed: () => setState(selected.clear),
                      child: const Text('取消全选'),
                    ),
                  ],
                ),
                SizedBox(
                  height: 240,
                  child: ListView(
                    children: [
                      for (final entry in controller.palette)
                        CheckboxListTile(
                          value: selected.contains(entry.color),
                          title: Text(
                            '${entry.name} ${entry.color.hex}'.trim(),
                          ),
                          controlAffinity: ListTileControlAffinity.leading,
                          onChanged: (v) => setState(() {
                            if (v == true) {
                              selected.add(entry.color);
                            } else {
                              selected.remove(entry.color);
                            }
                          }),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
            for (final flutter in [false, true])
              FilledButton(
                onPressed: selected.isEmpty
                    ? null
                    : () async {
                        await controller.copyPaletteSelection(
                          selected,
                          flutter: flutter,
                        );
                        if (context.mounted) Navigator.pop(context);
                      },
                child: Text(flutter ? '复制 Flutter' : '复制 CSS'),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 10,
    runSpacing: 8,
    children: [
      OutlinedButton.icon(
        onPressed: () => _import(context),
        icon: const Icon(Icons.file_open_outlined, size: 16),
        label: const Text('导入 JSON'),
      ),
      OutlinedButton.icon(
        onPressed: controller.palette.isEmpty ? null : () => _batch(context),
        icon: const Icon(Icons.copy_all_outlined, size: 16),
        label: const Text('批量复制'),
      ),
    ],
  );
}

class _MeasurementHistory extends StatefulWidget {
  const _MeasurementHistory({required this.controller});
  final AppController controller;
  @override
  State<_MeasurementHistory> createState() => _MeasurementHistoryState();
}

class _MeasurementHistoryState extends State<_MeasurementHistory> {
  String query = '';
  bool favorites = false;
  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final records = c.filterMeasurements(query, favoritesOnly: favorites);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
          title: '测量记录',
          subtitle: '${records.length} / ${c.measurements.length} · px / pt',
          onClear: c.measurements.isEmpty ? null : c.clearMeasurements,
        ),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('measurement-search'),
          decoration: const InputDecoration(
            labelText: '搜索名称、尺寸、显示器或日期',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (v) => setState(() => query = v),
        ),
        Wrap(
          spacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilterChip(
              label: const Text('只看收藏'),
              selected: favorites,
              onSelected: (v) => setState(() => favorites = v),
            ),
            for (final csv in [true, false])
              TextButton(
                onPressed: records.isEmpty
                    ? null
                    : () => c.exportMeasurements(records, csv: csv),
                child: Text('导出当前结果 ${csv ? 'CSV' : 'JSON'}'),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (records.isEmpty)
          const _Empty(
            icon: Icons.square_foot_rounded,
            title: '暂无匹配记录',
            description: '测量后会保留像素、逻辑尺寸及显示器缩放；收藏可长期保留。',
          )
        else
          for (final r in records)
            Card(
              color: _panel,
              child: ListTile(
                onTap: () => c.copyMeasurement(r),
                leading: IconButton(
                  tooltip: r.favorite ? '取消收藏测量' : '收藏测量',
                  icon: Icon(
                    r.favorite ? Icons.star : Icons.star_border,
                    color: _accent,
                  ),
                  onPressed: () =>
                      c.updateMeasurement(r, favorite: !r.favorite),
                ),
                title: Text(
                  '${r.name.isEmpty ? '' : '${r.name} · '}${r.measurement.pixelLabel}',
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${r.measurement.pointLabel} · ${_modeLabels[r.measurement.mode]} · ${r.displayName}\n缩放 ${r.scaleX.toStringAsFixed(2)} × ${r.scaleY.toStringAsFixed(2)} · ${r.createdAt.toLocal().toString().split('.').first}',
                  style: const TextStyle(fontSize: 11, color: _muted),
                ),
                isThreeLine: true,
                trailing: PopupMenuButton<String>(
                  tooltip: '测量记录操作',
                  onSelected: (action) async {
                    if (action == 'delete') {
                      c.removeMeasurement(r);
                    } else if (action == 'copy') {
                      await c.copyMeasurement(r);
                    } else {
                      final name = await _requestName(context, '命名测量', r.name);
                      if (name != null) c.updateMeasurement(r, name: name);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'copy', child: Text('复制尺寸')),
                    PopupMenuItem(value: 'name', child: Text('命名测量')),
                    PopupMenuItem(value: 'delete', child: Text('删除记录')),
                  ],
                ),
              ),
            ),
      ],
    );
  }
}
