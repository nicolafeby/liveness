import 'dart:async';

import 'package:flutter/services.dart';

import '../models/observation.dart';

/// Stable categories for errors produced by the native detector boundary.
enum LivenessEdgeErrorCode {
  initializationFailed,
  invalidFrame,
  analysisFailed,
  timeout,
  unavailable,
  closeFailed,
  unknown,
}

/// The detector operation that failed.
enum LivenessEdgeOperation { initialize, analyze, close }

/// An error reported while initializing or running the native detector.
class LivenessEdgeException implements Exception {
  const LivenessEdgeException(
    this.message, {
    this.code = LivenessEdgeErrorCode.unknown,
    this.operation,
    this.nativeCode,
    this.details,
  });

  final LivenessEdgeErrorCode code;
  final LivenessEdgeOperation? operation;
  final String? nativeCode;
  final Object? details;

  /// A description of the detector error.
  final String message;
  @override
  String toString() => message;
}

class LivenessEdgeDetector {
  LivenessEdgeDetector({
    MethodChannel channel = const MethodChannel('liveness_edge_flutter'),
    this.initializeTimeout = const Duration(seconds: 30),
    this.analysisTimeout = const Duration(seconds: 10),
    this.closeTimeout = const Duration(seconds: 5),
  }) : _channel = channel;

  final MethodChannel _channel;
  final Duration initializeTimeout;
  final Duration analysisTimeout;
  final Duration closeTimeout;

  Future<void> initialize() => _invoke<void>(
    'initialize',
    operation: LivenessEdgeOperation.initialize,
    timeout: initializeTimeout,
    fallbackMessage: 'The liveness model could not be loaded.',
  );

  Future<LivenessObservation> analyze(Uint8List frame) async {
    final result = await _invoke<Map<Object?, Object?>>(
      'analyze',
      arguments: frame,
      operation: LivenessEdgeOperation.analyze,
      timeout: analysisTimeout,
      fallbackMessage: 'The camera frame could not be analyzed.',
    );
    if (result == null) {
      throw const LivenessEdgeException(
        'The detector returned an empty result.',
        code: LivenessEdgeErrorCode.analysisFailed,
        operation: LivenessEdgeOperation.analyze,
      );
    }
    try {
      return LivenessObservation.fromMap(result);
    } catch (error) {
      throw LivenessEdgeException(
        'The detector returned an invalid result.',
        code: LivenessEdgeErrorCode.analysisFailed,
        operation: LivenessEdgeOperation.analyze,
        details: error,
      );
    }
  }

  Future<void> close() => _invoke<void>(
    'close',
    operation: LivenessEdgeOperation.close,
    timeout: closeTimeout,
    fallbackMessage: 'The liveness detector could not be closed.',
  );

  Future<T?> _invoke<T>(
    String method, {
    Object? arguments,
    required LivenessEdgeOperation operation,
    required Duration timeout,
    required String fallbackMessage,
  }) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments).timeout(timeout);
    } on TimeoutException catch (error) {
      throw LivenessEdgeException(
        'The native detector timed out while trying to ${operation.name}.',
        code: LivenessEdgeErrorCode.timeout,
        operation: operation,
        details: error,
      );
    } on MissingPluginException catch (error) {
      throw LivenessEdgeException(
        'The native liveness detector is unavailable.',
        code: LivenessEdgeErrorCode.unavailable,
        operation: operation,
        details: error,
      );
    } on PlatformException catch (error) {
      throw LivenessEdgeException(
        error.message ?? fallbackMessage,
        code: _mapErrorCode(error.code, operation),
        operation: operation,
        nativeCode: error.code,
        details: error.details,
      );
    }
  }

  static LivenessEdgeErrorCode _mapErrorCode(
    String nativeCode,
    LivenessEdgeOperation operation,
  ) => switch (nativeCode) {
    'invalid_frame' => LivenessEdgeErrorCode.invalidFrame,
    'initialize_failed' => LivenessEdgeErrorCode.initializationFailed,
    'analysis_failed' => LivenessEdgeErrorCode.analysisFailed,
    'close_failed' => LivenessEdgeErrorCode.closeFailed,
    _ => switch (operation) {
      LivenessEdgeOperation.initialize =>
        LivenessEdgeErrorCode.initializationFailed,
      LivenessEdgeOperation.analyze => LivenessEdgeErrorCode.analysisFailed,
      LivenessEdgeOperation.close => LivenessEdgeErrorCode.closeFailed,
    },
  };
}
