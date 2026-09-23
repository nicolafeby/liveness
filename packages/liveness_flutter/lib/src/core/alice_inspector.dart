import 'package:alice/alice.dart';
import 'package:alice/model/alice_configuration.dart';
import 'package:alice_dio/alice_dio_adapter.dart';

final Alice aliceInspector = Alice(
  configuration: AliceConfiguration(
    showNotification: false,
    showInspectorOnShake: true,
  ),
);

AliceDioAdapter createAliceDioAdapter() {
  final adapter = AliceDioAdapter();
  aliceInspector.addAdapter(adapter);
  return adapter;
}
