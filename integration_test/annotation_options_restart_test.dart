import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:fruler/app/app_controller.dart';
import 'package:fruler/core/core.dart';
import 'package:fruler/platform/desktop_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const phase = String.fromEnvironment('FRULER_OPTIONS_PHASE');
  testWidgets('标注选项跨真实 macOS 应用进程恢复 $phase', (tester) async {
    const driver = MethodChannel('dev.fruler/integration');
    final status = await driver.invokeMapMethod<String, Object?>('status');
    expect(status?['bundleId'], 'dev.fruler.integration');
    final directory = await getApplicationSupportDirectory();
    final backup = File(
      '${directory.path}/fruler/annotation-options-test-backup.json',
    );
    final desktop = MacDesktopService();
    final c = AppController(desktop);
    final expected = <String, AnnotationOptions>{
      for (final tool in [
        'ellipse',
        'line',
        'pencil',
        'marker',
        'blur',
        'eraser',
        'text',
      ])
        tool: AnnotationOptions(
          width: tool == 'marker' ? 17 : 7,
          fontSize: 36,
          fontFamily: 'Menlo',
          filled: true,
          bold: true,
          italic: true,
          outlined: true,
          effectBrush: true,
          eraserBrush: true,
          effectStrength: 5,
        ),
    };
    try {
      if (phase == 'write') {
        expect(await backup.exists(), false, reason: '不得覆盖未恢复的测试配置备份');
        await backup.parent.create(recursive: true);
        await backup.writeAsString(
          jsonEncode(await desktop.loadState()),
          flush: true,
        );
        await c.initialize();
        for (final entry in expected.entries) {
          c.setAnnotationOptions(entry.key, entry.value);
          c.rememberAnnotationTool(entry.key);
        }
        // 等待真实通道写入完成，下一阶段会关闭并重新启动应用进程。
        for (var attempt = 0; attempt < 100; attempt++) {
          final saved = jsonDecode((await desktop.loadState())!);
          if (saved['annotationTools']?['effect'] == 'blur') break;
          await tester.pump(const Duration(milliseconds: 10));
        }
        final saved = jsonDecode((await desktop.loadState())!);
        expect(saved['annotationOptions']['marker']['width'], 17);
        expect(saved['annotationTools']['effect'], 'blur');
      } else {
        expect(phase, anyOf('read', 'restore'));
        expect(await backup.exists(), true);
        try {
          if (phase == 'read') {
            await c.initialize();
            for (final entry in expected.entries) {
              expect(
                c.annotationOptions(entry.key).toJson(),
                entry.value.toJson(),
                reason: entry.key,
              );
            }
            expect(c.annotationTool('shape'), 'ellipse');
            expect(c.annotationTool('line'), 'line');
            expect(c.annotationTool('effect'), 'blur');
          }
        } finally {
          final original = jsonDecode(await backup.readAsString()) as String?;
          await desktop.saveState(original ?? '{}');
          await backup.delete();
        }
      }
    } finally {
      c.dispose();
    }
  });
}
