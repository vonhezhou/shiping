import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fruler/platform/desktop_service.dart';
import 'package:fruler/core/core.dart';
import 'package:fruler/platform/desktop.g.dart' as wire;
import 'package:logging/logging.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  test('语言协议只传递已解析的语言代码', () async {
    final channel = BasicMessageChannel<Object?>(
      'dev.flutter.pigeon.fruler.DesktopHostApi.configureLocale',
      wire.DesktopHostApi.pigeonChannelCodec,
    );
    addTearDown(
      () => messenger.setMockDecodedMessageHandler<Object?>(channel, null),
    );
    messenger.setMockDecodedMessageHandler<Object?>(channel, (message) async {
      expect(message, ['en']);
      return [null];
    });
    await MacDesktopService().configureLocale('en');
  });

  test('录屏协议传递像素选区和完整编码参数，停止与取消独立', () async {
    final channels = [
      for (final name in ['startRecording', 'stopRecording', 'cancelRecording'])
        BasicMessageChannel<Object?>(
          'dev.flutter.pigeon.fruler.DesktopHostApi.$name',
          wire.DesktopHostApi.pigeonChannelCodec,
        ),
    ];
    addTearDown(() {
      for (final channel in channels) {
        messenger.setMockDecodedMessageHandler<Object?>(channel, null);
      }
    });
    messenger.setMockDecodedMessageHandler<Object?>(channels[0], (
      message,
    ) async {
      final args = message as List;
      expect(args.take(2), [7, 9]);
      final region = args[2] as wire.PixelBounds;
      expect(
        [region.left, region.top, region.right, region.bottom],
        [12, 20, 192, 100],
      );
      final options = args[3] as wire.RecordingConfiguration;
      expect(
        [
          options.codec,
          options.frameRate,
          options.quality,
          options.resolution,
          options.showCursor,
          options.systemAudio,
        ],
        ['hevc', 24, 'medium', '1080p', false, true],
      );
      return [null];
    });
    messenger.setMockDecodedMessageHandler<Object?>(
      channels[1],
      (_) async => [true],
    );
    messenger.setMockDecodedMessageHandler<Object?>(
      channels[2],
      (_) async => [null],
    );
    final service = MacDesktopService();
    await service.startRecording(
      7,
      9,
      const PixelRect(left: 12, top: 20, right: 192, bottom: 100),
      const RecordingOptions(
        codec: 'hevc',
        frameRate: 24,
        quality: 'medium',
        resolution: '1080p',
        showCursor: false,
        systemAudio: true,
      ),
    );
    expect(await service.stopRecording(), true);
    await service.cancelRecording();
  });

  test('贴图协议携带会话与像素选区，历史入口保留空定位', () async {
    final channel = BasicMessageChannel<Object?>(
      'dev.flutter.pigeon.fruler.DesktopHostApi.pinImage',
      wire.DesktopHostApi.pigeonChannelCodec,
    );
    addTearDown(
      () => messenger.setMockDecodedMessageHandler<Object?>(channel, null),
    );
    final png = Uint8List.fromList([137, 80, 78, 71]);
    var calls = 0;
    messenger.setMockDecodedMessageHandler<Object?>(channel, (message) async {
      final args = message as List;
      expect(args[0], png);
      if (calls++ == 0) {
        expect(args[1], 7);
        expect(args[2], 9);
        final bounds = args[3] as wire.PixelBounds;
        expect(
          [bounds.left, bounds.top, bounds.right, bounds.bottom],
          [20, 40, 320, 240],
        );
      } else {
        expect(args.skip(1), everyElement(isNull));
      }
      return [null];
    });
    final desktop = MacDesktopService();
    await desktop.pinImage(
      png,
      sessionId: 7,
      displayId: 9,
      rect: const PixelRect(left: 20, top: 40, right: 320, bottom: 240),
    );
    await desktop.pinImage(png);
    expect(calls, 2);
  });

  test('原生日志按类型转入统一日志，不进入工具事件流', () async {
    final previousLevel = Logger.root.level;
    Logger.root.level = Level.ALL;
    final records = <LogRecord>[];
    final logs = Logger.root.onRecord.listen(records.add);
    final service = MacDesktopService();
    final events = <Map<Object?, Object?>>[];
    final subscription = service.events.listen(events.add);
    try {
      final complete = Completer<void>();
      final codec = wire.DesktopHostApi.pigeonChannelCodec;
      await messenger.handlePlatformMessage(
        'dev.flutter.pigeon.fruler.DesktopFlutterApi.onLog',
        codec.encodeMessage([
          wire.NativeLogEntry(
            level: Level.WARNING.value,
            category: 'capture',
            message: 'Capture cancelled: session=7.',
          ),
        ]),
        (reply) {
          expect(codec.decodeMessage(reply), isEmpty);
          complete.complete();
        },
      );
      await complete.future;
      await Future<void>.delayed(Duration.zero);
      expect(records.single.loggerName, 'native.capture');
      expect(records.single.level, Level.WARNING);
      expect(records.single.message, 'Capture cancelled: session=7.');
      expect(events, isEmpty);
    } finally {
      await logs.cancel();
      await subscription.cancel();
      Logger.root.level = previousLevel;
      wire.DesktopFlutterApi.setUp(null);
    }
  });

  test('原生调色盘保留 ARGB 透明度，取消返回 null', () async {
    final channel = BasicMessageChannel<Object?>(
      'dev.flutter.pigeon.fruler.DesktopHostApi.pickAnnotationColor',
      wire.DesktopHostApi.pigeonChannelCodec,
    );
    addTearDown(
      () => messenger.setMockDecodedMessageHandler<Object?>(channel, null),
    );
    for (final result in [null, 0x8012AB34]) {
      messenger.setMockDecodedMessageHandler<Object?>(channel, (message) async {
        expect(message, [0xFFABCDEF]);
        return [result];
      });
      expect(await MacDesktopService().pickAnnotationColor(0xFFABCDEF), result);
    }
  });

  test('capture channel carries Retina metadata and buffer handle, never pixel bytes', () async {
    messenger.setMockDecodedMessageHandler<Object?>(
      BasicMessageChannel<Object?>(
        'dev.flutter.pigeon.fruler.DesktopHostApi.begin',
        wire.DesktopHostApi.pigeonChannelCodec,
      ),
      (message) async {
        expect((message as List).single, wire.CaptureTool.picker);
        return [
          wire.CaptureReply(
            sessionId: 7,
            displays: [
              wire.DisplayFrame(
                id: 3,
                name: 'Retina',
                width: 2,
                height: 2,
                logicalWidth: 1,
                logicalHeight: 1,
                bufferId: 81,
                byteLength: 16,
                rowBytes: 8,
              ),
            ],
          ),
        ];
      },
    );
    final service = MacDesktopService(
      readFrame: (d) {
        expect(d.bufferId, 81);
        expect(d.byteLength, 16);
        expect(d.rowBytes, 8);
        return PixelFrame(
          width: d.width,
          height: d.height,
          rgba: Uint8List(d.byteLength),
          rowBytes: d.rowBytes,
          logicalWidth: d.logicalWidth,
          logicalHeight: d.logicalHeight,
        );
      },
    );
    final capture = await service.begin('picker');
    expect(capture.id, 7);
    expect(capture.displays.single.frame.scaleX, 2);
    expect(capture.displays.single.frame.rgba.length, 16);
    messenger.setMockDecodedMessageHandler<Object?>(
      BasicMessageChannel<Object?>(
        'dev.flutter.pigeon.fruler.DesktopHostApi.begin',
        wire.DesktopHostApi.pigeonChannelCodec,
      ),
      null,
    );
  });

  for (final count in [0, 2]) {
    test(
      'acquisition failure closes native session ($count displays)',
      () async {
        final begin = BasicMessageChannel<Object?>(
          'dev.flutter.pigeon.fruler.DesktopHostApi.begin',
          wire.DesktopHostApi.pigeonChannelCodec,
        );
        final finish = BasicMessageChannel<Object?>(
          'dev.flutter.pigeon.fruler.DesktopHostApi.finish',
          wire.DesktopHostApi.pigeonChannelCodec,
        );
        var finishes = 0, reads = 0;
        messenger.setMockDecodedMessageHandler<Object?>(
          begin,
          (_) async => [
            wire.CaptureReply(
              sessionId: 71,
              displays: [
                for (var i = 0; i < count; i++)
                  wire.DisplayFrame(
                    id: i,
                    name: 'display',
                    width: 2,
                    height: 2,
                    logicalWidth: 2,
                    logicalHeight: 2,
                    bufferId: i + 1,
                    byteLength: 16,
                    rowBytes: 8,
                  ),
              ],
            ),
          ],
        );
        messenger.setMockDecodedMessageHandler<Object?>(finish, (
          message,
        ) async {
          expect(message, [71]);
          finishes++;
          return [null];
        });
        final service = MacDesktopService(
          readFrame: (metadata) {
            if (++reads == 2) throw const FormatException('Expired buffer');
            return PixelFrame(
              width: 2,
              height: 2,
              rgba: Uint8List(16),
              logicalWidth: 2,
              logicalHeight: 2,
            );
          },
        );
        try {
          await expectLater(service.begin('screenshot'), throwsFormatException);
          expect(finishes, 1);
        } finally {
          messenger.setMockDecodedMessageHandler<Object?>(begin, null);
          messenger.setMockDecodedMessageHandler<Object?>(finish, null);
          wire.DesktopFlutterApi.setUp(null);
        }
      },
    );
  }

  test('invalid tools retain the public invalid_tool error', () async {
    await expectLater(
      MacDesktopService().begin('invalid-test-tool'),
      throwsA(
        isA<PlatformException>().having((e) => e.code, 'code', 'invalid_tool'),
      ),
    );
  });

  test('native errors retain their code for permission handling', () async {
    final channel = BasicMessageChannel<Object?>(
      'dev.flutter.pigeon.fruler.DesktopHostApi.begin',
      wire.DesktopHostApi.pigeonChannelCodec,
    );
    messenger.setMockDecodedMessageHandler<Object?>(
      channel,
      (_) async => ['screen_permission', 'Permission required', null],
    );
    await expectLater(
      MacDesktopService().begin('screenshot'),
      throwsA(
        isA<PlatformException>().having(
          (e) => e.code,
          'code',
          'screen_permission',
        ),
      ),
    );
    messenger.setMockDecodedMessageHandler<Object?>(channel, null);
  });
  test(
    'native callbacks decode typed pointer and cancellation events',
    () async {
      final service = MacDesktopService();
      final received = <Map<Object?, Object?>>[];
      final subscription = service.events.listen(received.add);
      try {
        for (final event in [
          wire.NativeEvent(
            kind: wire.EventKind.pointer,
            sessionId: 5,
            displayId: 9,
            x: 12.5,
            y: 40,
            phase: wire.InputPhase.drag,
            button: wire.MouseButton.secondary,
            suggestedRect: wire.PixelBounds(
              left: 1,
              top: 2,
              right: 20,
              bottom: 50,
            ),
          ),
          wire.NativeEvent(
            kind: wire.EventKind.nudge,
            sessionId: 5,
            dx: -1,
            dy: 0,
          ),
          wire.NativeEvent(kind: wire.EventKind.cancelled, sessionId: 5),
        ]) {
          final complete = Completer<void>();
          final codec = wire.DesktopHostApi.pigeonChannelCodec;
          await messenger.handlePlatformMessage(
            'dev.flutter.pigeon.fruler.DesktopFlutterApi.onEvent',
            codec.encodeMessage([event]),
            (reply) {
              expect(codec.decodeMessage(reply), isEmpty);
              complete.complete();
            },
          );
          await complete.future;
        }
        await Future<void>.delayed(Duration.zero);
        expect(received[0]['x'], 12.5);
        expect(received[0]['phase'], 'drag');
        expect(received[0]['button'], 'secondary');
        expect(received[0]['displayId'], 9);
        expect(received[0]['suggestedRect'], {
          'left': 1,
          'top': 2,
          'right': 20,
          'bottom': 50,
        });
        expect(received[1]['dx'], isA<int>());
        expect(received[1]['dx'], -1);
        expect(received[2]['type'], 'cancelled');
        expect(received[2]['sessionId'], 5);
      } finally {
        await subscription.cancel();
        wire.DesktopFlutterApi.setUp(null);
      }
    },
  );
}
