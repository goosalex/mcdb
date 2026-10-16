---
status: testing
phase: 02-spec-method-test-harness-pilot
source:
  - 02-01-SUMMARY.md
  - 02-02-SUMMARY.md
  - 02-03-SUMMARY.md
  - 02-04-SUMMARY.md
  - 02-05-SUMMARY.md
  - 02-06-SUMMARY.md
  - 02-07-SUMMARY.md
  - 02-08-SUMMARY.md
  - 02-09-SUMMARY.md
  - 02-10-SUMMARY.md
  - 02-11-SUMMARY.md
  - 02-12-SUMMARY.md
  - 02-13-SUMMARY.md
started: 2026-08-01T00:00:00Z
updated: 2026-08-01T00:00:00Z
---

## Current Test

number: 1
name: Cold start — one command, from scratch
expected: |
  `bash migration/test/run-all.sh --rebuild-template` rebuilds mcdb_tmpl from
  ddl/migrated + schema-fixes + masterdata fixtures, bootstraps a disposable DB,
  runs the three anti-circularity gates, then both harness halves, and prints a
  per-package pass/fail table. It exits NON-ZERO and reports 2 of 7 packages PASS.
awaiting: user response

## Tests

### 1. Cold start — one command, from scratch
expected: `bash migration/test/run-all.sh --rebuild-template` runs gates → template build → bootstrap → both harnesses, prints a per-package table, exits non-zero, reports 2/7 packages PASS (SC #2, HARN-04)
result: [pending]

### 2. Both harness halves actually run
expected: The table has BOTH a pgTAP column (pg_prove) and a REGRESS column (sql/*.sql vs expected/*.out diffing) — not one harness with the other stubbed (SC #1, HARN-01/HARN-02)
result: [pending]

### 3. Realistic reference data from masterdata/
expected: Tests execute against real reference rows (ticket statuses, labels, event types) seeded from masterdata/, not invented fixtures (SC #3, HARN-03)
result: [pending]

### 4. Specs apply the uniform 5-dimension checklist
expected: Each pilot spec in migration/spec/ covers empty-string/NULL, SELECT INTO strictness, exception codes, package state, FUNCTION-vs-PROCEDURE, and carries an explicit assumptions/unresolved section (SC #4, SPEC-02/SPEC-03)
result: [pending]

### 5. Tests cite spec clauses, and red→green is demonstrated
expected: Every assertion names its clause ID (S-TICKET-024 etc., enforced by trace_lint.py), and REDGREEN-EVIDENCE.md shows the whole pilot going 8/204 RED → 199/204 GREEN in one scripted run, with a mutation check proving the suite catches real defects (SC #5)
result: [pending]

### 6. Anti-circularity is enforced, not just claimed
expected: provenance_lint.sh passes for all 6 translated packages; no translation commit touches a test assertion file; every test change is logged in migration/spec/TEST-AMENDMENTS.md (A-001..A-008) with Oracle citations and evidence
result: [pending]

### 7. Residual reds are understood, not hidden
expected: run-all.sh reports the true state rather than forcing green. 5 of 7 packages are not green: auth.osag_auth 9/10 (S-AUTH-007, deferred by your own decision), tt.ticket_interface 125/129, and regress CONTEXT-line goldens — each root-caused to a test-fixture or harness defect, never a translation defect
result: [pending]

### 8. The Phase 4 verdict is decision-grade
expected: METHOD-REVIEW.md gives a measured spec-amendment error rate, extrapolates it honestly (budget 15-20 more amendments across the remaining 44 packages — not zero), and lists 6 concrete spec-template changes to land before Phase 4 starts
result: [pending]

## Summary

total: 8
passed: 0
issues: 0
pending: 8
skipped: 0

## Gaps

[none yet]
