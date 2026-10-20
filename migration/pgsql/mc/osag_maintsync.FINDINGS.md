# MC.OSAG_MAINTSYNC -- FINDINGS

**Source:** `ddl/src/pkg/mc_osag_maintsync.sql` (spec, 36 lines),
`ddl/src/pkgb/mc_osag_maintsync.sql` (body, 319 lines). **Spec:**
`migration/spec/mc.osag_maintsync.md` (21 clauses, S-MAINT-001..021). **Target:**
`migration/pgsql/mc/osag_maintsync.sql`. **Tests:**
`migration/test/pgtap/mc__osag_maintsync__spec.sql` (109 assertions),
`migration/test/regress/sql/mc__osag_maintsync__errors.sql` (+ golden).

Four PROCEDUREs that keep `mss.host.maintenance_status_id` / `mss.isp_link.maintenance_status_id`
(1 unknown, 2 active, 3 inactive, 4 maintenance) in sync with host activity and the TT
maintenance windows, writing `mc.host_maintenance_history` / `mc.isp_link_maintenance_history`
on every change. The two batch routines are Oracle scheduler jobs run every minute
(`ddl/src/jobs/mc_jobs.sql:7,19`); the two single-entity routines have no caller inside the
database. First package of Phase 6 batch A (06-CONTEXT.md); depends on plog only.

## Deviations from Oracle (project-owner instruction: correct broken behaviour, annotate it)

Four, all in the two single-entity routines, all marked `-- DEVIATION(ORACLE-BUG)` at the site
and specified as corrected behaviour in the spec, so the tests assert the corrected contract.
The two batch routines are Oracle-faithful.

| # | routine | Oracle behaviour (body lines) | why it is broken | corrected behaviour | spec |
|---|---|---|---|---|---|
| 1 | `update_single_host` | The status `SELECT INTO` (189-220) ANDs the batch cursor's "a change is needed" filter (217-220) onto `WHERE h.id = p_host_id`. For a host whose stored status already equals the derived one the query returns NO row -> `NO_DATA_FOUND` -> `WHEN OTHERS` (233-235) logs `update_single_host(): caught exception: ORA-01403: no data found` at ERR level. | The normal nothing-to-do case is an ERROR in the log, and the `IF (v_current_status != v_old_status OR v_old_status IS NULL)` at 222 -- written precisely to decide whether a change is needed -- can never be false (dead code). | Filter dropped from the WHERE; the IF decides. Missing host / OS-21 host still raise `NO_DATA_FOUND` into the same log-and-swallow handler (S-MAINT-013, faithful). | S-MAINT-012 |
| 2 | `update_single_isp_link` | The status query's WHERE (286) is `l.id = hosts.isp_link_id AND l.id = sw.isp_link_id(+) AND (...)` -- NO `l.id = p_isp_link_id`. | The `SELECT INTO` ranges over EVERY attached link in the database that needs a change: exactly one such link anywhere -> ITS status is written to `p_isp_link_id` (304-308); several -> `TOO_MANY_ROWS`, missed by the 296-301 `NO_DATA_FOUND` handler, logged by `WHEN OTHERS`. The sibling `update_single_host` has the predicate (216) and the UPDATE at 308 names `p_isp_link_id`, so the intent is unambiguous. | `WHERE l.id = p_isp_link_id` added. | S-MAINT-016 |
| 3 | `update_single_isp_link` | Same copied "change needed" filter (288-294) inside a `SELECT INTO` whose `NO_DATA_FOUND` handler (296-301, comment: "the isp link is not attached to an interface") sets status 1 / ticket NULL. | For an up-to-date ATTACHED link the query returns no row, the handler sets 1, line 304 sees `stored <> 1`, writes a history row and status 1 (unknown); the next call sees 1, re-derives 2/3/4, writes it back -- a flip-flop with a spurious history row per call. | Filter dropped; for an attached link the query returns exactly one row and the IF at 304 decides -- which is exactly the batch cursor's selection logic (S-MAINT-007), verified equivalent case by case in the spec. `NO_DATA_FOUND` now means exactly "no interface", as the handler's comment says. | S-MAINT-017 |
| 4 | `update_single_isp_link` | `l.maintenance_status_id = NULL` (288) where the batch cursor (121) says `IS NULL`. | Never true in SQL; an attached NULL-status link was handled by defect #3 instead (set to 1). | Disappears with the filter (#3); an attached NULL-status link gets its derived status with old status 1, like the batch. | S-MAINT-018 |

The S-MAINT-012 correction changes NO data outcome -- only the spurious ERR log line
disappears. The S-MAINT-016/017/018 corrections change data outcomes for
`update_single_isp_link` only; whether any client ever called it is unknown (no PL/SQL
caller in `ddl/src/`; the two jobs call the batch routines).

