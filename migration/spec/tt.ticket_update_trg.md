---
oracle_schema: TT
oracle_package: TICKET_UPDATE_TRG
oracle_kind: trigger
pg_schema: tt
pg_prefix: ticket_update_trg
clause_prefix: TTRG
oracle_spec: ddl/src/triggers/TT.sql
oracle_body: ddl/src/triggers/TT.sql
public_routines: 1
---

# TT.TICKET_UPDATE_TRG — PostgreSQL spec

A `BEFORE ... FOR EACH ROW` trigger on `TT.TICKET` that stamps
`:new.update_timestamp := SYSTIMESTAMP` (`ddl/src/triggers/TT.sql:3-7`). It fires on every
INSERT and on an UPDATE that names at least one of thirteen listed columns — the column list
is the whole point of this trigger: `TT.EVENT_INTERFACE` deliberately updates
`last_public_event_id` in a separate statement "to avoid unnecessary update_timestamp
updates on the ticket" (`ddl/src/pkgb/tt_event_interface.sql:785`), and
`TICKETEVOLUTION.CALCULATOR.materialize_incremental` uses `update_timestamp` as its
change watermark (`ddl/src/pkgb/ticketevolution_calculator.sql:204`). The column comment
in the Oracle DDL says the same: "This column is updated by the trigger
tt.ticket_update_trg" (`ddl/generated/schema.oracle.sql:223`).

This is a trigger, not a package: `oracle_kind: trigger` above tells `spec_lint.py` to
match it against the `kind=trigger` row of `name-map.csv` and inventory object
`TT.TICKET_UPDATE_TRG`. The one "routine" is the trigger itself.

## Routines

### ticket_update_trg

- **Oracle signature:** `TRIGGER "TT"."TICKET_UPDATE_TRG" BEFORE UPDATE OR INSERT OF "TYPE_ID", "STATUS_ID", "SUBJECT", "HOST_ID", "MSS_SERVICE_ID", "COMPANY_ID", "CONTACT_ID", "CUSTOMER_REFERENCE", "EMERGENCY", "ALWAYS_VISIBLE", "HANDLED_BY_MCC", "CUSTOMER_TICKET_RATING_ID", "LAST_PUBLIC_EVENT_ID" ON "TT"."TICKET" REFERENCING OLD AS OLD NEW AS NEW FOR EACH ROW`
- **PostgreSQL name:** trigger `tt.ticket_update_trg` on `tt.ticket`, executing function
  `tt.ticket_update_trg_fn()` (both from `name-map.csv`: `kind=trigger` →
  `ticket_update_trg`, `kind=trigger_function` → `ticket_update_trg_fn`)
- **Declared:** `ddl/src/triggers/TT.sql:3`
- **Defined:** `ddl/src/triggers/TT.sql:3-7`
- Sets the new row's `update_timestamp` to the current system time. No other side effect,
  no reads, no exception handling.

## Clauses

### S-TTRG-001

- **routines:** ticket_update_trg
- **claim:** The trigger is a row-level (`FOR EACH ROW`) `BEFORE` trigger on `TT.TICKET`
  for events INSERT and UPDATE. In Oracle's DML-event clause the `OF column-list` can only
  qualify UPDATE (`{DELETE | INSERT | UPDATE [OF column, ...]}`), so the written
  `UPDATE OR INSERT OF ...` means: every INSERT, plus UPDATE of any of the thirteen
  columns `TYPE_ID, STATUS_ID, SUBJECT, HOST_ID, MSS_SERVICE_ID, COMPANY_ID, CONTACT_ID,
  CUSTOMER_REFERENCE, EMERGENCY, ALWAYS_VISIBLE, HANDLED_BY_MCC, CUSTOMER_TICKET_RATING_ID,
  LAST_PUBLIC_EVENT_ID` — exactly those thirteen, no more, no fewer. It never fires on
  DELETE. The PostgreSQL translation is `BEFORE INSERT OR UPDATE OF <those 13 columns> ON
  tt.ticket FOR EACH ROW`, executing `tt.ticket_update_trg_fn()` (a function returning
  `trigger`).
- **source:** `ddl/src/triggers/TT.sql:3-4`

### S-TTRG-002

- **routines:** ticket_update_trg
- **claim:** On INSERT, `update_timestamp` of the inserted row is the current system time
  at the moment the trigger fires, REGARDLESS of any value the INSERT statement supplied
  for that column (the assignment is unconditional; an explicit
  `update_timestamp` in the INSERT is overwritten, and the column DEFAULT is irrelevant).
- **source:** `ddl/src/triggers/TT.sql:3`, `ddl/src/triggers/TT.sql:6`

### S-TTRG-003

- **routines:** ticket_update_trg
- **claim:** On an UPDATE whose SET list names at least one of the thirteen listed
  columns, `update_timestamp` is set to the current system time — even when the listed
  column's value does not actually change (Oracle's `UPDATE OF col` fires on the column
  being NAMED in SET, not on its value changing; PostgreSQL's `UPDATE OF col` has the same
  semantics), and even when the same statement also assigns `update_timestamp` explicitly
  (the trigger runs after the SET list is applied to `:new` and overwrites it).
- **source:** `ddl/src/triggers/TT.sql:3`, `ddl/src/triggers/TT.sql:6`

