# TT.TODO_ITEM_UPDATE_TRG -- FINDINGS

**Source:** `ddl/src/triggers/TT.sql:11-16` (one trigger, six lines). **Spec:**
`migration/spec/tt.todo_item_update_trg.md` (4 clauses, prefix TITRG, `oracle_kind: trigger`).
**Target:** `migration/pgsql/tt/todo_item_update_trg.sql` (function
`tt.todo_item_update_trg_fn()` + trigger `tt.todo_item_update_trg`). **Tests:**
`migration/test/pgtap/tt__todo_item_update_trg__spec.sql` (12 assertions).

## Deviations from Oracle

None.

## Decisions

Same as `ticket_update_trg.FINDINGS.md`, minus the column list: `BEFORE INSERT OR UPDATE ON
tt.todo_item FOR EACH ROW` with no `OF`, so every UPDATE — including one whose SET list is
only `update_timestamp` — re-stamps the row with `clock_timestamp()` (S-TITRG-003; asserted
by updating `update_timestamp` to a sentinel and checking it did not stick). `RETURN NEW`;
no `SECURITY DEFINER`; `DROP TRIGGER IF EXISTS` + `CREATE TRIGGER` for idempotency.

Consequence worth stating plainly for application code: with this trigger enabled,
`tt.todo_item.update_timestamp` cannot be set to a chosen value by any INSERT or UPDATE —
exactly as in Oracle. A data-migration load that needs to preserve historical values must
`ALTER TABLE tt.todo_item DISABLE TRIGGER todo_item_update_trg` for the load (Oracle: `ALTER
TRIGGER ... DISABLE`), which is a loader concern, not this translation's.

## ora2pg draft (raw material, not trusted)

`pg_migration/output/package_in_name/TRIGGER.pg.sql:54-66`: shape correct (no column list),
but unqualified `todo_item`, a `trigger_fct_` name not in `name-map.csv`,
`statement_timestamp()` instead of a per-firing clock, and `SECURITY DEFINER`. Not used.

## Interplay with other translations

`TT.TICKET_INTERFACE.deleteTicket` (translated in `migration/pgsql/tt/ticket_interface.sql`)
deletes `tt.todo_item` rows — DELETE never fires this trigger (tgtype asserted = 23, no
DELETE bit). No test in the harness asserts on `tt.todo_item.update_timestamp` besides this
one, and no `ddl/src/pkgb/**` routine reads it.

## Schema note (not this trigger's to fix)

Oracle: `UPDATE_TIMESTAMP TIMESTAMP(6) WITH TIME ZONE DEFAULT SYSDATE NOT NULL`
(`ddl/generated/schema.oracle.sql:588`); migrated: `timestamp NOT NULL DEFAULT
statement_timestamp()` (`ddl/migrated/tables/tables.pg.sql:2522`) — time zone dropped by
ora2pg, same drift as `tt.ticket`.

## Red/green status (verified live on `mcdb_test_tickev`)

- **RED** (nothing installed): 0/12, exit 1.
- **GREEN** (`--install migration/pgsql`): 12/12, exit 0. No test amendment needed.
