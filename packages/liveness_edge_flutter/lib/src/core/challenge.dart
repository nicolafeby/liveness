import 'dart:math' as math;

import '../models/liveness_result.dart';
import '../models/liveness_status.dart';
import '../models/liveness_validation.dart';
import '../models/observation.dart';

/// User-facing text shown during a liveness session.
///
/// All values default to English. Override only the values needed to localize
/// the experience or match your product's tone of voice.
class LivenessMessages {
  const LivenessMessages({
    this.oneFaceRequired = 'Make sure exactly one face is visible and look at the camera.',
    this.faceNotDetected = 'Face not detected. Verification has been restarted.',
    this.faceTooDark = 'Your face is too dark. Move to a brighter place.',
    this.faceTooBright = 'Your face is too bright. Avoid direct light.',
    this.keepFacingCamera = 'Keep facing the camera.',
    this.keepFaceStable = 'Keep your face at the same distance and height.',
    this.blinkNotDetected = 'Blink not detected. Try blinking once more.',
    this.faceDirectionUnavailable = 'Face the camera so your face direction can be detected.',
    this.eyesNotVisible = 'Your eyes are not clearly visible. Face the camera and make sure they are not covered.',
    this.openEyes = 'Open both eyes and look at the camera.',
    this.differentFace = 'A different face was detected. Verification has been restarted.',
    this.moveCloser = 'Move closer to the camera.',
    this.moveFarther = 'Move farther from the camera.',
    this.moveRight = 'Move your face to the right.',
    this.moveLeft = 'Move your face to the left.',
    this.moveDown = 'Move your face down.',
    this.moveUp = 'Move your face up.',
    this.spoofingDetected = 'Verification failed. Spoofing was detected.',
    this.alignFace = 'Face the camera and make sure both eyes are clearly visible.',
    this.blink = 'Blink both eyes once.',
    this.reopenEyes = 'Open both eyes again.',
    this.returnToCamera = 'Face the camera again.',
    this.turnHead = 'Turn your head slightly left or right.',
    this.verificationComplete = 'Verification complete.',
    this.verificationFailed = 'Verification failed.',
    this.frontCameraUnavailable = 'Front camera is not available.',
    this.close = 'Close',
    this.preparingCamera = 'Preparing camera…',
    this.cameraPermissionHelp = 'Make sure camera permission is enabled, then try again.',
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
  final String faceTooDark;
  final String faceTooBright;
  final String keepFacingCamera;
  final String keepFaceStable;
  final String blinkNotDetected;
  final String faceDirectionUnavailable;
  final String eyesNotVisible;
  final String openEyes;
  final String differentFace;
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
  /// [passiveThreshold] is expected to be between `0` and `1`. Calibrate it
  /// with data representative of the devices and attacks in your environment.
  const LivenessConfiguration({
    this.validations = const {
      LivenessValidation.blink,
      LivenessValidation.headTurn,
      LivenessValidation.passiveAntiSpoof,
    },
    this.timeout = const Duration(minutes: 2),
    this.maxFrames = 180,
    this.passiveThreshold = .5,
    this.faceIdentityThreshold = .22,
    this.messages = const LivenessMessages(),
  }) : assert(passiveThreshold >= 0 && passiveThreshold <= 1, 'passiveThreshold must be between 0 and 1'),
       assert(faceIdentityThreshold > 0, 'faceIdentityThreshold must be greater than 0');

  /// Checks enabled for this session.
  ///
  /// Face count, lighting, alignment, and stability remain mandatory input
  /// quality checks regardless of this selection.
  final Set<LivenessValidation> validations;

  /// Maximum wall-clock duration of a session.
  final Duration timeout;

  /// Maximum number of camera frames analyzed before the session fails.
  final int maxFrames;

  /// Minimum median passive anti-spoof score required to pass.
  final double passiveThreshold;

  /// Maximum normalized landmark distance still considered the same face.
  ///
  /// Identity continuity is evaluated only while the face is frontal. Two
  /// consecutive mismatches are required to avoid resets caused by noise.
  final double faceIdentityThreshold;

  /// User-facing copy used by the challenge and the ready-to-use screen.
  final LivenessMessages messages;
}

class LivenessChallenge {
  LivenessChallenge([this.configuration = const LivenessConfiguration()]) : _started = DateTime.now() {
    if (configuration.validations.isEmpty) {
      throw ArgumentError.value(configuration.validations, 'validations', 'At least one validation is required');
    }
  }
  final LivenessConfiguration configuration;
  final DateTime _started;
  LivenessStatus status = LivenessStatus.align;
  int frames = 0, aligned = 0, turned = 0, returned = 0;
  double? baseX, baseY, baseW, baseH, baseYaw;
  DateTime? blinkStartedAt, closedAt, unstableSince, eyesMissingSince, faceMissingSince, qualityIssueSince;
  String? qualityIssue;
  final List<double> scores = [];
  List<double>? faceIdentity;
  int identityMismatches = 0;

  static const _inputGracePeriod = Duration(milliseconds: 750);
  static const _eyesGracePeriod = Duration(milliseconds: 500);

  bool _uses(LivenessValidation validation) => configuration.validations.contains(validation);

  LivenessResult advance(LivenessObservation o) {
    final now = DateTime.now();
    if (++frames > configuration.maxFrames || now.difference(_started) > configuration.timeout) {
      status = LivenessStatus.failed;
      return result();
    }
    if (o.faceCount != 1) {
      faceMissingSince ??= now;
      final message = configuration.messages.oneFaceRequired;
      return now.difference(faceMissingSince!) >= const Duration(seconds: 2)
          ? _reset(configuration.messages.faceNotDetected)
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
      if (!_isActiveChallenge) return result(configuration.messages.eyesNotVisible);
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
      if (_uses(LivenessValidation.blink)) {
        _beginBlink(now);
      } else if (_uses(LivenessValidation.passiveAntiSpoof) && scores.length < 5) {
        return result(configuration.messages.keepFacingCamera);
      } else if (_uses(LivenessValidation.headTurn)) {
        status = LivenessStatus.move;
      } else {
        return _finish();
      }
    } else if ((status == LivenessStatus.blink || status == LivenessStatus.reopen) && !_stable(o)) {
      unstableSince ??= now;
      return now.difference(unstableSince!) >= _inputGracePeriod
          ? result(configuration.messages.keepFaceStable)
          : result();
    } else if (status == LivenessStatus.blink) {
      unstableSince = null;
      if (!o.eyesOpen) {
        closedAt = now;
        status = LivenessStatus.reopen;
      } else if (now.difference(blinkStartedAt!) >= const Duration(seconds: 5)) {
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
        if (_uses(LivenessValidation.headTurn)) {
          status = LivenessStatus.move;
        } else {
          return _finish();
        }
      }
    } else if (status == LivenessStatus.move) {
      if (o.yaw == null) {
        return result(configuration.messages.faceDirectionUnavailable);
      }
      baseYaw ??= o.yaw;
      final delta = (o.yaw! - baseYaw!).abs();
      if (turned < 2) {
        turned = delta >= 15 ? turned + 1 : 0;
      } else {
        returned = delta <= 8 && o.eyesOpen && guidance == null ? returned + 1 : 0;
        if (returned >= 2) {
          return _finish();
        }
      }
    }
    return result();
  }

  LivenessResult? _verifyFaceIdentity(LivenessObservation observation, String? guidance) {
    final identity = observation.faceIdentity;
    final isFrontal = guidance == null && observation.eyesDetected && (observation.yaw?.abs() ?? 0) <= 10;
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

    identityMismatches = 0;
    // Slowly absorb detector jitter without allowing a new face to replace the
    // baseline in one frame.
    const weight = .05;
    for (var i = 0; i < baseline.length; i++) {
      baseline[i] = baseline[i] * (1 - weight) + identity[i] * weight;
    }
    return null;
  }

  bool get _isActiveChallenge =>
      status == LivenessStatus.blink || status == LivenessStatus.reopen || status == LivenessStatus.move;

  LivenessResult _handleInputIssue(DateTime now, String message) {
    if (!_isActiveChallenge) return _reset(message);
    if (qualityIssue != message) {
      qualityIssue = message;
      qualityIssueSince = now;
    }
    return now.difference(qualityIssueSince!) >= _inputGracePeriod ? result(message) : result();
  }

  void _beginBlink(DateTime now) {
    status = LivenessStatus.blink;
    blinkStartedAt = now;
    unstableSince = null;
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
    baseX = baseY = baseW = baseH = baseYaw = null;
    blinkStartedAt = closedAt = unstableSince = eyesMissingSince = faceMissingSince = null;
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
    return sorted.length.isOdd ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2;
  }

  LivenessResult _finish() {
    if (!_uses(LivenessValidation.passiveAntiSpoof)) {
      status = LivenessStatus.passed;
      return result();
    }
    final score = _median(scores);
    status = scores.length >= 5 && score >= configuration.passiveThreshold
        ? LivenessStatus.passed
        : LivenessStatus.failed;
    return result(status == LivenessStatus.failed ? configuration.messages.spoofingDetected : null);
  }

  LivenessResult result([String? message]) => LivenessResult(
    status: status,
    framesProcessed: frames,
    passiveScore: scores.isEmpty ? null : _median(scores),
    instruction:
        message ??
        switch (status) {
          LivenessStatus.align || LivenessStatus.open => configuration.messages.alignFace,
          LivenessStatus.blink => configuration.messages.blink,
          LivenessStatus.reopen => configuration.messages.reopenEyes,
          LivenessStatus.move => turned >= 2 ? configuration.messages.returnToCamera : configuration.messages.turnHead,
          LivenessStatus.passed => configuration.messages.verificationComplete,
          LivenessStatus.failed => configuration.messages.verificationFailed,
        },
  );
}
