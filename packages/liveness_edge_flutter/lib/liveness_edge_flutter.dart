/// Offline face-liveness verification for Flutter.
///
/// Use [LivenessEdgeScreen] to run an active challenge and passive anti-spoof
/// check entirely on the device. A successful capture is returned as a
/// [LivenessResult].
library;

export 'src/core/challenge.dart'
    show
        FaceIdentitySensitivity,
        LivenessConfiguration,
        PassiveAntiSpoofSensitivity;
export 'src/core/detector.dart' show LivenessEdgeException;
export 'src/models/liveness_result.dart';
export 'src/models/liveness_status.dart';
export 'src/models/liveness_validation.dart';
export 'src/screen/liveness_edge_screen.dart';
