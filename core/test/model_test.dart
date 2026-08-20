// Copyright (c) 2026 Code Cowboys LLC. All rights reserved.

import 'package:faultcorral_core/faultcorral_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('AttestedValue completeness (spec §0.3)', () {
    test('empty value is incomplete', () {
      expect(const AttestedValue<double>.empty().isComplete, isFalse);
    });

    test('value without citation is incomplete', () {
      final v = AttestedValue<double>(
        value: 10,
        sourceType: SourceType.marked,
        citation: '   ',
        attestation: attest(),
      );
      expect(v.isComplete, isFalse);
    });

    test('value without attestation is incomplete', () {
      const v = AttestedValue<double>(
        value: 10,
        sourceType: SourceType.marked,
        citation: 'placeholder',
      );
      expect(v.isComplete, isFalse);
    });

    test('fully attested value is complete', () {
      expect(attestedKa(10).isComplete, isTrue);
    });
  });

  group('Component UNRATED state (spec §0.3 — no silent defaults)', () {
    test('component without SCCR is UNRATED', () {
      expect(component('c1').isUnrated, isTrue);
    });

    test('component with attested SCCR is rated', () {
      expect(component('c1', sccrKa: 10).isUnrated, isFalse);
    });
  });

  group('Finalized project immutability (spec §2.2)', () {
    test('assertEditable throws on a finalized project', () {
      expect(() => project(status: ProjectStatus.finalized).assertEditable(),
          throwsStateError);
    });

    test('assertEditable passes through on a draft', () {
      expect(() => project().assertEditable(), returnsNormally);
    });
  });

  group('Audit log (spec §0.3 — append-only)', () {
    test('events list is unmodifiable', () {
      final log = AuditLog();
      log.append(AuditEvent(
        id: 'a1',
        entityType: 'component',
        entityId: 'c1',
        field: 'sccr_ka',
        oldValue: null,
        newValue: '10.0',
        userId: 'user-1',
        timestamp: t0,
      ));
      expect(() => log.events.removeAt(0), throwsUnsupportedError);
      expect(() => log.events.clear(), throwsUnsupportedError);
      expect(log.events, hasLength(1));
    });
  });

  group('SCCR vs interrupting rating are distinct fields (spec §2.2)', () {
    test('setting interrupting rating does not rate the component', () {
      final c = Component(
        meta: meta('c1'),
        circuitId: 'circ-1',
        category: ComponentCategory.circuitBreakerMccb,
        tag: 'CB1',
        powerCircuit: true,
        interruptingRatingKa: attestedKa(65),
      );
      expect(c.isUnrated, isTrue,
          reason: 'An interrupting rating must never stand in for SCCR.');
    });
  });

  group('Acknowledgment gate (spec §0.4)', () {
    const gate = AcknowledgmentGate(currentTextVersion: '0.1.0');
    final accepted = AcknowledgmentRecord(
      id: 'ack1',
      userId: 'user-1',
      textVersion: '0.1.0',
      appVersion: '0.0.1',
      acceptedAt: t0,
    );

    test('new user must acknowledge', () {
      expect(gate.needsAcknowledgment('user-1', const []), isTrue);
    });

    test('accepted current version passes the gate', () {
      expect(gate.needsAcknowledgment('user-1', [accepted]), isFalse);
    });

    test('text change re-presents to every user', () {
      const bumped = AcknowledgmentGate(currentTextVersion: '0.2.0');
      expect(bumped.needsAcknowledgment('user-1', [accepted]), isTrue);
    });

    test('acceptance is per-user, not per-shop', () {
      expect(gate.needsAcknowledgment('user-2', [accepted]), isTrue);
    });
  });

  group('Enum wire round-trips', () {
    test('all enums survive wire encoding', () {
      for (final v in SourceType.values) {
        expect(SourceType.fromWire(v.wire), v);
      }
      for (final v in ComponentCategory.values) {
        expect(ComponentCategory.fromWire(v.wire), v);
      }
      for (final v in RuleStatus.values) {
        expect(RuleStatus.fromWire(v.wire), v);
      }
      for (final v in ProjectStatus.values) {
        expect(ProjectStatus.fromWire(v.wire), v);
      }
      for (final v in CircuitKind.values) {
        expect(CircuitKind.fromWire(v.wire), v);
      }
      for (final v in FlagSeverity.values) {
        expect(FlagSeverity.fromWire(v.wire), v);
      }
      for (final v in VoltageSystem.values) {
        expect(VoltageSystem.fromWire(v.wire), v);
      }
    });
  });

  group('Registry scaffold (spec §3.1)', () {
    test('ships all eight rule slots', () {
      final registry = RulesRegistry.scaffold();
      expect(registry.entries.keys.toSet(), RuleIds.all.toSet());
    });

    test('nothing ships signed off', () {
      final registry = RulesRegistry.scaffold();
      expect(
        registry.entries.values.any((e) => e.status == RuleStatus.verified),
        isFalse,
        reason: 'Only the owner may flip a rule after checking his copy '
            'of the standard (spec §0.5).',
      );
    });

    test('let-through elevation ships disabled', () {
      final registry = RulesRegistry.scaffold();
      expect(registry[RuleIds.currentLimitingLetThrough]!.isDisabled, isTrue);
    });
  });
}
