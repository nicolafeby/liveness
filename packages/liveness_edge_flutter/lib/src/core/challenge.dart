import 'dart:math' as math;

import '../models/liveness_result.dart';
import '../models/liveness_action.dart';
import '../models/liveness_status.dart';
import '../models/liveness_validation.dart';
import '../models/observation.dart';

/// Sensitivity for the passive anti-spoof check.
///
/// Use a built-in preset or [PassiveAntiSpoofSensitivity.withValue] for a
/// calibrated threshold. Higher values require a higher live score.
final class PassiveAntiSpoofSensitivity {
  const PassiveAntiSpoofSensitivity._(this.threshold);

  const PassiveAntiSpoofSensitivity.withValue(this.threshold)
    : assert(
        threshold >= 0 && threshold <= 1,
        'Passive anti-spoof threshold must be between 0 and 1',
      );

  static const low = PassiveAntiSpoofSensitivity._(.40);
  static const balanced = PassiveAntiSpoofSensitivity._(.50);
  static const high = PassiveAntiSpoofSensitivity._(.60);
  static const strict = PassiveAntiSpoofSensitivity._(.70);

  final double threshold;
}

/// Sensitivity for detecting a face replacement during one session.
///
/// Use a built-in preset or [FaceIdentitySensitivity.withValue] for a
/// calibrated threshold. Smaller values detect smaller landmark differences.
final class FaceIdentitySensitivity {
  const FaceIdentitySensitivity._(this.threshold);

  const FaceIdentitySensitivity.withValue(this.threshold)
    : assert(threshold > 0, 'Face identity threshold must be greater than 0');

  static const low = FaceIdentitySensitivity._(.16);
  static const balanced = FaceIdentitySensitivity._(.10);
  static const high = FaceIdentitySensitivity._(.06);
  static const strict = FaceIdentitySensitivity._(.035);

  final double threshold;
}

/// User-facing text shown during a liveness session.
///
/// All values default to English. Override only the values needed to localize
/// the experience or match your product's tone of voice.
class LivenessMessages {
  const LivenessMessages({
    this.oneFaceRequired =
        'Make sure exactly one face is visible and look at the camera.',
    this.faceNotDetected =
        'Face not detected. Verification has been restarted.',
    this.faceContinuityLost =
        'Face continuity was lost. Verification has been restarted.',
    this.faceTooDark = 'Your face is too dark. Move to a brighter place.',
    this.faceTooBright = 'Your face is too bright. Avoid direct light.',
    this.keepFacingCamera = 'Keep facing the camera.',
    this.keepFaceStable = 'Keep your face at the same distance and height.',
    this.blinkNotDetected = 'Blink not detected. Try blinking once more.',
    this.faceDirectionUnavailable =
        'Face the camera so your face direction can be detected.',
    this.eyesNotVisible =
        'Your eyes are not clearly visible. Face the camera and make sure they are not covered.',
    this.openEyes = 'Open both eyes and look at the camera.',
    this.differentFace =
        'A different face was detected. Verification has been restarted.',
    this.verifyingSameFace =
        'Keep facing the camera while we verify the same face.',
    this.moveCloser = 'Move closer to the camera.',
    this.moveFarther = 'Move farther from the camera.',
    this.moveRight = 'Move your face to the right.',
    this.moveLeft = 'Move your face to the left.',
    this.moveDown = 'Move your face down.',
    this.moveUp = 'Move your face up.',
    this.spoofingDetected = 'Verification failed. Spoofing was detected.',
    this.alignFace =
        'Face the camera and make sure both eyes are clearly visible.',
    this.blink = 'Blink both eyes once.',
    this.reopenEyes = 'Open both eyes again.',
    this.returnToCamera = 'Face the camera again.',
    this.turnHead = 'Turn your head slightly left or right.',
    this.turnLeft = 'Turn your head slightly to the left.',
    this.turnRight = 'Turn your head slightly to the right.',
    this.smile = 'Smile.',
    this.openMouth = 'Open your mouth.',
    this.returnToNeutral = 'Return to a neutral expression.',
    this.verificationComplete = 'Verification complete.',
    this.verificationFailed = 'Verification failed.',
    this.frontCameraUnavailable = 'Front camera is not available.',
    this.close = 'Close',
    this.preparingCamera = 'Preparing camera…',
    this.cameraPermissionHelp =
        'Make sure camera permission is enabled, then try again.',
    this.pleaseWait = 'Please wait a moment.',
    this.positionFaceInFrame = 'Position your entire face inside the frame.',
    this.holdStill = 'Keep your face still.',
    this.moveSlowly = 'Follow the instruction with a slow movement.',
    this.faceVerified = 'Face verified successfully.',
    this.verificationUnsuccessful = 'Verification was unsuccessful.',
    this.tryAgain = 'Try again',
  });

