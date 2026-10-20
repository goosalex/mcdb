# MCAUDIT.OSAG_AUDIT -- FINDINGS

**Source:** `ddl/src/pkg/mcaudit_osag_audit.sql` (spec, 87 lines),
`ddl/src/pkgb/mcaudit_osag_audit.sql` (body, 150 lines). **Spec:**
`migration/spec/mcaudit.osag_audit.md` (15 clauses, S-AUDIT-001..015). **Target:**
`migration/pgsql/mcaudit/osag_audit.sql`. **Tests:**
`migration/test/pgtap/mcaudit__osag_audit__spec.sql` (67 assertions),
`migration/test/regress/sql/mcaudit__osag_audit__errors.sql` (+ golden).

Four PROCEDUREs writing one `mcaudit.record` row each; `add_record_raw2` is the single
writer, the other three delegate to it. Callers in the corpus: `GUMA2.OSAG_GUMA`
(`add_record_raw`, plan 06-03) and `AUTH.OSAG_AUTH_PASSPORT` (`add_record`), plus client
code through the public synonym `osag_audit`. Second package of Phase 6 batch A.

## Deviations from Oracle

**None of the ORACLE-BUG kind.** The package is small and correct. Two deliberate,
annotated adaptations to PostgreSQL rules, both specified (S-AUDIT-012, S-AUDIT-013):

| # | what | why | where |
|---|---|---|---|
| 1 | `io_record_id` (`add_record_raw2`, `add_record2`) gets `DEFAULT NULL`; Oracle declares it `IN OUT` without a default, positioned after five `DEFAULT NULL` parameters. | PostgreSQL requires every input parameter after a defaulted one to carry a default (INOUT counts as input; probed before writing). NULL already means "allocate a record id" in the Oracle body (28-30), so the semantics are unchanged -- callers that passed an explicit NULL and callers that now omit it get the same result. | S-AUDIT-012 |
| 2 | `NULLIF(x, '')` on the five string inputs the writer stores or looks up (`i_message`, `i_details`, `i_table_name`, `i_zitadel_user_id`, `i_zitadel_user_name`). | Oracle collapses `''` to NULL: an empty message hit `message NOT NULL` (ORA-01400), empty details/zitadel strings were stored as NULL, an empty table name resolved to a NULL `object_type_id`. A naive port would store `''` and accept an empty message. The four `short` lookups need no normalisation (`short = ''` finds nothing in either engine). | S-AUDIT-013 |

**NOT treated as defects, deliberately:**

- `i_component_short` is anchored to `mcaudit.application.short%TYPE` instead of
  `component.short%TYPE` (both `VARCHAR2(64)`) -- harmless typo, translated as `varchar`.
- `table_name` on `mss.object_type` is NOT unique (`U_OBJECT_TYPE_TABLE_NAME` is a plain
  index, `ddl/generated/schema.oracle.sql:3874`), so the scalar subquery can fail with
  ORA-01427 / SQLSTATE `21000` -- Oracle-faithful, pinned by S-AUDIT-006, not "fixed" by a
  `LIMIT 1`.
- No exception handler anywhere; every error propagates. Faithful.

## AuditUsage deletion count

**4 of 4** `plog.AuditUsage(...)` call sites deleted outright, one per routine (lines 23,
56, 99, 134) -- confirmed by `grep -c AuditUsage ddl/src/pkgb/mcaudit_osag_audit.sql` -> 4.
Per XCUT-06, deleted, not stubbed (S-AUDIT-014). This package therefore calls plog not at
all.

## `pg_kind` verdict: procedure for all 4, correct and forced

All four are Oracle `PROCEDURE`s with `IN OUT` parameters; `name-map.csv` says
`pg_kind=procedure`; all four are PostgreSQL PROCEDUREs with `INOUT` parameters (S-AUDIT-001
checks `prokind='p'` and `proargmodes` containing `b`). A FUNCTION could carry OUT
parameters too, but the callers `CALL` these as statements and the `IN OUT` shape (value in,
value out) maps to `INOUT` only on a PROCEDURE. No `COMMIT`/`ROLLBACK`/autonomous
transaction -- the audit record is NOT durable on its own and dies with the caller's
transaction (S-AUDIT-015, proven with a `SAVEPOINT`/`ROLLBACK TO`).

## SELECT INTO strictness (8 sites, matching the spec's table and the inventory)

All eight (`add_record2` 100-103, `add_record` 135-138; `short` lookups against the four
`mcaudit.*` reference tables) are `INTO STRICT`. Oracle had NO handler at any scope, so
each routine's four lookups share one `WHEN NO_DATA_FOUND` arm that re-raises `P0002` with
Oracle's text `no data found` -- the message-parity shim of
`migration/mapping/sqlstate-map.md` rule 2, applied because these are externally
reachable, unhandled sites (clients and `AUTH.OSAG_AUTH_PASSPORT`'s `WHEN OTHERS` see the
text). `TOO_MANY_ROWS` (duplicate `short`; only `severity.short` is unique) propagates as
`P0003` unshimmed, as every other translation does. The scalar subquery at line 37 is not a
`SELECT INTO` site.

## Exception mapping

