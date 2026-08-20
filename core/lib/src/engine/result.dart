// Copyright (c) 2026 Code Cowboys LLC. All rights reserved.

import 'package:meta/meta.dart';

import '../model/common.dart';

/// Flag taxonomy the engine emits (spec §3.1).
enum FlagSeverity {
  /// Cannot finalize.
  blocker('blocker'),

  /// Finalize with acknowledgment, recorded.
  warning('warning'),

  /// Informational nudge — a question, never an assertion.
  question('question');

  const FlagSeverity(this.wire);
  final String wire;

  static FlagSeverity fromWire(String wire) =>
      FlagSeverity.values.firstWhere((v) => v.wire == wire);
}

/// One flag raised during evaluation. Every flag names its rule id and the
/// registry version that produced it (spec §3.1).
@immutable
class EngineFlag {
  const EngineFlag({
    required this.ruleId,
    required this.ruleVersion,
    required this.severity,
    required this.message,
    this.componentId,
    this.circuitId,
  });

  final String ruleId;
  final int ruleVersion;
  final FlagSeverity severity;
  final String message;
  final Id? componentId;
  final Id? circuitId;

  Map<String, Object?> toJson() => {
        'rule_id': ruleId,
        'rule_version': ruleVersion,
        'severity': severity.wire,
        'message': message,
        'component_id': componentId,
        'circuit_id': circuitId,
      };
}

/// One step in a component's explainability trace (spec §3.2): why this
/// effective value — source → combos applied → rules fired. Rendered
/// human-readably in the report appendix.
@immutable
class TraceStep {
  const TraceStep({required this.description, this.ruleId});

  final String description;
  final String? ruleId;

  Map<String, Object?> toJson() =>
      {'description': description, 'rule_id': ruleId};
}

@immutable
class ComponentTrace {
  const ComponentTrace({
    required this.componentId,
    required this.tag,
    required this.effectiveSccrKa,
    required this.steps,
  });

  final Id componentId;
  final String tag;

  /// Null when the component is UNRATED.
  final double? effectiveSccrKa;

  final List<TraceStep> steps;

  Map<String, Object?> toJson() => {
        'component_id': componentId,
        'tag': tag,
        'effective_sccr_ka': effectiveSccrKa,
        'steps': steps.map((s) => s.toJson()).toList(),
      };
}

/// A limiting component ("stray") in the ranking.
@immutable
class LimitingComponent {
  const LimitingComponent({
    required this.componentId,
    required this.tag,
    required this.effectiveSccrKa,
  });

  final Id componentId;
  final String tag;
  final double effectiveSccrKa;

  Map<String, Object?> toJson() => {
        'component_id': componentId,
        'tag': tag,
        'effective_sccr_ka': effectiveSccrKa,
      };
}

/// Output of one engine evaluation (spec §3.2). Pure data; reproducible from
/// the snapshot + registry versions embedded here.
@immutable
class RollupResult {
  const RollupResult({
    required this.panelSccrKaByVoltage,
    required this.limitingComponents,
    required this.flags,
    required this.traces,
    required this.firedRuleIds,
    required this.registryVersions,
    required this.containsUnverifiedRuleResults,
  });

  /// RatedVoltage.key → panel SCCR in kA (null when it cannot be determined,
  /// e.g. UNRATED components or nothing in scope).
  final Map<String, double?> panelSccrKaByVoltage;

  /// Ranked ascending by effective SCCR — the strays, worst first.
  final List<LimitingComponent> limitingComponents;

  final List<EngineFlag> flags;
  final List<ComponentTrace> traces;

  /// Rules that actually influenced this result.
  final List<String> firedRuleIds;

  /// rule id → version in force, for reproducibility (spec §2.2).
  final Map<String, int> registryVersions;

  /// True when any rule that fired has not been signed off by the owner
  /// against his copy of the standard. Reports generated in this state carry
  /// the watermark "CONTAINS UNVERIFIED RULES — NOT FOR USE" and the engine
  /// refuses finalization (spec §0.5).
  final bool containsUnverifiedRuleResults;

  bool get hasBlockers => flags.any((f) => f.severity == FlagSeverity.blocker);

  /// Finalization gate: no blockers and every fired rule signed off.
  bool get canFinalize => !hasBlockers && !containsUnverifiedRuleResults;

  Map<String, Object?> toJson() => {
        'panel_sccr_ka_by_voltage': panelSccrKaByVoltage,
        'limiting_components':
            limitingComponents.map((l) => l.toJson()).toList(),
        'flags': flags.map((f) => f.toJson()).toList(),
        'traces': traces.map((t) => t.toJson()).toList(),
        'fired_rule_ids': firedRuleIds,
        'registry_versions': registryVersions,
        'contains_unverified_rule_results': containsUnverifiedRuleResults,
      };
}
