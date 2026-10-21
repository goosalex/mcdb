-- tt__escalation_interface__closed_ticket / call.ora.sql
-- The wrapper procedures' own EXCEPTION handlers are the point of this scenario: they stand for a
-- static PL/SQL caller that catches the ticket_closed error (S-ESC-009).
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
BEGIN
    esc_os('01 escalate_os closed ticket',         956921);
    esc_cust('02 escalate_customer closed ticket', 956922);
END;
/
