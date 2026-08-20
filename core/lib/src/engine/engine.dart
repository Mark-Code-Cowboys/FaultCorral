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
/// Live in Phase 1: weakest-link rollup, scope, voltage validation, and the
/// assumed-defaults table check. Remaining §3.1 slots (series combination,
/// transformer handling, let-through) exist in the registry and are surfaced
/// in traces as "not evaluated in this build"; their logic lands in later
/// phases per owner specification — never from assistant training data
/// (spec §0.5).
class RollupEngine {
  const RollupEngine();

  RollupResult evaluate(ProjectSnapshot snapshot, RulesRegistry registry) {
    final firedRuleIds = <String>[];
    final flags = <EngineFlag>[];

    // --- Scope rule (§3.1 slot 2) -------------------------------------
    final scopeRule = registry[RuleIds.scope]!;
    firedRuleIds.add(scopeRule.id);
    final requirePowerCircuit =
        scopeRule.params['require_power_circuit_flag'] as bool? ?? true;

    // Deterministic ordering: sort by entity id (spec §3.2 determinism).
    final ordered = [...snapshot.components]
      ..sort((a, b) => a.meta.id.compareTo(b.meta.id));

    final inScope = <Component>[];
    // componentId → accumulated trace steps, in evaluation order.
    final steps = <String, List<TraceStep>>{};

    for (final component in ordered) {
      steps[component.meta.id] = [];
      final included = scopeRule.isDisabled ||
          !requirePowerCircuit ||
          component.powerCircuit;
      if (included) {
        inScope.add(component);
      } else {
        steps[component.meta.id]!.add(TraceStep(
          ruleId: scopeRule.id,
          description: 'Excluded from rollup by the shop-configured '
              'scope rule (power_circuit = false).',
        ));
      }
    }

    // --- Weakest-link rollup (§3.1 slot 1) ----------------------------
    final weakestLink = registry[RuleIds.weakestLinkRollup]!;
    firedRuleIds.add(weakestLink.id);
    final assumedDefaultRule = registry[RuleIds.assumedDefault]!;

    final effectiveByComponent = <String, double?>{};
    final rated = <LimitingComponent>[];
    for (final component in inScope) {
      final trace = steps[component.meta.id]!;
      double? effective;

      if (component.isUnrated) {
        trace.add(const TraceStep(
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
        trace.add(TraceStep(
          description: 'User-supplied SCCR ${effective!.toStringAsFixed(1)} kA '
              '(source: ${src.wire}; citation: ${component.sccrKa.citation}).',
        ));
        if (src == SourceType.assumedDefault) {
          _checkAssumedDefault(
              component, effective, assumedDefaultRule, flags, trace);
          firedRuleIds.add(assumedDefaultRule.id);
        }
        // §3.1 slots 4, 6, 7: registry slots present, logic not evaluated in
        // this build. Recorded in the trace so the appendix never implies
        // an evaluation that did not happen.
        if (component.comboRatingIds.isNotEmpty) {
          trace.add(const TraceStep(
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
      effectiveByComponent[component.meta.id] = effective;
    }

    // --- Voltage validation (§3.1 slot 5) ------------------------------
    final voltageRule = registry[RuleIds.voltageValidation]!;
    if (!voltageRule.isDisabled && inScope.isNotEmpty) {
      firedRuleIds.add(voltageRule.id);
      _validateVoltages(snapshot, inScope, voltageRule, flags, steps);
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

    // Voltage-specific elevation/derating is not modeled in Phase 1, so the
    // same weakest-link result is reported per rated voltage.
    final byVoltage = <String, double?>{
      for (final rv in snapshot.project.ratedVoltages) rv.key: panelSccr,
    };

    final traces = [
      for (final component in ordered)
        ComponentTrace(
          componentId: component.meta.id,
          tag: component.tag,
          effectiveSccrKa: effectiveByComponent[component.meta.id],
          steps: steps[component.meta.id]!,
        ),
    ];

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

  /// §3.1 slot 3: an assumed_default value must come from the shop's own
  /// configured assumed-ratings table ("your configured assumed ratings").
  /// Table entries: {'category': <category wire>, 'sccr_ka': <num>}.
  void _checkAssumedDefault(
    Component component,
    double effective,
    RuleRegistryEntry rule,
    List<EngineFlag> flags,
    List<TraceStep> trace,
  ) {
    final table = (rule.params['defaults_table'] as List? ?? const [])
        .whereType<Map<Object?, Object?>>()
        .map((e) => e.cast<String, Object?>())
        .toList();
    final entry =
        table.where((e) => e['category'] == component.category.wire).toList();
    if (entry.isEmpty) {
      flags.add(EngineFlag(
        ruleId: rule.id,
        ruleVersion: rule.version,
        severity: FlagSeverity.warning,
        message: 'Component "${component.tag}" uses source '
            '"assumed_default", but your configured assumed-ratings table '
            'has no entry for category "${component.category.wire}". '
            'Populate the table or change the source.',
        componentId: component.meta.id,
        circuitId: component.circuitId,
      ));
      trace.add(TraceStep(
        ruleId: rule.id,
        description: 'Source is assumed_default; no matching entry in '
            'your configured assumed ratings.',
      ));
      return;
    }
    final configured = (entry.first['sccr_ka'] as num?)?.toDouble();
    if (configured != effective) {
      flags.add(EngineFlag(
        ruleId: rule.id,
        ruleVersion: rule.version,
        severity: FlagSeverity.warning,
        message: 'Component "${component.tag}" entered assumed-default SCCR '
            '${effective.toStringAsFixed(1)} kA, but your configured assumed '
            'rating for "${component.category.wire}" is '
            '${configured?.toStringAsFixed(1) ?? 'unset'} kA. Reconcile.',
        componentId: component.meta.id,
        circuitId: component.circuitId,
      ));
      trace.add(TraceStep(
        ruleId: rule.id,
        description: 'Source is assumed_default; entered value differs from '
            'your configured assumed rating.',
      ));
    } else {
      trace.add(TraceStep(
        ruleId: rule.id,
        description: 'Source is assumed_default; matches your configured '
            'assumed rating for this category.',
      ));
    }
  }

  /// §3.1 slot 5: component voltage rating vs. panel rated voltage(s).
  /// Mismatch or missing data is a blocking flag. Slash-rating applicability
  /// parameters are owner-defined; until they are configured, any component
  /// or panel with slash-rating context raises a QUESTION for the user.
  void _validateVoltages(
    ProjectSnapshot snapshot,
    List<Component> inScope,
    RuleRegistryEntry rule,
    List<EngineFlag> flags,
    Map<String, List<TraceStep>> steps,
  ) {
    // TODO(owner-verify): slash_rating_params semantics (spec §3.1 slot 5).
    final slashParamsConfigured = rule.params['slash_rating_params'] != null;
    final panelSlashContext =
        snapshot.project.ratedVoltages.any((rv) => rv.slashRatingContext);

    for (final component in inScope) {
      final trace = steps[component.meta.id]!;
      if (!component.voltageRating.isComplete) {
        flags.add(EngineFlag(
          ruleId: rule.id,
          ruleVersion: rule.version,
          severity: FlagSeverity.blocker,
          message: 'Component "${component.tag}" has no complete attested '
              'voltage rating, so it cannot be checked against the panel '
              'rated voltage.',
          componentId: component.meta.id,
          circuitId: component.circuitId,
        ));
        trace.add(TraceStep(
          ruleId: rule.id,
          description: 'Voltage rating incomplete — check against panel '
              'rated voltage not possible.',
        ));
        continue;
      }

      final rating = component.voltageRating.value!;
      var mismatched = false;
      for (final rv in snapshot.project.ratedVoltages) {
        if (rating.volts < rv.volts) {
          mismatched = true;
          flags.add(EngineFlag(
            ruleId: rule.id,
            ruleVersion: rule.version,
            severity: FlagSeverity.blocker,
            message: 'Component "${component.tag}" voltage rating '
                '${rating.volts.toStringAsFixed(0)} V is below the panel '
                'rated voltage ${rv.volts.toStringAsFixed(0)} V '
                '(${rv.system.wire}).',
            componentId: component.meta.id,
            circuitId: component.circuitId,
          ));
        }
      }
      trace.add(TraceStep(
        ruleId: rule.id,
        description: mismatched
            ? 'Voltage rating ${rating.volts.toStringAsFixed(0)} V is below '
                'a panel rated voltage — blocking flag raised.'
            : 'Voltage rating ${rating.volts.toStringAsFixed(0)} V checked '
                'against panel rated voltage(s): no mismatch found.',
      ));

      final slashInvolved = rating.slashRating || panelSlashContext;
      if (slashInvolved && !slashParamsConfigured) {
        flags.add(EngineFlag(
          ruleId: rule.id,
          ruleVersion: rule.version,
          severity: FlagSeverity.question,
          message: 'Component "${component.tag}" involves slash-rating '
              'context, but slash-rating applicability parameters are not '
              'configured in the rules registry. Review before relying on '
              'the voltage check.',
          componentId: component.meta.id,
          circuitId: component.circuitId,
        ));
      }
    }
  }
}
