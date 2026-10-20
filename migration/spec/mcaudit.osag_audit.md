---
oracle_schema: MCAUDIT
oracle_package: OSAG_AUDIT
pg_schema: mcaudit
pg_prefix: osag_audit
clause_prefix: AUDIT
oracle_spec: ddl/src/pkg/mcaudit_osag_audit.sql
oracle_body: ddl/src/pkgb/mcaudit_osag_audit.sql
public_routines: 4
---

# MCAUDIT.OSAG_AUDIT — PostgreSQL spec

Per its header comment (`ddl/src/pkg/mcaudit_osag_audit.sql:6-12`), this package is a
"collection of functions to be used with the Mission Control Audit schema": four
procedures that write ONE row into `mcaudit.record` each. `add_record_raw2` is the single
writer (every other routine delegates to it): it allocates a transaction id and a record id
from `mcaudit.transaction_seq` / `mcaudit.record_seq` when the caller passes NULL, resolves
an optional table name to `mss.object_type.id`, and inserts the record with the current
timestamp. `add_record_raw` is the same with the record id discarded and no Zitadel
columns; `add_record` / `add_record2` take the application / component / record type /
severity as their `short` names instead of ids and resolve them with four `SELECT INTO`s.
Callers in the corpus: `GUMA2.OSAG_GUMA` (`add_record_raw`,
`ddl/src/pkgb/guma2_osag_guma.sql:335,397`) and `AUTH.OSAG_AUTH_PASSPORT` (`add_record`
with `'guma','authsys','login_modify','info'`, `ddl/src/pkgb/auth_osag_auth_passport.sql:1873,1900`),
plus client code through the public synonym `osag_audit`
(`ddl/src/pkg/mcaudit_osag_audit.sql:85`). The package has NO exception handler of its own:
every error propagates to the caller.

## Routines

### add_record_raw

- **Oracle signature:** `PROCEDURE add_record_raw(i_application_id NUMBER, i_component_id NUMBER, i_record_type_id NUMBER, i_severity_id NUMBER, io_transaction_id IN OUT NUMBER, i_message VARCHAR2, i_details CLOB, i_company_id NUMBER DEFAULT NULL, i_contact_id NUMBER DEFAULT NULL, i_table_name VARCHAR2 DEFAULT NULL, i_object_id NUMBER DEFAULT NULL, i_ticket_id NUMBER DEFAULT NULL)` (parameter types are `mcaudit.record.<col>%TYPE`)
- **PostgreSQL name:** `mcaudit.osag_audit_add_record_raw` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/mcaudit_osag_audit.sql:21-32`
- **Defined:** `ddl/src/pkgb/mcaudit_osag_audit.sql:42-74`
- Delegates to `add_record_raw2` with a NULL local record id (so a fresh record id is
  allocated and thrown away) and no Zitadel columns. Returns the (possibly allocated)
  transaction id through `io_transaction_id`.

### add_record_raw2

- **Oracle signature:** `PROCEDURE add_record_raw2(<the 12 add_record_raw parameters>, io_record_id IN OUT NUMBER, i_zitadel_user_id VARCHAR2 DEFAULT NULL, i_zitadel_user_name VARCHAR2 DEFAULT NULL, i_zitadel_user_company_id NUMBER DEFAULT NULL)`
- **PostgreSQL name:** `mcaudit.osag_audit_add_record_raw2` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/mcaudit_osag_audit.sql:34-49`
- **Defined:** `ddl/src/pkgb/mcaudit_osag_audit.sql:6-40`
- The single writer: allocates `io_transaction_id` / `io_record_id` from the two
  sequences when NULL, inserts one `mcaudit.record` row, returns both ids through the
  IN OUT parameters. Raises nothing of its own; constraint and lookup errors propagate.

### add_record

