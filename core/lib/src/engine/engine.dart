// Copyright (c) 2026 Code Cowboys LLC. All rights reserved.

import '../model/common.dart';
import '../model/component.dart';
import '../registry/registry.dart';
import '../registry/rule_entry.dart';
import 'result.dart';
import 'snapshot.dart';

/// The rollup engine (spec §3.2): pure, deterministic, side-effect free.
/// Input: project snapshot + registry snapshot. Output: [RollupResult].
///
/// Phase 0 implements the weakest-link rollup and the scope filter against
/// user-supplied data. The remaining §3.1 slots exist in the registry and
/// are surfaced in traces as "not evaluated in this build"; their logic
/// lands in later phases per owner specification — never from assistant
/// training data (spec §0.5).
class RollupEngine {
  const RollupEngine();

  RollupResult evaluate(ProjectSnapshot snapshot, RulesRegistry registry) {
    final firedRuleIds = <String>[];
    final flags = <EngineFlag>[];
    final traces = <ComponentTrace>[];

    // --- Scope rule (§3.1 slot 2) -------------------------------------
    final scopeRule = registry[RuleIds.scope]!;
    firedRuleIds.add(scopeRule.id);
    final requirePowerCircuit =
        scopeRule.params['require_power_circuit_flag'] as bool? ?? true;

    // Deterministic ordering: sort by entity id (spec §3.2 determinism).
    final ordered = [...snapshot.components]
      ..sort((a, b) => a.meta.id.compareTo(b.meta.id));

    final inScope = <Component>[];
    for (final component in ordered) {
      if (scopeRule.isDisabled) break;
      final included = !requirePowerCircuit || component.powerCircuit;
      if (included) {
        inScope.add(component);
      } else {
        traces.add(ComponentTrace(
          componentId: component.meta.id,
          tag: component.tag,
          effectiveSccrKa: null,
          steps: [
            TraceStep(
              ruleId: scopeRule.id,
              description: 'Excluded from rollup by the shop-configured '
                  'scope rule (power_circuit = false).',
            ),
          ],
        ));
      }
    }

    // --- Weakest-link rollup (§3.1 slot 1) ----------------------------
    final weakestLink = registry[RuleIds.weakestLinkRollup]!;
    firedRuleIds.add(weakestLink.id);
    final assumedDefaultRule = registry[RuleIds.assumedDefault]!;

    final rated = <LimitingComponent>[];
    for (final component in inScope) {
      final steps = <TraceStep>[];
      double? effective;

      if (component.isUnrated) {
        steps.add(const TraceStep(
          description: 'UNRATED — no complete attested SCCR entry '
              '(value, source type, citation, and attester are all required).',
        ));
        flags.add(EngineFlag(
          ruleId: weakestLink.id,
          ruleVersion: weakestLink.version,
          severity: FlagSeverity.blocker,
          message: 'Component "${component.tag}" is UNRATED. Enter and attest '
              'an SCCR value (with source and citation) to resolve.',
          componentId: component.meta.id,
          circuitId: component.circuitId,
        ));
      } else {
        effective = component.sccrKa.value;
        final src = component.sccrKa.sourceType!;
        steps.add(TraceStep(
          description: 'User-supplied SCCR ${effective!.toStringAsFixed(1)} kA '
              '(source: ${src.wire}; citation: ${component.sccrKa.citation}).',
        ));
        if (src == SourceType.assumedDefault) {
          // §3.1 slot 3: the value must come from the shop's own configured
          // assumed-ratings table. The table ships empty.
          firedRuleIds.add(assumedDefaultRule.id);
          final table =
              assumedDefaultRule.params['defaults_table'] as List? ?? const [];
          if (table.isEmpty) {
            flags.add(EngineFlag(
              ruleId: assumedDefaultRule.id,
              ruleVersion: assumedDefaultRule.version,
              severity: FlagSeverity.warning,
              message: 'Component "${component.tag}" uses source '
                  '"assumed_default", but your configured assumed-ratings '
                  'table is empty. Populate the table or change the source.',
              componentId: component.meta.id,
              circuitId: component.circuitId,
            ));
            steps.add(TraceStep(
              ruleId: assumedDefaultRule.id,
              description: 'Source is assumed_default; no matching entry in '
                  'your configured assumed ratings.',
            ));
          }
        }
        // §3.1 slots 4–7: registry slots present, logic not evaluated in
        // this build. Recorded in the trace so the appendix never implies
        // an evaluation that did not happen.
        if (component.comboRatingIds.isNotEmpty) {
          steps.add(const TraceStep(
            ruleId: RuleIds.seriesCombination,
            description: 'Series combination(s) attached but not applied: '
                'the series-combination rule is not evaluated in this build.',
          ));
        }
        rated.add(LimitingComponent(
          componentId: component.meta.id,
          tag: component.tag,
          effectiveSccrKa: effective,
        ));
      }

      traces.add(ComponentTrace(
        componentId: component.meta.id,
        tag: component.tag,
        effectiveSccrKa: effective,
        steps: steps,
      ));
    }

    if (inScope.isEmpty) {
      flags.add(EngineFlag(
        ruleId: scopeRule.id,
        ruleVersion: scopeRule.version,
        severity: FlagSeverity.blocker,
        message: 'No components are in the rollup scope. Add power-circuit '
            'components or review the scope rule configuration.',
      ));
    }

    // Rank the strays, worst first; stable tie-break by id.
    rated.sort((a, b) {
      final byValue = a.effectiveSccrKa.compareTo(b.effectiveSccrKa);
      return byValue != 0 ? byValue : a.componentId.compareTo(b.componentId);
    });
    final topN = weakestLink.params['top_n_strays'] as int? ?? 3;
    final limiting = rated.take(topN).toList();

    final anyUnrated = inScope.any((c) => c.isUnrated);
    final panelSccr =
        (anyUnrated || rated.isEmpty) ? null : rated.first.effectiveSccrKa;

    // Phase 0: voltage-specific behavior (slot 5) is not evaluated, so the
    // same weakest-link result is reported per rated voltage.
    final byVoltage = <String, double?>{
      for (final rv in snapshot.project.ratedVoltages) rv.key: panelSccr,
    };

    final fired = firedRuleIds.toSet().toList()..sort();
    final containsUnverified = fired.any((id) {
      final entry = registry[id];
      return entry != null && entry.status == RuleStatus.unverified;
    });

    return RollupResult(
      panelSccrKaByVoltage: byVoltage,
      limitingComponents: limiting,
      flags: flags,
      traces: traces,
      firedRuleIds: fired,
      registryVersions: registry.versions,
      containsUnverifiedRuleResults: containsUnverified,
    );
  }
}
