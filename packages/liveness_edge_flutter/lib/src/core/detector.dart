import 'package:flutter/services.dart';

import '../models/observation.dart';

/// An error reported while initializing or running the native detector.
class LivenessEdgeException implements Exception {
  /// Creates an exception with a user-readable [message].
  const LivenessEdgeException(this.message);

  /// A description of the detector error.
  final String message;
  @override
  String toString() => message;
}

class LivenessEdgeDetector {
  static const _channel = MethodChannel('liveness_edge_flutter');

  Future<void> initialize() async {
    try {
      await _channel.invokeMethod<void>('initialize');
    } on PlatformException catch (error) {
      throw LivenessEdgeException(
        error.message ?? 'The liveness model could not be loaded.',
      );
    }
  }

  Future<LivenessObservation> analyze(Uint8List frame) async {
    try {
      final result = await _channel.invokeMethod<Map<Object?, Object?>>(
        'analyze',
        frame,
      );
      if (result == null) {
        throw const LivenessEdgeException('Hasil deteksi kosong');
      }
      return LivenessObservation.fromMap(result);
    } on PlatformException catch (error) {
      throw LivenessEdgeException(
        error.message ?? 'The camera frame could not be analyzed.',
      );
    }
  }

  Future<void> close() => _channel.invokeMethod<void>('close');
}
