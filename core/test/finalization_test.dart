// Copyright (c) 2026 Code Cowboys LLC. All rights reserved.
//
// Finalization gate tests (spec §2.1, §3.1). Placeholder numeric values only.

import 'package:faultcorral_core/faultcorral_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  const service = FinalizationService();

  FinalizedSnapshot finalizeClean(ProjectSnapshot snap, RulesRegistry reg,
      {Iterable<FlagAcknowledgment> acks = const []}) {
    return service.finalize(
      snapshot: snap,
      registry: reg,
      warningAcknowledgments: acks,
      finalizedBy: 'user-1',
      finalizedAt: t0,
      acceptedAcknowledgmentTextVersion: '0.1.0-draft',
      appVersion: '0.0.1-test',
    );
  }

  test('clean project with signed-off rules finalizes and hashes', () {
    final snap = snapshot([component('c1', sccrKa: 65)]);
    final frozen = finalizeClean(snap, allSignedOffRegistry());
    expect(frozen.sha256Hex, hasLength(64));
    expect(frozen.acknowledgmentTextVersion, '0.1.0-draft');
    // Deterministic: same inputs, same hash.
    expect(finalizeClean(snap, allSignedOffRegistry()).sha256Hex,
        frozen.sha256Hex);
  });

  test('refuses while any fired rule is unverified (spec §0.5)', () {
    final snap = snapshot([component('c1', sccrKa: 65)]);
    expect(
      () => finalizeClean(snap, RulesRegistry.scaffold()),
      throwsA(isA<FinalizationBlocked>()
          .having((e) => e.reasons.join(), 'reasons', contains('unverified'))),
    );
  });

  test('refuses on blockers (UNRATED component)', () {
    final snap = snapshot([component('c1')]);
    expect(() => finalizeClean(snap, allSignedOffRegistry()),
        throwsA(isA<FinalizationBlocked>()));
  });

  test('refuses an already-finalized project', () {
    final snap = snapshot([component('c1', sccrKa: 65)],
        status: ProjectStatus.finalized);
    expect(
      () => finalizeClean(snap, allSignedOffRegistry()),
      throwsA(isA<FinalizationBlocked>().having(
          (e) => e.reasons.join(), 'reasons', contains('new revision'))),
    );
  });

  group('WARNING acknowledgment (spec §3.1)', () {
    // assumed_default with empty table ⇒ WARNING.
    final snap = snapshot([
      component('c1', sccrKa: 65, source: SourceType.assumedDefault),
    ]);
    final registry = allSignedOffRegistry();

    test('unacknowledged warning refuses finalization', () {
      expect(
        () => finalizeClean(snap, registry),
        throwsA(isA<FinalizationBlocked>().having((e) => e.reasons.join(),
            'reasons', contains('Unacknowledged WARNING'))),
      );
    });

    test('acknowledged warning (with note) finalizes', () {
      final result = const RollupEngine().evaluate(snap, registry);
      final warning =
          result.flags.singleWhere((f) => f.severity == FlagSeverity.warning);
      final frozen = finalizeClean(snap, registry, acks: [
        FlagAcknowledgment(
          flagKey: warning.key,
          projectId: 'proj-1',
          userId: 'user-1',
          timestamp: t0,
          note: 'placeholder note for test',
        ),
      ]);
      expect(frozen.sha256Hex, hasLength(64));
    });

    test('acknowledgment with empty note does not count', () {
      final result = const RollupEngine().evaluate(snap, registry);
      final warning =
          result.flags.singleWhere((f) => f.severity == FlagSeverity.warning);
      expect(
        () => finalizeClean(snap, registry, acks: [
          FlagAcknowledgment(
            flagKey: warning.key,
            projectId: 'proj-1',
            userId: 'user-1',
            timestamp: t0,
            note: '   ',
          ),
        ]),
        throwsA(isA<FinalizationBlocked>()),
      );
    });
  });

  test('flag keys are stable across evaluations', () {
    final snap = snapshot([component('c1')]);
    final a = const RollupEngine()
        .evaluate(snap, allSignedOffRegistry())
        .flags
        .map((f) => f.key)
        .toList();
    final b = const RollupEngine()
        .evaluate(snap, allSignedOffRegistry())
        .flags
        .map((f) => f.key)
        .toList();
    expect(a, b);
    expect(a.toSet(), hasLength(a.length), reason: 'keys must be unique');
  });
}
