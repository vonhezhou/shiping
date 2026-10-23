import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';

import 'app/app_controller.dart';
import 'app/logging/app_logging.dart';
import 'platform/desktop_service.dart';
import 'ui/fruler_app.dart';

void main() {
  runZonedGuarded<Future<void>>(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      final logs = await initializeAppLogging(
        appVersion: const String.fromEnvironment(
          'FLUTTER_BUILD_NAME',
          defaultValue: '0.10.0',
        ),
      );
      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        reportUnhandledError(
          'Flutter framework error.',
          details.exception,
          details.stack ?? StackTrace.empty,
        );
      };
      WidgetsBinding.instance.platformDispatcher.onError = (error, stackTrace) {
        reportUnhandledError('Platform dispatcher error.', error, stackTrace);
        return true;
      };
      // 正常退出时尽量写完末尾日志；进程强制退出仍由文件轮转器定期刷新。
      AppLifecycleListener(
        onExitRequested: () async {
          await logs?.dispose();
          return AppExitResponse.exit;
        },
      );
      final controller = AppController(DesktopService.create());
      runApp(FrulerApp(controller: controller));
      await controller.initialize();
    },
    (error, stackTrace) =>
        reportUnhandledError('Unhandled zone error.', error, stackTrace),
  );
}
