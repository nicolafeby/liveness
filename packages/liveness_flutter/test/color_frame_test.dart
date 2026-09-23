import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liveness_flutter/src/core/color_frame.dart';
import 'package:image/image.dart' as img;

void main() {
  test('encodes upright BGR from row-strided YUV planes', () {
    const sourceWidth = 100;
    const sourceHeight = 120;
    final y = Uint8List(sourceHeight * 104)
      ..fillRange(0, sourceHeight * 104, 16);
    y[0] = 235;
    final uv = Uint8List((sourceHeight ~/ 2) * 52)
      ..fillRange(0, (sourceHeight ~/ 2) * 52, 128);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    // ignore: deprecated_member_use
    final frame = CameraImage.fromPlatformData({
      'format': 35,
      'width': sourceWidth,
      'height': sourceHeight,
      'planes': [
        {'bytes': y, 'bytesPerRow': 104, 'bytesPerPixel': 1},
        {'bytes': uv, 'bytesPerRow': 52, 'bytesPerPixel': 1},
        {'bytes': uv, 'bytesPerRow': 52, 'bytesPerPixel': 1},
      ],
    });
    final output = encodeColorFrame(frame, 90, DeviceOrientation.portraitUp);
    expect(output.sublist(0, 4), [76, 86, 67, 49]);
    expect((output[4] << 8) | output[5], sourceHeight);
    expect((output[6] << 8) | output[7], sourceWidth);
    expect(output.sublist(8 + (sourceHeight - 1) * 3, 8 + sourceHeight * 3), [
      255,
      255,
      255,
    ]);
    expect(output.sublist(8, 11), [0, 0, 0]);
    debugDefaultTargetPlatformOverride = null;
  });

  test('encodes a mirrored JPEG cropped to the face-guide ratio', () {
    const width = 100;
    const height = 150;
    final frame = Uint8List(8 + width * height * 3);
    frame.setRange(0, 8, [76, 86, 67, 49, 0, width, 0, height]);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final offset = 8 + (y * width + x) * 3;
        frame[offset] = x < width ~/ 2 ? 255 : 0;
        frame[offset + 2] = x < width ~/ 2 ? 0 : 255;
      }
    }

    final jpeg = encodeResultImage(frame);
    final decoded = img.decodeJpg(jpeg)!;
    expect(decoded.width, 100);
    expect(decoded.height, 118);
    expect(decoded.getPixel(10, 50).r, greaterThan(decoded.getPixel(10, 50).b));
    expect(decoded.getPixel(90, 50).b, greaterThan(decoded.getPixel(90, 50).r));
  });
}
