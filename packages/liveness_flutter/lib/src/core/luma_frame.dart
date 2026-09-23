import 'package:camera/camera.dart';
import 'package:flutter/services.dart';

/// Packs a downsampled, upright Y plane for the WebSocket frame protocol.
Uint8List encodeLumaFrame(
  CameraImage frame,
  int sensorOrientation,
  DeviceOrientation deviceOrientation,
) {
  if (frame.format.group != ImageFormatGroup.yuv420 &&
      frame.format.group != ImageFormatGroup.nv21) {
    throw const FormatException('Format frame kamera tidak didukung');
  }
  final plane = frame.planes.first;
  final rotation =
      (sensorOrientation +
          (deviceOrientation == DeviceOrientation.portraitDown ? 180 : 0)) %
      360;
  return packLumaFrame(
    plane.bytes,
    width: frame.width,
    height: frame.height,
    rowStride: plane.bytesPerRow,
    pixelStride: plane.bytesPerPixel ?? 1,
    rotation: rotation,
  );
}

Uint8List packLumaFrame(
  Uint8List source, {
  required int width,
  required int height,
  required int rowStride,
  required int pixelStride,
  required int rotation,
}) {
  if (width <= 0 ||
      height <= 0 ||
      rowStride <= 0 ||
      pixelStride <= 0 ||
      !{0, 90, 180, 270}.contains(rotation)) {
    throw const FormatException(
      'Ukuran atau orientasi frame kamera tidak valid',
    );
  }
  final step = ((width > height ? width : height) / 640).ceil();
  final sourceWidth = (width + step - 1) ~/ step;
  final sourceHeight = (height + step - 1) ~/ step;
  final uprightWidth = rotation == 90 || rotation == 270
      ? sourceHeight
      : sourceWidth;
  final uprightHeight = rotation == 90 || rotation == 270
      ? sourceWidth
      : sourceHeight;
  if (uprightWidth < 100 ||
      uprightHeight < 100 ||
      uprightWidth > 65535 ||
      uprightHeight > 65535) {
    throw const FormatException('Resolusi frame kamera tidak didukung');
  }
  if ((height - 1) * rowStride + (width - 1) * pixelStride >= source.length) {
    throw const FormatException('Data frame kamera tidak lengkap');
  }
  final output = Uint8List(8 + uprightWidth * uprightHeight);
  output.setRange(0, 4, [76, 86, 89, 49]); // LVY1
  output[4] = uprightWidth >> 8;
  output[5] = uprightWidth & 255;
  output[6] = uprightHeight >> 8;
  output[7] = uprightHeight & 255;
  for (var y = 0; y < sourceHeight; y++) {
    for (var x = 0; x < sourceWidth; x++) {
      final value = source[y * step * rowStride + x * step * pixelStride];
      final destination = switch (rotation) {
        90 => x * uprightWidth + (uprightWidth - 1 - y),
        180 => (uprightHeight - 1 - y) * uprightWidth + (uprightWidth - 1 - x),
        270 => (uprightHeight - 1 - x) * uprightWidth + y,
        _ => y * uprightWidth + x,
      };
      output[8 + destination] = value;
    }
  }
  return output;
}
