// Copyright (c) 2026 Code Cowboys LLC. All rights reserved.

import 'dart:convert';

import 'package:faultcorral_core/faultcorral_core.dart';
import 'package:sqlite3/sqlite3.dart';

import 'database.dart';

/// Typed repository facade over [FaultCorralDatabase].
///
/// Every mutation runs in a transaction and appends field-level audit events
/// (spec §0.3: who, what, when, old → new). Mutations against a finalized
/// project are refused (spec §2.2). The `by` argument attributes the change;
/// `at` exists so tests are deterministic and defaults to now.
class FaultCorralStore {
  FaultCorralStore(this._database);

  final FaultCorralDatabase _database;

  Database get _db => _database.db;

  int _auditSeq = 0;

  void dispose() => _database.dispose();

  // --- helpers ---------------------------------------------------------

  Map<String, Object?> _decode(String json) =>
      (jsonDecode(json) as Map).cast<String, Object?>();

  String? _selectJson(String sql, List<Object?> params) {
    final rows = _db.select(sql, params);
    return rows.isEmpty ? null : rows.first['json'] as String;
  }

  DateTime _at(DateTime? at) => (at ?? DateTime.now()).toUtc();

  void _appendAudit({
    required String entityType,
    required Id entityId,
    Id? projectId,
    required String field,
    String? oldValue,
    String? newValue,
    required Id by,
    required DateTime at,
  }) {
    final event = AuditEvent(
      id: 'evt-${at.microsecondsSinceEpoch}-${_auditSeq++}',
      projectId: projectId,
      entityType: entityType,
      entityId: entityId,
      field: field,
      oldValue: oldValue,
      newValue: newValue,
      userId: by,
      timestamp: at,
    );
    _db.execute(
      'INSERT INTO audit_events (id, project_id, json) VALUES (?, ?, ?)',
      [event.id, projectId, jsonEncode(event.toJson())],
    );
  }

  /// Appends one audit event per changed top-level field.
  void _auditDiff({
    required String entityType,
    required Id entityId,
    Id? projectId,
    required Map<String, Object?>? oldJson,
    required Map<String, Object?>? newJson,
    required Id by,
    required DateTime at,
  }) {
    if (oldJson == null) {
      _appendAudit(
        entityType: entityType,
        entityId: entityId,
        projectId: projectId,
        field: '*',
        oldValue: null,
        newValue: 'created',
        by: by,
        at: at,
      );
      return;
    }
    if (newJson == null) {
      _appendAudit(
        entityType: entityType,
        entityId: entityId,
        projectId: projectId,
        field: '*',
        oldValue: 'exists',
        newValue: 'deleted',
        by: by,
        at: at,
      );
      return;
    }
    final keys = {...oldJson.keys, ...newJson.keys}..remove('updated_at');
    for (final key in keys) {
      final oldValue = jsonEncode(oldJson[key]);
      final newValue = jsonEncode(newJson[key]);
      if (oldValue != newValue) {
        _appendAudit(
          entityType: entityType,
          entityId: entityId,
          projectId: projectId,
          field: key,
          oldValue: oldValue,
          newValue: newValue,
          by: by,
          at: at,
        );
      }
    }
  }

  void _assertProjectEditable(Id projectId) {
    final project = getProject(projectId);
    if (project == null) {
      throw StateError('Project $projectId does not exist.');
    }
    project.assertEditable();
  }

  // --- shops & users ---------------------------------------------------

  void saveShop(Shop shop, {required Id by, DateTime? at}) {
    final now = _at(at);
    _database.transaction(() {
      final old = _selectJson('SELECT json FROM shops WHERE id = ?', [
        shop.meta.id,
      ]);
      final json = jsonEncode(shop.toJson());
      _db.execute(
        'INSERT INTO shops (id, json, updated_at) VALUES (?, ?, ?) '
        'ON CONFLICT(id) DO UPDATE SET json = ?, updated_at = ?',
        [
          shop.meta.id,
          json,
          now.toIso8601String(),
          json,
          now.toIso8601String()
        ],
      );
      _auditDiff(
        entityType: 'shop',
        entityId: shop.meta.id,
        oldJson: old == null ? null : _decode(old),
        newJson: shop.toJson(),
        by: by,
        at: now,
      );
    });
  }

  Shop? getShop(Id id) {
    final json = _selectJson('SELECT json FROM shops WHERE id = ?', [id]);
    return json == null ? null : Shop.fromJson(_decode(json));
  }

