---
phase: 01-inventory-foundation
plan: 01
subsystem: database
tags: [python, oracle, plsql, static-analysis, migration-tooling]

# Dependency graph
requires: []
provides:
  - "migration/analyze/plsql_lex.py — comment/string-stripping lexer + object header scanner"
  - "migration/analyze/inventory.py — inventory generator with --check reconciliation"
  - "migration/analyze/inventory.json — the object inventory (INV-01)"
  - "migration/analyze/expected_counts.json — reconciliation contract"
affects: ["01-inventory-foundation plan 02 (name-map + dependency graph)", "phase 2 (spec derivation)", "phase 3 (cross-cutting semantics decisions)"]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Comment/string-stripping lexer as a character-state machine (never regex-based comment removal)"
    - "Length-preserving blanking so line numbers survive strip_noise"
    - "Absolute file line numbers via a single scalar shift applied per object (spec_offset for routines, body_offset for everything else)"
    - "calls_out_raw captures candidate call references without resolving them — resolution deferred to plan 02"

key-files:
  created:
    - migration/README.md
    - migration/analyze/plsql_lex.py
    - migration/analyze/inventory.py
    - migration/analyze/expected_counts.json
    - migration/analyze/inventory.json
    - migration/analyze/tests/test_plsql_lex.py
    - migration/analyze/tests/test_inventory.py
  modified: []

key-decisions:
  - "schemas count in expected_counts.json is 23, not the plan's stated 21 — ddl/src/triggers/APPID.sql and STOP.sql declare objects in schemas absent from every package spec; hard-gated on the lexer-derived truth, not the incomplete manual count"
  - "reconcile() recomputes structural counts directly from result['objects'] rather than trusting the separately-stored counts snapshot, so the --check gate can actually detect a removed object"
  - "package_state/private_routines line numbers are computed relative to each object's own text slice, then shifted by a single scalar offset (start_line - 1) at object-build time, rather than threading absolute offsets through every marker-extraction helper"

patterns-established:
  - "Every marker/routine extraction helper returns line numbers relative to its own input text; build_inventory() is solely responsible for converting those to absolute file lines via shift_markers()/shift_line_field()"

requirements-completed: [INV-01]

coverage:
  - id: D1
    description: "PL/SQL lexer strips comments/strings before any marker matching, preserving line numbers"
    requirement: "INV-01"
    verification:
      - kind: unit
        ref: "migration/analyze/tests/test_plsql_lex.py#TestStripNoise (6 tests) + #TestCorpusWideStructuralInvariants.test_16_line_count_preserved_across_corpus"
        status: pass
    human_judgment: false
  - id: D2
    description: "Object header scanner finds every package spec/body, standalone procedure, trigger object (including quoted-identifier headers), and EXECUTE-IMMEDIATE-wrapped type"
    requirement: "INV-01"
    verification:
      - kind: unit
        ref: "migration/analyze/tests/test_plsql_lex.py#TestScanObjects (6 tests) + #test_17_trigger_objects_total_53 + #test_18_types_both_wrapped_in_dynamic_sql"
        status: pass
    human_judgment: false
  - id: D3
    description: "Inventory generator extracts public routine signatures (with overload discrimination), transaction/state/marker facts, and raw cross-object call references (both qualified and bare shapes) per object"
    requirement: "INV-01"
    verification:
      - kind: unit
        ref: "migration/analyze/tests/test_inventory.py (19 tests, all classes)"
        status: pass
    human_judgment: false
  - id: D4
    description: "Reconciliation (--check) exits 0 against the current tree and exits non-zero when an object is artificially removed from the parse result"
    requirement: "INV-01"
    verification:
      - kind: unit
        ref: "migration/analyze/tests/test_inventory.py#TestReconciliation.test_15_check_passes_then_fails_when_object_removed"
      - kind: integration
        ref: "python3 migration/analyze/inventory.py --check (exit 0 against current tree)"
        status: pass
    human_judgment: false

