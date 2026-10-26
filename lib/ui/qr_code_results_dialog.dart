part of 'fruler_app.dart';

class _QrCodeResultsDialog extends StatefulWidget {
  const _QrCodeResultsDialog({
    required this.results,
    required this.copying,
    required this.error,
    required this.onCopy,
    required this.onAdjust,
    required this.onClose,
  });

  final List<String> results;
  final bool copying;
  final String? error;
  final ValueChanged<String> onCopy;
  final VoidCallback onAdjust;
  final VoidCallback onClose;

  @override
  State<_QrCodeResultsDialog> createState() => _QrCodeResultsDialogState();
}

class _QrCodeResultsDialogState extends State<_QrCodeResultsDialog> {
  final contentScroll = ScrollController();
  final resultFocus = FocusNode();
  int selected = 0;

  @override
  void dispose() {
    contentScroll.dispose();
    resultFocus.dispose();
    super.dispose();
  }

  void select(int index) {
    if (widget.copying) return;
    if (index != selected) {
      if (contentScroll.hasClients) contentScroll.jumpTo(0);
      setState(() => selected = index);
    }
    resultFocus.requestFocus();
  }

  void copy() {
    if (!widget.copying) widget.onCopy(widget.results[selected]);
  }

  void close() {
    if (!widget.copying) widget.onClose();
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.enter): copy,
      const SingleActivator(LogicalKeyboardKey.escape): close,
    },
    child: Focus(
      focusNode: resultFocus,
      autofocus: true,
      child: Dialog(
        key: const ValueKey('qr-code-results'),
        insetPadding: const EdgeInsets.all(24),
        backgroundColor: _panel,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: _line),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 640,
            maxHeight: math.min(600, MediaQuery.sizeOf(context).height - 48),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 12, 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _AnnotationEditorState.toolbarBlue.withValues(
                          alpha: .12,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.qr_code_2,
                        size: 24,
                        color: _AnnotationEditorState.toolbarBlue,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.l10n.uiQrCodeResults,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            context.l10n.uiQrCodeResultCount(
                              widget.results.length,
                            ),
                            style: const TextStyle(fontSize: 12, color: _muted),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('cancel-qr-code'),
                      tooltip: context.l10n.uiQrCodeClose,
                      onPressed: widget.copying ? null : close,
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  ],
                ),
              ),
              if (widget.results.length > 1)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  child: SingleChildScrollView(
                    key: const ValueKey('qr-code-selector'),
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (var i = 0; i < widget.results.length; i++)
                          Padding(
                            padding: EdgeInsets.only(
                              right: i + 1 < widget.results.length ? 8 : 0,
                            ),
                            child: ChoiceChip(
                              key: ValueKey('qr-select-$i'),
                              label: Text(
                                context.l10n.uiQrCodeResultIndex(i + 1),
                              ),
                              selected: selected == i,
                              showCheckmark: false,
                              selectedColor: _AnnotationEditorState.toolbarBlue,
                              labelStyle: TextStyle(
                                color: selected == i ? Colors.white : _muted,
                              ),
                              onSelected: widget.copying
                                  ? null
                                  : (_) => select(i),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  context.l10n.uiQrCodeContent,
                  style: const TextStyle(fontSize: 12, color: _muted),
                ),
              ),
              // 内容独立滚动，长文本不会把复制和调整选区操作推到视口外。
              Flexible(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  constraints: const BoxConstraints(
                    minHeight: 128,
                    maxHeight: 320,
                  ),
                  decoration: BoxDecoration(
                    color: _background,
                    border: Border.all(color: _line),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Scrollbar(
                    controller: contentScroll,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      key: const ValueKey('qr-content-scroll'),
                      controller: contentScroll,
                      padding: const EdgeInsets.all(16),
                      child: SizedBox(
                        width: double.infinity,
                        child: SelectableText(
                          widget.results[selected],
                          key: ValueKey('qr-content-$selected'),
                          style: const TextStyle(
                            fontSize: 14,
                            height: 1.6,
                            fontFamily: 'Menlo',
                            fontFamilyFallback: ['PingFang SC'],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (widget.error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  child: Semantics(
                    liveRegion: true,
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline,
                          size: 16,
                          color: Colors.orange,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.error!,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.orange,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const Divider(height: 1, color: _line),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 20, 12),
                child: Row(
                  children: [
                    TextButton.icon(
                      key: const ValueKey('dismiss-qr-codes'),
                      onPressed: widget.copying ? null : widget.onAdjust,
                      icon: const Icon(Icons.crop_free, size: 18),
                      label: Text(context.l10n.uiQrCodeAdjustSelection),
                      style: TextButton.styleFrom(foregroundColor: _muted),
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      key: ValueKey('qr-result-$selected'),
                      onPressed: widget.copying ? null : copy,
                      icon: widget.copying
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.copy_outlined, size: 18),
                      label: Text(
                        widget.copying
                            ? context.l10n.uiQrCodeCopying
                            : context.l10n.uiQrCodeCopyAndFinish,
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: _AnnotationEditorState.toolbarBlue,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(164, 40),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
