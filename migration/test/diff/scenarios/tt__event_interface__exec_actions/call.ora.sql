-- tt__event_interface__exec_actions / call.ora.sql
-- One exec_event_type_actions call per fixture event; a successful call records 'ok' in s,
-- a failing one its SQLCODE (exec_event_type_actions has no procedure-level handler, S-EVENT-035).
DECLARE
    -- SQLCODE/SQLERRM may not appear inside a SQL statement (ORA-00984); pass them as arguments.
    PROCEDURE log_err(p_step VARCHAR2, p_code NUMBER, p_msg VARCHAR2) IS
    BEGIN
        INSERT INTO diff_probe (step, code, msg) VALUES (p_step, TO_CHAR(p_code), SUBSTR(p_msg, 1, 4000));
    END;

    PROCEDURE step(p_step VARCHAR2, p_event_id NUMBER) IS
    BEGIN
        tt.event_interface.exec_event_type_actions(p_event_id);
        INSERT INTO diff_probe (step, s) VALUES (p_step, 'ok');
    EXCEPTION WHEN OTHERS THEN
        log_err(p_step, SQLCODE, SQLERRM);
    END;
BEGIN
    step('01 action 1 escalate_os, active host, status 0',      956201);
    step('02 pilot action escalate_customer, status 0',         956202);
    step('03 pilot action nop, status 20',                      956203);
    step('04 pilot action escalate_isp_outage_to_os',           956204);
    step('05 pilot action off-allowlist clear_customer_escalation', 956105);
    step('06 action 2 DBPROP key 139 with host, no value',      956206);
    step('07 unmapped event type',                              956207);
    step('08 action 1 escalate_os, inactive host',              956208);
    step('09 action 1 escalate_os, closed ticket',              956209);
    step('10 action 2 suppressed by service window',            956210);
    step('11 nonexistent event',                                956999999);
END;
/
