import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

class LivenessScreen extends StatefulWidget {
  const LivenessScreen({super.key});

  @override
  State<LivenessScreen> createState() => _LivenessScreenState();
}

class _LivenessScreenState extends State<LivenessScreen> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  CameraController? _camera;
  String? _cameraError;
  late final AnimationController _animation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _animation = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))..repeat();
    _startCamera();
  }

  Future<void> _startCamera() async {
    try {
      final cameras = await availableCameras();
      if (!mounted) return;
      final front = cameras.where((camera) => camera.lensDirection == CameraLensDirection.front);
      if (front.isEmpty) {
        setState(() => _cameraError = 'Kamera depan tidak tersedia');
        return;
      }
      final controller = CameraController(front.first, ResolutionPreset.medium, enableAudio: false);
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _camera = controller;
        _cameraError = null;
      });
    } catch (_) {
      if (mounted) setState(() => _cameraError = 'Kamera tidak dapat dibuka');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _camera?.dispose();
      _camera = null;
    } else if (state == AppLifecycleState.resumed) {
      _startCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _animation.dispose();
    _camera?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final camera = _camera;
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
                        onPressed: () => Navigator.maybePop(context),
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
                            _cameraError ?? 'Tahan wajah tetap diam',
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
                            _cameraError == null
                                ? 'Posisikan wajah di dalam bingkai'
                                : 'Periksa izin kamera lalu coba lagi',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Color(0xFFDCE6E3), fontSize: 14),
                          ),
                          if (_cameraError != null) ...[
                            const SizedBox(height: 20),
                            TextButton(
                              onPressed: _startCamera,
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
