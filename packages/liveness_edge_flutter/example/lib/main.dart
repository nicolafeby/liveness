import 'package:flutter/material.dart';
import 'package:liveness_edge_flutter/liveness_edge_flutter.dart';

void main() => runApp(const MaterialApp(home: ExampleHome()));

class ExampleHome extends StatelessWidget {
  const ExampleHome({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Liveness Edge Flutter')),
    body: Center(
      child: FilledButton(
        onPressed: () => Navigator.push<void>(
          context,
          MaterialPageRoute(
            builder: (_) => LivenessEdgeScreen(
              configuration: const LivenessConfiguration(
                passiveAntiSpoofSensitivity: PassiveAntiSpoofSensitivity.high,
                faceIdentitySensitivity: FaceIdentitySensitivity.strict,
              ),
              guidelineTextStyle: const TextStyle(color: Color(0xFF243B53), fontSize: 23, fontWeight: FontWeight.w700),
              supportingTextStyle: const TextStyle(color: Color(0xFF627D98)),
              retryButtonBuilder: (context, label, onPressed) =>
                  OutlinedButton.icon(onPressed: onPressed, icon: const Icon(Icons.replay_rounded), label: Text(label)),
              onSuccess: (_) => Navigator.pop(context),
              onFailed: (result) =>
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.instruction))),
            ),
          ),
        ),
        child: const Text('Start offline verification'),
      ),
    ),
  );
}
