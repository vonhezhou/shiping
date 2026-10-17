import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fruler/app/app_controller.dart';
import 'package:fruler/core/core.dart';
import 'package:fruler/platform/image_document.dart';

import 'controller_test_host.dart';

import '../fake_desktop.dart';
import '../app/v6_controller_test.dart' show ProjectFixtureCodec;

void main() {
  late FakeDesktop d;
  late AppController c;
  final bytes = File('test/fixtures/workspace.png').readAsBytesSync();
  Future<void> setup(WidgetTester tester, {bool recovery = false}) async {
    tester.view.physicalSize = const Size(920, 680);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    d = FakeDesktop();
    if (recovery) {
      d.draft = jsonEncode({
        'version': 1,
        'dirty': true,
        'savedAt': DateTime(2026).toIso8601String(),
        'project': jsonDecode(
          ImageProject(
            name: 'fixture.png',
            png: bytes,
            width: 240,
            height: 160,
            annotations: [],
            tool: 'picker',
          ).encode(),
        ),
      });
    }
    c = AppController(d, imageCodec: ProjectFixtureCodec());
    await c.initialize();
    addTearDown(d.input.close);
    await tester.pumpWidget(ControllerTestHost(controller: c));
    await tester.pumpAndSettle();
    if (!recovery) {
      await tester.runAsync(
        () => c.loadImage(ImageFileData('fixture.png', bytes)),
      );
      await tester.pumpAndSettle();
    }
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('保存和另存为显示真实名称位置，最近项目可重新打开，最小窗口不溢出', (tester) async {
    await setup(tester);
    await tap(tester, find.widgetWithText(OutlinedButton, '保存项目'));
    expect(find.text('saved.fruler'), findsOneWidget);
    expect(find.text('/tmp/saved.fruler'), findsOneWidget);
    await tap(tester, find.widgetWithText(OutlinedButton, '另存为'));
    expect(d.savedProjectPath, null);
    final text = d.projectText!;
    await tap(tester, find.text('关闭图片'));
    d.projectFile = ImageProjectFileData(
      'saved.fruler',
      text,
      path: '/tmp/saved.fruler',
    );
    await tap(tester, find.text('最近项目 ▾'));
    await tester.tap(find.text('saved.fruler'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {});
    await tester.pumpAndSettle();
    expect(d.openedProjectPath, '/tmp/saved.fruler');
    expect(tester.takeException(), null);
  });
  testWidgets('独立草稿在修改后自动写入，无变化不反复写', (tester) async {
    await setup(tester);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(d.draft, isNotNull);
    expect(d.projectText, null);
    final writes = d.draftWrites.length;
    await tester.pump(const Duration(seconds: 16));
    await tester.pumpAndSettle();
    expect(d.draftWrites.length, writes);
    await tap(tester, find.byTooltip('放大'));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(d.draftWrites.length, writes + 1);
  });
  testWidgets('恢复提示阻止覆盖旧草稿；恢复可继续，丢弃需确认', (tester) async {
    await setup(tester, recovery: true);
    expect(find.text('发现上次的图片草稿'), findsOneWidget);
    final open = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '打开图片'),
    );
    expect(open.onPressed, null);
    await tap(tester, find.text('丢弃草稿'));
    expect(find.text('丢弃本地草稿？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(d.draft, isNotNull);
    await tap(tester, find.text('恢复草稿'));
    await tester.runAsync(() async {});
    await tester.pumpAndSettle();
    expect(c.imageDocument, isNotNull);
    expect(c.imageProjectDirty, true);
    expect(tester.takeException(), null);
  });
  testWidgets('画布之外全局 Cmd O、Cmd S、Cmd Shift S 可用', (tester) async {
    await setup(tester);
    Future<void> shortcut(LogicalKeyboardKey key, {bool shift = false}) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(key);
      if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
    }

    await tap(tester, find.text('偏好设置'));
    await shortcut(LogicalKeyboardKey.keyS);
    expect(c.imageProjectPath, '/tmp/saved.fruler');
    await shortcut(LogicalKeyboardKey.keyS);
    expect(d.savedProjectPath, '/tmp/saved.fruler');
    await shortcut(LogicalKeyboardKey.keyS, shift: true);
    expect(d.savedProjectPath, null);
    d.projectFile = ImageProjectFileData(
      'copy.fruler',
      d.projectText!,
      path: '/tmp/copy.fruler',
    );
    await shortcut(LogicalKeyboardKey.keyO);
    await tester.runAsync(() async {});
    await tester.pumpAndSettle();
    expect(c.imageProjectName, 'copy.fruler');
    expect(c.section, AppSection.image);
  });
  testWidgets('未命名项目可选择保留草稿并正常退出', (tester) async {
    await setup(tester);
    d.event('quitRequested');
    await tester.pumpAndSettle();
    expect(find.text('保留草稿并退出'), findsOneWidget);
    await tester.tap(find.text('保留草稿并退出'));
    await tester.pumpAndSettle();
    expect(d.quitAllowed, true);
    expect(d.draft, isNotNull);
    expect(d.projectText, null);
    expect(tester.takeException(), null);
  });
}
