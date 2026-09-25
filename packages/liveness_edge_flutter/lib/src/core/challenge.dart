import 'dart:math' as math;

import '../models/liveness_result.dart';
import '../models/liveness_status.dart';
import '../models/liveness_validation.dart';
import '../models/observation.dart';

/// Sensitivity for the passive anti-spoof check.
///
/// Use a built-in preset or [PassiveAntiSpoofSensitivity.withValue] for a
/// calibrated threshold. Higher values require a higher live score.
final class PassiveAntiSpoofSensitivity {
  const PassiveAntiSpoofSensitivity._(this.threshold);

  /// Creates a custom sensitivity with a threshold between `0` and `1`.
  const PassiveAntiSpoofSensitivity.withValue(this.threshold)
    : assert(
        threshold >= 0 && threshold <= 1,
        'Passive anti-spoof threshold must be between 0 and 1',
      );

  static const low = PassiveAntiSpoofSensitivity._(.40);
  static const balanced = PassiveAntiSpoofSensitivity._(.50);
  static const high = PassiveAntiSpoofSensitivity._(.60);
  static const strict = PassiveAntiSpoofSensitivity._(.70);

  /// Minimum passive liveness score for this preset.
  final double threshold;
}

/// Sensitivity for detecting a face replacement during one session.
///
/// Use a built-in preset or [FaceIdentitySensitivity.withValue] for a
/// calibrated threshold. Smaller values detect smaller landmark differences.
final class FaceIdentitySensitivity {
  const FaceIdentitySensitivity._(this.threshold);

  /// Creates a custom sensitivity with a threshold greater than `0`.
  const FaceIdentitySensitivity.withValue(this.threshold)
    : assert(threshold > 0, 'Face identity threshold must be greater than 0');

  static const low = FaceIdentitySensitivity._(.16);
  static const balanced = FaceIdentitySensitivity._(.10);
  static const high = FaceIdentitySensitivity._(.06);
  static const strict = FaceIdentitySensitivity._(.035);

  /// Maximum normalized landmark distance for this preset.
  final double threshold;
}

/// Settings that control an on-device liveness session.
class LivenessConfiguration {
  /// Creates configuration for a liveness session.
  ///
  /// Calibrate passive sensitivity with representative devices and attacks.
  const LivenessConfiguration({
    this.validations = const {
      LivenessValidation.blink,
      LivenessValidation.headTurn,
      LivenessValidation.passiveAntiSpoof,
    },
    this.timeout = const Duration(minutes: 2),
    this.maxFrames = 180,
    this.passiveAntiSpoofSensitivity = PassiveAntiSpoofSensitivity.balanced,
    this.faceIdentitySensitivity = FaceIdentitySensitivity.balanced,
  });

  /// Checks enabled for this session.
  ///
  /// Face count, lighting, alignment, and stability remain mandatory input
  /// quality checks regardless of this selection.
  final Set<LivenessValidation> validations;

  /// Maximum wall-clock duration of a session.
  final Duration timeout;

  /// Maximum number of camera frames analyzed before the session fails.
  final int maxFrames;

  /// Passive anti-spoof preset or custom value.
  final PassiveAntiSpoofSensitivity passiveAntiSpoofSensitivity;

  /// Minimum median passive anti-spoof score required to pass.
  double get passiveThreshold => passiveAntiSpoofSensitivity.threshold;

  /// Face identity sensitivity preset or custom value.
  final FaceIdentitySensitivity faceIdentitySensitivity;

  /// Maximum normalized landmark distance still considered the same face.
  ///
  /// Identity continuity is evaluated only while the face is frontal. Two
  /// consecutive mismatches are required to avoid resets caused by noise.
  double get faceIdentityThreshold => faceIdentitySensitivity.threshold;
}

