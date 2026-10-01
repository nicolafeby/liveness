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
          theme: const LivenessEdgeTheme(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            primaryColor: Colors.orange,
            successColor: Colors.green,
            inactiveRingColor: Colors.white24,
            cameraShape: LivenessCameraShape.oval,
            cameraBorderRadius: 32,
            guidelineTextStyle: TextStyle(
              fontSize: 23,
              fontWeight: FontWeight.w700,
            ),
          ),
          headerBuilder: (context, state) => const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.verified_user_outlined, color: Colors.white),
              SizedBox(width: 8),
              Text(
                'Secure verification',
                style: TextStyle(color: Colors.white),
              ),
            ],
          ),
          retryButtonBuilder: (context, label, onPressed) =>
              OutlinedButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  onPressed();
                },
                icon: const Icon(Icons.replay_rounded),
                label: Text(label),
              ),
          onSuccess: (result) => Navigator.pop(verificationContext, result),
          onFailed: (result) {
            final messenger = ScaffoldMessenger.of(verificationContext);
            messenger
              ..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(content: Text(result.instruction)));
          },
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
                const Text(
                  'Final verified photo',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Image.memory(
                    imageBytes,
                    width: 260,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                  ),
                ),
                const SizedBox(height: 24),
              ],
              FilledButton(
                onPressed: _startVerification,
                child: Text(
                  imageBytes == null ? 'Start verification' : 'Verify again',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
