import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:liveness/liveness/models/liveness_result.dart';
import 'package:liveness/liveness/models/liveness_session.dart';

import 'alice_inspector.dart';

class LivenessApi {
  LivenessApi({String? baseUrl, bool enableAlice = true})
    : _baseUrl = baseUrl ?? const String.fromEnvironment('LIVENESS_API_URL', defaultValue: 'http://127.0.0.1:8000'),
      _enableAlice = enableAlice;

  final String _baseUrl;
  final bool _enableAlice;
  late final Dio _dio = Dio(
    BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 10),
    ),
  )..interceptors.addAll(_enableAlice ? [createAliceDioAdapter()] : []);

  Future<LivenessSession> createSession() async {
    try {
      final response = await _dio.post<Map<String, dynamic>>('/sessions');
      final body = response.data;
      if (body == null || body['success'] != true || body['data'] is! Map) {
        throw LivenessApiException(body?['message'] as String? ?? 'Respons server tidak valid');
      }
      return LivenessSession.fromJson(Map<String, dynamic>.from(body['data'] as Map));
    } on DioException catch (error) {
      final body = error.response?.data;
      final message = body is Map ? body['message'] : null;
      throw LivenessApiException(message is String ? message : 'Kamera atau server tidak dapat dihubungi');
    }
  }

  Future<LivenessStream> connect(String sessionId) async {
    final uri = Uri.parse(_baseUrl);
    final streamUri = uri.replace(
      scheme: uri.scheme == 'https' ? 'wss' : 'ws',
      path:
          '${uri.path.endsWith('/') ? uri.path.substring(0, uri.path.length - 1) : uri.path}/sessions/$sessionId/stream',
    );
    final socket = await WebSocket.connect(streamUri.toString()).timeout(const Duration(seconds: 5));
    final stream = LivenessStream(socket);
    try {
      await stream.ready();
      return stream;
    } catch (_) {
      await stream.close();
      rethrow;
    }
  }

  void close() => _dio.close(force: true);
}

class LivenessStream {
  LivenessStream(this._socket) : _messages = StreamIterator<dynamic>(_socket);

  final WebSocket _socket;
  final StreamIterator<dynamic> _messages;
  bool _closed = false;

  Future<void> ready() async => _next();

  Future<LivenessResult> submitFrame(List<int> jpeg) async {
    if (_closed) throw const LivenessApiException('Koneksi sesi sudah ditutup');
    _socket.add(jpeg);
    return _next();
  }

  Future<LivenessResult> _next() async {
    final hasMessage = await _messages.moveNext().timeout(const Duration(seconds: 10));
    if (!hasMessage) {
      throw const LivenessApiException('Koneksi sesi terputus');
    }
    final message = _messages.current;
    if (message is! String) {
      throw const LivenessApiException('Respons server tidak valid');
    }
    final json = jsonDecode(message) as Map<String, dynamic>;
    if (json['success'] != true) {
      throw LivenessApiException(json['message'] as String? ?? 'Frame tidak dapat diproses');
    }
    final data = json['data'];
    if (data is! Map) {
      throw const LivenessApiException('Respons server tidak valid');
    }
    return LivenessResult.fromJson(Map<String, dynamic>.from(data));
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _socket.close();
    await _messages.cancel();
  }
}

class LivenessApiException implements Exception {
  const LivenessApiException(this.message);
  final String message;
  @override
  String toString() => message;
}
