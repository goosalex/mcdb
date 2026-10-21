-- tt__escalation_interface__escalate / call.ora.sql
-- Every call is wrapped: success records 'ok' in s, an exception its SQLCODE.
DECLARE
    -- SQLCODE/SQLERRM may not appear inside a SQL statement (ORA-00984); pass them as arguments.
    PROCEDURE log_err(p_step VARCHAR2, p_code NUMBER, p_msg VARCHAR2) IS
    BEGIN
        INSERT INTO diff_probe (step, code, msg) VALUES (p_step, TO_CHAR(p_code), SUBSTR(p_msg, 1, 4000));
    END;

    PROCEDURE esc_os(p_step VARCHAR2, p_event_id NUMBER) IS
    BEGIN
        tt.escalation_interface.escalate_os(p_event_id);
        INSERT INTO diff_probe (step, s) VALUES (p_step, 'ok');
    EXCEPTION WHEN OTHERS THEN
        log_err(p_step, SQLCODE, SQLERRM);
    END;

    PROCEDURE esc_cust(p_step VARCHAR2, p_event_id NUMBER) IS
    BEGIN
        tt.escalation_interface.escalate_customer(p_event_id);
        INSERT INTO diff_probe (step, s) VALUES (p_step, 'ok');
    EXCEPTION WHEN OTHERS THEN
        log_err(p_step, SQLCODE, SQLERRM);
    END;

    PROCEDURE nop(p_step VARCHAR2, p_event_id NUMBER) IS
    BEGIN
        tt.escalation_interface.nop(p_event_id);
        INSERT INTO diff_probe (step, s) VALUES (p_step, 'ok');
    EXCEPTION WHEN OTHERS THEN
        log_err(p_step, SQLCODE, SQLERRM);
    END;

    PROCEDURE clear_cust(p_step VARCHAR2, p_ticket_id NUMBER) IS
    BEGIN
        tt.escalation_interface.clear_customer_escalation(p_ticket_id);
        INSERT INTO diff_probe (step, s) VALUES (p_step, 'ok');
    EXCEPTION WHEN OTHERS THEN
        log_err(p_step, SQLCODE, SQLERRM);
    END;
BEGIN
    esc_os('01 os active host status 0',            956811);
    esc_os('02 os already status 10',               956812);
    esc_os('03 os pikett failed status 11',         956813);
    esc_os('04 os no host',                         956814);
    esc_os('05 os inactive host',                   956815);
    esc_os('06 os customer escalation status 20',   956816);
    esc_os('07 os dangling host id',                956817);
    esc_os('08 os nonexistent event',               956999999);
    esc_cust('11 cust active host status 0',        956821);
    esc_cust('12 cust status 20 blocks',            956822);
    esc_cust('13 cust status 10 blocks',            956823);
    esc_cust('14 cust inactive host',               956824);
    esc_cust('15 cust no host',                     956825);
    esc_cust('16 cust nonexistent event',           956999998);
    nop('21 nop nonexistent event',                 956999997);
    clear_cust('31 clear status 20',                956731);
    clear_cust('32 clear status 10 untouched',      956732);
    clear_cust('33 clear nonexistent ticket',       956999996);
END;
/
