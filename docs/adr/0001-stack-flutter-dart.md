# ADR 0001 — Stack: Flutter/Dart

Date: 2026-08-19 · Status: accepted (owner decision at Phase 0 start, spec §9.1)

## Decision
FaultCorral is built in Dart with Flutter for UI. The core domain (models,
rules registry, rollup engine, export/import) is `faultcorral_core`, a pure
Dart package with zero Flutter imports.

## Rationale
- One codebase covers desktop/web now and the Phase 3 mobile companion.
- The pure-core constraint (spec §4) maps naturally onto a Dart package the
  Flutter app depends on by path.

## Consequences
- PDF generation (Phase 1) must be chosen for deterministic, hashable output
  within the Dart ecosystem.
- CI needs both a Dart job (core, tools) and a Flutter job (app).
