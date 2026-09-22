import 'package:flutter/material.dart';
import 'package:liveness/liveness_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const LivenessApp());
}

class LivenessApp extends StatelessWidget {
  const LivenessApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Liveness Detection',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true, fontFamily: 'Roboto'),
    home: const LivenessScreen(),
  );
}
