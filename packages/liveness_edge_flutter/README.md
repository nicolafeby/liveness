# Liveness Edge Flutter

Private, offline face-liveness verification for Flutter. Camera frames, face
landmarks, active challenges, and passive anti-spoofing are processed on the
device; the package does not make network requests.

## Features

- Ready-to-use camera screen with face-position guidance.
- Active blink and head-turn challenge.
- Passive presentation-attack score using MiniFASNetV2.
- Native MediaPipe Face Landmarker and ONNX Runtime processing.
- Final verified capture returned as JPEG bytes.
- Android and iOS support with bundled models; no backend required.

## Platform support

| Platform | Minimum version | Status |
| --- | ---: | --- |
| Android | API 24 | Supported |
| iOS | 15.1 | Supported |

The host device needs a front-facing camera. Desktop and web are not supported.

## Installation

Add the package to your application:

```sh
flutter pub add liveness_edge_flutter
```

Alternatively, add it directly to `pubspec.yaml`:

```yaml
dependencies:
  liveness_edge_flutter: ^0.0.1
```

### Android setup

Add camera permission to `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.CAMERA" />
```

Ensure the application has `minSdk` 24 or newer.

### iOS setup

Add a camera usage description to `ios/Runner/Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>The camera is used to verify that you are present.</string>
```

Set the application deployment target to iOS 15.1 or newer.

## Usage

Import the package and push `LivenessEdgeScreen` as a full-screen route:

```dart
import 'package:flutter/material.dart';
import 'package:liveness_edge_flutter/liveness_edge_flutter.dart';

Future<LivenessResult?> captureLiveness(BuildContext context) async {
  LivenessResult? verifiedResult;

  await Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (routeContext) => LivenessEdgeScreen(
        configuration: const LivenessConfiguration(
          timeout: Duration(minutes: 2),
          maxFrames: 180,
          passiveThreshold: 0.5,
        ),
        onSuccess: (result) {
          verifiedResult = result;
          Navigator.of(routeContext).pop();
        },
        onCancel: () => Navigator.of(routeContext).pop(),
      ),
    ),
  );

  return verifiedResult;
}
```

On success, `result.imageBytes` contains the verified JPEG and
`result.passiveScore` contains the median passive anti-spoof score. The package
does not upload or persist either value.

### Configuration

| Property | Default | Description |
| --- | ---: | --- |
| `timeout` | 2 minutes | Maximum session duration. |
| `maxFrames` | 180 | Maximum analyzed frames before failure. |
| `passiveThreshold` | 0.5 | Minimum median passive score required to pass. |

Treat the default threshold as a starting point. Calibrate it using genuine
users, target devices, lighting conditions, and representative attacks.

### Callback behavior

- `onSuccess` runs once after both checks pass. It does not close the route;
  the host application controls navigation.
- `onCancel` runs when the close button is pressed. When omitted, the screen
  attempts to pop its route automatically.
- A failed or timed-out session shows a retry action. It does not invoke
  `onSuccess`.

## How it works

```text
Flutter camera frame
  -> upright, downsampled BGR frame
  -> MediaPipe Face Landmarker (bounds, blink, and head yaw)
  -> MiniFASNetV2 through ONNX Runtime (passive live score)
  -> challenge state machine (align, blink, turn, return)
  -> LivenessResult
```

Models are bundled with the native Android and iOS implementations. Processing
stays in application memory unless the host application stores or transmits the
returned image.

## Security and privacy

Client-side liveness is not tamper-proof. Do not use `result.passed` as the sole
authorization for banking, e-KYC, account recovery, or another high-risk server
transaction. For those flows, combine local inference with a server-issued
nonce, platform attestation, replay protection, and a trusted server-side
decision.

The passive model primarily targets printed-photo and screen-replay attacks. It
has not been validated by this project against masks, 3D attacks, camera
injection, rooted devices, or modified applications. The host application is
responsible for consent, retention, logging, screenshots, backups, and privacy
disclosures.

Review the licenses and suitability of MediaPipe, ONNX Runtime, and the bundled
MiniFASNetV2 model before commercial distribution.

## Troubleshooting

- **Camera permission denied:** request permission through the normal platform
  flow and ensure the manifest or plist entry above is present.
- **Front camera unavailable:** the capture screen reports an error and allows
  retrying; use a physical device with a front-facing camera.
- **Frequent passive failures:** test representative lighting and devices before
  adjusting `passiveThreshold`; lowering it increases spoof acceptance risk.
- **Simulator or emulator:** camera and native inference behavior can differ
  from physical hardware, so release validation should use real devices.

## Example and development

See [`example/lib/main.dart`](example/lib/main.dart) for a runnable integration.

```sh
flutter analyze
flutter test
cd example
flutter run
```

Bug reports and feature requests are welcome in the project
[issue tracker](https://github.com/nicolafeby/liveness/issues).
