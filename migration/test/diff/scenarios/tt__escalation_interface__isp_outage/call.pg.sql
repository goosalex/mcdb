-- tt__escalation_interface__isp_outage / call.pg.sql -- PostgreSQL twin of call.ora.sql.
-- Name from migration/mapping/name-map.csv: tt.escalation_interface.escalate_isp_outage_to_os ->
-- tt.escalation_interface_escalate_isp_outage_to_os (procedure -> CALL).
CREATE FUNCTION pg_temp.isp(p_step text, p_event_id numeric) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
    CALL tt.escalation_interface_escalate_isp_outage_to_os(p_event_id);
    INSERT INTO diff_probe (step, s) VALUES (p_step, 'ok');
EXCEPTION WHEN OTHERS THEN
    INSERT INTO diff_probe (step, code, msg) VALUES (p_step, SQLSTATE, left(SQLERRM, 4000));
END $f$;

DO $$
BEGIN
    PERFORM pg_temp.isp('01 ticket host and ticket company',          957521);
    PERFORM pg_temp.isp('02 event host, service company without short', 957522);
    PERFORM pg_temp.isp('03 event company wins',                      957523);
    PERFORM pg_temp.isp('04 no host on event or ticket',              957524);
    PERFORM pg_temp.isp('05 nonexistent event',                       957999999);
END $$;
