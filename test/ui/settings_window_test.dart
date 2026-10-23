import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fruler/app/app_controller.dart';
import 'package:fruler/core/core.dart';
import 'package:fruler/l10n/app_language.dart';
import 'package:fruler/platform/desktop_service.dart';

import '../fake_desktop.dart';
import 'controller_test_host.dart';

class _OptionsDesktop extends FakeDesktop {
  String? lastTool;
  @override
  Future<CaptureSession> begin(String tool) async {
    lastTool = tool;
    return super.begin(tool);
  }
}

Future<void> _mouseClick(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder, kind: ui.PointerDeviceKind.mouse);
  await tester.pumpAndSettle();
}

Future<void> _selectOption(
  WidgetTester tester,
  String key,
  String option,
) async {
  await _mouseClick(tester, find.byKey(ValueKey(key)));
  await _mouseClick(tester, find.text(option).last);
}

Future<void> _seedScreenshot(
  WidgetTester tester,
  AppController controller,
  _OptionsDesktop desktop,
) async {
  await controller.startScreenshot();
  desktop.pointer(x: 2, y: 2, phase: 'down');
  desktop.pointer(x: 14, y: 10, phase: 'up');
  await tester.pump();
  expect(controller.screenshotEditing, true, reason: controller.error);
  await tester.runAsync(() async {
    await controller.exportScreenshot(save: false);
    expect(controller.screenshots, hasLength(1), reason: controller.error);
  });
  await tester.pumpAndSettle();
}

