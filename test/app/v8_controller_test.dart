import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fruler/app/app_controller.dart';
import 'package:fruler/core/core.dart';

import '../fake_desktop.dart';

Future<void> tick() => Future<void>.delayed(Duration.zero);
void main() {
  late FakeDesktop d;
  late AppController c;
  setUp(() async {
    d = FakeDesktop();
    c = AppController(d);
    await c.initialize();
  });
  tearDown(() async {
    c.dispose();
    await d.input.close();
  });
  Future<void> click(String button) async {
    d.pointer(phase: 'up', button: button);
    await tick();
    await tick();
  }

  test('格式编辑启停排序删除与默认复制持久化，不能清空所有可用格式', () async {
    expect(
      c.saveColorOutput(name: 'RGBA', template: 'rgba(%Re,%Gr,%Bl,%Alf)'),
      true,
    );
    final id = c.colorOutputs.last.id;
    c.selectColorOutput(id);
    await c.copyColor(const RgbColor(1, 2, 3));
    expect(d.clipboard, 'rgba(1,2,3,1)');
    c.moveColorOutput(id, -5);
    expect(c.colorOutputs.first.id, id);
    expect(
      c.saveColorOutput(id: id, name: 'Vector', template: '(%Ref,%Grf,%Blf)'),
      true,
    );
    final restored = AppController(d);
    await restored.initialize();
    expect(restored.colorOutputs.first.name, 'Vector');
    expect(restored.selectedOutputId, id);
    restored.dispose();
    expect(c.enableColorOutput(id, false), true);
    expect(c.selectedOutputId, 'hex');
    expect(c.deleteColorOutput(id), true);
    for (final f in c.colorOutputs.skip(1).toList()) {
      c.enableColorOutput(f.id, false);
    }
    expect(c.enableColorOutput('hex', false), false);
    expect(c.deleteColorOutput('hex'), false);
    expect(c.saveColorOutput(name: 'HEX', template: '%Re'), false);
    expect(c.saveColorOutput(name: 'broken', template: '%Bad'), false);
  });
  test('旧格式与连续取色偏好迁移，损坏配置不影响旧历史', () async {
    d.saved = jsonEncode({
      'version': 1,
      'format': 'rgb',
      'continuousPicker': true,
      'colors': [
        [1, 2, 3],
      ],
      'colorOutputs': [
        {'bad': true},
      ],
      'pickerBehavior': {'activation': 'bad'},
    });
    final old = AppController(d);
    await old.initialize();
    expect(old.selectedOutputId, 'rgb');
    expect(old.formatColor(const RgbColor(1, 2, 3)), 'rgb(1, 2, 3)');
    expect(old.pickerBehavior.primary, PickerMouseAction.pickAndContinue);
    expect(old.colors.single, const RgbColor(1, 2, 3));
    old.dispose();
  });
  test('取色并结束沿用当前自定义输出，鼠标动作相互独立', () async {
    c.saveColorOutput(name: 'Channels', template: '%Re/%Gr/%Bl');
    c.selectColorOutput(c.colorOutputs.last.id);
    c.setPickerBehavior(
      const PickerBehavior(
        primary: PickerMouseAction.pickAndContinue,
        middle: PickerMouseAction.pickAndClose,
        secondary: PickerMouseAction.cancel,
      ),
    );
    await c.pickColor();
    await click('primary');
    expect(c.busy, true);
    expect(d.clipboard, '255/0/0');
    await click('middle');
    expect(c.busy, false);
    expect(d.finishCalls, 1);
    expect(c.colors.length, 1);
  });
  test('取消不采集不复制；右键可配置成连续取色，Esc 仍取消', () async {
    await c.pickColor();
    await click('secondary');
    expect(c.colors, isEmpty);
    expect(d.clipboard, null);
    expect(c.busy, false);
    c.setPickerBehavior(
      const PickerBehavior(secondary: PickerMouseAction.pickAndContinue),
    );
    await c.pickColor();
    await click('secondary');
    expect(c.busy, true);
    expect(c.colors.length, 1);
    expect(d.clipboard, '#FF0000');
    d.event('cancelled');
    expect(c.busy, false);
  });
  test('取色后编辑器在关闭浮层后请求，取消或重取不重复采样', () async {
    c.setPickerBehavior(
      const PickerBehavior(primary: PickerMouseAction.pickAndEdit),
    );
    await c.pickColor();
    await click('primary');
    expect(c.busy, false);
    expect(d.finishCalls, 1);
    expect(d.showMainCalls, 1);
    expect(c.takePickedEditorColor(), const RgbColor(255, 0, 0));
    expect(c.pendingPickedEditorColor, null);
    expect(c.colors.length, 1);
    expect(d.clipboard, '#FF0000');
    await c.pickNewColor();
    expect(c.busy, true);
  });
  test('直接编辑器无需录屏权限，重新取色独立于启动配置', () async {
    c.setPickerBehavior(
      const PickerBehavior(activation: PickerActivation.editor),
    );
    d.permission = false;
    c.permissionGranted = false;
    await c.pickColor();
    expect(d.beginCalls, 0);
    expect(d.showMainCalls, 1);
    expect(c.pendingPickedEditorColor, c.selectedColor);
    expect(c.colors, isEmpty);
    c.takePickedEditorColor();
    d.permission = true;
    c.permissionGranted = true;
    await c.pickNewColor();
    expect(d.beginCalls, 1);
  });
  test('连续开关同步左键动作而保留中键右键及启动设置，重启恢复', () async {
    c.setPickerBehavior(
      const PickerBehavior(
        activation: PickerActivation.editor,
        middle: PickerMouseAction.pickAndEdit,
        secondary: PickerMouseAction.pickAndContinue,
      ),
    );
    c.setContinuousPicker(true);
    expect(c.pickerBehavior.primary, PickerMouseAction.pickAndContinue);
    c.setContinuousPicker(false);
    expect(c.pickerBehavior.primary, PickerMouseAction.pickAndClose);
    final restored = AppController(d);
    await restored.initialize();
    expect(restored.pickerBehavior.activation, PickerActivation.editor);
    expect(restored.pickerBehavior.middle, PickerMouseAction.pickAndEdit);
    expect(
      restored.pickerBehavior.secondary,
      PickerMouseAction.pickAndContinue,
    );
    restored.dispose();
  });
  test('对比度取色保留固定确认语义，不受普通鼠标动作影响', () async {
    c.setPickerBehavior(
      const PickerBehavior(primary: PickerMouseAction.cancel),
    );
    await c.pickContrast(foreground: true, pair: true);
    await click('primary');
    expect(c.busy, true);
    expect(c.contrastForeground, const RgbColor(255, 0, 0));
    await click('primary');
    expect(c.busy, false);
    expect(c.pendingPickedEditorColor, null);
  });
  test('异步复制期间丢弃重复点击，只打开一次编辑器', () async {
    c.setPickerBehavior(
      const PickerBehavior(primary: PickerMouseAction.pickAndEdit),
    );
    d.pendingClipboard = Completer<void>();
    await c.pickColor();
    d.pointer(phase: 'up');
    d.pointer(phase: 'up');
    await tick();
    expect(c.colors.length, 1);
    expect(d.finishCalls, 0);
    d.pendingClipboard!.complete();
    await tick();
    await tick();
    expect(d.finishCalls, 1);
    expect(d.showMainCalls, 1);
  });
  test('复制失败仍保留采样并退出浮层，编辑器仍可打开', () async {
    c.setPickerBehavior(
      const PickerBehavior(primary: PickerMouseAction.pickAndEdit),
    );
    d.clipboardError = StateError('clipboard');
    await c.pickColor();
    await click('primary');
    expect(c.colors.length, 1);
    expect(c.busy, false);
    expect(c.pendingPickedEditorColor, isNotNull);
    expect(c.error, contains('复制失败'));
  });
}
