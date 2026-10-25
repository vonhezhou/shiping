import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fruler/app/app_controller.dart';
import 'package:fruler/core/core.dart';
import 'package:fruler/l10n/app_language.dart';
import 'package:fruler/platform/desktop_service.dart';

import '../fake_desktop.dart';
import 'controller_test_host.dart';

class _RecordingDesktop extends FakeDesktop {
  String? selectedTool;
  RecordingOptions? startedWith;
  int stopCalls = 0;

  @override
  Future<CaptureSession> begin(String tool) async {
    selectedTool = tool;
    return super.begin(tool);
  }

  @override
  Future<void> startRecording(
    int sessionId,
    int displayId,
    PixelRect rect,
    RecordingOptions options,
  ) async {
    startedWith = options;
  }

  @override
  Future<bool> stopRecording() async {
    stopCalls++;
    return true;
  }
}

Future<void> _click(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder, kind: ui.PointerDeviceKind.mouse);
  await tester.pumpAndSettle();
}

Future<void> _choose(WidgetTester tester, String key, String text) async {
  await _click(tester, find.byKey(ValueKey(key)));
  await _click(tester, find.text(text).last);
}

void main() {
  for (final language in [AppLanguage.zh, AppLanguage.en]) {
    for (final size in [const Size(1100, 760), const Size(920, 680)]) {
      testWidgets('录屏参数保存、选区入口与录制中锁定 ${language.name} $size', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final desktop = _RecordingDesktop();
        final controller = AppController(desktop);
        await controller.initialize();
        await controller.setLanguage(language);
        addTearDown(desktop.input.close);
        await tester.pumpWidget(ControllerTestHost(controller: controller));
        await tester.pumpAndSettle();
        await _click(tester, find.byKey(const ValueKey('nav-recording')));
        expect(controller.section, AppSection.recording);
        expect(find.byKey(const ValueKey('picker-format')), findsNothing);

        await _choose(
          tester,
          'recording-codec',
          controller.strings.uiRecordingHevc,
        );
        await _choose(tester, 'recording-frame-rate', '60 fps');
        await _choose(
          tester,
          'recording-quality',
          controller.strings.uiRecordingQualityMedium,
        );
        await _choose(tester, 'recording-resolution', '720p');
        await _click(tester, find.byKey(const ValueKey('recording-cursor')));
        await _click(
          tester,
          find.byKey(const ValueKey('recording-system-audio')),
        );
        const expected = RecordingOptions(
          codec: 'hevc',
          frameRate: 60,
          quality: 'medium',
          resolution: '720p',
          showCursor: false,
          systemAudio: true,
        );
        expect(controller.recordingOptions, expected);
        final restored = AppController(desktop);
        try {
          await restored.initialize();
          expect(restored.recordingOptions, expected);
        } finally {
          restored.dispose();
        }

        await _click(tester, find.byKey(const ValueKey('start-recording')));
        expect(desktop.selectedTool, 'recording');
        expect(desktop.startedWith, isNull);
        desktop.pointer(x: .5, y: .5, phase: 'down');
        desktop.pointer(x: 3, y: 2.5, phase: 'up');
        await tester.pumpAndSettle();
        expect(desktop.startedWith, expected);
        expect(controller.screenRecording, isTrue);
        expect(
          tester
              .widget<DropdownButton<String>>(
                find.byKey(const ValueKey('recording-codec')),
              )
              .onChanged,
          isNull,
        );
        expect(
          tester
              .widget<SwitchListTile>(
                find.byKey(const ValueKey('recording-system-audio')),
              )
              .onChanged,
          isNull,
        );
        await _click(tester, find.byKey(const ValueKey('nav-picker')));
        expect(
          tester
              .widget<FilledButton>(find.byKey(const ValueKey('start-picker')))
              .onPressed,
          isNull,
        );
        await _click(tester, find.byKey(const ValueKey('nav-recording')));
        await _click(tester, find.byKey(const ValueKey('stop-recording')));
        expect(desktop.stopCalls, 1);
        expect(controller.screenRecording, isFalse);
        expect(controller.notice, controller.strings.msgRecordingSaved);
        expect(
          tester
              .widget<DropdownButton<String>>(
                find.byKey(const ValueKey('recording-codec')),
              )
              .onChanged,
          isNotNull,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }
}
