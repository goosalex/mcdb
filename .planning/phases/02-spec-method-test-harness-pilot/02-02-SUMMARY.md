---
phase: 02-spec-method-test-harness-pilot
plan: 02
subsystem: database
tags: [oracle-to-postgres, spec-first, static-analysis, python-stdlib, git-provenance, anti-circularity]

# Dependency graph
requires:
  - phase: 01-inventory-foundation
    provides: migration/analyze/inventory.json (routine coverage SSOT), migration/mapping/name-map.csv (PostgreSQL naming SSOT)
provides:
  - migration/spec/TEMPLATE.md — the spec skeleton every future package spec copies
  - migration/spec/CHECKLIST.md — the five SPEC-03 dimensions, machine-checkable
  - migration/spec/spec_lint.py — SPEC-02/SPEC-03 gate, cross-checked against Phase 1 SSOTs
  - migration/spec/trace_lint.py — HARN-05 gate, test-to-clause traceability + coverage report
  - migration/spec/provenance_lint.sh — git-ancestry anti-circularity gate (T-02-06)
affects: [02-03-test-schema, 02-04-spec-tests-mss-osag-dbprop-auth-tt-util, 02-05-spec-tests-osag-notify, 02-06-spec-tests-event-interface, 02-07-spec-ticket-interface, 02-08-tests-ticket-interface, 02-09-translate-batch1, 02-10-translate-notify, 02-11-translate-event-interface, 02-12-translate-ticket-interface, 02-13-integration]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Spec front-matter is a minimal YAML-lite block (flat key:value, no PyYAML dependency) parsed by a ~15-line hand-rolled parser, consistent with Phase 1's stdlib-only constraint (D-B)."
    - "Clause IDs (S-<PREFIX>-NNN) are permanent citation targets — spec_lint enforces uniqueness and shape, trace_lint resolves test citations against them, and clause numbering is documented as never-renumbered."
    - "SSOT cross-checks (name-map.csv, inventory.json) are skipped only for paths under a literal fixtures/ directory component — real specs (anything else) MUST resolve against the real SSOT or fail outright, closing the loophole a naive 'skip if not found' rule would have left."
    - "Both trace_lint.py and provenance_lint.sh are designed to run clean (0 found, exit 0) on a tree with nothing yet to check, so they can be wired into CI unconditionally from day one, before any spec/test/translation exists."

key-files:
  created:
    - migration/spec/TEMPLATE.md
    - migration/spec/CHECKLIST.md
    - migration/spec/README.md
    - migration/spec/spec_lint.py
    - migration/spec/trace_lint.py
    - migration/spec/provenance_lint.sh
    - migration/spec/tests/test_spec_lint.py
    - migration/spec/fixtures/good.example.md
    - migration/spec/fixtures/bad_missing_assumptions.example.md
    - migration/spec/fixtures/bad_missing_citation.example.md
  modified: []

key-decisions:
  - "SSOT cross-checks in spec_lint.py (pg_schema/pg_prefix vs name-map.csv, routine coverage vs inventory.json) are skipped ONLY for paths with a 'fixtures' path component, and are hard-required (fail if the package isn't found at all) for every other path — a mistyped oracle_package name in a real spec cannot silently pass."
  - "Clause and checklist-dimension content is rejected only when it is a BARE 'N/A' (nothing else on the line); 'N/A — reason' is accepted, matching SPEC-03's 'N/A is acceptable only when accompanied by a reason.'"
  - "trace_lint.py classifies an explicit CLI path argument as pgTAP-style unless a 'regress' path component is present, rather than requiring it to live under migration/test/pgtap/ — this lets ad hoc/temp-file probes (including the plan's own verify command, which uses /tmp/tl/...) be linted without relocating them."
  - "provenance_lint.sh's TEST-AMENDMENTS.md escape hatch was not itself created in this plan (no file yet needs it) — its exact ledger line shape (commit:<sha> file:<path> reason:<text>) is documented in README.md and implemented in the parser now, so the first future plan that needs the hatch does not have to invent the format."

