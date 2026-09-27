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

See the [package README](../README.md) for installation, platform setup,
configuration, result fields, and security guidance.
