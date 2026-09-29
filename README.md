# Flutter Face Liveness

This repository provides two Flutter packages for guided face-liveness
verification. Choose between fully on-device processing and server-assisted
verification according to your privacy, deployment, and performance needs.

## Packages

| Package | Processing | Network | Active challenges | Passive anti-spoofing | Platforms |
| --- | --- | --- | --- | --- | --- |
| [`liveness_edge_flutter`](packages/liveness_edge_flutter/) | On device | Not required | Randomized blink, head turn, smile, and open mouth | MiniFASNetV2 through native ONNX Runtime | Android API 24+ and iOS 15.1+ |
| [`liveness_verify_flutter`](packages/liveness_verify_flutter/) | Server assisted | HTTP and WebSocket | Align, blink, head turn, and return to center | MiniFASNetV2 on a compatible backend | Android and iOS |

Both packages include a ready-to-use front-camera screen, user guidance, camera
lifecycle handling, and a verified JPEG result. They differ primarily in where
face analysis and the final liveness decision run.

### Liveness Edge Flutter

[`liveness_edge_flutter`](packages/liveness_edge_flutter/README.md) keeps camera
frames, facial landmarks, active challenge state, and passive anti-spoofing on
the device. It bundles native MediaPipe Face Landmarker and ONNX Runtime models
for Android and iOS and does not make network requests.

Choose it when:

- face frames must remain on the device;
- the flow must work offline;
- Android API 24 and iOS 15.1 are acceptable minimum versions; and
- the application can accommodate the bundled native models and inference
  workload.

Install it with:

```sh
flutter pub add liveness_edge_flutter
```

Basic usage:

```dart
import 'package:flutter/material.dart';
import 'package:liveness_edge_flutter/liveness_edge_flutter.dart';

Future<LivenessResult?> verifyOnDevice(BuildContext context) async {
  LivenessResult? verifiedResult;

  await Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (routeContext) => LivenessEdgeScreen(
        configuration: const LivenessConfiguration(
          passiveAntiSpoofSensitivity: PassiveAntiSpoofSensitivity.high,
        ),
        onSuccess: (result) {
          verifiedResult = result;
          Navigator.of(routeContext).pop();
        },
        onFailed: (result) {
          debugPrint('Liveness failed: ${result.instruction}');
        },
      ),
    ),
  );

  return verifiedResult;
}
```

See the [package documentation](packages/liveness_edge_flutter/README.md) for
platform setup, localization, challenge selection, sensitivity presets,
callbacks, and security considerations.

### Liveness Verify Flutter

[`liveness_verify_flutter`](packages/liveness_verify_flutter/README.md) is a
lighter client that streams camera frames to a compatible backend. The backend
performs face analysis, maintains the challenge state, and calculates the
passive anti-spoofing result. A reference FastAPI implementation is included in
[`backend/`](backend/).

Choose it when:

- liveness decisions should be controlled by a trusted server;
- models and thresholds need to evolve without releasing the mobile app;
- sending biometric frames to your backend is allowed; and
- the device has reliable access to an HTTPS/WSS endpoint.

Install it with:

```sh
flutter pub add liveness_verify_flutter
```

Basic usage:

```dart
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:liveness_verify_flutter/liveness_verify_flutter.dart';

Future<void> verifyWithBackend(BuildContext context) async {
  await Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (routeContext) => LivenessScreen(
        baseUrl: 'https://liveness.example.com',
        onSuccess: (Uint8List imageBytes) {
          Navigator.of(routeContext).pop();
          // Continue with the verified JPEG.
        },
      ),
    ),
  );
}
```

See the [package documentation](packages/liveness_verify_flutter/README.md) for
backend URL resolution, platform permissions, API behavior, and deployment
guidance.

## Architecture

### On-device package

```text
Flutter front camera
  -> upright BGR frame
  -> native MediaPipe Face Landmarker
  -> native ONNX Runtime / MiniFASNetV2
  -> Dart randomized challenge state machine
  -> LivenessResult and verified JPEG
```

No face frames leave the application unless the host application explicitly
stores or transmits the result.

### Server-assisted package

