import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fruler/app/app_controller.dart';

import 'controller_test_host.dart';

import '../fake_desktop.dart';

void main() {
  testWidgets('录制组合可保存，取消会恢复注册且不修改配置', (tester) async {
    tester.view.physicalSize = const Size(920, 680);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final desktop = FakeDesktop();
    final controller = AppController(desktop);
    await controller.initialize();
    addTearDown(desktop.input.close);
    await tester.pumpWidget(ControllerTestHost(controller: controller));
    await tester.tap(find.text('偏好设置').first);
    await tester.pumpAndSettle();
    final edit = find.widgetWithText(
      OutlinedButton,
      controller.shortcuts.picker.label,
    );
    await tester.ensureVisible(edit);
    await tester.tap(edit);
    await tester.pumpAndSettle();
    expect(desktop.recording, true);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit8);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(find.text('⌃ ⌥ 8'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(desktop.recording, false);
    expect(controller.shortcuts.picker.key, '8');
    expect(controller.shortcuts.picker.control, true);
    await tester.tap(find.widgetWithText(OutlinedButton, '⌃ ⌥ 8'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(desktop.recording, false);
    expect(controller.shortcuts.picker.key, '8');
    await tester.tap(find.widgetWithText(OutlinedButton, '⌃ ⌥ 8'));
    await tester.pumpAndSettle();
    desktop.event('shortcutRecorded', {
      'chord': {'key': '9', 'meta': true, 'shift': true},
    });
    await tester.pump();
    expect(find.text('⇧ ⌘ 9'), findsOneWidget);
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(controller.shortcuts.picker.key, '9');
    expect(desktop.recording, false);
    expect(tester.takeException(), isNull);
  });
}