  final String oneFaceRequired;
  final String faceNotDetected;
  final String faceContinuityLost;
  final String faceTooDark;
  final String faceTooBright;
  final String keepFacingCamera;
  final String keepFaceStable;
  final String blinkNotDetected;
  final String faceDirectionUnavailable;
  final String eyesNotVisible;
  final String openEyes;
  final String differentFace;
  final String verifyingSameFace;
  final String moveCloser;
  final String moveFarther;
  final String moveRight;
  final String moveLeft;
  final String moveDown;
  final String moveUp;
  final String spoofingDetected;
  final String alignFace;
  final String blink;
  final String reopenEyes;
  final String returnToCamera;
  final String turnHead;
  final String turnLeft;
  final String turnRight;
  final String smile;
  final String openMouth;
  final String returnToNeutral;
  final String verificationComplete;
  final String verificationFailed;
  final String frontCameraUnavailable;
  final String close;
  final String preparingCamera;
  final String cameraPermissionHelp;
  final String pleaseWait;
  final String positionFaceInFrame;
  final String holdStill;
  final String moveSlowly;
  final String faceVerified;
  final String verificationUnsuccessful;
  final String tryAgain;
}

/// Settings that control an on-device liveness session.
class LivenessConfiguration {
  /// Creates configuration for a liveness session.
  ///
  /// Calibrate sensitivity with representative devices and attacks.
  const LivenessConfiguration({
    this.validations = const {
      LivenessValidation.blink,
      LivenessValidation.headTurn,
      LivenessValidation.smile,
      LivenessValidation.openMouth,
      LivenessValidation.passiveAntiSpoof,
    },
    this.minimumActiveChallenges = 3,
    this.maximumActiveChallenges = 4,
    this.timeout = const Duration(minutes: 2),
    this.maxFrames = 180,
    this.passiveAntiSpoofSensitivity = PassiveAntiSpoofSensitivity.balanced,
    this.faceIdentitySensitivity = FaceIdentitySensitivity.balanced,
    this.messages = const LivenessMessages(),
  });

  /// Checks enabled for this session.
  ///
  /// Face count, lighting, alignment, and stability remain mandatory input
  /// quality checks regardless of this selection.
  final Set<LivenessValidation> validations;

  /// Minimum number of randomly selected active challenges.
  final int minimumActiveChallenges;

  /// Maximum number of randomly selected active challenges.
  final int maximumActiveChallenges;

  /// Maximum wall-clock duration of a session.
  final Duration timeout;

  /// Maximum number of camera frames analyzed before the session fails.
  final int maxFrames;

  /// Passive anti-spoof sensitivity preset or custom value.
  final PassiveAntiSpoofSensitivity passiveAntiSpoofSensitivity;

  double get passiveThreshold => passiveAntiSpoofSensitivity.threshold;

  /// Face identity sensitivity preset or custom value.
  final FaceIdentitySensitivity faceIdentitySensitivity;

  /// Maximum normalized landmark distance still considered the same face.
  ///
  /// Identity continuity is evaluated only while the face is frontal. Two
  /// consecutive mismatches are required to avoid resets caused by noise.
  double get faceIdentityThreshold => faceIdentitySensitivity.threshold;

