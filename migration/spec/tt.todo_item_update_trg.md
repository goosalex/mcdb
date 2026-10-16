---
oracle_schema: TT
oracle_package: TODO_ITEM_UPDATE_TRG
oracle_kind: trigger
pg_schema: tt
pg_prefix: todo_item_update_trg
clause_prefix: TITRG
oracle_spec: ddl/src/triggers/TT.sql
oracle_body: ddl/src/triggers/TT.sql
public_routines: 1
---

# TT.TODO_ITEM_UPDATE_TRG — PostgreSQL spec

A `BEFORE INSERT OR UPDATE ... FOR EACH ROW` trigger on `TT.TODO_ITEM` that stamps
`:new.update_timestamp := SYSTIMESTAMP` (`ddl/src/triggers/TT.sql:11-16`). Unlike its
sibling `TT.TICKET_UPDATE_TRG` it has NO column list: every UPDATE of a todo item, whatever
columns it touches, re-stamps the row. The Oracle column comment agrees: "Tells when the
row was last updated. This column is updated by the trigger tt.todo_item_update_trg"
(`ddl/generated/schema.oracle.sql:590`).

`oracle_kind: trigger` above tells `spec_lint.py` to match this spec against the
`kind=trigger` row of `name-map.csv` and inventory object `TT.TODO_ITEM_UPDATE_TRG`; the
one "routine" is the trigger itself.

## Routines

### todo_item_update_trg

- **Oracle signature:** `TRIGGER tt.todo_item_update_trg BEFORE INSERT OR UPDATE ON tt.todo_item FOR EACH ROW`
- **PostgreSQL name:** trigger `tt.todo_item_update_trg` on `tt.todo_item`, executing
  function `tt.todo_item_update_trg_fn()` (both from `name-map.csv`: `kind=trigger` →
  `todo_item_update_trg`, `kind=trigger_function` → `todo_item_update_trg_fn`)
- **Declared:** `ddl/src/triggers/TT.sql:11`
- **Defined:** `ddl/src/triggers/TT.sql:11-16`
- Sets the new row's `update_timestamp` to the current system time. No other side effect,
  no reads, no exception handling.

## Clauses

### S-TITRG-001

- **routines:** todo_item_update_trg
- **claim:** The trigger is a row-level (`FOR EACH ROW`) `BEFORE` trigger on `TT.TODO_ITEM`
  for events INSERT and UPDATE, with NO `OF column-list` — it fires on every INSERT and on
  every UPDATE, whichever columns the SET list names. It never fires on DELETE. The
  PostgreSQL translation is `BEFORE INSERT OR UPDATE ON tt.todo_item FOR EACH ROW`
  (no column list), executing `tt.todo_item_update_trg_fn()` (a function returning
  `trigger`).
- **source:** `ddl/src/triggers/TT.sql:11-13`

### S-TITRG-002

- **routines:** todo_item_update_trg
- **claim:** On INSERT, `update_timestamp` of the inserted row is the current system time
  at the moment the trigger fires, REGARDLESS of any value the INSERT statement supplied
  for that column (the assignment is unconditional; an explicit `update_timestamp` in the
  INSERT is overwritten, and the column DEFAULT is irrelevant).
- **source:** `ddl/src/triggers/TT.sql:12`, `ddl/src/triggers/TT.sql:15`

### S-TITRG-003

- **routines:** todo_item_update_trg
- **claim:** On ANY UPDATE of a `tt.todo_item` row, `update_timestamp` is set to the
  current system time — whether the SET list names `details`, `todo_item_status_id`,
  `seq_no`, `is_public`, `ticket_id`, or ONLY `update_timestamp` itself. Consequently
  `update_timestamp` can never be set to an arbitrary value by an UPDATE while this trigger
  is enabled: an explicit assignment is always overwritten by the trigger.
- **source:** `ddl/src/triggers/TT.sql:12`, `ddl/src/triggers/TT.sql:15`

### S-TITRG-004

- **routines:** todo_item_update_trg
- **claim:** The stamped value is `SYSTIMESTAMP` — the database server's wall clock at the
  moment the row trigger fires (fractional seconds included), not the transaction start
  and not the statement start; a second UPDATE in the same transaction stamps a later time
  than the first. Translation: `clock_timestamp()`, assigned to the `timestamp` column
  `tt.todo_item.update_timestamp` (the migrated DDL's type for Oracle's
  `TIMESTAMP(6) WITH TIME ZONE`, see Assumptions).
- **source:** `ddl/src/triggers/TT.sql:15`

## Checklist

### 1. Empty-string / NULL handling

N/A — the trigger body is a single assignment of `SYSTIMESTAMP` to a `TIMESTAMP` column
(`ddl/src/triggers/TT.sql:15`); there is no `VARCHAR2` identifier, no `IS NULL` check, no
comparison and no concatenation anywhere in it.

### 2. SELECT INTO strictness

N/A — no `SELECT ... INTO` (the body is one assignment, `ddl/src/triggers/TT.sql:14-16`);
the inventory's `select_into_sites: []` agrees.

### 3. Exception codes

None — no `RAISE_APPLICATION_ERROR`, no named exception, no handler
(`ddl/src/triggers/TT.sql:14-16`; inventory `raise_application_error: []`, handlers 0/0/0).

### 4. Package state

N/A — a trigger has no package body, no declare section and no initialisation block
(`ddl/src/triggers/TT.sql:11-16` is the entire object); inventory `package: null`.

### 5. FUNCTION vs PROCEDURE

No `COMMIT`/`ROLLBACK`/`PRAGMA AUTONOMOUS_TRANSACTION` (`ddl/src/triggers/TT.sql:14-16`;
inventory `has_commit: false`, `has_rollback: false`, `autonomous_transaction: false`).
A PostgreSQL trigger body must be a FUNCTION returning `trigger` —
`tt.todo_item_update_trg_fn()` per `name-map.csv` — which can never commit anyway. The
function `RETURN`s `NEW` so the modified row is what gets written.

## Assumptions / Unresolved

- **Column type drift in the migrated DDL.** Oracle declares `TT.TODO_ITEM.UPDATE_TIMESTAMP`
  as `TIMESTAMP(6) WITH TIME ZONE DEFAULT SYSDATE NOT NULL` (`ddl/generated/schema.oracle.sql:588`);
  the ora2pg DDL in `ddl/migrated/tables/tables.pg.sql:2522` made it `timestamp NOT NULL
  DEFAULT statement_timestamp()` — WITHOUT time zone. Assigning `clock_timestamp()` stores
  the server's local time. Whether the column should become `timestamptz` is a
  schema-migration question (Phase 5), not this trigger's.
- **`TT.TICKET_INTERFACE.deleteTicket` and other callers** that UPDATE `tt.todo_item` get a
  fresh `update_timestamp` on every such statement in PostgreSQL exactly as in Oracle; no
  caller in `ddl/src/pkgb/**` reads `tt.todo_item.update_timestamp`
  (`grep -rn update_timestamp ddl/src/pkgb` finds only the ticket-side uses), so nothing
  downstream depends on its precise value.
- Nothing else is unresolved: the whole object is six lines
  (`ddl/src/triggers/TT.sql:11-16`), reviewed in full.
