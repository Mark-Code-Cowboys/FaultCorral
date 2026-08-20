# FaultCorral

**A vendor-neutral SCCR determination workbook and documentation generator for
UL 508A panel shops.** Published by Code Cowboys LLC.

Round up every power-circuit component in the panel, find the stray dragging the
rating down, and walk out with a clean documentation package.

## What FaultCorral is — and is not

FaultCorral is a **documentation aid, not an authority**. It organizes,
cross-checks, and reports values the user supplies and attests. It does not
determine, assert, or declare the correctness of any rating, and it does not
reproduce the text of UL 508A, the NEC, or any other standard. The app assumes
the user holds a current licensed copy of UL 508A. Every value in the system
carries a source type, a citation, and an attestation record; the report is the
responsible person's document — the app is the pencil.

## Repository layout

| Path      | Contents |
|-----------|----------|
| `core/`   | `faultcorral_core` — pure Dart library: domain model, rules registry, rollup engine, JSON export/import. Zero UI imports. |
| `app/`    | Flutter UI (desktop/web first). Phase 0: first-run acknowledgment flow stub. |
| `report/` | PDF report generation (Phase 1). |
| `data/`   | Versioned export schema, empty registry seeds. |
| `tests/`  | Cross-package fixtures: golden cases (placeholders until the owner supplies worked examples). |
| `legal/`  | EULA / disclaimer drafts — all `DRAFT — REQUIRES ATTORNEY REVIEW`, ship-blocking. |
| `docs/`   | Master build prompt, ADRs, owner sign-off checklist (generated), friction log. |
| `tool/`   | Repo checks: banned-vocabulary lint, license-header check, schema check, owner checklist generator. |

Dart-package unit/property tests live inside each package's `test/` directory
(Dart tooling convention); shared fixtures live in top-level `tests/`. See
`docs/adr/0003-repo-layout.md`.

## Development

Requires Dart SDK ≥ 3.4 (core) and Flutter (app).

```sh
# Core library
cd core
dart pub get
dart analyze
dart test

# Repo checks (run from repo root)
dart tool/banned_vocab_lint.dart
dart tool/license_header_check.dart
dart tool/schema_check.dart
dart tool/owner_verify_checklist.dart --check   # --write to regenerate
```

CI runs all of the above on every push (`.github/workflows/ci.yml`).

## Ground rules baked into the code

- **No invented domain values.** Rule slots ship empty or parameterized; every
  domain rule carries `status: unverified` until the owner marks it against his
  copy of the standard. The engine refuses to finalize while any fired rule is
  unmarked; dev builds watermark output `CONTAINS UNVERIFIED RULES — NOT FOR USE`.
- **Attestation-first.** Every SCCR/voltage value requires source type,
  citation, and attester. Missing SCCR ⇒ component is **UNRATED** and blocks
  finalization.
- **Banned-vocabulary lint.** CI fails if user-facing strings claim authority
  the tool must never claim (see `tool/banned_vocab_lint.dart`).
- **SCCR and interrupting rating are distinct fields, never conflated.**
- **Append-only audit trail** per project.
- **Reproducibility.** Rollup is a pure function of project snapshot + registry
  snapshot; finalization freezes an immutable snapshot.

## Build status

Currently in **Phase 0 — Skeleton** of `docs/faultcorral-master-build-prompt.md`.
Phase gates require explicit owner confirmation before advancing. Open items for
GATE 0 are listed in `docs/phase-0-gate.md` and the generated
`docs/owner-verification-checklist.md`.

---
Copyright (c) 2026 Code Cowboys LLC. All rights reserved.