class LivenessChallenge {
  LivenessChallenge([this.configuration = const LivenessConfiguration()])
    : _started = DateTime.now() {
    if (configuration.validations.isEmpty) {
      throw ArgumentError.value(
        configuration.validations,
        'validations',
        'At least one validation is required',
      );
    }
  }
  final LivenessConfiguration configuration;
  final DateTime _started;
  LivenessStatus status = LivenessStatus.align;
  int frames = 0, aligned = 0, turned = 0, returned = 0;
  double? baseX, baseY, baseW, baseH, baseYaw;
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
      const message =
          'Make sure exactly one face is visible and face the camera';
      final gracePeriod = _isActiveChallenge
          ? _activeFaceLossGracePeriod
          : _idleFaceLossGracePeriod;
      return now.difference(faceMissingSince!) >= gracePeriod
          ? _reset('Face continuity was lost. Verification has restarted.')
          : result(message);
    }
    faceMissingSince = null;
    if (o.lighting == 'dark') {
      return _handleInputIssue(
        now,
        'Your face is too dark. Move to a brighter area.',
      );
    }
    if (o.lighting == 'bright') {
      return _handleInputIssue(
        now,
        'Your face is too bright. Avoid direct light.',
      );
    }
    qualityIssueSince = null;
    qualityIssue = null;
    final guidance = _alignment(o);
    final identityReset = _verifyFaceIdentity(o, guidance);
    if (identityReset != null) return identityReset;
    if (!o.eyesDetected) {
      if (!_isActiveChallenge) return result(_eyes);
      eyesMissingSince ??= now;
      return now.difference(eyesMissingSince!) >= _eyesGracePeriod
          ? result(_eyes)
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
        return result(guidance ?? _openEyes);
      }
      if (++aligned >= 2) status = LivenessStatus.open;
    } else if (status == LivenessStatus.open) {
      if (guidance != null) return _reset(guidance);
      if (!o.eyesOpen) return result(_openEyes);
      baseX = o.faceCenterX;
      baseY = o.faceCenterY;
      baseW = o.faceWidth;
      baseH = o.faceHeight;
      if (_uses(LivenessValidation.blink)) {
        _beginBlink(now);
      } else if (_uses(LivenessValidation.passiveAntiSpoof) &&
          scores.length < 5) {
        return result('Keep facing the camera');
      } else if (_uses(LivenessValidation.headTurn)) {
        status = LivenessStatus.move;
      } else {
        return _finish();
      }
    } else if ((status == LivenessStatus.blink ||
            status == LivenessStatus.reopen) &&
        !_stable(o)) {
      unstableSince ??= now;
      return now.difference(unstableSince!) >= _inputGracePeriod
          ? result('Keep your face at the same distance and height')
          : result();
    } else if (status == LivenessStatus.blink) {
      unstableSince = null;
      if (!o.eyesOpen) {
        closedAt = now;
        status = LivenessStatus.reopen;
      } else if (now.difference(blinkStartedAt!) >=
          const Duration(seconds: 5)) {
        return result('No blink detected. Try blinking once more.');
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
        return result('Face the camera so your head direction can be detected');
      }
      baseYaw ??= o.yaw;
      final delta = (o.yaw! - baseYaw!).abs();
      if (turned < 2) {
        turned = delta >= 15 ? turned + 1 : 0;
      } else {
        returned = delta <= 8 && o.eyesOpen && guidance == null
            ? returned + 1
            : 0;
        if (returned >= 2) {
          return _finish();
        }
      }
    }
    return result();
  }

  static const _eyes =
      'Your eyes are not clearly visible. Face the camera and make sure they are not covered.';
  static const _openEyes = 'Open both eyes and look at the camera.';
  static const _differentFace =
      'A different face was detected. Verification has restarted.';

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
      if (identityMismatches >= 2) return _reset(_differentFace);
      return null;
    }

    // Keep the first aligned identity frozen for the entire session. Updating
    // it here could gradually let a replacement face become the new baseline.
    identityMismatches = 0;
    return null;
  }

  bool get _isActiveChallenge =>
      status == LivenessStatus.blink ||
      status == LivenessStatus.reopen ||
      status == LivenessStatus.move;

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
      return 'Move your face closer to the camera';
    }
    if (o.faceWidth > .70 || o.faceHeight > .75) {
      return 'Move your face away from the camera';
    }
    if (o.faceCenterX < .40) return 'Move your face to the right';
    if (o.faceCenterX > .60) return 'Move your face to the left';
    if (o.faceCenterY < .38) return 'Move your face down';
    if (o.faceCenterY > .62) return 'Move your face up';
    return null;
  }

  LivenessResult _reset(String message) {
    status = LivenessStatus.align;
    aligned = turned = returned = 0;
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
    // A single noisy identity reading is tolerated, but it must be followed by
    // a matching frame before the session is allowed to pass. A second
    // consecutive mismatch is handled by _verifyFaceIdentity and resets the
    // challenge.
    if (identityMismatches > 0) {
      return result('Keep facing the camera while we verify the same face');
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
          ? 'Verification failed: spoofing detected'
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
          LivenessStatus.align || LivenessStatus.open =>
            'Face the camera and make sure both eyes are clearly visible.',
          LivenessStatus.blink => 'Blink both eyes once.',
          LivenessStatus.reopen => 'Open both eyes again',
          LivenessStatus.move =>
            turned >= 2
                ? 'Face the camera again'
                : 'Turn your head slightly left or right',
          LivenessStatus.passed => 'Verification complete',
          LivenessStatus.failed => 'Verification failed',
        },
  );
}
