-- tt__osag_notify__event_notify / call.pg.sql -- PostgreSQL twin of call.ora.sql.
-- Names from migration/mapping/name-map.csv: tt.osag_notify.event_notify ->
-- tt.osag_notify_event_notify (procedure -> CALL), is_notify_suppressor_active ->
-- tt.osag_notify_is_notify_suppressor_active (function).
CREATE FUNCTION pg_temp.record_state(p_step text, p_ticket numeric) RETURNS void LANGUAGE plpgsql AS $f$
DECLARE v_cust numeric; v_osag numeric;
BEGIN
    SELECT event_notify_count, event_notify_count_osag INTO STRICT v_cust, v_osag FROM tt.ticket WHERE id = p_ticket;
    INSERT INTO diff_probe (step, n, s) VALUES (p_step, v_cust, coalesce(v_osag::text, 'null'));
END $f$;

CREATE FUNCTION pg_temp.step_suppressor(p_step text, p_host numeric) RETURNS void LANGUAGE plpgsql AS $f$
DECLARE v_flag numeric;
BEGIN
    IF tt.osag_notify_is_notify_suppressor_active(p_host) THEN v_flag := 1; ELSE v_flag := 0; END IF;
    INSERT INTO diff_probe (step, n) VALUES (p_step, v_flag);
EXCEPTION WHEN OTHERS THEN
    INSERT INTO diff_probe (step, code, msg) VALUES (p_step, SQLSTATE, left(SQLERRM, 4000));
END $f$;

CREATE FUNCTION pg_temp.step_notify(p_step text, p_event numeric, p_ticket numeric, p_record_ticket numeric) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
    CALL tt.osag_notify_event_notify(p_event, p_ticket);
    PERFORM pg_temp.record_state(p_step, p_record_ticket);
EXCEPTION WHEN OTHERS THEN
    INSERT INTO diff_probe (step, code, msg) VALUES (p_step, SQLSTATE, left(SQLERRM, 4000));
END $f$;

DO $$
BEGIN
    PERFORM pg_temp.record_state('00 initial sms ticket', 958120);
    PERFORM pg_temp.step_suppressor('01 suppressor active window with flag', 958109);
    PERFORM pg_temp.step_suppressor('02 suppressor active window without flag', 958106);
    PERFORM pg_temp.step_suppressor('03 suppressor expired window with flag', 958110);
    PERFORM pg_temp.step_suppressor('04 suppressor unknown host', 958999999);
    PERFORM pg_temp.step_notify('05 notify sms local contact', 958130, NULL, 958120);
    PERFORM pg_temp.step_notify('06 notify mail local contact', 958131, NULL, 958121);
    PERFORM pg_temp.step_notify('07 notify no service', 958132, 958122, 958122);
    PERFORM pg_temp.step_notify('08 notify suppressed', 958133, NULL, 958123);
    PERFORM pg_temp.step_notify('09 notify question not suppressed', 958134, NULL, 958123);
    PERFORM pg_temp.step_notify('10 notify capped automatic early return', 958135, NULL, 958124);
    PERFORM pg_temp.step_notify('11 notify fourth to fifth limit event', 958136, NULL, 958125);
    PERFORM pg_temp.step_notify('12 notify nonexistent event', 958999999, NULL, 958120);
    PERFORM pg_temp.step_notify('13 notify nonexistent ticket', 958130, 958999999, 958120);
END $$;
