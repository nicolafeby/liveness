# Liveness Edge Flutter example

Demonstrates the ready-to-use `LivenessEdgeScreen` from
`liveness_edge_flutter`, including:

- strict passive anti-spoof and face-continuity sensitivity presets;
- custom instruction and supporting-text styles;
- a custom retry button;
- success and failure callbacks; and
- display of the verified JPEG returned on success.

## Run the example

Use a physical Android or iOS device with a front-facing camera:

```sh
flutter pub get
flutter run
```

The native face-landmark and anti-spoof models are bundled by the package. No
backend or network connection is required. Grant camera access when prompted.

## Native device tests and attack corpus

The device suite initializes the packaged native models, checks channel error
handling and lifecycle re-initialization, then evaluates the synthetic print
and screen-replay corpus against the strict passive threshold:

```sh
flutter test integration_test/native_detector_test.dart -d <device-id>
```

For a wirelessly connected iOS device, use Flutter Driver so mDNS can publish
the VM service port:

```sh
flutter drive --publish-port \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/native_detector_test.dart \
  -d <device-id>
```

Run it on at least one physical Android device and one physical iOS device
before release. Corpus format, privacy rules, and expansion guidance are in
[`assets/attack_corpus/README.md`](assets/attack_corpus/README.md).

See the [package README](../README.md) for installation, platform setup,
configuration, result fields, and security guidance.
