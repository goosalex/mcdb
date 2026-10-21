-- tt__escalation_interface__closed_ticket / call.pg.sql -- PostgreSQL twin of call.ora.sql.
-- Names from migration/mapping/name-map.csv: tt.escalation_interface.escalate_os ->
-- tt.escalation_interface_escalate_os, escalate_customer likewise (procedures -> CALL).
-- The EXCEPTION block of each wrapper is a subtransaction in PL/pgSQL -- see meta.env.
CREATE FUNCTION pg_temp.esc_os(p_step text, p_event_id numeric) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
    CALL tt.escalation_interface_escalate_os(p_event_id);
    INSERT INTO diff_probe (step, s) VALUES (p_step, 'ok');
EXCEPTION WHEN OTHERS THEN
    INSERT INTO diff_probe (step, code, msg) VALUES (p_step, SQLSTATE, left(SQLERRM, 4000));
END $f$;

CREATE FUNCTION pg_temp.esc_cust(p_step text, p_event_id numeric) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
    CALL tt.escalation_interface_escalate_customer(p_event_id);
    INSERT INTO diff_probe (step, s) VALUES (p_step, 'ok');
EXCEPTION WHEN OTHERS THEN
    INSERT INTO diff_probe (step, code, msg) VALUES (p_step, SQLSTATE, left(SQLERRM, 4000));
END $f$;

DO $$
BEGIN
    PERFORM pg_temp.esc_os('01 escalate_os closed ticket',         956921);
    PERFORM pg_temp.esc_cust('02 escalate_customer closed ticket', 956922);
END $$;
