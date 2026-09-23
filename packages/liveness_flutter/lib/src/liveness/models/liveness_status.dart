import 'package:json_annotation/json_annotation.dart';

@JsonEnum(valueField: 'value')
enum LivenessStatus {
  align('align'),
  open('open'),
  blink('blink'),
  reopen('reopen'),
  move('move'),
  passed('passed'),
  failed('failed');

  const LivenessStatus(this.value);

  final String value;

  bool get isFinished => this == passed || this == failed;
}
