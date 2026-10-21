-- tt__escalation_interface__isp_outage / call.ora.sql
DECLARE
    -- SQLCODE/SQLERRM may not appear inside a SQL statement (ORA-00984); pass them as arguments.
    PROCEDURE log_err(p_step VARCHAR2, p_code NUMBER, p_msg VARCHAR2) IS
    BEGIN
        INSERT INTO diff_probe (step, code, msg) VALUES (p_step, TO_CHAR(p_code), SUBSTR(p_msg, 1, 4000));
    END;

    PROCEDURE isp(p_step VARCHAR2, p_event_id NUMBER) IS
    BEGIN
        tt.escalation_interface.escalate_isp_outage_to_os(p_event_id);
        INSERT INTO diff_probe (step, s) VALUES (p_step, 'ok');
    EXCEPTION WHEN OTHERS THEN
        log_err(p_step, SQLCODE, SQLERRM);
    END;
BEGIN
    isp('01 ticket host and ticket company',          957521);
    isp('02 event host, service company without short', 957522);
    isp('03 event company wins',                      957523);
    isp('04 no host on event or ticket',              957524);
    isp('05 nonexistent event',                       957999999);
END;
/
