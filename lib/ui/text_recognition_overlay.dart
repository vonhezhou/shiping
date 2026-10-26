part of 'fruler_app.dart';

class _TextRecognitionOverlay extends StatefulWidget {
  const _TextRecognitionOverlay({
    required this.controller,
    required this.rect,
    required this.toolbarTop,
  });
  final AppController controller;
  final Rect rect;
  final double toolbarTop;
  @override
  State<_TextRecognitionOverlay> createState() =>
      _TextRecognitionOverlayState();
}

class _TextRecognitionOverlayState extends State<_TextRecognitionOverlay> {
  final focus = FocusNode();
  RecognizedTextPosition? anchor, extent;
  int? pointer;
  bool overText = false;
  AppController get c => widget.controller;
  RecognizedTextDocument? get document => c.recognizedText;
  Offset pixelAt(Offset point) => Offset(
    (point.dx - widget.rect.left) * c.screenshotScaleX,
    (point.dy - widget.rect.top) * c.screenshotScaleY,
  );
  String? get selectedText =>
      document == null || anchor == null || extent == null
      ? null
      : document!.selectedText(anchor!, extent!);

  @override
  void initState() {
    super.initState();
    // 模式切换时主动获取焦点，不沿用截图工具栏按钮的焦点。
    focus.requestFocus();
  }

  @override
  void dispose() {
    focus.dispose();
    super.dispose();
  }

  KeyEventResult key(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      final k = event.logicalKey;
      if (k == LogicalKeyboardKey.escape) c.dismissText();
      if (HardwareKeyboard.instance.isMetaPressed &&
          document != null &&
          !c.textCopying) {
        if (k == LogicalKeyboardKey.keyA) {
          setState(() {
            anchor = document!.start;
            extent = document!.end;
          });
        } else if (k == LogicalKeyboardKey.keyC) {
          c.copyRecognizedText(selectedText: selectedText);
        }
      }
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final boxes = document == null || anchor == null || extent == null
        ? <Rect>[]
        : document!.selectionBoxes(anchor!, extent!);
    return Focus(
      focusNode: focus,
      autofocus: true,
      onKeyEvent: key,
      child: Stack(
        children: [
          Positioned.fill(
            child: MouseRegion(
              cursor: overText
                  ? SystemMouseCursors.text
                  : SystemMouseCursors.basic,
              onHover: (event) {
                final hit = document?.hit(pixelAt(event.localPosition)) != null;
                if (hit != overText) setState(() => overText = hit);
              },
              onExit: (_) {
                if (overText) setState(() => overText = false);
              },
              child: Listener(
                key: const ValueKey('text-selection-canvas'),
                behavior: HitTestBehavior.opaque,
                onPointerDown: (event) {
                  if (event.buttons != kPrimaryMouseButton ||
                      c.textCopying ||
                      c.textRecognizing ||
                      pointer != null) {
                    return;
                  }
                  focus.requestFocus();
                  final hit = document?.hit(pixelAt(event.localPosition));
                  setState(() {
                    anchor = extent = hit;
                    pointer = hit == null ? null : event.pointer;
                  });
                },
                onPointerMove: (event) {
                  if (pointer != event.pointer || c.textCopying) return;
                  setState(
                    () => extent = document?.hit(
                      pixelAt(event.localPosition),
                      nearest: true,
                    ),
                  );
                },
                onPointerUp: (event) {
                  if (pointer == event.pointer) pointer = null;
                },
                onPointerCancel: (event) {
                  if (pointer == event.pointer) pointer = null;
                },
                child: CustomPaint(
                  painter: _TextSelectionPainter(
                    boxes,
                    widget.rect,
                    c.screenshotScaleX,
                    c.screenshotScaleY,
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: CustomSingleChildLayout(
              delegate: _TextToolbarLayout(widget.toolbarTop),
              child: Material(
                color: _panel,
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (c.textRecognizing)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      Text(
                        c.textRecognizing
                            ? context.l10n.uiTextRecognizing
                            : context.l10n.uiTextSelectionHint,
                        style: const TextStyle(fontSize: 12),
                      ),
                      TextButton(
                        key: const ValueKey('dismiss-text-selection'),
                        onPressed: c.textCopying ? null : c.dismissText,
                        child: Text(context.l10n.uiExitTextSelection),
                      ),
                      if (document != null)
                        FilledButton(
                          key: const ValueKey('copy-all-text-finish'),
                          onPressed: c.textCopying
                              ? null
                              : () => c.copyRecognizedText(finish: true),
                          child: Text(context.l10n.uiCopyAllTextAndFinish),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TextSelectionPainter extends CustomPainter {
  const _TextSelectionPainter(this.boxes, this.rect, this.scaleX, this.scaleY);
  final List<Rect> boxes;
  final Rect rect;
  final double scaleX, scaleY;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(rect);
    canvas.translate(rect.left, rect.top);
    canvas.scale(1 / scaleX, 1 / scaleY);
    final paint = Paint()..color = const Color(0x663B82F6);
    for (final box in boxes) {
      canvas.drawRect(box, paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_TextSelectionPainter old) =>
      old.boxes != boxes ||
      old.rect != rect ||
      old.scaleX != scaleX ||
      old.scaleY != scaleY;
}

/// 按工具栏实际高度约束位置，避免近全屏选区或文案换行时操作越出屏幕。
class _TextToolbarLayout extends SingleChildLayoutDelegate {
  const _TextToolbarLayout(this.top);
  final double top;
  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints(maxWidth: math.max(0, constraints.maxWidth - 24));
  @override
  Offset getPositionForChild(Size size, Size childSize) => Offset(
    (size.width - childSize.width) / 2,
    top.clamp(8, math.max(8, size.height - childSize.height - 8)).toDouble(),
  );
  @override
  bool shouldRelayout(_TextToolbarLayout oldDelegate) => top != oldDelegate.top;
}
