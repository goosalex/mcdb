-- tt__escalation_interface__escalate / call.pg.sql -- PostgreSQL twin of call.ora.sql.
-- Names from migration/mapping/name-map.csv: tt.escalation_interface.<routine> ->
-- tt.escalation_interface_<routine> (all procedures -> CALL).
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

CREATE FUNCTION pg_temp.nop(p_step text, p_event_id numeric) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
    CALL tt.escalation_interface_nop(p_event_id);
    INSERT INTO diff_probe (step, s) VALUES (p_step, 'ok');
EXCEPTION WHEN OTHERS THEN
    INSERT INTO diff_probe (step, code, msg) VALUES (p_step, SQLSTATE, left(SQLERRM, 4000));
END $f$;

CREATE FUNCTION pg_temp.clear_cust(p_step text, p_ticket_id numeric) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
    CALL tt.escalation_interface_clear_customer_escalation(p_ticket_id);
    INSERT INTO diff_probe (step, s) VALUES (p_step, 'ok');
EXCEPTION WHEN OTHERS THEN
    INSERT INTO diff_probe (step, code, msg) VALUES (p_step, SQLSTATE, left(SQLERRM, 4000));
END $f$;

DO $$
BEGIN
    PERFORM pg_temp.esc_os('01 os active host status 0',            956811);
    PERFORM pg_temp.esc_os('02 os already status 10',               956812);
    PERFORM pg_temp.esc_os('03 os pikett failed status 11',         956813);
    PERFORM pg_temp.esc_os('04 os no host',                         956814);
    PERFORM pg_temp.esc_os('05 os inactive host',                   956815);
    PERFORM pg_temp.esc_os('06 os customer escalation status 20',   956816);
    PERFORM pg_temp.esc_os('07 os dangling host id',                956817);
    PERFORM pg_temp.esc_os('08 os nonexistent event',               956999999);
    PERFORM pg_temp.esc_cust('11 cust active host status 0',        956821);
    PERFORM pg_temp.esc_cust('12 cust status 20 blocks',            956822);
    PERFORM pg_temp.esc_cust('13 cust status 10 blocks',            956823);
    PERFORM pg_temp.esc_cust('14 cust inactive host',               956824);
    PERFORM pg_temp.esc_cust('15 cust no host',                     956825);
    PERFORM pg_temp.esc_cust('16 cust nonexistent event',           956999998);
    PERFORM pg_temp.nop('21 nop nonexistent event',                 956999997);
    PERFORM pg_temp.clear_cust('31 clear status 20',                956731);
    PERFORM pg_temp.clear_cust('32 clear status 10 untouched',      956732);
    PERFORM pg_temp.clear_cust('33 clear nonexistent ticket',       956999996);
END $$;
