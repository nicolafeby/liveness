import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:liveness/liveness/alice_inspector.dart';
import 'package:liveness/liveness/liveness_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]).then((_) {
    runApp(const LivenessApp());
  });
}

class LivenessApp extends StatelessWidget {
  const LivenessApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    navigatorKey: aliceInspector.getNavigatorKey(),
    title: 'Liveness Detection',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true, fontFamily: 'Roboto'),
    home: const LivenessScreen(),
  );
}
