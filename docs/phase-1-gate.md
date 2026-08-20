# GATE 1 — owner end-to-end validation

Phase 1 (MVP) is code-complete pending this gate (spec §7). The gate
exercise: **run a real historical panel through the app end-to-end and
compare against the spreadsheet result.** Golden cases get recorded from
that exercise into `tests/golden/`.

## What shipped in Phase 1

- **Store** (`store/`): SQLite (WAL journaling), typed repositories,
  field-level append-only audit (DB triggers enforce it), finalized-project
  immutability at the storage layer, version-pinned library items,
  registry persistence per shop, acknowledgment records, warning
  acknowledgments, portable JSON export/import.
- **Engine live rules**: weakest-link, scope, voltage validation (mismatch
  and missing-data blockers; slash-rating question until owner configures
  params), assumed-defaults table cross-check. Series combination /
  transformer / let-through remain scaffolded slots per spec.
- **Finalization**: core gate (blockers, unverified fired rules,
  unacknowledged warnings, per-user acknowledgment text version) freezes an
  immutable snapshot with a SHA-256 over the canonical export.
- **Report** (`report/`): §6 PDF minus the combos section; disclaimer
  placeholder + attribution on every page; DRAFT and
  CONTAINS-UNVERIFIED-RULES watermarks; byte-deterministic output
  (ADR 0005); PDF hash recorded on finalized reports.
- **App** (`app/`): first-run acknowledgment (live, persisted, audited),
  project CRUD, circuit tree editor, keyboard-first component entry with
  library type-ahead and save-to-library, undo/redo (Ctrl+Z /
  Ctrl+Shift+Z), rollup panel with strays + resolve queue, value traces,
  assumed-ratings table UI, rules registry UI with sign-off flow,
  finalize flow, draft reports, export/import. Linux desktop target.

## Gate exercise checklist (owner)

1. In **Rules registry**, review each rule against your copy of the
   standard: rewrite descriptions in your words, fill clause pointers, set
   `top_n_strays` and scope params, then sign off the rules you accept.
2. Populate **Your configured assumed ratings** if your workflow uses
   assumed defaults.
3. Enter a real historical panel (circuit tree + all power-circuit
   components with citations).
4. Compare the rollup + limiting components against your spreadsheet.
5. Finalize; check the PDF against what you'd file in the job record.
6. Send back the export JSON — it becomes golden case #0001.

## Known gaps / deliberate deferrals

- Combos section of the report and combo engine rule: Phase 2.
- BOM CSV import, multi-voltage, tier gating, report branding: Phase 2.
- Export-as-backup nag (spec §8) not yet implemented — flagged for Phase 2.
- Windows/macOS runners not yet generated (Linux only so far).
- Slash-rating applicability parameters: engine raises QUESTION flags until
  you define them (registry `voltage_validation.params.slash_rating_params`).

## Questions for the owner at this gate

1. Voltage validation currently blocks when a component's rating is below
   ANY panel rated voltage, and blocks on missing/unattested voltage data.
   Confirm or amend before sign-off.
2. Assumed-defaults cross-check behavior (warn on missing entry, warn on
   mismatch) — confirm or amend.
3. Component entry form field order — matches your entry rhythm?
4. What should the method statement template say (report §6.1.2 slot)?
