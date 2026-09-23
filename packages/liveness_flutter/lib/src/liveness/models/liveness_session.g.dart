// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'liveness_session.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

LivenessSession _$LivenessSessionFromJson(Map<String, dynamic> json) =>
    LivenessSession(
      sessionId: json['session_id'] as String,
      expiresInSeconds: (json['expires_in_seconds'] as num).toInt(),
      status: $enumDecode(_$LivenessStatusEnumMap, json['status']),
      instruction: json['instruction'] as String,
      passed: json['passed'] as bool,
      framesProcessed: (json['frames_processed'] as num).toInt(),
    );

Map<String, dynamic> _$LivenessSessionToJson(LivenessSession instance) =>
    <String, dynamic>{
      'session_id': instance.sessionId,
      'expires_in_seconds': instance.expiresInSeconds,
      'status': _$LivenessStatusEnumMap[instance.status]!,
      'instruction': instance.instruction,
      'passed': instance.passed,
      'frames_processed': instance.framesProcessed,
    };

const _$LivenessStatusEnumMap = {
  LivenessStatus.align: 'align',
  LivenessStatus.open: 'open',
  LivenessStatus.blink: 'blink',
  LivenessStatus.reopen: 'reopen',
  LivenessStatus.move: 'move',
  LivenessStatus.passed: 'passed',
  LivenessStatus.failed: 'failed',
};
