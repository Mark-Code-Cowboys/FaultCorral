// Copyright (c) 2026 Code Cowboys LLC. All rights reserved.

import 'package:meta/meta.dart';

import 'common.dart';

/// One append-only audit record (spec §2.1): who changed what, when,
/// old → new.
@immutable
class AuditEvent {
  const AuditEvent({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.field,
    required this.oldValue,
    required this.newValue,
    required this.userId,
    required this.timestamp,
    this.projectId,
  });

  final Id id;
  final Id? projectId;
  final String entityType;
  final Id entityId;
  final String field;
  final String? oldValue;
  final String? newValue;
  final Id userId;
  final DateTime timestamp;

  Map<String, Object?> toJson() => {
        'id': id,
        'project_id': projectId,
        'entity_type': entityType,
        'entity_id': entityId,
        'field': field,
        'old_value': oldValue,
        'new_value': newValue,
        'user_id': userId,
        'timestamp': timestamp.toUtc().toIso8601String(),
      };

  factory AuditEvent.fromJson(Map<String, Object?> json) => AuditEvent(
        id: json['id'] as Id,
        projectId: json['project_id'] as Id?,
        entityType: json['entity_type'] as String,
        entityId: json['entity_id'] as Id,
        field: json['field'] as String,
        oldValue: json['old_value'] as String?,
        newValue: json['new_value'] as String?,
        userId: json['user_id'] as Id,
        timestamp: DateTime.parse(json['timestamp'] as String),
      );
}

/// Append-only audit trail (spec §0.3). Exposes no mutation besides [append];
/// persistence layers must not offer update or delete for audit rows.
class AuditLog {
  AuditLog([Iterable<AuditEvent>? events]) : _events = [...?events];

  final List<AuditEvent> _events;

  List<AuditEvent> get events => List.unmodifiable(_events);

  void append(AuditEvent event) => _events.add(event);

  List<Object?> toJson() => _events.map((e) => e.toJson()).toList();

  factory AuditLog.fromJson(List<Object?> json) => AuditLog(
      json.map((e) => AuditEvent.fromJson((e as Map).cast<String, Object?>())));
}
