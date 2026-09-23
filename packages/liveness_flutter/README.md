# Liveness Flutter

Flutter client for the liveness service in this repository. Consumer applications
can use the package directly without configuring a server URL.

The package uses the project's configured liveness service by default. You can
also deploy and use your own backend.

```dart
import 'package:liveness_flutter/liveness_flutter.dart';

LivenessScreen(
  onSuccess: (image) {
    // Use the image produced by the liveness check.
  },
)
```

Android hosts must declare the `CAMERA` and `INTERNET` permissions. iOS hosts must
provide `NSCameraUsageDescription`. You can supply `baseUrl` for development or
testing.

The package can be installed directly from GitHub:

```yaml
dependencies:
  liveness_flutter:
    git:
      url: https://github.com/nicolafeby/research-liveness.git
      ref: liveness-v1.0.1
      path: packages/liveness_flutter
```

## Using Your Own Backend

You can customize the service by deploying the open-source
[`backend/`](https://github.com/nicolafeby/research-liveness/tree/main/backend)
code to your own server. The backend includes a FastAPI application, the required
models, and a Dockerfile.

For example, clone the repository and run the backend with Docker:

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

In production, expose both HTTP and WebSocket traffic through an HTTPS/WSS
endpoint. Configure DNS, TLS, the firewall, and a reverse proxy as appropriate
for your infrastructure. Full backend deployment details are available in the
[`backend/README.md`](https://github.com/nicolafeby/research-liveness/blob/main/backend/README.md).

Pass your server's public base URL to `LivenessScreen`:

```dart
LivenessScreen(
  baseUrl: 'https://liveness.example.com',
  onSuccess: (image) {
    // Continue with the verified image.
  },
)
```

Do not include `/sessions` or another endpoint path in `baseUrl`. The package
automatically uses HTTPS for API requests and WSS for frame streaming when the
base URL starts with `https://`.

Alternatively, provide the URL at build time:

```sh
flutter build apk \
  --dart-define=LIVENESS_API_URL=https://liveness.example.com
```

An explicit `baseUrl` passed to `LivenessScreen` takes precedence over the
build-time `LIVENESS_API_URL` value.

## GitHub Actions Configuration

This repository's mobile distribution workflow uses the GitHub environment
named `research`. If you fork the project and want to use its GitHub Actions
workflow, configure the following values:

| Name | GitHub scope | Required | Purpose |
| --- | --- | --- | --- |
| `LIVENESS_API_URL` | `research` environment variable | Yes | Public base URL of the backend embedded in the release APK |
| `FIREBASE_TESTER_GROUPS` | `research` environment variable | Yes | Firebase App Distribution group aliases, separated by commas |
| `FIREBASE_SERVICE_ACCOUNT` | `research` environment secret | Yes | Complete JSON private key for a service account with the Firebase App Distribution Admin role |
| `FVM_EXECUTABLE` | Repository variable | Only if FVM is not found automatically | Absolute path to the FVM executable on the self-hosted runner |

Create the environment from **Repository Settings → Environments → New
environment**, name it `research`, and add the first three values on its
configuration page. Add `FVM_EXECUTABLE`, when required, under **Repository
Settings → Secrets and variables → Actions → Variables**. It must be a repository
variable because the workflow's `ci` job does not use the `research` environment.

Keep `FIREBASE_SERVICE_ACCOUNT` as a secret. Do not store it as a variable or
commit its JSON file to source control. The backend deployment workflow does not
currently require a backend-specific secret or variable; it uses Docker installed
on a self-hosted Linux X64 runner labeled `liveness`.

For the complete runner and Firebase setup, see
[`mobile/README.md`](https://github.com/nicolafeby/research-liveness/blob/main/mobile/README.md).

## Testing

Pull requests that change the package automatically run `flutter analyze` and
`flutter test`. You can run the same checks locally from the package directory.
