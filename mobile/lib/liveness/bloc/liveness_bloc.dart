import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:liveness/liveness/bloc/liveness_event.dart';
import 'package:liveness/liveness/bloc/liveness_state.dart';
import 'package:liveness/core/liveness_api.dart';

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
      emit(LivenessState(camera: state.camera, instruction: event.instruction, status: event.status));
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
        imageFormatGroup: ImageFormatGroup.jpeg,
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
      final stream = await _api.connect(session['session_id'] as String);
      if (isClosed || emit.isDone || generation != _generation) {
        await stream.close();
        await controller.dispose();
        return;
      }
      _stream = stream;
      emit(
        LivenessState(
          camera: controller,
          instruction: session['instruction'] as String?,
          status: session['status'] as String?,
        ),
      );
      unawaited(_captureLoop(controller, stream, generation));
    } catch (error) {
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

  Future<void> _captureLoop(CameraController camera, LivenessStream stream, int generation) async {
    while (!isClosed && generation == _generation) {
      try {
        final image = await camera.takePicture();
        if (isClosed || generation != _generation) return;
        final result = await stream.submitFrame(await image.readAsBytes());
        if (isClosed || generation != _generation) return;
        final status = result['status'] as String;
        add(FrameResultReceived(generation, result['instruction'] as String, status));
        if (status == 'passed' || status == 'failed') {
          await stream.close();
          if (identical(_stream, stream)) _stream = null;
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 350));
      } catch (error) {
        if (!isClosed && generation == _generation) {
          add(
            SessionFailed(generation, error is LivenessApiException ? error.message : 'Gagal mengirim frame ke server'),
          );
        }
        await stream.close();
        if (identical(_stream, stream)) _stream = null;
        return;
      }
    }
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
