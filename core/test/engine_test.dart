// Copyright (c) 2026 Code Cowboys LLC. All rights reserved.
//
// Engine mechanics against PLACEHOLDER data (spec Phase 0). Numeric values
// are arbitrary; they assert nothing about real devices or the standard.

import 'package:faultcorral_core/faultcorral_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  const engine = RollupEngine();

  group('Weakest-link rollup', () {
    test('panel SCCR is the minimum across in-scope components', () {
      final result = engine.evaluate(
        snapshot([
          component('c1', sccrKa: 65),
          component('c2', sccrKa: 10),
          component('c3', sccrKa: 100),
        ]),
        allSignedOffRegistry(),
      );
      expect(result.panelSccrKaByVoltage.values.single, 10);
      expect(result.limitingComponents.first.componentId, 'c2');
    });

    test('strays are ranked ascending, top N', () {
      final result = engine.evaluate(
        snapshot([
          component('c1', sccrKa: 65),
          component('c2', sccrKa: 10),
          component('c3', sccrKa: 100),
          component('c4', sccrKa: 5),
        ]),
        allSignedOffRegistry(),
      );
      expect(result.limitingComponents.map((l) => l.componentId).toList(),
          ['c4', 'c2', 'c1']);
    });

    test('UNRATED component blocks and yields no panel value', () {
      final result = engine.evaluate(
        snapshot([component('c1', sccrKa: 65), component('c2')]),
        allSignedOffRegistry(),
      );
      expect(result.panelSccrKaByVoltage.values.single, isNull);
      expect(result.hasBlockers, isTrue);
      expect(result.canFinalize, isFalse);
      final blocker =
          result.flags.singleWhere((f) => f.severity == FlagSeverity.blocker);
      expect(blocker.componentId, 'c2');
      expect(blocker.ruleId, RuleIds.weakestLinkRollup);
    });

    test('empty scope is a blocker', () {
      final result = engine.evaluate(snapshot([]), allSignedOffRegistry());
      expect(result.hasBlockers, isTrue);
      expect(result.panelSccrKaByVoltage.values.single, isNull);
    });
  });

  group('Scope rule', () {
    test('control-circuit components are excluded from rollup', () {
      final result = engine.evaluate(
        snapshot([
          component('c1', sccrKa: 65),
          component('c2', sccrKa: 5, powerCircuit: false),
        ]),
        allSignedOffRegistry(),
      );
      expect(result.panelSccrKaByVoltage.values.single, 65,
          reason: 'The 5 kA control-circuit component must not drag the '
              'rollup down.');
      final excludedTrace =
          result.traces.singleWhere((t) => t.componentId == 'c2');
      expect(excludedTrace.steps.single.ruleId, RuleIds.scope);
    });
  });

  group('Finalization gate (spec §0.5)', () {
    test('unmarked fired rules refuse finalization', () {
      final result = engine.evaluate(
        snapshot([component('c1', sccrKa: 65)]),
        RulesRegistry.scaffold(),
      );
      expect(result.containsUnverifiedRuleResults, isTrue);
      expect(result.canFinalize, isFalse);
      expect(result.hasBlockers, isFalse,
          reason: 'The gate closes on rule status alone, without blockers.');
    });

    test('owner-signed-off rules with clean data may finalize', () {
      final result = engine.evaluate(
        snapshot([component('c1', sccrKa: 65)]),
        allSignedOffRegistry(),
      );
      expect(result.canFinalize, isTrue);
    });
  });

  group('assumed_default source (spec §3.1 slot 3)', () {
    test('empty shop defaults table raises a warning', () {
      final result = engine.evaluate(
        snapshot([
          component('c1', sccrKa: 5, source: SourceType.assumedDefault),
        ]),
        allSignedOffRegistry(),
      );
      final warning =
          result.flags.singleWhere((f) => f.severity == FlagSeverity.warning);
      expect(warning.ruleId, RuleIds.assumedDefault);
      expect(result.firedRuleIds, contains(RuleIds.assumedDefault));
    });
  });

  group('Explainability (spec §3.2)', () {
    test('every in-scope component gets a trace naming its source', () {
      final result = engine.evaluate(
        snapshot([component('c1', sccrKa: 65)]),
        allSignedOffRegistry(),
      );
      final trace = result.traces.single;
      expect(trace.effectiveSccrKa, 65);
      expect(trace.steps.first.description, contains('datasheet'));
      expect(trace.steps.first.description, contains('placeholder citation'));
    });

    test('attached combos are traced as not applied in this build', () {
      final result = engine.evaluate(
        snapshot([
          component('c1', sccrKa: 65, comboRatingIds: ['combo-1']),
        ]),
        allSignedOffRegistry(),
      );
      expect(
        result.traces.single.steps
            .any((s) => s.ruleId == RuleIds.seriesCombination),
        isTrue,
      );
    });
  });

  group('Voltage validation (spec §3.1 slot 5)', () {
    test('rating below panel voltage is a blocker', () {
      final result = engine.evaluate(
        snapshot([component('c1', sccrKa: 65, volts: 240)]),
        allSignedOffRegistry(),
      );
      final blocker =
          result.flags.singleWhere((f) => f.severity == FlagSeverity.blocker);
      expect(blocker.ruleId, RuleIds.voltageValidation);
      expect(blocker.componentId, 'c1');
      expect(result.canFinalize, isFalse);
    });

    test('rating at or above panel voltage raises no voltage flag', () {
      final result = engine.evaluate(
        snapshot([
          component('c1', sccrKa: 65, volts: 480),
          component('c2', sccrKa: 65, volts: 600),
        ]),
        allSignedOffRegistry(),
      );
      expect(result.flags, isEmpty);
    });

    test('missing voltage rating is a blocker', () {
      final result = engine.evaluate(
        snapshot([component('c1', sccrKa: 65, volts: null)]),
        allSignedOffRegistry(),
      );
      final blocker =
          result.flags.singleWhere((f) => f.severity == FlagSeverity.blocker);
      expect(blocker.ruleId, RuleIds.voltageValidation);
    });

    test('voltage rule fires and appears in fired list', () {
      final result = engine.evaluate(
        snapshot([component('c1', sccrKa: 65)]),
        allSignedOffRegistry(),
      );
      expect(result.firedRuleIds, contains(RuleIds.voltageValidation));
    });

    test('slash-rating context without configured params is a question', () {
      final panel = Project(
        meta: meta('proj-1'),
        shopId: 'shop-1',
        name: 'Test Panel',
        status: ProjectStatus.draft,
        ratedVoltages: const [
          RatedVoltage(
              volts: 480,
              system: VoltageSystem.threePhaseWye,
              slashRatingContext: true),
        ],
      );
      final result = engine.evaluate(
        ProjectSnapshot(
          project: panel,
          circuits: [feeder()],
          components: [component('c1', sccrKa: 65)],
        ),
        allSignedOffRegistry(),
      );
      final question =
          result.flags.singleWhere((f) => f.severity == FlagSeverity.question);
      expect(question.ruleId, RuleIds.voltageValidation);
    });
  });

  group('Assumed-defaults table matching (spec §3.1 slot 3)', () {
    RulesRegistry withTable(List<Map<String, Object?>> table) {
      final reg = allSignedOffRegistry();
      final rule = reg[RuleIds.assumedDefault]!;
      return reg.withEntry(rule.copyWith(
        params: {...rule.params, 'defaults_table': table},
        version: rule.version + 1,
      ));
    }

    test('entered value matching the shop table raises no flag', () {
      final result = engine.evaluate(
        snapshot(
            [component('c1', sccrKa: 5, source: SourceType.assumedDefault)]),
        withTable([
          {'category': 'circuit_breaker_mccb', 'sccr_ka': 5},
        ]),
      );
      expect(result.flags, isEmpty);
      expect(
        result.traces.single.steps
            .any((s) => s.description.contains('matches your configured')),
        isTrue,
      );
    });

    test('entered value differing from the shop table warns', () {
      final result = engine.evaluate(
        snapshot(
            [component('c1', sccrKa: 10, source: SourceType.assumedDefault)]),
        withTable([
          {'category': 'circuit_breaker_mccb', 'sccr_ka': 5},
        ]),
      );
      final warning =
          result.flags.singleWhere((f) => f.severity == FlagSeverity.warning);
      expect(warning.message, contains('Reconcile'));
    });

    test('no table entry for the category warns', () {
      final result = engine.evaluate(
        snapshot(
            [component('c1', sccrKa: 5, source: SourceType.assumedDefault)]),
        withTable([
          {'category': 'contactor', 'sccr_ka': 5},
        ]),
      );
      final warning =
          result.flags.singleWhere((f) => f.severity == FlagSeverity.warning);
      expect(warning.message, contains('no entry for category'));
    });
  });

  group('Flag provenance (spec §3.1)', () {
    test('every flag names its rule id and version', () {
      final result = engine.evaluate(
        snapshot([component('c2')]),
        RulesRegistry.scaffold(),
      );
      for (final flag in result.flags) {
        expect(RuleIds.all, contains(flag.ruleId));
        expect(flag.ruleVersion, greaterThan(0));
      }
    });
  });
}
