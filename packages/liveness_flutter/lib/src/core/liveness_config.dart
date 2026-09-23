import 'liveness_config.g.dart';

/// Resolves the backend URL without requiring package consumers to configure it.
abstract final class LivenessConfig {
  static const _buildTimeUrl = String.fromEnvironment('LIVENESS_API_URL');

  static String resolveApiUrl([String? override]) {
    if (override != null && override.trim().isNotEmpty) return override.trim();
    if (_buildTimeUrl.isNotEmpty) return _buildTimeUrl;
    if (generatedLivenessApiUrl.isNotEmpty) return generatedLivenessApiUrl;
    return 'http://127.0.0.1:8000';
  }
}
