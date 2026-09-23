import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:liveness/liveness/bloc/liveness_event.dart';
import 'package:liveness/liveness/bloc/liveness_state.dart';
import 'package:liveness/core/liveness_api.dart';
import 'package:liveness/core/color_frame.dart';
import 'package:liveness/liveness/models/liveness_status.dart';

class LivenessBloc extends Bloc<LivenessEvent, LivenessState> {
  LivenessBloc({LivenessApi? api}) : _api = api ?? LivenessApi(), super(const LivenessState()) {
    on<CameraStarted>((event, emit) => _start(emit));
    on<CameraRetried>((event, emit) => _start(emit));
    on<CameraPaused>((event, emit) async {
      _generation++;
      final camera = state.camera;
      final stream = _stream;
      _stream = null;
      emit(const LivenessState());
      await stream?.close();
      await camera?.dispose();
    });
    on<FrameResultReceived>((event, emit) {
      if (event.generation != _generation) return;
      emit(
        LivenessState(
          camera: state.camera,
          instruction: event.result.instruction,
          status: event.result.status,
          resultImage: event.resultImage,
        ),
      );
    });
    on<SessionFailed>((event, emit) {
      if (event.generation != _generation) return;
      emit(LivenessState(camera: state.camera, error: event.message));
    });
  }

  final LivenessApi _api;
  LivenessStream? _stream;
  int _generation = 0;

  Future<void> _start(Emitter<LivenessState> emit) async {
    final generation = ++_generation;
    final previous = state.camera;
    final previousStream = _stream;
    _stream = null;
    emit(const LivenessState());
    await previousStream?.close();
    await previous?.dispose();
    CameraController? controller;
    try {
      final cameras = await availableCameras();
      if (isClosed || emit.isDone || generation != _generation) return;
      final front = cameras.where((camera) => camera.lensDirection == CameraLensDirection.front);
      if (front.isEmpty) {
        emit(const LivenessState(error: 'Kamera depan tidak tersedia'));
        return;
      }
      controller = CameraController(
        front.first,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await controller.initialize();
      if (isClosed || emit.isDone || generation != _generation) {
        await controller.dispose();
        return;
      }
      final session = await _api.createSession();
      if (isClosed || emit.isDone || generation != _generation) {
        await controller.dispose();
        return;
      }
      final stream = await _api.connect(session.sessionId);
      if (isClosed || emit.isDone || generation != _generation) {
        await stream.close();
        await controller.dispose();
        return;
      }
      _stream = stream;
      emit(LivenessState(camera: controller, instruction: session.result.instruction, status: session.result.status));
      await _startFrameStream(controller, stream, generation);
    } catch (error) {
      if (_stream != null && generation == _generation) {
        await _stream?.close();
        _stream = null;
      }
      await controller?.dispose();
      if (!isClosed && !emit.isDone && generation == _generation) {
        emit(
          LivenessState(
            error: error is LivenessApiException ? error.message : 'Kamera atau server tidak dapat dihubungi',
          ),
        );
      }
    }
  }

  Future<void> _startFrameStream(CameraController camera, LivenessStream stream, int generation) async {
    final clock = Stopwatch()..start();
    var lastFrameAt = -350;
    var sending = false;
    var status = LivenessStatus.align;
    await camera.startImageStream((image) {
      if (sending || isClosed || generation != _generation || !identical(_stream, stream)) return;
      final blinkInProgress = status == LivenessStatus.blink || status == LivenessStatus.reopen;
      final interval = blinkInProgress ? 100 : 300;
      if (clock.elapsedMilliseconds - lastFrameAt < interval) return;
      sending = true;
      lastFrameAt = clock.elapsedMilliseconds;
      unawaited(() async {
        try {
          final payload = encodeColorFrame(image, camera.description.sensorOrientation, camera.value.deviceOrientation);
          final result = await stream.submitFrame(payload);
          if (isClosed || generation != _generation) return;
          status = result.status;
          add(
            FrameResultReceived(
              generation,
              result,
              resultImage: result.status == LivenessStatus.passed ? encodeResultImage(payload) : null,
            ),
          );
          if (result.status.isFinished) {
            if (camera.value.isStreamingImages) {
              await camera.stopImageStream();
            }
            await stream.close();
            if (identical(_stream, stream)) _stream = null;
          }
        } catch (error) {
          if (!isClosed && generation == _generation) {
            add(
              SessionFailed(
                generation,
                error is LivenessApiException ? error.message : 'Gagal mengirim frame ke server',
              ),
            );
          }
          await stream.close();
          if (identical(_stream, stream)) _stream = null;
        } finally {
          sending = false;
        }
      }());
    });
  }

  @override
  Future<void> close() async {
    _generation++;
    await _stream?.close();
    _stream = null;
    await state.camera?.dispose();
    _api.close();
    await super.close();
  }
}
