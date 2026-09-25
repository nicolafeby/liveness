import 'package:flutter_test/flutter_test.dart';
import 'package:liveness_edge_flutter/src/core/challenge.dart';
import 'package:liveness_edge_flutter/src/models/liveness_result.dart';
import 'package:liveness_edge_flutter/src/models/liveness_status.dart';
import 'package:liveness_edge_flutter/src/models/liveness_validation.dart';
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

  test('skips blink when it is disabled', () {
    final challenge = LivenessChallenge(
      const LivenessConfiguration(validations: {LivenessValidation.headTurn}),
    );

    challenge.advance(front);
    challenge.advance(front);
    challenge.advance(front);

    expect(challenge.status, LivenessStatus.move);
    expect(challenge.result().instruction, contains('Menoleh'));
    expect(challenge.result().passiveScore, isNull);
  });

  test('completes blink without running head turn or passive check', () {
    final challenge = LivenessChallenge(
      const LivenessConfiguration(validations: {LivenessValidation.blink}),
    );

    challenge.advance(front);
    challenge.advance(front);
    challenge.advance(front);
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
    final result = challenge.advance(front);

    expect(result.status, LivenessStatus.passed);
    expect(result.passiveScore, isNull);
  });

  test('ignores a transient eye-landmark loss during blink', () {
    final challenge = LivenessChallenge(
      const LivenessConfiguration(validations: {LivenessValidation.blink}),
    );

    challenge.advance(front);
    challenge.advance(front);
    challenge.advance(front);
    final result = challenge.advance(
      const LivenessObservation(
        faceCount: 1,
        eyesDetected: false,
        faceCenterX: .5,
        faceCenterY: .5,
        faceWidth: .4,
        faceHeight: .5,
      ),
    );

    expect(result.status, LivenessStatus.blink);
    expect(result.instruction, 'Kedipkan kedua mata sekali.');
  });

  test('does not reset blink after one unstable frame', () {
    final challenge = LivenessChallenge(
      const LivenessConfiguration(validations: {LivenessValidation.blink}),
    );

    challenge.advance(front);
    challenge.advance(front);
    challenge.advance(front);
    final result = challenge.advance(
      const LivenessObservation(
        faceCount: 1,
        eyesOpen: true,
        faceCenterX: .62,
        faceCenterY: .5,
        faceWidth: .4,
        faceHeight: .5,
      ),
    );

    expect(result.status, LivenessStatus.blink);
    expect(challenge.advance(front).status, LivenessStatus.blink);
  });

  test('keeps blink active while position correction is shown', () {
    final challenge = LivenessChallenge(
      const LivenessConfiguration(validations: {LivenessValidation.blink}),
    );
    const unstable = LivenessObservation(
      faceCount: 1,
      eyesOpen: true,
      faceCenterX: .65,
      faceCenterY: .5,
      faceWidth: .4,
      faceHeight: .5,
    );

    challenge.advance(front);
    challenge.advance(front);
    challenge.advance(front);
    for (var i = 0; i < 10; i++) {
      expect(challenge.advance(unstable).status, LivenessStatus.blink);
    }
    expect(challenge.advance(front).status, LivenessStatus.blink);
  });

  test('keeps active challenge when face is briefly lost', () {
    final challenge = LivenessChallenge(
      const LivenessConfiguration(validations: {LivenessValidation.blink}),
    );

    challenge.advance(front);
    challenge.advance(front);
    challenge.advance(front);
    final result = challenge.advance(const LivenessObservation(faceCount: 0));

    expect(result.status, LivenessStatus.blink);
    expect(result.instruction, contains('tepat satu wajah'));
  });

  test('restarts from alignment when face is missing for two seconds', () {
    final challenge = LivenessChallenge(
      const LivenessConfiguration(validations: {LivenessValidation.blink}),
    );

    challenge.advance(front);
    challenge.advance(front);
    challenge.advance(front);
    expect(challenge.status, LivenessStatus.blink);

    challenge.advance(const LivenessObservation(faceCount: 0));
    challenge.faceMissingSince = DateTime.now().subtract(
      const Duration(seconds: 2),
    );
    final reset = challenge.advance(const LivenessObservation(faceCount: 0));

    expect(reset.status, LivenessStatus.align);
    expect(reset.instruction, contains('Wajah tidak terdeteksi'));
  });

  test('cancels face-missing timer when face returns', () {
    final challenge = LivenessChallenge(
      const LivenessConfiguration(validations: {LivenessValidation.blink}),
    );

    challenge.advance(front);
    challenge.advance(front);
    challenge.advance(front);
    challenge.advance(const LivenessObservation(faceCount: 0));
    expect(challenge.faceMissingSince, isNotNull);

    challenge.advance(front);

    expect(challenge.status, LivenessStatus.blink);
    expect(challenge.faceMissingSince, isNull);
  });

  test('collects enough scores for passive check when blink is disabled', () {
    final challenge = LivenessChallenge(
      const LivenessConfiguration(
        validations: {
          LivenessValidation.headTurn,
          LivenessValidation.passiveAntiSpoof,
        },
      ),
    );

    for (var i = 0; i < 5; i++) {
      challenge.advance(front);
    }

    expect(challenge.status, LivenessStatus.move);
    expect(challenge.result().instruction, contains('Menoleh'));
  });

  test('completes a passive-only session without blink guidance', () {
    final challenge = LivenessChallenge(
      const LivenessConfiguration(
        validations: {LivenessValidation.passiveAntiSpoof},
      ),
    );

    LivenessResult? result;
    for (var i = 0; i < 5; i++) {
      result = challenge.advance(front);
      expect(result.instruction, isNot(contains('Kedip')));
    }

    expect(result!.status, LivenessStatus.passed);
  });

  test('rejects an empty validation set', () {
    expect(
      () => LivenessChallenge(
        const LivenessConfiguration(validations: <LivenessValidation>{}),
      ),
      throwsArgumentError,
    );
  });

  test('restarts from alignment when the face identity changes', () {
    const firstFace = LivenessObservation(
      faceCount: 1,
      eyesOpen: true,
      faceCenterX: .5,
      faceCenterY: .5,
      faceWidth: .4,
      faceHeight: .5,
      yaw: 0,
      faceIdentity: [0, 0, 0, 0],
    );
    const differentFace = LivenessObservation(
      faceCount: 1,
      eyesOpen: true,
      faceCenterX: .5,
      faceCenterY: .5,
      faceWidth: .4,
      faceHeight: .5,
      yaw: 0,
      faceIdentity: [1, 1, 1, 1],
    );
    final challenge = LivenessChallenge(
      const LivenessConfiguration(validations: {LivenessValidation.blink}),
    );

    challenge.advance(firstFace);
    challenge.advance(firstFace);
    challenge.advance(firstFace);
    expect(challenge.status, LivenessStatus.blink);

    expect(challenge.advance(differentFace).status, LivenessStatus.blink);
    final reset = challenge.advance(differentFace);

    expect(reset.status, LivenessStatus.align);
    expect(reset.instruction, contains('Wajah berbeda'));
  });

  test('does not reset identity on a single noisy frame', () {
    const identified = LivenessObservation(
      faceCount: 1,
      eyesOpen: true,
      faceCenterX: .5,
      faceCenterY: .5,
      faceWidth: .4,
      faceHeight: .5,
      yaw: 0,
      faceIdentity: [0, 0, 0, 0],
    );
    const noisy = LivenessObservation(
      faceCount: 1,
      eyesOpen: true,
      faceCenterX: .5,
      faceCenterY: .5,
      faceWidth: .4,
      faceHeight: .5,
      yaw: 0,
      faceIdentity: [1, 1, 1, 1],
    );
    final challenge = LivenessChallenge(
      const LivenessConfiguration(validations: {LivenessValidation.blink}),
    );

    challenge.advance(identified);
    challenge.advance(identified);
    challenge.advance(identified);
    challenge.advance(noisy);

    expect(challenge.advance(identified).status, LivenessStatus.blink);
  });
}
