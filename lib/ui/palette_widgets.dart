part of 'fruler_app.dart';

Future<void> _editColor(
  BuildContext context,
  AppController controller,
  RgbColor color,
) async {
  final result = await showDialog<RgbColor>(
    context: context,
    builder: (_) => _ColorEditorDialog(initial: color),
  );
  if (result != null) controller.addEditedColor(result);
}

class _ColorEditorDialog extends StatefulWidget {
  const _ColorEditorDialog({required this.initial});
  final RgbColor initial;
  @override
  State<_ColorEditorDialog> createState() => _ColorEditorDialogState();
}

class _ColorEditorDialogState extends State<_ColorEditorDialog> {
  late RgbColor color = widget.initial;
  late final TextEditingController hex = TextEditingController(text: color.hex);
  late var hsl = color.hslValues;
  bool useHsl = false;
  bool valid = true;
  @override
  void dispose() {
    hex.dispose();
    super.dispose();
  }

  void _change(RgbColor value, {bool updateHsl = true}) {
    setState(() {
      color = value;
      if (updateHsl) hsl = value.hslValues;
      hex.text = value.hex;
      valid = true;
    });
  }

  Widget _slider(
    String label,
    double value,
    double max,
    ValueChanged<double> onChanged,
  ) => Row(
    children: [
      SizedBox(width: 26, child: Text(label)),
      Expanded(
        child: Slider(
          value: value.clamp(0, max),
          min: 0,
          max: max,
          divisions: max.toInt(),
          semanticFormatterCallback: (v) => v.round().toString(),
          onChanged: onChanged,
        ),
      ),
      SizedBox(
        width: 38,
        child: Text('${value.round()}', textAlign: TextAlign.end),
      ),
    ],
  );
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('编辑颜色'),
    content: SizedBox(
      width: 460,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 72,
              decoration: BoxDecoration(
                color: Color.fromARGB(255, color.r, color.g, color.b),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(height: 18),
            TextField(
              key: const ValueKey('hex-editor'),
              controller: hex,
              maxLength: 7,
              decoration: InputDecoration(
                labelText: 'HEX',
                hintText: '#D7FA6B',
                errorText: valid ? null : '请输入 3 位或 6 位 HEX',
              ),
              onChanged: (text) {
                try {
                  final value = RgbColor.parseHex(text);
                  setState(() {
                    color = value;
                    hsl = value.hslValues;
                    valid = true;
                  });
                } catch (_) {
                  setState(() => valid = false);
                }
              },
            ),
            const SizedBox(height: 12),
            SegmentedButton<bool>(
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor: _accent,
                selectedForegroundColor: const Color(0xFF182008),
              ),
              segments: const [
                ButtonSegment(value: false, label: Text('RGB')),
                ButtonSegment(value: true, label: Text('HSL')),
              ],
              selected: {useHsl},
              onSelectionChanged: (v) => setState(() => useHsl = v.single),
            ),
            const SizedBox(height: 12),
            if (!useHsl) ...[
              _slider(
                'R',
                color.r.toDouble(),
                255,
                (v) => _change(RgbColor(v.round(), color.g, color.b)),
              ),
              _slider(
                'G',
                color.g.toDouble(),
                255,
                (v) => _change(RgbColor(color.r, v.round(), color.b)),
              ),
              _slider(
                'B',
                color.b.toDouble(),
                255,
                (v) => _change(RgbColor(color.r, color.g, v.round())),
              ),
            ] else ...[
              _slider('H', hsl.h, 360, (v) {
                hsl = (h: v, s: hsl.s, l: hsl.l);
                _change(
                  RgbColor.fromHsl(hsl.h, hsl.s, hsl.l),
                  updateHsl: false,
                );
              }),
              _slider('S', hsl.s * 100, 100, (v) {
                hsl = (h: hsl.h, s: v / 100, l: hsl.l);
                _change(
                  RgbColor.fromHsl(hsl.h, hsl.s, hsl.l),
                  updateHsl: false,
                );
              }),
              _slider('L', hsl.l * 100, 100, (v) {
                hsl = (h: hsl.h, s: hsl.s, l: v / 100);
                _change(
                  RgbColor.fromHsl(hsl.h, hsl.s, hsl.l),
                  updateHsl: false,
                );
              }),
            ],
            Text(
              '${color.rgb}\n${color.hsl}',
              style: const TextStyle(color: _muted, fontSize: 12),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: valid ? () => Navigator.pop(context, color) : null,
        child: const Text('保存颜色'),
      ),
    ],
  );
}

