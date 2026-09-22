import 'package:camera/camera.dart';

class LivenessState {
  const LivenessState({this.camera, this.error});

  final CameraController? camera;
  final String? error;
}
