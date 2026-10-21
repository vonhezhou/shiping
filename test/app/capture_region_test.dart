import 'package:flutter_test/flutter_test.dart';
import 'package:fruler/app/app_controller.dart';

import '../fake_desktop.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final drag in [false, true]) {
    test('窗口候选点击选中，主动拖动改用手动边界 drag=$drag', () async {
      final d = FakeDesktop();
      final c = AppController(d);
      await c.initialize();
      try {
        await c.startScreenshot();
        const candidate = {'left': 2, 'top': 1, 'right': 6, 'bottom': 5};
        void pointer(String phase, double x, double y) => d.event('pointer', {
          'displayId': 1,
          'x': x,
          'y': y,
          'phase': phase,
          'suggestedRect': candidate,
        });
        pointer('move', 1.5, 1);
        expect(d.lastOverlay?['rect'], candidate);
        pointer('down', 1.5, 1);
        // Any deliberate movement on this tiny fake display abandons snapping.
        if (drag) pointer('drag', 4, 3);
        pointer('up', drag ? 4 : 1.5, drag ? 3 : 1);
        for (var i = 0; i < 100 && !c.screenshotEditing; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(c.screenshotEditing, true);
        expect(
          c.screenshotSelection!.toJson(),
          drag ? {'left': 3, 'top': 2, 'right': 8, 'bottom': 6} : candidate,
        );
        expect(d.beginCalls, 1);
      } finally {
        c.dispose();
        await d.input.close();
      }
    });
  }
}
