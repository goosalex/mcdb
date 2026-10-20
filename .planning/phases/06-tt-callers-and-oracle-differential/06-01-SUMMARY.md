---
phase: 06-tt-callers-and-oracle-differential
plan: 01
subsystem: database
tags: [postgresql, plpgsql, oracle-migration, maintsync, mcaudit, pgtap, spec-first-translation]

requires:
  - phase: 02-spec-method-test-harness-pilot
    provides: "spec method + linters, dual harness, plog stub, mcdb_tmpl template"
provides:
  - "migration/spec/mc.osag_maintsync.md (21 clauses) and migration/spec/mcaudit.osag_audit.md (15 clauses)"
  - "migration/pgsql/mc/osag_maintsync.sql: 4 PROCEDUREs, GREEN 109/109 pgTAP + 1/1 regress"
  - "migration/pgsql/mcaudit/osag_audit.sql: 4 PROCEDUREs with INOUT ids, GREEN 67/67 pgTAP + 1/1 regress"
  - "migration/test/schema-fixes/26_p0601_fixes.sql: mcaudit.record zitadel_user_* columns ora2pg dropped"
affects: [06-03 (GUMA2.OSAG_GUMA calls add_record_raw), 06-05/06-06 (differential scenarios), 06-07 (integration, template rebuild, pg_cron)]

tech-stack:
  added: []
  patterns:
    - "Corrected Oracle defects specified as clauses citing the wrong Oracle line, marked DEVIATION(ORACLE-BUG) at the translation site, tests assert the corrected contract"
    - "INOUT results captured in pgTAP through pg_temp helper functions writing a temp table"
    - "Regress goldens rendered through psql itself (stand-in SELECT ... FROM (VALUES ...)) with \\set VERBOSITY terse so no CONTEXT line numbers are pinned"

