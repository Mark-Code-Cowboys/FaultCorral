// Copyright (c) 2026 Code Cowboys LLC. All rights reserved.
//
// Store behavior tests against an in-memory SQLite database. All numeric
// values are arbitrary placeholders, not domain data.

import 'package:faultcorral_core/faultcorral_core.dart';
import 'package:faultcorral_store/faultcorral_store.dart';
import 'package:sqlite3/sqlite3.dart' show SqliteException;
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

Project project({String id = 'proj-1'}) => Project(
      meta: meta(id),
      shopId: 'shop-1',
      name: 'Panel A',
      status: ProjectStatus.draft,
      ratedVoltages: const [
        RatedVoltage(
            volts: 480,
            system: VoltageSystem.threePhaseWye,
            slashRatingContext: false),
      ],
    );

Circuit circuit({String id = 'circ-1', String? parent}) => Circuit(
      meta: meta(id),
      projectId: 'proj-1',
      parentCircuitId: parent,
      kind: parent == null ? CircuitKind.feeder : CircuitKind.branch,
      label: 'Circuit $id',
    );

Component component(String id,
        {double? sccr = 65, String circuitId = 'circ-1'}) =>
    Component(
      meta: meta(id),
      circuitId: circuitId,
      category: ComponentCategory.circuitBreakerMccb,
      tag: 'TAG-$id',
      powerCircuit: true,
      voltageRating: volts(480),
      sccrKa: sccr == null ? const AttestedValue<double>.empty() : ka(sccr),
    );

