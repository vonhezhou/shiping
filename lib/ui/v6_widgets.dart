part of 'fruler_app.dart';

Future<bool> _confirmImageReplacement(
  BuildContext context,
  AppController controller,
) async {
  if (!context.mounted) return false;
  final action = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('保存图片项目？'),
      content: const Text('当前图片项目有未保存的修改。保存后可以恢复图片、标注和视图位置。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, 'cancel'),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, 'discard'),
          child: const Text('放弃更改'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, 'save'),
          child: const Text('保存项目'),
        ),
      ],
    ),
  );
  if (action == 'save') return await controller.saveImageProject();
  return action == 'discard';
}