requirements-completed: [SPEC-02, SPEC-03, HARN-05]

coverage:
  - id: D1
    description: "Spec template (TEMPLATE.md) and the SPEC-03 five-dimension checklist (CHECKLIST.md), each dimension tied to a named PITFALLS.md pitfall and to concrete Oracle-source evidence"
    requirement: "SPEC-03"
    verification:
      - kind: other
        ref: "bash -c 'grep -qF \"## Routines\"/\"## Clauses\"/\"## Checklist\"/\"## Assumptions / Unresolved\" TEMPLATE.md; grep -cE \"^### [0-9]\\.\" CHECKLIST.md == 5' (plan's Task 1 verify command)"
        status: pass
    human_judgment: false
  - id: D2
    description: "spec_lint.py rejects a spec missing its Assumptions/Unresolved content, a checklist dimension, a malformed/duplicate clause ID, a clause with no source citation, a citation pointing past end-of-file, an invented pg_schema/pg_prefix, or a dropped routine — cross-checked against the real migration/analyze/inventory.json and migration/mapping/name-map.csv"
    requirement: "SPEC-02"
    verification:
      - kind: unit
        ref: "migration/spec/tests/test_spec_lint.py (11 tests, all passing) — python3 -m unittest discover -s migration/spec/tests"
        status: pass
      - kind: other
        ref: "plan's Task 2 verify commands: fixtures/good.example.md passes, fixtures/bad_missing_assumptions.example.md and fixtures/bad_missing_citation.example.md both rejected"
        status: pass
    human_judgment: false
  - id: D3
    description: "trace_lint.py rejects a pgTAP assertion with no description, no leading clause ID, or a citation to a nonexistent clause, and rejects a test file for a package with no spec at all; prints an informational clause-coverage report; runs clean on an empty tree"
    requirement: "HARN-05"
    verification:
      - kind: other
        ref: "plan's Task 3 verify commands (empty-tree clean run + rejects an uncited assertion); additionally proven in isolation during implementation for the 'no leading clause ID' and 'cites nonexistent clause' cases specifically (see Deviations/Verification Trail below)"
        status: pass
    human_judgment: false
  - id: D4
    description: "provenance_lint.sh asserts (via git merge-base --is-ancestor) that a translation's spec-add and first-test-add commits precede the translation-add commit, rejects a translation commit that also modifies a test file for that package, honors the TEST-AMENDMENTS.md escape hatch, and runs clean on an empty tree"
    requirement: "HARN-05"
    verification:
      - kind: other
        ref: "plan's Task 3 verify commands (grep for merge-base --is-ancestor and TEST-AMENDMENTS); additionally end-to-end proven against four synthetic throwaway git repos during implementation covering: good ordering (pass), translation-predates-spec (rejected), translation-touches-test (rejected), and the TEST-AMENDMENTS.md escape hatch (honored) — see Deviations/Verification Trail below"
        status: pass
    human_judgment: false

# Metrics
duration: ~20min
completed: 2026-07-12
status: complete
---

# Phase 2 Plan 2: Spec Method, Test Harness & Pilot — Spec Template + Anti-Circularity Linters Summary

**Spec template, uniform SPEC-03 five-dimension checklist, and three linters (`spec_lint.py`, `trace_lint.py`, `provenance_lint.sh`) that make SPEC-02, SPEC-03, and HARN-05 mechanical exit-code properties of the repo rather than reviewer discipline.**

## Performance

- **Duration:** ~20 min
- **Started:** 2026-07-12T14:20:00Z (approx.)
- **Completed:** 2026-07-12T14:38:49Z
- **Tasks:** 3/3
- **Files modified:** 10 created

## Accomplishments

