import 'dart:typed_data';

import 'liveness_status.dart';

/// The latest state or final output of a liveness session.
class LivenessResult {
  /// Creates a liveness result.
  const LivenessResult({
    required this.status,
    required this.instruction,
    required this.framesProcessed,
    this.imageBytes,
    this.passiveScore,
  });

  /// Stage reached by the liveness challenge.
  final LivenessStatus status;

  /// Localized guidance suitable for presenting to the user.
  final String instruction;

  /// Number of camera frames processed in this session.
  final int framesProcessed;

  /// Final verified JPEG bytes, available on a successful screen capture.
  final Uint8List? imageBytes;

  /// Median passive anti-spoof score, where a higher value is more likely live.
  final double? passiveScore;

  /// Whether this result completed successfully.
  bool get passed => status == LivenessStatus.passed;
}
