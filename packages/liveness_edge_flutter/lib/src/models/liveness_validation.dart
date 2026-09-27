/// Liveness checks that can be enabled for a verification session.
enum LivenessValidation {
  /// Requires the user to blink once.
  blink,

  /// Requires the user to turn their head and face the camera again.
  headTurn,

  /// Requires the user to smile and return to a neutral expression.
  smile,

  /// Requires the user to open and close their mouth.
  openMouth,

  /// Requires the median on-device anti-spoof score to meet the threshold.
  passiveAntiSpoof,
}
