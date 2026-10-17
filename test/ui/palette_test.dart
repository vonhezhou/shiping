import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fruler/app/app_controller.dart';
import 'package:fruler/core/core.dart';

import 'controller_test_host.dart';

import '../fake_desktop.dart';

void main() {
  testWidgets('最小窗口可编辑、收藏、命名、单条删除并导出颜色', (tester) async {
    tester.view.physicalSize = const Size(920, 680);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final desktop = FakeDesktop();
    final controller = AppController(desktop);
    await controller.initialize();
    addTearDown(desktop.input.close);
    await tester.pumpWidget(ControllerTestHost(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(controller.continuousPicker, true);
    await tester.tap(find.text('编辑颜色').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('hex-editor')), '#GG');
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '保存颜色'))
          .onPressed,
      isNull,
    );
    await tester.enterText(find.byKey(const ValueKey('hex-editor')), '#123');
    await tester.pump();
    await tester.tap(
      find.descendant(of: find.byType(AlertDialog), matching: find.text('HSL')),
    );
    await tester.pump();
    expect(find.byType(Slider), findsNWidgets(3));
    await tester.tap(find.text('保存颜色'));
    await tester.pumpAndSettle();
    expect(controller.selectedColor, const RgbColor(17, 34, 51));
    await tester.ensureVisible(find.byTooltip('颜色操作 #112233'));
    await tester.tap(find.byTooltip('颜色操作 #112233'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('收藏颜色'));
    await tester.pumpAndSettle();
    expect(controller.palette.single.favorite, true);
    await tester.tap(find.byTooltip('颜色操作 #112233').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('命名颜色'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextFormField),
      ),
      '品牌主色',
    );
    await tester.tap(find.text('保存名称'));
    await tester.pumpAndSettle();
    expect(controller.palette.single.name, '品牌主色');
    await tester.tap(find.byTooltip('颜色操作 #112233').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('从最近记录删除'));
    await tester.pumpAndSettle();
    expect(controller.colors, isEmpty);
    expect(controller.palette.length, 1);
    await tester.ensureVisible(find.text('导出 JSON').last);
    await tester.tap(find.text('导出 JSON').last);
    await tester.pumpAndSettle();
    expect(desktop.exportedName, 'fruler-palette.json');
    expect(desktop.exportedText, contains('品牌主色'));
    expect(tester.takeException(), isNull);
  });
}