- **Oracle signature:** `PROCEDURE add_record(i_application_short VARCHAR2, i_component_short VARCHAR2, i_record_type_short VARCHAR2, i_severity_short VARCHAR2, io_transaction_id IN OUT NUMBER, i_message VARCHAR2, i_details CLOB, i_company_id NUMBER DEFAULT NULL, i_contact_id NUMBER DEFAULT NULL, i_table_name VARCHAR2 DEFAULT NULL, i_object_id NUMBER DEFAULT NULL, i_ticket_id NUMBER DEFAULT NULL)`
- **PostgreSQL name:** `mcaudit.osag_audit_add_record` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/mcaudit_osag_audit.sql:52-63`
- **Defined:** `ddl/src/pkgb/mcaudit_osag_audit.sql:115-147`
- Resolves the four `short` names to ids with four unguarded `SELECT INTO`s, then calls
  `add_record_raw2` with a NULL local record id (allocated, discarded) and no Zitadel
  columns.

### add_record2

- **Oracle signature:** `PROCEDURE add_record2(<the 12 add_record parameters>, io_record_id IN OUT NUMBER, i_zitadel_user_id VARCHAR2 DEFAULT NULL, i_zitadel_user_name VARCHAR2 DEFAULT NULL, i_zitadel_user_company_id NUMBER DEFAULT NULL)`
- **PostgreSQL name:** `mcaudit.osag_audit_add_record2` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/mcaudit_osag_audit.sql:66-81`
- **Defined:** `ddl/src/pkgb/mcaudit_osag_audit.sql:76-113`
- Same as `add_record` but passes `io_record_id` and the three Zitadel parameters through
  to `add_record_raw2`, so the caller receives the record id ("returns the ID of the
  created record in the parameter io_record_id", `ddl/src/pkg/mcaudit_osag_audit.sql:65`).

## Clauses

### S-AUDIT-001

- **routines:** add_record_raw, add_record_raw2, add_record, add_record2
- **claim:** All four routines are Oracle `PROCEDURE`s with `IN OUT` parameters and no
  return value; they are created as PostgreSQL PROCEDUREs (`pg_kind=procedure` in
  `name-map.csv` for all four) whose `IN OUT` parameters become `INOUT` parameters, so a
  `CALL` returns the (possibly allocated) ids to the caller.
- **source:** `ddl/src/pkg/mcaudit_osag_audit.sql:21`, `ddl/src/pkg/mcaudit_osag_audit.sql:34`, `ddl/src/pkg/mcaudit_osag_audit.sql:52`, `ddl/src/pkg/mcaudit_osag_audit.sql:66`

### S-AUDIT-002

- **routines:** add_record_raw2
- **claim:** When `io_transaction_id` is NULL on entry, `add_record_raw2` sets it to the next
  value of `mcaudit.transaction_seq` and the inserted row carries that value; when it is
  not NULL it is used unchanged (so several records can share one transaction id). The
  value is returned to the caller through the IN OUT parameter.
- **source:** `ddl/src/pkgb/mcaudit_osag_audit.sql:24-26`, `ddl/src/pkgb/mcaudit_osag_audit.sql:35-36`

### S-AUDIT-003

- **routines:** add_record_raw2
- **claim:** When `io_record_id` is NULL on entry, `add_record_raw2` sets it to the next
  value of `mcaudit.record_seq` and uses it as the new row's `id`; when it is not NULL that
  id is used as-is. The value is returned to the caller through the IN OUT parameter.
- **source:** `ddl/src/pkgb/mcaudit_osag_audit.sql:28-30`, `ddl/src/pkgb/mcaudit_osag_audit.sql:33-35`

### S-AUDIT-004

- **routines:** add_record_raw2
- **claim:** `add_record_raw2` inserts exactly one `mcaudit.record` row with `id` =
  `io_record_id`, `timestamp` = the current timestamp, `application_id`, `component_id`,
  `record_type_id`, `severity_id`, `message`, `details`, `transaction_id` =
  `io_transaction_id`, `company_id`, `contact_id`, `object_id`, `object_type_id` (S-AUDIT-005),
  `ticket_id`, `zitadel_user_id`, `zitadel_user_name`, `zitadel_user_company_id` all taken
  verbatim from the corresponding parameters. No other column is written; no other table is
  touched.
- **source:** `ddl/src/pkgb/mcaudit_osag_audit.sql:32-38`

### S-AUDIT-005

- **routines:** add_record_raw2
- **claim:** `object_type_id` is the `id` of the `mss.object_type` row whose `table_name`
  equals `i_table_name` (exact, case-sensitive match); when `i_table_name` is NULL or
  matches no row the scalar subquery yields NULL and `object_type_id` is NULL — no error.
- **source:** `ddl/src/pkgb/mcaudit_osag_audit.sql:37`

### S-AUDIT-006

- **routines:** add_record_raw2
- **claim:** When `i_table_name` matches MORE than one `mss.object_type` row (the
  `U_OBJECT_TYPE_TABLE_NAME` index on `table_name` is NOT unique:
  `ddl/generated/schema.oracle.sql:3874` is a plain `CREATE INDEX`), the single-row
  subquery raises an error (Oracle ORA-01427; PostgreSQL SQLSTATE `21000`,
  `cardinality_violation`) that propagates to the caller, and no row is inserted.
- **source:** `ddl/src/pkgb/mcaudit_osag_audit.sql:37`

### S-AUDIT-007

- **routines:** add_record_raw2
- **claim:** `add_record_raw2` has no exception handler: a NULL `i_application_id`,
  `i_component_id`, `i_record_type_id`, `i_severity_id` or `i_message` violates the
  corresponding `NOT NULL` constraint of `mcaudit.record` (Oracle ORA-01400; PostgreSQL
  SQLSTATE `23502`, `not_null_violation`) and the error propagates to the caller with no
  row inserted. (A NULL `i_severity_id` is an explicit NULL in the VALUES list, so the
  column's `DEFAULT 30` does not apply.)
- **source:** `ddl/src/pkgb/mcaudit_osag_audit.sql:32-38`, `ddl/src/pkgb/mcaudit_osag_audit.sql:40`

### S-AUDIT-008

- **routines:** add_record_raw
- **claim:** `add_record_raw` calls `add_record_raw2` with its own twelve parameters in
  order and a NULL local `v_record_id` as `io_record_id`, so a record id is allocated from
  `mcaudit.record_seq` and discarded (not returned); the three Zitadel columns are NULL;
  `io_transaction_id` is passed through IN OUT, so the caller receives the allocated
  transaction id exactly as with `add_record_raw2`.
- **source:** `ddl/src/pkgb/mcaudit_osag_audit.sql:54`, `ddl/src/pkgb/mcaudit_osag_audit.sql:58-72`

### S-AUDIT-009

- **routines:** add_record2
- **claim:** `add_record2` resolves `i_application_short` against `mcaudit.application.short`,
  `i_component_short` against `mcaudit.component.short`, `i_record_type_short` against
  `mcaudit.record_type.short` and `i_severity_short` against `mcaudit.severity.short` (four
  `SELECT id INTO ... WHERE short = ...`, exact match), then calls `add_record_raw2` by
  name with the four resolved ids, all its other parameters unchanged, and `io_record_id`
  and the three Zitadel parameters passed through — so the caller receives both the
  transaction id and the record id.
- **source:** `ddl/src/pkgb/mcaudit_osag_audit.sql:100-103`, `ddl/src/pkgb/mcaudit_osag_audit.sql:105-111`

### S-AUDIT-010

- **routines:** add_record, add_record2
- **claim:** When any of the four `short` names matches no row, the corresponding
  `SELECT INTO` raises `NO_DATA_FOUND`, which has no handler anywhere in the package and
  propagates to the caller (PostgreSQL SQLSTATE `P0002` with Oracle's message text
  `no data found`, per the project's message-parity shim); no `mcaudit.record` row is
  inserted and no sequence value is consumed for the record. (Should a `short` match more
  than one row, `TOO_MANY_ROWS` propagates likewise — SQLSTATE `P0003`; see Assumptions.)
- **source:** `ddl/src/pkgb/mcaudit_osag_audit.sql:100-103`, `ddl/src/pkgb/mcaudit_osag_audit.sql:135-138`

### S-AUDIT-011

- **routines:** add_record
- **claim:** `add_record` resolves the four `short` names exactly as `add_record2`
  (S-AUDIT-009) and calls `add_record_raw2` by name with the resolved ids, its other
  parameters unchanged and a NULL local `v_record_id`, so the record id is allocated and
  discarded and the three Zitadel columns are NULL; `io_transaction_id` is passed through
  IN OUT.
- **source:** `ddl/src/pkgb/mcaudit_osag_audit.sql:132`, `ddl/src/pkgb/mcaudit_osag_audit.sql:135-145`

### S-AUDIT-012

- **routines:** add_record_raw, add_record_raw2, add_record, add_record2
- **claim:** The parameters `i_company_id`, `i_contact_id`, `i_table_name`, `i_object_id`,
  `i_ticket_id` (all four routines) and `i_zitadel_user_id`, `i_zitadel_user_name`,
  `i_zitadel_user_company_id` (`add_record_raw2`, `add_record2`) default to NULL, so every
  routine is callable with only its first seven arguments (`add_record_raw2` /
  `add_record2` additionally need `io_record_id`, which has no default in Oracle; the
  PostgreSQL translation gives it `DEFAULT NULL` because PostgreSQL requires every input
  parameter after a defaulted one to have a default — a NULL there means "allocate", exactly
  Oracle's semantics for an explicit NULL).
- **source:** `ddl/src/pkg/mcaudit_osag_audit.sql:28-32`, `ddl/src/pkg/mcaudit_osag_audit.sql:41-49`, `ddl/src/pkg/mcaudit_osag_audit.sql:59-63`, `ddl/src/pkg/mcaudit_osag_audit.sql:73-81`

### S-AUDIT-013

- **routines:** add_record_raw2
- **claim:** Oracle treats an empty string `''` as NULL for every `VARCHAR2`/`CLOB` value it
  stores: an empty `i_message` violates `message NOT NULL` (ORA-01400 → SQLSTATE `23502`,
  no row), and empty `i_details`, `i_table_name`, `i_zitadel_user_id`,
  `i_zitadel_user_name` are stored / looked up as NULL (`object_type_id` NULL). The
  translation normalizes these five string inputs with `NULLIF(x, '')` at the single
  writer so PostgreSQL stores and rejects exactly what Oracle did.
- **source:** `ddl/src/pkgb/mcaudit_osag_audit.sql:32-38`

### S-AUDIT-014

- **routines:** add_record_raw, add_record_raw2, add_record, add_record2
- **claim:** Each routine's first statement is `plog.AuditUsage(...)` (4 call sites). Per
  XCUT-06 the usage audit is deleted, not ported: the translation contains no AuditUsage
  call and no replacement.
- **source:** `ddl/src/pkgb/mcaudit_osag_audit.sql:23`, `ddl/src/pkgb/mcaudit_osag_audit.sql:56`, `ddl/src/pkgb/mcaudit_osag_audit.sql:99`, `ddl/src/pkgb/mcaudit_osag_audit.sql:134`

### S-AUDIT-015

- **routines:** add_record_raw, add_record_raw2, add_record, add_record2
- **claim:** No routine issues `COMMIT` or `ROLLBACK`; the inserted record lives in the
  caller's transaction and is rolled back with it.
- **source:** `ddl/src/pkgb/mcaudit_osag_audit.sql:6-40`, `ddl/src/pkgb/mcaudit_osag_audit.sql:42-74`, `ddl/src/pkgb/mcaudit_osag_audit.sql:76-113`, `ddl/src/pkgb/mcaudit_osag_audit.sql:115-147`

## Checklist

### 1. Empty-string / NULL handling

String-typed values and every site where they are compared or stored:

- `i_application_short`, `i_component_short`, `i_record_type_short`, `i_severity_short`
  (`add_record` / `add_record2`, `ddl/src/pkg/mcaudit_osag_audit.sql:52-55,66-69`; note
  `i_component_short` is declared `mcaudit.application.short%TYPE`, not
  `component.short%TYPE` — both `VARCHAR2(64)`, harmless): used only in `WHERE short = ...`
  (body 100-103, 135-138). In Oracle `''` is NULL and `short = NULL` matches nothing →
  `NO_DATA_FOUND`; in PostgreSQL `short = ''` matches nothing either (every `short` in
  masterdata is non-empty, and the columns are `NOT NULL`) → the same `no_data_found`.
  Outcome identical; no normalization needed. (a) reachable, (b) no, (c) leave as-is.
- `i_message` (`record.message%TYPE`, `NOT NULL`): stored at body 33-35. Oracle `''` → NULL →
  ORA-01400; PostgreSQL would store an empty string. (a) reachable from any client,
  (b) YES — a naive port accepts what Oracle rejected, (c) `NULLIF(i_message, '')` at the
  writer (S-AUDIT-013).
- `i_details` (`record.details%TYPE`, CLOB, nullable): stored at 33-35. Oracle `''` → NULL
  stored; PostgreSQL would store `''`. (a) reachable, (b) yes for stored-data parity,
  (c) `NULLIF`.
- `i_table_name` (`VARCHAR2`, nullable): used in `WHERE table_name = i_table_name` (37).
  Oracle `''` → NULL → subquery NULL; PostgreSQL `table_name = ''` → no row → NULL as well
  (`table_name` is `NOT NULL`, never empty in practice). Same outcome; normalized anyway
  for uniformity (S-AUDIT-013).
- `i_zitadel_user_id`, `i_zitadel_user_name` (`VARCHAR2(128)`, nullable): stored at 38.
  Same as `i_details` → `NULLIF`.
- No `||` concatenation exists anywhere in this package; no string is ever tested with
  `IS NULL` (the two `IS NULL` tests at 24 and 28 are on numeric IN OUT parameters).

### 2. SELECT INTO strictness

Eight `SELECT ... INTO` sites (the Phase 1 inventory lists `[100, 101, 102, 103, 135,
136, 137, 138]` — cross-checked: the four lookups in `add_record2` and the four in
`add_record`; the scalar subquery at line 37 is not a `SELECT INTO`):

| # | line | routine | lookup | zero rows possible? | >1 row possible? | Oracle handler | translation |
|---|---|---|---|---|---|---|---|
| 1 | 100 | add_record2 | `application.short` | yes (unknown name) | no unique constraint on `short` (only on `name`); masterdata has distinct shorts | none at any scope | `INTO STRICT`; `NO_DATA_FOUND` re-raised as `P0002` with text `no data found` (message-parity shim, externally reachable unhandled site) |
| 2 | 101 | add_record2 | `component.short` | yes | same (no unique on `short`) | none | same |
| 3 | 102 | add_record2 | `record_type.short` | yes | same | none | same |
| 4 | 103 | add_record2 | `severity.short` | yes | no (`UQ_SEVERITY_SHORT` unique) | none | same |
| 5 | 135 | add_record | `application.short` | yes | as #1 | none | same |
| 6 | 136 | add_record | `component.short` | yes | as #2 | none | same |
| 7 | 137 | add_record | `record_type.short` | yes | as #3 | none | same |
| 8 | 138 | add_record | `severity.short` | yes | no | none | same |

`TOO_MANY_ROWS` is theoretically reachable at #1-#3/#5-#7 (no unique constraint on
`short`); Oracle would raise ORA-01422 unhandled, PostgreSQL `STRICT` raises `P0003`
unhandled — identical propagation, no shim (the text differs: `exact fetch returns more
than requested number of rows` vs `query returned more than one row`; rule 1 of
`migration/mapping/sqlstate-map.md`). Inventory cross-check: `exception_handlers`
`NO_DATA_FOUND 0, TOO_MANY_ROWS 0, OTHERS 0` — the package has no `EXCEPTION` block at
all (full 150-line body read).

### 3. Exception codes

No `RAISE_APPLICATION_ERROR`, no named exception, no `EXCEPTION` block anywhere (inventory
`raise_application_error: []`; body read in full). Everything that can fail propagates
unchanged to the caller:

| condition | Oracle | PostgreSQL | where |
|---|---|---|---|
| unknown `short` | ORA-01403 `NO_DATA_FOUND` | `P0002`, text `no data found` (shim) | S-AUDIT-010 |
| duplicate `short` | ORA-01422 `TOO_MANY_ROWS` | `P0003` | S-AUDIT-010 |
| `i_table_name` matching >1 `mss.object_type` row | ORA-01427 | `21000` | S-AUDIT-006 |
| NULL into a `NOT NULL` column | ORA-01400 | `23502` | S-AUDIT-007 |
| FK violation (unknown application/company/contact/ticket id etc.) | ORA-02291 | `23503` (deferred until commit for the DEFERRABLE FKs ora2pg emitted) | not pinned |
| duplicate `io_record_id` | ORA-00001 | `23505` | not pinned |

Nothing for XCUT-01 to map (no `-20NNN` codes). Callers: `GUMA2.OSAG_GUMA` and
`AUTH.OSAG_AUTH_PASSPORT` both wrap their calls in their own `WHEN OTHERS` handlers
(their translation is plans 06-03 and the AUTH work) — this package never branches on a
code.

### 4. Package state

None. The body's declare section is empty: line 1 (`CREATE OR REPLACE PACKAGE BODY
MCAUDIT.OSAG_AUDIT IS`) is followed by two comment lines and `PROCEDURE add_record_raw2`
at line 6; no package-level variable, no `CONSTANT`, no trailing initialization block
(the file ends `END OSAG_AUDIT;` at line 149). Matches the inventory's
`package_state: []`, `has_init_block: false`. The sequences `transaction_seq` /
`record_seq` are schema objects (unqualified in the body, resolved in the package owner's
schema `MCAUDIT`), not package state.

### 5. FUNCTION vs PROCEDURE

All four routines are `PROCEDURE` (`ddl/src/pkg/mcaudit_osag_audit.sql:21,34,52,66`);
`name-map.csv` says `pg_kind=procedure` for all four; the translation creates PostgreSQL
PROCEDUREs (S-AUDIT-001), which is also the only kind that can carry the `IN OUT`
parameters (`io_transaction_id`, `io_record_id`) as `INOUT`. No `COMMIT`, `ROLLBACK` or
`PRAGMA AUTONOMOUS_TRANSACTION` in the body (inventory `has_commit: false`,
`has_rollback: false`, `autonomous_transaction: false`; confirmed by grep) — the audit
record is NOT durable on its own; it lives and dies with the caller's transaction
(S-AUDIT-015). The `PUBLIC SYNONYM osag_audit` (`ddl/src/pkg/mcaudit_osag_audit.sql:85`)
has no PostgreSQL equivalent; callers use the schema-qualified name from `name-map.csv`.

## Assumptions / Unresolved

- **The three `zitadel_user_*` columns are missing from ora2pg's `mcaudit.record`.** The
  Oracle export has them (`ddl/generated/schema.oracle.sql:110`, with the FK
  `FK_RECORD_ZITADEL_USER_COMPANY_ID` at `constraints.oracle.sql:386` and the index at
  `schema.oracle.sql:3618`); `ddl/migrated/tables/tables.pg.sql:627-642` does not. The
  spec assumes the PostgreSQL table carries them (added by an additive schema fix,
  `migration/test/schema-fixes/26_p0601_fixes.sql`); S-AUDIT-004 cannot hold otherwise.
- **`timestamp` column type.** Oracle: `TIMESTAMP(6) WITH TIME ZONE`
  (`ddl/generated/schema.oracle.sql:110`); ora2pg emitted `timestamp without time zone`.
  The translation writes `statement_timestamp()`, implicitly converted to the session time
  zone — a representation difference owned by the DDL migration, not by this package.
  Tests assert "recent", not an exact value.
- **`short` uniqueness.** Only `severity.short` is unique in the schema; a duplicate
  `application`/`component`/`record_type` short would make `add_record`/`add_record2` raise
  `TOO_MANY_ROWS`. Whether production data has duplicates cannot be known from source;
  masterdata (`masterdata/MCAUDIT/*.csv`) has none. Not tested.
- **Sequence consumption on failure.** When `add_record2` fails on a lookup, no sequence
  value is consumed (the lookups precede the allocation); when `add_record_raw2`'s INSERT
  fails, the sequence values already pulled are lost — identical in Oracle and PostgreSQL
  (sequences are non-transactional in both). Not tested.
- **Client call shape.** DBI clients call the procedures positionally (the package header
  explains that overloading was avoided because "when calling from DBI, the overload
  resolution fails", `ddl/src/pkg/mcaudit_osag_audit.sql:18-20`); the PostgreSQL `CALL`
  returns the INOUT values as a result row, which Oracle's bind-variable OUT mechanism did
  not — a client-side adaptation outside this spec.
