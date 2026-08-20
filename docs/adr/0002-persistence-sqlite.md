# ADR 0002 — Persistence: SQLite locally, JSON as the portable format

Date: 2026-08-19 · Status: accepted (owner decision at Phase 0 start, spec §9.2)

## Decision
- Local persistence is SQLite (journaled/WAL writes for the zero-data-loss
  bar, spec §8). Wiring lands in Phase 1 in the app layer.
- The versioned single-file JSON export (spec §4) is the portable
  project/backup format from day one and is implemented in the core
  (`ProjectExport`), independent of the database.

## Consequences
- The core stays persistence-agnostic: it defines entities and their JSON
  forms; the app layer owns SQLite schema and migrations.
- Audit rows and finalized snapshots must be write-once at the DB layer
  (no UPDATE/DELETE paths for them).
