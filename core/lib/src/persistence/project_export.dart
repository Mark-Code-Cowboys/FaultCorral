// Copyright (c) 2026 Code Cowboys LLC. All rights reserved.

import 'dart:convert';

import '../engine/snapshot.dart';
import '../registry/registry.dart';

/// Version of the portable project file format. Bump on any breaking change
/// and add a migration in [ProjectExport.import]. Checked against
/// data/schemas/project_export.schema.json by tool/schema_check.dart.
const String projectExportSchemaVersion = '0.1.0';

/// Single-file portable project export/import (spec §4): JSON, versioned
/// schema, embedded registry versions. This is also the backup story from
/// day one — export must always work, on every tier (spec §8).
class ProjectExport {
  const ProjectExport();

  Map<String, Object?> exportToMap({
    required ProjectSnapshot snapshot,
    required RulesRegistry registry,
    required DateTime exportedAt,
    required String appVersion,
  }) =>
      {
        'format': 'faultcorral_project',
        'schema_version': projectExportSchemaVersion,
        'app_version': appVersion,
        'exported_at': exportedAt.toUtc().toIso8601String(),
        'registry_versions': registry.versions,
        'registry': registry.toJson(),
        'snapshot': snapshot.toJson(),
      };

  String exportToString({
    required ProjectSnapshot snapshot,
    required RulesRegistry registry,
    required DateTime exportedAt,
    required String appVersion,
  }) =>
      const JsonEncoder.withIndent('  ').convert(exportToMap(
        snapshot: snapshot,
        registry: registry,
        exportedAt: exportedAt,
        appVersion: appVersion,
      ));

  ({ProjectSnapshot snapshot, RulesRegistry registry}) import(String json) {
    final map = (jsonDecode(json) as Map).cast<String, Object?>();
    if (map['format'] != 'faultcorral_project') {
      throw const FormatException('Not a FaultCorral project file.');
    }
    final version = map['schema_version'] as String?;
    if (version != projectExportSchemaVersion) {
      // Migrations land here as the schema evolves; unknown versions must
      // fail loudly rather than guess (spec §8: zero data loss).
      throw FormatException('Unsupported project file schema version: $version '
          '(this build reads $projectExportSchemaVersion).');
    }
    return (
      snapshot: ProjectSnapshot.fromJson(
          (map['snapshot'] as Map).cast<String, Object?>()),
      registry: RulesRegistry.fromJson(map['registry'] as List),
    );
  }
}
