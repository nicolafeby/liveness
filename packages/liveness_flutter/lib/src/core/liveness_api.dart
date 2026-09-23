import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:liveness_flutter/src/liveness/models/liveness_result.dart';
import 'package:liveness_flutter/src/liveness/models/liveness_session.dart';

import 'alice_inspector.dart';
import 'liveness_endpoint_resolver.dart';

class LivenessApi {
  LivenessApi({String? baseUrl, bool enableAlice = true, LivenessEndpointResolver? endpointResolver})
    : _baseUrlOverride = _resolveOverride(baseUrl),
      _enableAlice = enableAlice,
      _endpointResolver = endpointResolver ?? LivenessEndpointResolver();

  static const _buildTimeUrl = String.fromEnvironment('LIVENESS_API_URL');

  final Uri? _baseUrlOverride;
  final bool _enableAlice;
  final LivenessEndpointResolver _endpointResolver;
  Future<Uri>? _resolvedBaseUrl;
  late final Dio _dio = Dio(
    BaseOptions(connectTimeout: const Duration(seconds: 5), receiveTimeout: const Duration(seconds: 10)),
  )..interceptors.addAll(_enableAlice ? [createAliceDioAdapter()] : []);

  Future<LivenessSession> createSession() async {
    try {
      final baseUrl = await _resolveBaseUrl();
      final response = await _dio.postUri<Map<String, dynamic>>(_endpoint(baseUrl, '/sessions'));
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
    final baseUrl = await _resolveBaseUrl();
    final streamUri = _endpoint(
      baseUrl,
      '/sessions/$sessionId/stream',
    ).replace(scheme: baseUrl.scheme == 'https' ? 'wss' : 'ws');
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

  Future<Uri> _resolveBaseUrl() => _resolvedBaseUrl ??= _resolveBaseUrlOnce();

  Future<Uri> _resolveBaseUrlOnce() async {
    final override = _baseUrlOverride;
    if (override != null) return override;
    try {
      return await _endpointResolver.resolve();
    } on LivenessEndpointException catch (error) {
      throw LivenessApiException(error.message);
    }
  }

  static Uri? _resolveOverride(String? baseUrl) {
    final value = baseUrl?.trim().isNotEmpty == true ? baseUrl!.trim() : _buildTimeUrl;
    if (value.isEmpty) return null;
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority || (uri.scheme != 'https' && uri.scheme != 'http')) {
      throw const LivenessApiException('URL server liveness tidak valid');
    }
    return uri;
  }

  static Uri _endpoint(Uri baseUrl, String suffix) {
    final basePath = baseUrl.path.endsWith('/') ? baseUrl.path.substring(0, baseUrl.path.length - 1) : baseUrl.path;
    return baseUrl.replace(path: '$basePath$suffix', query: null, fragment: null);
  }

  void close() {
    _dio.close(force: true);
    _endpointResolver.close();
  }
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
