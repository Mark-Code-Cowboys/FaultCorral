// Copyright (c) 2026 Code Cowboys LLC. All rights reserved.
//
// Golden regression harness (spec §3.2). Cases live in ../tests/golden and
// come from the owner's real panels with known-correct outcomes. Placeholder
// cases (status: todo_owner_verify) are structure-checked and skipped.

import 'dart:convert';
import 'dart:io';

import 'package:faultcorral_core/faultcorral_core.dart';
import 'package:test/test.dart';

void main() {
  final goldenDir = Directory('../tests/golden');
  final caseFiles = goldenDir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.json'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  test('golden directory has at least one case file', () {
    expect(caseFiles, isNotEmpty);
  });

  for (final file in caseFiles) {
    final name = file.uri.pathSegments.last;
    group('golden $name', () {
      final map =
          (jsonDecode(file.readAsStringSync()) as Map).cast<String, Object?>();

      test('has required structure', () {
        expect(map['golden_case'], isA<String>());
        expect(map['title'], isA<String>());
        expect(map['status'], anyOf('todo_owner_verify', 'ready'));
      });

      final ready = map['status'] == 'ready';

      test('outcome matches owner-supplied expectation',
          skip: ready
              ? false
              : 'Placeholder awaiting owner-supplied panel (GATE 1).', () {
        final export = map['export'] as Map?;
        final expected = (map['expected'] as Map).cast<String, Object?>();
        expect(export, isNotNull,
            reason: 'A ready case must embed a full project export.');

        final imported = const ProjectExport().import(jsonEncode(export));
        final result =
            const RollupEngine().evaluate(imported.snapshot, imported.registry);

        expect(
          result.panelSccrKaByVoltage,
          (expected['panel_sccr_ka_by_voltage'] as Map)
              .map((k, v) => MapEntry(k as String, (v as num?)?.toDouble())),
        );
        expect(
          result.limitingComponents.map((l) => l.componentId).toList(),
          (expected['limiting_component_ids'] as List).cast<String>(),
        );
      });
    });
  }
}
