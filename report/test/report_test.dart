// Copyright (c) 2026 Code Cowboys LLC. All rights reserved.
//
// Report tests: determinism (hashable bytes), watermark rules, footer
// framing (spec §6.4). Placeholder values only.

import 'package:crypto/crypto.dart';
import 'package:faultcorral_core/faultcorral_core.dart';
import 'package:faultcorral_report/faultcorral_report.dart';
import 'package:test/test.dart';

final t0 = DateTime.utc(2026, 1, 1);

EntityMeta meta(String id) =>
    EntityMeta(id: id, createdAt: t0, updatedAt: t0, createdBy: 'user-1');

Attestation attest() => Attestation(userId: 'user-1', timestamp: t0);

AttestedValue<double> ka(double v) => AttestedValue(
      value: v,
      sourceType: SourceType.datasheet,
      citation: 'placeholder citation',
      attestation: attest(),
    );

AttestedValue<VoltageRating> volts(double v) => AttestedValue(
      value: VoltageRating(volts: v, slashRating: false),
      sourceType: SourceType.datasheet,
      citation: 'placeholder citation',
      attestation: attest(),
    );

ProjectSnapshot snapshot({ProjectStatus status = ProjectStatus.draft}) =>
    ProjectSnapshot(
      project: Project(
        meta: meta('proj-1'),
        shopId: 'shop-1',
        name: 'Panel A',
        panelNumber: 'PNL-001',
        customer: 'Placeholder Customer',
        revision: 'A',
        status: status,
        ratedVoltages: const [
          RatedVoltage(
              volts: 480,
              system: VoltageSystem.threePhaseWye,
              slashRatingContext: false),
        ],
      ),
      circuits: [
        Circuit(
          meta: meta('circ-1'),
          projectId: 'proj-1',
          kind: CircuitKind.feeder,
          label: 'Incoming feeder',
        ),
        Circuit(
          meta: meta('circ-2'),
          projectId: 'proj-1',
          parentCircuitId: 'circ-1',
          kind: CircuitKind.branch,
          label: 'Branch 1',
        ),
      ],
      components: [
        Component(
          meta: meta('comp-1'),
          circuitId: 'circ-2',
          category: ComponentCategory.circuitBreakerMccb,
          tag: 'CB1',
          powerCircuit: true,
          manufacturer: 'PlaceholderCo',
          partNumber: 'PN-1',
          voltageRating: volts(480),
          sccrKa: ka(65),
        ),
      ],
    );

RulesRegistry signedOff() {
  var registry = RulesRegistry.scaffold();
  for (final entry in registry.entries.values) {
    if (entry.status == RuleStatus.unverified) {
      registry = registry.withEntry(entry.copyWith(
          status: RuleStatus.verified,
          verifiedBy: 'owner-1',
          verifiedDate: t0));
    }
  }
  return registry;
}

ReportInputs inputs({
  ProjectStatus status = ProjectStatus.draft,
  RulesRegistry? registry,
}) {
  final reg = registry ?? signedOff();
  final snap = snapshot(status: status);
  return ReportInputs(
    snapshot: snap,
    result: const RollupEngine().evaluate(snap, reg),
    registry: reg,
    flagAcknowledgments: const [],
    shopName: 'Placeholder Shop LLC',
    responsibleName: 'R. Person',
    responsibleTitle: 'Controls Engineer',
    generatedAt: t0,
    appVersion: '0.0.1-test',
    userNames: const {'user-1': 'R. Person'},
  );
}

void main() {
  const builder = SccrReportBuilder();

  test('identical inputs produce identical bytes (hashable, spec §4)',
      () async {
    final a = await builder.buildPdf(inputs());
    final b = await builder.buildPdf(inputs());
    expect(sha256.convert(a).toString(), sha256.convert(b).toString());
  });

  test('different inputs produce different bytes', () async {
    final a = await builder.buildPdf(inputs());
    final b = await builder.buildPdf(inputs(status: ProjectStatus.finalized));
    expect(sha256.convert(a).toString(), isNot(sha256.convert(b).toString()));
  });

  test('produces a plausible PDF', () async {
    final bytes = await builder.buildPdf(inputs());
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(bytes.length, greaterThan(1000));
  });

  group('Watermark rules (spec §6.4, §0.5)', () {
    test('non-finalized project is DRAFT', () {
      expect(watermarksFor(inputs()), contains('DRAFT'));
    });

    test('unverified-rule results carry the NOT FOR USE watermark', () {
      final marks = watermarksFor(inputs(registry: RulesRegistry.scaffold()));
      expect(marks, contains('CONTAINS UNVERIFIED RULES - NOT FOR USE'));
    });

    test('finalized project with signed-off rules has no watermark', () {
      expect(watermarksFor(inputs(status: ProjectStatus.finalized)), isEmpty);
    });
  });

  group('Footer framing (spec §6.4)', () {
    test('placeholder disclaimer + attribution always present', () {
      final lines = footerLinesFor(inputs());
      expect(lines.first, disclaimerPlaceholder);
      expect(lines.last, attributionLine);
    });

    test('shop addendum adds to the block, never replaces it', () {
      final snap = snapshot();
      final reg = signedOff();
      final withAddendum = ReportInputs(
        snapshot: snap,
        result: const RollupEngine().evaluate(snap, reg),
        registry: reg,
        flagAcknowledgments: const [],
        shopName: 'Placeholder Shop LLC',
        responsibleName: 'R. Person',
        responsibleTitle: 'Controls Engineer',
        generatedAt: t0,
        appVersion: '0.0.1-test',
        legalFooterAddendum: 'Shop addendum text.',
      );
      final lines = footerLinesFor(withAddendum);
      expect(lines, contains('Shop addendum text.'));
      expect(lines.first, disclaimerPlaceholder);
      expect(lines.last, attributionLine);
    });
  });

  test('circuit paths reflect the tree', () {
    final paths = circuitPaths(snapshot());
    expect(paths['circ-2'], 'Incoming feeder > Branch 1');
  });
}
