import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liveness/core/color_frame.dart';

void main() {
  test('encodes upright BGR from row-strided YUV planes', () {
    const sourceWidth = 100;
    const sourceHeight = 120;
    final y = Uint8List(sourceHeight * 104)..fillRange(0, sourceHeight * 104, 16);
    y[0] = 235;
    final uv = Uint8List((sourceHeight ~/ 2) * 52)..fillRange(0, (sourceHeight ~/ 2) * 52, 128);
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
    expect(output.sublist(8 + (sourceHeight - 1) * 3, 8 + sourceHeight * 3), [255, 255, 255]);
    expect(output.sublist(8, 11), [0, 0, 0]);
    debugDefaultTargetPlatformOverride = null;
  });
}
