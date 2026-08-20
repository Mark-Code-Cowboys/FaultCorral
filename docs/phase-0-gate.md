# GATE 0 — owner review checklist

Phase 0 (Skeleton) is complete pending this review (spec §7). Do not start
Phase 1 without explicit owner confirmation.

## What exists

- [x] Repo, `.gitignore`, README, proprietary LICENSE, license headers.
- [x] CI (`.github/workflows/ci.yml`): core analyze + tests, banned-vocab
      lint, license-header check, schema check, owner-checklist freshness,
      Flutter app analyze.
- [x] `faultcorral_core`: full §2 domain model (attestation-first, UNRATED
      semantics, SCCR ≠ interrupting rating, append-only audit, version-pinned
      library items), all eight §3.1 registry slots (everything `unverified`,
      let-through `disabled`), engine with weakest-link + scope implemented
      against placeholder data, explainability traces, flag taxonomy,
      finalization gate.
- [x] Versioned JSON export/import with round-trip property test; unknown
      versions refused.
- [x] Golden and property test scaffolding (36+ tests green).
- [x] `legal/` drafts, all marked DRAFT + ship-blocking; first-run
      acknowledgment flow stub in the app with fixed mechanics.
- [x] Generated `docs/owner-verification-checklist.md` enumerating every
      `TODO(owner-verify)`.

## Decisions recorded at Phase 0 start (spec §9)

1. Stack: Flutter/Dart (ADR 0001).
2. Persistence: SQLite locally; JSON portable format (ADR 0002).
3. Component category list: shipped as spec §2.1 verbatim — **owner: edits?**
4. Golden case #1: **open — owner picks the historical panel at GATE 1.**
5. Attorney: none yet — placeholders are ship-blocking.
6. Name: FaultCorral confirmed (owner runs USPTO/domain checks separately).

## Questions for the owner at this gate

1. Review the domain model (§2) and registry slots (§3.1) against your copy
   of the standard: field-level gaps? Extra rule slots needed?
2. Banned-vocab lint scope + the two recorded allowances (ADR 0004) — agree?
3. Rule-slot placeholder descriptions must be replaced with your own wording
   (they are marked PLACEHOLDER in the registry scaffold).
4. `top_n_strays` placeholder parameter (currently 3) — your call.
5. Scope-rule default (`require_power_circuit_flag: true`, no category
   filter) — confirm or specify the category list.
