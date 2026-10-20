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
                  '${r.imageSource ? '原图像素' : r.measurement.pointLabel} · ${_modeLabels[r.measurement.mode]} · ${r.displayName}\n缩放 ${r.scaleX.toStringAsFixed(2)} × ${r.scaleY.toStringAsFixed(2)} · ${r.createdAt.toLocal().toString().split('.').first}',
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
