import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

// Keep streamed frames small enough for mobile uplinks. The detector resizes
// its anti-spoofing input to 80x80, so sending camera-sized frames only adds
// transfer latency without adding useful detail for that model.
const int streamedFrameMaxDimension = 480;

/// Packs an upright, downsampled BGR frame for the backend's LVC1 protocol.
Uint8List encodeColorFrame(
  CameraImage frame,
  int sensorOrientation,
  DeviceOrientation deviceOrientation,
) {
  final rotation =
      (sensorOrientation +
          (deviceOrientation == DeviceOrientation.portraitDown ? 180 : 0)) %
      360;
  if (!{0, 90, 180, 270}.contains(rotation) ||
      frame.width < 100 ||
      frame.height < 100) {
    throw const FormatException(
      'The camera frame size or orientation is invalid.',
    );
  }
  if (frame.format.group == ImageFormatGroup.bgra8888) {
    // camera_avfoundation applies AVCaptureConnection.videoOrientation before
    // delivering BGRA image-stream buffers. They are already display-oriented;
    // applying sensorOrientation again would rotate the final JPEG sideways.
    return _encodeBgraFrame(frame, 0);
  }
  if (frame.format.group != ImageFormatGroup.yuv420 &&
      frame.format.group != ImageFormatGroup.nv21) {
    throw const FormatException('The camera frame format is not supported.');
  }
  final interleaved = frame.planes.length == 2;
  final nv21 = frame.format.group == ImageFormatGroup.nv21;
  if (frame.planes.length < 2) {
    throw const FormatException('The camera color data is incomplete.');
  }
  final yPlane = frame.planes[0];
  final uPlane = frame.planes[1];
  final vPlane = interleaved ? uPlane : frame.planes[2];
  final step = (math.max(frame.width, frame.height) / streamedFrameMaxDimension)
      .ceil();
  final sourceWidth = (frame.width + step - 1) ~/ step;
  final sourceHeight = (frame.height + step - 1) ~/ step;
  final width = rotation == 90 || rotation == 270 ? sourceHeight : sourceWidth;
  final height = rotation == 90 || rotation == 270 ? sourceWidth : sourceHeight;
  if (width < 100 || height < 100 || width > 65535 || height > 65535) {
    throw const FormatException(
      'The camera frame resolution is not supported.',
    );
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
      final chromaIndex =
          chromaY * uPlane.bytesPerRow +
          chromaX * (uPlane.bytesPerPixel ?? (interleaved ? 2 : 1));
      final uIndex = chromaIndex + (interleaved && nv21 ? 1 : 0);
      final vIndex = interleaved
          ? chromaIndex + (nv21 ? 0 : 1)
          : chromaY * vPlane.bytesPerRow +
                chromaX * (vPlane.bytesPerPixel ?? 1);
      if (yIndex >= yPlane.bytes.length ||
          uIndex >= uPlane.bytes.length ||
          vIndex >= vPlane.bytes.length) {
        throw const FormatException('The camera color data is incomplete.');
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
      output[index + 1] = ((298 * yy - 100 * u - 208 * v + 128) >> 8)
          .clamp(0, 255)
          .toInt();
      output[index + 2] = ((298 * yy + 409 * v + 128) >> 8)
          .clamp(0, 255)
          .toInt();
    }
  }
  return output;
}

Uint8List _encodeBgraFrame(CameraImage frame, int rotation) {
  if (frame.planes.length != 1) {
    throw const FormatException('The camera color data is incomplete.');
  }
  final plane = frame.planes.single;
  final pixelStride = plane.bytesPerPixel ?? 4;
  if (pixelStride < 4) {
    throw const FormatException('The camera pixel format is not supported.');
  }
  final step = (math.max(frame.width, frame.height) / streamedFrameMaxDimension)
      .ceil();
  final sourceWidth = (frame.width + step - 1) ~/ step;
  final sourceHeight = (frame.height + step - 1) ~/ step;
  final width = rotation == 90 || rotation == 270 ? sourceHeight : sourceWidth;
  final height = rotation == 90 || rotation == 270 ? sourceWidth : sourceHeight;
  final output = Uint8List(8 + width * height * 3);
  output.setRange(0, 4, [76, 86, 67, 49]);
  output[4] = width >> 8;
  output[5] = width & 255;
  output[6] = height >> 8;
  output[7] = height & 255;
  for (var y = 0; y < sourceHeight; y++) {
    for (var x = 0; x < sourceWidth; x++) {
      final offset = y * step * plane.bytesPerRow + x * step * pixelStride;
      if (offset + 2 >= plane.bytes.length) {
        throw const FormatException('The camera color data is incomplete.');
      }
      final destination = switch (rotation) {
        90 => x * width + (width - 1 - y),
        180 => (height - 1 - y) * width + (width - 1 - x),
        270 => (height - 1 - x) * width + y,
        _ => y * width + x,
      };
      final index = 8 + destination * 3;
      output[index] = plane.bytes[offset];
      output[index + 1] = plane.bytes[offset + 1];
      output[index + 2] = plane.bytes[offset + 2];
    }
  }
  return output;
}

/// Converts an upright LVC1 frame into a display-ready JPEG.
///
/// The crop matches the portrait face guide (width / height = 1 / 1.18), so
/// callers can render it with [BoxFit.cover] without losing additional area.
Uint8List encodeResultImage(Uint8List frame) {
  if (frame.length < 8 ||
      frame[0] != 76 ||
      frame[1] != 86 ||
      frame[2] != 67 ||
      frame[3] != 49) {
    throw const FormatException('The liveness result frame is invalid.');
  }
  final width = frame[4] << 8 | frame[5];
  final height = frame[6] << 8 | frame[7];
  if (width < 1 || height < 1 || frame.length != 8 + width * height * 3) {
    throw const FormatException('The liveness result frame size is invalid.');
  }

  var source = img.Image(width: width, height: height);
  var offset = 8;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final blue = frame[offset++];
      final green = frame[offset++];
      final red = frame[offset++];
      source.setPixelRgb(x, y, red, green, blue);
    }
  }

  // Some camera_avfoundation/device combinations still deliver landscape
  // pixels while reporting a portrait device orientation. Normalize from the
  // actual pixel dimensions so the exported result is reliably portrait.
  if (source.width > source.height) {
    source = img.copyRotate(source, angle: -90);
  }

  const guideAspectRatio = 1 / 1.18;
  var cropWidth = source.width;
  var cropHeight = (cropWidth / guideAspectRatio).round();
  if (cropHeight > source.height) {
    cropHeight = source.height;
    cropWidth = (cropHeight * guideAspectRatio).round();
  }
  final cropped = img.copyCrop(
    source,
    x: (source.width - cropWidth) ~/ 2,
    y: (source.height - cropHeight) ~/ 2,
    width: cropWidth,
    height: cropHeight,
  );
  final mirrored = img.flipHorizontal(cropped);
  return Uint8List.fromList(img.encodeJpg(mirrored, quality: 92));
}
