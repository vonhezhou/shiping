import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fruler/app/app_controller.dart';
import 'package:fruler/core/core.dart';
import 'package:fruler/platform/desktop_service.dart';

import '../fake_desktop.dart';
import 'controller_test_host.dart';

var parameterPointer = 20000;

Future<void> setSlider(
  WidgetTester tester,
  String key,
  double value, {
  AppController? controller,
}) async {
  final finder = find.byKey(ValueKey(key));
  final slider = tester.widget<Slider>(finder);
  final rect = tester.getRect(finder);
  Offset at(double v) => Offset(
    (rect.left +
            6 +
            (rect.width - 12) * ((v - slider.min) / (slider.max - slider.min)))
        .clamp(rect.left + 6.01, rect.right - 6.01),
    rect.center.dy,
  );
  final before = controller == null
      ? null
      : List<Annotation>.of(controller.markup.items);
  final id = parameterPointer++;
  final mouse = TestGesture(
    dispatcher: tester.sendEventToBinding,
    pointer: id,
    device: id,
    kind: ui.PointerDeviceKind.mouse,
  );
  await mouse.addPointer(location: at(slider.value));
  await mouse.down(at(slider.value));
  await tester.pump();
  await mouse.moveTo(at((slider.value + value) / 2));
  await tester.pump();
  await mouse.moveTo(at(value));
  await tester.pump();
  if (before != null) {
    expect(controller!.markup.items, before, reason: '滑杆拖动期间只预览，不连续写入历史');
  }
  await mouse.up();
  await mouse.removePointer();
  await tester.pumpAndSettle();
  expect(tester.widget<Slider>(finder).value, closeTo(value, .5));
}

Future<void> wheel(
  WidgetTester tester,
  Offset position, {
  double dy = -20,
  double dx = 0,
  double? expectedWidth,
}) async {
  final id = parameterPointer++;
  final mouse = TestGesture(
    dispatcher: tester.sendEventToBinding,
    pointer: id,
    device: id,
    kind: ui.PointerDeviceKind.mouse,
  );
  await mouse.addPointer(location: position);
  await mouse.moveTo(position);
  await tester.sendEventToBinding(
    PointerScrollEvent(
      device: id,
      position: position,
      scrollDelta: Offset(dx, dy),
      kind: ui.PointerDeviceKind.mouse,
    ),
  );
  await tester.pumpAndSettle();
  if (expectedWidth != null) {
    expect(
      tester
          .getSize(find.byKey(const ValueKey('annotation-brush-cursor')))
          .width,
      expectedWidth,
    );
  }
  await mouse.removePointer();
  await tester.pumpAndSettle();
}

