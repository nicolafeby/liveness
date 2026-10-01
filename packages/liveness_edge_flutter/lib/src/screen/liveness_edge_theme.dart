import 'package:flutter/material.dart';

/// Shapes supported by the built-in camera guide.
enum LivenessCameraShape { oval, circle, roundedRectangle }

/// Visual configuration for [LivenessEdgeScreen].
@immutable
class LivenessEdgeTheme {
  const LivenessEdgeTheme({
    this.backgroundColor = Colors.white,
    this.foregroundColor = const Color(0xFF202727),
    this.primaryColor = const Color(0xFF6635E8),
    this.successColor = const Color(0xFF25C995),
    this.inactiveRingColor = const Color(0xFFD1D6D5),
    this.cameraShape = LivenessCameraShape.oval,
    this.cameraBorderRadius = 24,
    this.guidelineTextStyle,
    this.supportingTextStyle,
  }) : assert(cameraBorderRadius >= 0);

  final Color backgroundColor;
  final Color foregroundColor;
  final Color primaryColor;
  final Color successColor;
  final Color inactiveRingColor;
  final LivenessCameraShape cameraShape;

  /// Corner radius used when [cameraShape] is
  /// [LivenessCameraShape.roundedRectangle].
  final double cameraBorderRadius;

  /// Overrides the built-in primary challenge instruction style.
  /// Unspecified properties retain the themed defaults.
  final TextStyle? guidelineTextStyle;

  /// Overrides the built-in supporting text style.
  /// Unspecified properties retain the themed defaults.
  final TextStyle? supportingTextStyle;
}
