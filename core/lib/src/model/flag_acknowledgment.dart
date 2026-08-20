// Copyright (c) 2026 Code Cowboys LLC. All rights reserved.

import 'package:meta/meta.dart';

import 'common.dart';

/// A user's recorded acknowledgment of one WARNING flag (spec §3.1: WARNING
/// = finalize with acknowledgment, recorded; spec §6.1 item 5: every WARNING
/// acknowledged, by whom, with note). Keyed by [EngineFlag.key].
@immutable
class FlagAcknowledgment {
  const FlagAcknowledgment({
    required this.flagKey,
    required this.projectId,
    required this.userId,
    required this.timestamp,
    required this.note,
  });

  final String flagKey;
  final Id projectId;
  final Id userId;
  final DateTime timestamp;

  /// Required: the user's own reasoning, printed in the report.
  final String note;

  Map<String, Object?> toJson() => {
        'flag_key': flagKey,
        'project_id': projectId,
        'user_id': userId,
        'timestamp': timestamp.toUtc().toIso8601String(),
        'note': note,
      };

  factory FlagAcknowledgment.fromJson(Map<String, Object?> json) =>
      FlagAcknowledgment(
        flagKey: json['flag_key'] as String,
        projectId: json['project_id'] as Id,
        userId: json['user_id'] as Id,
        timestamp: DateTime.parse(json['timestamp'] as String),
        note: json['note'] as String,
      );
}
