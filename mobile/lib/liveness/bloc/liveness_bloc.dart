import 'package:camera/camera.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:liveness/liveness/bloc/liveness_event.dart';
import 'package:liveness/liveness/bloc/liveness_state.dart';

class LivenessBloc extends Bloc<LivenessEvent, LivenessState> {
  LivenessBloc() : super(const LivenessState()) {
    on<CameraStarted>((event, emit) => _start(emit));
    on<CameraRetried>((event, emit) => _start(emit));
    on<CameraPaused>((event, emit) {
      _generation++;
      final camera = state.camera;
      emit(const LivenessState());
      camera?.dispose();
    });
  }

  int _generation = 0;

  Future<void> _start(Emitter<LivenessState> emit) async {
    final generation = ++_generation;
    final previous = state.camera;
    emit(const LivenessState());
    await previous?.dispose();
    CameraController? controller;
    try {
      final cameras = await availableCameras();
      if (isClosed || emit.isDone || generation != _generation) return;
      final front = cameras.where(
        (camera) => camera.lensDirection == CameraLensDirection.front,
      );
      if (front.isEmpty) {
        emit(const LivenessState(error: 'Kamera depan tidak tersedia'));
        return;
      }
      controller = CameraController(
        front.first,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await controller.initialize();
      if (isClosed || emit.isDone || generation != _generation) {
        await controller.dispose();
        return;
      }
      emit(LivenessState(camera: controller));
    } catch (_) {
      await controller?.dispose();
      if (!isClosed && !emit.isDone && generation == _generation) {
        emit(const LivenessState(error: 'Kamera tidak dapat dibuka'));
      }
    }
  }

  @override
  Future<void> close() async {
    _generation++;
    await state.camera?.dispose();
    await super.close();
  }
}