key-files:
  created:
    - migration/spec/mc.osag_maintsync.md
    - migration/spec/mcaudit.osag_audit.md
    - migration/test/pgtap/mc__osag_maintsync__spec.sql
    - migration/test/pgtap/mcaudit__osag_audit__spec.sql
    - migration/test/regress/sql/mc__osag_maintsync__errors.sql (+ expected/.out)
    - migration/test/regress/sql/mcaudit__osag_audit__errors.sql (+ expected/.out)
    - migration/test/schema-fixes/26_p0601_fixes.sql
    - migration/pgsql/mc/osag_maintsync.sql
    - migration/pgsql/mc/osag_maintsync.FINDINGS.md
    - migration/pgsql/mcaudit/osag_audit.sql
    - migration/pgsql/mcaudit/osag_audit.FINDINGS.md
  modified:
    - migration/test/SCHEMA-FIXES.md (fix #10 + the empty mc.maintenance_status note)
    - migration/spec/TEST-AMENDMENTS.md (A-009)
    - migration/db/pg.sh (coordinator's 1a8c31c cherry-picked; my earlier d5cd932 superseded)

key-decisions:
  - "update_single_isp_link is corrected, not mimicked: missing p_isp_link_id predicate, `= NULL`, and the batch 'change needed' filter copied into a SELECT INTO whose NO_DATA_FOUND handler meant 'no interface' (flip-flop to unknown on every call)"
  - "update_single_host corrected too: same copied filter made the nothing-to-do case an ERR log line and the IF at line 222 dead code; data outcome unchanged"
  - "Maintenance-window join kept as four textual copies (instruction); a shared view is a recorded follow-up"
  - "mcaudit translation uses explicit parameter types, not %TYPE, so the file installs on a template without 26_p0601_fixes.sql (only the INSERT fails there)"
  - "mc.maintenance_status rows are inserted by the test itself (ON CONFLICT DO NOTHING) because the template loads no MC masterdata"

requirements-completed: [HARN-04, HARN-05]

duration: ~2h
completed: 2026-10-20
status: complete
---

# Phase 6 Plan 01: MC.OSAG_MAINTSYNC + MCAUDIT.OSAG_AUDIT Summary

**Both batch-A packages specified, tested RED, translated and GREEN: 8 procedures, 176 pgTAP
assertions + 2 regress goldens, four provable Oracle defects corrected and annotated, one
ora2pg schema gap fixed additively.**

## What was done

1. **Specs** derived from `ddl/src/pkg` + `ddl/src/pkgb` only, every clause cited to a
   verified line number (`grep -n`, not arithmetic): `mc.osag_maintsync.md` (S-MAINT-001..021,
   4 corrected-behaviour clauses) and `mcaudit.osag_audit.md` (S-AUDIT-001..015). `spec_lint`
   OK for both.
2. **RED suites** (`trace_lint` OK, 20/21 and 15/15 clauses cited), run against
   `mcdb_test_p0601` (template clone + fix file) with `--install migration/pgsql` while the
   translations did not exist:
   - `mc.osag_maintsync`: **33/109 pgTAP, 0/1 regress** (all failures "procedure does not exist")
   - `mcaudit.osag_audit`: **12/67 pgTAP, 0/1 regress**
3. **Translations** + FINDINGS, then GREEN:
   - `mc.osag_maintsync`: **109/109 pgTAP, 1/1 regress** (regress went 0/1 -> 1/1 after the
     whitespace-only golden correction, see A-009)
   - `mcaudit.osag_audit`: **67/67 pgTAP, 1/1 regress**
   - whole harness: 16 packages, 15 pass, 1 fail -- the pre-existing, accepted
     `auth.osag_auth 9/10`; no sibling count changed.
4. **Lints**: `spec_lint` 14/14 OK, `trace_lint` 31/31 OK, `provenance_lint` OK for both
   packages (its 4 reported violations are pre-existing `tt.ticket_interface` commits
   `b9ba1dd`/`0e5c990`, untouched here).

## Deviations from Oracle (all marked `-- DEVIATION(ORACLE-BUG)`, all specified + tested)

| pkg | clause | defect (Oracle body line) | correction |
|---|---|---|---|
| MAINTSYNC | S-MAINT-012 | `update_single_host`: batch "change needed" filter copied into the SELECT INTO WHERE (217-220) -> nothing-to-do case logged as ERR, IF at 222 dead | filter dropped, IF decides; missing host / OS 21 still log (S-MAINT-013) |
| MAINTSYNC | S-MAINT-016 | `update_single_isp_link`: no `l.id = p_isp_link_id` predicate (286) -> evaluated every changed link in the DB | predicate added |
| MAINTSYNC | S-MAINT-017 | same copied filter (288-294) + NO_DATA_FOUND handler meaning "no interface" -> up-to-date attached link flipped to 1 and back on every call, a history row each time | filter dropped; NO_DATA_FOUND now means exactly "no interface" |
| MAINTSYNC | S-MAINT-018 | `l.maintenance_status_id = NULL` (288; batch says IS NULL at 121) | disappears with the filter |
| MCAUDIT | -- | none of the ORACLE-BUG kind | two PostgreSQL-rule adaptations only: `io_record_id DEFAULT NULL` (S-AUDIT-012) and `NULLIF(x,'')` on stored strings (S-AUDIT-013) |

AuditUsage call sites deleted: 4 (MAINTSYNC) + 4 (MCAUDIT) = 8, reconciled against `grep -c`.

## Schema fixes added

- `migration/test/schema-fixes/26_p0601_fixes.sql` (SCHEMA-FIXES.md fix #10): `mcaudit.record`
  `zitadel_user_id varchar(128)`, `zitadel_user_name varchar(128)`, `zitadel_user_company_id bigint`
  + FK to `stop.company` (DEFERRABLE), index, three column comments -- present in the Oracle
  export (`ddl/generated/schema.oracle.sql:110`), absent from ora2pg's `tables.pg.sql:627-642`.
  Idempotent (applied twice, verified). `build-template.sh` picks it up on the next rebuild.
- Not a schema fix, recorded: `mc.maintenance_status` is EMPTY in `mcdb_tmpl` (the loader
  covers AUTH/TT/MSS/MCAUDIT/OSAG only); the MAINTSYNC test inserts the four rows itself.

## Infrastructure incident (resolved by the coordinator's fix)

`pg.sh` derived its mount set from its own location, so each agent worktree recreated the
shared `mcdb-pg` container with only its own worktree mounted, killing the other agents'
sessions and making `pg.sh psql` fail with `chdir to cwd ... no such file` from any other
worktree. I patched it locally (`d5cd932`), then cherry-picked the coordinator's equivalent
fix `1a8c31c` (-> `96adcc1`; conflicts in `pg.sh` and two container files resolved to the
cherry-picked versions, so `pg.sh` is byte-identical to `1a8c31c`). `d5cd932` remains in
history, superseded.

## Open questions for the project owner

1. **Do any clients call `update_single_host` / `update_single_isp_link`?** No PL/SQL in
   `ddl/src/` does. If they do, the differential run (06-05/06-06) will show diffs for exactly
   the four corrected cases -- by design; they should be whitelisted as corrections, not
   "fixed" back.
2. **Scheduling the two batch routines**: Oracle runs them every minute
   (`ddl/src/jobs/mc_jobs.sql`); `migration/pgsql/_support/30_pg_cron_jobs.sql` does not list
   them. Add `CALL mc.osag_maintsync_update_host_maint_status()` /
   `..._update_isp_link_maint_status()` at `* * * * *`?
3. **Template masterdata scope**: add `MC` (at least `maintenance_status`) to
   `bootstrap/40_fixtures.sh`'s schema list at the next rebuild?
4. **Transaction-scope delta (XCUT-05)** in the four `WHEN OTHERS` swallows: PL/pgSQL rolls
   back the whole call's loop iterations on a mid-loop failure where Oracle kept the earlier
   ones; steady state identical after the next job run. Accept?
5. **Shared maintenance-window view**: five textual copies of the same join now exist
   (four here + `tt.osag_notify_is_notify_suppressor_active`). Factor later?
6. **MCAUDIT client call shape**: PostgreSQL `CALL` returns INOUT values as a result row where
   Oracle used IN OUT bind variables -- needs an application note in the Phase 5 regexp kit.
7. **`mcaudit.record."timestamp"`** lost `WITH TIME ZONE` in ora2pg's conversion (DDL-migration
   owned; flagged because this package is the only writer).

## Commits (in order)

| sha | subject |
|---|---|
| `d5cd932` | build(pg): mount the main checkout so linked worktrees share one mcdb-pg container (superseded by 96adcc1) |
| `48b455c` | spec(06-01): MC.OSAG_MAINTSYNC |
| `319bbcb` | spec(06-01): MCAUDIT.OSAG_AUDIT |
| `96adcc1` | fix(pg.sh): resolve the project root to the main checkout from git worktrees (cherry-pick of 1a8c31c) |
| `ef43290` | test(06-01): RED suite for MC.OSAG_MAINTSYNC |
| `b47193d` | test(06-01): RED suite for MCAUDIT.OSAG_AUDIT (+ 26_p0601_fixes.sql, SCHEMA-FIXES.md) |
| `c214e17` | test(06-01): restore psql's trailing spaces in the mc__osag_maintsync__errors golden |
| `a8f1f7d` | docs(06-01): TEST-AMENDMENTS A-009 |
| `c8d87fd` | feat(06-01): translate MC.OSAG_MAINTSYNC |
| `9e4e911` | feat(06-01): translate MCAUDIT.OSAG_AUDIT |
| (this) | docs(06-01): SUMMARY |

Nothing pushed. Test database: `mcdb_test_p0601` (disposable).
