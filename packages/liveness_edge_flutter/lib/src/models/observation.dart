class LivenessObservation {
  const LivenessObservation({
    required this.faceCount,
    this.eyesDetected = true,
    this.faceVisible = true,
    this.faceOcclusionScore = 0,
    this.eyesOpen = false,
    this.eyeBlinkScore,
    this.faceCenterX = 0,
    this.faceCenterY = 0,
    this.faceWidth = 0,
    this.faceHeight = 0,
    this.lighting,
    this.yaw,
    this.smileScore,
    this.mouthOpenScore,
    this.liveScore,
    this.faceIdentity,
    this.upperFaceIdentity,
  });

  final int faceCount;
  final bool eyesDetected;

  /// Whether the general face-occlusion model considers the required facial
  /// regions visible.
  ///
  /// This is an input-quality signal, not proof that an occlusion is a spoof.
  final bool faceVisible;

  /// General face-occlusion confidence in the range 0 (clear) to 1 (covered).
  final double faceOcclusionScore;
  final bool eyesOpen;

  /// Highest MediaPipe blink score for either eye; lower means more open.
  final double? eyeBlinkScore;
  final double faceCenterX;
  final double faceCenterY;
  final double faceWidth;
  final double faceHeight;
  final String? lighting;
  final double? yaw;
  final double? smileScore;
  final double? mouthOpenScore;
  final double? liveScore;
  final List<double>? faceIdentity;

  /// Identity geometry limited to the eyes, brows, and upper face.
  ///
  /// Comparing this with [faceIdentity] lets the challenge distinguish a
  /// lower-face obstruction from an actual face replacement.
  final List<double>? upperFaceIdentity;

  factory LivenessObservation.fromMap(
    Map<Object?, Object?> map,
  ) => LivenessObservation(
    faceCount: map['faceCount'] as int,
    eyesDetected: map['eyesDetected'] as bool? ?? map.containsKey('eyesOpen'),
    faceVisible: map['faceVisible'] as bool? ?? true,
    faceOcclusionScore: (map['faceOcclusionScore'] as num?)?.toDouble() ?? 0,
    eyesOpen: map['eyesOpen'] as bool? ?? false,
    eyeBlinkScore: (map['eyeBlinkScore'] as num?)?.toDouble(),
    faceCenterX: (map['faceCenterX'] as num?)?.toDouble() ?? 0,
    faceCenterY: (map['faceCenterY'] as num?)?.toDouble() ?? 0,
    faceWidth: (map['faceWidth'] as num?)?.toDouble() ?? 0,
    faceHeight: (map['faceHeight'] as num?)?.toDouble() ?? 0,
    lighting: map['lighting'] as String?,
    yaw: (map['yaw'] as num?)?.toDouble(),
    smileScore: (map['smileScore'] as num?)?.toDouble(),
    mouthOpenScore: (map['mouthOpenScore'] as num?)?.toDouble(),
    liveScore: (map['liveScore'] as num?)?.toDouble(),
    faceIdentity: (map['faceIdentity'] as List<Object?>?)
        ?.map((value) => (value as num).toDouble())
        .toList(growable: false),
    upperFaceIdentity: (map['upperFaceIdentity'] as List<Object?>?)
        ?.map((value) => (value as num).toDouble())
        .toList(growable: false),
  );
}
