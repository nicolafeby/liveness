import 'dart:typed_data';

import 'package:liveness_flutter/src/liveness/models/liveness_result.dart';

sealed class LivenessEvent {}

final class CameraStarted extends LivenessEvent {}

final class CameraPaused extends LivenessEvent {}

final class CameraRetried extends LivenessEvent {}

final class FrameResultReceived extends LivenessEvent {
  FrameResultReceived(this.generation, this.result, {this.resultImage});
  final int generation;
  final LivenessResult result;
  final Uint8List? resultImage;
}

final class SessionFailed extends LivenessEvent {
  SessionFailed(this.generation, this.message);
  final int generation;
  final String message;
}
