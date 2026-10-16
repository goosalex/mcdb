-- migration/pgsql/tt/ticket_update_trg.sql
--
-- Translation of trigger TT.TICKET_UPDATE_TRG (spec: migration/spec/tt.ticket_update_trg.md;
-- Oracle source: ddl/src/triggers/TT.sql:3-7). Names from migration/mapping/name-map.csv:
-- kind=trigger -> tt.ticket_update_trg, kind=trigger_function -> tt.ticket_update_trg_fn.
--
-- Oracle's event clause `BEFORE UPDATE OR INSERT OF <13 columns>` attaches the OF list to
-- the UPDATE event only (Oracle grammar: {DELETE | INSERT | UPDATE [OF col, ...]}), i.e.
-- every INSERT plus UPDATE of any listed column. PostgreSQL's `UPDATE OF` has the same
-- "column named in SET, whether or not its value changes" semantics (S-TTRG-003/004).
-- The ora2pg draft (pg_migration/output/*/TRIGGER.pg.sql) dropped the column list
-- entirely and added SECURITY DEFINER -- both wrong; not used.
--
-- SYSTIMESTAMP -> clock_timestamp(): Oracle's SYSTIMESTAMP is the OS clock at the moment
-- of evaluation, so each row-trigger firing (even within one statement or transaction)
-- gets its own, advancing value (S-TTRG-005). statement_timestamp() would freeze all
-- rows of a statement to one value and transaction_timestamp()/now() would freeze a
-- whole transaction -- neither is what Oracle does. The column is `timestamp` (without
-- time zone) in the migrated DDL; the assignment stores the server-local time -- see the
-- spec's Assumptions for the type-drift note (Oracle: TIMESTAMP(6) WITH TIME ZONE).

CREATE OR REPLACE FUNCTION tt.ticket_update_trg_fn() RETURNS trigger
LANGUAGE plpgsql
AS $fn$
BEGIN
    NEW.update_timestamp := clock_timestamp();   -- Oracle: :new.update_timestamp := SYSTIMESTAMP
    RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS ticket_update_trg ON tt.ticket;

CREATE TRIGGER ticket_update_trg
    BEFORE INSERT OR UPDATE OF
        type_id, status_id, subject, host_id, mss_service_id, company_id, contact_id,
        customer_reference, emergency, always_visible, handled_by_mcc,
        customer_ticket_rating_id, last_public_event_id
    ON tt.ticket
    FOR EACH ROW
    EXECUTE FUNCTION tt.ticket_update_trg_fn();
