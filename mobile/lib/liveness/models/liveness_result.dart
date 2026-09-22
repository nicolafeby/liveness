import 'package:json_annotation/json_annotation.dart';

import 'liveness_status.dart';

part 'liveness_result.g.dart';

@JsonSerializable(fieldRename: FieldRename.snake)
class LivenessResult {
  const LivenessResult({
    required this.status,
    required this.instruction,
    required this.passed,
    required this.framesProcessed,
  });

  final LivenessStatus status;
  final String instruction;
  final bool passed;
  final int framesProcessed;

  factory LivenessResult.fromJson(Map<String, dynamic> json) => _$LivenessResultFromJson(json);

  Map<String, dynamic> toJson() => _$LivenessResultToJson(this);
}
