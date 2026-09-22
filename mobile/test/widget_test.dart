import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liveness/main.dart';

void main() {
  testWidgets('liveness screen shows face positioning guidance', (tester) async {
    await tester.pumpWidget(const LivenessApp());
    expect(find.text('Hadapkan wajah ke kamera dan pastikan kedua mata terlihat jelas.'), findsOneWidget);
    expect(find.text('Posisikan wajah di dalam bingkai'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);
  });
}