  /// User-facing copy used by the challenge and the ready-to-use screen.
  final LivenessMessages messages;
}

class LivenessChallenge {
  LivenessChallenge([
    this.configuration = const LivenessConfiguration(),
    math.Random? random,
  ]) : _started = DateTime.now(),
       _random = random ?? math.Random.secure() {
    if (configuration.validations.isEmpty) {
      throw ArgumentError.value(
        configuration.validations,
        'validations',
        'At least one validation is required',
      );
    }
    if (configuration.minimumActiveChallenges < 0 ||
        configuration.maximumActiveChallenges <
            configuration.minimumActiveChallenges) {
      throw ArgumentError(
        'Active challenge limits must be non-negative and ordered',
      );
    }
    final candidates = <LivenessAction>[
      if (_uses(LivenessValidation.blink)) LivenessAction.blink,
      if (_uses(LivenessValidation.headTurn))
        _random.nextBool() ? LivenessAction.turnLeft : LivenessAction.turnRight,
      if (_uses(LivenessValidation.smile)) LivenessAction.smile,
      if (_uses(LivenessValidation.openMouth)) LivenessAction.openMouth,
    ]..shuffle(_random);
    if (candidates.isNotEmpty) {
      final minimum = math.min(
        configuration.minimumActiveChallenges,
        candidates.length,
      );
      final maximum = math.min(
        configuration.maximumActiveChallenges,
        candidates.length,
      );
      final count = minimum + _random.nextInt(maximum - minimum + 1);
      _actions.addAll(candidates.take(count));
    }
  }
  final LivenessConfiguration configuration;
  final DateTime _started;
  final math.Random _random;
  final List<LivenessAction> _actions = [];
  List<LivenessAction> get actions => List.unmodifiable(_actions);
  int actionIndex = 0;
  int actionFrames = 0;
  LivenessStatus status = LivenessStatus.align;
  int frames = 0, aligned = 0, turned = 0, returned = 0;
  double? baseX, baseY, baseW, baseH, baseYaw;
  double baseSmile = 0, baseMouthOpen = 0;
  DateTime? blinkStartedAt,
      closedAt,
      unstableSince,
      eyesMissingSince,
      faceMissingSince,
      qualityIssueSince;
  String? qualityIssue;
  final List<double> scores = [];
  List<double>? faceIdentity;
  int identityMismatches = 0;

  /// Overall session progress, including alignment and randomized actions.
  ///
  /// Progress is derived from the action index rather than the current action
  /// type, so moving between differently ordered actions never makes it go
  /// backwards.
  double get progress {
    switch (status) {
      case LivenessStatus.align:
        return .08;
      case LivenessStatus.open:
        return .16;
      case LivenessStatus.passed:
        return 1;
      case LivenessStatus.failed:
        return 0;
      case LivenessStatus.blink:
      case LivenessStatus.smile:
      case LivenessStatus.openMouth:
        return _activeProgress(.25);
      case LivenessStatus.reopen:
      case LivenessStatus.returnNeutral:
        return _activeProgress(.65);
      case LivenessStatus.move:
        return _activeProgress(turned >= 2 ? .65 : .25);
    }
  }

  double _activeProgress(double phase) {
    const activeStart = .20;
    const activeShare = 1 - activeStart;
    final total = math.max(_actions.length, 1);
    return (activeStart + ((actionIndex + phase) / total) * activeShare).clamp(
      0.0,
      1.0,
    );
  }

  static const _inputGracePeriod = Duration(milliseconds: 750);
  static const _eyesGracePeriod = Duration(milliseconds: 500);
  static const _activeFaceLossGracePeriod = Duration(milliseconds: 400);
  static const _idleFaceLossGracePeriod = Duration(seconds: 2);

  bool _uses(LivenessValidation validation) =>
      configuration.validations.contains(validation);

