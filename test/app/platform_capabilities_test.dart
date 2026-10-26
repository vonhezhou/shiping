import 'package:flutter_test/flutter_test.dart';
import 'package:fruler/app/app_controller.dart';
import 'package:fruler/platform/desktop_service.dart';

import '../fake_desktop.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('未声明能力的平台默认不提供工具', () {
    expect(UnsupportedDesktopService().capabilities, isEmpty);
  });

  test('能力逐项判断，截图依赖不影响独立录屏，未授权不隐藏已实现能力', () async {
    final desktop = FakeDesktop()..permission = false;
    final c = AppController(desktop);
    addTearDown(c.dispose);
    addTearDown(desktop.input.close);
    await c.initialize();
    expect(c.permissionGranted, isFalse);
    for (final missing in DesktopFeature.values) {
      desktop.capabilities = DesktopFeature.values.toSet()..remove(missing);
      for (final feature in DesktopFeature.values) {
        final needsScreenshot =
            feature == DesktopFeature.qrCode ||
            feature == DesktopFeature.textRecognition;
        expect(
          c.supports(feature),
          feature != missing &&
              !(needsScreenshot && missing == DesktopFeature.screenshot),
          reason: 'missing=$missing, feature=$feature',
        );
      }
    }
    c.supported = false;
    expect(DesktopFeature.values.any(c.supports), isFalse);
  });

  test('部分能力的平台拦截直接调用和原生激活事件，保留支持的工具', () async {
    final desktop = FakeDesktop()..capabilities = {DesktopFeature.picker};
    final c = AppController(desktop);
    addTearDown(c.dispose);
    addTearDown(desktop.input.close);
    await c.initialize();
    c.selectSection(AppSection.recording);
    expect(c.section, AppSection.settings);
    await c.startRecording();
    await c.startQrCodeRecognition();
    await c.startScreenshot();
    await c.startRuler();
    desktop.event('activateQrCode');
    desktop.event('activate', {'tool': 'recording'});
    await c.pinClipboard();
    await c.togglePinnedImages();
    await c.closePinnedImages();
    await Future<void>.delayed(Duration.zero);
    expect(desktop.beginCalls, 0);
    expect(desktop.pinClipboardCalls, 0);
    expect(desktop.togglePinCalls, 0);
    expect(desktop.closePinCalls, 0);
    await c.pickColor();
    expect(desktop.beginCalls, 1);
  });

  test('二维码能力还需要截图能力', () async {
    final desktop = FakeDesktop()..capabilities = {DesktopFeature.qrCode};
    final c = AppController(desktop);
    addTearDown(c.dispose);
    addTearDown(desktop.input.close);
    await c.initialize();
    await c.startQrCodeRecognition();
    expect(desktop.beginCalls, 0);
  });
}
