// Copyright (c) 2026 Code Cowboys LLC. All rights reserved.
//
// Property tests (spec §3.2): monotonicity, determinism, snapshot
// reproducibility. Seeded PRNG for reproducible runs; generated values are
// arbitrary placeholders, not domain data.

import 'dart:convert';
import 'dart:math';

import 'package:faultcorral_core/faultcorral_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

const _iterations = 100;

List<Component> randomComponents(Random rng) {
  final count = 1 + rng.nextInt(12);
  return List.generate(count, (i) {
    final unrated = rng.nextInt(10) == 0;
    return component(
      'c${i.toString().padLeft(3, '0')}',
      sccrKa: unrated ? null : (1 + rng.nextInt(200)).toDouble(),
      powerCircuit: rng.nextInt(5) != 0,
    );
  });
}

String resultFingerprint(RollupResult r) => jsonEncode(r.toJson());

void main() {
  const engine = RollupEngine();
  final registry = allSignedOffRegistry();

  test('determinism: same snapshot + registry ⇒ identical output', () {
    final rng = Random(42);
    for (var i = 0; i < _iterations; i++) {
      final snap = snapshot(randomComponents(rng));
      final a = engine.evaluate(snap, registry);
      final b = engine.evaluate(snap, registry);
      expect(resultFingerprint(a), resultFingerprint(b));
    }
  });

  test('monotonicity: raising any component SCCR never lowers panel SCCR', () {
    final rng = Random(1337);
    for (var i = 0; i < _iterations; i++) {
      final components = randomComponents(rng);
      final rated = components.where((c) => !c.isUnrated).toList();
      if (rated.isEmpty) continue;

      final before = engine.evaluate(snapshot(components), registry);
      final beforeValue = before.panelSccrKaByVoltage.values.single;
      if (beforeValue == null) continue;

      final target = rated[rng.nextInt(rated.length)];
      final bumped = components
          .map((c) => c.meta.id == target.meta.id
              ? component(c.meta.id,
                  sccrKa: c.sccrKa.value! + 1 + rng.nextInt(100),
                  powerCircuit: c.powerCircuit)
              : c)
          .toList();

      final after = engine.evaluate(snapshot(bumped), registry);
      final afterValue = after.panelSccrKaByVoltage.values.single;
      expect(afterValue, isNotNull);
      expect(afterValue!, greaterThanOrEqualTo(beforeValue),
          reason: 'Raising ${target.meta.id} lowered the panel SCCR.');
    }
  });

  test('reproducibility: export → import round-trip preserves the rollup', () {
    final rng = Random(2026);
    const exporter = ProjectExport();
    for (var i = 0; i < _iterations; i++) {
      final snap = snapshot(randomComponents(rng));
      final original = engine.evaluate(snap, registry);

      final file = exporter.exportToString(
        snapshot: snap,
        registry: registry,
        exportedAt: t0,
        appVersion: '0.0.1-test',
      );
      final imported = exporter.import(file);
      final replayed = engine.evaluate(imported.snapshot, imported.registry);

      expect(resultFingerprint(replayed), resultFingerprint(original));
    }
  });

  test('import refuses unknown schema versions instead of guessing', () {
    const exporter = ProjectExport();
    final file = exporter.exportToMap(
      snapshot: snapshot([component('c1', sccrKa: 10)]),
      registry: registry,
      exportedAt: t0,
      appVersion: '0.0.1-test',
    );
    file['schema_version'] = '999.0.0';
    expect(() => exporter.import(jsonEncode(file)), throwsFormatException);
  });

  test('import refuses files that are not FaultCorral projects', () {
    const exporter = ProjectExport();
    expect(() => exporter.import('{"format":"something_else"}'),
        throwsFormatException);
  });
}
