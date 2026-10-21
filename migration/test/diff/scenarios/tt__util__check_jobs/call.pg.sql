-- tt__util__check_jobs / call.pg.sql -- PostgreSQL twin of call.ora.sql.
-- Names from migration/mapping/name-map.csv: tt.util.check_resolved_tickets ->
-- tt.util_check_resolved_tickets, check_ticket_status -> tt.util_check_ticket_status,
-- check_dnids_tickets_to_resolve -> tt.util_check_dnids_tickets_to_resolve,
-- update_status_valid_until -> tt.util_update_status_valid_until (all procedures -> CALL).
-- The date argument is passed by name as a plain timestamp (localtimestamp): Oracle's
-- SYSDATE + n is a DATE, the translation's parameter is timestamp without time zone.
CREATE FUNCTION pg_temp.record_state(p_step text) RETURNS void LANGUAGE plpgsql AS $f$
DECLARE v_closed numeric; v_hot numeric; v_resolved numeric; v_waiting numeric;
BEGIN
    SELECT sum(CASE WHEN status_id = 102 THEN 1 ELSE 0 END), sum(CASE WHEN status_id = 3 THEN 1 ELSE 0 END),
           sum(CASE WHEN status_id = 101 THEN 1 ELSE 0 END), sum(CASE WHEN status_id IN (11, 12, 60, 61) THEN 1 ELSE 0 END)
    INTO v_closed, v_hot, v_resolved, v_waiting
    FROM tt.ticket WHERE id BETWEEN 958310 AND 958347;
    INSERT INTO diff_probe (step, n, s) VALUES (p_step, v_closed, 'hot=' || v_hot || ' resolved=' || v_resolved || ' waiting=' || v_waiting);
END $f$;

CREATE FUNCTION pg_temp.step_resolved(p_step text) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
    CALL tt.util_check_resolved_tickets();
    PERFORM pg_temp.record_state(p_step);
EXCEPTION WHEN OTHERS THEN
    INSERT INTO diff_probe (step, code, msg) VALUES (p_step, SQLSTATE, left(SQLERRM, 4000));
END $f$;

CREATE FUNCTION pg_temp.step_status(p_step text) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
    CALL tt.util_check_ticket_status();
    PERFORM pg_temp.record_state(p_step);
EXCEPTION WHEN OTHERS THEN
    INSERT INTO diff_probe (step, code, msg) VALUES (p_step, SQLSTATE, left(SQLERRM, 4000));
END $f$;

CREATE FUNCTION pg_temp.step_dnids(p_step text) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
    CALL tt.util_check_dnids_tickets_to_resolve();
    PERFORM pg_temp.record_state(p_step);
EXCEPTION WHEN OTHERS THEN
    INSERT INTO diff_probe (step, code, msg) VALUES (p_step, SQLSTATE, left(SQLERRM, 4000));
END $f$;

CREATE FUNCTION pg_temp.step_usvu(p_step text, p_ticket numeric, p_date timestamp) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
    IF p_date IS NULL THEN
        CALL tt.util_update_status_valid_until(p_ticket);
    ELSE
        CALL tt.util_update_status_valid_until(p_ticket, p_valid_until_date => p_date);
    END IF;
    PERFORM pg_temp.record_state(p_step);
EXCEPTION WHEN OTHERS THEN
    INSERT INTO diff_probe (step, code, msg) VALUES (p_step, SQLSTATE, left(SQLERRM, 4000));
END $f$;

DO $$
BEGIN
    PERFORM pg_temp.record_state('00 initial');
    PERFORM pg_temp.step_resolved('01 check_resolved_tickets');
    PERFORM pg_temp.step_usvu('02 usvu waiting default 20d', 958340, NULL);
    PERFORM pg_temp.step_usvu('03 usvu emergency default 4h', 958341, NULL);
    PERFORM pg_temp.step_usvu('04 usvu third party explicit 10d', 958342, localtimestamp + interval '10 days');
    PERFORM pg_temp.step_usvu('05 usvu waiting explicit 90d over cap', 958343, localtimestamp + interval '90 days');
    PERFORM pg_temp.step_usvu('06 usvu emergency explicit 2d over cap', 958344, localtimestamp + interval '2 days');
    PERFORM pg_temp.step_usvu('07 usvu deferred no-op', 958345, NULL);
    PERFORM pg_temp.step_usvu('08 usvu open resets to null', 958346, NULL);
    PERFORM pg_temp.step_usvu('09 usvu waiting explicit past date', 958347, localtimestamp - interval '1 day');
    PERFORM pg_temp.step_usvu('10 usvu nonexistent ticket', 958999999, NULL);
    PERFORM pg_temp.step_status('11 check_ticket_status');
    PERFORM pg_temp.step_dnids('12 check_dnids_tickets_to_resolve');
END $$;
