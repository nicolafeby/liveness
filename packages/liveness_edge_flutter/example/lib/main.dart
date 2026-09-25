import 'package:flutter/material.dart';
import 'package:liveness_edge_flutter/liveness_edge_flutter.dart';

void main() => runApp(const MaterialApp(home: ExampleHome()));

class ExampleHome extends StatefulWidget {
  const ExampleHome({super.key});

  @override
  State<ExampleHome> createState() => _ExampleHomeState();
}

class _ExampleHomeState extends State<ExampleHome> {
  LivenessResult? _result;

  Future<void> _startVerification() async {
    final result = await Navigator.push<LivenessResult>(
      context,
      MaterialPageRoute(
        builder: (verificationContext) => LivenessEdgeScreen(
          configuration: const LivenessConfiguration(
            passiveAntiSpoofSensitivity: PassiveAntiSpoofSensitivity.high,
            faceIdentitySensitivity: FaceIdentitySensitivity.strict,
          ),
          guidelineTextStyle: const TextStyle(color: Color(0xFF243B53), fontSize: 23, fontWeight: FontWeight.w700),
          supportingTextStyle: const TextStyle(color: Color(0xFF627D98)),
          retryButtonBuilder: (context, label, onPressed) =>
              OutlinedButton.icon(onPressed: onPressed, icon: const Icon(Icons.replay_rounded), label: Text(label)),
          onSuccess: (result) => Navigator.pop(verificationContext, result),
          onFailed: (result) =>
              ScaffoldMessenger.of(verificationContext).showSnackBar(SnackBar(content: Text(result.instruction))),
        ),
      ),
    );

    if (!mounted || result == null) return;
    setState(() => _result = result);
  }

  @override
  Widget build(BuildContext context) {
    final imageBytes = _result?.imageBytes;

    return Scaffold(
      appBar: AppBar(title: const Text('Liveness Edge Flutter')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (imageBytes != null) ...[
                const Text('Final verified photo', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Image.memory(imageBytes, width: 260, fit: BoxFit.cover, gaplessPlayback: true),
                ),
                const SizedBox(height: 24),
              ],
              FilledButton(
                onPressed: _startVerification,
                child: Text(imageBytes == null ? 'Start verification' : 'Verify again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
