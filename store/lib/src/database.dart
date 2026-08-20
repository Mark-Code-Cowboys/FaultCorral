// Copyright (c) 2026 Code Cowboys LLC. All rights reserved.

import 'package:sqlite3/sqlite3.dart';

/// SQLite database holder for FaultCorral (ADR 0002).
///
/// - WAL journaling for crash safety (spec §8: zero data loss).
/// - `audit_events`, `acknowledgments`, and `finalized_snapshots` are
///   write-once at the database layer via ABORT triggers — the append-only
///   audit invariant does not depend on repository code being polite.
/// - `library_items` rows are immutable per (id, version); edits insert a
///   new version (spec §2.2 version pinning).
class FaultCorralDatabase {
  FaultCorralDatabase._(this.db);

  final Database db;

  static const _schemaVersion = 1;

  /// Opens (and migrates) a database file. The Flutter app supplies the
  /// platform sqlite3 library; on plain Dart the system library is used.
  factory FaultCorralDatabase.open(String path) {
    final db = sqlite3.open(path);
    db.execute('PRAGMA journal_mode=WAL;');
    return FaultCorralDatabase._migrate(db);
  }

  /// In-memory database for tests.
  factory FaultCorralDatabase.memory() =>
      FaultCorralDatabase._migrate(sqlite3.openInMemory());

  static FaultCorralDatabase _migrate(Database db) {
    db.execute('PRAGMA foreign_keys=ON;');
    final version = db.select('PRAGMA user_version;').first.columnAt(0) as int;
    if (version < 1) {
      db.execute(_schemaV1);
      db.execute('PRAGMA user_version = $_schemaVersion;');
    }
    return FaultCorralDatabase._(db);
  }

  void dispose() => db.dispose();

  /// Runs [action] in a transaction; rolls back on any throw.
  T transaction<T>(T Function() action) {
    db.execute('BEGIN IMMEDIATE;');
    try {
      final result = action();
      db.execute('COMMIT;');
      return result;
    } catch (_) {
      db.execute('ROLLBACK;');
      rethrow;
    }
  }

  static const _schemaV1 = '''
CREATE TABLE shops (
  id TEXT PRIMARY KEY,
  json TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE users (
  id TEXT PRIMARY KEY,
  shop_id TEXT NOT NULL,
  json TEXT NOT NULL
);

CREATE TABLE projects (
  id TEXT PRIMARY KEY,
  shop_id TEXT NOT NULL,
  status TEXT NOT NULL,
  json TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE circuits (
  id TEXT PRIMARY KEY,
  project_id TEXT NOT NULL,
  parent_circuit_id TEXT,
  json TEXT NOT NULL
);
CREATE INDEX idx_circuits_project ON circuits(project_id);

CREATE TABLE components (
  id TEXT PRIMARY KEY,
  project_id TEXT NOT NULL,
  circuit_id TEXT NOT NULL,
  json TEXT NOT NULL
);
CREATE INDEX idx_components_project ON components(project_id);
CREATE INDEX idx_components_circuit ON components(circuit_id);

CREATE TABLE library_items (
  id TEXT NOT NULL,
  version INTEGER NOT NULL,
  shop_id TEXT NOT NULL,
  json TEXT NOT NULL,
  PRIMARY KEY (id, version)
);
CREATE TRIGGER library_items_immutable BEFORE UPDATE ON library_items
BEGIN SELECT RAISE(ABORT, 'library_items rows are immutable; insert a new version'); END;

CREATE TABLE combo_ratings (
  id TEXT PRIMARY KEY,
  shop_id TEXT NOT NULL,
  json TEXT NOT NULL
);

CREATE TABLE registry_entries (
  shop_id TEXT NOT NULL,
  rule_id TEXT NOT NULL,
  json TEXT NOT NULL,
  PRIMARY KEY (shop_id, rule_id)
);

CREATE TABLE audit_events (
  id TEXT PRIMARY KEY,
  project_id TEXT,
  json TEXT NOT NULL
);
CREATE INDEX idx_audit_project ON audit_events(project_id);
CREATE TRIGGER audit_events_no_update BEFORE UPDATE ON audit_events
BEGIN SELECT RAISE(ABORT, 'audit_events is append-only'); END;
CREATE TRIGGER audit_events_no_delete BEFORE DELETE ON audit_events
BEGIN SELECT RAISE(ABORT, 'audit_events is append-only'); END;

CREATE TABLE acknowledgments (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  text_version TEXT NOT NULL,
  json TEXT NOT NULL
);
CREATE TRIGGER acknowledgments_no_update BEFORE UPDATE ON acknowledgments
BEGIN SELECT RAISE(ABORT, 'acknowledgments are write-once'); END;
CREATE TRIGGER acknowledgments_no_delete BEFORE DELETE ON acknowledgments
BEGIN SELECT RAISE(ABORT, 'acknowledgments are write-once'); END;

CREATE TABLE flag_acknowledgments (
  project_id TEXT NOT NULL,
  flag_key TEXT NOT NULL,
  json TEXT NOT NULL,
  PRIMARY KEY (project_id, flag_key)
);

CREATE TABLE finalized_snapshots (
  project_id TEXT NOT NULL,
  sha256_hex TEXT NOT NULL,
  json TEXT NOT NULL,
  PRIMARY KEY (project_id, sha256_hex)
);
CREATE TRIGGER finalized_snapshots_no_update BEFORE UPDATE ON finalized_snapshots
BEGIN SELECT RAISE(ABORT, 'finalized snapshots are immutable'); END;
CREATE TRIGGER finalized_snapshots_no_delete BEFORE DELETE ON finalized_snapshots
BEGIN SELECT RAISE(ABORT, 'finalized snapshots are immutable'); END;

CREATE TABLE report_records (
  id TEXT PRIMARY KEY,
  project_id TEXT NOT NULL,
  json TEXT NOT NULL
);
''';
}