class _ColorGrid extends StatelessWidget {
  const _ColorGrid({required this.controller, required this.saved});
  final AppController controller;
  final bool saved;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 10,
    runSpacing: 10,
    children: [
      for (final color
          in saved ? controller.palette.map((e) => e.color) : controller.colors)
        _ColorTile(controller: controller, color: color, saved: saved),
    ],
  );
}

class _ColorTile extends StatelessWidget {
  const _ColorTile({
    required this.controller,
    required this.color,
    required this.saved,
  });
  final AppController controller;
  final RgbColor color;
  final bool saved;
  Future<void> _rename(BuildContext context) async {
    var name = controller.paletteEntry(color)?.name ?? '';
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('命名颜色'),
        content: SizedBox(
          width: 320,
          child: TextFormField(
            initialValue: name,
            autofocus: true,
            maxLength: 60,
            decoration: const InputDecoration(labelText: '颜色名称'),
            onChanged: (v) => name = v,
            onFieldSubmitted: (v) => Navigator.pop(context, v),
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
    if (result != null) controller.savePaletteColor(color, name: result);
  }

  @override
  Widget build(BuildContext context) {
    final entry = controller.paletteEntry(color);
    return Container(
      width: 142,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: _line),
        color: _panel,
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => controller.copyColor(color),
            child: Container(
              height: 56,
              color: Color.fromARGB(255, color.r, color.g, color.b),
              child: Center(
                child: entry?.favorite == true
                    ? Icon(
                        Icons.star_rounded,
                        size: 19,
                        color:
                            Color.fromARGB(
                                  255,
                                  color.r,
                                  color.g,
                                  color.b,
                                ).computeLuminance() >
                                .4
                            ? Colors.black54
                            : Colors.white70,
                      )
                    : null,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 10),
            child: Row(
              children: [
                Expanded(
                  child: Tooltip(
                    message: entry?.name.isNotEmpty == true
                        ? '${entry!.name} · ${color.hex}'
                        : color.hex,
                    child: InkWell(
                      onTap: () => controller.copyColor(color),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (entry?.name.isNotEmpty == true)
                            Text(
                              entry!.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11),
                            ),
                          Text(
                            color.hex,
                            style: const TextStyle(
                              fontFamily: 'Menlo',
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: '颜色操作 ${color.hex}',
                  iconSize: 16,
                  onSelected: (action) async {
                    switch (action) {
                      case 'copy':
                        await controller.copyColor(color);
                      case 'edit':
                        if (context.mounted) {
                          await _editColor(context, controller, color);
                        }
                      case 'favorite':
                        controller.savePaletteColor(
                          color,
                          favorite: entry?.favorite != true,
                        );
                      case 'name':
                        await _rename(context);
                      case 'save':
                        controller.savePaletteColor(color);
                      case 'delete':
                        if (saved) {
                          controller.removePaletteColor(color);
                        } else {
                          controller.removeRecentColor(color);
                        }
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'copy', child: Text('复制颜色')),
                    const PopupMenuItem(value: 'edit', child: Text('编辑颜色')),
                    PopupMenuItem(
                      value: 'favorite',
                      child: Text(entry?.favorite == true ? '取消收藏' : '收藏颜色'),
                    ),
                    const PopupMenuItem(value: 'name', child: Text('命名颜色')),
                    if (!saved && entry == null)
                      const PopupMenuItem(value: 'save', child: Text('保存到调色板')),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text(saved ? '从调色板删除' : '从最近记录删除'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ExportColors extends StatelessWidget {
  const _ExportColors({required this.controller, required this.saved});
  final AppController controller;
  final bool saved;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final format in PaletteExport.values)
        TextButton.icon(
          onPressed:
              (saved ? controller.palette.isEmpty : controller.colors.isEmpty)
              ? null
              : () => controller.exportColors(format, saved: saved),
          icon: const Icon(Icons.file_download_outlined, size: 16),
          label: Text('导出 ${format.name.toUpperCase()}'),
        ),
    ],
  );
}
