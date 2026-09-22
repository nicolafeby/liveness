import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';

/// Packs an upright, downsampled BGR frame for the backend's LVC1 protocol.
Uint8List encodeColorFrame(CameraImage frame, int sensorOrientation, DeviceOrientation deviceOrientation) {
  if (frame.format.group != ImageFormatGroup.yuv420 && frame.format.group != ImageFormatGroup.nv21) {
    throw const FormatException('Format frame kamera tidak didukung');
  }
  final rotation = (sensorOrientation + (deviceOrientation == DeviceOrientation.portraitDown ? 180 : 0)) % 360;
  if (!{0, 90, 180, 270}.contains(rotation) || frame.width < 100 || frame.height < 100) {
    throw const FormatException('Ukuran atau orientasi frame kamera tidak valid');
  }
  final interleaved = frame.planes.length == 2;
  final nv21 = frame.format.group == ImageFormatGroup.nv21;
  if (frame.planes.length < 2) {
    throw const FormatException('Data warna kamera tidak lengkap');
  }
  final yPlane = frame.planes[0];
  final uPlane = frame.planes[1];
  final vPlane = interleaved ? uPlane : frame.planes[2];
  final step = (math.max(frame.width, frame.height) / 640).ceil();
  final sourceWidth = (frame.width + step - 1) ~/ step;
  final sourceHeight = (frame.height + step - 1) ~/ step;
  final width = rotation == 90 || rotation == 270 ? sourceHeight : sourceWidth;
  final height = rotation == 90 || rotation == 270 ? sourceWidth : sourceHeight;
  if (width < 100 || height < 100 || width > 65535 || height > 65535) {
    throw const FormatException('Resolusi frame kamera tidak didukung');
  }
  final output = Uint8List(8 + width * height * 3);
  output.setRange(0, 4, [76, 86, 67, 49]); // LVC1
  output[4] = width >> 8;
  output[5] = width & 255;
  output[6] = height >> 8;
  output[7] = height & 255;
  for (var y = 0; y < sourceHeight; y++) {
    for (var x = 0; x < sourceWidth; x++) {
      final sx = x * step;
      final sy = y * step;
      final chromaX = sx ~/ 2;
      final chromaY = sy ~/ 2;
      final yIndex = sy * yPlane.bytesPerRow + sx * (yPlane.bytesPerPixel ?? 1);
      final chromaIndex = chromaY * uPlane.bytesPerRow + chromaX * (uPlane.bytesPerPixel ?? (interleaved ? 2 : 1));
      final uIndex = chromaIndex + (interleaved && nv21 ? 1 : 0);
      final vIndex = interleaved
          ? chromaIndex + (nv21 ? 0 : 1)
          : chromaY * vPlane.bytesPerRow + chromaX * (vPlane.bytesPerPixel ?? 1);
      if (yIndex >= yPlane.bytes.length ||
          uIndex >= uPlane.bytes.length ||
          vIndex >= vPlane.bytes.length) {
        throw const FormatException('Data warna kamera tidak lengkap');
      }
      final yy = math.max(0, yPlane.bytes[yIndex] - 16);
      final u = uPlane.bytes[uIndex] - 128;
      final v = vPlane.bytes[vIndex] - 128;
      final destination = switch (rotation) {
        90 => x * width + (width - 1 - y),
        180 => (height - 1 - y) * width + (width - 1 - x),
        270 => (height - 1 - x) * width + y,
        _ => y * width + x,
      };
      final index = 8 + destination * 3;
      output[index] = ((298 * yy + 516 * u + 128) >> 8).clamp(0, 255).toInt();
      output[index + 1] = ((298 * yy - 100 * u - 208 * v + 128) >> 8).clamp(0, 255).toInt();
      output[index + 2] = ((298 * yy + 409 * v + 128) >> 8).clamp(0, 255).toInt();
    }
  }
  return output;
}
