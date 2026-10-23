import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fruler/app/app_controller.dart';
import 'package:fruler/core/core.dart';
import 'package:fruler/platform/desktop_service.dart';
import 'package:fruler/l10n/app_language.dart';
import 'package:fruler/l10n/app_localizations.dart';
import 'package:fruler/ui/font_family_picker.dart';

import '../fake_desktop.dart';
import 'controller_test_host.dart';

void main() {
  for (final size in [const Size(1100, 760), const Size(920, 680)]) {
    testWidgets('鼠标切换中英文时更新设置及三种历史，保留语言选择 $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
      final desktop = FakeDesktop();
      final controller = AppController(desktop);
      await controller.initialize();
      addTearDown(desktop.input.close);
      await tester.pumpWidget(ControllerTestHost(controller: controller));
      await tester.pumpAndSettle();
      expect(find.text('取色历史'), findsOneWidget);

      final preferences = find.byKey(const ValueKey('open-preferences'));
      await tester.tap(preferences, kind: ui.PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      final language = find.byKey(const ValueKey('app-language'));
      await tester.tap(language, kind: ui.PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      await tester.tap(
        find.text('English').last,
        kind: ui.PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(controller.language, AppLanguage.en);
      expect(controller.locale.languageCode, 'en');
      expect(find.text('Language'), findsOneWidget);
      expect(find.text('Make it your own'), findsOneWidget);
      expect(find.text('按你的习惯工作'), findsNothing);

      await tester.tap(preferences, kind: ui.PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(find.text('Color history'), findsOneWidget);
      expect(find.text('No colors yet'), findsOneWidget);
      await tester.tap(
        find.text('Measurement history'),
        kind: ui.PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(find.text('No matching measurements'), findsOneWidget);
      expect(
        find.widgetWithText(TextField, 'Search name, size, display, or date'),
        findsOneWidget,
      );
      await tester.tap(
        find.text('Screenshot history'),
        kind: ui.PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(find.text('No screenshots yet'), findsOneWidget);

      await tester.tap(preferences, kind: ui.PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      await tester.tap(language, kind: ui.PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      await tester.tap(
        find.text('简体中文').last,
        kind: ui.PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(controller.language, AppLanguage.zh);
      expect(find.text('按你的习惯工作'), findsOneWidget);
      expect(find.text('语言'), findsOneWidget);

      tester.binding.platformDispatcher.localesTestValue = [
        const Locale('en', 'GB'),
      ];
      await tester.pumpAndSettle();
      expect(find.text('按你的习惯工作'), findsOneWidget);
      await tester.tap(language, kind: ui.PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      await tester.tap(
        find.text('跟随系统').last,
        kind: ui.PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(controller.language, AppLanguage.system);
      expect(find.text('Make it your own'), findsOneWidget);
      expect(desktop.beginCalls, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('英文截图标注工具条和文字属性使用当前语言', (tester) async {
    tester.view.physicalSize = const Size(920, 680);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final desktop = FakeDesktop()
      ..capture = CaptureSession(7, [
        CapturedDisplay(
          id: 1,
          name: '用户显示器',
          frame: PixelFrame(
            width: 640,
            height: 480,
            logicalWidth: 640,
            logicalHeight: 480,
            rgba: Uint8List.fromList(
              List.generate(640 * 480 * 4, (i) => i % 4 == 3 ? 255 : 200),
            ),
          ),
        ),
      ]);
    final controller = AppController(desktop);
    await controller.initialize();
    await controller.setLanguage(AppLanguage.en);
    addTearDown(desktop.input.close);
    await tester.pumpWidget(ControllerTestHost(controller: controller));
    await controller.startScreenshot();
    desktop.pointer(x: 100, y: 100, phase: 'down');
    desktop.pointer(x: 500, y: 350, phase: 'up');
    for (
      var i = 0;
      i < 100 && (!controller.screenshotEditing || controller.imageLoading);
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.byTooltip('Shapes: rectangle / ellipse'), findsOneWidget);
    expect(find.byTooltip('Copy and finish ↵'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('annotation-tool-text')),
      kind: ui.PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Font size'), findsOneWidget);
    expect(
      find.byTooltip('Text outline (automatic black or white contrast)'),
      findsOneWidget,
    );
    expect(find.byTooltip('Font: PingFang SC'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('独立字体菜单使用英文搜索提示和空结果', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: FontFamilyPicker(
            families: const ['用户字体'],
            selected: '用户字体',
            onSelected: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Search fonts'), findsOneWidget);
    expect(find.text('用户字体'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'missing');
    await tester.pumpAndSettle();
    expect(find.text('No matching fonts'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
