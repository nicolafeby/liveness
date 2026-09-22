import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:liveness/liveness/liveness_api.dart';

void main() {
  test('creates an HTTP session and exchanges binary frames over WebSocket', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final handled = <Future<void>>[];
    server.listen((request) {
      handled.add(() async {
        if (request.uri.path == '/sessions') {
          expect(request.method, 'POST');
          request.response.statusCode = 201;
          request.response.write(
            jsonEncode({
              'success': true,
              'data': {'session_id': 'test-session', 'instruction': 'Hadap kamera'},
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
            'data': {'status': 'open'},
          }),
        );
        await for (final frame in socket) {
          expect(frame, <int>[0xff, 0xd8, 0xff]);
          socket.add(
            jsonEncode({
              'success': true,
              'data': {'status': 'passed', 'instruction': 'Tantangan selesai'},
            }),
          );
          await socket.close();
          break;
        }
      }());
    });

    final api = LivenessApi(baseUrl: 'http://127.0.0.1:${server.port}');
    try {
      final session = await api.createSession();
      final stream = await api.connect(session['session_id'] as String);
      final result = await stream.submitFrame([0xff, 0xd8, 0xff]);
      expect(result['status'], 'passed');
      await stream.close();
      await Future.wait(handled);
    } finally {
      api.close();
      await server.close(force: true);
    }
  });
}
