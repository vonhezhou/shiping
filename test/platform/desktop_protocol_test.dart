import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fruler/platform/desktop_service.dart';
import 'package:fruler/core/core.dart';
import 'package:fruler/platform/desktop.g.dart' as wire;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

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
