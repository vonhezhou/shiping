import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fruler/app/app_controller.dart';
import 'package:fruler/core/core.dart';
import 'package:fruler/l10n/app_language.dart';

import '../fake_desktop.dart';
import 'controller_test_host.dart';

Future<void> click(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder, kind: ui.PointerDeviceKind.mouse);
  await tester.pumpAndSettle();
}

Future<void> choose(WidgetTester tester, String key, String label) async {
  await click(tester, find.byKey(ValueKey(key)));
  await click(tester, find.text(label).last);
}

void main() {
  for (final language in [AppLanguage.zh, AppLanguage.en]) {
    for (final size in [const Size(1100, 760), const Size(920, 680)]) {
      testWidgets('历史限制、独立鼠标动作与颜色模板编辑 ${language.name} $size', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final desktop = FakeDesktop();
        final controller = AppController(desktop);
        await controller.initialize();
        await controller.setLanguage(language);
        addTearDown(desktop.input.close);
        await tester.pumpWidget(ControllerTestHost(controller: controller));
        await tester.pumpAndSettle();
        await click(tester, find.byKey(const ValueKey('nav-picker')));
        await choose(
          tester,
          'picker-right-action',
          controller.pickerActionLabel(PickerMouseAction.pickAndContinue),
        );
        await choose(
          tester,
          'picker-middle-action',
          controller.pickerActionLabel(PickerMouseAction.cancel),
        );
        expect(
          controller.pickerBehavior.secondary,
          PickerMouseAction.pickAndContinue,
        );
        expect(controller.pickerBehavior.middle, PickerMouseAction.cancel);
        expect(controller.continuousPicker, false);
        await choose(
          tester,
          'picker-history-limit',
          controller.strings.uiHistoryItemCount(16),
        );
        expect(controller.colorHistoryLimit, 16);

        await click(
          tester,
          find.byKey(const ValueKey('color-format-settings')),
        );
        await click(tester, find.byKey(const ValueKey('format-add')));
        await tester.enterText(
          find.byKey(const ValueKey('format-name')),
          'Channels',
        );
        await tester.enterText(
          find.byKey(const ValueKey('format-template')),
          '%ZZ',
        );
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<FilledButton>(find.byKey(const ValueKey('format-save')))
              .onPressed,
          isNull,
        );
        await tester.enterText(
          find.byKey(const ValueKey('format-template')),
          '%Re/%Gr/%Bl',
        );
        await tester.pumpAndSettle();
        expect(find.text('215/250/107'), findsOneWidget);
        await click(tester, find.byKey(const ValueKey('format-save')));
        expect(controller.colorOutputs.last.name, 'Channels');
        await choose(tester, 'picker-format', 'Channels');
        expect(controller.formatColor(const RgbColor(1, 2, 3)), '1/2/3');
        final id = controller.activeColorOutput.id;
        await click(tester, find.byKey(ValueKey('format-edit-$id')));
        await tester.enterText(
          find.byKey(const ValueKey('format-template')),
          '#%Rex%Grx%Blx',
        );
        await tester.pumpAndSettle();
        expect(find.text('#d7fa6b'), findsOneWidget);
        await click(tester, find.byKey(const ValueKey('format-save')));
        expect(
          controller.formatColor(const RgbColor(171, 205, 239)),
          '#abcdef',
        );
        await click(tester, find.byKey(ValueKey('format-actions-$id')));
        await click(tester, find.text(controller.strings.uiMoveUp));
        expect(
          controller.colorOutputs[controller.colorOutputs.length - 2].id,
          id,
        );
        await click(tester, find.byKey(ValueKey('format-enabled-$id')));
        expect(controller.activeColorOutput.id, 'hex');

        await click(tester, find.byKey(const ValueKey('nav-ruler')));
        await choose(
          tester,
          'ruler-history-limit',
          controller.strings.uiHistoryItemCount(16),
        );
        expect(controller.measurementHistoryLimit, 16);
        await click(tester, find.byKey(const ValueKey('nav-picker')));
        expect(
          controller.pickerBehavior.secondary,
          PickerMouseAction.pickAndContinue,
        );
        expect(controller.colorHistoryLimit, 16);
        final restored = AppController(desktop);
        try {
          await restored.initialize();
          expect(restored.pickerBehavior.middle, PickerMouseAction.cancel);
          expect(
            restored.pickerBehavior.secondary,
            PickerMouseAction.pickAndContinue,
          );
          expect(restored.colorHistoryLimit, 16);
          expect(restored.measurementHistoryLimit, 16);
          expect(
            restored.colorOutputs.where((f) => f.id == id).single.template,
            '#%Rex%Grx%Blx',
          );
        } finally {
          restored.dispose();
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
}
