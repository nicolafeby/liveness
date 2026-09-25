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
