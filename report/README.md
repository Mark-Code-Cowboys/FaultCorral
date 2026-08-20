# report/

PDF report generation lands in Phase 1 (spec §6). Requirements already fixed
by the spec and the core model:

- Deterministic output — the PDF bytes are hashed (SHA-256) into the
  finalization record (`ReportRecord.pdfSha256`), so generation must be
  reproducible from a project snapshot + registry snapshot.
- Every page footer renders the disclaimer block from
  `legal/DISCLAIMER_TEMPLATE_DRAFT.md` (placeholder until attorney text).
- Draft watermark on any report from a non-finalized project; the
  "CONTAINS UNVERIFIED RULES — NOT FOR USE" watermark whenever
  `RollupResult.containsUnverifiedRuleResults` is true.
- Section order per spec §6.1; the corral metaphor never appears in report
  output.
