// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'liveness_result.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

LivenessResult _$LivenessResultFromJson(Map<String, dynamic> json) =>
    LivenessResult(
      status: $enumDecode(_$LivenessStatusEnumMap, json['status']),
      instruction: json['instruction'] as String,
      passed: json['passed'] as bool,
      framesProcessed: (json['frames_processed'] as num).toInt(),
    );

Map<String, dynamic> _$LivenessResultToJson(LivenessResult instance) =>
    <String, dynamic>{
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
