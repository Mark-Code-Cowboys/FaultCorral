// Copyright (c) 2026 Code Cowboys LLC. All rights reserved.

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';

import '../engine/engine.dart';
import '../engine/result.dart';
import '../engine/snapshot.dart';
import '../model/common.dart';
import '../model/flag_acknowledgment.dart';
import '../model/project.dart';
import '../persistence/project_export.dart';
import '../registry/registry.dart';

/// Why finalization was refused. Never bypassed — dev builds that render
/// unverified-rule output do so as watermarked DRAFTS, not finalizations.
class FinalizationBlocked implements Exception {
  FinalizationBlocked(this.reasons);

  final List<String> reasons;

  @override
  String toString() =>
      'FinalizationBlocked:\n${reasons.map((r) => '  - $r').join('\n')}';
}

/// The immutable output of finalization (spec §2.1): frozen data + registry
/// versions + a SHA-256 over the canonical export JSON. The report PDF hash
/// is recorded separately on the ReportRecord once generated.
@immutable
class FinalizedSnapshot {
  const FinalizedSnapshot({
    required this.projectId,
    required this.exportJson,
    required this.resultJson,
    required this.sha256Hex,
    required this.finalizedBy,
    required this.finalizedAt,
    required this.acknowledgmentTextVersion,
    required this.appVersion,
  });

  final Id projectId;

  /// Canonical single-file export (schema-versioned) this hash covers.
  final String exportJson;

  /// The rollup result at finalization, for the report and the record.
  final String resultJson;

  final String sha256Hex;
  final Id finalizedBy;
  final DateTime finalizedAt;
  final String acknowledgmentTextVersion;
  final String appVersion;

  Map<String, Object?> toJson() => {
        'project_id': projectId,
        'export_json': exportJson,
        'result_json': resultJson,
        'sha256_hex': sha256Hex,
        'finalized_by': finalizedBy,
        'finalized_at': finalizedAt.toUtc().toIso8601String(),
        'acknowledgment_text_version': acknowledgmentTextVersion,
        'app_version': appVersion,
      };

  factory FinalizedSnapshot.fromJson(Map<String, Object?> json) =>
      FinalizedSnapshot(
        projectId: json['project_id'] as Id,
        exportJson: json['export_json'] as String,
        resultJson: json['result_json'] as String,
        sha256Hex: json['sha256_hex'] as String,
        finalizedBy: json['finalized_by'] as Id,
        finalizedAt: DateTime.parse(json['finalized_at'] as String),
        acknowledgmentTextVersion:
            json['acknowledgment_text_version'] as String,
        appVersion: json['app_version'] as String,
      );
}

/// Finalization (spec §2.1, §0.4, §3.1): freezes an immutable snapshot when —
/// and only when —
///   1. the project is not already finalized,
///   2. the rollup has no BLOCKER flags,
///   3. every rule that fired is owner-signed-off (no unverified results),
///   4. every WARNING flag has a recorded acknowledgment with a note,
///   5. the finalizing user has accepted the current acknowledgment text.
class FinalizationService {
  const FinalizationService({this.engine = const RollupEngine()});

  final RollupEngine engine;

  FinalizedSnapshot finalize({
    required ProjectSnapshot snapshot,
    required RulesRegistry registry,
    required Iterable<FlagAcknowledgment> warningAcknowledgments,
    required Id finalizedBy,
    required DateTime finalizedAt,
    required String acceptedAcknowledgmentTextVersion,
    required String appVersion,
  }) {
    final reasons = <String>[];

    if (snapshot.project.status == ProjectStatus.finalized) {
      reasons.add('Project is already finalized; create a new revision.');
    }

    final result = engine.evaluate(snapshot, registry);

    for (final flag
        in result.flags.where((f) => f.severity == FlagSeverity.blocker)) {
      reasons.add('BLOCKER: ${flag.message}');
    }
    if (result.containsUnverifiedRuleResults) {
      reasons.add('One or more rules that fired are still unverified in the '
          'rules registry. The owner must review them against the standard '
          'before any report can be finalized.');
    }

    final acknowledgedKeys = warningAcknowledgments
        .where((a) =>
            a.projectId == snapshot.project.meta.id && a.note.trim().isNotEmpty)
        .map((a) => a.flagKey)
        .toSet();
    for (final flag
        in result.flags.where((f) => f.severity == FlagSeverity.warning)) {
      if (!acknowledgedKeys.contains(flag.key)) {
        reasons.add('Unacknowledged WARNING: ${flag.message}');
      }
    }

    if (reasons.isNotEmpty) {
      throw FinalizationBlocked(reasons);
    }

    final exportJson = const ProjectExport().exportToString(
      snapshot: snapshot,
      registry: registry,
      exportedAt: finalizedAt,
      appVersion: appVersion,
    );

    return FinalizedSnapshot(
      projectId: snapshot.project.meta.id,
      exportJson: exportJson,
      resultJson: jsonEncode(result.toJson()),
      sha256Hex: sha256.convert(utf8.encode(exportJson)).toString(),
      finalizedBy: finalizedBy,
      finalizedAt: finalizedAt,
      acknowledgmentTextVersion: acceptedAcknowledgmentTextVersion,
      appVersion: appVersion,
    );
  }
}
