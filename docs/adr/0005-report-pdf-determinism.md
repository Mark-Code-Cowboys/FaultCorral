# ADR 0005 — Deterministic PDF bytes

Date: 2026-08-19 · Status: accepted

Spec §4 requires report PDFs to be deterministic enough to hash into the
finalization record. The `pdf` package (dart_pdf) breaks that two ways:
any Info dict gets `/CreationDate` stamped with `DateTime.now()`, and the
trailer `/ID` is generated from a secure-random seed.

## Decision
- Write **no Info metadata** (no title/author/producer params), so no
  CreationDate is emitted. Document identity lives in the rendered content
  (shop, project, date, revision) where the reader actually looks.
- Emit **PDF 1.4** so the trailer stays plain text, then post-process the
  bytes: replace the random `/ID` pair with a same-length FNV-1a-derived id
  computed from the rest of the file (`_pinDocumentId`).
- A regression test asserts two builds from identical inputs produce
  byte-identical files.

## Consequences
- If the pdf package later grows a seedable ID / date, drop the
  post-processing.
- Any new metadata feature (XMP, etc.) must be checked against the
  determinism test before shipping.