  void saveUser(User user, {required Id by, DateTime? at}) {
    final now = _at(at);
    _database.transaction(() {
      final old = _selectJson('SELECT json FROM users WHERE id = ?', [
        user.meta.id,
      ]);
      final json = jsonEncode(user.toJson());
      _db.execute(
        'INSERT INTO users (id, shop_id, json) VALUES (?, ?, ?) '
        'ON CONFLICT(id) DO UPDATE SET shop_id = ?, json = ?',
        [user.meta.id, user.shopId, json, user.shopId, json],
      );
      _auditDiff(
        entityType: 'user',
        entityId: user.meta.id,
        oldJson: old == null ? null : _decode(old),
        newJson: user.toJson(),
        by: by,
        at: now,
      );
    });
  }

  User? getUser(Id id) {
    final json = _selectJson('SELECT json FROM users WHERE id = ?', [id]);
    return json == null ? null : User.fromJson(_decode(json));
  }

  // --- projects --------------------------------------------------------

  /// Creates or updates a project. Updating a finalized project throws;
  /// the only allowed transition onto `finalized` is [finalizeProject].
  void saveProject(Project project, {required Id by, DateTime? at}) {
    final now = _at(at);
    _database.transaction(() {
      final old = _selectJson('SELECT json FROM projects WHERE id = ?', [
        project.meta.id,
      ]);
      if (old != null) {
        Project.fromJson(_decode(old)).assertEditable();
        if (project.status == ProjectStatus.finalized) {
          throw StateError(
              'Use finalizeProject to finalize; direct status writes are '
              'not allowed.');
        }
      }
      _writeProjectRow(project, now);
      _auditDiff(
        entityType: 'project',
        entityId: project.meta.id,
        projectId: project.meta.id,
        oldJson: old == null ? null : _decode(old),
        newJson: project.toJson(),
        by: by,
        at: now,
      );
    });
  }

  void _writeProjectRow(Project project, DateTime now) {
    final json = jsonEncode(project.toJson());
    _db.execute(
      'INSERT INTO projects (id, shop_id, status, json, updated_at) '
      'VALUES (?, ?, ?, ?, ?) '
      'ON CONFLICT(id) DO UPDATE SET status = ?, json = ?, updated_at = ?',
      [
        project.meta.id,
        project.shopId,
        project.status.wire,
        json,
        now.toIso8601String(),
        project.status.wire,
        json,
        now.toIso8601String(),
      ],
    );
  }

  Project? getProject(Id id) {
    final json = _selectJson('SELECT json FROM projects WHERE id = ?', [id]);
    return json == null ? null : Project.fromJson(_decode(json));
  }

  List<Project> projectsForShop(Id shopId) => _db
      .select(
          'SELECT json FROM projects WHERE shop_id = ? ORDER BY updated_at DESC',
          [shopId])
      .map((row) => Project.fromJson(_decode(row['json'] as String)))
      .toList();

  // --- circuits & components -------------------------------------------

  void saveCircuit(Circuit circuit, {required Id by, DateTime? at}) {
    final now = _at(at);
    _database.transaction(() {
      _assertProjectEditable(circuit.projectId);
      final old = _selectJson('SELECT json FROM circuits WHERE id = ?', [
        circuit.meta.id,
      ]);
      final json = jsonEncode(circuit.toJson());
      _db.execute(
        'INSERT INTO circuits (id, project_id, parent_circuit_id, json) '
        'VALUES (?, ?, ?, ?) '
        'ON CONFLICT(id) DO UPDATE SET parent_circuit_id = ?, json = ?',
        [
          circuit.meta.id,
          circuit.projectId,
          circuit.parentCircuitId,
          json,
          circuit.parentCircuitId,
          json,
        ],
      );
      _auditDiff(
        entityType: 'circuit',
        entityId: circuit.meta.id,
        projectId: circuit.projectId,
        oldJson: old == null ? null : _decode(old),
        newJson: circuit.toJson(),
        by: by,
        at: now,
      );
    });
  }

