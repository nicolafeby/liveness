sealed class LivenessEvent {}

final class CameraStarted extends LivenessEvent {}

final class CameraPaused extends LivenessEvent {}

final class CameraRetried extends LivenessEvent {}
