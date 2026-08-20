// Copyright (c) 2026 Code Cowboys LLC. All rights reserved.

import 'package:meta/meta.dart';

import 'common.dart';

/// Record of one user accepting the first-run acknowledgment (spec §0.4).
/// Per-user, not per-shop. Recorded with the acknowledgment text version,
/// app version, user, and timestamp; also mirrored into the audit log by
/// the app layer.
@immutable
class AcknowledgmentRecord {
  const AcknowledgmentRecord({
    required this.id,
    required this.userId,
    required this.textVersion,
    required this.appVersion,
    required this.acceptedAt,
  });

  final Id id;
  final Id userId;

  /// Version of the acknowledgment text accepted (source of truth:
  /// legal/FIRST_RUN_ACKNOWLEDGMENT_DRAFT.md).
  final String textVersion;

  final String appVersion;
  final DateTime acceptedAt;

  Map<String, Object?> toJson() => {
        'id': id,
        'user_id': userId,
        'text_version': textVersion,
        'app_version': appVersion,
        'accepted_at': acceptedAt.toUtc().toIso8601String(),
      };

  factory AcknowledgmentRecord.fromJson(Map<String, Object?> json) =>
      AcknowledgmentRecord(
        id: json['id'] as Id,
        userId: json['user_id'] as Id,
        textVersion: json['text_version'] as String,
        appVersion: json['app_version'] as String,
        acceptedAt: DateTime.parse(json['accepted_at'] as String),
      );
}

/// Gate logic for the mandatory acknowledgment screen (spec §0.4).
/// The UI must present two checkboxes, both unchecked by default, both
/// required — no pre-check, no skip. This class only answers "must we show
/// the screen for this user right now?"; re-presented to every user on any
/// material change to the text (i.e., any bump of [currentTextVersion]).
class AcknowledgmentGate {
  const AcknowledgmentGate({required this.currentTextVersion});

  final String currentTextVersion;

  bool needsAcknowledgment(Id userId, Iterable<AcknowledgmentRecord> records) {
    return !records.any(
      (r) => r.userId == userId && r.textVersion == currentTextVersion,
    );
  }

  /// The accepted text version to stamp into finalized snapshots and report
  /// records for [userId], or null if they have not accepted the current text.
  String? acceptedVersionFor(
      Id userId, Iterable<AcknowledgmentRecord> records) {
    final match = records
        .where((r) => r.userId == userId && r.textVersion == currentTextVersion)
        .toList();
    return match.isEmpty ? null : match.first.textVersion;
  }
}
