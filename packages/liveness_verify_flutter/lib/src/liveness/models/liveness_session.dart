import 'package:json_annotation/json_annotation.dart';

import 'liveness_result.dart';
import 'liveness_status.dart';

part 'liveness_session.g.dart';

@JsonSerializable(fieldRename: FieldRename.snake)
class LivenessSession {
  const LivenessSession({
    required this.sessionId,
    required this.expiresInSeconds,
    required this.status,
    required this.instruction,
    required this.passed,
    required this.framesProcessed,
  });

  final String sessionId;
  final int expiresInSeconds;
  final LivenessStatus status;
  final String instruction;
  final bool passed;
  final int framesProcessed;

  LivenessResult get result => LivenessResult(
    status: status,
    instruction: instruction,
    passed: passed,
    framesProcessed: framesProcessed,
  );

  factory LivenessSession.fromJson(Map<String, dynamic> json) =>
      _$LivenessSessionFromJson(json);

  Map<String, dynamic> toJson() => _$LivenessSessionToJson(this);
}