  LivenessResult advance(LivenessObservation o) {
    final now = DateTime.now();
    if (++frames > configuration.maxFrames ||
        now.difference(_started) > configuration.timeout) {
      status = LivenessStatus.failed;
      return result();
    }
    if (o.faceCount != 1) {
      faceMissingSince ??= now;
      final message = configuration.messages.oneFaceRequired;
      final isActive = _isActiveChallenge;
      final gracePeriod = isActive
          ? _activeFaceLossGracePeriod
          : _idleFaceLossGracePeriod;
      return now.difference(faceMissingSince!) >= gracePeriod
          ? _reset(
              isActive
                  ? configuration.messages.faceContinuityLost
                  : configuration.messages.faceNotDetected,
            )
          : result(message);
    }
    faceMissingSince = null;
    if (o.lighting == 'dark') {
      return _handleInputIssue(now, configuration.messages.faceTooDark);
    }
    if (o.lighting == 'bright') {
      return _handleInputIssue(now, configuration.messages.faceTooBright);
    }
    qualityIssueSince = null;
    qualityIssue = null;
    final guidance = _alignment(o);
    final identityReset = _verifyFaceIdentity(o, guidance);
    if (identityReset != null) return identityReset;
    if (!o.eyesDetected) {
      if (!_isActiveChallenge) {
        return result(configuration.messages.eyesNotVisible);
      }
      eyesMissingSince ??= now;
      return now.difference(eyesMissingSince!) >= _eyesGracePeriod
          ? result(configuration.messages.eyesNotVisible)
          : result();
    }
    eyesMissingSince = null;
    if (_uses(LivenessValidation.passiveAntiSpoof) &&
        status != LivenessStatus.move &&
        guidance == null &&
        o.liveScore != null) {
      scores.add(o.liveScore!);
      if (scores.length > 8) scores.removeAt(0);
    }
    if (status == LivenessStatus.align) {
      if (guidance != null || !o.eyesOpen) {
        aligned = 0;
        return result(guidance ?? configuration.messages.openEyes);
      }
      if (++aligned >= 2) status = LivenessStatus.open;
    } else if (status == LivenessStatus.open) {
      if (guidance != null) return _reset(guidance);
      if (!o.eyesOpen) return result(configuration.messages.openEyes);
      baseX = o.faceCenterX;
      baseY = o.faceCenterY;
      baseW = o.faceWidth;
      baseH = o.faceHeight;
      baseYaw = o.yaw;
      baseSmile = o.smileScore ?? 0;
      baseMouthOpen = o.mouthOpenScore ?? 0;
      if (_actions.isNotEmpty) {
        _beginAction(now);
      } else if (_uses(LivenessValidation.passiveAntiSpoof) &&
          scores.length < 5) {
        return result(configuration.messages.keepFacingCamera);
      } else {
        return _finish();
      }
    } else if ((status == LivenessStatus.blink ||
            status == LivenessStatus.reopen) &&
        !_stable(o)) {
      unstableSince ??= now;
      return now.difference(unstableSince!) >= _inputGracePeriod
          ? result(configuration.messages.keepFaceStable)
          : result();
    } else if (status == LivenessStatus.blink) {
      unstableSince = null;
      if (!o.eyesOpen) {
        closedAt = now;
        status = LivenessStatus.reopen;
      } else if (now.difference(blinkStartedAt!) >=
          const Duration(seconds: 5)) {
        return result(configuration.messages.blinkNotDetected);
      } else {
        _adaptBaseline(o);
      }
    } else if (status == LivenessStatus.reopen) {
      unstableSince = null;
      if (now.difference(closedAt!).inMilliseconds > 1500) {
        _beginBlink(now);
        return result();
      }
      if (o.eyesOpen) {
        return _completeAction(now);
      }
    } else if (status == LivenessStatus.move) {
      if (o.yaw == null) {
        return result(configuration.messages.faceDirectionUnavailable);
      }
      baseYaw ??= o.yaw;
      final delta = o.yaw! - baseYaw!;
      final expected = _actions[actionIndex] == LivenessAction.turnLeft
          ? delta >= 15
          : delta <= -15;
      if (turned < 2) {
        turned = expected ? turned + 1 : 0;
      } else {
        returned = delta.abs() <= 8 && o.eyesOpen && guidance == null
            ? returned + 1
            : 0;
        if (returned >= 2) {
          return _completeAction(now);
        }
      }
    } else if (status == LivenessStatus.smile ||
        status == LivenessStatus.openMouth) {
      final score = status == LivenessStatus.smile
          ? o.smileScore
          : o.mouthOpenScore;
      if (score == null) return result(configuration.messages.pleaseWait);
      final baseline = status == LivenessStatus.smile
          ? baseSmile
          : baseMouthOpen;
      final absoluteThreshold = status == LivenessStatus.smile ? .45 : .50;
      final relativeThreshold = status == LivenessStatus.smile ? .25 : .30;
      final detected =
          score >= math.max(baseline + relativeThreshold, absoluteThreshold);
      actionFrames = detected ? actionFrames + 1 : 0;
      if (actionFrames >= 2) {
        actionFrames = 0;
        status = LivenessStatus.returnNeutral;
      }
    } else if (status == LivenessStatus.returnNeutral) {
      final action = _actions[actionIndex];
      final score = action == LivenessAction.smile
          ? o.smileScore
          : o.mouthOpenScore;
      if (score == null) return result(configuration.messages.pleaseWait);
      final baseline = action == LivenessAction.smile
          ? baseSmile
          : baseMouthOpen;
      actionFrames = score <= baseline + .12 ? actionFrames + 1 : 0;
      if (actionFrames >= 2) return _completeAction(now);
    }
    return result();
  }

