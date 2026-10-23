import 'package:flutter/material.dart';

import '../l10n/localizations_context.dart';

/// 仅构建可见字体项，搜索不会修改当前文字样式。
class FontFamilyPicker extends StatefulWidget {
  const FontFamilyPicker({
    super.key,
    required this.families,
    required this.selected,
    required this.onSelected,
  });

  final List<String> families;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  State<FontFamilyPicker> createState() => _FontFamilyPickerState();
}

class _FontFamilyPickerState extends State<FontFamilyPicker> {
  final scroll = ScrollController();
  String query = '';

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final families = query.isEmpty
        ? widget.families
        : widget.families
              .where((family) => family.toLowerCase().contains(query))
              .toList();
    return SizedBox(
      width: 280,
      height: 340,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: TextField(
              key: const ValueKey('annotation-font-search'),
              autofocus: true,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: context.l10n.uiSearchFonts,
                prefixIcon: Icon(Icons.search, size: 18),
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                if (scroll.hasClients) scroll.jumpTo(0);
                setState(() => query = value.trim().toLowerCase());
              },
            ),
          ),
          Expanded(
            child: families.isEmpty
                ? Center(child: Text(context.l10n.uiNoMatchingFonts))
                : Scrollbar(
                    controller: scroll,
                    child: ListView.builder(
                      key: const ValueKey('annotation-font-list'),
                      controller: scroll,
                      padding: EdgeInsets.zero,
                      itemExtent: 40,
                      itemCount: families.length,
                      itemBuilder: (context, index) {
                        final family = families[index];
                        return ListTile(
                          key: ValueKey('annotation-font-option-$family'),
                          dense: true,
                          selected: family == widget.selected,
                          leading: SizedBox(
                            width: 18,
                            child: family == widget.selected
                                ? const Icon(Icons.check, size: 18)
                                : null,
                          ),
                          title: Text(
                            family,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontFamily: family,
                              fontSize: 14,
                            ),
                          ),
                          onTap: () => widget.onSelected(family),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
