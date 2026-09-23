import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:liveness_flutter/src/liveness/models/liveness_status.dart';

class LivenessState {
  const LivenessState({
    this.camera,
    this.error,
    this.instruction,
    this.status,
    this.resultImage,
  });

  final CameraController? camera;
  final String? error;
  final String? instruction;
  final LivenessStatus? status;
  final Uint8List? resultImage;
}
