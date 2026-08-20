// Copyright (c) 2026 Code Cowboys LLC. All rights reserved.
//
// Schema-migration check (spec §4 CI): the export schema version constant in
// core must match data/schemas/project_export.schema.json. A mismatch means
// someone changed the format without versioning it — fail CI.

import 'dart:convert';
import 'dart:io';

void main() {
  final source = File(
    'core/lib/src/persistence/project_export.dart',
  ).readAsStringSync();
  final match = RegExp(
    r"projectExportSchemaVersion\s*=\s*'([^']+)'",
  ).firstMatch(source);
  if (match == null) {
    stderr.writeln('schema-check: FAIL — version constant not found in core.');
    exit(1);
  }
  final coreVersion = match.group(1);

  final schema =
      (jsonDecode(
                File(
                  'data/schemas/project_export.schema.json',
                ).readAsStringSync(),
              )
              as Map)
          .cast<String, Object?>();
  final schemaVersion =
      ((schema['properties'] as Map)['schema_version'] as Map)['const'];

  if (coreVersion != schemaVersion) {
    stderr.writeln(
      'schema-check: FAIL — core declares $coreVersion but '
      'data/schemas/project_export.schema.json declares $schemaVersion. '
      'Version the change and add a migration.',
    );
    exit(1);
  }
  stdout.writeln('schema-check: OK ($coreVersion)');
}
