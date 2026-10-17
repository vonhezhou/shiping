import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fruler/app/app_controller.dart';

import 'controller_test_host.dart';

import '../fake_desktop.dart';

void main() {
  for (final size in [const Size(1100, 760), const Size(920, 680)]) {
    testWidgets('桌面布局 ${size.width}x${size.height} 可导航且无溢出', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final desktop = FakeDesktop();
      final controller = AppController(desktop);
      await controller.initialize();
      addTearDown(desktop.input.close);
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: ControllerTestHost(controller: controller),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('开始取色'), findsOneWidget);
      expect(find.text('你的调色板，从这里开始'), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (size.width == 1100) await _capture(tester, key, 'picker');
      await tester.tap(find.text('屏幕尺子').first);
      await tester.pumpAndSettle();
      expect(find.text('开始测量'), findsOneWidget);
      await tester.tap(find.text('交叉').first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (size.width == 1100) await _capture(tester, key, 'ruler');
      await tester.tap(find.text('偏好设置').first);
      await tester.pumpAndSettle();
      expect(find.text('颜色容差'), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (size.width == 1100) await _capture(tester, key, 'settings');
    });
  }
  testWidgets('未授权时可从引导进入权限页', (tester) async {
    tester.view.physicalSize = const Size(1100, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final desktop = FakeDesktop()..permission = false;
    final controller = AppController(desktop);
    await controller.initialize();
    addTearDown(desktop.input.close);
    await tester.pumpWidget(ControllerTestHost(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('前往授权 →'));
    await tester.pumpAndSettle();
    expect(find.text('请求屏幕授权'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String page) async {
  if (!const bool.fromEnvironment('FRULER_CAPTURE_PREVIEWS')) return;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('/private/tmp/fruler-$page.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