### S-TTRG-004

- **routines:** ticket_update_trg
- **claim:** On an UPDATE whose SET list names NONE of the thirteen listed columns (for
  example `summary_public`, `priority`, `worker_id`, `last_resolved_date`, or
  `update_timestamp` itself), the trigger does not fire: `update_timestamp` keeps its
  previous value — or takes the value the statement explicitly assigned to it, which is
  the only way `update_timestamp` can be set by hand while the trigger is enabled. This
  is the behaviour the column list exists for: bulk bookkeeping updates (counters,
  summaries, dates) must not move the change watermark that
  `TICKETEVOLUTION.CALCULATOR.materialize_incremental` reads.
- **source:** `ddl/src/triggers/TT.sql:3`

### S-TTRG-005

- **routines:** ticket_update_trg
- **claim:** The stamped value is `SYSTIMESTAMP` — the database server's wall clock at the
  moment the row trigger fires (fractional seconds included), not the transaction start
  and not the statement start. Two rows touched by one multi-row statement may therefore
  carry different `update_timestamp` values, and a second UPDATE in the same transaction
  stamps a later time than the first. Translation: `clock_timestamp()` (the PostgreSQL
  function with exactly these semantics), assigned to the `timestamp` column
  `tt.ticket.update_timestamp` (the migrated DDL's type for Oracle's
  `TIMESTAMP(6) WITH TIME ZONE`, see Assumptions).
- **source:** `ddl/src/triggers/TT.sql:6`

## Checklist

### 1. Empty-string / NULL handling

N/A — the trigger body is a single assignment of `SYSTIMESTAMP` to a `TIMESTAMP` column
(`ddl/src/triggers/TT.sql:6`); there is no `VARCHAR2` identifier, no `IS NULL` check, no
comparison and no concatenation anywhere in it. The thirteen column names in the event
clause are metadata, not values.

### 2. SELECT INTO strictness

N/A — no `SELECT ... INTO` (the body is one assignment, `ddl/src/triggers/TT.sql:5-7`);
the inventory's `select_into_sites: []` agrees.

### 3. Exception codes

None — no `RAISE_APPLICATION_ERROR`, no named exception, no handler
(`ddl/src/triggers/TT.sql:5-7`; inventory `raise_application_error: []`, handlers 0/0/0).
The only error a translation can raise is a NOT NULL violation that cannot happen (the
trigger always assigns a non-NULL value).

### 4. Package state

N/A — a trigger has no package body, no declare section and no initialisation block
(`ddl/src/triggers/TT.sql:3-7` is the entire object); inventory `package: null`.

### 5. FUNCTION vs PROCEDURE

No `COMMIT`/`ROLLBACK`/`PRAGMA AUTONOMOUS_TRANSACTION` (`ddl/src/triggers/TT.sql:5-7`;
inventory `has_commit: false`, `has_rollback: false`, `autonomous_transaction: false`).
A PostgreSQL trigger body must be a FUNCTION returning `trigger` — `tt.ticket_update_trg_fn()`
per `name-map.csv` — and a trigger function can never commit anyway, so there is no
FUNCTION-vs-PROCEDURE question here. The function `RETURN`s `NEW` so the modified row is
what gets written (a BEFORE ROW trigger returning NULL would silently skip the row).

## Assumptions / Unresolved

- **Column type drift in the migrated DDL.** Oracle declares `TT.TICKET.UPDATE_TIMESTAMP`
  as `TIMESTAMP(6) WITH TIME ZONE DEFAULT SYSDATE NOT NULL` (`ddl/generated/schema.oracle.sql:203`);
  the ora2pg DDL in `ddl/migrated/tables/tables.pg.sql:1000` made it
  `timestamp NOT NULL DEFAULT statement_timestamp()` — WITHOUT time zone. Assigning
  `clock_timestamp()` (timestamptz) to it stores the server's local time, which is what
  Oracle's `SYSTIMESTAMP` into a WITH TIME ZONE column would show in the session's zone.
  Whether the column should become `timestamptz` is a schema-migration question (Phase 5),
  not this trigger's; the trigger assigns whatever the column's type accepts.
- **Oracle `UPDATE OR INSERT OF ...` parsing.** The event clause is written in an unusual
  order (`UPDATE OR INSERT OF cols`). Oracle's grammar attaches an `OF` list to the UPDATE
  event only, so the reading "INSERT always; UPDATE of listed columns" (S-TTRG-001) is the
  only grammatical one; Phase 1's lexer recorded the same events
  (`events: ["INSERT", "UPDATE"]`). No live Oracle to confirm the compiled trigger's
  `TRIGGER_EVENT`; the reading is nevertheless unambiguous from the grammar.
- **Column list vs the migrated table.** All thirteen columns exist on the migrated
  `tt.ticket` (`ddl/migrated/tables/tables.pg.sql:962-1011`), so no column needs dropping
  from the list; the Oracle-only columns `CONTACT_ZITADEL_ID`/`WORKER_ZITADEL_ID`
  (`ddl/generated/schema.oracle.sql:203`, absent from the migrated DDL) are not in the
  list and do not matter here.
- Nothing else is unresolved: the whole object is five lines
  (`ddl/src/triggers/TT.sql:3-7`), reviewed in full.
