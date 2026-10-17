import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fruler/app/app_controller.dart';
import 'package:fruler/core/core.dart';
import 'package:fruler/platform/image_document.dart';

import '../fake_desktop.dart';
import '../app/v6_controller_test.dart' show ProjectFixtureCodec;
import 'controller_test_host.dart';

void main() {
  late FakeDesktop d;
  late AppController c;
  Future<void> setup(WidgetTester tester) async {
    tester.view.physicalSize = const Size(920, 680);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    d = FakeDesktop();
    c = AppController(d, imageCodec: ProjectFixtureCodec());
    await c.initialize();
    addTearDown(d.input.close);
    await tester.pumpWidget(ControllerTestHost(controller: c));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('最小窗口添加格式、即时预览、修改排序与自动复制可用', (tester) async {
    await setup(tester);
    await tap(tester, find.text('颜色格式'));
    await tap(tester, find.text('添加格式'));
    await tester.enterText(find.byKey(const ValueKey('output-name')), 'RGBA');
    await tester.enterText(
      find.byKey(const ValueKey('output-template')),
      'rgba(%Re,%Gr,%Bl,%Alf)',
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('output-preview')), findsOneWidget);
    await tap(tester, find.text('保存格式'));
    await tester.scrollUntilVisible(
      find.byTooltip('上移 RGBA'),
      150,
      scrollable: find
          .descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tap(tester, find.byTooltip('上移 RGBA'));
    expect(c.colorOutputs[c.colorOutputs.length - 2].name, 'RGBA');
    await tap(tester, find.text('完成'));
    await tap(tester, find.text('RGBA').last);
    expect(c.activeColorOutput.name, 'RGBA');
    await c.copyColor(const RgbColor(1, 2, 3));
    expect(d.clipboard, 'rgba(1,2,3,1)');
    await tester.pumpAndSettle();
    expect(tester.takeException(), null);
  });
  testWidgets('未知模板不可保存，取消不更改原格式', (tester) async {
    await setup(tester);
    await tap(tester, find.text('颜色格式'));
    await tap(tester, find.byTooltip('编辑 HEX'));
    await tester.enterText(
      find.byKey(const ValueKey('output-template')),
      '%Unknown',
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '保存格式'))
          .onPressed,
      null,
    );
    await tap(tester, find.text('取消'));
    expect(c.colorOutputs.first.template, '#%ReX%GrX%BlX');
    await tap(tester, find.text('完成'));
    expect(tester.takeException(), null);
  });
  testWidgets('鼠标动作设置即时生效并与连续开关联动', (tester) async {
    await setup(tester);
    await tap(tester, find.text('取色设置'));
    await tap(tester, find.byKey(const ValueKey('picker-primary')));
    await tap(tester, find.text('取色后打开编辑器').last);
    expect(c.pickerBehavior.primary, PickerMouseAction.pickAndEdit);
    await tap(tester, find.byKey(const ValueKey('picker-secondary')));
    await tap(tester, find.text('取色并继续').last);
    expect(c.pickerBehavior.secondary, PickerMouseAction.pickAndContinue);
    await tap(tester, find.text('完成'));
    await tap(tester, find.byType(Switch).first);
    expect(c.pickerBehavior.primary, PickerMouseAction.pickAndContinue);
    expect(c.pickerBehavior.secondary, PickerMouseAction.pickAndContinue);
    expect(tester.takeException(), null);
  });
  testWidgets('取色后自动打开编辑器，取消保留采样，重新取色不会递归进入编辑器', (tester) async {
    await setup(tester);
    c.setPickerBehavior(
      const PickerBehavior(primary: PickerMouseAction.pickAndEdit),
    );
    await c.pickColor();
    d.pointer(phase: 'up');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('hex-editor')), findsOneWidget);
    expect(c.busy, false);
    expect(d.finishCalls, 1);
    await c.pickColor();
    await tester.pumpAndSettle();
    expect(c.pendingPickedEditorColor, null);
    await tap(tester, find.text('取消'));
    expect(c.colors.length, 1);
    c.setPickerBehavior(
      const PickerBehavior(activation: PickerActivation.editor),
    );
    await c.pickColor();
    await tester.pumpAndSettle();
    expect(find.text('重新取色'), findsOneWidget);
    await tap(tester, find.text('重新取色'));
    expect(c.busy, true);
    expect(d.beginCalls, 2);
    d.event('cancelled');
    await tester.pumpAndSettle();
    expect(tester.takeException(), null);
  });
  testWidgets('图片右键不误取色，左键使用自定义输出且保留文档', (tester) async {
    await setup(tester);
    c.saveColorOutput(name: 'Channels', template: '%Re/%Gr/%Bl');
    c.selectColorOutput(c.colorOutputs.last.id);
    c.setPickerBehavior(
      const PickerBehavior(primary: PickerMouseAction.cancel),
    );
    await c.loadImage(
      ImageFileData(
        'fixture.png',
        File('test/fixtures/workspace.png').readAsBytesSync(),
      ),
    );
    await tester.pumpAndSettle();
    final canvas = find.byKey(const ValueKey('image-canvas'));
    await tester.ensureVisible(canvas);
    await tester.pumpAndSettle();
    final point = tester.getCenter(canvas);
    await tester.tapAt(point, buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(c.colors, isEmpty);
    await tester.tapAt(point);
    await tester.pumpAndSettle();
    expect(c.colors.length, 1);
    expect(c.imageDocument, isNotNull);
    expect(d.clipboard, contains('/'));
    expect(tester.takeException(), null);
  });
}
