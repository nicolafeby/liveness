import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../core/challenge.dart';
import '../core/color_frame.dart';
import '../core/detector.dart';
import '../models/liveness_result.dart';
import '../models/liveness_status.dart';

/// A full-screen, ready-to-use on-device liveness capture flow.
///
/// The widget opens the front camera, guides the user through a blink and head
/// turn, and invokes [onSuccess] after both active and passive checks pass.
class LivenessEdgeScreen extends StatefulWidget {
  /// Creates a liveness capture screen.
  const LivenessEdgeScreen({
    super.key,
    this.configuration = const LivenessConfiguration(),
    this.onSuccess,
    this.onCancel,
  });

  /// Limits and passive anti-spoof threshold used by this session.
  final LivenessConfiguration configuration;

  /// Called once with the final result after verification succeeds.
  ///
  /// Navigation is deliberately left to the host application.
  final ValueChanged<LivenessResult>? onSuccess;

  /// Called when the close button is pressed.
  ///
  /// When omitted, the screen attempts to pop the current route.
  final VoidCallback? onCancel;

  @override
  State<LivenessEdgeScreen> createState() => _LivenessEdgeScreenState();
}

class _LivenessEdgeScreenState extends State<LivenessEdgeScreen> with WidgetsBindingObserver {
  final _detector = LivenessEdgeDetector();
  CameraController? _camera;
  late LivenessChallenge _challenge;
  LivenessResult? _result;
  String? _error;
  bool _busy = false;
  int _generation = 0;
  final _clock = Stopwatch();
  int _lastFrame = -500;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  Future<void> _start() async {
    final generation = ++_generation;
    await _camera?.dispose();
    _challenge = LivenessChallenge(widget.configuration);
    setState(() {
      _camera = null;
      _result = null;
      _error = null;
    });
    try {
      await _detector.initialize();
      final cameras = await availableCameras();
      final front = cameras.where((c) => c.lensDirection == CameraLensDirection.front).firstOrNull;
      if (front == null) {
        throw const LivenessEdgeException('Kamera depan tidak tersedia');
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
      setState(() => _result = _challenge.result());
      await camera.startImageStream((frame) => _process(frame, generation));
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = error.toString());
      }
    }
  }

  void _process(CameraImage image, int generation) {
    final interval = _result?.status == LivenessStatus.blink || _result?.status == LivenessStatus.reopen ? 100 : 200;
    if (_busy || _clock.elapsedMilliseconds - _lastFrame < interval) return;
    _busy = true;
    _lastFrame = _clock.elapsedMilliseconds;
    unawaited(() async {
      try {
        final camera = _camera!;
        final frame = encodeColorFrame(image, camera.description.sensorOrientation, camera.value.deviceOrientation);
        final observation = await _detector.analyze(frame);
        final next = _challenge.advance(observation);
        if (!mounted || generation != _generation) return;
        if (next.status == LivenessStatus.passed) {
          final completed = LivenessResult(
            status: next.status,
            instruction: next.instruction,
            framesProcessed: next.framesProcessed,
            passiveScore: next.passiveScore,
            imageBytes: encodeResultImage(frame),
          );
          setState(() => _result = completed);
          await camera.stopImageStream();
          widget.onSuccess?.call(completed);
        } else {
          setState(() => _result = next);
          if (next.status.isFinished) {
            await camera.stopImageStream();
          }
        }
      } catch (error) {
        if (mounted && generation == _generation) {
          setState(() => _error = error.toString());
        }
      } finally {
        _busy = false;
      }
    }());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
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
      backgroundColor: const Color(0xff121b1b),
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
            ),
          const Center(
            child: IgnorePointer(
              child: SizedBox(
                width: 300,
                height: 360,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.fromBorderSide(BorderSide(color: Color(0xff64d7c5), width: 3)),
                    borderRadius: BorderRadius.all(Radius.elliptical(150, 180)),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: IconButton(
                onPressed: widget.onCancel ?? () => Navigator.maybePop(context),
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 60,
            child: Column(
              children: [
                Text(
                  _error ?? _result?.instruction ?? 'Menyiapkan model on-device…',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w600),
                ),
                if (_error != null || _result?.status == LivenessStatus.failed)
                  TextButton(onPressed: _start, child: const Text('Coba lagi')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
