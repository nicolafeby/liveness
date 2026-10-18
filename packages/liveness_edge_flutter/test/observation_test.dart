import 'package:flutter_test/flutter_test.dart';
import 'package:liveness_edge_flutter/src/models/observation.dart';

void main() {
  test('maps the native general face-occlusion signal', () {
    final observation = LivenessObservation.fromMap(const {
      'faceCount': 1,
      'faceVisible': false,
      'faceOcclusionScore': .73,
      'upperFaceIdentity': [0, 1, 2],
    });

    expect(observation.faceVisible, isFalse);
    expect(observation.faceOcclusionScore, .73);
    expect(observation.upperFaceIdentity, [0, 1, 2]);
  });

  test('keeps older native implementations backward compatible', () {
    final observation = LivenessObservation.fromMap(const {'faceCount': 1});

    expect(observation.faceVisible, isTrue);
    expect(observation.faceOcclusionScore, 0);
  });
}
