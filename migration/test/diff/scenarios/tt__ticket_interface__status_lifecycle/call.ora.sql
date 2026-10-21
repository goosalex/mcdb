-- tt__ticket_interface__status_lifecycle / call.ora.sql
-- After every successful step the ticket's status_id (n) and whether status_valid_until_date
-- is set (s) are recorded, so intermediate states are compared, not only the end state.
DECLARE
    -- SQLCODE/SQLERRM may not appear inside a SQL statement (ORA-00984); pass them as arguments.
    PROCEDURE log_err(p_step VARCHAR2, p_code NUMBER, p_msg VARCHAR2) IS
    BEGIN
        INSERT INTO diff_probe (step, code, msg) VALUES (p_step, TO_CHAR(p_code), SUBSTR(p_msg, 1, 4000));
    END;

    PROCEDURE record_state(p_step VARCHAR2, p_ticket NUMBER) IS
        v_status NUMBER;
        v_valid  VARCHAR2(10);
    BEGIN
        SELECT status_id, CASE WHEN status_valid_until_date IS NULL THEN 'null' ELSE 'set' END
        INTO v_status, v_valid
        FROM tt.ticket WHERE id = p_ticket;
        INSERT INTO diff_probe (step, n, s) VALUES (p_step, v_status, v_valid);
    END;

    PROCEDURE step_status(p_step VARCHAR2, p_ticket NUMBER, p_status NUMBER, p_text VARCHAR2) IS
    BEGIN
        tt.ticket_interface.change_status(p_ticket, p_status, 950002, p_text);
        record_state(p_step, p_ticket);
    EXCEPTION WHEN OTHERS THEN
        log_err(p_step, SQLCODE, SQLERRM);
    END;

    PROCEDURE step_subject(p_step VARCHAR2, p_ticket NUMBER, p_subject VARCHAR2) IS
    BEGIN
        tt.ticket_interface.change_subject(p_ticket, p_subject, 950002);
        record_state(p_step, p_ticket);
    EXCEPTION WHEN OTHERS THEN
        log_err(p_step, SQLCODE, SQLERRM);
    END;
BEGIN
    record_state('00 initial', 950010);
    step_status('01 open->hot', 950010, 3, 'moved to hot');
    step_status('02 hot->hot no-op', 950010, 3, 'same status again');
    step_status('03 hot->waiting', 950010, 11, 'waiting for the customer');
    step_status('04 waiting->closed', 950010, 102, 'closing');
    step_subject('05 change_subject', 950010, 'changed subject');
    step_status('06 nonexistent ticket', 950999999, 3, 'should fail with NO_DATA_FOUND');
    step_subject('07 change_subject nonexistent', 950999999, 'x');
END;
/
