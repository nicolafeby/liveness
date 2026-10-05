import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liveness_edge_flutter/src/core/detector.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('liveness_edge_flutter_test');

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('maps native error codes to typed exceptions', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          throw PlatformException(
            code: 'invalid_frame',
            message: 'bad bytes',
            details: const {'expected': 'LVC1'},
          );
        });
    final detector = LivenessEdgeDetector(channel: channel);

    await expectLater(
      detector.analyze(Uint8List(0)),
      throwsA(
        isA<LivenessEdgeException>()
            .having(
              (error) => error.code,
              'code',
              LivenessEdgeErrorCode.invalidFrame,
            )
            .having(
              (error) => error.operation,
              'operation',
              LivenessEdgeOperation.analyze,
            )
            .having((error) => error.nativeCode, 'nativeCode', 'invalid_frame')
            .having((error) => error.message, 'message', 'bad bytes'),
      ),
    );
  });

  test('times out a native call that never completes', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) => Completer<Object?>().future);
    final detector = LivenessEdgeDetector(
      channel: channel,
      analysisTimeout: const Duration(milliseconds: 10),
    );

    await expectLater(
      detector.analyze(Uint8List(0)),
      throwsA(
        isA<LivenessEdgeException>()
            .having(
              (error) => error.code,
              'code',
              LivenessEdgeErrorCode.timeout,
            )
            .having(
              (error) => error.operation,
              'operation',
              LivenessEdgeOperation.analyze,
            ),
      ),
    );
  });

  test('maps missing native plugin to unavailable', () async {
    final detector = LivenessEdgeDetector(channel: channel);

    await expectLater(
      detector.initialize(),
      throwsA(
        isA<LivenessEdgeException>().having(
          (error) => error.code,
          'code',
          LivenessEdgeErrorCode.unavailable,
        ),
      ),
    );
  });
}
