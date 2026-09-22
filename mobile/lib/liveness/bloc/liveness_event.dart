sealed class LivenessEvent {}

final class CameraStarted extends LivenessEvent {}

final class CameraPaused extends LivenessEvent {}

final class CameraRetried extends LivenessEvent {}

final class FrameResultReceived extends LivenessEvent {
  FrameResultReceived(this.generation, this.instruction, this.status);
  final int generation;
  final String instruction;
  final String status;
}

final class SessionFailed extends LivenessEvent {
  SessionFailed(this.generation, this.message);
  final int generation;
  final String message;
}
