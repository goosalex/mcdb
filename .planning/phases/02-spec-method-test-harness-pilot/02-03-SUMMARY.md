---
phase: 02-spec-method-test-harness-pilot
plan: 03
subsystem: database
tags: [postgresql-17, ora2pg, ddl-migration, pgtap, python3-stdlib, bash]

# Dependency graph
requires:
  - phase: 02-spec-method-test-harness-pilot
    provides: "migration/test/ dual test harness (bootstrap.sh, run-tests.sh, redgreen.sh) from plan 02-01"
provides:
  - "migration/test/build-template.sh -- the mcdb_tmpl TEMPLATE database, built from the real ddl/migrated/ schema"
  - "migration/test/SCHEMA-FIXES.md -- the ora2pg fix ledger (4 fixes, each with a Phase 5 action)"
  - "migration/test/fixtures/load_masterdata.py -- masterdata/ reference-data loader (HARN-03)"
  - "migration/pgsql/osag/osag_plog.sql -- the plog stub every pilot package calls on error paths"
affects: ["02-04", "02-05", "02-06", "02-07", "every later plan in phase 02 that translates a pilot package", "phase 04 bulk translation", "phase 05 container build"]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Schema fixes are additive files layered on top of ddl/migrated/, never edits to it (D-P7) -- fixes #1-#2 load BEFORE the base schema (roles/schemas a table statement needs to even attempt), fixes #3-#4 load AFTER (constraints that need the base tables to exist first)"
    - "Base-load error surfacing via line-number reconciliation: bootstrap/20_ddl.sh captures every failing statement's exact source line, diffs the set against a hardcoded expected-failure allowlist, and aborts hard on any discrepancy -- not a blanket ON_ERROR_STOP=off tolerance"
    - "NULL sentinel in masterdata CSVs is the literal quoted token \"NULL\", not an empty field -- COPY's NULL 'NULL' + FORCE_NULL(every column), evidence-based (grep-verified zero genuine empty fields across the pilot's schemas), not assumed"
    - "Circular FK ordering in fixture loads handled via SET CONSTRAINTS ALL DEFERRED inside one transaction (translating Oracle's disable/enable-constraint _pre.sql/_post.sql intent), not by executing the Oracle scripts' syntax directly"

key-files:
  created:
    - migration/test/build-template.sh
    - migration/test/bootstrap/10_schemas_roles.sql
    - migration/test/bootstrap/20_ddl.sh
    - migration/test/bootstrap/30_sequences.sql
    - migration/test/bootstrap/40_fixtures.sh
    - migration/test/schema-fixes/00_README.md
    - migration/test/schema-fixes/10_ora2pg_fixes.sql
    - migration/test/SCHEMA-FIXES.md
    - migration/test/fixtures/load_masterdata.py
    - migration/test/fixtures/PILOT-TABLES.md
    - migration/pgsql/osag/osag_plog.sql
    - migration/pgsql/osag/osag_plog.FINDINGS.md
  modified:
    - migration/test/.gitignore

key-decisions:
  - "tables/constraints.pg.sql (843 FK statements, non-deferrable) is deliberately NOT loaded -- it duplicates constraints/fk-constraints.pg.sql (same 843 constraints, DEFERRABLE), which is the version fixtures/load_masterdata.py's SET CONSTRAINTS ALL DEFERRED strategy requires"
  - "postgresadmin role and checklist schema (2 ora2pg gaps blocking, respectively, all 116 users/*.sql files and 43 checklist.* table statements) are fixed in bootstrap/10_schemas_roles.sql itself, not in schema-fixes/, since they must exist before tables.pg.sql can even attempt those statements"
  - "3 bireader.* views (loaded by views.pg.sql before schema-fixes runs) are dropped and recreated verbatim around the 15 FK column-type fixes, since PostgreSQL has no CASCADE option for ALTER COLUMN TYPE"
  - "4 non-pilot views.pg.sql errors (mc.* interval/trunc issues, a sys_nc00008$ ghost column, a materialized-view ordering gap) are recorded in SCHEMA-FIXES.md and deliberately left broken, per the plan's own scope boundary"
  - "ddl/migrated/grants/, helpers/, and mviews/ are out of scope for this plan -- not required for pilot tables to exist and be queryable under a superuser connection, deferred to Phase 5's full container build"

