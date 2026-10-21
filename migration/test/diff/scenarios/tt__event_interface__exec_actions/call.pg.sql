-- tt__event_interface__exec_actions / call.pg.sql -- PostgreSQL twin of call.ora.sql.
-- Name from migration/mapping/name-map.csv: tt.event_interface.exec_event_type_actions ->
-- tt.event_interface_exec_event_type_actions (procedure -> CALL).
CREATE FUNCTION pg_temp.step(p_step text, p_event_id numeric) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
    CALL tt.event_interface_exec_event_type_actions(p_event_id);
    INSERT INTO diff_probe (step, s) VALUES (p_step, 'ok');
EXCEPTION WHEN OTHERS THEN
    INSERT INTO diff_probe (step, code, msg) VALUES (p_step, SQLSTATE, left(SQLERRM, 4000));
END $f$;

DO $$
BEGIN
    PERFORM pg_temp.step('01 action 1 escalate_os, active host, status 0',      956201);
    PERFORM pg_temp.step('02 pilot action escalate_customer, status 0',         956202);
    PERFORM pg_temp.step('03 pilot action nop, status 20',                      956203);
    PERFORM pg_temp.step('04 pilot action escalate_isp_outage_to_os',           956204);
    PERFORM pg_temp.step('05 pilot action off-allowlist clear_customer_escalation', 956105);
    PERFORM pg_temp.step('06 action 2 DBPROP key 139 with host, no value',      956206);
    PERFORM pg_temp.step('07 unmapped event type',                              956207);
    PERFORM pg_temp.step('08 action 1 escalate_os, inactive host',              956208);
    PERFORM pg_temp.step('09 action 1 escalate_os, closed ticket',              956209);
    PERFORM pg_temp.step('10 action 2 suppressed by service window',            956210);
    PERFORM pg_temp.step('11 nonexistent event',                                956999999);
END $$;