duration: 20min
completed: 2026-07-11
status: complete
---

# Phase 01 Plan 01: Oracle Source Lexer + Object Inventory Summary

**Built a comment/string-stripping PL/SQL lexer and inventory generator that catalogs all 105 top-level programmatic objects in `ddl/src` (48 packages, 2 procedures, 53 trigger objects, 2 dynamic-SQL-wrapped types) with routine signatures, transaction markers, and raw call references, gated by a reconciliation check that can actually fail.**

## Performance

- **Duration:** ~20 min
- **Started:** 2026-07-11T21:14:00Z (approx., first file reads)
- **Completed:** 2026-07-11T21:32:33Z
- **Tasks:** 2
- **Files modified:** 7 (all new)

## Accomplishments

- `plsql_lex.py`: a length-preserving `strip_noise()` character-state machine that blanks line comments, block comments, and single-quoted string literals (preserving doubled-quote escapes and newlines), plus `scan_objects()` (finds `CREATE OR REPLACE {PACKAGE[ BODY]|PROCEDURE|FUNCTION|TRIGGER|TYPE}` headers, including quoted-identifier headers and the two `EXECUTE IMMEDIATE`-wrapped `TYPE` objects) and `scan_synonyms()` (public synonym mappings, tolerating the one malformed unqualified synonym target).
- `inventory.py`: walks the five scanned source directories, pairs package specs↔bodies, and emits per-object metadata — public routine signatures (overload-discriminated by parameter type list), private body-only routines, package-level mutable state, `has_commit`/`has_rollback`/`autonomous_transaction` with line sites, `DBMS_*`/`UTL_*` call sites, `RAISE_APPLICATION_ERROR` codes, `%TYPE`/`%ROWTYPE` dictionary-vs-project classification, `SELECT INTO` sites, and `calls_out_raw` (both schema-qualified 3-part and public-synonym 2-part call shapes, deliberately unresolved — that's plan 02's job).
- `inventory.json`: 105 top-level objects (48 packages, 2 procedures, 53 triggers, 2 types), all four known dynamic-SQL objects (`SYS.OSAG_TABLE_REDEFINITION`, `REPORT.OSAG_CHANNEL`, `TT.EVENT_INTERFACE`, `MCDB_CHECKS.CONSISTENCY`) flagged `static_resolution: "incomplete"` with reasons; `excluded_files` names `ticketing-interfaces.md` so the 48-vs-49-body discrepancy is answered by the artifact.
- `expected_counts.json` + `inventory.py --check`: reconciles structural counts (recomputed live from `result['objects']`, not a stale snapshot) and exits non-zero when an object is missing — proved by a unit test that removes an object and asserts the failure, not just by hand-waving that it would fail.
- 38 unit tests total (19 lexer, 19 inventory) pinned against real `ddl/src` files.

## Task Commits

1. **Task 1: PL/SQL lexer — strip comments/strings, scan object headers** - `9547f04` (feat)
2. **Task 2: Inventory generator — per-object metadata and raw call references** - `f5ed888` (feat)

_Both tasks were TDD: tests written first, confirmed failing (ModuleNotFoundError) before the corresponding module existed, then implementation added until green._

## Files Created/Modified

- `migration/README.md` - migration/ tree purpose, D-A/D-B/D-C/D-D decisions, "everything here is generated" rule
- `migration/.gitignore` - keeps `__pycache__/` out of the tree
- `migration/analyze/plsql_lex.py` - lexer library (strip_noise, scan_objects, scan_synonyms, normalize)
- `migration/analyze/inventory.py` - inventory generator (CLI: default mode writes JSON, `--check` reconciles)
- `migration/analyze/expected_counts.json` - reconciliation contract
- `migration/analyze/inventory.json` - the object inventory (INV-01 artifact)
- `migration/analyze/tests/test_plsql_lex.py` - 19 lexer unit tests
- `migration/analyze/tests/test_inventory.py` - 19 inventory unit tests

## Decisions Made

