part of 'fruler_app.dart';

class _ColorFormatSettings extends StatelessWidget {
  const _ColorFormatSettings({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) => _SettingsCard(
    title: context.l10n.uiColorFormats,
    icon: Icons.code,
    child: KeyedSubtree(
      key: const PageStorageKey('color-format-expansion'),
      child: ExpansionTile(
        key: const ValueKey('color-format-settings'),
        tilePadding: EdgeInsets.zero,
        title: Text(
          context.l10n.uiColorFormatsHint,
          style: const TextStyle(fontSize: 12, height: 1.6),
        ),
        children: [
          for (var index = 0; index < controller.colorOutputs.length; index++)
            _formatRow(context, controller.colorOutputs[index], index),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey('format-add'),
              onPressed: controller.colorOutputs.length >= 24
                  ? null
                  : () => _edit(context),
              icon: const Icon(Icons.add, size: 18),
              label: Text(context.l10n.uiAddColorFormat),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _formatRow(BuildContext context, ColorOutput format, int index) {
    final lastEnabled =
        format.enabled && controller.enabledColorOutputs.length == 1;
    return Row(
      children: [
        Checkbox(
          key: ValueKey('format-enabled-${format.id}'),
          semanticLabel: format.name,
          value: format.enabled,
          onChanged: lastEnabled
              ? null
              : (value) {
                  if (value != null) {
                    controller.enableColorOutput(format.id, value);
                  }
                },
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(format.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(
                  format.template,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: _muted),
                ),
              ],
            ),
          ),
        ),
        IconButton(
          key: ValueKey('format-edit-${format.id}'),
          tooltip: context.l10n.uiEdit,
          onPressed: () => _edit(context, format),
          icon: const Icon(Icons.edit_outlined, size: 18),
        ),
        PopupMenuButton<String>(
          key: ValueKey('format-actions-${format.id}'),
          tooltip: context.l10n.uiFormatActions,
          onSelected: (value) {
            switch (value) {
              case 'up':
                controller.moveColorOutput(format.id, -1);
              case 'down':
                controller.moveColorOutput(format.id, 1);
              case 'delete':
                controller.deleteColorOutput(format.id);
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'up',
              enabled: index > 0,
              child: Text(context.l10n.uiMoveUp),
            ),
            PopupMenuItem(
              value: 'down',
              enabled: index < controller.colorOutputs.length - 1,
              child: Text(context.l10n.uiMoveDown),
            ),
            PopupMenuItem(
              value: 'delete',
              enabled: !lastEnabled,
              child: Text(context.l10n.uiDeleteColorFormat),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _edit(BuildContext context, [ColorOutput? format]) =>
      showDialog<void>(
        context: context,
        builder: (_) =>
            _ColorFormatDialog(controller: controller, format: format),
      );
}

class _ColorFormatDialog extends StatefulWidget {
  const _ColorFormatDialog({required this.controller, this.format});
  final AppController controller;
  final ColorOutput? format;
  @override
  State<_ColorFormatDialog> createState() => _ColorFormatDialogState();
}

class _ColorFormatDialogState extends State<_ColorFormatDialog> {
  late String name = widget.format?.name ?? '';
  late String template = widget.format?.template ?? '#%ReX%GrX%BlX';
  bool saveFailed = false;

  @override
  Widget build(BuildContext context) {
    String? previewError;
    var preview = '';
    try {
      preview = ColorOutput(
        id: 'preview',
        name: 'preview',
        template: template,
      ).render(widget.controller.selectedColor);
    } on FormatException catch (error) {
      previewError = widget.controller.describeError(error);
    }
    return AlertDialog(
      title: Text(
        widget.format == null
            ? context.l10n.uiAddColorFormat
            : context.l10n.uiEditColorFormat,
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                key: const ValueKey('format-name'),
                initialValue: name,
                maxLength: 40,
                decoration: InputDecoration(labelText: context.l10n.uiName),
                onChanged: (value) => setState(() {
                  name = value;
                  saveFailed = false;
                }),
              ),
              TextFormField(
                key: const ValueKey('format-template'),
                initialValue: template,
                maxLength: 1024,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: context.l10n.uiFormatTemplate,
                  errorText: previewError,
                ),
                onChanged: (value) => setState(() {
                  template = value;
                  saveFailed = false;
                }),
              ),
              const SizedBox(height: 8),
              Text(
                context.l10n.uiFormatTemplateHint,
                style: const TextStyle(
                  color: _muted,
                  fontSize: 11,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 16),
              Text(context.l10n.uiFormatPreview),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 80),
                child: SingleChildScrollView(
                  child: Text(
                    preview,
                    key: const ValueKey('format-preview'),
                    style: const TextStyle(fontFamily: 'Menlo'),
                  ),
                ),
              ),
              if (saveFailed && widget.controller.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    widget.controller.error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.uiCancel),
        ),
        FilledButton(
          key: const ValueKey('format-save'),
          onPressed: name.trim().isEmpty || previewError != null
              ? null
              : () {
                  if (widget.controller.saveColorOutput(
                    id: widget.format?.id,
                    name: name,
                    template: template,
                  )) {
                    Navigator.pop(context);
                  } else {
                    setState(() => saveFailed = true);
                  }
                },
          child: Text(context.l10n.uiSave),
        ),
      ],
    );
  }
}
