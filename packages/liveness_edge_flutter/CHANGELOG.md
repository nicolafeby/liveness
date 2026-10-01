## 0.3.0

- Add `LivenessEdgeTheme` for screen colors and camera-guide appearance.
- Move guideline and supporting text styles into `LivenessEdgeTheme`; retain
  the screen-level properties as deprecated compatibility aliases.
- Add oval, circular, and rounded-rectangle camera shapes.
- Add `headerBuilder` with read-only `LivenessEdgeViewState` presentation data.
- Improve open-mouth recognition on iOS with a normalized lip-gap fallback
  when the MediaPipe `jawOpen` blendshape is too conservative.
- Show move-farther guidance before the face reaches the frame boundary,
  improving alignment feedback on iOS front-camera frames.

## 0.2.1

- Require three stable, frontal frames with both eyes fully open before saving
  the final verification image.
- Prevent fast iOS devices from exhausting the analyzed-frame safety cap well
  before the configured session timeout.
- Tolerate brief face-landmarker dropouts during active challenges while still
  enforcing same-face identity when detection resumes.
- Preserve more landmark detail when downscaling iOS BGRA camera frames without
  changing the Android YUV/NV21 conversion path.
- Normalize front-camera yaw on iOS so left and right head-turn instructions
  match the user's physical direction.

## 0.2.0

- Randomly select three or four active challenges per session from blink, one
  randomly directed head turn, smile, and open mouth.
- Validate smile and open-mouth transitions with MediaPipe blendshapes.

## 0.1.0

- Initial offline Android and iOS implementation.
- MediaPipe face landmarks, blink blendshapes, and head-turn estimation.
- MiniFASNetV2 passive anti-spoofing through ONNX Runtime.
- Dart challenge state machine and ready-to-use camera screen.
- Custom guideline text, styles, and retry button builder.
- Complete setup, usage, security, and API documentation.
