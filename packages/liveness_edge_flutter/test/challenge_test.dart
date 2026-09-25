import 'package:flutter_test/flutter_test.dart';
import 'package:liveness_edge_flutter/src/core/challenge.dart';
import 'package:liveness_edge_flutter/src/models/liveness_status.dart';
import 'package:liveness_edge_flutter/src/models/observation.dart';

void main() {
  const front = LivenessObservation(
    faceCount: 1,
    eyesOpen: true,
    faceCenterX: .5,
    faceCenterY: .5,
    faceWidth: .4,
    faceHeight: .5,
    yaw: 0,
    liveScore: .9,
  );

  test('completes blink, turn, return, and passive challenge', () {
    final challenge = LivenessChallenge();
    challenge.advance(front);
    challenge.advance(front);
    challenge.advance(front);
    expect(challenge.status, LivenessStatus.blink);
    challenge.advance(
      const LivenessObservation(
        faceCount: 1,
        faceCenterX: .5,
        faceCenterY: .5,
        faceWidth: .4,
        faceHeight: .5,
        yaw: 0,
        liveScore: .9,
      ),
    );
    challenge.advance(front);
    challenge.advance(front);
    expect(challenge.status, LivenessStatus.move);
    challenge.advance(front);
    const turned = LivenessObservation(
      faceCount: 1,
      eyesOpen: true,
      faceCenterX: .5,
      faceCenterY: .5,
      faceWidth: .4,
      faceHeight: .5,
      yaw: 20,
      liveScore: .9,
    );
    challenge.advance(turned);
    challenge.advance(turned);
    challenge.advance(front);
    expect(challenge.advance(front).status, LivenessStatus.passed);
  });
}
