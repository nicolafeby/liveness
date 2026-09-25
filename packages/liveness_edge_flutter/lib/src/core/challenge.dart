import '../models/liveness_result.dart';
import '../models/liveness_status.dart';
import '../models/observation.dart';

/// Settings that control an on-device liveness session.
class LivenessConfiguration {
  /// Creates configuration for a liveness session.
  ///
  /// [passiveThreshold] is expected to be between `0` and `1`. Calibrate it
  /// with data representative of the devices and attacks in your environment.
  const LivenessConfiguration({
    this.timeout = const Duration(minutes: 2),
    this.maxFrames = 180,
    this.passiveThreshold = .5,
  });

  /// Maximum wall-clock duration of a session.
  final Duration timeout;

  /// Maximum number of camera frames analyzed before the session fails.
  final int maxFrames;

  /// Minimum median passive anti-spoof score required to pass.
  final double passiveThreshold;
}

class LivenessChallenge {
  LivenessChallenge([this.configuration = const LivenessConfiguration()])
    : _started = DateTime.now();
  final LivenessConfiguration configuration;
  final DateTime _started;
  LivenessStatus status = LivenessStatus.align;
  int frames = 0,
      aligned = 0,
      blinkWait = 0,
      reopened = 0,
      turned = 0,
      returned = 0;
  double? baseX, baseY, baseW, baseH, baseYaw;
  DateTime? closedAt;
  final List<double> scores = [];

  LivenessResult advance(LivenessObservation o) {
    if (++frames > configuration.maxFrames ||
        DateTime.now().difference(_started) > configuration.timeout) {
      status = LivenessStatus.failed;
      return result();
    }
    if (o.faceCount != 1) {
      return _reset('Pastikan tepat satu wajah terlihat dan hadap kamera');
    }
    if (o.lighting == 'dark') {
      return _reset('Wajah terlalu gelap, pindah ke tempat yang lebih terang');
    }
    if (o.lighting == 'bright') {
      return _reset('Wajah terlalu terang, hindari cahaya langsung');
    }
    final guidance = _alignment(o);
    if (status != LivenessStatus.move &&
        guidance == null &&
        o.liveScore != null) {
      scores.add(o.liveScore!);
      if (scores.length > 8) scores.removeAt(0);
    }
    if (status == LivenessStatus.align) {
      if (guidance != null || !o.eyesOpen) {
        aligned = 0;
        return result(guidance ?? _eyes);
      }
      if (++aligned >= 2) status = LivenessStatus.open;
    } else if (status == LivenessStatus.open) {
      if (guidance != null) return _reset(guidance);
      if (!o.eyesOpen) return result(_eyes);
      baseX = o.faceCenterX;
      baseY = o.faceCenterY;
      baseW = o.faceWidth;
      baseH = o.faceHeight;
      status = LivenessStatus.blink;
    } else if ((status == LivenessStatus.blink ||
            status == LivenessStatus.reopen) &&
        !_stable(o)) {
      return _reset('Jaga wajah tetap pada jarak dan tinggi yang sama');
    } else if (status == LivenessStatus.blink) {
      if (!o.eyesOpen) {
        closedAt = DateTime.now();
        status = LivenessStatus.reopen;
        blinkWait = 0;
      } else if (++blinkWait >= 4) {
        blinkWait = 0;
        return result('Kedipan belum terdeteksi. Coba kedip sekali lagi.');
      }
    } else if (status == LivenessStatus.reopen) {
      if (DateTime.now().difference(closedAt!).inMilliseconds > 1500) {
        status = LivenessStatus.blink;
        reopened = 0;
        return result('Kedipan belum terdeteksi. Coba kedip sekali lagi.');
      }
      if (o.eyesOpen && ++reopened >= 2) status = LivenessStatus.move;
      if (!o.eyesOpen) reopened = 0;
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
      }
    }
    return result();
  }

  static const _eyes =
      'Mata belum terlihat jelas. Hadap kamera dan pastikan area mata tidak tertutup.';
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
    aligned = blinkWait = reopened = turned = returned = 0;
    baseX = baseY = baseW = baseH = baseYaw = null;
    closedAt = null;
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
