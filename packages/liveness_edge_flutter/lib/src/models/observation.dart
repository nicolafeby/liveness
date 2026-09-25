class LivenessObservation {
  const LivenessObservation({
    required this.faceCount,
    this.eyesOpen = false,
    this.faceCenterX = 0,
    this.faceCenterY = 0,
    this.faceWidth = 0,
    this.faceHeight = 0,
    this.lighting,
    this.yaw,
    this.liveScore,
  });

  final int faceCount;
  final bool eyesOpen;
  final double faceCenterX;
  final double faceCenterY;
  final double faceWidth;
  final double faceHeight;
  final String? lighting;
  final double? yaw;
  final double? liveScore;

  factory LivenessObservation.fromMap(Map<Object?, Object?> map) =>
      LivenessObservation(
        faceCount: map['faceCount'] as int,
        eyesOpen: map['eyesOpen'] as bool? ?? false,
        faceCenterX: (map['faceCenterX'] as num?)?.toDouble() ?? 0,
        faceCenterY: (map['faceCenterY'] as num?)?.toDouble() ?? 0,
        faceWidth: (map['faceWidth'] as num?)?.toDouble() ?? 0,
        faceHeight: (map['faceHeight'] as num?)?.toDouble() ?? 0,
        lighting: map['lighting'] as String?,
        yaw: (map['yaw'] as num?)?.toDouble(),
        liveScore: (map['liveScore'] as num?)?.toDouble(),
      );
}
