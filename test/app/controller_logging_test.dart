import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fruler/app/app_controller.dart';
import 'package:logging/logging.dart';

import '../fake_desktop.dart';

class _FailingStorageDesktop extends FakeDesktop {
  @override
  Future<void> saveState(String json) async => throw const FileSystemFailure();
}

class FileSystemFailure implements Exception {
  const FileSystemFailure();
}

void main() {
  late List<LogRecord> records;
  late StreamSubscription<LogRecord> subscription;
  late Level previousLevel;

  setUp(() {
    previousLevel = Logger.root.level;
    Logger.root.level = Level.ALL;
    records = [];
    subscription = Logger.root.onRecord.listen(records.add);
  });
  tearDown(() async {
    await subscription.cancel();
    Logger.root.level = previousLevel;
  });

  test('工具失败记录错误代码和堆栈，不记录原生错误中的用户内容', () async {
    final desktop = FakeDesktop()
      ..beginError = PlatformException(
        code: 'screen_permission',
        message: '/Users/private/secret-shot.png clipboard-secret',
      );
    final controller = AppController(desktop);
    addTearDown(controller.dispose);
    addTearDown(desktop.input.close);
    await controller.initialize();
    await controller.startScreenshot();

    final failure = records.singleWhere(
      (record) => record.message.startsWith('Capture begin failed:'),
    );
    expect(failure.level, Level.WARNING);
    expect(failure.message, contains('code=screen_permission'));
    expect(failure.stackTrace, isNotNull);
    expect(
      records.map((r) => '${r.message} ${r.error}').join(),
      isNot(contains('secret')),
    );
  });

  test('持久化失败有诊断且不包含完整配置与历史内容', () async {
    final desktop = _FailingStorageDesktop();
    final controller = AppController(desktop);
    addTearDown(controller.dispose);
    addTearDown(desktop.input.close);
    await controller.initialize();
    controller.createPaletteGroup('private-palette-secret');
    await Future<void>.delayed(Duration.zero);

    expect(
      records.any((r) => r.message.startsWith('State save failed:')),
      true,
    );
    expect(
      records.map((r) => '${r.message} ${r.error}').join(),
      isNot(contains('private-palette-secret')),
    );
  });

  test('复制成功日志不包含剪贴板颜色值', () async {
    final desktop = FakeDesktop();
    final controller = AppController(desktop);
    addTearDown(controller.dispose);
    addTearDown(desktop.input.close);
    await controller.initialize();
    await controller.copyColor();

    expect(records.any((r) => r.message == 'Clipboard write completed.'), true);
    expect(
      records.map((r) => r.message).join(),
      isNot(contains(desktop.clipboard!)),
    );
  });
}
