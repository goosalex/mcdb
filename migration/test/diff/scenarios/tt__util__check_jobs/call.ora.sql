-- tt__util__check_jobs / call.ora.sql
-- After every step the status histogram of the fixture tickets is recorded (n = closed,
-- s = 'hot=<n> resolved=<n> waiting=<n>'), so each job's effect is compared step by step.
DECLARE
    -- SQLCODE/SQLERRM may not appear inside a SQL statement (ORA-00984); pass them as arguments.
    PROCEDURE log_err(p_step VARCHAR2, p_code NUMBER, p_msg VARCHAR2) IS
    BEGIN
        INSERT INTO diff_probe (step, code, msg) VALUES (p_step, TO_CHAR(p_code), SUBSTR(p_msg, 1, 4000));
    END;

    PROCEDURE record_state(p_step VARCHAR2) IS
        v_closed NUMBER; v_hot NUMBER; v_resolved NUMBER; v_waiting NUMBER;
    BEGIN
        SELECT SUM(CASE WHEN status_id = 102 THEN 1 ELSE 0 END), SUM(CASE WHEN status_id = 3 THEN 1 ELSE 0 END),
               SUM(CASE WHEN status_id = 101 THEN 1 ELSE 0 END), SUM(CASE WHEN status_id IN (11, 12, 60, 61) THEN 1 ELSE 0 END)
        INTO v_closed, v_hot, v_resolved, v_waiting
        FROM tt.ticket WHERE id BETWEEN 958310 AND 958347;
        INSERT INTO diff_probe (step, n, s) VALUES (p_step, v_closed, 'hot=' || v_hot || ' resolved=' || v_resolved || ' waiting=' || v_waiting);
    END;

    PROCEDURE step_resolved(p_step VARCHAR2) IS
    BEGIN
        tt.util.check_resolved_tickets;
        record_state(p_step);
    EXCEPTION WHEN OTHERS THEN
        log_err(p_step, SQLCODE, SQLERRM);
    END;

    PROCEDURE step_status(p_step VARCHAR2) IS
    BEGIN
        tt.util.check_ticket_status;
        record_state(p_step);
    EXCEPTION WHEN OTHERS THEN
        log_err(p_step, SQLCODE, SQLERRM);
    END;

    PROCEDURE step_dnids(p_step VARCHAR2) IS
    BEGIN
        tt.util.check_dnids_tickets_to_resolve;
        record_state(p_step);
    EXCEPTION WHEN OTHERS THEN
        log_err(p_step, SQLCODE, SQLERRM);
    END;

    PROCEDURE step_usvu(p_step VARCHAR2, p_ticket NUMBER, p_date DATE) IS
    BEGIN
        IF p_date IS NULL THEN
            tt.util.update_status_valid_until(p_ticket);
        ELSE
            tt.util.update_status_valid_until(p_ticket, p_date);
        END IF;
        record_state(p_step);
    EXCEPTION WHEN OTHERS THEN
        log_err(p_step, SQLCODE, SQLERRM);
    END;
BEGIN
    record_state('00 initial');
    -- S-UTIL-001
    step_resolved('01 check_resolved_tickets');
    -- S-UTIL-003..007
    step_usvu('02 usvu waiting default 20d', 958340, NULL);
    step_usvu('03 usvu emergency default 4h', 958341, NULL);
    step_usvu('04 usvu third party explicit 10d', 958342, SYSDATE + 10);
    step_usvu('05 usvu waiting explicit 90d over cap', 958343, SYSDATE + 90);
    step_usvu('06 usvu emergency explicit 2d over cap', 958344, SYSDATE + 2);
    step_usvu('07 usvu deferred no-op', 958345, NULL);
    step_usvu('08 usvu open resets to null', 958346, NULL);
    step_usvu('09 usvu waiting explicit past date', 958347, SYSDATE - 1);
    step_usvu('10 usvu nonexistent ticket', 958999999, NULL);
    -- S-UTIL-002
    step_status('11 check_ticket_status');
    -- S-UTIL-008
    step_dnids('12 check_dnids_tickets_to_resolve');
END;
/
