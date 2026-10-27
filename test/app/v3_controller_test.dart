import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fruler/app/app_controller.dart';
import 'package:fruler/core/core.dart';
import 'package:fruler/platform/desktop_service.dart';

import '../fake_desktop.dart';

Future<void> settle() => Future<void>.delayed(Duration.zero);
void main() {
  late FakeDesktop desktop;
  late AppController controller;
  setUp(() async {
    desktop = FakeDesktop();
    controller = AppController(desktop);
    await controller.initialize();
  });
  tearDown(() async {
    controller.dispose();
    await desktop.input.close();
  });
  Future<void> pin() async {
    desktop.pointer(x: 0, y: 0, phase: 'down');
    desktop.pointer(x: 2, y: 2, phase: 'up', keep: true);
    await settle();
  }

  test('连续取色复用快照，重复颜色去重且 Esc 保留已采集颜色', () async {
    controller.setContinuousPicker(true);
    await controller.pickColor();
    desktop.pointer(phase: 'up');
    await settle();
    desktop.pointer(phase: 'up');
    await settle();
    expect(controller.busy, true);
    expect(desktop.finishCalls, 0);
    expect(desktop.beginCalls, 1);
    expect(controller.colors.length, 1);
    expect(desktop.lastOverlay!['pickedCount'], 2);
    desktop.event('cancelled');
    expect(controller.busy, false);
    expect(controller.notice, '取色已结束，已采集 2 次');
    expect(controller.colors.length, 1);
    expect(jsonDecode(desktop.saved!)['continuousPicker'], true);
  });
  test('现场关闭连续取色，下次确认正常结束；复制失败后可重试', () async {
    controller.setContinuousPicker(true);
    await controller.pickColor();
    desktop.clipboardError = PlatformException(code: 'clipboard');
    desktop.pointer(phase: 'up');
    await settle();
    expect(controller.busy, true);
    expect(controller.error, contains('复制失败'));
    desktop.clipboardError = null;
    desktop.pointer(phase: 'up');
    await settle();
    expect(controller.error, isNull);
    desktop.event('continuousChanged', {'enabled': false});
    desktop.pointer(phase: 'up');
    await settle();
    expect(desktop.finishCalls, 1);
  });
  test('命名和收藏独立于最近记录淘汰，更新与单条删除持久化', () async {
    const chosen = RgbColor(1, 2, 3);
    controller.savePaletteColor(chosen, name: '主色', favorite: true);
    controller.savePaletteColor(chosen, name: '品牌色');
    for (var i = 0; i < 70; i++) {
      controller.addEditedColor(RgbColor(i, 0, 0));
    }
    expect(controller.colors.length, 64);
    expect(controller.palette.single.name, '品牌色');
    controller.clearColors();
    expect(controller.palette.single.favorite, true);
    final restored = AppController(desktop);
    await restored.initialize();
    expect(restored.palette.single.color, chosen);
    expect(restored.colors, isEmpty);
    restored.dispose();
    controller.removePaletteColor(chosen);
    expect(controller.palette, isEmpty);
  });
  test('第二版历史迁移且损坏调色板条目不影响有效数据', () async {
    desktop.saved = jsonEncode({
      'version': 1,
      'colors': [
        [1, 2, 3],
      ],
      'palette': [
        {'name': '坏记录'},
        {
          'color': [4, 5, 6],
          'name': '保留',
          'favorite': true,
        },
      ],
    });
    final restored = AppController(desktop);
    await restored.initialize();
    expect(restored.colors.single, const RgbColor(1, 2, 3));
    expect(restored.palette.single.name, '保留');
    expect(restored.continuousPicker, false);
    restored.dispose();
  });
  test('导出使用调用时快照，保存取消不显示成功', () async {
    controller.addEditedColor(const RgbColor(1, 2, 3));
    controller.savePaletteColor(
      const RgbColor(4, 5, 6),
      name: '收藏',
      favorite: true,
    );
    await controller.exportColors(PaletteExport.json, saved: true);
    expect(desktop.exportedName, '拾屏-palette.json');
    expect(jsonDecode(desktop.exportedText!)['colors'][0]['hex'], '#040506');
    controller.dismissMessage();
    desktop.fileResult = false;
    await controller.exportColors(PaletteExport.css, saved: false);
    expect(desktop.exportedText, contains('--shiping-1: #010203;'));
    expect(controller.notice, isNull);
  });
  test('选择删除、清空和撤销标注，测量历史不被误删', () async {
    await controller.startRuler();
    await pin();
    await pin();
    final pins = desktop.lastOverlay!['pinned'] as List;
    final id = (pins.first as Map)['id'];
    desktop.event('selectPin', {'id': id});
    expect(desktop.lastOverlay!['selectedPin'], id);
    desktop.event('deletePin');
    expect((desktop.lastOverlay!['pinned'] as List).length, 1);
    desktop.event('undoPins');
    expect((desktop.lastOverlay!['pinned'] as List).length, 2);
    desktop.event('clearPins');
    expect(desktop.lastOverlay!['pinned'], isEmpty);
    desktop.event('undoPins');
    expect((desktop.lastOverlay!['pinned'] as List).length, 2);
    expect(controller.measurements.length, 2);
    desktop.event('undoPins');
    expect((desktop.lastOverlay!['pinned'] as List).length, 1);
    desktop.event('cancelled');
    await controller.startRuler();
    expect(desktop.lastOverlay!['canUndoPins'], false);
  });
  test('编辑标注时不会误确认新矩形，删除已不存在标注为无操作', () async {
    await controller.startRuler();
    await pin();
    desktop.event('editPins');
    desktop.pointer(x: 0, y: 0, phase: 'down');
    desktop.pointer(x: 2, y: 2, phase: 'up');
    await settle();
    expect(controller.measurements.length, 1);
    expect(controller.busy, true);
    desktop.event('selectPin', {'id': 9999});
    desktop.event('deletePin');
    expect((desktop.lastOverlay!['pinned'] as List).length, 1);
  });
  test('图片导出只包含选中项或当前屏标注，失败不结束会话', () async {
    await controller.startRuler();
    await pin();
    await pin();
    final first = (desktop.lastOverlay!['pinned'] as List).first as Map;
    desktop.event('selectPin', {'id': first['id']});
    desktop.event('exportPins', {'displayId': 1, 'save': false});
    await settle();
    expect(desktop.exportedAnnotations!.length, 1);
    expect(desktop.exportedAnnotations!.single['id'], first['id']);
    desktop.event('selectPin', {'id': null});
    desktop.event('exportPins', {'displayId': 1, 'save': true});
    await settle();
    expect(desktop.exportedAnnotations!.length, 2);
    expect(controller.busy, true);
    expect(desktop.finishCalls, 0);
    desktop.exportError = PlatformException(code: 'write_failed');
    desktop.event('exportPins', {'displayId': 1, 'save': true});
    await settle();
    expect(controller.error, contains('导出失败'));
    desktop.event('cancelled');
    expect(controller.busy, false);
  });
  test('旧会话的异步复制结束不能关闭新会话或解除新会话提交锁', () async {
    desktop.pendingClipboard = Completer<void>();
    await controller.pickColor();
    desktop.pointer(phase: 'up');
    desktop.event('cancelled');
    desktop.capture = CaptureSession(8, desktop.capture.displays);
    await controller.pickColor();
    desktop.pendingClipboard!.complete();
    await settle();
    expect(controller.busy, true);
    expect(desktop.finishedSession, 7);
    desktop.pointer(session: 8, phase: 'up');
    await settle();
    expect(controller.busy, false);
    expect(desktop.finishedSession, 8);
  });
}
