# FaultCorral — Master Build Prompt

You are building **FaultCorral**, a vendor-neutral SCCR (short-circuit current rating)
determination workbook and documentation generator for UL 508A panel shops, published by
Code Cowboys LLC. This document is the authoritative build specification. Follow it in
phase order. **Stop at every PHASE GATE and wait for explicit confirmation before
advancing.**

---

## 0. PRIME DIRECTIVES — read before writing any code

These override everything else in this document and every future instruction unless the
owner explicitly amends this section.

### 0.1 The app is a tool, never the authority
- FaultCorral is a **documentation workbook**. It organizes, cross-checks, and reports
  values the user supplies and attests. It does not certify, approve, verify, or declare
  compliance with anything.
- **Banned vocabulary** in all UI text, reports, marketing copy, and code comments that
  render to users: "compliant," "certified," "approved," "verified," "guaranteed,"
  "UL-approved," "meets UL 508A," "passes." Build a lint rule / string test that fails CI
  if these appear in user-facing strings.
- **Permitted framing**: "determination worksheet," "as entered and attested by the user,"
  "user-supplied value," "documentation aid," "supports your Supplement SB workflow."
- The app may flag inconsistencies and raise questions. It may never assert correctness.

### 0.2 No reproduction of the standard
- Do not embed, paraphrase, or reproduce text from UL 508A, the NEC, or any copyrighted
  standard. The app assumes the user holds a current licensed copy of UL 508A.
- Numeric defaults (e.g., assumed ratings) are implemented as a **user-confirmed rules
  registry** (see §3): the app ships with empty or owner-populated rule slots, every value
  carries a `verified_by` and `verified_date` field, and the UI presents them as "your
  shop's configured defaults," never as "the standard says."
- Clause references (e.g., "SB4.x") may appear as *citation pointers the user filled in*,
  never as app-asserted claims about clause content.

### 0.3 Attestation-first data model
- Every SCCR value, voltage rating, and combination rating in the system requires:
  (a) a **source type** — `marked | datasheet | assumed_default | series_combination |
  other`, (b) a free-text **citation** (document, page/section, date), and (c) an implicit
  **attestation** record (user, timestamp) captured at entry and at every edit.
- No silent defaults. A component with no SCCR entered is displayed as **UNRATED** and
  blocks report finalization until the user resolves it deliberately.
- Full audit trail: append-only change log per project (who, what, when, old → new).

### 0.4 Liability surface
- **First-run gate:** a mandatory acknowledgment screen with two explicit checkboxes,
  both unchecked by default, both required to proceed — no pre-check, no "skip for now":
  1. `[ ] I understand FaultCorral is a documentation aid, not an authority. It does not
     determine, verify, or certify any rating or compliance.`
  2. `[ ] I accept final responsibility and liability for all values entered, all
     determinations made, and all documentation produced using this tool.`
  Wording above is placeholder — `[[ATTORNEY REVIEW REQUIRED]]` — but the mechanics are
  fixed: per-user (not per-shop) acknowledgment, recorded with EULA/acknowledgment text
  version, app version, user, and timestamp in the audit log; re-presented to every user
  on any material change to the text; the recorded acknowledgment version is stamped into
  every finalized project snapshot and report record so each report is traceable to an
  accepted acknowledgment.
- Every report page footer carries the disclaimer block (owner supplies final legal text;
  scaffold with a clearly marked placeholder — see §6.4).
- Every report contains a signed **attestation block** for the responsible person at the
  shop. The report is *their* document; the app is the pencil.
- EULA/ToS scaffold: limitation of liability, no warranty, no professional-engineering
  services, user responsibility for standard compliance, indemnification. Generate a
  draft clearly marked `DRAFT — REQUIRES ATTORNEY REVIEW`; never present it as final.

### 0.5 Rules for YOU, the AI assistant executing this prompt
- **Never invent domain values.** No SCCR numbers, no assumed-rating tables, no series
  combination data, no clause text from memory. Where the build needs domain data, create
  the empty structure and a `TODO(owner-verify)` marker.
- Every domain rule you implement in the rollup engine gets status `UNVERIFIED` until the
  owner marks it verified against his copy of the standard. The engine must refuse to
  finalize a report if any rule that fired is `UNVERIFIED` (dev builds may override with
  a visible watermark: "CONTAINS UNVERIFIED RULES — NOT FOR USE").
- When the correct behavior depends on the standard's actual text, **ask the owner** —
  do not guess, do not fill from training data.
- Prefer boring, proven technology. This product wins on trust, not novelty.

---

## 1. PRODUCT DEFINITION

**One-liner:** Round up every power-circuit component in the panel, find the stray
dragging the rating down, and walk out with a clean documentation package.

