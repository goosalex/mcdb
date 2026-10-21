-- tt__osag_notify__event_notify / call.ora.sql
-- After every event_notify step the ticket's two notify counters are recorded (n = customer
-- counter, s = osag counter as text) so the counter bumps are compared step by step.
DECLARE
    -- SQLCODE/SQLERRM may not appear inside a SQL statement (ORA-00984); pass them as arguments.
    PROCEDURE log_err(p_step VARCHAR2, p_code NUMBER, p_msg VARCHAR2) IS
    BEGIN
        INSERT INTO diff_probe (step, code, msg) VALUES (p_step, TO_CHAR(p_code), SUBSTR(p_msg, 1, 4000));
    END;

    PROCEDURE record_state(p_step VARCHAR2, p_ticket NUMBER) IS
        v_cust NUMBER;
        v_osag NUMBER;
    BEGIN
        SELECT event_notify_count, event_notify_count_osag INTO v_cust, v_osag FROM tt.ticket WHERE id = p_ticket;
        INSERT INTO diff_probe (step, n, s) VALUES (p_step, v_cust, NVL(TO_CHAR(v_osag), 'null'));
    END;

    PROCEDURE step_suppressor(p_step VARCHAR2, p_host NUMBER) IS
        v_flag NUMBER;
    BEGIN
        IF tt.osag_notify.is_notify_suppressor_active(p_host) THEN v_flag := 1; ELSE v_flag := 0; END IF;
        INSERT INTO diff_probe (step, n) VALUES (p_step, v_flag);
    EXCEPTION WHEN OTHERS THEN
        log_err(p_step, SQLCODE, SQLERRM);
    END;

    PROCEDURE step_notify(p_step VARCHAR2, p_event NUMBER, p_ticket NUMBER, p_record_ticket NUMBER) IS
    BEGIN
        tt.osag_notify.event_notify(p_event, p_ticket);
        record_state(p_step, p_record_ticket);
    EXCEPTION WHEN OTHERS THEN
        log_err(p_step, SQLCODE, SQLERRM);
    END;
BEGIN
    record_state('00 initial sms ticket', 958120);
    -- S-NOTIFY-023 / S-NOTIFY-006 gate inputs
    step_suppressor('01 suppressor active window with flag', 958109);
    step_suppressor('02 suppressor active window without flag', 958106);
    step_suppressor('03 suppressor expired window with flag', 958110);
    step_suppressor('04 suppressor unknown host', 958999999);
    -- S-NOTIFY-010/029: local contact SMS (send_sms swallows the SMTP failure on Oracle)
    step_notify('05 notify sms local contact', 958130, NULL, 958120);
    -- local contact email (send_mail re-raises on Oracle -> swallowed by event_notify)
    step_notify('06 notify mail local contact', 958131, NULL, 958121);
    -- S-NOTIFY-029 NO_DATA_FOUND arm: ticket without service, explicit p_ticket_id
    step_notify('07 notify no service', 958132, 958122, 958122);
    -- S-NOTIFY-006: suppressed by the active window with disable_notification
    step_notify('08 notify suppressed', 958133, NULL, 958123);
    -- S-NOTIFY-006: a question passes the gate (not group 1, nothing to dispatch)
    step_notify('09 notify question not suppressed', 958134, NULL, 958123);
    -- S-NOTIFY-004: both counters at the cap and an automatic event -> early return
    step_notify('10 notify capped automatic early return', 958135, NULL, 958124);
    -- S-NOTIFY-015: fourth -> fifth customer notification writes the 20010 limit event
    step_notify('11 notify fourth to fifth limit event', 958136, NULL, 958125);
    -- S-NOTIFY-001/002: nonexistent event, swallowed
    step_notify('12 notify nonexistent event', 958999999, NULL, 958120);
    -- S-NOTIFY-001/007: nonexistent explicit ticket (site 4), swallowed
    step_notify('13 notify nonexistent ticket', 958130, 958999999, 958120);
END;
/
