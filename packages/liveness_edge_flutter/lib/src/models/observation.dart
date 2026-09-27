class LivenessObservation {
  const LivenessObservation({
    required this.faceCount,
    this.eyesDetected = true,
    this.eyesOpen = false,
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
  });

  final int faceCount;
  final bool eyesDetected;
  final bool eyesOpen;
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

  factory LivenessObservation.fromMap(Map<Object?, Object?> map) =>
      LivenessObservation(
        faceCount: map['faceCount'] as int,
        eyesDetected:
            map['eyesDetected'] as bool? ?? map.containsKey('eyesOpen'),
        eyesOpen: map['eyesOpen'] as bool? ?? false,
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
      );
}
