<!--
One ticket = one PR. Fill the four sections below.
Ticket IDs and their Problem/Solution/Tests live in ROADMAP.md.
-->

**Ticket:** <!-- e.g. A1 — Metadata-below parser (ROADMAP.md → Wave 1) -->

## Problem
<!-- What's broken/missing and why it matters. Link the ROADMAP/DESIGN line. -->

## Solution
<!-- The approach in a few sentences. Files touched. What it deliberately does NOT do.
     Note any contract other tickets depend on. -->

## Tests
<!-- The assertions that prove the logic. -->
- [ ]

## Verify
<!--
REQUIRED — no PR merges without proof it works. Attach clear, human-readable evidence,
matched to the ticket type. A green claim in prose is not evidence; paste/attach the real thing.
  - pure logic (parser, bucketing, date math) → paste the green `swift run foolscap-selftest`
    output (there is NO `swift test` here) + `bash scripts/check-core-boundary.sh` = OK
  - rendering (panel layout, chips, stamps)   → a screenshot (Playwright on the composed
    HTML/WKWebView surface, or the real app)
  - behavioral / stateful (writes, notifications, conflicts) → a short screen-recording / GIF
  - the morning routine (not app code)        → a run transcript + the vault `git diff`
-->
- **Method:**
- **Evidence:** <!-- paste the test output, or attach the screenshot / GIF / recording -->
- [ ] Proof attached above (screenshot / video / green test run), matched to the ticket type

---
<!-- depends: <ticket IDs> · blocks: <ticket IDs> -->
