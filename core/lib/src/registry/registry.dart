// Copyright (c) 2026 Code Cowboys LLC. All rights reserved.

import 'package:meta/meta.dart';

import 'rule_entry.dart';

/// Stable rule ids the engine dispatches on (spec §3.1 slots 1–8).
abstract final class RuleIds {
  static const weakestLinkRollup = 'weakest_link_rollup';
  static const scope = 'scope';
  static const assumedDefault = 'assumed_default';
  static const seriesCombination = 'series_combination';
  static const voltageValidation = 'voltage_validation';
  static const transformerHandling = 'transformer_handling';
  static const currentLimitingLetThrough = 'current_limiting_let_through';
  static const pdbPresenceCheck = 'pdb_presence_check';

  static const all = [
    weakestLinkRollup,
    scope,
    assumedDefault,
    seriesCombination,
    voltageValidation,
    transformerHandling,
    currentLimitingLetThrough,
    pdbPresenceCheck,
  ];
}

/// The shop's rules registry (spec §3.1): the mechanism that keeps the app a
/// tool rather than an authority. Ships as scaffolded slots — descriptions
/// below are placeholders for the owner's own words, parameters are empty,
/// and every rule is `unverified` (let-through elevation ships `disabled`).
@immutable
class RulesRegistry {
  RulesRegistry(Iterable<RuleRegistryEntry> entries)
      : entries = Map.unmodifiable({for (final e in entries) e.id: e});

  final Map<String, RuleRegistryEntry> entries;

  RuleRegistryEntry? operator [](String ruleId) => entries[ruleId];

  /// rule id → version, embedded in snapshots and reports so every rollup is
  /// reproducible (spec §2.2).
  Map<String, int> get versions =>
      {for (final e in entries.values) e.id: e.version};

  RulesRegistry withEntry(RuleRegistryEntry entry) =>
      RulesRegistry({...entries, entry.id: entry}.values);

  List<Object?> toJson() => entries.values.map((e) => e.toJson()).toList();

  factory RulesRegistry.fromJson(List<Object?> json) => RulesRegistry(json.map(
      (e) => RuleRegistryEntry.fromJson((e as Map).cast<String, Object?>())));

  /// The shipped scaffold: all §3.1 slots, no owner-populated parameters,
  /// nothing marked off by anyone. TODO(owner-verify): every entry below —
  /// owner supplies description in his own words, clause pointer, params,
  /// and flips status after checking against his copy of UL 508A.
  factory RulesRegistry.scaffold() => RulesRegistry([
        const RuleRegistryEntry(
          id: RuleIds.weakestLinkRollup,
          name: 'Weakest-link rollup',
          description:
              'PLACEHOLDER — owner wording required. Panel SCCR is the '
              'minimum effective SCCR across in-scope components; limiting '
              'components are ranked (top-N strays).',
          status: RuleStatus.unverified,
          version: 1,
          // TODO(owner-verify): confirm ranking depth. Placeholder param.
          params: {'top_n_strays': 3},
        ),
        const RuleRegistryEntry(
          id: RuleIds.scope,
          name: 'Rollup scope',
          description:
              'PLACEHOLDER — owner wording required. Which categories/flags '
              'are in the power-circuit rollup.',
          status: RuleStatus.unverified,
          version: 1,
          // TODO(owner-verify): category applicability list is owner-defined.
          params: {'require_power_circuit_flag': true, 'category_scope': null},
        ),
        const RuleRegistryEntry(
          id: RuleIds.assumedDefault,
          name: 'Assumed-default values',
          description:
              'PLACEHOLDER — owner wording required. Values with source type '
              'assumed_default come from the shop-configured assumed-ratings '
              'table. UI label: "your configured assumed ratings".',
          status: RuleStatus.unverified,
          version: 1,
          // TODO(owner-verify): defaults table ships EMPTY; owner populates.
          params: {'defaults_table': <Object?>[]},
        ),
        const RuleRegistryEntry(
          id: RuleIds.seriesCombination,
          name: 'Series-combination application',
          description:
              'PLACEHOLDER — owner wording required. A ComboRating may raise '
              'a downstream component\'s effective SCCR only when the tree '
              'shows the specified upstream device on the path, voltage '
              'limits hold, and the combo is attested.',
          status: RuleStatus.unverified,
          version: 1,
          params: {},
        ),
        const RuleRegistryEntry(
          id: RuleIds.voltageValidation,
          name: 'Voltage validation',
          description:
              'PLACEHOLDER — owner wording required. Component voltage '
              'rating vs. panel rated voltage; slash-rating applicability '
              'parameters are owner-defined. Mismatch is a blocking flag.',
          status: RuleStatus.unverified,
          version: 1,
          // TODO(owner-verify): slash-rating applicability parameters.
          params: {'slash_rating_params': null},
        ),
        const RuleRegistryEntry(
          id: RuleIds.transformerHandling,
          name: 'Transformer handling',
          description:
              'PLACEHOLDER — owner wording required. Treatment of power and '
              'control transformers. Structure and UI affordances only; math '
              'lands after the owner specifies and signs off the rule.',
          status: RuleStatus.unverified,
          version: 1,
          params: {},
        ),
        const RuleRegistryEntry(
          id: RuleIds.currentLimitingLetThrough,
          name: 'Current-limiting / let-through',
          description:
              'PLACEHOLDER — owner wording required. Data structure and '
              'display only. Any rating-elevation logic stays disabled until '
              'the owner writes the rule and signs it off (spec §3.1 rule 7).',
          status: RuleStatus.disabled,
          version: 1,
          params: {},
        ),
        const RuleRegistryEntry(
          id: RuleIds.pdbPresenceCheck,
          name: 'PDB / terminal block presence check',
          description:
              'PLACEHOLDER — owner wording required. Heuristic QUESTION flag '
              'when a circuit distributes power but records no rated '
              'distribution component — a question, never an assertion.',
          status: RuleStatus.unverified,
          version: 1,
          params: {},
        ),
      ]);
}