  /// Deletes a circuit, its descendant circuits, and every component on
  /// them. Each removal is audited.
  void deleteCircuit(Id circuitId, {required Id by, DateTime? at}) {
    final now = _at(at);
    _database.transaction(() {
      final json = _selectJson('SELECT json FROM circuits WHERE id = ?', [
        circuitId,
      ]);
      if (json == null) return;
      final circuit = Circuit.fromJson(_decode(json));
      _assertProjectEditable(circuit.projectId);

      final all = circuitsForProject(circuit.projectId);
      final doomed = <Id>{circuitId};
      var grew = true;
      while (grew) {
        grew = false;
        for (final c in all) {
          if (doomed.contains(c.parentCircuitId) && doomed.add(c.meta.id)) {
            grew = true;
          }
        }
      }
      for (final id in doomed.toList()..sort()) {
        for (final component in componentsForCircuit(id)) {
          _deleteComponentRow(component, by: by, at: now);
        }
        _db.execute('DELETE FROM circuits WHERE id = ?', [id]);
        _auditDiff(
          entityType: 'circuit',
          entityId: id,
          projectId: circuit.projectId,
          oldJson: const {'': ''},
          newJson: null,
          by: by,
          at: now,
        );
      }
    });
  }

  List<Circuit> circuitsForProject(Id projectId) => _db
      .select('SELECT json FROM circuits WHERE project_id = ? ORDER BY id',
          [projectId])
      .map((row) => Circuit.fromJson(_decode(row['json'] as String)))
      .toList();

  void saveComponent(Component component,
      {required Id projectId, required Id by, DateTime? at}) {
    final now = _at(at);
    _database.transaction(() {
      _assertProjectEditable(projectId);
      final old = _selectJson('SELECT json FROM components WHERE id = ?', [
        component.meta.id,
      ]);
      final json = jsonEncode(component.toJson());
      _db.execute(
        'INSERT INTO components (id, project_id, circuit_id, json) '
        'VALUES (?, ?, ?, ?) '
        'ON CONFLICT(id) DO UPDATE SET circuit_id = ?, json = ?',
        [
          component.meta.id,
          projectId,
          component.circuitId,
          json,
          component.circuitId,
          json,
        ],
      );
      _auditDiff(
        entityType: 'component',
        entityId: component.meta.id,
        projectId: projectId,
        oldJson: old == null ? null : _decode(old),
        newJson: component.toJson(),
        by: by,
        at: now,
      );
    });
  }

  void _deleteComponentRow(Component component,
      {required Id by, required DateTime at}) {
    final projectId = _db.select(
        'SELECT project_id FROM components WHERE id = ?',
        [component.meta.id]).first['project_id'] as String;
    _db.execute('DELETE FROM components WHERE id = ?', [component.meta.id]);
    _auditDiff(
      entityType: 'component',
      entityId: component.meta.id,
      projectId: projectId,
      oldJson: component.toJson(),
      newJson: null,
      by: by,
      at: at,
    );
  }

  void deleteComponent(Id componentId, {required Id by, DateTime? at}) {
    final now = _at(at);
    _database.transaction(() {
      final rows = _db.select(
          'SELECT project_id, json FROM components WHERE id = ?',
          [componentId]);
      if (rows.isEmpty) return;
      _assertProjectEditable(rows.first['project_id'] as String);
      _deleteComponentRow(
        Component.fromJson(_decode(rows.first['json'] as String)),
        by: by,
        at: now,
      );
    });
  }

  List<Component> componentsForProject(Id projectId) => _db
      .select('SELECT json FROM components WHERE project_id = ? ORDER BY id',
          [projectId])
      .map((row) => Component.fromJson(_decode(row['json'] as String)))
      .toList();

  List<Component> componentsForCircuit(Id circuitId) => _db
      .select('SELECT json FROM components WHERE circuit_id = ? ORDER BY id',
          [circuitId])
      .map((row) => Component.fromJson(_decode(row['json'] as String)))
      .toList();

  // --- shop library (version-pinned, spec §2.2) -------------------------

  /// Inserts a library item version. Rows are immutable: re-saving an
  /// existing (id, version) with different content throws — bump the
  /// version instead. Historical projects keep the version they pinned.
  void saveLibraryItem(LibraryItem item, {required Id by, DateTime? at}) {
    final now = _at(at);
    _database.transaction(() {
      final existing = _selectJson(
        'SELECT json FROM library_items WHERE id = ? AND version = ?',
        [item.meta.id, item.version],
      );
      final json = jsonEncode(item.toJson());
      if (existing != null) {
        if (existing == json) return; // idempotent re-save
        throw StateError(
            'Library item ${item.meta.id} v${item.version} already exists '
            'and is immutable; save a new version.');
      }
      _db.execute(
        'INSERT INTO library_items (id, version, shop_id, json) '
        'VALUES (?, ?, ?, ?)',
        [item.meta.id, item.version, item.shopId, json],
      );
      _auditDiff(
        entityType: 'library_item',
        entityId: '${item.meta.id}@v${item.version}',
        oldJson: null,
        newJson: item.toJson(),
        by: by,
        at: now,
      );
    });
  }

