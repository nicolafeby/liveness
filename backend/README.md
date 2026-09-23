# Liveness Detection Backend

Python API prototype for a camera challenge: keep the face centered for two frames → open the eyes → close them for one frame → reopen them for two frames within 1.5 seconds → turn slightly left or right for two frames → face the camera again for two frames. The mobile client uses a camera stream so it can send frames more frequently during the blink stage. Frontal-face, eye, and lighting detection use OpenCV Haar cascades; the turn stage uses the five eye and nose landmarks from OpenCV's YuNet model. Alignment uses the position and size of the face bounding box in the camera image; these coordinates have not yet been calibrated against the preview crop and mobile guide frame. A `passed` result also requires passive anti-spoofing scores from at least five color face frames. This remains a prototype; do not use its result as the sole basis for authentication or KYC.

Passive anti-spoofing uses [MiniFASNetV2 from Silent Face Anti-Spoofing](https://github.com/minivision-ai/Silent-Face-Anti-Spoofing) as an [ONNX conversion](https://huggingface.co/garciafido/minifasnet-v2-anti-spoofing-onnx), with SHA-256 `d7b3cd9ba8a7ceb13baa8c4720902e27ca3112eff52f926c08804af6b6eecc7b`. Its input is an 80×80 BGR face crop with a 2.7× margin and **0–255** pixel values, following the original project's preprocessing. Output index **1** represents a real face according to the original project's test code; indices 0 and 2 are jointly treated as presentation attacks. The model targets photos and screen displays, including replay attacks, but the current decision combines scores from multiple frames produced by a single-image model; there is no dedicated temporal motion model. A session is not terminated merely because its first five scores are low. `passed` requires a median real-face score of at least 0.5 at the end of the challenge; a lower score produces a message saying that the check was inconclusive, without claiming that face media was detected. This threshold is preliminary and must be calibrated using real cameras, lighting conditions, printed photos, phone/monitor screens, and video replays. Specific attack types are not reported because the two attack-class labels have not been verified. Mask and 3D spoofs are not yet validation targets.

Lighting is measured over the central face region in the original image. A frame whose median intensity is below 55 or above 205, or whose face region is more than 45% nearly black/white, restarts alignment and prompts the user to correct the lighting. These thresholds are heuristic and must be tested on real devices and conditions; this check does not detect sunglasses or guarantee spoofing resistance.

Eye detection tries both the standard eye Haar cascade and the `eye_tree_eyeglasses` variant on a contrast-equalized face, then retries with local contrast enhancement if needed. Two candidates are accepted only if they lie on the left and right sides of the face at similar heights. This reduces failures when one cascade misses an eye, but sensitivity changes still need testing with real camera recordings, including closed eyes.

During the turn stage, YuNet estimates changes in face direction from the nose position relative to both eyes. The first frame becomes the reference; an estimated change of at least 15° for two frames is accepted as a turn, followed by a change of at most 8° for two frames to count as facing the camera again. These angles are approximations based on two-dimensional landmarks, not three-dimensional pose measurements. The existing grayscale frame remains in use; the turn stage converts it to a three-channel image for model input. If face tracking or lighting is interrupted, the stage is retained for up to two seconds to give the user time to correct their position. The thresholds must be calibrated on real devices and users.

The `face_detection_yunet_2023mar.onnx` model comes from [OpenCV Zoo](https://github.com/opencv/opencv_zoo/tree/main/models/face_detection_yunet) and is bundled in the backend image.

## Running the Backend

Pull requests that change `backend/` run the full unit test suite with Python 3.12 through `.github/workflows/backend-pr-check.yml`.

Use a Python interpreter supported by the packages in `requirements.txt` (tested with Python 3.14 on macOS ARM).

```sh
cd backend
python3 -m venv .venv
. .venv/bin/activate
pip install -r requirements.txt
cd ..
./script/run-backend.sh
```

Connect an Android device over USB, enable USB debugging, and verify that `adb devices` lists it with the `device` status. The script configures `adb reverse tcp:8000 tcp:8000` before starting the backend on the loopback interface. Rerun the script if the device is disconnected or ADB loses its connection.

Interactive documentation is available on the computer at `http://127.0.0.1:8000/docs`.

## API

1. `POST /sessions` creates a session that expires after 120 seconds.
2. `POST /sessions/{session_id}/frames` accepts a JPEG/PNG in the multipart field `image` (maximum 5 MB). Send no more than one frame every 80 ms, following the response's `instruction`.
3. Successful responses use the `success`, `message`, `data`, and `errors` fields. Challenge state (`status`, `passed`, `instruction`, and `frames_processed`) is nested under `data`. A session ends after success, expiration, or 180 frames.
4. `GET /health` checks the process health.

For repeated frame delivery, use `WS /sessions/{session_id}/stream`. The URL for Android over USB is `ws://127.0.0.1:8000/sessions/SESSION_ID/stream`, while sessions are created from Android through `http://127.0.0.1:8000/sessions`. After `POST /sessions`, connect to the WebSocket URL. The server immediately sends the session state as JSON using the `success`, `message`, `data`, and `errors` fields. Send **one JPEG/PNG frame as a binary message**, wait for the JSON response, and then send the next frame with a minimum interval of 80 ms. Text messages and invalid images receive a `success: false` response; the connection stays open so the mobile client can retry. Missing or expired sessions close with code 4404, completed sessions with 4409, and challenge success or failure with code 1000 after the final response. The maximum image payload is 5 MB. The HTTP endpoint remains available.

For WebSocket connections specifically, the mobile client sends raw BGR frames in the `LVC1` format: 4 ASCII bytes `LVC1`, 2-byte big-endian width and height values, followed by three BGR bytes for every pixel in row-major order. The mobile client rotates frames upright and scales the longest side down to at most 640 pixels before sending. The legacy `LVY1` format is rejected because it lacks the color data required by the model. The HTTP endpoint accepts JPEG/PNG only.

```sh
curl -X POST http://127.0.0.1:8000/sessions
curl -X POST -F 'image=@frame.jpg;type=image/jpeg' http://127.0.0.1:8000/sessions/SESSION_ID/frames
```

Example successful response (`POST /sessions`):

```json
{"success":true,"message":"Sesi berhasil dibuat","data":{"session_id":"...","expires_in_seconds":120,"status":"align","passed":false,"instruction":"Posisikan wajah di tengah bingkai","frames_processed":0},"errors":null}
```

Example validation-error response (HTTP 422):

```json
{"success":false,"message":"Data permintaan tidak valid","data":null,"errors":[{"field":"body.image","message":"Field required"}]}
```

The Indonesian strings above are literal API payload examples produced by the application. Sessions are stored in process memory, and the application does not save images. Production deployment requires shared session storage, rate limiting, authentication, TLS, and an anti-spoofing model tested on relevant data.

## Deploying to Your Own Server

You can use your own liveness server by deploying the code in `backend/`. The backend is self-contained and can run on any server that supports Python or Docker. After deployment, set the mobile application's `LIVENESS_API_URL` to the public base URL of your server, without a trailing endpoint path. For example:

```text
https://liveness.example.com
```

The server must expose both HTTP and WebSocket traffic. In production, place the backend behind a reverse proxy with TLS so that the API uses HTTPS and the stream uses WSS. Verify the deployment through `GET /health` before connecting the mobile application.

To deploy the backend manually with Docker:

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

You may use a different host port or deployment platform as long as traffic reaches container port `8000`. Configure your firewall, DNS, TLS certificate, and reverse proxy for the chosen public URL.

### Deployment with GitHub Actions

A push to `main` that changes files under `backend/` runs `.github/workflows/backend-deploy.yml`. The workflow uses a self-hosted Linux X64 runner labeled `liveness` and the GitHub environment named `research`. The runner must be installed on the target server, remain online, have Docker installed, and be allowed to execute `docker` commands without `sudo`.

The workflow does not currently require a backend-specific GitHub secret or variable. It builds the image from `backend/Dockerfile`, starts the `liveness-backend` container on host port `18080`, and waits for its health check. The deploy script stops with a clear error if another container already publishes this port and waits for Docker to release the port when replacing the existing backend container. The previous container is restored if the new one fails its health check. Deployment resets all in-memory sessions, so any session in progress must be restarted.

If you use a different runner label, port, container name, or deployment strategy, update `.github/workflows/backend-deploy.yml` and `backend/deploy.sh` accordingly.