- `migration/spec/TEMPLATE.md` + `migration/spec/CHECKLIST.md`: the spec skeleton and the five SPEC-03 dimensions (empty-string/NULL, SELECT INTO strictness, exception codes, package state, FUNCTION vs PROCEDURE), each dimension citing its PITFALLS.md source and the exact Oracle-source evidence that answers it.
- `migration/spec/spec_lint.py`: rejects a spec that invents a PostgreSQL name, drops a public routine, skips a checklist dimension, leaves Assumptions/Unresolved empty, or cites a fabricated source line — proven against both the three required throwaway fixtures AND synthetic specs built against the REAL `MSS.OSAG_DBPROP` package data in `name-map.csv`/`inventory.json` (11 unit tests, all green).
- `migration/spec/trace_lint.py`: HARN-05 gate — a pgTAP assertion or expected-output test that doesn't cite a real spec clause ID is rejected; prints a clause-coverage report (informational, not a gate).
- `migration/spec/provenance_lint.sh`: the structural anti-circularity gate — `git merge-base --is-ancestor` proves a translation's spec and tests predate it; a translation commit may not also touch a test file except via the `TEST-AMENDMENTS.md` escape hatch. Proven end-to-end against four synthetic throwaway git repos (see Verification Trail below), not just asserted.

## Task Commits

Each task was committed atomically:

1. **Task 1: The spec template and the SPEC-03 uniform checklist** - `40754e8` (feat)
2. **Task 2: spec_lint.py — reject a spec that cheats** - `b769020` (feat)
3. **Task 3: trace_lint.py and provenance_lint.sh — make circular verification impossible** - `818568e` (feat)

**Plan metadata:** (this commit) `docs(02-02): complete spec method plan`

## Files Created/Modified

- `migration/spec/TEMPLATE.md` - the spec skeleton (front-matter + Routines/Clauses/Checklist/Assumptions-Unresolved)
- `migration/spec/CHECKLIST.md` - the five SPEC-03 dimensions, each tied to a PITFALLS.md pitfall
- `migration/spec/README.md` - authoring guide, derived-from-Oracle-source-only rule, linter reference table, TEST-AMENDMENTS.md format
- `migration/spec/spec_lint.py` - SPEC-02/SPEC-03 linter (stdlib-only Python 3.12)
- `migration/spec/trace_lint.py` - HARN-05 test-to-clause traceability linter + coverage report
- `migration/spec/provenance_lint.sh` - git-ancestry anti-circularity gate + TEST-AMENDMENTS.md escape hatch
- `migration/spec/tests/test_spec_lint.py` - 11-test unittest suite (fixtures + real-SSOT-data probes)
- `migration/spec/fixtures/good.example.md` - passing fixture (throwaway `ZZ.FIXTURE_PKG`)
- `migration/spec/fixtures/bad_missing_assumptions.example.md` - rejected: empty Assumptions/Unresolved
- `migration/spec/fixtures/bad_missing_citation.example.md` - rejected: citation past end-of-file

## Decisions Made

- **SSOT-loophole closure:** rather than silently skipping the name-map.csv/inventory.json cross-checks whenever a package isn't found (which would let a real spec with a typo'd `oracle_package` sail through), the linter distinguishes real specs from fixtures by path (`fixtures/` component present or absent). Real specs get a hard "package not found in SSOT" failure; only the three required throwaway fixtures (and any future linter test fixtures) are exempt. This was validated by writing temporary specs against the real `MSS.OSAG_DBPROP` package and confirming both a wrong `pg_schema` and a dropped routine are rejected using the actual `migration/mapping/name-map.csv` and `migration/analyze/inventory.json` on disk — not a synthetic stand-in.
- **provenance_lint.sh proven, not just asserted:** the plan's own verify commands for Task 3 only check for the *presence* of `merge-base --is-ancestor` and `TEST-AMENDMENTS` strings in the script, and only exercise the empty-tree path. Per this plan's `<critical_property>` instruction ("Prove it by feeding each one a deliberately bad input and observing non-zero exit. Do not assert that it would fail."), I additionally built four synthetic throwaway git repos during implementation (not committed anywhere) that exercised: (1) correct spec→test→translation ordering passing clean, (2) a translation committed before its spec/tests being rejected with the expected merge-base failure message, (3) a translation commit that also modifies a test file being rejected, and (4) the same case being permitted once logged in a `TEST-AMENDMENTS.md` ledger entry. All four behaved as designed.
- **trace_lint.py's "no leading clause ID" and "cites nonexistent clause" paths proven in isolation:** the plan's Task 3 verify command for `trace_lint.py` (the `/tmp/tl/mss__osag_dbprop__x.sql` case) actually exercises the "no spec found for package" rejection path first, since no real `migration/spec/mss.osag_dbprop.md` exists yet in this repo — it still produces the required non-zero exit, but not via the specific code path the `<done>` criteria describe ("rejects an assertion whose description carries no leading clause ID"). I additionally ran `trace_lint.lint_pgtap_file()` directly against a throwaway spec (via `SPEC_DIR` monkeypatch, not committed) to confirm the "no leading clause ID" violation and the "cites clause S-DBPROP-999 which does not exist" violation each fire correctly and independently. Both did.

