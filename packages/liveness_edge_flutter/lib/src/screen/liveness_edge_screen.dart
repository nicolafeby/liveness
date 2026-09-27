import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../core/challenge.dart';
import '../core/color_frame.dart';
import '../core/detector.dart';
import '../models/liveness_result.dart';
import '../models/liveness_status.dart';

/// Builds the retry action shown after a failed attempt or screen error.
///
/// Use [onPressed] as the button's action so the liveness session can restart.
typedef LivenessRetryButtonBuilder =
    Widget Function(BuildContext context, String label, VoidCallback onPressed);

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
    this.guidelineTextStyle,
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

  /// Overrides the style of the primary challenge instruction.
  ///
  /// Unspecified properties retain the screen's default values.
  final TextStyle? guidelineTextStyle;

  /// Overrides the style of the supporting text below the instruction.
  ///
  /// Unspecified properties retain the screen's default values.
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

    if (forceInstruction || statusChanged || _displayedInstruction == null) {
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
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final guideWidth = math.min(
              constraints.maxWidth * .76,
              constraints.maxHeight * .52 / 1.28,
            );
            final guideSize = Size(guideWidth, guideWidth * 1.28);
            final status = _result?.status;

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
                    color: const Color(0xFF202727),
                  ),
                ),
                Positioned.fill(
                  child: Column(
                    children: [
                      const Spacer(flex: 2),
                      _FaceCaptureGuide(
                        size: guideSize,
                        camera: camera,
                        progress: status == null ? 0 : _challenge.progress,
                        completed: status == LivenessStatus.passed,
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
                                    _error ??
                                        _displayedInstruction ??
                                        widget
                                            .configuration
                                            .messages
                                            .preparingCamera,
                                    textAlign: TextAlign.center,
                                    maxLines: 3,
                                    style: TextStyle(
                                      color: status == LivenessStatus.passed
                                          ? const Color(0xFF14B887)
                                          : const Color(0xFF202727),
                                      fontSize: 21,
                                      height: 1.25,
                                      fontWeight: FontWeight.w600,
                                    ).merge(widget.guidelineTextStyle),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                _supportingText(status),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Color(0xFF77807E),
                                  fontSize: 14,
                                  height: 1.4,
                                ).merge(widget.supportingTextStyle),
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
  const _RetryButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    const borderRadius = BorderRadius.all(Radius.circular(24));

    return DecoratedBox(
      decoration: const BoxDecoration(
        borderRadius: borderRadius,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF7548EE), Color(0xFF5D31E8)],
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x385D31E8),
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
  });

  final Size size;
  final CameraController? camera;
  final double progress;
  final bool completed;

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
            child: ClipOval(
              child: SizedBox.fromSize(size: size, child: _cameraPreview()),
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
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cameraPreview() {
    final controller = camera;
    if (controller == null || !controller.value.isInitialized) {
      return const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF0F3F2), Color(0xFFDDE5E3)],
          ),
        ),
        child: Center(
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: Color(0xFF6635E8),
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
  });

  final double progress;
  final bool completed;
  final double padding;

  static const _segments = 64;

  @override
  void paint(Canvas canvas, Size size) {
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
          ? const Color(0xFF25C995)
          : isActive
          ? const Color(0xFF6635E8)
          : const Color(0xFFD1D6D5);

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

  @override
  bool shouldRepaint(_SegmentedRingPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.completed != completed ||
      oldDelegate.padding != padding;
}
