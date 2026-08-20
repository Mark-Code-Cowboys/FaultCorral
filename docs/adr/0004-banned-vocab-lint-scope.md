# ADR 0004 — Banned-vocabulary lint: scope and escape hatch

Date: 2026-08-19 · Status: accepted (owner review requested at GATE 0)

Spec §0.1 bans authority-claiming vocabulary in UI text, reports, marketing
copy, and user-rendered comments.

## Decision
`tool/banned_vocab_lint.dart` scans:
- string literals in `core/lib` and `app/lib` Dart code (flag messages and UI
  strings are user-facing),
- everything under `report/` (templates render to users).

Excluded: `legal/` (attorney-owned text legitimately negates these words),
`docs/` and `README.md` (developer-facing), test code.

Escape hatch: a comment containing `lint:allow-banned-vocab` plus a reason
suppresses findings until the next blank line. Known allowances at Phase 0:
1. `RuleStatus` wire tokens (`'verified'` etc.) — serialization values for
   the owner sign-off lifecycle, not claims about any panel.
2. The §0.4 acknowledgment placeholder text — it NEGATES authority claims
   ("does not … verify, or certify").

The lint prints every allowance so the owner can review the list at each
phase gate.
