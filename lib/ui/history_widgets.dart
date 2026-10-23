part of 'fruler_app.dart';

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
          decoration: InputDecoration(labelText: context.l10n.uiName),
          onChanged: (v) => name = v,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.uiCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, name),
          child: Text(context.l10n.uiSaveName),
        ),
      ],
    ),
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
          title: context.l10n.uiMeasurementRecords,
          subtitle: '${records.length} / ${c.measurements.length} · px / pt',
          onClear: c.measurements.isEmpty ? null : c.clearMeasurements,
        ),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('measurement-search'),
          decoration: InputDecoration(
            labelText: context.l10n.uiMeasurementSearch,
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (v) => setState(() => query = v),
        ),
        Wrap(
          spacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilterChip(
              label: Text(context.l10n.uiFavoritesOnly),
              selected: favorites,
              onSelected: (v) => setState(() => favorites = v),
            ),
            for (final csv in [true, false])
              TextButton(
                onPressed: records.isEmpty
                    ? null
                    : () => c.exportMeasurements(records, csv: csv),
                child: Text(
                  context.l10n.uiExportCurrentResults(csv ? 'CSV' : 'JSON'),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (records.isEmpty)
          _Empty(
            icon: Icons.square_foot_rounded,
            title: context.l10n.uiNoMeasurements,
            description: context.l10n.uiNoMeasurementsDescription,
          )
        else
          for (final r in records)
            Card(
              color: _panel,
              child: ListTile(
                onTap: () => c.copyMeasurement(r),
                leading: IconButton(
                  tooltip: r.favorite
                      ? context.l10n.uiUnfavoriteMeasurement
                      : context.l10n.uiFavoriteMeasurement,
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
                  context.l10n.uiMeasurementDetails(
                    r.imageSource
                        ? context.l10n.uiOriginalPixels
                        : r.measurement.pointLabel,
                    _modeLabel(context, r.measurement.mode),
                    r.displayName,
                    r.scaleX.toStringAsFixed(2),
                    r.scaleY.toStringAsFixed(2),
                    DateFormat.yMMMd(context.l10n.localeName)
                        .add_Hms()
                        .format(r.createdAt.toLocal()),
                  ),
                  style: const TextStyle(fontSize: 11, color: _muted),
                ),
                isThreeLine: true,
                trailing: PopupMenuButton<String>(
                  tooltip: context.l10n.uiMeasurementActions,
                  onSelected: (action) async {
                    if (action == 'delete') {
                      c.removeMeasurement(r);
                    } else if (action == 'copy') {
                      await c.copyMeasurement(r);
                    } else {
                      final name = await _requestName(
                        context,
                        context.l10n.uiNameMeasurement,
                        r.name,
                      );
                      if (name != null) c.updateMeasurement(r, name: name);
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'copy',
                      child: Text(context.l10n.uiCopyDimensions),
                    ),
                    PopupMenuItem(
                      value: 'name',
                      child: Text(context.l10n.uiNameMeasurement),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text(context.l10n.uiDeleteRecord),
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }
}
