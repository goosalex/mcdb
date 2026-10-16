# TT.TICKET_UPDATE_TRG -- FINDINGS

**Source:** `ddl/src/triggers/TT.sql:3-7` (one trigger, five lines). **Spec:**
`migration/spec/tt.ticket_update_trg.md` (5 clauses, prefix TTRG, `oracle_kind: trigger`).
**Target:** `migration/pgsql/tt/ticket_update_trg.sql` (function `tt.ticket_update_trg_fn()`
+ trigger `tt.ticket_update_trg`). **Tests:** `migration/test/pgtap/tt__ticket_update_trg__spec.sql`
(17 assertions).

This is the first non-package object through the spec-first pipeline; the harness tooling
was extended first (commit `chore(harness): accept trigger objects in pkgname.py and
spec_lint.py`) so that `tt__ticket_update_trg__spec.sql` validates against `name-map.csv`'s
`kind=trigger` row and the spec lints against inventory object `TT.TICKET_UPDATE_TRG`.

## Deviations from Oracle

None. Every clause is a faithful translation.

## Decisions

| Oracle | PostgreSQL | Why |
|---|---|---|
| `BEFORE UPDATE OR INSERT OF <13 cols> ... FOR EACH ROW` | `BEFORE INSERT OR UPDATE OF <13 cols> ON tt.ticket FOR EACH ROW` | Oracle's grammar attaches `OF` to the UPDATE event only; PostgreSQL's `UPDATE OF` fires when a listed column is named in SET regardless of value change — the same rule as Oracle (S-TTRG-003, asserted with `SET status_id = status_id`). The list is preserved verbatim (asserted order-independently via `pg_trigger.tgattr`). |
| `:new.update_timestamp := SYSTIMESTAMP` | `NEW.update_timestamp := clock_timestamp(); RETURN NEW;` | `SYSTIMESTAMP` is the OS clock at evaluation, per row firing. `clock_timestamp()` is the only PostgreSQL function with that property; `statement_timestamp()` would give every row of one statement the same stamp, `now()` every statement of one transaction (S-TTRG-005 asserts two UPDATEs in one transaction stamp strictly increasing values — `now()` would fail it). |
| trigger body (anonymous) | `tt.ticket_update_trg_fn()` RETURNS trigger | PostgreSQL requires a function; name from `name-map.csv`'s `kind=trigger_function` row. No `SECURITY DEFINER` (the ora2pg draft added one; Oracle triggers run with the DML's privileges, and nothing here needs elevation). |
| `CREATE OR REPLACE TRIGGER` | `DROP TRIGGER IF EXISTS` + `CREATE TRIGGER` | `CREATE OR REPLACE TRIGGER` exists since PG 14 but cannot change the column list of an existing trigger in all cases; drop+create is unambiguous and idempotent. |

## ora2pg draft (raw material, not trusted)

`pg_migration/output/package_in_name/TRIGGER.pg.sql:40-52`: `BEFORE INSERT OR UPDATE ON
ticket` — the 13-column list is **gone**, so every bookkeeping UPDATE (counters, summaries)
would move the change watermark `TICKETEVOLUTION.CALCULATOR.materialize_incremental` reads,
re-materializing tickets needlessly; also unqualified `ticket`, a `trigger_fct_` name not in
`name-map.csv`, `statement_timestamp()`, and `SECURITY DEFINER`. **Mutation evidence:**
loading this translation with the column list removed (ora2pg's shape) turns tests 3
(column list) and 8, 9, 10 (S-TTRG-004: an UPDATE of only update_timestamp /
summary_public / priority must NOT stamp) red — `Failed 4/17 subtests`; restoring the list
returns 17/17.

## Interplay with other translations

- `migration/pgsql/ticketevolution/calculator.sql` reads `tt.ticket.update_timestamp`
  (`date_trunc('second', ...) > LAST_RUN`). With this trigger installed, every INSERT into
  `tt.ticket` in any test now carries the insert time; the calculator regress golden was
  written to be independent of whether the trigger exists (it sets `update_timestamp`
  explicitly only in an UPDATE naming nothing else — which, per S-TTRG-004, the trigger
  leaves alone). Verified: the full `--install migration/pgsql` run keeps
  `ticketevolution.calculator` at 62/62 + 1/1 with the trigger present.
- `TT.TICKET_INTERFACE` / `TT.EVENT_INTERFACE` tests insert and update `tt.ticket` freely;
  none asserts on `update_timestamp` (`grep -rn update_timestamp migration/test/` finds
  only this trigger's and the calculator's files), so installing the trigger changes no
  other package's result.

## Schema note (not this trigger's to fix)

Oracle: `UPDATE_TIMESTAMP TIMESTAMP(6) WITH TIME ZONE DEFAULT SYSDATE NOT NULL`
(`ddl/generated/schema.oracle.sql:203`); migrated: `timestamp NOT NULL DEFAULT
statement_timestamp()` (`ddl/migrated/tables/tables.pg.sql:1000`) — time zone dropped by
ora2pg. The trigger assigns `clock_timestamp()` and lets the column's type decide; if Phase 5
restores `timestamptz`, nothing here changes. The Oracle index
`TT.IDX_TICKET_UPDATETIME ON TT.TICKET(SYS_EXTRACT_UTC("UPDATE_TIMESTAMP"))`
(`ddl/generated/schema.oracle.sql:3928`) is the consumer that cares about the zone.

## Red/green status (verified live on `mcdb_test_tickev`)

- **RED** (nothing installed): 3/17 — the three S-TTRG-004 "value sticks" checks hold
  vacuously when no trigger exists at all; everything else red, exit 1.
- **GREEN** (`--install migration/pgsql`): 17/17, exit 0. No test amendment needed.
