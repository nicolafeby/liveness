import 'package:dio/dio.dart';

class LivenessEndpointResolver {
  LivenessEndpointResolver({Dio? dio, Uri? discoveryUrl})
    : _dio =
          dio ??
          Dio(BaseOptions(connectTimeout: const Duration(seconds: 5), receiveTimeout: const Duration(seconds: 10))),
      discoveryUrl = discoveryUrl ?? Uri.parse('https://config.nicolaboard.my.id/liveness.json');

  final Dio _dio;
  final Uri discoveryUrl;

  Future<Uri> resolve() async {
    final response = await _dio.getUri<dynamic>(discoveryUrl);
    final body = response.data;
    final value = body is Map ? body['api_url'] : null;
    if (value is! String || value.trim().isEmpty) {
      throw const LivenessEndpointException('Konfigurasi server liveness tidak valid');
    }

    final uri = Uri.tryParse(value.trim());
    if (uri == null || !uri.hasScheme || !uri.hasAuthority || (uri.scheme != 'https' && uri.scheme != 'http')) {
      throw const LivenessEndpointException('URL server liveness tidak valid');
    }
    return uri;
  }

  void close() => _dio.close(force: true);
}

class LivenessEndpointException implements Exception {
  const LivenessEndpointException(this.message);

  final String message;

  @override
  String toString() => message;
}
