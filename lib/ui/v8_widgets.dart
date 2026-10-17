part of 'fruler_app.dart';

class _PickedColorEditorHost extends StatefulWidget {
  const _PickedColorEditorHost({required this.controller, required this.child});
  final AppController controller;
  final Widget child;
  @override
  State<_PickedColorEditorHost> createState() => _PickedColorEditorHostState();
}

class _PickedColorEditorHostState extends State<_PickedColorEditorHost> {
  bool showing = false;
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(check);
    check();
  }

  @override
  void didUpdateWidget(_PickedColorEditorHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(check);
      widget.controller.addListener(check);
    }
    check();
  }

  void check() {
    if (showing || widget.controller.pendingPickedEditorColor == null) return;
    showing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final c = widget.controller;
      final color = c.takePickedEditorColor();
      if (color != null) {
        final result = await showDialog<Object>(
          context: context,
          builder: (_) =>
              _ColorEditorDialog(initial: color, allowPickNew: true),
        );
        c.finishPickedEditor();
        if (!mounted) return;
        if (result is RgbColor) c.addEditedColor(result);
        if (result == 'pickNew') await c.pickNewColor();
      }
      showing = false;
      if (mounted) check();
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(check);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

Future<void> _manageColorOutputs(
  BuildContext context,
  AppController c,
) => showDialog<void>(
  context: context,
  builder: (context) => StatefulBuilder(
    builder: (context, refresh) => AlertDialog(
      title: const Text('颜色输出格式'),
      content: SizedBox(
        width: 620,
        height: 460,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '按列表顺序显示；启用的格式可用于自动复制。修改即时保存，至少保留一种启用格式。',
              style: TextStyle(color: _muted, fontSize: 12),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                children: [
                  for (var index = 0; index < c.colorOutputs.length; index++)
                    Builder(
                      builder: (context) {
                        final f = c.colorOutputs[index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Switch(
                                    value: f.enabled,
                                    onChanged: (v) {
                                      c.enableColorOutput(f.id, v);
                                      refresh(() {});
                                    },
                                  ),
                                  Expanded(
                                    child: Text(
                                      f.name,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: '上移 ${f.name}',
                                    onPressed: index == 0
                                        ? null
                                        : () {
                                            c.moveColorOutput(f.id, -1);
                                            refresh(() {});
                                          },
                                    icon: const Icon(
                                      Icons.arrow_upward,
                                      size: 18,
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: '下移 ${f.name}',
                                    onPressed:
                                        index == c.colorOutputs.length - 1
                                        ? null
                                        : () {
                                            c.moveColorOutput(f.id, 1);
                                            refresh(() {});
                                          },
                                    icon: const Icon(
                                      Icons.arrow_downward,
                                      size: 18,
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: '编辑 ${f.name}',
                                    onPressed: () async {
                                      await _editColorOutput(context, c, f);
                                      refresh(() {});
                                    },
                                    icon: const Icon(
                                      Icons.edit_outlined,
                                      size: 18,
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: '删除 ${f.name}',
                                    onPressed: () async {
                                      final remove = await showDialog<bool>(
                                        context: context,
                                        builder: (context) => AlertDialog(
                                          title: Text('删除格式“${f.name}”？'),
                                          content: const Text(
                                            '仅删除输出格式，不删除颜色记录。',
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(context, false),
                                              child: const Text('取消'),
                                            ),
                                            FilledButton(
                                              onPressed: () =>
                                                  Navigator.pop(context, true),
                                              child: const Text('删除格式'),
                                            ),
                                          ],
                                        ),
                                      );
                                      if (remove == true) {
                                        c.deleteColorOutput(f.id);
                                      }
                                      refresh(() {});
                                    },
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      size: 18,
                                    ),
                                  ),
                                ],
                              ),
                              Padding(
                                padding: const EdgeInsets.only(left: 12),
                                child: Text(
                                  f.render(c.selectedColor),
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontFamily: 'Menlo',
                                    fontSize: 11,
                                    color: _muted,
                                  ),
                                ),
                              ),
                              const Divider(),
                            ],
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
            if (c.error != null)
              Text(
                c.error!,
                style: const TextStyle(color: Colors.orange, fontSize: 12),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: c.colorOutputs.length >= 24
              ? null
              : () async {
                  await _editColorOutput(context, c, null);
                  refresh(() {});
                },
          child: const Text('添加格式'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('完成'),
        ),
      ],
    ),
  ),
);

Future<void> _editColorOutput(
  BuildContext context,
  AppController c,
  ColorOutput? output,
) => showDialog<void>(
  context: context,
  builder: (_) => _ColorOutputDialog(controller: c, output: output),
);

class _ColorOutputDialog extends StatefulWidget {
  const _ColorOutputDialog({required this.controller, this.output});
  final AppController controller;
  final ColorOutput? output;
  @override
  State<_ColorOutputDialog> createState() => _ColorOutputDialogState();
}

class _ColorOutputDialogState extends State<_ColorOutputDialog> {
  late final name = TextEditingController(text: widget.output?.name ?? '');
  late final template = TextEditingController(
    text: widget.output?.template ?? '#%ReX%GrX%BlX',
  );
  String? failure;
  @override
  void dispose() {
    name.dispose();
    template.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String? preview, problem;
    try {
      preview = ColorOutput(
        id: 'preview',
        name: name.text,
        template: template.text,
      ).render(widget.controller.selectedColor);
    } on FormatException catch (e) {
      problem = e.message;
    }
    return AlertDialog(
      title: Text(widget.output == null ? '添加颜色格式' : '编辑颜色格式'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const ValueKey('output-name'),
                controller: name,
                maxLength: 40,
                decoration: const InputDecoration(labelText: '格式名称'),
                onChanged: (_) => setState(() => failure = null),
              ),
              TextField(
                key: const ValueKey('output-template'),
                controller: template,
                maxLength: 1024,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(labelText: '输出模板'),
                onChanged: (_) => setState(() => failure = null),
              ),
              const SizedBox(height: 12),
              Text(
                problem ?? preview ?? '',
                key: const ValueKey('output-preview'),
                style: TextStyle(
                  fontFamily: 'Menlo',
                  fontSize: 12,
                  color: problem == null ? _accent : Colors.orange,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'RGB：%Re / %Gr / %Bl；Alpha：%Al（固定 255）\n后缀 b 为整数，x / X 为两位十六进制，h / H 为一位，f / F 为 0–1 小数。\nHSL：%Hu / %Sl / %Ll；HSV：%Hu / %Sb / %Va（或 %Br）。\n%Dr 为 RGB 整数，%Dv 为 BGR 整数；%% 输出百分号。大小写敏感。',
                style: TextStyle(color: _muted, fontSize: 11),
              ),
              if (failure != null)
                Text(
                  failure!,
                  style: const TextStyle(color: Colors.orange, fontSize: 12),
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
          onPressed: problem != null || name.text.trim().isEmpty
              ? null
              : () {
                  if (widget.controller.saveColorOutput(
                    id: widget.output?.id,
                    name: name.text,
                    template: template.text,
                  )) {
                    Navigator.pop(context);
                  } else {
                    setState(() => failure = widget.controller.error);
                  }
                },
          child: const Text('保存格式'),
        ),
      ],
    );
  }
}

Future<void> _configurePicker(BuildContext context, AppController c) =>
    showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: const Text('屏幕取色设置'),
          content: SizedBox(
            width: 540,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<PickerActivation>(
                    initialValue: c.pickerBehavior.activation,
                    decoration: const InputDecoration(labelText: '启动行为'),
                    items: const [
                      DropdownMenuItem(
                        value: PickerActivation.picker,
                        child: Text('先取色'),
                      ),
                      DropdownMenuItem(
                        value: PickerActivation.editor,
                        child: Text('直接打开颜色编辑器'),
                      ),
                    ],
                    onChanged: (v) {
                      if (v != null) {
                        c.setPickerBehavior(
                          c.pickerBehavior.copyWith(activation: v),
                        );
                      }
                      refresh(() {});
                    },
                  ),
                  for (final button in ['primary', 'middle', 'secondary'])
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: DropdownButtonFormField<PickerMouseAction>(
                        key: ValueKey('picker-$button'),
                        initialValue: c.pickerBehavior.forButton(button),
                        decoration: InputDecoration(
                          labelText: switch (button) {
                            'primary' => '左键 / Enter',
                            'middle' => '中键',
                            _ => '右键',
                          },
                        ),
                        items: PickerMouseAction.values
                            .map(
                              (v) => DropdownMenuItem(
                                value: v,
                                child: Text(v.label),
                              ),
                            )
                            .toList(),
                        onChanged: (v) {
                          if (v == null) return;
                          c.setPickerBehavior(switch (button) {
                            'primary' => c.pickerBehavior.copyWith(primary: v),
                            'middle' => c.pickerBehavior.copyWith(middle: v),
                            _ => c.pickerBehavior.copyWith(secondary: v),
                          });
                          refresh(() {});
                        },
                      ),
                    ),
                  const SizedBox(height: 16),
                  const Text(
                    '修改即时保存。Esc 始终取消屏幕取色；“连续取色”开关会切换左键动作。对比度取色保持左键 / Enter 确认、右键取消。图片取色保留当前工作区，使用左键连续采集。',
                    style: TextStyle(color: _muted, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('完成'),
            ),
          ],
        ),
      ),
    );