**Primary user:** UL 508A panel shop engineer/designer performing Supplement SB SCCR
determination. Secondary: OEM machine builders, controls engineers auditing existing
panels.

**Core loop:** Create panel project → build circuit tree (feeder path + branch circuits)
→ add components (from shop library or manual entry) → enter/attest SCCR + voltage data
with citations → engine computes weakest-link rollup and flags issues → resolve →
generate PDF documentation package for the shop's records.

**The moat, in order:** (1) per-shop self-building component library, (2) the rules
registry + audit trail rigor no spreadsheet matches, (3) later, curated cross-vendor
series-combination data. The incumbent is a vendor-captive enterprise web tool and
spreadsheets; FaultCorral wins on speed of entry, reuse, and trustworthy paper.

**Business model:** subscription per shop. Free tier: 1 active project, no PDF export.
Paid: unlimited projects, export, library sync. Price target ~$19/mo or ~$190/yr.

---

## 2. DOMAIN MODEL

Implement as the persistence schema and core types. All entities get `id`, `created_at`,
`updated_at`, `created_by`.

### 2.1 Entities

**Shop** — account root. Name, users, subscription state, settings (default voltage
system, report branding/logo, legal footer overrides).

**User** — member of a Shop. Role: `owner | editor | viewer`.

**Project (Panel)** — one determination effort.
- Fields: name, customer, panel/drawing number, revision, **rated voltage(s)** (value +
  system type: e.g., 3φ delta, 3φ wye, 1φ; slash-rating context flag), phases, frequency,
  enclosure ref (free text), status: `draft | in_review | finalized`, finalized snapshot
  ref.
- Finalization freezes an immutable snapshot (data + rules-registry versions + report
  PDF hash). Post-finalization edits require a new revision.

**Circuit** — node in the panel's power-circuit tree.
- Fields: project ref, parent circuit ref (null = incoming feeder), kind:
  `feeder | branch | sub`, label, upstream protective device ref (component), notes.
- The tree matters: series-combination and protective-device relationships are
  parent-path dependent.

**Component** — an instance placed on a circuit.
- Fields: circuit ref, library item ref (nullable for one-offs), quantity, position/tag,
  and the attested electrical data (below).
- **Category** (enum, extensible via registry): disconnect switch, fusible disconnect,
  fuse + holder/block, circuit breaker (MCCB), motor circuit protector, supplementary
  protector, contactor, motor starter (combo), overload relay, soft starter, VFD/drive,
  power distribution block, terminal block, busbar, power transformer, control
  transformer, SPD, receptacle, switch (other), meter/monitor, **other (owner-defined)**.
- Attested data per component: voltage rating (+ slash-rating flag), SCCR value (kA) with
  source type + citation, interrupting rating where applicable (kept as a **distinct
  field** from SCCR — never conflated), current-limiting flag + let-through data slot
  (structure only; usage rules live in the registry), applicable series-combination refs.
- `power_circuit: bool` — control-circuit components can be recorded for completeness but
  are excluded from rollup per a registry rule the owner configures and verifies.

**LibraryItem** — the shop's reusable catalog. Manufacturer, part number, category,
default attested data (each field still carries source + citation + attester). Adding any
manual component offers one-tap "save to library." Library items are versioned; projects
pin the version they used.

**ComboRating** — a manufacturer-published tested series combination.
- Upstream device spec (mfr, part/family, class/size), downstream device spec (mfr,
  part/family), tested SCCR (kA), voltage limit, source citation (document + date),
  attester. Scope: shop-level (global catalog is a later phase).

**RuleRegistryEntry** — see §3.

**ReportRecord** — generated report metadata: project snapshot ref, PDF hash, generated
by/at, registry versions in force.

**AuditEvent** — append-only. Entity ref, field, old, new, user, timestamp, project ref.

### 2.2 Invariants (enforce in the core, test exhaustively)
- A finalized project is immutable.
- No component may contribute to rollup without complete attested data.
- Deleting a library item never mutates historical projects (version pinning).
- SCCR and interrupting rating are never substituted for one another anywhere.
- Every rollup result is reproducible from the snapshot: same inputs + same registry
  versions ⇒ identical output (pure function; property-test this).

---

## 3. RULES REGISTRY + ROLLUP ENGINE

The heart of the product, and the mechanism that keeps the app a tool rather than an
authority.

### 3.1 Registry design
- Each rule is data + a small pure evaluator: `id`, `name`, `description` (owner's own
  words — not standard text), `clause_pointer` (free text the owner fills), `status:
  unverified | verified | disabled`, `verified_by`, `verified_date`, `version`,
  parameters (e.g., numeric thresholds, category applicability).