void main() {
  for (final language in [AppLanguage.zh, AppLanguage.en]) {
    for (final size in [const Size(1100, 760), const Size(920, 680)]) {
      testWidgets('选项页归属、鼠标配置和历史保留 ${language.name} $size', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final measurement = MeasurementRecord(
          name: 'Retained measurement',
          favorite: true,
          measurement: const RulerMeasurement(
            rect: PixelRect(left: 1, top: 2, right: 11, bottom: 22),
            logicalWidth: 10,
            logicalHeight: 20,
            mode: RulerMode.rectangle,
          ),
          createdAt: DateTime(2026, 10, 23, 12),
          displayName: 'Retina display',
        );
        final desktop = _OptionsDesktop()
          ..saved = jsonEncode({
            'version': 1,
            'language': language.name,
            'colors': [
              [18, 52, 86],
            ],
            'measurements': [measurement.toJson()],
          })
          ..capture = CaptureSession(7, [
            CapturedDisplay(
              id: 1,
              name: 'Retina display',
              frame: PixelFrame(
                width: 16,
                height: 12,
                logicalWidth: 16,
                logicalHeight: 12,
                rgba: Uint8List.fromList([
                  for (var i = 0; i < 16 * 12; i++) ...[18, 52, 86, 255],
                ]),
              ),
            ),
          ]);
        final controller = AppController(desktop);
        await controller.initialize();
        addTearDown(desktop.input.close);
        expect(controller.section, AppSection.settings);
        // 在挂载窗口前通过截图业务流程准备内存历史，避免渲染器与编辑器争用图片缓存。
        await _seedScreenshot(tester, controller, desktop);
        controller.selectSection(AppSection.settings);
        await tester.pumpWidget(ControllerTestHost(controller: controller));
        await tester.pumpAndSettle();

        expect(controller.section, AppSection.settings);
        for (final tab in ['settings', 'picker', 'ruler', 'image']) {
          expect(find.byKey(ValueKey('nav-$tab')), findsOneWidget);
        }
        expect(find.byKey(const ValueKey('start-picker')), findsNothing);
        expect(find.byKey(const ValueKey('start-ruler')), findsNothing);
        expect(find.byKey(const ValueKey('start-screenshot')), findsNothing);
        expect(find.byKey(const ValueKey('picker-format')), findsNothing);
        expect(find.byKey(const ValueKey('ruler-tolerance')), findsNothing);

        final screenshot = controller.screenshots.single;
        final colors = List.of(controller.colors);
        final measurements = List.of(controller.measurements);

        await _mouseClick(tester, find.byKey(const ValueKey('nav-picker')));
        expect(controller.section, AppSection.picker);
        expect(
          find.byKey(const ValueKey('options-scroll-picker')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('picker-format')), findsOneWidget);
        expect(find.byKey(const ValueKey('picker-continuous')), findsOneWidget);
        expect(find.byKey(const ValueKey('picker-zoom')), findsOneWidget);
        expect(find.byKey(const ValueKey('color-history')), findsOneWidget);
        expect(find.byKey(const ValueKey('ruler-mode')), findsNothing);
        await _selectOption(tester, 'picker-format', 'RGB');
        await _mouseClick(
          tester,
          find.byKey(const ValueKey('picker-continuous')),
        );
        await _selectOption(tester, 'picker-zoom', '24×');
        expect(controller.selectedOutputId, 'rgb');
        expect(controller.continuousPicker, true);
        expect(controller.zoom, 24);

        await _mouseClick(tester, find.byKey(const ValueKey('nav-ruler')));
        expect(controller.section, AppSection.ruler);
        expect(
          find.byKey(const ValueKey('options-scroll-ruler')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('ruler-mode')), findsOneWidget);
        expect(find.byKey(const ValueKey('ruler-tolerance')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('measurement-search')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('picker-format')), findsNothing);
        await _selectOption(
          tester,
          'ruler-mode',
          controller.strings.uiModeCross,
        );
        final tolerance = find.byKey(const ValueKey('ruler-tolerance'));
        await tester.ensureVisible(tolerance);
        await tester.pumpAndSettle();
        final slider = tester.getRect(tolerance);
        await tester.tapAt(
          Offset(slider.left + slider.width * .75, slider.center.dy),
          kind: ui.PointerDeviceKind.mouse,
        );
        await tester.pumpAndSettle();
        final changedTolerance = controller.tolerance;
        expect(changedTolerance, greaterThan(16));
        expect(controller.mode, RulerMode.cross);

        await _mouseClick(tester, find.byKey(const ValueKey('nav-image')));
        expect(controller.section, AppSection.image);
        expect(
          find.byKey(const ValueKey('options-scroll-image')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('screenshot-history')),
          findsOneWidget,
        );
        expect(find.byType(Image), findsOneWidget);
        expect(find.byKey(const ValueKey('picker-format')), findsNothing);
        expect(find.byKey(const ValueKey('ruler-tolerance')), findsNothing);

        await _mouseClick(tester, find.byKey(const ValueKey('nav-settings')));
        expect(find.byKey(const ValueKey('app-language')), findsOneWidget);
        await _mouseClick(tester, find.byKey(const ValueKey('nav-picker')));
        expect(controller.selectedOutputId, 'rgb');
        expect(controller.zoom, 24);
        expect(controller.continuousPicker, true);
        expect(
          tester
              .widget<DropdownButton<String>>(
                find.byKey(const ValueKey('picker-format')),
              )
              .value,
          'rgb',
        );
        expect(
          tester
              .widget<DropdownButton<int>>(
                find.byKey(const ValueKey('picker-zoom')),
              )
              .value,
          24,
        );

        for (final (tab, key, tool) in [
          ('picker', 'start-picker', 'picker'),
          ('ruler', 'start-ruler', 'cross'),
          ('image', 'start-screenshot', 'screenshot'),
        ]) {
          await _mouseClick(tester, find.byKey(ValueKey('nav-$tab')));
          await _mouseClick(tester, find.byKey(ValueKey(key)));
          expect(desktop.lastTool, tool);
          expect(controller.busy, true);
          desktop.event('cancelled');
          await tester.pumpAndSettle();
          expect(controller.busy, false);
        }
        expect(controller.mode, RulerMode.cross);
        expect(controller.tolerance, changedTolerance);
        expect(controller.colors, colors);
        expect(controller.measurements, measurements);
        expect(controller.screenshots.single, same(screenshot));
        expect(controller.language, language);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
