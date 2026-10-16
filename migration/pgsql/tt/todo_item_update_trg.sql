-- migration/pgsql/tt/todo_item_update_trg.sql
--
-- Translation of trigger TT.TODO_ITEM_UPDATE_TRG (spec: migration/spec/tt.todo_item_update_trg.md;
-- Oracle source: ddl/src/triggers/TT.sql:11-16). Names from migration/mapping/name-map.csv:
-- kind=trigger -> tt.todo_item_update_trg, kind=trigger_function -> tt.todo_item_update_trg_fn.
--
-- No column list in Oracle, none here: every INSERT and every UPDATE (including one that
-- only assigns update_timestamp) re-stamps the row (S-TITRG-002/003). The ora2pg draft
-- (pg_migration/output/*/TRIGGER.pg.sql) got the shape right but added SECURITY DEFINER,
-- which Oracle's trigger (definer-less, runs as the DML's session) does not have; not used.
--
-- SYSTIMESTAMP -> clock_timestamp(): wall clock at the moment the row trigger fires,
-- advancing across statements of one transaction (S-TITRG-004) -- the same decision as
-- tt/ticket_update_trg.sql, see its header for the rejected alternatives.

CREATE OR REPLACE FUNCTION tt.todo_item_update_trg_fn() RETURNS trigger
LANGUAGE plpgsql
AS $fn$
BEGIN
    NEW.update_timestamp := clock_timestamp();   -- Oracle: :new.update_timestamp := SYSTIMESTAMP
    RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS todo_item_update_trg ON tt.todo_item;

CREATE TRIGGER todo_item_update_trg
    BEFORE INSERT OR UPDATE
    ON tt.todo_item
    FOR EACH ROW
    EXECUTE FUNCTION tt.todo_item_update_trg_fn();
