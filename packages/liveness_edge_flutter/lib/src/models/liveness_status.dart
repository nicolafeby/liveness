/// Current stage of the active liveness challenge.
enum LivenessStatus {
  /// The user must align their face with the on-screen guide.
  align,

  /// The detector is recording the initial eyes-open pose.
  open,

  /// The user must close their eyes once.
  blink,

  /// The user must reopen their eyes to complete the blink.
  reopen,

  /// The user must turn their head and then face forward again.
  move,

  /// Active and passive liveness checks succeeded.
  passed,

  /// The session timed out, exceeded its frame limit, or failed anti-spoofing.
  failed,
}

/// Convenience properties for [LivenessStatus].
extension LivenessStatusX on LivenessStatus {
  /// Whether no more frames are needed for this session.
  bool get isFinished =>
      this == LivenessStatus.passed || this == LivenessStatus.failed;
}
