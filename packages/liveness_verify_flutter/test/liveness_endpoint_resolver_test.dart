import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:liveness_verify_flutter/src/core/liveness_endpoint_resolver.dart';

void main() {
  test('resolves api_url from discovery endpoint', () async {
    final server = await _jsonServer({'api_url': 'https://liveness-api.example.com'});
    final resolver = LivenessEndpointResolver(discoveryUrl: Uri.parse('http://127.0.0.1:${server.port}/liveness.json'));
    try {
      expect(await resolver.resolve(), Uri.parse('https://liveness-api.example.com'));
    } finally {
      resolver.close();
      await server.close(force: true);
    }
  });

  test('rejects discovery response without api_url', () async {
    final server = await _jsonServer({'status': 'ok'});
    final resolver = LivenessEndpointResolver(discoveryUrl: Uri.parse('http://127.0.0.1:${server.port}/liveness.json'));
    try {
      await expectLater(
        resolver.resolve(),
        throwsA(
          isA<LivenessEndpointException>().having(
            (error) => error.message,
            'message',
            'Konfigurasi server liveness tidak valid',
          ),
        ),
      );
    } finally {
      resolver.close();
      await server.close(force: true);
    }
  });

  test('rejects invalid api_url', () async {
    final server = await _jsonServer({'api_url': 'not-a-url'});
    final resolver = LivenessEndpointResolver(discoveryUrl: Uri.parse('http://127.0.0.1:${server.port}/liveness.json'));
    try {
      await expectLater(
        resolver.resolve(),
        throwsA(
          isA<LivenessEndpointException>().having(
            (error) => error.message,
            'message',
            'URL server liveness tidak valid',
          ),
        ),
      );
    } finally {
      resolver.close();
      await server.close(force: true);
    }
  });
}

Future<HttpServer> _jsonServer(Map<String, dynamic> body) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    expect(request.method, 'GET');
    expect(request.uri.path, '/liveness.json');
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(body));
    await request.response.close();
  });
  return server;
}
