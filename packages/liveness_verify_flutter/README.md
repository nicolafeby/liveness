# Liveness Verify Flutter

A Flutter client for guided face-liveness verification with active challenges
and server-side passive anti-spoofing. The package provides a ready-to-use
camera screen, streams frames to a compatible backend, and returns a JPEG image
after verification succeeds.

## Features

- Front-camera preview with face-positioning guidance.
- Sequential align, eyes-open, blink, head-turn, and return-to-center checks.
- Server-side passive anti-spoofing across multiple frames.
- HTTP session creation and WebSocket frame streaming.
- Automatic camera cleanup when the application is paused or the screen closes.
- A verified JPEG image returned as `Uint8List` after a successful challenge.
- Optional default service discovery, build-time backend configuration, or an
  explicit backend URL.

## How It Works

```text
Flutter host application
        │
        ▼
LivenessScreen ──► front camera and guided active challenges
        │
        │ HTTP + WebSocket frames
        ▼
FastAPI backend ──► OpenCV / YuNet face analysis
        │
        ├─────────► MiniFASNetV2 passive anti-spoofing
        │
        └─────────► challenge state and instructions
                          │
                          ▼
                 verified JPEG callback
```

Camera capture and user guidance run in Flutter. Face analysis, challenge-state
evaluation, and passive anti-spoofing run on the backend. This is not a fully
on-device liveness solution.

The reference implementation uses Flutter Camera, BLoC, Dio, FastAPI, OpenCV,
YuNet, and MiniFASNetV2. See the
[project repository](https://github.com/nicolafeby/research-liveness) for the
complete architecture and backend source.

## Requirements

- Flutter with Dart `>=3.11.4 <4.0.0`.
- A front-facing camera.
- Network access to the default service or a compatible backend.
- Android or iOS host permissions configured as described below.

## Installation

Add the package from pub.dev:

```sh
flutter pub add liveness_verify_flutter
```

Or add it to `pubspec.yaml`:

```yaml
dependencies:
  liveness_verify_flutter: ^0.1.0
```

Until a release is available on pub.dev, the package can be installed from the
repository:

```yaml
dependencies:
  liveness_verify_flutter:
    git:
      url: https://github.com/nicolafeby/research-liveness.git
      ref: main
      path: packages/liveness_verify_flutter
```

For reproducible builds, replace `main` with an existing package release tag.

## Platform Setup

### Android

Add camera and internet permissions to
`android/app/src/main/AndroidManifest.xml`:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.CAMERA" />
    <uses-permission android:name="android.permission.INTERNET" />

    <application>
        <!-- Existing application configuration. -->
    </application>
</manifest>
```

Use HTTPS/WSS in production. If cleartext HTTP is required for local Android
development, configure the host application according to Android's network
security requirements.

### iOS

Add a camera usage description to `ios/Runner/Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>The camera is used to verify that you are physically present.</string>
```

Use HTTPS/WSS in production. Non-secure development endpoints might require
additional App Transport Security configuration in the host application.

## Usage

Push `LivenessScreen` like any other Flutter route:

```dart
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:liveness_verify_flutter/liveness_verify_flutter.dart';

Future<void> startLivenessCheck(BuildContext context) async {
  await Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => LivenessScreen(
        onSuccess: (Uint8List imageBytes) {
          // imageBytes contains the verified frame encoded as JPEG.
          Navigator.of(context).pop();
          // Continue your application flow with imageBytes.
        },
        onCancel: () {
          Navigator.of(context).pop();
        },
      ),
    ),
  );
}
```

`onSuccess` is called after the backend reports that the challenge passed. The
screen does not close automatically, so the host application controls navigation
and what happens to the returned image.

If `onCancel` is omitted, the close button calls `Navigator.maybePop(context)`.

## Backend Configuration

When no URL is supplied, the package resolves the project's configured default
liveness service. For production systems, operate a compatible backend and pass
its public URL explicitly.

### Runtime URL

Pass `baseUrl` to `LivenessScreen`:

```dart
LivenessScreen(
  baseUrl: 'https://liveness.example.com',
  onSuccess: (imageBytes) {
    // Continue with the verified JPEG.
  },
)
```

### Build-time URL

Alternatively, provide `LIVENESS_API_URL` when building or running the host app:

```sh
flutter run \
  --dart-define=LIVENESS_API_URL=https://liveness.example.com
```

An explicit `baseUrl` takes precedence over `LIVENESS_API_URL`, which takes
precedence over default service discovery.

Provide only the server base URL; do not append `/sessions` or another endpoint.
An `https://` base URL automatically uses `wss://` for frame streaming.

## Run Your Own Backend

The open-source reference backend includes the FastAPI application, challenge
state machine, OpenCV integration, ONNX models, and Dockerfile:

```sh
git clone https://github.com/nicolafeby/research-liveness.git
cd research-liveness
docker build -t liveness-backend backend
docker run -d \
  --name liveness-backend \
  --restart unless-stopped \
  -p 18080:8000 \
  liveness-backend
curl http://127.0.0.1:18080/health
```

See the
[backend documentation](https://github.com/nicolafeby/research-liveness/blob/main/backend/README.md)
for its API contract, model details, reverse-proxy configuration, and deployment
instructions.

## Verification Flow

The reference backend asks the user to:

1. Position one face within the guide.
2. Keep both eyes visible.
3. Blink and reopen both eyes.
4. Turn slightly left or right.
5. Face the camera again.

The challenge succeeds only after the required active checks and passive
anti-spoofing samples pass the backend thresholds. Backend implementations and
thresholds can evolve independently of the package.

## Privacy, Security, and Limitations

- Face frames are biometric data and are transmitted to a backend during each
  session. Use HTTPS/WSS and publish an appropriate privacy and retention policy.
- The reference backend processes frames in memory, but operators are responsible
  for verifying and documenting the behavior of their deployment.
- The reference thresholds are heuristic and require evaluation with target
  devices, users, lighting conditions, and expected presentation attacks.
- Current evaluation primarily targets printed photos and screen displays. Masks,
  3D attacks, injection attacks, and compromised clients have not been fully
  validated.
- Client-side success callbacks must not be treated as tamper-proof. High-risk
  systems should validate session results through a trusted server-side flow.
- Add authentication, authorization, rate limiting, monitoring, and replay
  protections before exposing a backend publicly.

## Testing

Run checks from the package directory:

```sh
flutter pub get
flutter analyze
flutter test
dart pub publish --dry-run
```

After changing JSON-annotated models, regenerate serializers:

```sh
dart run build_runner build --delete-conflicting-outputs
```

## License

The package source is available under the
[MIT License](https://github.com/nicolafeby/research-liveness/blob/main/LICENSE).
The reference backend includes third-party models with their own provenance and
terms. Review those terms before redistribution or commercial use.