- **schemas = 23, not the plan's ground-truth 21.** `ddl/src/triggers/APPID.sql` and `STOP.sql` declare trigger objects in schemas `APPID` and `STOP`, neither of which appears in any package spec. The plan's ground-truth table's "21 distinct schemas" turns out to have been derived from `ddl/src/pkg` (package specs) only, and doesn't account for trigger-only schemas. Verified directly: `grep`-extracting schema names from every `CREATE OR REPLACE PACKAGE` header yields exactly the plan's 21-item list; adding the two trigger files' schemas brings the true scanned-corpus total to 23. Per the execution rules ("hard-gate on structural counts your lexer derives... do not hard-gate on any count inherited from the roadmap/plan"), `expected_counts.json` hard-gates on 23, with an inline `_schemas_note` explaining the discrepancy.
- **`reconcile()` recomputes counts from `result['objects']` live**, rather than trusting the `result['counts']` dict computed once at build time. This was necessary to make the `--check` gate genuinely able to fail: the plan's Test 15 requires that artificially removing an object makes `--check` exit non-zero, and a naive implementation that only compared the precomputed `counts` snapshot would not have noticed the object was gone.
- **Absolute line numbers via single-scalar shift.** Every marker/routine-extraction helper (`find_commit_rollback`, `_parse_routine_headers`, `find_package_state`, etc.) computes line numbers relative to whatever text slice it's handed. `build_inventory()` is the only place that converts these to real file line numbers, via `shift_markers()`/`shift_line_field()` applied with the object's own `start_line - 1` (spec's start_line for `routines[]`, body's start_line for everything else, since `package_state`/`private_routines`/markers all come from the body slice). This keeps every helper function's unit tests simple (they test relative-to-input-text semantics, which is what a synthetic snippet naturally exercises) while the integration path guarantees absolute correctness — verified line-for-line against `sys_decom_authhost.sql` (`raise_application_error` at absolute line 13, matching the source) and `auth_osag_auth.sql` (`SELECT ... INTO` at absolute line 21, matching the source).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Task 1's regression fixture file doesn't exhibit the property it's meant to test**
- **Found during:** Task 1 (writing test_plsql_lex.py Test 5)
- **Issue:** The plan names `ddl/src/pkgb/tt_ticket_interface.sql` as the fixture for proving comment-stripped `RAISE_APPLICATION_ERROR` counts are strictly less than the naive raw count. Verified via `grep -o`: this file contains **zero** occurrences of `RAISE_APPLICATION_ERROR` at all, so "stripped < naive" (0 < 0) can never hold — the test as specified is unsatisfiable against reality, not a case of the lexer being wrong.
- **Fix:** Surveyed the corpus for a file that actually demonstrates comment-inflated counts. `ddl/src/pkgb/auth_osag_auth_passport.sql` has 29 raw occurrences, two of which (lines 670, 1564) are commented out with a leading `--` — a real, verifiable instance of the exact property the test is designed to catch. Used it instead, with an inline comment explaining the substitution.
- **Files modified:** `migration/analyze/tests/test_plsql_lex.py`
- **Verification:** `test_05_regression_comment_stripped_count_below_naive_count` passes (27 stripped < 29 naive).
- **Committed in:** `9547f04` (Task 1 commit)

**2. [Rule 1 - Bug] `.gitkeep` placeholder swept into `excluded_files`**
- **Found during:** Task 2 (running `inventory.py --check` against the real tree)
- **Issue:** `ddl/src/proc/.gitkeep` (a git placeholder keeping the near-empty `proc/` directory tracked) was being reported in `excluded_files` alongside the genuine non-SQL document `ticketing-interfaces.md`, which is not what that field is for and would have made `--check` fail against the plan's stated exclusion list.
- **Fix:** `discover()` now skips dotfiles (`p.name.startswith(".")`) entirely before classifying files as `.sql` vs. excluded — a hidden git-tracking artifact is not Oracle source and isn't part of the translation scope at all.
- **Files modified:** `migration/analyze/inventory.py`
- **Verification:** `excluded_files` now contains exactly `["ticketing-interfaces.md"]`; `--check` passes.
- **Committed in:** `f5ed888` (Task 2 commit)

