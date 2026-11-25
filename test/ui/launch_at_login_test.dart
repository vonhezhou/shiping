import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fruler/app/app_controller.dart';
import 'package:fruler/platform/desktop_service.dart';

import '../app/launch_at_login_test.dart' show LoginDesktop;
import 'controller_test_host.dart';

void main() {
  for (final size in [const Size(1100, 760), const Size(920, 680)]) {
    testWidgets('随系统启动支持桌面鼠标并展示批准状态 $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final desktop = LoginDesktop();
      addTearDown(desktop.input.close);
      final controller = AppController(desktop);
      await controller.initialize();
      controller.selectSection(AppSection.settings);
      await tester.pumpWidget(ControllerTestHost(controller: controller));
      await tester.pumpAndSettle();
      final toggle = find.byKey(const ValueKey('launch-at-login'));
      await tester.ensureVisible(toggle);
      await tester.tap(toggle, kind: ui.PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(desktop.status, LaunchAtLoginStatus.enabled);
      expect(tester.widget<SwitchListTile>(toggle).value, true);
      desktop.status = LaunchAtLoginStatus.requiresApproval;
      await controller.refreshLaunchAtLogin();
      await tester.pumpAndSettle();
      expect(find.textContaining('等待系统批准'), findsOneWidget);
      await tester.tap(toggle, kind: ui.PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(desktop.status, LaunchAtLoginStatus.disabled);
      expect(tester.takeException(), isNull);
    });
  }
}