  LivenessResult? _verifyFaceIdentity(
    LivenessObservation observation,
    String? guidance,
  ) {
    final identity = observation.faceIdentity;
    final isFrontal =
        guidance == null &&
        observation.eyesDetected &&
        (observation.yaw?.abs() ?? 0) <= 10;
    if (identity == null || identity.isEmpty || !isFrontal) return null;

    final baseline = faceIdentity;
    if (baseline == null || baseline.length != identity.length) {
      faceIdentity = List<double>.of(identity);
      identityMismatches = 0;
      return null;
    }

    var squaredDistance = 0.0;
    for (var i = 0; i < baseline.length; i++) {
      final delta = identity[i] - baseline[i];
      squaredDistance += delta * delta;
    }
    final distance = math.sqrt(squaredDistance / baseline.length);
    if (distance > configuration.faceIdentityThreshold) {
      identityMismatches++;
      if (identityMismatches >= 2) {
        return _reset(configuration.messages.differentFace);
      }
      return null;
    }

    // Keep the first aligned identity frozen for the entire session so a
    // replacement face cannot gradually become the new baseline.
    identityMismatches = 0;
    return null;
  }

  bool get _isActiveChallenge =>
      status == LivenessStatus.blink ||
      status == LivenessStatus.reopen ||
      status == LivenessStatus.move ||
      status == LivenessStatus.smile ||
      status == LivenessStatus.openMouth ||
      status == LivenessStatus.returnNeutral;

  LivenessResult _handleInputIssue(DateTime now, String message) {
    if (!_isActiveChallenge) return _reset(message);
    if (qualityIssue != message) {
      qualityIssue = message;
      qualityIssueSince = now;
    }
    return now.difference(qualityIssueSince!) >= _inputGracePeriod
        ? result(message)
        : result();
  }

  void _beginBlink(DateTime now) {
    status = LivenessStatus.blink;
    blinkStartedAt = now;
    unstableSince = null;
  }

  void _beginAction(DateTime now) {
    actionFrames = turned = returned = 0;
    switch (_actions[actionIndex]) {
      case LivenessAction.blink:
        _beginBlink(now);
      case LivenessAction.turnLeft || LivenessAction.turnRight:
        status = LivenessStatus.move;
      case LivenessAction.smile:
        status = LivenessStatus.smile;
      case LivenessAction.openMouth:
        status = LivenessStatus.openMouth;
    }
  }

