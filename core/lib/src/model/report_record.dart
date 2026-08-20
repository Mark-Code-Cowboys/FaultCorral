// Copyright (c) 2026 Code Cowboys LLC. All rights reserved.

import 'package:meta/meta.dart';

import 'common.dart';

/// Metadata for one generated report (spec §2.1). The PDF itself lives in
/// the app's storage; this record makes the generation reproducible and
/// traceable: which snapshot, which registry versions, which acknowledgment
/// text version the generating user had accepted (spec §0.4).
@immutable
class ReportRecord {
  const ReportRecord({
    required this.meta,
    required this.projectId,
    required this.projectSnapshotRef,
    required this.pdfSha256,
    required this.registryVersions,
    required this.acknowledgmentTextVersion,
    required this.appVersion,
    this.draftWatermark = true,
  });

  final EntityMeta meta;
  final Id projectId;
  final String projectSnapshotRef;
  final String pdfSha256;

  /// rule id → registry entry version in force at generation.
  final Map<String, int> registryVersions;

  /// Version of the first-run acknowledgment text the generating user had
  /// accepted; stamped so every report traces to an accepted acknowledgment.
  final String acknowledgmentTextVersion;

  final String appVersion;

  /// True unless generated from a finalized project with no unresolved-rule
  /// results (spec §6.4 draft watermark).
  final bool draftWatermark;

  Map<String, Object?> toJson() => {
        ...meta.toJson(),
        'project_id': projectId,
        'project_snapshot_ref': projectSnapshotRef,
        'pdf_sha256': pdfSha256,
        'registry_versions': registryVersions,
        'acknowledgment_text_version': acknowledgmentTextVersion,
        'app_version': appVersion,
        'draft_watermark': draftWatermark,
      };

  factory ReportRecord.fromJson(Map<String, Object?> json) => ReportRecord(
        meta: EntityMeta.fromJson(json),
        projectId: json['project_id'] as Id,
        projectSnapshotRef: json['project_snapshot_ref'] as String,
        pdfSha256: json['pdf_sha256'] as String,
        registryVersions:
            (json['registry_versions'] as Map).cast<String, int>(),
        acknowledgmentTextVersion:
            json['acknowledgment_text_version'] as String,
        appVersion: json['app_version'] as String,
        draftWatermark: json['draft_watermark'] as bool? ?? true,
      );
}