  LibraryItem? getLibraryItem(Id id, {int? version}) {
    final json = version != null
        ? _selectJson(
            'SELECT json FROM library_items WHERE id = ? AND version = ?',
            [id, version])
        : _selectJson(
            'SELECT json FROM library_items WHERE id = ? '
            'ORDER BY version DESC LIMIT 1',
            [id]);
    return json == null ? null : LibraryItem.fromJson(_decode(json));
  }

  /// Latest version of each non-deleted item in the shop's library.
  List<LibraryItem> libraryForShop(Id shopId) {
    final rows = _db.select(
      'SELECT json FROM library_items li WHERE shop_id = ? AND version = '
      '(SELECT MAX(version) FROM library_items WHERE id = li.id) '
      'ORDER BY id',
      [shopId],
    );
    return rows
        .map((row) => LibraryItem.fromJson(_decode(row['json'] as String)))
        .where((item) => !item.deleted)
        .toList();
  }

  // --- combo ratings ----------------------------------------------------

  void saveComboRating(ComboRating combo, {required Id by, DateTime? at}) {
    final now = _at(at);
    _database.transaction(() {
      final old = _selectJson('SELECT json FROM combo_ratings WHERE id = ?', [
        combo.meta.id,
      ]);
      final json = jsonEncode(combo.toJson());
      _db.execute(
        'INSERT INTO combo_ratings (id, shop_id, json) VALUES (?, ?, ?) '
        'ON CONFLICT(id) DO UPDATE SET json = ?',
        [combo.meta.id, combo.shopId, json, json],
      );
      _auditDiff(
        entityType: 'combo_rating',
        entityId: combo.meta.id,
        oldJson: old == null ? null : _decode(old),
        newJson: combo.toJson(),
        by: by,
        at: now,
      );
    });
  }

  List<ComboRating> combosForShop(Id shopId) => _db
      .select('SELECT json FROM combo_ratings WHERE shop_id = ? ORDER BY id',
          [shopId])
      .map((row) => ComboRating.fromJson(_decode(row['json'] as String)))
      .toList();

  // --- rules registry ----------------------------------------------------

  /// Loads the shop's registry, seeding the shipped scaffold on first use.
  RulesRegistry registryForShop(Id shopId, {required Id by, DateTime? at}) {
    final rows = _db.select(
        'SELECT json FROM registry_entries WHERE shop_id = ? ORDER BY rule_id',
        [shopId]);
    if (rows.isNotEmpty) {
      return RulesRegistry(rows.map(
          (row) => RuleRegistryEntry.fromJson(_decode(row['json'] as String))));
    }
    final scaffold = RulesRegistry.scaffold();
    final now = _at(at);
    _database.transaction(() {
      for (final entry in scaffold.entries.values) {
        _db.execute(
          'INSERT INTO registry_entries (shop_id, rule_id, json) '
          'VALUES (?, ?, ?)',
          [shopId, entry.id, jsonEncode(entry.toJson())],
        );
      }
      _appendAudit(
        entityType: 'registry',
        entityId: shopId,
        field: '*',
        oldValue: null,
        newValue: 'seeded scaffold',
        by: by,
        at: now,
      );
    });
    return scaffold;
  }

  void saveRegistryEntry(Id shopId, RuleRegistryEntry entry,
      {required Id by, DateTime? at}) {
    final now = _at(at);
    _database.transaction(() {
      final old = _selectJson(
        'SELECT json FROM registry_entries WHERE shop_id = ? AND rule_id = ?',
        [shopId, entry.id],
      );
      final json = jsonEncode(entry.toJson());
      _db.execute(
        'INSERT INTO registry_entries (shop_id, rule_id, json) '
        'VALUES (?, ?, ?) ON CONFLICT(shop_id, rule_id) DO UPDATE SET json = ?',
        [shopId, entry.id, json, json],
      );
      _auditDiff(
        entityType: 'registry_entry',
        entityId: entry.id,
        oldJson: old == null ? null : _decode(old),
        newJson: entry.toJson(),
        by: by,
        at: now,
      );
    });
  }

