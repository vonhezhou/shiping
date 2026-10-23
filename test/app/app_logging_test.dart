import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fruler/app/logging/app_logging.dart';
import 'package:logging/logging.dart';

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('fruler-logs-');
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test('启动和不同模块写入同一文件，关闭会刷新且可重复调用', () async {
    final handle = await initializeAppLogging(
      appVersion: 'test-version',
      directoryResolver: () async => directory,
      isReleaseMode: true,
    );
    expect(handle, isNotNull);
    Logger('app.capture').info('Capture completed: session=7.');
    Logger('native.capture').warning('Capture cancelled: session=8.');
    await handle!.dispose();
    await handle.dispose();
    final content = await File('${directory.path}/$appLogFileName')
        .readAsString();
    expect(content, contains('Session started: version=test-version'));
    expect(content, contains('app.capture'));
    expect(content, contains('native.capture'));
    expect(content, contains('session=7'));
    expect(content, contains('session=8'));
  });

  test('运行时等级过滤生效，未处理异常保留堆栈但不写异常数据', () async {
    final handle = await initializeAppLogging(
      appVersion: 'test',
      directoryResolver: () async => directory,
      isReleaseMode: true,
    );
    Logger('test').fine('debug-filtered');
    applyAppLogLevel(AppLogLevel.warning);
    Logger('test').info('info-filtered');
    Logger('test').warning('warning-kept');
    reportUnhandledError(
      'Unhandled test error.',
      StateError('private clipboard payload'),
      StackTrace.fromString('test_stack_trace'),
    );
    await handle!.dispose();
    final content = await File('${directory.path}/$appLogFileName')
        .readAsString();
    expect(content, isNot(contains('debug-filtered')));
    expect(content, isNot(contains('info-filtered')));
    expect(content, contains('warning-kept'));
    expect(content, contains('test_stack_trace'));
    expect(content, contains('StateError'));
    expect(content, isNot(contains('private clipboard payload')));
  });

  test('轮转后文件数量有界且保留最新诊断', () async {
    final handle = await initializeAppLogging(
      appVersion: 'test',
      directoryResolver: () async => directory,
      isReleaseMode: true,
      rotateAtSizeBytes: 300,
      keepRotateCount: 2,
      rotateCheckInterval: Duration.zero,
    );
    for (var i = 0; i < 40; i++) {
      Logger('test.rotation').warning('Diagnostic record $i: ${'x' * 80}');
      await handle!.flush();
      // 等待轮转器异步检查文件长度并完成移动。
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await handle!.dispose();
    final files = await directory.list().where((e) => e is File).toList();
    expect(files.length, lessThanOrEqualTo(3));
    final contents = await Future.wait(
      files.cast<File>().map((e) => e.readAsString()),
    );
    expect(contents.join(), contains('Diagnostic record 39'));
    expect(contents.join(), isNot(contains('Diagnostic record 0:')));
  });

  test('日志目录不可用不阻止应用启动', () async {
    final handle = await initializeAppLogging(
      appVersion: 'test',
      directoryResolver: () async =>
          throw const FileSystemException('unavailable'),
      isReleaseMode: true,
    );
    expect(handle, isNull);
    Logger('test').warning('Application continues.');
  });

  test('运行中日志目录丢失会停用文件输出，不递归抛出写入错误', () async {
    final output = Directory('${directory.path}/output');
    final handle = await initializeAppLogging(
      appVersion: 'test',
      directoryResolver: () async => output,
      isReleaseMode: true,
    );
    await handle!.flush();
    await output.rename('${directory.path}/removed');
    Logger('test').warning('Diagnostic after directory removal.');
    final deadline = DateTime.now().add(const Duration(seconds: 2));
    while (handle.fileAvailable && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(handle.fileAvailable, false);
    Logger('test').warning('Application continues after logging failure.');
    await handle.dispose();
  });
}
