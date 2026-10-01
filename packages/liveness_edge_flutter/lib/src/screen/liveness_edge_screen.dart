import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../core/challenge.dart';
import '../core/color_frame.dart';
import '../core/detector.dart';
import '../models/liveness_result.dart';
import '../models/liveness_status.dart';
import 'liveness_edge_theme.dart';

/// Builds the retry action shown after a failed attempt or screen error.
///
/// Use [onPressed] as the button's action so the liveness session can restart.
typedef LivenessRetryButtonBuilder =
    Widget Function(BuildContext context, String label, VoidCallback onPressed);

/// Builds optional content above the camera guide.
typedef LivenessHeaderBuilder =
    Widget Function(BuildContext context, LivenessEdgeViewState state);

/// Read-only presentation state exposed to custom liveness widgets.
@immutable
class LivenessEdgeViewState {
  const LivenessEdgeViewState({
    required this.status,
    required this.instruction,
    required this.supportingText,
    required this.progress,
    required this.isCameraReady,
    required this.hasError,
  });

  final LivenessStatus? status;
  final String instruction;
  final String supportingText;
  final double progress;
  final bool isCameraReady;
  final bool hasError;
}

/// A full-screen, ready-to-use on-device liveness capture flow.
///
/// The widget opens the front camera, guides the user through randomized active
/// challenges, invokes [onSuccess] after active and passive checks pass, or
/// invokes [onFailed] when verification reaches a terminal failure.
class LivenessEdgeScreen extends StatefulWidget {
  /// Creates a liveness capture screen.
  const LivenessEdgeScreen({
    super.key,
    this.configuration = const LivenessConfiguration(),
    this.onSuccess,
    this.onFailed,
    this.onCancel,
    this.theme = const LivenessEdgeTheme(),
    this.headerBuilder,
    @Deprecated('Use LivenessEdgeTheme.guidelineTextStyle instead.')
    this.guidelineTextStyle,
    @Deprecated('Use LivenessEdgeTheme.supportingTextStyle instead.')
    this.supportingTextStyle,
    this.retryButtonBuilder,
  });

  /// Limits and passive anti-spoof threshold used by this session.
  final LivenessConfiguration configuration;

  /// Called once with the final result after verification succeeds.
  ///
  /// Navigation is deliberately left to the host application.
  final ValueChanged<LivenessResult>? onSuccess;

  /// Called once with the final result after verification fails.
  ///
  /// A retry starts a new verification attempt and may invoke this callback
  /// again. Navigation is deliberately left to the host application.
  final ValueChanged<LivenessResult>? onFailed;

  /// Called when the close button is pressed.
  ///
  /// When omitted, the screen attempts to pop the current route.
  final VoidCallback? onCancel;

  /// Colors and camera-guide shape used by the built-in interface.
  final LivenessEdgeTheme theme;

  /// Builds optional branded content above the camera guide.
  final LivenessHeaderBuilder? headerBuilder;

  /// Overrides the style of the primary challenge instruction.
  ///
  /// Unspecified properties retain the screen's default values.
  @Deprecated('Use LivenessEdgeTheme.guidelineTextStyle instead.')
  final TextStyle? guidelineTextStyle;

  /// Overrides the style of the supporting text below the instruction.
  ///
  /// Unspecified properties retain the screen's default values.
  @Deprecated('Use LivenessEdgeTheme.supportingTextStyle instead.')
  final TextStyle? supportingTextStyle;

  /// Builds the retry button shown after a failed attempt or screen error.
  ///
  /// When omitted, the built-in retry button is used.
  final LivenessRetryButtonBuilder? retryButtonBuilder;

  @override
  State<LivenessEdgeScreen> createState() => _LivenessEdgeScreenState();
}