  // --- acknowledgments (spec §0.4) ---------------------------------------

  void recordAcknowledgment(AcknowledgmentRecord record, {DateTime? at}) {
    final now = _at(at);
    _database.transaction(() {
      _db.execute(
        'INSERT INTO acknowledgments (id, user_id, text_version, json) '
        'VALUES (?, ?, ?, ?)',
        [
          record.id,
          record.userId,
          record.textVersion,
          jsonEncode(record.toJson()),
        ],
      );
      _appendAudit(
        entityType: 'acknowledgment',
        entityId: record.id,
        field: 'text_version',
        oldValue: null,
        newValue: record.textVersion,
        by: record.userId,
        at: now,
      );
    });
  }

  List<AcknowledgmentRecord> acknowledgmentsForUser(Id userId) => _db
      .select('SELECT json FROM acknowledgments WHERE user_id = ? ORDER BY id',
          [userId])
      .map((row) =>
          AcknowledgmentRecord.fromJson(_decode(row['json'] as String)))
      .toList();

  bool needsAcknowledgment(Id userId, String currentTextVersion) =>
      AcknowledgmentGate(currentTextVersion: currentTextVersion)
          .needsAcknowledgment(userId, acknowledgmentsForUser(userId));

  // --- flag acknowledgments (WARNING resolutions, spec §3.1) -------------

  void saveFlagAcknowledgment(FlagAcknowledgment ack,
      {required Id by, DateTime? at}) {
    final now = _at(at);
    _database.transaction(() {
      _assertProjectEditable(ack.projectId);
      final json = jsonEncode(ack.toJson());
      _db.execute(
        'INSERT INTO flag_acknowledgments (project_id, flag_key, json) '
        'VALUES (?, ?, ?) '
        'ON CONFLICT(project_id, flag_key) DO UPDATE SET json = ?',
        [ack.projectId, ack.flagKey, json, json],
      );
      _appendAudit(
        entityType: 'flag_acknowledgment',
        entityId: ack.flagKey,
        projectId: ack.projectId,
        field: 'note',
        oldValue: null,
        newValue: ack.note,
        by: by,
        at: now,
      );
    });
  }

  List<FlagAcknowledgment> flagAcksForProject(Id projectId) => _db
      .select(
          'SELECT json FROM flag_acknowledgments WHERE project_id = ? '
          'ORDER BY flag_key',
          [projectId])
      .map((row) => FlagAcknowledgment.fromJson(_decode(row['json'] as String)))
      .toList();

  // --- audit -------------------------------------------------------------

  List<AuditEvent> auditForProject(Id projectId) => _db
      .select('SELECT json FROM audit_events WHERE project_id = ? ORDER BY id',
          [projectId])
      .map((row) => AuditEvent.fromJson(_decode(row['json'] as String)))
      .toList();

  // --- snapshots, finalization, export ------------------------------------

  ProjectSnapshot loadSnapshot(Id projectId) {
    final project = getProject(projectId);
    if (project == null) {
      throw StateError('Project $projectId does not exist.');
    }
    return ProjectSnapshot(
      project: project,
      circuits: circuitsForProject(projectId),
      components: componentsForProject(projectId),
      comboRatings: combosForShop(project.shopId),
    );
  }

