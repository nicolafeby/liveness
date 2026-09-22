import 'package:camera/camera.dart';
import 'package:liveness/liveness/models/liveness_status.dart';

class LivenessState {
  const LivenessState({this.camera, this.error, this.instruction, this.status});

  final CameraController? camera;
  final String? error;
  final String? instruction;
  final LivenessStatus? status;
}
