import 'package:flutter_test/flutter_test.dart';
import 'package:fruler/core/core.dart';

void main() {
  String render(String value, RgbColor color) =>
      ColorOutput(id: 'test', name: 'test', template: value).render(color);
  test('默认格式与旧版输出逐项一致', () {
    for (final color in [
      const RgbColor(0, 0, 0),
      const RgbColor(255, 255, 255),
      const RgbColor(13, 128, 255),
      const RgbColor(255, 0, 1),
      const RgbColor(60, 30, 60),
    ]) {
      for (final entry in ColorOutput.defaults) {
        expect(
          entry.render(color),
          color.formatted(ColorFormat.values.byName(entry.id)),
        );
      }
    }
  });
  test('字节、十六进制、归一小数及不透明 Alpha', () {
    const color = RgbColor(13, 128, 255);
    expect(render('%Re|%Grb|%Bl|%Al', color), '13|128|255|255');
    expect(render('%Reh%Grh%BlH %Rex%GrX%BlX', color), '08F 0d80FF');
    expect(render('%Ref|%Grf|%Blf|%AlF', color), '0.05|0.5|1|1');
    expect(render('%ReF|%GrF', color), '.05|.5');
  });
  test('HSL、HSV与 RGB/BGR 整数保持固定小数点语义', () {
    const color = RgbColor(255, 0, 0);
    expect(
      render('hsl(%Hu, %Sl%, %Ll%) hsv(%Hu, %Sb%, %Va%)', color),
      'hsl(0, 100%, 50%) hsv(0, 100%, 100%)',
    );
    expect(render('%Dr %Dv %Br', color), '16711680 255 100');
    expect(render('%Hu %Sb %Va', const RgbColor(0, 0, 0)), '0 0 0');
  });
  test('模板只替换已知占位符，文字、换行和百分号保留', () {
    expect(
      render(
        'var color = #%ReX%GrX%BlX; %% ready\nvalue=%Re',
        const RgbColor(1, 2, 3),
      ),
      'var color = #010203; % ready\nvalue=1',
    );
    expect(
      render(r'$(touch /tmp/no) %Re', const RgbColor(1, 2, 3)),
      r'$(touch /tmp/no) 1',
    );
  });
  test('损坏模板与超限定义明确拒绝', () {
    for (final value in [
      '',
      'literal',
      '%Bad',
      '%Na',
      '%Lc',
      '%Re\u0000',
      'a' * 1025,
    ]) {
      expect(
        () => render(value, const RgbColor(1, 2, 3)),
        throwsFormatException,
      );
    }
    expect(
      () => const ColorOutput(
        id: '../bad',
        name: 'name',
        template: '%Re',
      ).validate(),
      throwsFormatException,
    );
    expect(
      () => const ColorOutput(id: 'ok', name: ' ', template: '%Re').validate(),
      throwsFormatException,
    );
  });
  test('格式与鼠标动作严格序列化', () {
    final f = ColorOutput.fromJson(
      ColorOutput.defaults.first.copyWith(enabled: false).toJson(),
    );
    expect(f.enabled, false);
    expect(f.template, '#%ReX%GrX%BlX');
    const value = PickerBehavior(
      activation: PickerActivation.editor,
      primary: PickerMouseAction.pickAndEdit,
      middle: PickerMouseAction.cancel,
      secondary: PickerMouseAction.pickAndContinue,
    );
    final round = PickerBehavior.fromJson(value.toJson());
    expect(round.activation, PickerActivation.editor);
    expect(round.forButton('secondary'), PickerMouseAction.pickAndContinue);
    expect(
      () => PickerBehavior.fromJson({'activation': 'invalid'}),
      throwsA(anything),
    );
  });
}