```text
Flutter front camera
  -> liveness_verify_flutter
  -> HTTP session + WebSocket LVC1 frames
  -> FastAPI / OpenCV / YuNet / MiniFASNetV2
  -> challenge response
  -> verified JPEG callback
```

The reference backend processes frames in memory. Production operators remain
responsible for transport security, authentication, retention policy, and
infrastructure controls.

## Platform Setup

Both packages require camera permission.

Android (`android/app/src/main/AndroidManifest.xml`):

```xml
<uses-permission android:name="android.permission.CAMERA" />
```

The server-assisted package also needs internet permission:

```xml
<uses-permission android:name="android.permission.INTERNET" />
```

iOS (`ios/Runner/Info.plist`):

```xml
<key>NSCameraUsageDescription</key>
<string>The camera is used to verify that you are physically present.</string>
```

Use HTTPS/WSS in production. Local cleartext endpoints may require Android
network-security or iOS App Transport Security configuration.

## Repository Structure

```text
.
├── packages/
│   ├── liveness_edge_flutter/     # Offline, native on-device package
│   │   ├── android/               # Android MediaPipe and ONNX plugin
│   │   ├── ios/                   # iOS MediaPipe and ONNX plugin
│   │   ├── lib/                   # Public API, UI, and challenge state
│   │   ├── test/                  # State-machine and frame tests
│   │   └── example/               # Runnable Android/iOS example
│   └── liveness_verify_flutter/   # Server-assisted Flutter package
│       ├── lib/                   # UI, BLoC, API, and frame streaming
│       └── test/                  # Client and frame tests
├── backend/                       # Reference FastAPI liveness backend
├── mobile/                        # Reference app for server-assisted package
├── script/run-backend.sh          # Local backend and adb reverse helper
└── .github/workflows/             # Test, release, and deployment workflows
```

## Running the Examples

### On-device example

No backend is required:

```sh
cd packages/liveness_edge_flutter
flutter pub get
cd example
flutter run
```

Use a physical Android or iOS device for meaningful camera and native-inference
testing.

### Server-assisted example

Create the backend environment:

```sh
cd backend
python3 -m venv .venv
. .venv/bin/activate
pip install -r requirements.txt
cd ..
```

For an Android device connected through ADB, start the backend from the
repository root:

```sh
./script/run-backend.sh
```

Then run the reference app:

```sh
cd mobile
flutter pub get
flutter run
```

The default URL is `http://127.0.0.1:8000`. To use another reachable backend:

```sh
flutter run \
  --dart-define=LIVENESS_API_URL=https://liveness.example.com
```

See [backend/README.md](backend/README.md) for the API contract, Docker setup,
models, thresholds, and deployment details.

## Testing

Run checks for the on-device package:

```sh
cd packages/liveness_edge_flutter
flutter analyze
flutter test
```

Run checks for the server-assisted package:

```sh
cd packages/liveness_verify_flutter
flutter analyze
flutter test
```

After changing JSON-annotated models in `liveness_verify_flutter`, regenerate
the serializers:

```sh
cd packages/liveness_verify_flutter
dart run build_runner build --delete-conflicting-outputs
```

Run backend tests:

```sh
cd backend
.venv/bin/python -m unittest discover -p 'test_*.py'
```

## Security and Limitations

- Neither package should be the sole authorization signal for banking, e-KYC,
  account recovery, or another high-risk operation.
- The bundled passive model primarily targets printed-photo and screen-replay
  attacks. Masks, 3D attacks, camera injection, rooted devices, and modified
  applications have not been fully validated.
- Thresholds require calibration using representative users, devices, lighting,
  and attacks.
- For high-risk flows, combine liveness with server-issued nonces, replay
  protection, platform attestation, and a trusted server-side decision.
- The server-assisted package transmits biometric frames. Use encrypted
  transport and publish an appropriate consent, privacy, and retention policy.
- Client-side on-device results are private and offline, but a compromised host
  application can still tamper with callbacks or result handling.

## License and Third-Party Models

Project code is licensed under the [MIT License](LICENSE).

The repository bundles third-party MediaPipe, YuNet, ONNX Runtime, and
MiniFASNetV2 components or model files. Review their provenance, licenses, and
suitability before redistribution or commercial use. Additional model details
are documented in the package and [backend documentation](backend/README.md).
