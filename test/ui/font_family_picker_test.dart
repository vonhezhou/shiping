import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fruler/ui/font_family_picker.dart';
import 'package:fruler/l10n/app_localizations.dart';

void main() {
  for (final size in [const Size(1100, 760), const Size(920, 680)]) {
    testWidgets('大量字体按需构建，搜索和空结果不修改样式 $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final families = List.generate(
        5000,
        (i) => 'Family ${i.toString().padLeft(5, '0')}',
      );
      final selections = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData.dark(),
          home: Scaffold(
            body: Center(
              child: FontFamilyPicker(
                families: families,
                selected: families.first,
                onSelected: selections.add,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ListTile).evaluate().length, lessThan(30));
      expect(
        find.byKey(ValueKey('annotation-font-option-${families.last}')),
        findsNothing,
      );
      expect(
        tester.widget<ListTile>(find.byType(ListTile).first).selected,
        true,
      );
      final listCenter = tester.getCenter(
        find.byKey(const ValueKey('annotation-font-list')),
      );
      final mouse = await tester.createGesture(
        kind: ui.PointerDeviceKind.mouse,
      );
      await mouse.addPointer(location: listCenter);
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: listCenter,
          scrollDelta: const Offset(0, 1200),
          kind: ui.PointerDeviceKind.mouse,
        ),
      );
      await mouse.removePointer();
      await tester.pumpAndSettle();
      expect(
        find.byKey(ValueKey('annotation-font-option-${families.first}')),
        findsNothing,
      );
      final search = find.byKey(const ValueKey('annotation-font-search'));
      await tester.enterText(search, '  FAMILY 04999  ');
      await tester.pumpAndSettle();
      expect(find.byType(ListTile), findsOneWidget);
      expect(selections, isEmpty);
      await tester.tap(find.byType(ListTile), kind: ui.PointerDeviceKind.mouse);
      expect(selections, [families.last]);
      await tester.enterText(search, 'no matching font');
      await tester.pumpAndSettle();
      expect(find.text('没有匹配的字体'), findsOneWidget);
      expect(find.byType(ListTile), findsNothing);
      expect(selections, [families.last]);
      await tester.enterText(search, '');
      await tester.pumpAndSettle();
      expect(
        find.byKey(ValueKey('annotation-font-option-${families.first}')),
        findsOneWidget,
      );
      expect(find.byType(ListTile).evaluate().length, lessThan(30));
      expect(tester.takeException(), isNull);
    });
  }
}
