# ADR 0003 — Repo layout vs. Dart package conventions

Date: 2026-08-19 · Status: accepted

The spec (§4) prescribes `core/ app/ report/ data/ tests/ legal/ docs/`.
Dart tooling requires each package's unit tests in its own `test/` directory.

## Decision
- Package tests live inside packages (`core/test/`).
- Top-level `tests/` holds cross-package fixtures — the golden cases —
  loaded by `core/test/golden_test.dart` via relative path.
- Repo-level checks live in `tool/` (banned-vocab lint, license headers,
  schema check, owner checklist generator); they are dependency-free Dart
  scripts runnable from the repo root.
- `data/registry_seeds/registry_seed.json` is generated from
  `RulesRegistry.scaffold()` (core/tool/generate_registry_seed.dart) and a
  test keeps it from drifting.
