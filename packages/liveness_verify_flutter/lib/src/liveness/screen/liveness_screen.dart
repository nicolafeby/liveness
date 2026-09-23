import 'dart:developer';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:liveness_verify_flutter/src/liveness/bloc/liveness_bloc.dart';
import 'package:liveness_verify_flutter/src/liveness/bloc/liveness_event.dart';
import 'package:liveness_verify_flutter/src/liveness/bloc/liveness_state.dart';
import 'package:liveness_verify_flutter/src/liveness/models/liveness_status.dart';
import 'package:liveness_verify_flutter/src/core/liveness_api.dart';

class LivenessScreen extends StatefulWidget {
  const LivenessScreen({super.key, this.baseUrl, this.onSuccess, this.onCancel});

  final String? baseUrl;
  final ValueChanged<Uint8List>? onSuccess;
  final VoidCallback? onCancel;

  @override
  State<LivenessScreen> createState() => _LivenessScreenState();
}

class _LivenessScreenState extends State<LivenessScreen> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final LivenessBloc _bloc;
  late final AnimationController _animation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bloc = LivenessBloc(api: LivenessApi(baseUrl: widget.baseUrl))..add(CameraStarted());
    _animation = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))..repeat();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _bloc.add(CameraPaused());
    } else if (state == AppLifecycleState.resumed) {
      _bloc.add(CameraStarted());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _animation.dispose();
    _bloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BlocProvider.value(
    value: _bloc,
    child: BlocConsumer<LivenessBloc, LivenessState>(
      listenWhen: (previous, current) =>
          previous.status != LivenessStatus.passed &&
          current.status == LivenessStatus.passed &&
          current.resultImage != null,
      listener: (context, state) {
        final image = state.resultImage;
        if (image == null) return;
        log('Liveness passed, returning image of length $image');
        widget.onSuccess?.call(image);
      },
      builder: (context, state) => _buildScreen(context, state),
    ),
  );

  Widget _buildScreen(BuildContext context, LivenessState state) {
    final camera = state.camera;
    final cameraError = state.error;
    return Scaffold(
      backgroundColor: const Color(0xFF121B1B),
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (camera != null && camera.value.isInitialized)
            ClipRect(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: camera.value.previewSize!.height,
                  height: camera.value.previewSize!.width,
                  child: CameraPreview(camera),
                ),
              ),
            )
          else
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF344849), Color(0xFF111A1A)],
                ),
              ),
            ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final faceWidth = math.min(
                  math.min(constraints.maxWidth * .92, 400.0),
                  constraints.maxHeight * .65 / 1.28,
                );
                final faceHeight = faceWidth * 1.18;

                return Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(painter: _OutsideShadePainter(faceSize: Size(faceWidth, faceHeight))),
                    ),
                    Positioned(
                      top: 16,
                      right: 20,
                      child: IconButton(
                        tooltip: 'Tutup',
                        onPressed: () {
                          if (widget.onCancel != null) {
                            widget.onCancel!();
                          } else {
                            Navigator.maybePop(context);
                          }
                        },
                        icon: const Icon(Icons.close, color: Colors.white),
                      ),
                    ),
                    Center(
                      child: Transform.translate(
                        offset: const Offset(0, -35),
                        child: SizedBox(
                          width: faceWidth,
                          height: faceHeight,
                          child: AnimatedBuilder(
                            animation: _animation,
                            builder: (context, _) => CustomPaint(painter: _FaceGuidePainter(_animation.value)),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 24,
                      right: 24,
                      bottom: math.max(28, constraints.maxHeight * .08),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            cameraError ??
                                state.instruction ??
                                'Hadapkan wajah ke kamera dan pastikan kedua mata terlihat jelas.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w600,
                              shadows: [Shadow(blurRadius: 12, color: Colors.black)],
                            ),
                          ),
                          const SizedBox(height: 9),
                          Text(
                            cameraError != null
                                ? 'Periksa kamera dan koneksi backend lalu coba lagi'
                                : state.status == LivenessStatus.passed
                                ? 'Verifikasi berhasil'
                                : state.status == LivenessStatus.failed
                                ? 'Silakan coba lagi'
                                : state.status == LivenessStatus.align
                                ? 'Ikuti petunjuk sampai wajah sejajar'
                                : state.status == null
                                ? 'Posisikan wajah di dalam bingkai'
                                : 'Pertahankan wajah terlihat jelas',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Color(0xFFDCE6E3), fontSize: 14),
                          ),
                          if (cameraError != null || state.status == LivenessStatus.failed) ...[
                            const SizedBox(height: 20),
                            TextButton(
                              onPressed: () => _bloc.add(CameraRetried()),
                              child: const Text('Coba lagi', style: TextStyle(color: Color(0xFF69DCCA))),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _OutsideShadePainter extends CustomPainter {
  const _OutsideShadePainter({required this.faceSize});

  final Size faceSize;

  @override
  void paint(Canvas canvas, Size size) {
    final faceOffset = Offset((size.width - faceSize.width) / 2, (size.height - faceSize.height) / 2 - 35);
    final shade = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addPath(_FaceGuidePainter.facePath(faceSize), faceOffset);
    canvas.drawPath(shade, Paint()..color = const Color(0x99071113));
  }

  @override
  bool shouldRepaint(_OutsideShadePainter oldDelegate) => oldDelegate.faceSize != faceSize;
}

class _FaceGuidePainter extends CustomPainter {
  _FaceGuidePainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final path = facePath(size);
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0x665EE0CB)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 9
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 13),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF64D7C5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );
    final metric = path.computeMetrics().first;
    final sweep = metric.extractPath(metric.length * progress, metric.length * math.min(progress + .14, 1));
    canvas.drawPath(
      sweep,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round,
    );
  }

  static Path facePath(Size size) {
    final x = size.width;
    final y = size.height;
    return Path()
      ..moveTo(.5 * x, .04 * y)
      ..cubicTo(.25 * x, .04 * y, .15 * x, .14 * y, .15 * x, .34 * y)
      ..lineTo(.15 * x, .39 * y)
      ..cubicTo(.06 * x, .38 * y, .05 * x, .43 * y, .08 * x, .49 * y)
      ..cubicTo(.1 * x, .54 * y, .14 * x, .54 * y, .17 * x, .55 * y)
      ..cubicTo(.2 * x, .79 * y, .34 * x, .94 * y, .5 * x, .94 * y)
      ..cubicTo(.66 * x, .94 * y, .8 * x, .79 * y, .83 * x, .55 * y)
      ..cubicTo(.86 * x, .54 * y, .9 * x, .54 * y, .92 * x, .49 * y)
      ..cubicTo(.95 * x, .43 * y, .94 * x, .38 * y, .85 * x, .39 * y)
      ..lineTo(.85 * x, .34 * y)
      ..cubicTo(.85 * x, .14 * y, .75 * x, .04 * y, .5 * x, .04 * y)
      ..close();
  }

  @override
  bool shouldRepaint(_FaceGuidePainter oldDelegate) => oldDelegate.progress != progress;
}
