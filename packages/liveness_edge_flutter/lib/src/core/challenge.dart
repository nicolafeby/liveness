import '../models/liveness_result.dart';
import '../models/liveness_status.dart';
import '../models/liveness_validation.dart';
import '../models/observation.dart';

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
  }) : assert(
         passiveThreshold >= 0 && passiveThreshold <= 1,
         'passiveThreshold must be between 0 and 1',
       );

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
      qualityIssueSince;
  String? qualityIssue;
  final List<double> scores = [];

  static const _inputGracePeriod = Duration(milliseconds: 750);
  static const _eyesGracePeriod = Duration(milliseconds: 500);

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
      return _handleInputIssue(
        now,
        'Pastikan tepat satu wajah terlihat dan hadap kamera',
      );
    }
    if (o.lighting == 'dark') {
      return _handleInputIssue(
        now,
        'Wajah terlalu gelap, pindah ke tempat yang lebih terang',
      );
    }
    if (o.lighting == 'bright') {
      return _handleInputIssue(
        now,
        'Wajah terlalu terang, hindari cahaya langsung',
      );
    }
    qualityIssueSince = null;
    qualityIssue = null;
    final guidance = _alignment(o);
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
        return result('Tetap hadapkan wajah ke kamera');
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
          ? result('Jaga wajah tetap pada jarak dan tinggi yang sama')
          : result();
    } else if (status == LivenessStatus.blink) {
      unstableSince = null;
      if (!o.eyesOpen) {
        closedAt = now;
        status = LivenessStatus.reopen;
      } else if (now.difference(blinkStartedAt!) >=
          const Duration(seconds: 5)) {
        return result('Kedipan belum terdeteksi. Coba kedip sekali lagi.');
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
        return result('Hadapkan wajah ke kamera agar arah wajah terbaca');
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
      'Mata belum terlihat jelas. Hadap kamera dan pastikan area mata tidak tertutup.';
  static const _openEyes = 'Buka kedua mata dan lihat ke arah kamera.';

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
      return 'Dekatkan wajah ke kamera';
    }
    if (o.faceWidth > .70 || o.faceHeight > .75) {
      return 'Jauhkan wajah dari kamera';
    }
    if (o.faceCenterX < .40) return 'Geser wajah ke kanan';
    if (o.faceCenterX > .60) return 'Geser wajah ke kiri';
    if (o.faceCenterY < .38) return 'Geser wajah ke bawah';
    if (o.faceCenterY > .62) return 'Geser wajah ke atas';
    return null;
  }

  LivenessResult _reset(String message) {
    status = LivenessStatus.align;
    aligned = turned = returned = 0;
    baseX = baseY = baseW = baseH = baseYaw = null;
    blinkStartedAt = closedAt = unstableSince = eyesMissingSince = null;
    qualityIssueSince = null;
    qualityIssue = null;
    scores.clear();
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
          ? 'Verifikasi gagal, terdeteksi spoofing'
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
            'Hadapkan wajah ke kamera dan pastikan kedua mata terlihat jelas.',
          LivenessStatus.blink => 'Kedipkan kedua mata sekali.',
          LivenessStatus.reopen => 'Buka kembali kedua mata',
          LivenessStatus.move =>
            turned >= 2
                ? 'Kembali menghadap kamera'
                : 'Menoleh sedikit ke kiri atau kanan',
          LivenessStatus.passed => 'Verifikasi selesai',
          LivenessStatus.failed => 'Verifikasi gagal',
        },
  );
}
