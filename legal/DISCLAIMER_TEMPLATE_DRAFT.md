# Report footer disclaimer block

**DRAFT — REQUIRES ATTORNEY REVIEW. NOT FINAL. SHIP-BLOCKING.**

Rendered in the footer of EVERY report page (spec §6.4). Two parts:

## 1. Legal disclaimer (attorney text)

```
[[LEGAL-DISCLAIMER — ATTORNEY TEXT REQUIRED]]
```

Topics counsel must cover: documentation produced by and owned by the
attesting user; no representation by Code Cowboys LLC as to correctness or
conformance of the panel; no professional-engineering services.

## 2. Fixed attribution line (product copy, final)

```
Generated with FaultCorral — a documentation tool. All values user-supplied and attested.
```

Rules baked into the report layer (spec §6.4):
- Nowhere may the app's name appear as the source of any rating or
  determination.
- Draft watermark on any report from a non-finalized project or one
  containing unverified-rule results.
- Shop `legal_footer_override` text may ADD to this block, never replace it.