class _LivenessEdgeScreenState extends State<LivenessEdgeScreen>
    with WidgetsBindingObserver {
  final _detector = LivenessEdgeDetector();
  CameraController? _camera;
  late LivenessChallenge _challenge;
  LivenessResult? _result;
  String? _error;
  bool _busy = false;
  int _generation = 0;
  final _clock = Stopwatch();
  int _lastFrame = -500;
  String? _displayedInstruction;
  String? _pendingInstruction;
  int? _pendingInstructionSince;

  static const _instructionHold = Duration(milliseconds: 600);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  Future<void> _start() async {
    final generation = ++_generation;
    final previousCamera = _camera;
    _camera = null;
    _clock.stop();
    _busy = false;
    _lastFrame = -500;
    _displayedInstruction = null;
    _pendingInstruction = null;
    _pendingInstructionSince = null;
    _challenge = LivenessChallenge(widget.configuration);
    setState(() {
      _result = null;
      _error = null;
    });
    await previousCamera?.dispose();
    if (!mounted || generation != _generation) return;
    try {
      await _detector.initialize();
      final cameras = await availableCameras();
      final front = cameras
          .where((c) => c.lensDirection == CameraLensDirection.front)
          .firstOrNull;
      if (front == null) {
        throw LivenessEdgeException(
          widget.configuration.messages.frontCameraUnavailable,
        );
      }
      final camera = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await camera.initialize();
      if (!mounted || generation != _generation) {
        await camera.dispose();
        return;
      }
      _camera = camera;
      _clock
        ..reset()
        ..start();
      _updateResult(_challenge.result(), forceInstruction: true);
      await camera.startImageStream((frame) => _process(frame, generation));
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = error.toString());
      }
    }
  }

  void _process(CameraImage image, int generation) {
    if (generation != _generation) return;
    final interval =
        _result?.status == LivenessStatus.blink ||
            _result?.status == LivenessStatus.reopen
        ? 50
        : 200;
    if (_busy || _clock.elapsedMilliseconds - _lastFrame < interval) return;
    _busy = true;
    _lastFrame = _clock.elapsedMilliseconds;
    unawaited(() async {
      try {
        final camera = _camera;
        if (camera == null) return;
        final frame = encodeColorFrame(
          image,
          camera.description.sensorOrientation,
          camera.value.deviceOrientation,
        );
        final observation = await _detector.analyze(frame);
        if (!mounted || generation != _generation) return;
        final next = _challenge.advance(observation);
        if (next.status == LivenessStatus.passed) {
          final completed = LivenessResult(
            status: next.status,
            instruction: next.instruction,
            framesProcessed: next.framesProcessed,
            passiveScore: next.passiveScore,
            imageBytes: encodeResultImage(frame),
          );
          await _stopImageStream(camera);
          if (mounted && generation == _generation) {
            _updateResult(completed, forceInstruction: true);
            widget.onSuccess?.call(completed);
          }
        } else if (next.status.isFinished) {
          await _stopImageStream(camera);
          if (mounted && generation == _generation) {
            _updateResult(next, forceInstruction: true);
            widget.onFailed?.call(next);
          }
        } else {
          _updateResult(next);
        }
      } catch (error) {
        if (mounted && generation == _generation) {
          final camera = _camera;
          if (camera != null) await _stopImageStream(camera);
        }
        if (mounted && generation == _generation) {
          setState(() => _error = error.toString());
        }
      } finally {
        _busy = false;
      }
    }());
  }

  void _updateResult(LivenessResult next, {bool forceInstruction = false}) {
    final previousStatus = _result?.status;
    final instructionChanged = next.instruction != _displayedInstruction;
    final statusChanged = next.status != previousStatus;
    final distanceWarning =
        next.instruction == widget.configuration.messages.moveFarther;

    if (forceInstruction ||
        statusChanged ||
        distanceWarning ||
        _displayedInstruction == null) {
      _displayedInstruction = next.instruction;
      _pendingInstruction = null;
      _pendingInstructionSince = null;
    } else if (!instructionChanged) {
      _pendingInstruction = null;
      _pendingInstructionSince = null;
    } else if (_pendingInstruction != next.instruction) {
      _pendingInstruction = next.instruction;
      _pendingInstructionSince = _clock.elapsedMilliseconds;
    } else if (_clock.elapsedMilliseconds - _pendingInstructionSince! >=
        _instructionHold.inMilliseconds) {
      _displayedInstruction = next.instruction;
      _pendingInstruction = null;
      _pendingInstructionSince = null;
    }

    setState(() => _result = next);
  }

  Future<void> _stopImageStream(CameraController camera) async {
    if (!camera.value.isStreamingImages) return;
    try {
      await camera.stopImageStream();
    } on CameraException {
      // It may already be stopping because of an app lifecycle transition.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _generation++;
      _camera?.dispose();
      _camera = null;
    } else if (state == AppLifecycleState.resumed) {
      _start();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _generation++;
    _camera?.dispose();
    _detector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final camera = _camera;
    final theme = widget.theme;
    return Scaffold(
      backgroundColor: theme.backgroundColor,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final guideWidth = math.min(
              constraints.maxWidth * .76,
              constraints.maxHeight * .52 / 1.28,
            );
            final guideSize = theme.cameraShape == LivenessCameraShape.circle
                ? Size.square(guideWidth)
                : Size(guideWidth, guideWidth * 1.28);
            final status = _result?.status;
            final instruction =
                _error ??
                _displayedInstruction ??
                widget.configuration.messages.preparingCamera;
            final supportingText = _supportingText(status);
            final viewState = LivenessEdgeViewState(
              status: status,
              instruction: instruction,
              supportingText: supportingText,
              progress: status == null ? 0 : _challenge.progress,
              isCameraReady: camera?.value.isInitialized ?? false,
              hasError: _error != null,
            );

            return Stack(
              children: [
                Positioned(
                  top: 8,
                  right: 12,
                  child: IconButton(
                    tooltip: widget.configuration.messages.close,
                    onPressed:
                        widget.onCancel ?? () => Navigator.maybePop(context),
                    icon: const Icon(Icons.close_rounded),
                    color: theme.foregroundColor,
                  ),
                ),
                Positioned.fill(
                  child: Column(
                    children: [
                      const Spacer(flex: 2),
                      if (widget.headerBuilder case final builder?) ...[
                        builder(context, viewState),
                        const SizedBox(height: 16),
                      ],
                      _FaceCaptureGuide(
                        size: guideSize,
                        camera: camera,
                        progress: viewState.progress,
                        completed: status == LivenessStatus.passed,
                        theme: theme,
                      ),
                      const Spacer(flex: 1),
                      SizedBox(
                        height: 160,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 28),
                          child: Column(
                            children: [
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  minHeight: 54,
                                ),
                                child: Center(
                                  child: Text(
                                    instruction,
                                    textAlign: TextAlign.center,
                                    maxLines: 3,
                                    style:
                                        TextStyle(
                                              color:
                                                  status ==
                                                      LivenessStatus.passed
                                                  ? theme.successColor
                                                  : theme.foregroundColor,
                                              fontSize: 21,
                                              height: 1.25,
                                              fontWeight: FontWeight.w600,
                                            )
                                            .merge(theme.guidelineTextStyle)
                                            .merge(widget.guidelineTextStyle),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                supportingText,
                                textAlign: TextAlign.center,
                                style:
                                    TextStyle(
                                          color: theme.foregroundColor
                                              .withValues(alpha: .65),
                                          fontSize: 14,
                                          height: 1.4,
                                        )
                                        .merge(theme.supportingTextStyle)
                                        .merge(widget.supportingTextStyle),
                              ),
                              if (_error != null ||
                                  status == LivenessStatus.failed) ...[
                                const SizedBox(height: 16),
                                if (widget.retryButtonBuilder
                                    case final builder?)
                                  builder(
                                    context,
                                    widget.configuration.messages.tryAgain,
                                    _start,
                                  )
                                else
                                  _RetryButton(
                                    label:
                                        widget.configuration.messages.tryAgain,
                                    onPressed: _start,
                                    theme: theme,
                                  ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const Spacer(flex: 2),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  String _supportingText(LivenessStatus? status) {
    final messages = widget.configuration.messages;
    if (_error != null) return messages.cameraPermissionHelp;
    return switch (status) {
      null => messages.pleaseWait,
      LivenessStatus.align ||
      LivenessStatus.open => messages.positionFaceInFrame,
      LivenessStatus.blink || LivenessStatus.reopen => messages.holdStill,
      LivenessStatus.finalCapture => messages.holdStill,
      LivenessStatus.move ||
      LivenessStatus.smile ||
      LivenessStatus.openMouth ||
      LivenessStatus.returnNeutral => messages.moveSlowly,
      LivenessStatus.passed => messages.faceVerified,
      LivenessStatus.failed => messages.verificationUnsuccessful,
    };
  }
}

class _RetryButton extends StatelessWidget {
  const _RetryButton({
    required this.label,
    required this.onPressed,
    required this.theme,
  });

  final String label;
  final VoidCallback onPressed;
  final LivenessEdgeTheme theme;

  @override
  Widget build(BuildContext context) {
    const borderRadius = BorderRadius.all(Radius.circular(24));

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(theme.primaryColor, Colors.white, .12)!,
            theme.primaryColor,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: theme.primaryColor.withValues(alpha: .22),
            blurRadius: 18,
            offset: Offset(0, 7),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: borderRadius,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.refresh_rounded,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 9),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                    letterSpacing: .15,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FaceCaptureGuide extends StatelessWidget {
  const _FaceCaptureGuide({
    required this.size,
    required this.camera,
    required this.progress,
    required this.completed,
    required this.theme,
  });

  final Size size;
  final CameraController? camera;
  final double progress;
  final bool completed;
  final LivenessEdgeTheme theme;

  @override
  Widget build(BuildContext context) {
    const ringPadding = 25.0;
    return SizedBox(
      width: size.width + ringPadding * 2,
      height: size.height + ringPadding * 2,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: _clipCamera(
              SizedBox.fromSize(size: size, child: _cameraPreview()),
            ),
          ),
          IgnorePointer(
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: progress),
              duration: const Duration(milliseconds: 480),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) => CustomPaint(
                painter: _SegmentedRingPainter(
                  progress: value,
                  completed: completed,
                  padding: ringPadding,
                  shape: theme.cameraShape,
                  borderRadius: theme.cameraBorderRadius,
                  primaryColor: theme.primaryColor,
                  successColor: theme.successColor,
                  inactiveColor: theme.inactiveRingColor,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _clipCamera(Widget child) => switch (theme.cameraShape) {
    LivenessCameraShape.oval ||
    LivenessCameraShape.circle => ClipOval(child: child),
    LivenessCameraShape.roundedRectangle => ClipRRect(
      borderRadius: BorderRadius.circular(theme.cameraBorderRadius),
      child: child,
    ),
  };

  Widget _cameraPreview() {
    final controller = camera;
    if (controller == null || !controller.value.isInitialized) {
      return DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF0F3F2), Color(0xFFDDE5E3)],
          ),
        ),
        child: Center(
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: theme.primaryColor,
          ),
        ),
      );
    }
    final preview = controller.value.previewSize!;
    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        // CameraPreview in portrait uses the reciprocal of the sensor's
        // landscape aspect ratio. Match those constraints so the texture is
        // cropped by FittedBox without ever being stretched.
        width: preview.height,
        height: preview.width,
        child: CameraPreview(controller),
      ),
    );
  }
}

class _SegmentedRingPainter extends CustomPainter {
  const _SegmentedRingPainter({
    required this.progress,
    required this.completed,
    required this.padding,
    required this.shape,
    required this.borderRadius,
    required this.primaryColor,
    required this.successColor,
    required this.inactiveColor,
  });

  final double progress;
  final bool completed;
  final double padding;
  final LivenessCameraShape shape;
  final double borderRadius;
  final Color primaryColor;
  final Color successColor;
  final Color inactiveColor;

  static const _segments = 64;

  @override
  void paint(Canvas canvas, Size size) {
    if (shape == LivenessCameraShape.roundedRectangle) {
      _paintRoundedRectangle(canvas, size);
      return;
    }
    final center = size.center(Offset.zero);
    final innerRx = (size.width - padding * 2) / 2 + 7;
    final innerRy = (size.height - padding * 2) / 2 + 7;
    const tickLength = 13.0;
    final activeSegments = (progress.clamp(0.0, 1.0) * _segments).round();

    for (var index = 0; index < _segments; index++) {
      final angle = -math.pi / 2 + (math.pi * 2 * index / _segments);
      final cosAngle = math.cos(angle);
      final sinAngle = math.sin(angle);
      final start = Offset(
        center.dx + innerRx * cosAngle,
        center.dy + innerRy * sinAngle,
      );
      final end = Offset(
        center.dx + (innerRx + tickLength) * cosAngle,
        center.dy + (innerRy + tickLength) * sinAngle,
      );
      final isActive = index < activeSegments;
      final color = completed
          ? successColor
          : isActive
          ? primaryColor
          : inactiveColor;

      canvas.drawLine(
        start,
        end,
        Paint()
          ..color = color
          ..strokeWidth = 3.5
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  void _paintRoundedRectangle(Canvas canvas, Size size) {
    final ringOffset = padding - 7;
    final rect = Rect.fromLTWH(
      ringOffset,
      ringOffset,
      size.width - ringOffset * 2,
      size.height - ringOffset * 2,
    );
    final radius = math.min(
      borderRadius + 7,
      math.min(rect.width, rect.height) / 2,
    );
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
    final metric = path.computeMetrics().first;
    final activeSegments = (progress.clamp(0.0, 1.0) * _segments).round();
    final segmentLength = metric.length / _segments;

    for (var index = 0; index < _segments; index++) {
      final start = index * segmentLength + segmentLength * .18;
      final end = (index + 1) * segmentLength - segmentLength * .18;
      final isActive = index < activeSegments;
      canvas.drawPath(
        metric.extractPath(start, end),
        Paint()
          ..color = completed
              ? successColor
              : isActive
              ? primaryColor
              : inactiveColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.5
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_SegmentedRingPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.completed != completed ||
      oldDelegate.padding != padding ||
      oldDelegate.shape != shape ||
      oldDelegate.borderRadius != borderRadius ||
      oldDelegate.primaryColor != primaryColor ||
      oldDelegate.successColor != successColor ||
      oldDelegate.inactiveColor != inactiveColor;
}
