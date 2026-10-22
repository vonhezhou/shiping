import 'package:flutter_test/flutter_test.dart';
import 'package:fruler/app/app_controller.dart';
import 'package:fruler/core/core.dart';

import '../fake_desktop.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('只有自动测距接受精确容差，重绘并限制到合法区间', () async {
    final d = FakeDesktop();
    final c = AppController(d);
    await c.initialize();
    try {
      await c.startRuler(RulerMode.horizontal);
      d.event('toleranceChanged', {'tolerance': 37});
      expect(c.tolerance, 37);
      expect(d.lastOverlay!['tolerance'], 37);
      d.event('toleranceChanged', {'tolerance': 999});
      expect(c.tolerance, 255);
      d.event('modeChanged', {'tool': 'rectangle'});
      d.event('toleranceChanged', {'tolerance': 11});
      expect(c.tolerance, 255);
    } finally {
      c.dispose();
      await d.input.close();
    }
  });
  for (final initial in ['picker', 'rectangle', 'screenshot']) {
    test('$initial 会话不能通过模式切换变成其他工具', () async {
      final d = FakeDesktop();
      final c = AppController(d);
      await c.initialize();
      try {
        if (initial == 'picker') {
          await c.pickColor();
        } else if (initial == 'rectangle') {
          await c.startRuler(RulerMode.rectangle);
        } else {
          await c.startScreenshot();
        }
        final others = initial == 'rectangle'
            ? ['picker', 'screenshot']
            : [
                'picker',
                'rectangle',
                'horizontal',
                'vertical',
                'cross',
                'screenshot',
              ].where((t) => t != initial);
        for (final tool in others) {
          d.event('modeChanged', {'tool': tool});
          expect(d.lastOverlay!['tool'], initial);
        }
        expect(d.beginCalls, 1);
        expect(d.finishCalls, 0);
      } finally {
        c.dispose();
        await d.input.close();
      }
    });
  }

  test('尺子主入口恢复上次模式，尺子内仍可切换四种模式', () async {
    final d = FakeDesktop();
    final c = AppController(d);
    await c.initialize();
    try {
      c.selectMode(RulerMode.vertical);
      d.event('activate', {'tool': 'rectangle'});
      await Future<void>.delayed(Duration.zero);
      expect(d.lastOverlay!['tool'], 'vertical');
      d.event('modeChanged', {'tool': 'horizontal'});
      expect(d.lastOverlay!['tool'], 'horizontal');
      d.event('modeChanged', {'tool': 'rectangle'});
      expect(d.lastOverlay!['tool'], 'rectangle');
    } finally {
      c.dispose();
      await d.input.close();
    }
  });
}
