# First-run acknowledgment text

**DRAFT — REQUIRES ATTORNEY REVIEW. Wording is the spec §0.4 placeholder;
mechanics are fixed and already implemented.**

`text_version: 0.1.0-draft` — this version string is what the app records in
each user's `AcknowledgmentRecord` and stamps into finalized snapshots and
report records. Any material change to the text below MUST bump the version,
which re-presents the screen to every user.

## Checkbox 1 `[[ATTORNEY REVIEW REQUIRED]]`

> I understand FaultCorral is a documentation aid, not an authority. It does
> not determine, verify, or certify any rating or compliance.

## Checkbox 2 `[[ATTORNEY REVIEW REQUIRED]]`

> I accept final responsibility and liability for all values entered, all
> determinations made, and all documentation produced using this tool.

## Fixed mechanics (not subject to wording review)

- Per-user, not per-shop. Both boxes unchecked by default; both required;
  no pre-check; no "skip for now".
- Acceptance recorded with text version, app version, user, timestamp — in
  the acknowledgment store and the audit log.
- Re-presented to every user on any bump of `text_version`.