- Rules the skeleton must scaffold (as empty/parameterized slots, logic per owner spec):
  1. **Weakest-link rollup** — panel SCCR = minimum across in-scope components/circuits;
     always identify and rank the limiting components (show top N strays, not just #1).
  2. **Scope rule** — which categories/flags are in the power circuit rollup.
  3. **Assumed-default rule** — when source type is `assumed_default`, the value comes
     from an owner-populated defaults table (empty at ship; UI labels it "your configured
     assumed ratings").
  4. **Series-combination application** — a ComboRating may elevate a downstream
     component's effective SCCR only when the circuit tree shows the specified upstream
     device on the path, voltage limits hold, and the combo is attested. Elevated values
     display with a distinct badge + the combo citation.
  5. **Voltage validation** — component voltage rating vs. panel rated voltage;
     slash-rating applicability check (parameters owner-defined); mismatch = blocking flag.
  6. **Transformer handling** — slot for owner-specified treatment of power and control
     transformers (structure + UI affordances now, math after owner verification).
  7. **Current-limiting / let-through** — data structure and display only in early
     phases; any rating-elevation logic ships `disabled` until owner writes and verifies
     the rule.
  8. **PDB / terminal block presence check** — heuristic flag: circuits with distribution
     but no rated distribution component get a "did you forget the PDB?" question flag
     (question, not assertion).
- Flag taxonomy the engine emits: `BLOCKER` (cannot finalize), `WARNING` (finalize with
  acknowledgment, recorded), `QUESTION` (informational nudge). Every flag names its rule
  id and registry version.

### 3.2 Engine requirements
- Pure, deterministic, side-effect free. Input: project snapshot + registry snapshot.
  Output: rollup result (panel SCCR per rated voltage, limiting-component ranking, flag
  list, per-component effective-value trace).
- **Explainability:** for every component, the engine can render "why this effective
  value" as a human-readable trace (source → combos applied → rules fired). This trace
  goes in the report appendix.
- Golden test suite: owner will supply worked examples (real panels with known-correct
  outcomes). Every golden case is a regression test. Start the file structure now with
  placeholder cases marked `TODO(owner-verify)`.
- Property tests: monotonicity (raising any component SCCR never lowers panel SCCR),
  determinism, snapshot reproducibility.

---

## 4. ARCHITECTURE & STACK

- **Platform priority:** desktop/web first (this work happens at a desk). Structure for a
  future mobile companion (floor verification) by keeping the core engine and models in a
  UI-free library.
- **Stack:** use the owner's established cross-platform toolchain — ASK which before
  scaffolding; do not assume. Constraints regardless of choice:
  - Core domain (models, engine, registry) in a pure library with zero UI imports.
  - **Local-first**: full offline operation; sync is a later phase, not a dependency.
  - Single-file portable project export/import (JSON, versioned schema, embedded schema
    version + registry versions) from day one — this is also the backup story.
  - PDF generation must be deterministic enough to hash for the finalization record.
- Repo layout: `core/` (domain + engine + registry), `app/` (UI), `report/` (PDF),
  `data/` (schemas, empty registry seeds), `tests/` (unit, property, golden), `legal/`
  (EULA draft, disclaimer templates, all marked DRAFT), `docs/` (this file, ADRs,
  owner-verification checklist).
- CI from phase 0: build, tests, the banned-vocabulary lint (§0.1), schema-migration
  check.

---

## 5. UX PRINCIPLES

- **Keyboard-first entry.** The whole pitch is "faster than the spreadsheet." Component
  entry must be doable without touching the mouse: type-ahead against the shop library,
  tab-through fields, duplicate-row, bulk edit.
- The circuit tree is the primary navigation; the limiting component is always visible
  ("the stray") with one-click jump.
- UNRATED and UNVERIFIED states are loud, specific, and listed in a single resolve queue.
- Autosave everything; undo/redo across the project; never lose a keystroke of entry
  work. Data loss is the one sin this audience never forgives.
- Empty states teach: a new shop's first project walks the loop with inline guidance
  (owner-authored copy; scaffold the slots).
- Tone: competent ranch-hand, not cartoon cowboy. The corral metaphor lives in naming and
  light touches (the "stray" = limiting component), never in the report output. Reports
  are dead serious.

---

## 6. REPORT SPECIFICATION (the actual deliverable shops pay for)

### 6.1 Contents, in order
1. Cover: shop branding, project/panel identity, revision, rated voltage(s), date,
   overall determined SCCR **as attested by** [responsible person].
2. Determination summary: method statement slot (owner-authored template text), registry
   versions in force, limiting component(s) with effective values.
3. Component table: circuit path, tag, category, mfr, part number, voltage rating, SCCR,
   source type, citation, combo applied (if any), attester, date.
4. Series combinations applied: full detail per combo with citations.
5. Flags & resolutions: every WARNING acknowledged, by whom, with note.
6. Explainability appendix: per-component value trace (§3.2).
7. Attestation block: printed name, title, signature line, date — the human owns this
   document.
8. Revision history.

### 6.2–6.4 Framing requirements
- Footer on every page: disclaimer block (placeholder `[[LEGAL-DISCLAIMER — ATTORNEY
  TEXT REQUIRED]]` until owner supplies final language) + "Generated with FaultCorral —
  a documentation tool. All values user-supplied and attested."
- Nowhere in the report may the app's name appear as the source of any rating or
  determination.
- Draft watermark on any report from a non-finalized project or one containing
  unverified-rule results.

---

## 7. PHASED BUILD PLAN

Work strictly in order. Each phase ends with a **PHASE GATE**: demo the checklist,
present open questions, wait for owner confirmation.

### Phase 0 — Skeleton (no features, all bones)
- Repo, CI, banned-vocab lint, license headers.
- Core library: full domain model (§2), empty rules registry with all §3.1 slots,
  engine interface + weakest-link rule implemented against placeholder data,
  golden/property test scaffolding.
- Persistence + versioned JSON export/import round-trip.
- `legal/` drafts (marked DRAFT), first-run acknowledgment flow stub.
- Owner-verification checklist doc: every `TODO(owner-verify)` in the codebase is
  enumerated here automatically (build step).
- **GATE 0:** owner reviews model + registry design against his copy of the standard.

### Phase 1 — MVP (a shop could use this tomorrow)
- Project CRUD, circuit tree editor, component entry (keyboard-first), shop library with
  save-from-entry and version pinning.
- Rollup engine live: weakest-link, scope, voltage validation; flag queue; explainability
  trace.
- Assumed-defaults table UI (owner/shop populates own values).
- PDF report per §6 (minus combos section), finalization snapshot + hash.
- First-run checkbox acknowledgment live per §0.4 (both boxes, blocking, audited);
  disclaimer placeholders in place.
- **GATE 1:** owner runs a real historical panel through it end-to-end and compares
  against the spreadsheet result. Golden cases recorded from this exercise.

### Phase 2 — The spreadsheet killer
- Series-combination registry + engine rule (owner-verified), combo badges + report
  section.
- **BOM CSV import** with mapping UI (target: EPLAN and AutoCAD Electrical export
  formats; owner supplies real sample files) — imported rows land as UNRATED components
  ready for attestation, matched against the library where possible.
- Multi-voltage panels; transformer structure UI.
- Report polish: shop branding, template text editing.
- Free-tier / paid-tier gating; single-shop licensing mechanics.
- **GATE 2:** two or three friendly beta shops (owner's network), structured feedback
  loop, fix list burned down before any public availability.

### Phase 3 — The moat deepens
- Sync/multi-user within a shop (roles per §2.1), conflict-safe.
- Curated cross-vendor combo/catalog data as a premium layer (owner-verified pipeline —
  data entry tooling for the owner, provenance on every row).
- Mobile companion (read + verify + photo attach against components on the floor).
- **GATE 3:** pricing validation with real shops; churn and support-load review.

### Phase 4 — Suite posture
- FaultCorral becomes the umbrella: SCCR module joined by the next calc module (enclosure
  thermal or feeder sizing — owner picks based on beta feedback). Shared shop library,
  shared report engine, one subscription.
- Marketing site under Code Cowboys patterns; community-driven launch (forums, the
  owner's course audience, email list) — no paid ads assumed.

---

## 8. QUALITY BAR (the 1-in-10 rule)

Happy shops tell one friend; burned shops tell everyone. Therefore:
- **Zero data loss, ever.** Autosave, journaled writes, export-as-backup nag until the
  shop has exported once.
- **No wrong numbers from the app's side.** The engine is pure, property-tested, and
  golden-tested; anything unverified is loudly watermarked.
- **No surprise paywalls mid-work.** Free tier limits are stated up front; hitting a
  limit never traps entered data (export always works).
- Support debt is design debt: every confusing beta question becomes either a UX fix or
  an empty-state explanation. Keep a `docs/friction-log.md`.
- Performance: entry and rollup feel instant on a 200-component panel on modest shop
  hardware.

---

## 9. OPEN QUESTIONS FOR THE OWNER (ask at Phase 0 start)

1. Stack/toolchain to use (§4)?
2. Local persistence choice within that stack?
3. Exact component-category list edits to §2.1?
4. Which historical panel becomes golden case #1?
5. Attorney lined up for EULA/disclaimer text, or ship-blocking placeholder until then?
6. Product name lock: FaultCorral (pending USPTO/domain checks) — confirmed?

— End of master build prompt. Begin with Phase 0 after answering §9. —