requirements-completed: [HARN-03]

coverage:
  - id: D1
    description: "mcdb_tmpl template database built from the real ddl/migrated/ ora2pg schema, with the ON_ERROR_STOP OFF landmine neutralized so the load fails hard on error instead of silently skipping broken statements (T-02-09)"
    requirement: "HARN-03"
    verification:
      - kind: integration
        ref: "bash migration/test/build-template.sh (full rebuild from scratch, ~16s, idempotent -- re-run twice in sequence during this plan, both succeeded)"
        status: pass
    human_judgment: false
  - id: D2
    description: "Every pilot table, constraint, and sequence queryable in mcdb_tmpl (auth.login, auth.profile, auth.user_permission, auth.consented_term, mcaudit.record, mss.key, mss.value, mss.news_entry, tt.ticket, tt.event; tt.event_sequence, tt.ticket_sequence, auth.seq_profile, auth.seq_user_permission)"
    verification:
      - kind: integration
        ref: "10 pilot-table SELECT ... WHERE false checks + 4 sequence nextval() checks against mcdb_tmpl, all OK"
        status: pass
    human_judgment: false
  - id: D3
    description: "Every ora2pg fix is ledgered with an explicit Phase 5 action (SCHEMA-FIXES.md)"
    verification:
      - kind: unit
        ref: "test -s migration/test/SCHEMA-FIXES.md && grep -qi 'Phase 5 action' migration/test/SCHEMA-FIXES.md"
        status: pass
    human_judgment: false
  - id: D4
    description: "masterdata/ reference fixtures seeded into mcdb_tmpl's five pilot schemas (HARN-03)"
    requirement: "HARN-03"
    verification:
      - kind: integration
        ref: "python3 migration/test/fixtures/load_masterdata.py --db mcdb_tmpl --schemas AUTH TT MSS MCAUDIT OSAG -- 82 tables, 3400 rows, re-run twice (idempotency proven)"
        status: pass
    human_judgment: false
  - id: D5
    description: "plog stub loads cleanly, is observable (a test can assert a specific error path logged a specific message), exposes exactly 12 routines (AuditUsage deliberately absent), and performs no transaction control (callable from inside a FUNCTION body)"
    verification:
      - kind: integration
        ref: "CALL osag.osag_plog_err('pilot-canary') -> 1 matching row in osag.plog_stub_log; CALL from inside a pg_temp FUNCTION body succeeds; pg_proc surface count = 12; osag_plog_auditusage absent"
        status: pass
    human_judgment: false
  - id: D6
    description: "run-tests.sh (plan 02-01's harness) still works end-to-end now that mcdb_tmpl is a real template, not the placeholder --bare mode 02-01 was forced to use"
    verification:
      - kind: integration
        ref: "bash migration/test/run-tests.sh -> _canary.canary PASS, TOTAL: 1 packages, 1 pass, 0 fail, exit 0"
        status: pass
    human_judgment: false

duration: ~30min
completed: 2026-07-12
status: complete
---

# Phase 2 Plan 3: Real ora2pg Schema, Fixtures & plog Stub Summary

**Built the mcdb_tmpl template from the actual ora2pg-converted ddl/migrated/ schema (not a fixture), fixed and ledgered 4 genuine ora2pg export gaps, seeded 82 masterdata reference tables (3400 rows), and shipped an observable, transaction-control-free plog stub.**

## Performance

- **Duration:** ~30 min (session started ~14:42Z per the preceding commit in git log, task commits landed 15:07:40Z-15:08:01Z, plus final documentation/state work after)
- **Tasks:** 3/3
- **Files modified:** 12 created, 1 modified (.gitignore)