**3. [Rule 1 - Bug] Reported line numbers were relative to each object's text slice, not the source file**
- **Found during:** Task 2 (manual spot-check of generated `inventory.json` against the source files it was derived from)
- **Issue:** All `find_*` marker-extraction functions compute line numbers via `text.count('\n', 0, offset) + 1` against whatever text they're handed — but `build_inventory()` calls them with each object's own carved-out slice (which starts at that object's `header.start_line`, not file line 1). The reported line numbers were therefore off by `(start_line - 1)` for every object whose body doesn't start at file line 1 — e.g. `AUTH.OSAG_AUTH`'s first `SELECT ... INTO` was reported at line 19 when the actual source line is 21.
- **Fix:** Added `shift_markers()`/`shift_line_field()` applied once, at the single point in `build_inventory()` where each helper's output is assembled into the final object record, using the correct base offset per source (spec's `start_line` for `routines[]`, body's `start_line` for `private_routines`/`package_state`/all transaction-and-error markers). Also restructured `find_package_state()` to operate on bounds within the full body text rather than a pre-sliced declare-section substring, so it needs only the same single shift level as everything else instead of a second, harder-to-track inner offset.
- **Files modified:** `migration/analyze/inventory.py`
- **Verification:** Regenerated `inventory.json` and spot-checked against source: `SYS.DECOMAUTHHOST`'s first `raise_application_error(-20000, ...)` now reports line 13, matching `sed -n '13p' ddl/src/proc/sys_decom_authhost.sql`; `AUTH.OSAG_AUTH`'s `SELECT contact_id INTO v_contact_id` now reports line 21, matching the source. All 38 unit tests still pass (the unit-level `find_*` tests exercise relative-to-input semantics directly, which is unaffected by this fix — only the integration path in `build_inventory()` changed).
- **Committed in:** `f5ed888` (Task 2 commit, fixed before commit — not a follow-up)

**4. [Rule 1 - Bug] schemas ground-truth count corrected from 21 to 23**
- Documented above under "Decisions Made" — same root cause class as the discrepancies flagged in this plan's own `verified_ground_truth` note (a manually-derived count that didn't account for the full scanned scope). Fixed by gating on the lexer-derived truth (23) rather than the plan's stated figure, with the discrepancy documented inline in `expected_counts.json`.

---

**Total deviations:** 4 auto-fixed (2 test-fixture corrections, 1 exclusion-list bug, 1 line-number correctness bug). All were necessary for correctness of the generator/tests; none represent scope creep.
**Impact on plan:** None of these weakened any gate — `--check` still hard-gates on exact structural counts (now the verified-correct ones) and the reconciliation test still proves the gate can fail. The line-number fix specifically strengthens correctness of an artifact that plan 02 and Phase 4 will rely on for locating call sites and markers in the original source.

## Issues Encountered

None beyond the deviations documented above.

## User Setup Required

None - no external service configuration required. Python 3.12 stdlib only, already present on the box.

## Next Phase Readiness

- `inventory.json` is ready to be consumed by plan 02 (name-map + dependency graph): `calls_out_raw` carries both call shapes needed to resolve edges, `routines[]`/`private_routines[]` give the full object roster for the name map, and `synonyms` gives the public-synonym mappings needed to resolve bare-shape calls.
- All four dynamic-SQL objects are flagged `static_resolution: "incomplete"` with `reasons[]`, satisfying ROADMAP success criterion 4 (to be completed end-to-end once plan 02's graph explicitly surfaces these as unresolvable edges).
- No blockers. `migration/regenerate.sh` (plan 02) can wrap `inventory.py` + the plan 02 generators into one regeneration command as planned.

---
*Phase: 01-inventory-foundation*
*Completed: 2026-07-11*