| condition | Oracle | PostgreSQL | pinned by |
|---|---|---|---|
| unknown `short` | ORA-01403 | `P0002` `no data found` (shim) | S-AUDIT-010 (pgTAP + regress golden) |
| duplicate `short` | ORA-01422 | `P0003` | spec only |
| `i_table_name` matching >1 `mss.object_type` rows | ORA-01427 | `21000` | S-AUDIT-006 |
| NULL / `''` into a NOT NULL column | ORA-01400 | `23502` | S-AUDIT-007, S-AUDIT-013 (pgTAP + regress golden) |
| FK violation | ORA-02291 | `23503` (deferred -- ora2pg emitted every FK `DEFERRABLE`, so it surfaces at COMMIT, not at the CALL) | not pinned |
| duplicate `io_record_id` | ORA-00001 | `23505` | not pinned |

No `-20NNN` application codes: nothing to add to `sqlstate-map.md`.

## Translation mechanics worth knowing

- **Explicit parameter types, not `%TYPE`**, on purpose: the three `zitadel_user_*`
  parameters would anchor to columns that do not exist on a template without
  `26_p0601_fixes.sql`, and `%TYPE` resolves at CREATE time -- the whole file would fail to
  install (and `run-tests.sh --install` aborts the entire harness on the first failing
  file). With explicit types the CREATE succeeds everywhere and only the INSERT fails, at
  run time, on a stale template. Types are the resolved column types (`bigint`, `varchar`,
  `text`).
- **INOUT pass-through:** `add_record_raw`/`add_record`/`add_record2` pass their own INOUT
  `io_transaction_id` (and `add_record2` its `io_record_id`) straight into the inner `CALL`
  as the INOUT argument -- legal in PL/pgSQL because a parameter is a variable. Named
  notation (`i_x => v_x`) is kept where Oracle used it (`add_record`, `add_record2`), positional
  where Oracle was positional (`add_record_raw`).
- **Calling convention for tests and clients:** a SQL-level `CALL` accepts literals for INOUT
  arguments and returns the INOUT values as a one-row result (`CALL
  mcaudit.osag_audit_add_record('guma','authsys','login_modify','info', NULL, 'msg', NULL)`
  works, S-AUDIT-012); a PL/pgSQL `CALL` needs variables. The pgTAP suite captures the ids
  through `pg_temp` helper functions into a temp table.
- `"timestamp"` is quoted in the INSERT column list (it is also a type name);
  `SYSTIMESTAMP` -> `statement_timestamp()`, implicitly converted to the column's
  `timestamp without time zone` (Oracle: `TIMESTAMP(6) WITH TIME ZONE`; the type change is
  ora2pg's, see the spec's Assumptions).
- Unqualified `record`, `application`, `component`, `record_type`, `severity`,
  `transaction_seq`, `record_seq` (resolved in the package owner's schema in Oracle) are
  written `mcaudit.*` / `nextval('mcaudit.*')`.

## Schema fix required (ora2pg gap)

`migration/test/schema-fixes/26_p0601_fixes.sql` (ledgered as fix #10 in
`migration/test/SCHEMA-FIXES.md`): `mcaudit.record` lacks `zitadel_user_id varchar(128)`,
`zitadel_user_name varchar(128)`, `zitadel_user_company_id` (+ FK to `stop.company`, index,
comments) which the Oracle export has (`ddl/generated/schema.oracle.sql:110`) and
`ddl/migrated/tables/tables.pg.sql:627-642` does not. Same shape as plan 02-12's fix for
`tt.change_request`. Idempotent; `build-template.sh` loads it on the next template rebuild.

## Red/green status (verified live against `mcdb_test_p0601`, cloned from `mcdb_tmpl` + `26_p0601_fixes.sql`)

**RED (commit b47193d, `--install migration/pgsql` without this file):**

```
mcaudit.osag_audit                       | 12/67              | 0/1                | FAIL
```

Every failure is `procedure mcaudit.osag_audit_* does not exist`; the 12 pre-passing
assertions are the "no row inserted"/"nothing returned" checks beside a failing
`lives_ok`/`throws_ok`.

**GREEN (this translation installed):**

```
mcaudit.osag_audit                       | 67/67              | 1/1                | PASS
```

**GREEN, whole harness:** 16 packages, 15 pass, 1 fail (the pre-existing, accepted
`auth.osag_auth 9/10`). No sibling count changed.

## Verification performed

- `python3 migration/spec/spec_lint.py migration/spec/mcaudit.osag_audit.md` (OK),
  `python3 migration/spec/trace_lint.py` on both test files (OK, 15/15 clauses cited),
  `bash migration/spec/provenance_lint.sh` (OK once the translation commit landed).
- `grep -nEi "dbms_|utl_|auditusage|dblink|pg_background"` over the translation: matches
  only in comments.
- Commit order: spec (319bbcb), RED suite + schema fix (b47193d), then this translation +
  FINDINGS.

## Open questions

- Client call shape: Oracle DBI clients bind `io_transaction_id` as an IN OUT bind variable;
  the PostgreSQL `CALL` returns the INOUT values as a result row instead. The client
  regexp kit (Phase 5) needs an application note for this, not just a name rewrite.
- Whether production data has duplicate `application`/`component`/`record_type` shorts
  (would make `add_record`/`add_record2` raise `P0003`); masterdata has none.
- `mcaudit.record."timestamp"` lost its time zone in ora2pg's conversion (`TIMESTAMP(6)
  WITH TIME ZONE` -> `timestamp`). Owned by the DDL migration; flagged here because this is
  the only writer.
