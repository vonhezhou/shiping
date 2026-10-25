import 'package:flutter_test/flutter_test.dart';
import 'package:fruler/core/core.dart';

void main() {
  test('贴图快捷键参与冲突校验并往返保存', () {
    const bindings = ShortcutBindings.defaults;
    expect(bindings.pinClipboard.key, 'T');
    expect(bindings.togglePins.key, 'V');
    expect(
      ShortcutBindings.fromJson(bindings.toJson()).pinClipboard,
      bindings.pinClipboard,
    );
    expect(
      ShortcutBindings.fromJson(bindings.toJson()).togglePins,
      bindings.togglePins,
    );
    expect(
      ShortcutBindings(
        picker: bindings.picker,
        ruler: bindings.ruler,
        pinClipboard: bindings.screenshot,
      ).isValid,
      false,
    );
    expect(
      ShortcutBindings(
        picker: bindings.picker,
        ruler: bindings.ruler,
        togglePins: bindings.pinClipboard,
      ).isValid,
      false,
    );
  });

  test('贴图候选键遵守原生保留键规则', () {
    expect(
      const ShortcutChord(key: 'H', meta: true, shift: true).isValid,
      false,
    );
    expect(
      const ShortcutChord(key: 'T', meta: true, shift: true).isValid,
      true,
    );
    expect(
      const ShortcutChord(key: 'V', meta: true, shift: true).isValid,
      true,
    );
    expect(const ShortcutChord(key: 'V', meta: true).isValid, false);
    expect(
      const ShortcutChord(key: '3', meta: true, shift: true).isValid,
      false,
    );
  });

  test('旧配置补齐贴图快捷键时避开已有自定义组合', () {
    final old = ShortcutBindings.fromJson({
      'picker': const ShortcutChord(key: 'T', meta: true, shift: true).toJson(),
      'ruler': const ShortcutChord(key: 'V', meta: true, shift: true).toJson(),
      'screenshot': const ShortcutChord(
        key: 'P',
        meta: true,
        shift: true,
      ).toJson(),
    });
    expect(old.isValid, true);
    expect(old.pinClipboard, isNot(old.picker));
    expect(old.togglePins, isNot(old.ruler));
    expect(old.pinClipboard, isNot(old.togglePins));
  });
}