  /// Finalizes a project (spec §2.1): runs the core [FinalizationService]
  /// gate, stores the immutable snapshot, and flips the project status —
  /// all in one transaction.
  FinalizedSnapshot finalizeProject({
    required Id projectId,
    required Id by,
    DateTime? at,
    required String acceptedAcknowledgmentTextVersion,
    required String appVersion,
  }) {
    final now = _at(at);
    return _database.transaction(() {
      final snapshot = loadSnapshot(projectId);
      final registry = registryForShop(snapshot.project.shopId, by: by);
      final frozen = const FinalizationService().finalize(
        snapshot: snapshot,
        registry: registry,
        warningAcknowledgments: flagAcksForProject(projectId),
        finalizedBy: by,
        finalizedAt: now,
        acceptedAcknowledgmentTextVersion: acceptedAcknowledgmentTextVersion,
        appVersion: appVersion,
      );
      _db.execute(
        'INSERT INTO finalized_snapshots (project_id, sha256_hex, json) '
        'VALUES (?, ?, ?)',
        [projectId, frozen.sha256Hex, jsonEncode(frozen.toJson())],
      );
      final old = snapshot.project;
      final finalized = Project(
        meta: EntityMeta(
          id: old.meta.id,
          createdAt: old.meta.createdAt,
          updatedAt: now,
          createdBy: old.meta.createdBy,
        ),
        shopId: old.shopId,
        name: old.name,
        customer: old.customer,
        panelNumber: old.panelNumber,
        revision: old.revision,
        ratedVoltages: old.ratedVoltages,
        phases: old.phases,
        frequencyHz: old.frequencyHz,
        enclosureRef: old.enclosureRef,
        status: ProjectStatus.finalized,
        finalizedSnapshotRef: frozen.sha256Hex,
      );
      _writeProjectRow(finalized, now);
      _auditDiff(
        entityType: 'project',
        entityId: projectId,
        projectId: projectId,
        oldJson: old.toJson(),
        newJson: finalized.toJson(),
        by: by,
        at: now,
      );
      return frozen;
    });
  }

  FinalizedSnapshot? finalizedSnapshot(Id projectId, String sha256Hex) {
    final json = _selectJson(
      'SELECT json FROM finalized_snapshots WHERE project_id = ? '
      'AND sha256_hex = ?',
      [projectId, sha256Hex],
    );
    return json == null ? null : FinalizedSnapshot.fromJson(_decode(json));
  }

  void saveReportRecord(ReportRecord record, {required Id by, DateTime? at}) {
    final now = _at(at);
    _database.transaction(() {
      _db.execute(
        'INSERT INTO report_records (id, project_id, json) VALUES (?, ?, ?)',
        [record.meta.id, record.projectId, jsonEncode(record.toJson())],
      );
      _appendAudit(
        entityType: 'report_record',
        entityId: record.meta.id,
        projectId: record.projectId,
        field: 'pdf_sha256',
        oldValue: null,
        newValue: record.pdfSha256,
        by: by,
        at: now,
      );
    });
  }

  List<ReportRecord> reportsForProject(Id projectId) => _db
      .select(
          'SELECT json FROM report_records WHERE project_id = ? '
          'ORDER BY id',
          [projectId])
      .map((row) => ReportRecord.fromJson(_decode(row['json'] as String)))
      .toList();

  /// Single-file portable export (spec §4). Always available, every tier
  /// (spec §8: hitting a limit never traps entered data).
  String exportProject(Id projectId,
      {required Id by, DateTime? at, required String appVersion}) {
    final snapshot = loadSnapshot(projectId);
    return const ProjectExport().exportToString(
      snapshot: snapshot,
      registry: registryForShop(snapshot.project.shopId, by: by),
      exportedAt: _at(at),
      appVersion: appVersion,
    );
  }

  /// Imports a portable project file. Refuses to overwrite an existing
  /// project id — zero data loss beats convenience (spec §8).
  Id importProject(String json, {required Id by, DateTime? at}) {
    final imported = const ProjectExport().import(json);
    final projectId = imported.snapshot.project.meta.id;
    if (getProject(projectId) != null) {
      throw StateError(
          'Project $projectId already exists; import refused. Delete or '
          'rename the existing project first.');
    }
    final now = _at(at);
    _database.transaction(() {
      _writeProjectRow(imported.snapshot.project, now);
      for (final circuit in imported.snapshot.circuits) {
        _db.execute(
          'INSERT INTO circuits (id, project_id, parent_circuit_id, json) '
          'VALUES (?, ?, ?, ?)',
          [
            circuit.meta.id,
            circuit.projectId,
            circuit.parentCircuitId,
            jsonEncode(circuit.toJson()),
          ],
        );
      }
      for (final component in imported.snapshot.components) {
        _db.execute(
          'INSERT INTO components (id, project_id, circuit_id, json) '
          'VALUES (?, ?, ?, ?)',
          [
            component.meta.id,
            projectId,
            component.circuitId,
            jsonEncode(component.toJson()),
          ],
        );
      }
      _appendAudit(
        entityType: 'project',
        entityId: projectId,
        projectId: projectId,
        field: '*',
        oldValue: null,
        newValue: 'imported from portable file',
        by: by,
        at: now,
      );
    });
    return projectId;
  }
}
