import 'package:flutter/material.dart';

import 'app/app_controller.dart';
import 'platform/desktop_service.dart';
import 'ui/fruler_app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = AppController(DesktopService.create());
  runApp(FrulerApp(controller: controller));
  controller.initialize();
}