void main() {
  late FaultCorralDatabase database;
  late FaultCorralStore store;

  setUp(() {
    database = FaultCorralDatabase.memory();
    store = FaultCorralStore(database);
  });
  tearDown(() => store.dispose());

  void seedProject() {
    store.saveProject(project(), by: 'user-1', at: t0);
    store.saveCircuit(circuit(), by: 'user-1', at: t0);
    store.saveComponent(component('comp-1'),
        projectId: 'proj-1', by: 'user-1', at: t0);
  }

  RulesRegistry signedOffRegistry() {
    var registry = store.registryForShop('shop-1', by: 'owner-1', at: t0);
    for (final entry in registry.entries.values) {
      if (entry.status == RuleStatus.unverified) {
        final updated = entry.copyWith(
          status: RuleStatus.verified,
          verifiedBy: 'owner-1',
          verifiedDate: t0,
        );
        store.saveRegistryEntry('shop-1', updated, by: 'owner-1', at: t0);
        registry = registry.withEntry(updated);
      }
    }
    return registry;
  }

  group('CRUD round-trips', () {
    test('project, circuit, component survive storage', () {
      seedProject();
      expect(store.getProject('proj-1')!.name, 'Panel A');
      expect(store.circuitsForProject('proj-1'), hasLength(1));
      final loaded = store.componentsForProject('proj-1').single;
      expect(loaded.sccrKa.value, 65);
      expect(loaded.sccrKa.isComplete, isTrue);
    });

    test('snapshot loads everything', () {
      seedProject();
      final snap = store.loadSnapshot('proj-1');
      expect(snap.project.meta.id, 'proj-1');
      expect(snap.components, hasLength(1));
    });
  });

  group('Audit trail (spec §0.3)', () {
    test('creates and edits produce field-level events', () {
      seedProject();
      final edited = Component(
        meta: meta('comp-1'),
        circuitId: 'circ-1',
        category: ComponentCategory.circuitBreakerMccb,
        tag: 'TAG-comp-1',
        powerCircuit: true,
        voltageRating: volts(480),
        sccrKa: ka(100),
      );
      store.saveComponent(edited, projectId: 'proj-1', by: 'user-2', at: t0);
      final events = store.auditForProject('proj-1');
      final sccrEdit = events.where((e) => e.field == 'sccr_ka').single;
      expect(sccrEdit.userId, 'user-2');
      expect(sccrEdit.oldValue, contains('65'));
      expect(sccrEdit.newValue, contains('100'));
    });

    test('audit rows cannot be updated or deleted (DB triggers)', () {
      seedProject();
      final id = store.auditForProject('proj-1').first.id;
      expect(
        () => database.db.execute(
            'UPDATE audit_events SET json = ? WHERE id = ?', ['{}', id]),
        throwsA(isA<SqliteException>()),
      );
      expect(
        () =>
            database.db.execute('DELETE FROM audit_events WHERE id = ?', [id]),
        throwsA(isA<SqliteException>()),
      );
    });
  });

  group('Finalized immutability (spec §2.2)', () {
    test('finalize freezes; edits then refuse', () {
      seedProject();
      signedOffRegistry();
      final frozen = store.finalizeProject(
        projectId: 'proj-1',
        by: 'user-1',
        at: t0,
        acceptedAcknowledgmentTextVersion: '0.1.0-draft',
        appVersion: '0.0.1-test',
      );
      expect(frozen.sha256Hex, hasLength(64));
      expect(store.getProject('proj-1')!.status, ProjectStatus.finalized);
      expect(
          store.getProject('proj-1')!.finalizedSnapshotRef, frozen.sha256Hex);
      expect(
        store
            .finalizedSnapshot('proj-1', frozen.sha256Hex)!
            .exportJson
            .isNotEmpty,
        isTrue,
      );

      expect(
        () => store.saveComponent(component('comp-2'),
            projectId: 'proj-1', by: 'user-1', at: t0),
        throwsStateError,
      );
      expect(() => store.saveProject(project(), by: 'user-1', at: t0),
          throwsStateError);
      expect(() => store.deleteCircuit('circ-1', by: 'user-1', at: t0),
          throwsStateError);
    });

    test('finalize refuses UNRATED components', () {
      store.saveProject(project(), by: 'user-1', at: t0);
      store.saveCircuit(circuit(), by: 'user-1', at: t0);
      store.saveComponent(component('comp-1', sccr: null),
          projectId: 'proj-1', by: 'user-1', at: t0);
      signedOffRegistry();
      expect(
        () => store.finalizeProject(
          projectId: 'proj-1',
          by: 'user-1',
          at: t0,
          acceptedAcknowledgmentTextVersion: '0.1.0-draft',
          appVersion: '0.0.1-test',
        ),
        throwsA(isA<FinalizationBlocked>()),
      );
      // Nothing was written: project still draft, no snapshot rows.
      expect(store.getProject('proj-1')!.status, ProjectStatus.draft);
    });

    test('direct status write to finalized is refused', () {
      seedProject();
      final sneaky = Project(
        meta: meta('proj-1'),
        shopId: 'shop-1',
        name: 'Panel A',
        status: ProjectStatus.finalized,
        ratedVoltages: project().ratedVoltages,
      );
      expect(() => store.saveProject(sneaky, by: 'user-1', at: t0),
          throwsStateError);
    });
  });

  group('Library version pinning (spec §2.2)', () {
    LibraryItem item(int version, {double sccr = 65}) => LibraryItem(
          meta: meta('lib-1'),
          shopId: 'shop-1',
          manufacturer: 'PlaceholderCo',
          partNumber: 'PN-1',
          category: ComponentCategory.circuitBreakerMccb,
          version: version,
          defaultSccrKa: ka(sccr),
        );

    test('same (id, version) with different content is refused', () {
      store.saveLibraryItem(item(1), by: 'user-1', at: t0);
      expect(
          () => store.saveLibraryItem(item(1, sccr: 100), by: 'user-1', at: t0),
          throwsStateError);
    });

    test('new versions coexist; pinned lookups return the old one', () {
      store.saveLibraryItem(item(1), by: 'user-1', at: t0);
      store.saveLibraryItem(item(2, sccr: 100), by: 'user-1', at: t0);
      expect(
          store.getLibraryItem('lib-1', version: 1)!.defaultSccrKa.value, 65);
      expect(store.getLibraryItem('lib-1')!.version, 2);
      expect(store.libraryForShop('shop-1').single.version, 2);
    });

    test('soft delete hides from library but keeps pinned versions', () {
      store.saveLibraryItem(item(1), by: 'user-1', at: t0);
      store.saveLibraryItem(
        LibraryItem(
          meta: meta('lib-1'),
          shopId: 'shop-1',
          manufacturer: 'PlaceholderCo',
          partNumber: 'PN-1',
          category: ComponentCategory.circuitBreakerMccb,
          version: 2,
          defaultSccrKa: ka(65),
          deleted: true,
        ),
        by: 'user-1',
        at: t0,
      );
      expect(store.libraryForShop('shop-1'), isEmpty);
      expect(store.getLibraryItem('lib-1', version: 1), isNotNull);
    });
  });

  group('Registry per shop', () {
    test('first load seeds the scaffold', () {
      final registry = store.registryForShop('shop-1', by: 'owner-1', at: t0);
      expect(registry.entries.keys.toSet(), RuleIds.all.toSet());
    });

    test('entry edits persist', () {
      signedOffRegistry();
      final reloaded = store.registryForShop('shop-1', by: 'owner-1', at: t0);
      expect(
        reloaded.entries.values
            .where((e) => e.status == RuleStatus.verified)
            .length,
        greaterThan(0),
      );
    });
  });

  group('Acknowledgments (spec §0.4)', () {
    test('gate opens only after current text version accepted', () {
      expect(store.needsAcknowledgment('user-1', '0.1.0-draft'), isTrue);
      store.recordAcknowledgment(
        AcknowledgmentRecord(
          id: 'ack-1',
          userId: 'user-1',
          textVersion: '0.1.0-draft',
          appVersion: '0.0.1-test',
          acceptedAt: t0,
        ),
        at: t0,
      );
      expect(store.needsAcknowledgment('user-1', '0.1.0-draft'), isFalse);
      expect(store.needsAcknowledgment('user-1', '0.2.0'), isTrue);
      expect(store.needsAcknowledgment('user-2', '0.1.0-draft'), isTrue);
    });
  });

  group('Circuit tree deletion', () {
    test('cascades to descendants and their components, audited', () {
      seedProject();
      store.saveCircuit(circuit(id: 'circ-2', parent: 'circ-1'),
          by: 'user-1', at: t0);
      store.saveComponent(component('comp-2', circuitId: 'circ-2'),
          projectId: 'proj-1', by: 'user-1', at: t0);
      store.deleteCircuit('circ-1', by: 'user-1', at: t0);
      expect(store.circuitsForProject('proj-1'), isEmpty);
      expect(store.componentsForProject('proj-1'), isEmpty);
      final deletions = store
          .auditForProject('proj-1')
          .where((e) => e.newValue == 'deleted')
          .toList();
      expect(deletions.length, greaterThanOrEqualTo(2));
    });
  });

  group('Export / import (spec §4, §8)', () {
    test('round-trips a project into a fresh store', () {
      seedProject();
      final file =
          store.exportProject('proj-1', by: 'user-1', appVersion: 'test');
      final second = FaultCorralStore(FaultCorralDatabase.memory());
      addTearDown(second.dispose);
      final id = second.importProject(file, by: 'user-2', at: t0);
      expect(id, 'proj-1');
      expect(second.componentsForProject('proj-1'), hasLength(1));
    });

    test('import refuses to overwrite an existing project', () {
      seedProject();
      final file =
          store.exportProject('proj-1', by: 'user-1', appVersion: 'test');
      expect(() => store.importProject(file, by: 'user-1', at: t0),
          throwsStateError);
    });
  });
}
