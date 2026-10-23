import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fruler/app/app_controller.dart';
import 'package:fruler/core/core.dart';

import '../fake_desktop.dart';

class _OptionsDesktop extends FakeDesktop {
  int stateWrites = 0;
  int overlayWrites = 0;
  @override
  Future<void> saveState(String json) async {
    stateWrites++;
    await super.saveState(json);
  }

  @override
  Future<void> updateOverlay(Map<String, Object?> data) async {
    overlayWrites++;
    await super.updateOverlay(data);
  }
}

void main() {
  test('选项窗口默认常规页，合法倍率保存并在新控制器中恢复', () async {
    final desktop = _OptionsDesktop();
    final controller = AppController(desktop);
    addTearDown(controller.dispose);
    addTearDown(desktop.input.close);
    expect(controller.section, AppSection.settings);
    await controller.initialize();
    expect(controller.section, AppSection.settings);
    for (final zoom in CaptureControls.zoomLevels) {
      controller.setZoom(zoom);
      expect(controller.zoom, zoom);
      expect(jsonDecode(desktop.saved!)['zoom'], zoom);
    }
    final restoredDesktop = _OptionsDesktop()..saved = desktop.saved;
    final restored = AppController(restoredDesktop);
    addTearDown(restored.dispose);
    addTearDown(restoredDesktop.input.close);
    await restored.initialize();
    expect(restored.zoom, 32);
    expect(restored.section, AppSection.settings);
  });

  test('无效或未变化的倍率不污染配置，也不通知或重绘浮层', () async {
    final desktop = _OptionsDesktop();
    final controller = AppController(desktop);
    addTearDown(controller.dispose);
    addTearDown(desktop.input.close);
    await controller.initialize();
    await controller.pickColor();
    final oldOverlay = desktop.lastOverlay;
    final oldOverlayWrites = desktop.overlayWrites;
    final oldStateWrites = desktop.stateWrites;
    var notifications = 0;
    controller.addListener(() => notifications++);
    for (final value in [-4, 0, 3, 5, 10, 20, 64, controller.zoom]) {
      controller.setZoom(value);
    }
    expect(controller.zoom, CaptureControls.defaultZoom);
    expect(desktop.stateWrites, oldStateWrites);
    expect(desktop.overlayWrites, oldOverlayWrites);
    expect(desktop.lastOverlay, same(oldOverlay));
    expect(notifications, 0);
    controller.setZoom(24);
    expect(controller.zoom, 24);
    expect(desktop.lastOverlay!['zoom'], 24);
    expect(desktop.lastOverlay!['tool'], 'picker');
    expect(desktop.overlayWrites, oldOverlayWrites + 1);
    expect(desktop.stateWrites, oldStateWrites + 1);
    expect(notifications, 1);
  });

  test('损坏历史中的无效倍率继续使用默认值', () async {
    final desktop = _OptionsDesktop()
      ..saved = jsonEncode({'version': 1, 'zoom': 20});
    final controller = AppController(desktop);
    addTearDown(controller.dispose);
    addTearDown(desktop.input.close);
    await controller.initialize();
    expect(controller.zoom, CaptureControls.defaultZoom);
  });
}
