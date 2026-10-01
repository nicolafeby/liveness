import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liveness_edge_flutter/liveness_edge_flutter.dart';

void main() {
  test('theme preserves the existing visual defaults', () {
    const theme = LivenessEdgeTheme();

    expect(theme.backgroundColor, Colors.white);
    expect(theme.foregroundColor, const Color(0xFF202727));
    expect(theme.primaryColor, const Color(0xFF6635E8));
    expect(theme.successColor, const Color(0xFF25C995));
    expect(theme.inactiveRingColor, const Color(0xFFD1D6D5));
    expect(theme.cameraShape, LivenessCameraShape.oval);
    expect(theme.cameraBorderRadius, 24);
  });

  test('view state exposes immutable presentation data', () {
    const state = LivenessEdgeViewState(
      status: LivenessStatus.blink,
      instruction: 'Blink',
      supportingText: 'Hold still',
      progress: .5,
      isCameraReady: true,
      hasError: false,
    );

    expect(state.status, LivenessStatus.blink);
    expect(state.progress, .5);
    expect(state.isCameraReady, isTrue);
  });

  test('theme accepts guideline and supporting text styles', () {
    const theme = LivenessEdgeTheme(
      guidelineTextStyle: TextStyle(fontSize: 23),
      supportingTextStyle: TextStyle(fontSize: 14),
    );

    expect(theme.guidelineTextStyle?.fontSize, 23);
    expect(theme.supportingTextStyle?.fontSize, 14);
  });
}
