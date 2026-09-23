import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:liveness_verify_flutter/src/core/luma_frame.dart';

void main() {
  test('packs row-strided luma and rotates it upright', () {
    const width = 100;
    const height = 120;
    const stride = 104;
    final source = Uint8List(height * stride);
    source[0] = 10;
    source[width - 1] = 20;
    source[(height - 1) * stride] = 30;
    final output = packLumaFrame(
      source,
      width: width,
      height: height,
      rowStride: stride,
      pixelStride: 1,
      rotation: 90,
    );
    expect(output.sublist(0, 4), [76, 86, 89, 49]);
    expect((output[4] << 8) | output[5], height);
    expect((output[6] << 8) | output[7], width);
    expect(output[8 + height - 1], 10);
    expect(output[8 + (width - 1) * height + height - 1], 20);
    expect(output[8], 30);
  });

  test('rejects incomplete camera plane', () {
    expect(
      () => packLumaFrame(
        Uint8List(10),
        width: 100,
        height: 100,
        rowStride: 100,
        pixelStride: 1,
        rotation: 0,
      ),
      throwsFormatException,
    );
  });
}
