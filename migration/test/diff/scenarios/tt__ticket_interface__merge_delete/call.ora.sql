-- tt__ticket_interface__merge_delete / call.ora.sql
DECLARE
    -- SQLCODE/SQLERRM may not appear inside a SQL statement (ORA-00984); pass them as arguments.
    PROCEDURE log_err(p_step VARCHAR2, p_code NUMBER, p_msg VARCHAR2) IS
    BEGIN
        INSERT INTO diff_probe (step, code, msg) VALUES (p_step, TO_CHAR(p_code), SUBSTR(p_msg, 1, 4000));
    END;

    PROCEDURE ok(p_step VARCHAR2) IS
    BEGIN
        INSERT INTO diff_probe (step, s) VALUES (p_step, 'ok');
    END;

    PROCEDURE merge(p_step VARCHAR2, p_src NUMBER, p_tgt NUMBER) IS
    BEGIN
        tt.ticket_interface.merge_tickets(p_src, p_tgt, 954302);
        ok(p_step);
    EXCEPTION WHEN OTHERS THEN log_err(p_step, SQLCODE, SQLERRM);
    END;

    PROCEDURE del(p_step VARCHAR2, p_t NUMBER) IS
    BEGIN
        tt.ticket_interface.deleteTicket(p_t);
        ok(p_step);
    EXCEPTION WHEN OTHERS THEN log_err(p_step, SQLCODE, SQLERRM);
    END;
BEGIN
    merge('01 merge SRC into TGT',             954320, 954321);
    merge('02 merge SRC2 into TGT2',           954323, 954322);
    merge('03 merge nonexistent source',       954099999, 954322);
    merge('04 merge into nonexistent target',  954323, 954099999);
    del('05 delete DEL',                       954325);
    del('06 delete nonexistent ticket',        954099999);
END;
/
