# Liveness

## Android CI and Firebase App Distribution

Pull requests that change the application or liveness package run `flutter analyze` and `flutter test` through [mobile-pr-check.yml](../.github/workflows/mobile-pr-check.yml) on a GitHub-hosted runner. [mobile-firebase-distribution.yml](../.github/workflows/mobile-firebase-distribution.yml) handles pushes to `main` and manual runs on the self-hosted Linux X64 runner labeled `liveness` (`ncladrserver`), including APK builds and distribution through Firebase App Distribution using the `research` GitHub environment.

The runner must remain online and have the Android SDK (including the required build tools and licenses), `git`, Python 3, and FVM. The workflow searches for FVM on `PATH`, under `~/.pub-cache/bin` and `~/.local/bin`, and at the `ncladrserver` path `/home/ncladr/fvm/bin/fvm`. If FVM moves, create a GitHub Actions **repository variable** named `FVM_EXECUTABLE` containing the absolute path to the `fvm` executable; variables in the `research` environment are unavailable to the `ci` job. Flutter **3.41.6** is pinned in `.fvmrc`. On push, the workflow runs `fvm use 3.41.6 --skip-pub-get` and uses the SDK selected by FVM for every Flutter step. FVM reuses its existing SDK cache and downloads the version only when it is missing. `FLUTTER_SDK_PATH` is not required. Pull requests continue to set up Flutter on a fresh GitHub-hosted runner. The workflow also configures Java 17 and Node.js 22, and downloads Gradle and dependencies when they are not cached.

For distribution, install Firebase CLI once on the self-hosted runner with `npm install --global firebase-tools@15.30.1`, and ensure that `firebase` is on the `PATH` of the account running the GitHub Actions runner. The CD job checks `firebase --version` and stops unless it is `15.30.1`; the workflow does not reinstall the CLI on every run. When upgrading the CLI, update both the runner version and the workflow's version check.

One-time distribution setup:

1. Open Firebase Console, select the `liveness` project, open **App Distribution** for the Android application `id.nicolafsalv.liveness`, and click **Get started**.
2. Create a tester group in App Distribution and add tester email addresses. Record the group **alias**, such as `qa-team`.
3. In the same Google Cloud project, create a service account with the **Firebase App Distribution Admin** role and download its private-key JSON. Store the entire JSON value as a GitHub Actions **environment secret** named `FIREBASE_SERVICE_ACCOUNT` in the `research` environment. Never commit the private key.
4. Create a GitHub Actions **environment variable** named `FIREBASE_TESTER_GROUPS` in the `research` environment and set it to the tester-group alias. Separate multiple aliases with commas.

The workflow reads the Firebase App ID from `android/app/google-services.json`. The distributed APK is a **release** build intended for testing. The Android build number (`versionCode`) automatically uses the GitHub Actions run number, while the application version (`versionName`) continues to follow `pubspec.yaml`. Firebase release notes contain messages from the five most recent commits. Verify the Android signing configuration before distributing the application more widely.

## Getting Started

This is a Flutter application. These resources are useful if you are new to Flutter:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

The [Flutter documentation](https://docs.flutter.dev/) provides tutorials, samples, mobile-development guidance, and a complete API reference.

## Liveness Backend

API response models use `json_serializable`. After changing fields or annotations under `packages/liveness_flutter/lib/src/liveness/models/`, run `flutter pub run build_runner build --delete-conflicting-outputs` from `packages/liveness_flutter/` and commit the generated `.g.dart` files.

Run `./script/run-backend.sh` from the project root, then start the application on an Android device connected over USB. The script enables `adb reverse tcp:8000 tcp:8000`; the application uses `http://127.0.0.1:8000` by default. It creates a session, opens a WebSocket, sends front-camera frames one at a time after receiving each server response, and displays instructions and results from the backend. Tap **Coba lagi** ("Try again") to create a new session after a failure.

For another device, configure the backend URL when starting Flutter, for example: `flutter run --dart-define=LIVENESS_API_URL=http://192.168.1.10:8000`. The backend must be reachable from the device; for LAN access, start Uvicorn with `--host 0.0.0.0`. Use HTTPS and appropriate platform security settings outside local development.

For APKs distributed by GitHub Actions, set the `LIVENESS_API_URL` variable in the `research` GitHub environment to a backend URL reachable by tester devices. The workflow passes it to `flutter build` through `--dart-define`. The release build fails when the variable is missing.

## Using the Flutter Package

The package's public entry point is `package:liveness_flutter/liveness_flutter.dart`, and its source is under `packages/liveness_flutter`. Consumers can install it directly as a Git dependency:

```yaml
dependencies:
  liveness_flutter:
    git:
      url: https://github.com/nicolafeby/liveness.git
      ref: liveness-v1.0.2
      path: packages/liveness_flutter
```

The simplest usage does not require a URL:

```dart
import 'package:liveness_flutter/liveness_flutter.dart';

LivenessScreen(
  onSuccess: (image) {
    // Use the image produced by the liveness check.
  },
)
```

Android hosts must declare the `CAMERA` and `INTERNET` permissions; iOS hosts must provide `NSCameraUsageDescription`. The `baseUrl` parameter remains available as an override for development and testing.
