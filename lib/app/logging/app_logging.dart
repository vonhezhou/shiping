import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:logging_appenders/logging_appenders.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

const appLogFileName = 'fruler.log';
const appLogRotateAtSizeBytes = 10 * 1024 * 1024;
const appLogKeepRotateCount = 3;

enum AppLogLevel { debug, info, warning, error }

final _lifecycleLogger = Logger('app.lifecycle');
final _errorLogger = Logger('app.errors');

/// Dart 是唯一文件写入者；原生诊断也通过 Logger 汇入这里。
class AppLogHandle {
  AppLogHandle._(this.directory, this._consoleAppender);

  final Directory directory;
  RotatingFileAppender? _fileAppender;
  Zone? _fileZone;
  final PrintAppender? _consoleAppender;
  Future<void>? _disposal;
  bool _fileAvailable = true;
  bool get fileAvailable => _fileAvailable;

  void _startFileAppender({
    required String filePath,
    required int keepRotateCount,
    required int rotateAtSizeBytes,
    required Duration rotateCheckInterval,
  }) {
    // 包住订阅和异步文件操作，避免日志写入失败再被全局错误处理写回同一文件。
    runZonedGuarded(
      () {
        _fileZone = Zone.current;
        _fileAppender = RotatingFileAppender(
          baseFilePath: filePath,
          keepRotateCount: keepRotateCount,
          rotateAtSizeBytes: rotateAtSizeBytes,
          rotateCheckInterval: rotateCheckInterval,
        )..attachToLogger(Logger.root);
      },
      (error, stackTrace) {
        if (!_fileAvailable) return;
        _fileAvailable = false;
        unawaited(_fileAppender?.detachFromLoggers());
        _fileZone?.run(() => unawaited(_fileAppender?.dispose()));
        _errorLogger.severe(
          'File logging disabled: errorType=${error.runtimeType}.',
          null,
          stackTrace,
        );
      },
    );
  }

  @visibleForTesting
  // 该库仅将显式刷新标记为测试用途；集成验收读盘前使用它。
  Future<void> flush() async {
    // ignore: invalid_use_of_visible_for_testing_member
    if (_fileAvailable) await _fileZone?.run(() => _fileAppender?.forceFlush());
  }

  Future<void> dispose() => _disposal ??= _dispose();

  Future<void> _dispose() async {
    if (_fileAvailable) await _fileZone?.run(() => _fileAppender?.dispose());
    await _consoleAppender?.dispose();
  }
}

/// 日志目录或文件不可用时继续启动，诊断失败不能阻断屏幕工具。
Future<AppLogHandle?> initializeAppLogging({
  required String appVersion,
  Future<Directory> Function()? directoryResolver,
  bool? isReleaseMode,
  AppLogLevel? logLevel,
  int rotateAtSizeBytes = appLogRotateAtSizeBytes,
  int keepRotateCount = appLogKeepRotateCount,
  Duration rotateCheckInterval = const Duration(minutes: 5),
}) async {
  final releaseMode = isReleaseMode ?? kReleaseMode;
  final configuredLevel =
      logLevel ?? (releaseMode ? AppLogLevel.info : AppLogLevel.debug);
  Logger.root
    ..clearListeners()
    ..level = _level(configuredLevel);
  final console = releaseMode
      ? null
      : PrintAppender(formatter: const ColorFormatter());
  console?.attachToLogger(Logger.root);
  try {
    final directory = await (directoryResolver ?? _defaultLogDirectory)();
    await directory.create(recursive: true);
    // 提前验证写权限，让常见初始化失败在此处降级。
    final file = File(path.join(directory.path, appLogFileName));
    final probe = await file.open(mode: FileMode.append);
    await probe.close();
    final handle = AppLogHandle._(directory, console);
    handle._startFileAppender(
      filePath: file.path,
      keepRotateCount: keepRotateCount,
      rotateAtSizeBytes: rotateAtSizeBytes,
      rotateCheckInterval: rotateCheckInterval,
    );
    if (!handle.fileAvailable) return null;
    _lifecycleLogger.log(
      _level(configuredLevel),
      'Session started: version=$appVersion, '
      'mode=${releaseMode ? 'release' : 'debug'}, '
      'logLevel=${configuredLevel.name}, os=${Platform.operatingSystem}.',
    );
    return handle;
  } catch (error, stackTrace) {
    _errorLogger.severe(
      'Local logging unavailable: errorType=${error.runtimeType}.',
      null,
      stackTrace,
    );
    return null;
  }
}

void applyAppLogLevel(AppLogLevel level) {
  Logger.root.level = _level(level);
  _lifecycleLogger.log(_level(level), 'Log level changed: ${level.name}.');
}

Level _level(AppLogLevel level) => switch (level) {
  AppLogLevel.debug => Level.ALL,
  AppLogLevel.info => Level.INFO,
  AppLogLevel.warning => Level.WARNING,
  AppLogLevel.error => Level.SEVERE,
};

Future<Directory> _defaultLogDirectory() async => Directory(
  path.join((await getApplicationSupportDirectory()).path, 'fruler', 'logs'),
);

void reportUnhandledError(String message, Object error, StackTrace stackTrace) {
  _errorLogger.severe(
    '$message errorType=${error.runtimeType}.',
    null,
    stackTrace,
  );
}