**NOT treated as defects, deliberately:**

- The batch routines' `WHEN OTHERS` swallow (67-69, 170-172): intended (a job must not die
  on one bad row). Kept, with the transaction-scope delta below.
- The four textual copies of the five-table maintenance-window join (28-44, 95-115,
  198-214, 262-282; the ISP-link copies add `mss.interface` -> `mss.interface2isp_link`):
  kept as four copies on instruction ("translate the join faithfully, no shared view in
  this plan"). **Follow-up:** `tt.osag_notify_is_notify_suppressor_active`
  (`migration/pgsql/tt/osag_notify.sql`) carries a fifth copy of the same join with a
  different flag (`disable_notification`); a `tt.v_active_maintenance_window(host_id,
  ticket_id, flags...)` view would replace all five. Not done here.
- The `hosts` / `sw` derived tables in the single-link routine are still grouped over ALL
  links before the outer `WHERE l.id = p_isp_link_id` applies (Oracle shape kept); the
  planner may or may not push the predicate down. Performance, not behaviour.

## AuditUsage deletion count

**4 of 4** `plog.AuditUsage(...)` call sites deleted outright, one per routine (lines 54,
141, 187, 250) -- confirmed by `grep -c AuditUsage ddl/src/pkgb/mc_osag_maintsync.sql` -> 4.
Per XCUT-06, deleted, not stubbed (S-MAINT-020).

## `pg_kind` verdict: procedure for all 4, correct

All four are Oracle `PROCEDURE`s, `name-map.csv` says `pg_kind=procedure`, all four are
created as PostgreSQL PROCEDUREs (`prokind='p'`, the four S-MAINT-001 assertions). No
`COMMIT`/`ROLLBACK`/autonomous transaction anywhere (inventory and full read agree). The batch
routines are job entry points (`CALL` from a scheduler); the single-entity routines are
client entry points -- nothing calls them from SQL expressions, so FUNCTION was never an
option worth considering.

## Transaction-scope delta (XCUT-05, recorded, not asserted)

Each routine wraps its whole body in `EXCEPTION WHEN OTHERS THEN plog.err(...)`. In Oracle
the handler leaves the loop iterations already executed in place (only the failing
statement is rolled back). In PL/pgSQL the `BEGIN ... EXCEPTION` block is a subtransaction:
a failure in iteration N rolls back iterations 1..N-1 of the same call as well. The next
minute's job run redoes them, so the steady state is identical; the per-call outcome is
not. The S-MAINT-006/010 tests provoke the failure (a pre-inserted history row colliding
with the next sequence value) on the FIRST and only iteration, where both engines agree
(nothing written, one ERR line). Also note the plog stub rows ride in the caller's
transaction (`osag_plog.FINDINGS.md`); the ERR line itself is NOT rolled back by the
handler's subtransaction because `plog.err` runs in the handler, after the rollback.

## SELECT INTO strictness (3 sites, matching the spec's table and the inventory)

| # | line | routine | verdict |
|---|---|---|---|
| 1 | 189-220 | `update_single_host` | `INTO STRICT`; query corrected (deviation #1); zero rows = missing host / OS 21 -> caught by the routine's `WHEN OTHERS`, logged with prefix (S-MAINT-013). >1 row impossible (`h.id` PK, `sw` grouped). |
| 2 | 251 | `update_single_isp_link` | `INTO STRICT`, no local handler; missing link -> `WHEN OTHERS`, logged (S-MAINT-014). |
| 3 | 254-294 | `update_single_isp_link` | `INTO STRICT` + Oracle's local `NO_DATA_FOUND -> 1/NULL` handler (S-MAINT-015); query corrected (deviations #2-#4), after which >1 row is impossible. |

The batch routines use cursor FOR loops (empty result = empty loop). No `TOO_MANY_ROWS`
handling anywhere -- impossible after the corrections, exactly as Oracle intended.

The "no data found" message-parity shim is NOT used: no `NO_DATA_FOUND` ever leaves this
package. The logged `SQLERRM` text is PostgreSQL's (`query returned no rows`) where Oracle
logged `ORA-01403: no data found`; the spec pins the fixed prefix only, the regress golden
documents the PostgreSQL text.

## Exception mapping

Nothing to map: no `RAISE_APPLICATION_ERROR`, no named exception, no error leaves the
package (four `WHEN OTHERS` swallows, one `WHEN NO_DATA_FOUND` default). Nothing for
`migration/mapping/sqlstate-map.md`.

## Translation mechanics worth knowing

- **`(+)` -> `LEFT JOIN`**, comma joins -> explicit `INNER JOIN`; `FOR UPDATE OF
  h.maintenance_status_id` -> `FOR UPDATE OF h` (PostgreSQL locks rows of the named table,
  not columns; the outer query has no GROUP BY, so the lock is legal even though the derived
  table is grouped -- probed before writing). S-MAINT-021 pins the clause textually via
  `pg_proc.prosrc`.
- **`SYSTIMESTAMP` -> `statement_timestamp()`** (the established convention, see
  `tt/osag_notify.sql`'s copy of the same join); compared against `timestamp without time
  zone` window bounds through the session time zone, written into `change_date` (`timestamp`)
  likewise.
- **`NVL(x, 1)` -> `coalesce(x, 1)`**, `seq.nextval` -> `nextval('mc.<seq>')`.
- **NULL concatenation (Pitfall 2):** the one `||` site with a nullable operand is the
  `plog.notice` in the ISP batch (`maintenance_status_old` NULL for a never-synced link) ->
  `concat()`; S-MAINT-008 pins the rendered `': old status is '` (nothing after it).
- **`%TYPE` kept** for the two parameters (`mss.host.id%TYPE`, `mss.isp_link.id%TYPE` ->
  `bigint`) and the locals, following the `osag_notify` / `escalation_interface` convention.
- **`SQLERRM`** inside `WHEN OTHERS` is PostgreSQL's message text; prefix is Oracle's.

## Schema / masterdata facts the tests depend on

- **`mc.maintenance_status` is EMPTY in `mcdb_tmpl`**: `bootstrap/40_fixtures.sh` loads
  masterdata for `AUTH TT MSS MCAUDIT OSAG` only, and `masterdata/MC/maintenance_status.csv`
  (the four statuses) is not among them. The test inserts the four rows itself
  (`ON CONFLICT (id) DO NOTHING`), so it passes with or without MC masterdata. Open question:
  add `MC` to the template's loaded schemas (recorded in `SCHEMA-FIXES.md` and 06-01-SUMMARY).
- No schema fix was needed for this package: `mss.host`, `mss.isp_link`, `mss.interface`,
  `mss.interface2isp_link`, `mc.host_maintenance_history`, `mc.isp_link_maintenance_history`,
  the four TT window tables and the two sequences (`mc.host_maint_history_seq`,
  `mc.isp_link_maint_history_seq`, increment 1) all exist in the template as ora2pg emitted
  them.
- `mss.host.active` defaults to 0; every fixture sets it explicitly. `mss.interface.network_id`
  defaults to 1 but `mss.network` is empty in the template -- fixtures set it NULL.

## Red/green status (verified live against `mcdb_test_p0601`, cloned from `mcdb_tmpl` + `26_p0601_fixes.sql`)

**RED (commit ef43290, `--install migration/pgsql` without this file):**

```
mc.osag_maintsync                        | 33/109             | 0/1                | FAIL
```

Every failure is `procedure mc.osag_maintsync_* does not exist`; the 33 pre-passing
assertions are the "did NOT happen"/unchanged checks beside a failing `lives_ok`.

**GREEN (this translation installed):**

```
mc.osag_maintsync                        | 109/109            | 1/1                | PASS
```

(The regress half went 0/1 -> 1/1 after the whitespace-only golden correction c214e17,
ledgered as TEST-AMENDMENTS A-019.)

**GREEN, whole harness (`run-tests.sh --db mcdb_test_p0601 --install migration/pgsql`):**
16 packages, 15 pass, 1 fail -- the one fail is the pre-existing, accepted
`auth.osag_auth 9/10`. No sibling count changed.

## Verification performed

- `python3 migration/spec/spec_lint.py migration/spec/mc.osag_maintsync.md` (OK),
  `python3 migration/spec/trace_lint.py` on both test files (OK, 20/21 clauses cited --
  uncited: S-MAINT-020, the AuditUsage-deletion clause),
  `bash migration/spec/provenance_lint.sh` (OK once the translation commit landed).
- `grep -nEi "dbms_|utl_|auditusage|dblink|pg_background"` over the translation: matches
  only in comments.
- Commit order: spec (48b455c), RED suite (ef43290), golden whitespace fix (c214e17) +
  ledger, then this translation + FINDINGS.

## Open questions (could not be settled from the Oracle source)

- Whether any client calls `update_single_host` / `update_single_isp_link` and therefore
  ever observed the four corrected defects (06-05/06-06's differential run will show diffs
  for exactly these cases, by design).
- Scheduling: the two Oracle jobs run every minute; `migration/pgsql/_support/30_pg_cron_jobs.sql`
  does not list them. A `pg_cron` entry `CALL mc.osag_maintsync_update_host_maint_status()`
  / `..._update_isp_link_maint_status()` at `* * * * *` is the obvious equivalent -- project
  decision, not taken here.
- Whether to factor the five-times-duplicated maintenance-window join into one view (see
  "NOT treated as defects").