void main() {
  for (final ratio in [1, 2, 3]) {
    for (final size in [const Size(1100, 760), const Size(920, 680)]) {
      testWidgets('pt 线宽、光标和原位字号 ${ratio}x $size', (tester) async {
        tester.view.physicalSize = size * ratio.toDouble();
        tester.view.devicePixelRatio = ratio.toDouble();
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final d = FakeDesktop()
          ..capture = CaptureSession(7, [
            CapturedDisplay(
              id: 1,
              name: 'screen',
              frame: PixelFrame(
                width: 640 * ratio,
                height: 480 * ratio,
                logicalWidth: 640,
                logicalHeight: 480,
                rgba: Uint8List.fromList([
                  for (var i = 0; i < 640 * 480 * ratio * ratio; i++) ...[
                    200,
                    210,
                    220,
                    255,
                  ],
                ]),
              ),
            ),
          ]);
        final c = AppController(d);
        await c.initialize();
        addTearDown(d.input.close);
        await tester.pumpWidget(ControllerTestHost(controller: c));
        await tester.pumpAndSettle();
        await c.startScreenshot();
        d.pointer(x: 100, y: 100, phase: 'down');
        d.pointer(x: 500, y: 350, phase: 'up');
        for (var i = 0; i < 150; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
          final copy = find.byKey(const ValueKey('copy-screenshot'));
          if (copy.evaluate().isNotEmpty &&
              tester.widget<IconButton>(copy).onPressed != null) {
            break;
          }
        }
        await tester.tap(find.byKey(const ValueKey('annotation-tool-marker')));
        await tester.pumpAndSettle();
        final origin = tester.getTopLeft(
          find.byKey(const ValueKey('annotation-canvas')),
        );
        final widthControl = find.byKey(const ValueKey('annotation-width'));
        await tester.tap(widthControl, kind: ui.PointerDeviceKind.mouse);
        await tester.pumpAndSettle();
        expect(find.byType(PopupMenuItem<double>), findsNothing);
        expect(tester.widget<IconButton>(widthControl).isSelected, true);
        await tester.tap(widthControl, kind: ui.PointerDeviceKind.mouse);
        await tester.pumpAndSettle();
        expect(tester.widget<IconButton>(widthControl).isSelected, true);
        await wheel(tester, tester.getCenter(widthControl));
        expect(find.byTooltip('线宽 13 pt · 滚轮 / 1、2 / [、]'), findsOneWidget);
        await wheel(tester, tester.getCenter(widthControl), dy: 20);

        await wheel(tester, origin + const Offset(80, 80), expectedWidth: 13);
        expect(find.byTooltip('线宽 13 pt · 滚轮 / 1、2 / [、]'), findsOneWidget);
        await tester.dragFrom(
          origin + const Offset(80, 80),
          const Offset(60, 0),
          kind: ui.PointerDeviceKind.mouse,
        );
        await tester.pumpAndSettle();
        expect(c.markup.items.last.width, 13 * ratio);
        await tester.tap(widthControl, kind: ui.PointerDeviceKind.mouse);
        await tester.pumpAndSettle();
        await wheel(tester, tester.getCenter(widthControl));
        expect(c.markup.items.last.width, 14 * ratio);
        await wheel(tester, tester.getCenter(widthControl), dy: 20);
        expect(c.markup.items.last.width, 13 * ratio);

        await tester.sendKeyEvent(LogicalKeyboardKey.bracketRight);
        await tester.pumpAndSettle();
        expect(c.markup.items.last.width, 14 * ratio);
        await tester.tap(find.byKey(const ValueKey('annotation-tool-text')));
        await tester.pumpAndSettle();
        await tester.tapAt(
          origin + const Offset(80, 150),
          kind: ui.PointerDeviceKind.mouse,
        );
        await tester.pumpAndSettle();
        final input = find.byKey(const ValueKey('annotation-text-input'));
        expect(tester.widget<TextField>(input).style!.fontSize, 24);
        await tester.enterText(input, 'pt text');
        await tester.tap(
          find.byKey(const ValueKey('annotation-font-family')),
          kind: ui.PointerDeviceKind.mouse,
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('annotation-font-search')),
          'no matching font',
        );
        await tester.pumpAndSettle();
        expect(find.text('没有匹配的字体'), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('annotation-font-search')),
          findsNothing,
        );
        expect(tester.widget<TextField>(input).controller!.text, 'pt text');
        expect(
          tester.widget<TextField>(input).style!.fontFamily,
          Annotation.defaultFontFamily,
        );
        await tester.tap(
          find.byKey(const ValueKey('annotation-font-family')),
          kind: ui.PointerDeviceKind.mouse,
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('annotation-font-search')),
          'comic',
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('annotation-font-option-Comic Sans MS')),
          kind: ui.PointerDeviceKind.mouse,
        );
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(input).style!.fontFamily,
          'Comic Sans MS',
        );
        await tester.tap(
          find.byKey(const ValueKey('annotation-font')),
          kind: ui.PointerDeviceKind.mouse,
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('36 pt'));
        await tester.tap(find.text('36 pt'), kind: ui.PointerDeviceKind.mouse);
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(input).style!.fontSize, 36);

        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        await tester.pumpAndSettle();
        expect(c.markup.items.last.fontSize, 36 * ratio);
        expect(c.markup.items.last.fontFamily, 'Comic Sans MS');
        await tester.tap(
          find.byKey(const ValueKey('annotation-font-family')),
          kind: ui.PointerDeviceKind.mouse,
        );
        await tester.pumpAndSettle();
        final beforeSearch = List<Annotation>.of(c.markup.items);
        final search = find.byKey(const ValueKey('annotation-font-search'));
        await tester.enterText(search, 'comic 12');
        for (final key in [
          LogicalKeyboardKey.keyC,
          LogicalKeyboardKey.keyM,
          LogicalKeyboardKey.space,
          LogicalKeyboardKey.digit1,
          LogicalKeyboardKey.digit2,
        ]) {
          await tester.sendKeyEvent(key);
        }
        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        await tester.pumpAndSettle();
        expect(c.screenshotEditing, true);
        expect(c.markup.items, beforeSearch);
        await tester.enterText(search, 'menlo');
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('annotation-font-option-Menlo')),
          kind: ui.PointerDeviceKind.mouse,
        );
        await tester.pumpAndSettle();
        expect(c.markup.items.last.fontFamily, 'Menlo');
        await tester.tap(find.byKey(const ValueKey('annotation-undo')));
        await tester.pumpAndSettle();
        expect(c.markup.items.last.fontFamily, 'Comic Sans MS');
        await tester.tap(find.byKey(const ValueKey('annotation-redo')));
        await tester.pumpAndSettle();
        expect(c.markup.items.last.fontFamily, 'Menlo');
        await tester.tap(
          find.byKey(const ValueKey('annotation-font')),
          kind: ui.PointerDeviceKind.mouse,
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('48 pt'));
        await tester.tap(find.text('48 pt'), kind: ui.PointerDeviceKind.mouse);
        await tester.pumpAndSettle();
        expect(c.markup.items.last.fontSize, 48 * ratio);
        expect(
          c.markup.items.last.bounds.height,
          greaterThanOrEqualTo(48 * ratio),
        );
        await tester.tap(find.byKey(const ValueKey('annotation-undo')));
        await tester.pumpAndSettle();
        expect(c.markup.items.last.fontSize, 36 * ratio);
        await tester.tap(find.byKey(const ValueKey('annotation-edit-text')));
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(input).style!.fontSize, 36);
        expect(tester.widget<TextField>(input).style!.fontFamily, 'Menlo');
        expect(tester.takeException(), isNull);
      });
    }
  }
  for (final size in [const Size(1100, 760), const Size(920, 680)]) {
    testWidgets('Snipaste 工具分组、原位文字和快捷操作 $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final d = FakeDesktop()
        ..capture = CaptureSession(7, [
          CapturedDisplay(
            id: 1,
            name: 'screen',
            frame: PixelFrame(
              width: 640,
              height: 480,
              logicalWidth: 640,
              logicalHeight: 480,
              rgba: Uint8List.fromList([
                for (var i = 0; i < 640 * 480; i++) ...[200, 210, 220, 255],
              ]),
            ),
          ),
        ]);
      final c = AppController(d);
      await c.initialize();
      addTearDown(d.input.close);
      await tester.pumpWidget(ControllerTestHost(controller: c));
      await tester.pumpAndSettle();
      await c.startScreenshot();
      d.pointer(x: 100, y: 100, phase: 'down');
      d.pointer(x: 500, y: 350, phase: 'up');
      for (var i = 0; i < 150; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
        final copy = find.byKey(const ValueKey('copy-screenshot'));
        if (copy.evaluate().isNotEmpty &&
            tester.widget<IconButton>(copy).onPressed != null) {
          break;
        }
      }
      await tester.pumpAndSettle();
      final toolbar = find.byKey(const ValueKey('annotation-toolbar'));
      expect(tester.getSize(toolbar).height, lessThanOrEqualTo(40));
      expect(tester.getSize(toolbar).width, lessThan(500));
      expect(tester.getRect(toolbar).right, closeTo(500, 1));
      final redo = find.byKey(const ValueKey('annotation-redo'));
      final cancel = find.byKey(const ValueKey('cancel-screenshot'));
      expect(
        tester.getRect(cancel).left - tester.getRect(redo).right,
        lessThanOrEqualTo(12),
        reason: '历史与完成操作之间只保留紧凑的分隔线',
      );
      for (final id in ['annotation-group-shape', 'annotation-group-line']) {
        final button = tester.widget<IconButton>(find.byKey(ValueKey(id)));
        expect(button.icon, isNot(isA<Stack>()), reason: '工具图标不显示更新红点');
      }
      expect(find.byKey(const ValueKey('annotation-properties')), findsNothing);
      expect(
        find.byKey(const ValueKey('annotation-tool-select')),
        findsNothing,
      );
      // Before annotating, selection movement and handles reuse the frozen frame.
      final cropCanvas = find.byKey(const ValueKey('annotation-canvas'));
      await tester.dragFrom(
        tester.getCenter(cropCanvas),
        const Offset(20, 10),
        kind: ui.PointerDeviceKind.mouse,
      );
      for (var i = 0; i < 100; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
        if (!c.imageLoading && c.screenshotSelection!.left == 120) break;
      }
      expect(c.screenshotSelection!.left, 120);
      expect(c.screenshotSelection!.top, 110);
      final handle = find.byKey(const ValueKey('screenshot-handle-se'));
      await tester.drag(
        handle,
        const Offset(20, 20),
        kind: ui.PointerDeviceKind.mouse,
      );
      for (var i = 0; i < 100; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
        if (!c.imageLoading && c.screenshotSelection!.right == 540) break;
      }
      expect(c.screenshotSelection!.right, 540);
      expect(d.beginCalls, 1);
      expect(d.finishCalls, 0);
      for (var i = 0; i < 150; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
        if (tester
                .widget<IconButton>(
                  find.byKey(const ValueKey('copy-screenshot')),
                )
                .onPressed !=
            null) {
          break;
        }
      }

      await tester.tap(find.byKey(const ValueKey('annotation-group-shape')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('annotation-tool-rectangle')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('annotation-tool-ellipse')),
        findsOneWidget,
      );
      final properties = find.byKey(const ValueKey('annotation-properties'));
      expect(tester.getSize(properties).height, 32);
      expect(tester.getSize(properties).width, lessThanOrEqualTo(310));
      expect(tester.getRect(properties).left, tester.getRect(toolbar).left);
      expect(
        tester.getRect(properties).top - tester.getRect(toolbar).bottom,
        4,
      );
      await tester.tap(find.byKey(const ValueKey('annotation-fill')));
      await tester.sendKeyEvent(LogicalKeyboardKey.bracketRight);
      final canvas = find.byKey(const ValueKey('annotation-canvas'));
      final origin = tester.getTopLeft(canvas);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.dragFrom(
        origin + const Offset(40, 50),
        const Offset(60, 30),
        kind: ui.PointerDeviceKind.mouse,
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      final shape = c.markup.items.single;
      expect(shape.bounds.width, shape.bounds.height);
      expect(shape.toJson()['filled'], true);
      expect(shape.width, 3);
      expect(
        tester.getRect(cancel).left -
            tester
                .getRect(find.byKey(const ValueKey('annotation-delete')))
                .right,
        lessThanOrEqualTo(12),
      );
      await tester.tap(find.byKey(const ValueKey('annotation-group-line')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('annotation-group-shape')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('annotation-tool-ellipse')));
      await tester.pumpAndSettle();
      await tester.dragFrom(
        origin + const Offset(120, 50),
        const Offset(40, 40),
        kind: ui.PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(c.markup.items.last.filled, true);
      expect(c.markup.items.last.width, 3);
      await tester.tap(find.byKey(const ValueKey('annotation-undo')));
      await tester.pumpAndSettle();
      expect(c.markup.items, hasLength(1));
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(toolbar, findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(toolbar, findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('annotation-group-line')));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey('annotation-tool-line')),
            )
            .isSelected,
        true,
      );
      await tester.tapAt(
        origin + const Offset(160, 70),
        kind: ui.PointerDeviceKind.mouse,
      );
      await tester.tapAt(
        origin + const Offset(190, 100),
        kind: ui.PointerDeviceKind.mouse,
      );
      final right = await tester.createGesture(
        kind: ui.PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await right.down(origin + const Offset(220, 70));
      await right.up();
      await tester.pumpAndSettle();
      expect(c.markup.items.length, 2);
      expect(c.markup.items.last.kind, AnnotationKind.line);
      expect(find.byKey(const ValueKey('annotation-properties')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('annotation-tool-text')));
      await tester.pumpAndSettle();
      await tester.tapAt(
        origin + const Offset(80, 150),
        kind: ui.PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      final input = find.byKey(const ValueKey('annotation-text-input'));
      expect(input, findsOneWidget);
      expect(
        tester.getRect(canvas).contains(tester.getRect(input).topLeft),
        true,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(toolbar, findsOneWidget);
      await tester.enterText(input, '原位文字\n第二行');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
      expect(input, findsNothing);
      expect(c.markup.items.last.text, '原位文字\n第二行');
      await tester.tap(find.byKey(const ValueKey('annotation-bold')));
      await tester.pumpAndSettle();
      expect(c.markup.items.last.toJson()['bold'], true);
      await tester.tap(find.byKey(const ValueKey('annotation-edit-text')));
      await tester.pumpAndSettle();
      await tester.enterText(input, '取消这次编辑');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(c.markup.items.last.text, '原位文字\n第二行');
      await tester.tap(find.byKey(const ValueKey('annotation-edit-text')));
      await tester.pumpAndSettle();
      await tester.enterText(input, '应被撤销的文字编辑');
      await tester.tap(find.byKey(const ValueKey('annotation-undo')));
      await tester.pumpAndSettle();
      expect(input, findsNothing);
      expect(c.markup.items.last.text, '原位文字\n第二行');
      expect(c.screenshotEditing, true);
      for (final kind in ['mosaic', 'blur']) {
        if (find.byKey(ValueKey('annotation-tool-$kind')).evaluate().isEmpty) {
          await tester.tap(
            find.byKey(const ValueKey('annotation-group-effect')),
          );
          await tester.pumpAndSettle();
        }
        await tester.tap(find.byKey(ValueKey('annotation-tool-$kind')));
        await tester.pumpAndSettle();
        expect(find.byType(Slider), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('annotation-effect-brush')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('annotation-effect-width')),
          findsNothing,
        );
        expect(find.byKey(const ValueKey('annotation-width')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('annotation-effect-strength')),
          findsOneWidget,
        );
        expect(find.byType(Slider), findsOneWidget);
        await setSlider(tester, 'annotation-effect-strength', 5);
        final point = origin + const Offset(30, 30);
        await wheel(tester, point);
        await wheel(tester, point);
        expect(
          tester
              .widget<Slider>(
                find.byKey(const ValueKey('annotation-effect-strength')),
              )
              .value,
          5,
        );
        await tester.dragFrom(
          point,
          const Offset(120, 80),
          kind: ui.PointerDeviceKind.mouse,
        );
        await tester.pumpAndSettle();
        final brush = c.markup.items.last;
        expect(brush.kind.name, kind);
        expect(brush.effectBrush, true);
        expect(brush.effectStrength, 5);
        expect(brush.width, greaterThan(24));
        final count = c.markup.items.length;
        await setSlider(tester, 'annotation-effect-strength', 1, controller: c);
        expect(c.markup.items.length, count);
        expect(c.markup.items.last.width, brush.width);
        expect(c.markup.items.last.effectStrength, 1);
        await tester.tap(find.byKey(const ValueKey('annotation-undo')));
        await tester.pumpAndSettle();
        expect(c.markup.items.last, brush);
        // A fresh tool selection restores the chosen brush settings.
        await tester.tap(
          find.byKey(const ValueKey('annotation-effect-rectangle')),
        );
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<IconButton>(
                find.byKey(const ValueKey('annotation-width')),
              )
              .isSelected,
          false,
        );
        await setSlider(tester, 'annotation-effect-strength', 2);
        await tester.tap(find.byKey(const ValueKey('annotation-effect-brush')));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<Slider>(
                find.byKey(const ValueKey('annotation-effect-strength')),
              )
              .value,
          2,
        );
        await tester.tap(
          find.byKey(const ValueKey('annotation-effect-rectangle')),
        );
        await tester.pumpAndSettle();
        await setSlider(tester, 'annotation-effect-strength', 5);
        await tester.dragFrom(
          origin + const Offset(200, 30),
          const Offset(60, 50),
          kind: ui.PointerDeviceKind.mouse,
        );
        await tester.pumpAndSettle();
        expect(c.markup.items.last.effectBrush, false);
        expect(c.markup.items.last.effectStrength, 5);
      }
      await tester.tap(find.byKey(const ValueKey('annotation-tool-marker')));
      await tester.pumpAndSettle();
      final markerPoint = origin + const Offset(30, 180);
      final widthButton = find.byKey(const ValueKey('annotation-width'));
      final widthButtonSize = tester.getSize(widthButton);
      await wheel(tester, markerPoint, expectedWidth: 13);
      expect(
        find.descendant(of: widthButton, matching: find.text('13')),
        findsOneWidget,
      );
      await wheel(tester, markerPoint, dy: 20, expectedWidth: 12);
      expect(
        find.descendant(of: widthButton, matching: find.text('12')),
        findsNothing,
      );
      await wheel(tester, markerPoint, dy: 0, dx: 20, expectedWidth: 12);
      await wheel(tester, markerPoint, dy: 0);
      await wheel(tester, markerPoint);
      await tester.dragFrom(
        markerPoint,
        const Offset(100, 0),
        kind: ui.PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(c.markup.items.last.kind, AnnotationKind.marker);
      expect(c.markup.items.last.width, 13);
      expect(find.byTooltip('线宽 13 pt · 滚轮 / 1、2 / [、]'), findsOneWidget);
      await tester.tap(widthButton, kind: ui.PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(find.byType(PopupMenuItem<double>), findsNothing);
      expect(tester.widget<IconButton>(widthButton).isSelected, true);
      await wheel(tester, tester.getCenter(widthButton));
      expect(c.markup.items.last.width, 14);
      expect(tester.getSize(widthButton), widthButtonSize);
      await tester.tap(widthButton, kind: ui.PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(tester.widget<IconButton>(widthButton).isSelected, true);
      await wheel(tester, tester.getCenter(widthButton), dy: 20);
      await wheel(tester, tester.getCenter(widthButton), dy: 20);
      expect(c.markup.items.last.width, 12);
      expect(
        find.descendant(of: widthButton, matching: find.text('12')),
        findsNothing,
      );
      expect(tester.getSize(widthButton), widthButtonSize);
      expect(c.busy, true);
      expect(d.showMainCalls, 0);
      expect(tester.takeException(), isNull);
    });
    testWidgets('工具栏在屏幕右下角翻到选区上方且属性条不溢出 $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final d = FakeDesktop()
        ..capture = CaptureSession(7, [
          CapturedDisplay(
            id: 1,
            name: 'screen',
            frame: PixelFrame(
              width: size.width.toInt(),
              height: size.height.toInt(),
              logicalWidth: size.width,
              logicalHeight: size.height,
              rgba: Uint8List(size.width.toInt() * size.height.toInt() * 4),
            ),
          ),
        ]);
      final c = AppController(d);
      await c.initialize();
      addTearDown(d.input.close);
      await tester.pumpWidget(ControllerTestHost(controller: c));
      await tester.pumpAndSettle();
      await c.startScreenshot();
      d.pointer(x: size.width - 200, y: size.height - 100, phase: 'down');
      d.pointer(x: size.width - 12, y: size.height - 12, phase: 'up');
      for (var i = 0; i < 150; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
        final copy = find.byKey(const ValueKey('copy-screenshot'));
        if (copy.evaluate().isNotEmpty &&
            tester.widget<IconButton>(copy).onPressed != null) {
          break;
        }
      }
      await tester.pumpAndSettle();
      final toolbar = find.byKey(const ValueKey('annotation-toolbar'));
      expect(tester.getRect(toolbar).bottom, lessThan(size.height - 100));
      await tester.tap(find.byKey(const ValueKey('annotation-tool-text')));
      await tester.pumpAndSettle();
      final properties = find.byKey(const ValueKey('annotation-properties'));
      expect(
        tester.getRect(properties).bottom,
        lessThanOrEqualTo(tester.getRect(toolbar).top - 4),
      );
      expect(
        (Offset.zero & size).contains(tester.getRect(properties).topLeft),
        true,
      );
      expect(
        (Offset.zero & size).contains(tester.getRect(properties).bottomRight),
        true,
      );
      await tester.tap(
        find.byKey(const ValueKey('annotation-font-family')),
        kind: ui.PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      final picker = tester.getRect(
        find.byKey(const ValueKey('annotation-font-picker')),
      );
      expect((Offset.zero & size).contains(picker.topLeft), true);
      expect((Offset.zero & size).contains(picker.bottomRight), true);
      await tester.tapAt(
        const Offset(10, 10),
        kind: ui.PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('annotation-font-search')),
        findsNothing,
      );
      expect(c.screenshotEditing, true);
      expect(c.markup.items, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }
}
