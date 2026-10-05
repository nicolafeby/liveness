import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';

const _channel = MethodChannel('liveness_edge_flutter');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await _channel.invokeMethod<void>('initialize');
  });

  tearDownAll(() async {
    await _channel.invokeMethod<void>('close');
  });

  testWidgets('native detector rejects malformed frames', (tester) async {
    await expectLater(
      _channel.invokeMethod<Object?>('analyze', Uint8List.fromList([1, 2, 3])),
      throwsA(isA<PlatformException>()),
    );
  });

  testWidgets('native detector initializes again after close', (tester) async {
    await _channel.invokeMethod<void>('close');
    await _channel.invokeMethod<void>('initialize');
  });

  testWidgets('native detector rejects the bundled attack corpus', (
    tester,
  ) async {
    final manifestData = await rootBundle.loadString(
      'assets/attack_corpus/manifest.json',
    );
    final manifest = jsonDecode(manifestData) as Map<String, dynamic>;
    expect(manifest['schemaVersion'], 1);
    final threshold = (manifest['threshold'] as num).toDouble();
    final cases = manifest['cases'] as List<dynamic>;
    expect(cases, isNotEmpty);

    for (final value in cases) {
      final attack = value as Map<String, dynamic>;
      final id = attack['id'] as String;
      final frame = await _loadLvc1Frame(attack['asset'] as String);
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
        'analyze',
        frame,
      );

      expect(raw, isNotNull, reason: '$id returned no native result');
      final faceCount = raw!['faceCount'] as int;
      expect(
        faceCount,
        attack['expectedFaceCount'],
        reason: '$id did not exercise the anti-spoof model',
      );
      final score = (raw['liveScore'] as num).toDouble();
      expect(score, inInclusiveRange(0, 1), reason: '$id score is invalid');
      expect(
        score,
        lessThan(threshold),
        reason: '$id was accepted as live (score=$score, threshold=$threshold)',
      );
    }
  });
}

Future<Uint8List> _loadLvc1Frame(String asset) async {
  final data = await rootBundle.load(asset);
  final encoded = data.buffer.asUint8List(
    data.offsetInBytes,
    data.lengthInBytes,
  );
  var image = img.decodeImage(encoded);
  if (image == null) {
    throw FormatException('Could not decode corpus asset: $asset');
  }
  const maxDimension = 480;
  if (math.max(image.width, image.height) > maxDimension) {
    image = image.width >= image.height
        ? img.copyResize(image, width: maxDimension)
        : img.copyResize(image, height: maxDimension);
  }

  final output = Uint8List(8 + image.width * image.height * 3);
  output.setRange(0, 4, const [76, 86, 67, 49]);
  output[4] = image.width >> 8;
  output[5] = image.width & 255;
  output[6] = image.height >> 8;
  output[7] = image.height & 255;
  var offset = 8;
  for (final pixel in image) {
    output[offset++] = pixel.b.toInt();
    output[offset++] = pixel.g.toInt();
    output[offset++] = pixel.r.toInt();
  }
  return output;
}
