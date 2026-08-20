// Copyright (c) 2026 Code Cowboys LLC. All rights reserved.
//
// Test fixture builders. All numeric values in tests are ARBITRARY
// PLACEHOLDERS for exercising engine mechanics — they are not domain data
// and assert nothing about any real device or standard (spec §0.5).

import 'package:faultcorral_core/faultcorral_core.dart';

final t0 = DateTime.utc(2026, 1, 1);

EntityMeta meta(String id) =>
    EntityMeta(id: id, createdAt: t0, updatedAt: t0, createdBy: 'user-1');

Attestation attest() => Attestation(userId: 'user-1', timestamp: t0);

AttestedValue<double> attestedKa(double ka,
        {SourceType source = SourceType.datasheet}) =>
    AttestedValue(
      value: ka,
      sourceType: source,
      citation: 'placeholder citation, test fixture',
      attestation: attest(),
    );

AttestedValue<VoltageRating> attestedVolts(double volts) => AttestedValue(
      value: VoltageRating(volts: volts, slashRating: false),
      sourceType: SourceType.datasheet,
      citation: 'placeholder citation, test fixture',
      attestation: attest(),
    );

Project project({ProjectStatus status = ProjectStatus.draft}) => Project(
      meta: meta('proj-1'),
      shopId: 'shop-1',
      name: 'Test Panel',
      status: status,
      ratedVoltages: const [
        RatedVoltage(
            volts: 480,
            system: VoltageSystem.threePhaseWye,
            slashRatingContext: false),
      ],
    );

Circuit feeder({String id = 'circ-1'}) => Circuit(
      meta: meta(id),
      projectId: 'proj-1',
      kind: CircuitKind.feeder,
      label: 'Incoming feeder',
    );

Component component(
  String id, {
  double? sccrKa,
  bool powerCircuit = true,
  String circuitId = 'circ-1',
  SourceType source = SourceType.datasheet,
  List<String> comboRatingIds = const [],
}) =>
    Component(
      meta: meta(id),
      circuitId: circuitId,
      category: ComponentCategory.circuitBreakerMccb,
      tag: 'TAG-$id',
      powerCircuit: powerCircuit,
      voltageRating: attestedVolts(480),
      sccrKa: sccrKa == null
          ? const AttestedValue<double>.empty()
          : attestedKa(sccrKa, source: source),
      comboRatingIds: comboRatingIds,
    );

ProjectSnapshot snapshot(List<Component> components,
        {ProjectStatus status = ProjectStatus.draft}) =>
    ProjectSnapshot(
      project: project(status: status),
      circuits: [feeder()],
      components: components,
    );

/// Registry scaffold with every entry flipped for tests that need the
/// finalization gate open. Marker fields are synthetic test data.
RulesRegistry allSignedOffRegistry() {
  var registry = RulesRegistry.scaffold();
  for (final entry in registry.entries.values) {
    if (entry.status == RuleStatus.unverified) {
      registry = registry.withEntry(entry.copyWith(
        status: RuleStatus.verified,
        verifiedBy: 'owner-1',
        verifiedDate: t0,
      ));
    }
  }
  return registry;
}
