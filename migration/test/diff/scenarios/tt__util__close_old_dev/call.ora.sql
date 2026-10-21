-- tt__util__close_old_dev / call.ora.sql
-- The routine runs in its own autonomous transaction (S-UTIL-010); on a non-dev instance it
-- ROLLBACKs that (empty) transaction and returns (S-UTIL-012).
DECLARE
    -- SQLCODE/SQLERRM may not appear inside a SQL statement (ORA-00984); pass them as arguments.
    PROCEDURE log_err(p_step VARCHAR2, p_code NUMBER, p_msg VARCHAR2) IS
    BEGIN
        INSERT INTO diff_probe (step, code, msg) VALUES (p_step, TO_CHAR(p_code), SUBSTR(p_msg, 1, 4000));
    END;
BEGIN
    BEGIN
        tt.util.close_old_dev_tickets;
        INSERT INTO diff_probe (step, s) VALUES ('01 close_old_dev_tickets', 'ok');
    EXCEPTION WHEN OTHERS THEN
        log_err('01 close_old_dev_tickets', SQLCODE, SQLERRM);
    END;
END;
/