## Accomplishments
- `build-template.sh` loads the REAL `ddl/migrated/` schema (548 tables, 843 FK constraints, 18 check constraints, 246 pilot-schema tables) end-to-end with errors surfaced, never swallowed: `tables.pg.sql` loads STRICT (`ON_ERROR_STOP=on`, proven to abort hard on the first error) and is expected/verified zero-error after two schema fixes; constraints and views load in inventory mode, with every failure's exact source line number diffed against a hardcoded expected-failure allowlist, aborting the whole build on any discrepancy from what's ledgered
- Found and fixed 4 genuine ora2pg gaps, every one recorded in `SCHEMA-FIXES.md` with root cause and an explicit Phase 5 action: a missing `postgresadmin` role (blocks all 116 `users/*.sql` files), a missing `checklist` schema (blocks 43 table statements), 15 FK constraints with `numeric`/`bigint` type mismatches (including 3 `bireader.*` views that had to be dropped and recreated around the fix, since PostgreSQL has no CASCADE for `ALTER COLUMN TYPE`), and 3 CHECK constraints ora2pg's line-based conversion silently truncated (reconstructed from `ddl/generated/check-constraints.oracle.sql`, the pre-conversion Oracle source)
- Ported all 30 `ddl/generated/sequences/*.sql` files (309 sequences) since `ddl/migrated/` ships none — the only Oracle-only clause found was `ORDER` (dropped; no PostgreSQL RAC equivalent needed)
- `load_masterdata.py` seeds 82 of 83 candidate reference tables (3400 rows) into the pilot's 5 schemas via `COPY`, overturning the plan's own empty-string-vs-NULL assumption with grep-verified evidence: the real CSVs use a literal `"NULL"` token, not an empty field, so `NULL 'NULL'` + `FORCE_NULL` is the correct policy, not `NULL ''`
- `osag_plog.sql` ships 12 of 13 `OSAG_PLOG` routines as an observable stub (AuditUsage deliberately absent, XCUT-06), proven callable from inside a `FUNCTION` body — the one property that would have silently poisoned every pilot package if gotten wrong
- Confirmed `migration/test/run-tests.sh` (plan 02-01's harness) now runs end-to-end against the real `mcdb_tmpl` template, not the `--bare` placeholder 02-01 was forced to use

## Task Commits

Each task was committed atomically:

1. **Task 1: Load the real ora2pg schema with errors surfaced, and fix what the pilot needs** - `20315ef` (feat)
2. **Task 2: Seed realistic reference data from masterdata/** - `23ac079` (feat)
3. **Task 3: The plog stub — observable enough to assert on, throwaway by design** - `68b6abe` (feat)

**Plan metadata:** (this commit, made after this SUMMARY)

## Files Created/Modified
- `migration/test/build-template.sh` - orchestrates the full mcdb_tmpl build in strict dependency order, idempotent (unmarks IS_TEMPLATE before rebuilding), asserts zero disabled triggers (T-02-11) before marking the result as a template
- `migration/test/bootstrap/10_schemas_roles.sql` - postgresadmin role bootstrap + all 116 `ddl/migrated/users/*.sql` files via `\ir` + the reconstructed checklist schema fix
- `migration/test/bootstrap/20_ddl.sh` - loads tables/constraints/views with the `\set ON_ERROR_STOP OFF` directive stripped and `-v ON_ERROR_STOP=on` forced; line-number reconciliation against a hardcoded expected-failure allowlist
- `migration/test/bootstrap/30_sequences.sql` - all 30 `ddl/generated/sequences/*.sql` files ported (309 sequences, `ORDER` clause dropped)
- `migration/test/bootstrap/40_fixtures.sh` - calls `load_masterdata.py` from `build-template.sh`
- `migration/test/schema-fixes/00_README.md` - explains the fix-file layout and why line-number reconciliation, not blanket error tolerance
- `migration/test/schema-fixes/10_ora2pg_fixes.sql` - the 15 FK type fixes + 3 dropped/recreated views + 3 reconstructed CHECK constraints, applied after the base load
- `migration/test/SCHEMA-FIXES.md` - the full ledger: 4 fixes with Phase 5 actions, plus every deliberately-unfixed failure and why
- `migration/test/fixtures/load_masterdata.py` - Python 3.12 stdlib masterdata loader, COPY-based, idempotent (TRUNCATE-before-load)
- `migration/test/fixtures/PILOT-TABLES.md` - which tables loaded, row counts, the NULL-token policy and its evidence, the mss.scope skip
- `migration/pgsql/osag/osag_plog.sql` - the plog stub (12 routines)
- `migration/pgsql/osag/osag_plog.FINDINGS.md` - what the stub does NOT do, the rollback limitation, and the Phase 3 (XCUT-02) replacement contract
- `migration/test/.gitignore` - added `.build-scratch/` (runtime scratch directory used by `20_ddl.sh` and `load_masterdata.py`)

## Decisions Made
- Skipped `tables/constraints.pg.sql` entirely (duplicate, non-deferrable FK export) in favor of `constraints/fk-constraints.pg.sql` (deferrable) — loading both would produce 843 duplicate-constraint errors for zero benefit, and the masterdata loader's deferred-constraint strategy specifically needs the deferrable version.
- Placed the `postgresadmin`/`checklist` fixes in `bootstrap/10_schemas_roles.sql` rather than `schema-fixes/`, since D-P7's "fixes applied after the base load" framing assumes the base tables already exist to be fixed — these two gaps block statements from ever running at all, so they must be resolved before the base load, not after.
- Reconstructed the 3 lost CHECK constraints from `ddl/generated/check-constraints.oracle.sql` (the pre-ora2pg-conversion Oracle source) rather than guessing at the missing logic — the Oracle source has the complete, correctly-terminated text.
- Used line-number-based reconciliation in `20_ddl.sh` (capture every failure's exact source line, diff against a hardcoded expected set, abort on any mismatch) instead of either (a) aborting the whole build on the first constraint/view error (which would make the base-load/schema-fixes split from D-P7 unworkable) or (b) tolerating all errors silently (the exact landmine this plan exists to defuse). This makes every constraint/view failure an explicitly ledgered, printed, and verified discrepancy rather than a swallowed one.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Plan's own Task 2 verify command references a nonexistent table `tt.ticket_status`**
- **Found during:** Preparing to run Task 2's automated verify block
- **Issue:** The plan's `<verify>` block for Task 2 counts rows via `SELECT ... + (SELECT count(*) FROM tt.ticket_status)`. No `tt.ticket_status` table exists anywhere in the loaded schema (or in Oracle's own DDL) — the actual ticket-status lookup table, and the one `masterdata/TT/status.csv` maps to, is `tt.status`. This mirrors the precedent recorded in 02-01-SUMMARY.md (a shell-quoting bug in that plan's own verify script) — the plan text itself, not the deliverable, was wrong.
- **Fix:** Ran the equivalent verification using `tt.status` in place of `tt.ticket_status`; the underlying capability (masterdata rows present and countable) is unaffected by the plan's typo.
- **Files modified:** None (verify-script text is not a repo artifact)
- **Verification:** `SELECT (SELECT count(*) FROM auth.authtype) + (SELECT count(*) FROM tt.event_type) + (SELECT count(*) FROM tt.status)` → `146`, `MASTERDATA_ROWS=146`
- **Committed in:** N/A

**2. [Rule 1 - Bug] Plan's own Task 3 verify commands use a database name that fails bootstrap.sh's own safety gate**
- **Found during:** Preparing to run Task 3's automated verify blocks
- **Issue:** The plan's `<verify>` blocks use `--db mcdb_plogtest`. `bootstrap.sh`'s hard name-allowlist (T-02-01, `^mcdb_(test|tmpl|harness)[a-z0-9_]*$`) rejects `mcdb_plogtest` — after `mcdb_`, the remaining text `plogtest` does not start with `test`, `tmpl`, or `harness`. This is the same class of pre-existing-plan-authoring gap as deviation #1 above.
- **Fix:** Ran the equivalent verification using `mcdb_test_plog` (which matches the allowlist: `mcdb_` + `test` + `_plog`) instead. The underlying capability (plog stub loads/observable/callable-from-function/surface-count) is unaffected.
- **Files modified:** None
- **Verification:** All 4 of Task 3's verify checks passed against `mcdb_test_plog`: `PLOG_STUB_LOADS`, `PLOG_OBSERVABLE`, `PLOG_CALLABLE_FROM_FUNCTION`, `PLOG_SURFACE_OK`
- **Committed in:** N/A

**3. [Rule 3 - Blocking] `build-template.sh` could not rebuild an already-built `mcdb_tmpl` (fails "cannot drop a template database")**
- **Found during:** Re-running `build-template.sh` a second time (proving idempotency) after the first successful build had marked `mcdb_tmpl` as `IS_TEMPLATE true`
- **Issue:** PostgreSQL refuses `DROP DATABASE` on any database with `datistemplate=true`. Since step 6 of `build-template.sh` itself sets this flag on every successful build, a second run of the same idempotent script self-blocked on its own prior output.
- **Fix:** `build-template.sh` now checks, before calling `bootstrap.sh --bare`, whether its target database already exists and is marked as a template, and issues `ALTER DATABASE ... IS_TEMPLATE false` first if so. Guarded by the same name-allowlist regex as `bootstrap.sh` (T-02-01), reimplemented locally since this ALTER statement is issued directly by `build-template.sh`, not routed through `bootstrap.sh`.
- **Files modified:** `migration/test/build-template.sh`
- **Verification:** Ran `build-template.sh` twice in direct succession; both runs succeeded (second run: ~16s, full rebuild, all downstream verify checks re-passed)
- **Committed in:** `20315ef` (Task 1 commit — the fix landed before Task 1's commit, since it was discovered during Task 1's own verification)

---

**Total deviations:** 3 auto-fixed (2 plan-authoring bugs in verify-script text, 1 blocking self-inflicted idempotency issue)
**Impact on plan:** None affected any deliverable's correctness; all three were necessary to reach a genuine, non-fabricated PASS on the plan's stated verification, or to make the plan's own idempotency promise ("safe to re-run") actually true. No scope creep.

## Issues Encountered
None beyond the three deviations above, which were resolved inline during verification.

## User Setup Required
None — no new system packages or external services required (pgTAP/orafce/pg_prove were already installed in plan 02-01).

## Next Phase Readiness
- `mcdb_tmpl` exists, is a genuine PostgreSQL template (`datistemplate=true`), and clones in ~instant time via `bootstrap.sh --template mcdb_tmpl` (now the default `bootstrap.sh` mode, since `mcdb_tmpl` exists) — every later plan/wave in this phase can now build on isolated, pre-seeded databases without re-loading ~9.7k lines of DDL or re-running the masterdata load.
- `run-tests.sh` was confirmed working end-to-end against the real template (previously only exercised against `--bare` in 02-01, since no template existed yet).
- `redgreen.sh`'s full RED→GREEN cycle (deferred in 02-01, since it needs a real template AND a real `--install DIR` of translated objects) can now be exercised for the first time by whichever plan lands the first pilot package's translation — the template half of that dependency is satisfied.
- `SCHEMA-FIXES.md` and `osag_plog.FINDINGS.md` are the two documents later plans (and Phase 3/5) most need to read before writing pilot package specs/translations: the former lists every schema quirk a pilot spec might trip on, the latter is the exact contract Phase 3's XCUT-02 must satisfy when replacing the plog stub.
- One masterdata/schema mismatch (`mss.scope`, documented in `PILOT-TABLES.md`) is flagged but not blocking — no pilot package or table dependency references it.

---
*Phase: 02-spec-method-test-harness-pilot*
*Completed: 2026-07-12*

## Self-Check: PASSED

All 12 created/modified files confirmed present on disk; all 3 task commits (`20315ef`,
`23ac079`, `68b6abe`) confirmed present in `git log --oneline --all`. No missing items.
