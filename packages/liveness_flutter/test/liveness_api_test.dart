import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:liveness_flutter/src/core/liveness_api.dart';
import 'package:liveness_flutter/src/core/liveness_endpoint_resolver.dart';
import 'package:liveness_flutter/src/liveness/models/liveness_status.dart';

void main() {
  test('creates an HTTP session and exchanges binary frames over WebSocket', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final handled = <Future<void>>[];
    server.listen((request) {
      handled.add(() async {
        if (request.uri.path == '/sessions') {
          expect(request.method, 'POST');
          request.response.statusCode = 201;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'success': true,
              'data': {
                'session_id': 'test-session',
                'expires_in_seconds': 120,
                'status': 'align',
                'passed': false,
                'instruction': 'Posisikan wajah',
                'frames_processed': 0,
              },
            }),
          );
          await request.response.close();
          return;
        }
        expect(request.uri.path, '/sessions/test-session/stream');
        final socket = await WebSocketTransformer.upgrade(request);
        socket.add(
          jsonEncode({
            'success': true,
            'data': {'status': 'align', 'passed': false, 'instruction': 'Posisikan wajah', 'frames_processed': 0},
          }),
        );
        await for (final frame in socket) {
          expect(frame, <int>[0xff, 0xd8, 0xff]);
          socket.add(
            jsonEncode({
              'success': true,
              'data': {'status': 'passed', 'passed': true, 'instruction': 'Tantangan selesai', 'frames_processed': 1},
            }),
          );
          await socket.close();
          break;
        }
      }());
    });

    final resolver = _CountingResolver(Uri.parse('http://127.0.0.1:${server.port}'));
    final api = LivenessApi(endpointResolver: resolver);
    try {
      final session = await api.createSession();
      expect(session.sessionId, 'test-session');
      expect(session.result.status, LivenessStatus.align);
      expect(session.toJson()['status'], 'align');
      expect(session.toJson()['session_id'], 'test-session');
      final stream = await api.connect(session.sessionId);
      final result = await stream.submitFrame([0xff, 0xd8, 0xff]);
      expect(result.status, LivenessStatus.passed);
      expect(result.passed, isTrue);
      expect(result.toJson()['frames_processed'], 1);
      expect(resolver.calls, 1);
      await stream.close();
      await Future.wait(handled);
    } finally {
      api.close();
      await server.close(force: true);
    }
  });
}

class _CountingResolver extends LivenessEndpointResolver {
  _CountingResolver(this.endpoint);

  final Uri endpoint;
  int calls = 0;

  @override
  Future<Uri> resolve() async {
    calls++;
    return endpoint;
  }
}
