# Liveness Detection

An end-to-end prototype that verifies whether the face in front of a camera belongs to a live, active user rather than a static image. The project combines a Flutter application for capturing camera frames with a FastAPI/OpenCV API that processes the liveness challenge.

> [!WARNING]
> This project is still a research prototype. Detection thresholds have not been calibrated against representative populations, devices, and attack conditions. Do not use its results as the sole basis for authentication, KYC, or other high-risk decisions.

## Key Features

- Real-time camera guidance for position, distance, face count, and lighting.
- Sequential active liveness checks: align the face, keep the eyes open, blink, turn, and face the camera again.
- Passive anti-spoofing over multiple frames using MiniFASNetV2 ONNX.
- Face and eye detection with OpenCV Haar cascades, plus face-direction estimation from YuNet landmarks.
- HTTP session creation and WebSocket frame streaming between the mobile app and backend.
- In-memory frame processing; the backend does not save frames.
- Unit tests for the state machine, detectors, streaming protocol, frame conversion, and API client.
- Docker backend deployment and Android APK distribution through Firebase App Distribution.

## Architecture

```text
Flutter front camera
       │
       │ LVC1 BGR frames (WebSocket)
       ▼
FastAPI ──► OpenCV Haar / YuNet ──► face, eye, light, and direction observations
       │
       ├──► MiniFASNetV2 ─────────► passive anti-spoofing score
       │
       └──► state machine ────────► instruction / passed / failed
                    │
                    └─────────────► Flutter UI
```

The verification flow is:

1. One face must remain centered at an appropriate size for two frames.
2. Both eyes must be visible, after which the user is asked to blink.
3. The eyes must reopen for two frames within 1.5 seconds.
4. The user turns slightly left or right for two frames, then faces the camera again for two frames.
5. The challenge passes only when at least five passive anti-spoofing samples are available and the median real-face score reaches the `0.5` threshold.

Sessions last 120 seconds, are limited to 180 frames, and accept frames at a minimum interval of 80 ms. The mobile app sends more frequently during the blink stage (about 100 ms) and about every 300 ms during other stages.

## Repository Structure

```text
.
├── backend/                 # FastAPI, state machine, OpenCV, and ONNX models
│   ├── main.py              # HTTP and WebSocket endpoints
│   ├── challenge.py         # Challenge rules and state
│   ├── detector.py          # Face, eye, light, yaw, and anti-spoofing detection
│   ├── *_test.py            # Backend tests
│   ├── Dockerfile
│   └── README.md            # Algorithm, API, and backend deployment details
├── mobile/                  # Flutter application
│   ├── lib/core/            # API client and camera-frame encoding
│   ├── lib/liveness/        # BLoC, models, and liveness screen
│   ├── test/                # Flutter tests
│   └── README.md            # CI and Firebase App Distribution details
├── script/run-backend.sh    # Local backend + adb reverse
└── .github/workflows/       # Backend deployment and mobile pipelines
```

## Prerequisites

- A Python version compatible with `backend/requirements.txt` (the Docker image uses Python 3.12).
- Flutter 3.41.6 and its matching Dart version; Flutter is pinned through `mobile/.fvmrc`.
- The Android SDK and an Android device with USB debugging for the simplest local workflow.
- `adb` available on `PATH`.

The iOS project structure and camera permission are configured, but the repository's current build and distribution automation targets Android.

## Running Locally

### 1. Set Up the Backend

```sh
cd backend
python3 -m venv .venv
. .venv/bin/activate
pip install -r requirements.txt
cd ..
```

Connect an Android device, enable USB debugging, and verify the connection:

```sh
adb devices
```

Start the backend from the repository root:

```sh
./script/run-backend.sh
```

The script configures `adb reverse tcp:8000 tcp:8000` and runs Uvicorn at `127.0.0.1:8000` with hot reload. OpenAPI documentation is available at <http://127.0.0.1:8000/docs>.

You can also run the backend without an Android device:

```sh
cd backend
.venv/bin/uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

### 2. Run the Flutter App

In another terminal:

```sh
cd mobile
fvm flutter pub get
fvm flutter run
```

The default application URL is `http://127.0.0.1:8000`, so it works directly with `adb reverse`. For a device on the same network, point the app to a backend address reachable from that device:

```sh
fvm flutter run \
  --dart-define=LIVENESS_API_URL=http://192.168.1.10:8000
```

Use HTTPS/WSS and appropriate platform security settings outside local development. Android currently permits cleartext traffic for development.

## API and Frame Protocol

| Method | Endpoint | Purpose |
| --- | --- | --- |
| `GET` | `/health` | Check backend process health |
| `POST` | `/sessions` | Create a liveness session |
| `POST` | `/sessions/{session_id}/frames` | Send one JPEG/PNG in the multipart `image` field |
| `WS` | `/sessions/{session_id}/stream` | Exchange binary frames and results sequentially |

HTTP examples:

```sh
curl -X POST http://127.0.0.1:8000/sessions
curl -X POST \
  -F 'image=@frame.jpg;type=image/jpeg' \
  http://127.0.0.1:8000/sessions/SESSION_ID/frames
```

The mobile app uses the internal `LVC1` binary format over WebSocket:

```text
4 bytes : ASCII "LVC1"
2 bytes : width, unsigned big-endian
2 bytes : height, unsigned big-endian
N bytes : BGR pixels, three bytes per pixel
```

Camera frames are rotated upright and scaled so the longest side is no more than 640 pixels. The WebSocket protocol requires one frame followed by one response and limits payloads to 5 MB. The HTTP endpoint accepts JPEG/PNG only.

API responses use this envelope:

```json
{
  "success": true,
  "message": "Frame berhasil diproses",
  "data": {
    "status": "blink",
    "passed": false,
    "instruction": "Kedipkan kedua mata sekali.",
    "frames_processed": 4
  },
  "errors": null
}
```

The Indonesian strings above are literal values produced by the API. Challenge states are `align`, `open`, `blink`, `reopen`, `move`, `passed`, and `failed`.

## Testing

Every pull request must pass checks for the liveness package, mobile application, and backend before it can be merged into the main branch.

Backend tests use `unittest`:

```sh
cd backend
.venv/bin/python -m unittest discover -p 'test_*.py'
```

Mobile tests use Flutter Test:

```sh
cd mobile
fvm flutter test
```

Run static analysis with:

```sh
cd mobile
fvm flutter analyze
```

After changing annotated models under `packages/liveness_flutter/lib/src/liveness/models/`, regenerate serializers:

```sh
cd packages/liveness_flutter
fvm flutter pub run build_runner build --delete-conflicting-outputs
```

## Docker and Deployment

### Use Your Own Backend Server

You can customize the deployment by hosting the code under `backend/` on your own server. The server may run the Python application directly or use the included Dockerfile. A basic Docker deployment is:

```sh
docker build -t liveness-backend backend
docker run -d --name liveness-backend --restart unless-stopped \
  -p 18080:8000 liveness-backend
curl http://127.0.0.1:18080/health
```

Expose the backend through an HTTPS/WSS endpoint, then configure that base URL as `LIVENESS_API_URL` when building the mobile application. The URL must be reachable from the tester's device. See [backend/README.md](backend/README.md) for Docker, reverse-proxy, health-check, and GitHub Actions deployment details.

A push to `main` that changes `backend/**` starts deployment on the self-hosted Linux X64 runner labeled `liveness`. The workflow uses the `research` GitHub environment, builds a container, publishes the backend on host port `18080`, performs a health check, and restores the previous container if the new deployment fails.

### GitHub Actions Secrets and Variables

Changes under `mobile/**` run Flutter tests. A push to `main` or a manual run then builds a release APK and distributes it through Firebase App Distribution. The required GitHub environment configuration is:

| Name | GitHub scope | Required | Purpose |
| --- | --- | --- | --- |
| `LIVENESS_API_URL` | `research` environment variable | Yes | Public backend base URL embedded in the release APK, for example `https://liveness.example.com` |
| `FIREBASE_TESTER_GROUPS` | `research` environment variable | Yes | One or more Firebase App Distribution group aliases, separated by commas |
| `FIREBASE_SERVICE_ACCOUNT` | `research` environment secret | Yes | Complete JSON private key for a service account with the Firebase App Distribution Admin role |
| `FVM_EXECUTABLE` | Repository variable | Only when FVM cannot be found automatically | Absolute path to the executable on the self-hosted runner, for example `/home/runner/fvm/bin/fvm` |

Create the `research` environment under **Repository Settings → Environments → New environment**. Add its variables and secret from the environment's configuration page. Add `FVM_EXECUTABLE`, when needed, under **Repository Settings → Secrets and variables → Actions → Variables** because the `ci` job does not use the `research` environment.

Do not add `FIREBASE_SERVICE_ACCOUNT` as a variable or commit it to the repository. Variables are suitable for non-sensitive configuration, while the service-account JSON must remain a secret. The backend deployment workflow currently needs no backend-specific secret or variable; it only references the `research` environment and relies on the self-hosted runner's local Docker access.

See [mobile/README.md](mobile/README.md) for runner and Firebase setup, and [backend/README.md](backend/README.md) for model, threshold, API, and backend deployment details.

## Limitations and Security

- MiniFASNetV2 is used as a single-image model; there is no dedicated temporal anti-replay model.
- Lighting, pose, alignment, and anti-spoofing thresholds are heuristic and require calibration with real data.
- Current evaluation targets primarily printed photos and screen displays; masks and 3D attacks have not been validated.
- Sessions live in one process's memory and are lost when the backend restarts or is deployed.
- The backend does not yet provide authentication, rate limiting, shared session storage, or TLS.
- The backend does not save frames, but biometric data is still transmitted over the network during a session. Use encrypted connections and an appropriate privacy policy in real environments.

## License and Third-Party Models

Project code is licensed under the [MIT License](LICENSE).

The repository also bundles third-party models:

- `face_detection_yunet_2023mar.onnx` from [OpenCV Zoo](https://github.com/opencv/opencv_zoo/tree/main/models/face_detection_yunet).
- `minifasnet_v2.onnx`, an ONNX conversion of MiniFASNetV2 from [Silent Face Anti-Spoofing](https://github.com/minivision-ai/Silent-Face-Anti-Spoofing); its conversion source is documented in [backend/README.md](backend/README.md).

Review each model's license and terms before distribution or commercial use.
