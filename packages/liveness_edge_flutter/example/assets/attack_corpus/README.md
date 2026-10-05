# Attack corpus

This directory contains synthetic presentation-attack fixtures used by the
on-device integration test. No real customer's biometric data belongs here.

`manifest.json` is the source of truth. Each case declares an attack type and
the face count expected from MediaPipe. The top-level threshold is the maximum
MiniFASNet live score accepted for every bundled attack; a score at or above it
fails the test because the attack would pass the strict preset.

The bundled fixtures cover a printed photograph and a tablet/screen replay.
They were generated specifically for this project and depict fictional people.
Add local cases by copying an upright PNG or JPEG into this directory and
adding a manifest entry. Before committing any captured corpus, obtain consent,
remove metadata, document its license and retention period, and ensure the
subject is not a customer or production user.

Run the corpus through the real native MediaPipe and ONNX implementations:

```sh
cd packages/liveness_edge_flutter/example
flutter test integration_test/native_detector_test.dart -d <device-id>
```

Use physical Android and iOS devices for release qualification. Emulator and
simulator results are useful smoke tests but are not representative PAD
measurements. Expand private release corpora with varied devices, displays,
printers, lighting, skin tones, ages, glasses, and capture distances. Keep
genuine/live samples in the same evaluation process to measure false rejects;
do not weaken the threshold solely to make an attack fixture pass.
