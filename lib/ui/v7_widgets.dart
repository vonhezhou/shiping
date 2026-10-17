part of 'fruler_app.dart';

class _RecoveryBanner extends StatelessWidget {
  const _RecoveryBanner({required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: _panel,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: _accent.withValues(alpha: .5)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '发现上次的图片草稿',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        const Text('可恢复图片、标注和视图位置。草稿保存在本机，不会自动覆盖原项目；请先恢复或丢弃，再打开其他图片项目。'),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            FilledButton(
              onPressed: controller.busy || controller.imageLoading
                  ? null
                  : controller.restoreImageDraft,
              child: const Text('恢复草稿'),
            ),
            TextButton(
              onPressed: controller.imageLoading
                  ? null
                  : () async {
                      final discard = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('丢弃本地草稿？'),
                          content: const Text('此操作无法撤销，已手动保存的项目文件不会被删除。'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('取消'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('丢弃草稿'),
                            ),
                          ],
                        ),
                      );
                      if (discard == true) await controller.discardRecovery();
                    },
              child: const Text('丢弃草稿'),
            ),
          ],
        ),
      ],
    ),
  );
}
