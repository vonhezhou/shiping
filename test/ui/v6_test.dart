import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fruler/app/app_controller.dart';
import 'package:fruler/core/core.dart';
import 'package:fruler/platform/image_document.dart';
import 'package:fruler/ui/fruler_app.dart';

import '../fake_desktop.dart';

void main() {
  late FakeDesktop d;
  late AppController c;
  Future<void> setup(WidgetTester tester) async {
    tester.view.physicalSize = const Size(920, 680);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    d = FakeDesktop();
    c = AppController(d);
    await c.initialize();
    addTearDown(c.dispose);
    addTearDown(d.input.close);
    await tester.pumpWidget(FrulerApp(controller: c));
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => c.loadImage(
        ImageFileData(
          'fixture.png',
          File('test/fixtures/workspace.png').readAsBytesSync(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  testWidgets('最小窗口保存项目、恢复视图并显示真实已保存状态', (tester) async {
    await setup(tester);
    await tap(tester, find.text('平移'));
    expect(c.imageView!.pan, true);
    await tap(tester, find.widgetWithText(ChoiceChip, '取色'));
    expect(c.imageView!.pan, false);
    await tap(tester, find.byTooltip('放大'));
    final scale = c.imageView!.scale;
    await tap(tester, find.text('保存项目'));
    expect(c.imageProjectDirty, false);
    expect(find.text('已保存'), findsOneWidget);
    final text = d.projectText!;
    expect(ImageProject.decode(text).view!.scale, scale);
    await tap(tester, find.text('关闭图片'));
    expect(c.imageDocument, isNull);
    d.projectFile = ImageProjectFileData('saved.fruler', text);
    await tester.runAsync(() => c.openImageProject());
    await tester.pumpAndSettle();
    expect(c.imageView!.scale, scale);
    expect(c.imageProjectDirty, false);
    expect(find.text('已保存'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('未保存关闭可取消、保存取消不丢数据、放弃后才关闭', (tester) async {
    await setup(tester);
    final doc = c.imageDocument;
    await tap(tester, find.text('关闭图片'));
    expect(find.text('保存图片项目？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(identical(c.imageDocument, doc), true);
    d.fileResult = false;
    await tap(tester, find.text('关闭图片'));
    await tester.tap(find.widgetWithText(FilledButton, '保存项目'));
    await tester.pumpAndSettle();
    expect(c.imageDocument, isNotNull);
    expect(c.imageProjectDirty, true);
    await tap(tester, find.text('关闭图片'));
    await tester.tap(find.text('放弃更改'));
    await tester.pumpAndSettle();
    expect(c.imageDocument, isNull);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Cmd Z、Cmd Shift Z 与按钮都能操作同一标注历史', (tester) async {
    await setup(tester);
    c.useImageTool('rectangle');
    c.imageEvent('pointer', {'x': 20.0, 'y': 30.0, 'phase': 'down'});
    c.imageEvent('pointer', {'x': 80.0, 'y': 90.0, 'phase': 'up'});
    await tester.pumpAndSettle();
    await tap(tester, find.text('编辑标注'));
    final canvas = find.byKey(const ValueKey('image-canvas'));
    await tester.ensureVisible(canvas);
    await tester.tapAt(tester.getTopLeft(canvas) + const Offset(40, 50));
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(c.imageOverlay['pinned'], isEmpty);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect((c.imageOverlay['pinned'] as List).length, 1);
    await tap(tester, find.text('清空标注'));
    await tap(tester, find.text('撤销'));
    expect((c.imageOverlay['pinned'] as List).length, 1);
    await tap(tester, find.text('重做'));
    expect(c.imageOverlay['pinned'], isEmpty);
    expect(tester.takeException(), isNull);
  });
  testWidgets('退出请求有未保存项目时确认，取消会告知原生保留应用', (tester) async {
    await setup(tester);
    d.event('quitRequested');
    await tester.pumpAndSettle();
    expect(find.text('保存图片项目？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(d.quitAllowed, false);
    d.event('quitRequested');
    await tester.pumpAndSettle();
    await tester.tap(find.text('放弃更改'));
    await tester.pumpAndSettle();
    expect(d.quitAllowed, true);
    expect(tester.takeException(), isNull);
  });
}