  LivenessResult _completeAction(DateTime now) {
    actionIndex++;
    if (actionIndex < _actions.length) {
      _beginAction(now);
      return result();
    }
    return _finish();
  }

  void _adaptBaseline(LivenessObservation o) {
    const weight = .08;
    baseX = baseX! * (1 - weight) + o.faceCenterX * weight;
    baseY = baseY! * (1 - weight) + o.faceCenterY * weight;
    baseW = baseW! * (1 - weight) + o.faceWidth * weight;
    baseH = baseH! * (1 - weight) + o.faceHeight * weight;
  }

  bool _stable(LivenessObservation o) =>
      baseY != null &&
      (o.faceCenterY - baseY!).abs() <= .10 &&
      (o.faceCenterX - baseX!).abs() <= .10 &&
      (o.faceWidth - baseW!).abs() <= .10 &&
      (o.faceHeight - baseH!).abs() <= .10;
  String? _alignment(LivenessObservation o) {
    if (o.faceWidth < .20 || o.faceHeight < .25) {
      return configuration.messages.moveCloser;
    }
    if (o.faceWidth > .70 || o.faceHeight > .75) {
      return configuration.messages.moveFarther;
    }
    if (o.faceCenterX < .40) return configuration.messages.moveRight;
    if (o.faceCenterX > .60) return configuration.messages.moveLeft;
    if (o.faceCenterY < .38) return configuration.messages.moveDown;
    if (o.faceCenterY > .62) return configuration.messages.moveUp;
    return null;
  }

  LivenessResult _reset(String message) {
    status = LivenessStatus.align;
    aligned = turned = returned = 0;
    actionIndex = actionFrames = 0;
    baseX = baseY = baseW = baseH = baseYaw = null;
    blinkStartedAt = closedAt = unstableSince = eyesMissingSince =
        faceMissingSince = null;
    qualityIssueSince = null;
    qualityIssue = null;
    scores.clear();
    faceIdentity = null;
    identityMismatches = 0;
    return result(message);
  }

  double _median(List<double> values) {
    if (values.isEmpty) return 0;
    final sorted = [...values]..sort();
    final middle = sorted.length ~/ 2;
    return sorted.length.isOdd
        ? sorted[middle]
        : (sorted[middle - 1] + sorted[middle]) / 2;
  }

  LivenessResult _finish() {
    // Never pass on the first mismatching frame. A matching frame clears the
    // pending mismatch; a second mismatch resets the challenge.
    if (identityMismatches > 0) {
      return result(configuration.messages.verifyingSameFace);
    }
    if (!_uses(LivenessValidation.passiveAntiSpoof)) {
      status = LivenessStatus.passed;
      return result();
    }
    final score = _median(scores);
    status = scores.length >= 5 && score >= configuration.passiveThreshold
        ? LivenessStatus.passed
        : LivenessStatus.failed;
    return result(
      status == LivenessStatus.failed
          ? configuration.messages.spoofingDetected
          : null,
    );
  }

  LivenessResult result([String? message]) => LivenessResult(
    status: status,
    framesProcessed: frames,
    passiveScore: scores.isEmpty ? null : _median(scores),
    instruction:
        message ??
        switch (status) {
          LivenessStatus.align ||
          LivenessStatus.open => configuration.messages.alignFace,
          LivenessStatus.blink => configuration.messages.blink,
          LivenessStatus.reopen => configuration.messages.reopenEyes,
          LivenessStatus.move =>
            turned >= 2
                ? configuration.messages.returnToCamera
                : _actions[actionIndex] == LivenessAction.turnLeft
                ? configuration.messages.turnLeft
                : configuration.messages.turnRight,
          LivenessStatus.smile => configuration.messages.smile,
          LivenessStatus.openMouth => configuration.messages.openMouth,
          LivenessStatus.returnNeutral =>
            configuration.messages.returnToNeutral,
          LivenessStatus.passed => configuration.messages.verificationComplete,
          LivenessStatus.failed => configuration.messages.verificationFailed,
        },
  );
}
