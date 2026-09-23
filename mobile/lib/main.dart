import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:liveness_flutter/liveness_flutter.dart';

const _mobileApiUrl = String.fromEnvironment('LIVENESS_API_URL', defaultValue: 'http://127.0.0.1:8000');

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]).then((_) {
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
    home: const LivenessScreen(baseUrl: _mobileApiUrl),
  );
}