## Deviations from Plan

None — plan executed exactly as written. The items above ("Decisions Made") are verification-rigor additions I performed beyond the plan's own verify commands, per the plan's explicit `<critical_property>` instruction to prove rejection rather than assert it; they did not require any code or file changes beyond what the plan specified, and no fixtures/files from these probes were committed (all probe repos and temp files were created under `/tmp` and deleted after use).

## Issues Encountered

None. The Phase 1 SSOT artifacts (`inventory.json`, `name-map.csv`) and `migration/README.md`'s documented conventions (D-A/D-B/D-C/D-D, the `package_in_name` naming rule, the cycle/collision semantics) were sufficient to build both linters without needing to re-derive anything. `migration/test/` (plan 02-01's harness, running in a parallel worktree) does not exist yet in this isolated worktree, so `trace_lint.py`'s filename convention (`<schema>__<pkg>__*.sql`) and directory layout (`migration/test/pgtap/`, `migration/test/regress/sql/`) were taken directly from this plan's own `read_first`/`action`/`verify` text rather than from 02-01's README — both linters were designed to degrace gracefully to "0 found, nothing to check" regardless of whether that tree exists yet, so this is not a blocking dependency.

## User Setup Required

None - no external service configuration required. Everything here is Python 3.12 stdlib + bash + git, matching Phase 1's D-B constraint.

## Next Phase Readiness

- `migration/spec/TEMPLATE.md`, `CHECKLIST.md`, and all three linters are ready for plan 02-04 (the first real specs: `MSS.OSAG_DBPROP`, `AUTH.OSAG_AUTH`, `TT.UTIL`) to consume immediately — copy the template, fill it from `ddl/src/**`, run `spec_lint.py` before committing.
- `trace_lint.py` and `provenance_lint.sh` are safe to wire into CI unconditionally starting now (both exit 0 on the current empty tree) — no future plan needs to gate on "does migration/test/ or migration/pgsql/ exist yet."
- `migration/spec/TEST-AMENDMENTS.md` does not exist yet by design (nothing needs it) — its exact line format is documented in `README.md` for whichever future plan first needs the escape hatch.
- No blockers. This plan's deliverable is infrastructure only — it does not write any real package spec, so `migration/spec/spec_lint.py` (run with no arguments) correctly reports "0 specs found... nothing to check" until 02-04 lands.

---
*Phase: 02-spec-method-test-harness-pilot*
*Completed: 2026-07-12*

## Self-Check: PASSED

All 10 claimed files verified present on disk (`migration/spec/TEMPLATE.md`,
`CHECKLIST.md`, `README.md`, `spec_lint.py`, `trace_lint.py`, `provenance_lint.sh`,
`tests/test_spec_lint.py`, `fixtures/good.example.md`,
`fixtures/bad_missing_assumptions.example.md`, `fixtures/bad_missing_citation.example.md`).
All 3 claimed task commit hashes (`40754e8`, `b769020`, `818568e`) verified present in
`git log --oneline --all`.
