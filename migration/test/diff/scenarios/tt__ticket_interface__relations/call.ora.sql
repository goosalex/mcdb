-- tt__ticket_interface__relations / call.ora.sql
-- Every routine here swallows its own errors (S-TICKET-042..045), so a step records 'ok'
-- in s unless something propagated; the effects are compared through the probes.
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

    PROCEDURE add_rt(p_step VARCHAR2, p_t NUMBER, p_r NUMBER) IS
    BEGIN
        tt.ticket_interface.add_related_ticket(p_t, p_r, 954003);
        ok(p_step);
    EXCEPTION WHEN OTHERS THEN log_err(p_step, SQLCODE, SQLERRM);
    END;

    PROCEDURE rem_rt(p_step VARCHAR2, p_t NUMBER, p_r NUMBER) IS
    BEGIN
        tt.ticket_interface.remove_related_ticket(p_t, p_r, 954003);
        ok(p_step);
    EXCEPTION WHEN OTHERS THEN log_err(p_step, SQLCODE, SQLERRM);
    END;

    PROCEDURE add_rf(p_step VARCHAR2, p_t NUMBER, p_f NUMBER) IS
    BEGIN
        tt.ticket_interface.add_related_file(p_t, p_f, 954003);
        ok(p_step);
    EXCEPTION WHEN OTHERS THEN log_err(p_step, SQLCODE, SQLERRM);
    END;

    PROCEDURE rem_rf(p_step VARCHAR2, p_t NUMBER, p_f NUMBER) IS
    BEGIN
        tt.ticket_interface.remove_related_file(p_t, p_f, 954003);
        ok(p_step);
    EXCEPTION WHEN OTHERS THEN log_err(p_step, SQLCODE, SQLERRM);
    END;
BEGIN
    add_rt('01 add T1-T2',                     954010, 954011);
    add_rt('02 add T1-T2 again duplicate',     954010, 954011);
    add_rt('03 add T1-T1 equal ids',           954010, 954010);
    add_rt('04 add T1-nonexistent',            954010, 954099999);
    add_rt('05 add T1-T3 other company',       954010, 954012);
    rem_rt('06 remove T3-T2 reverse direction', 954012, 954011);
    rem_rt('07 remove T2-T3',                  954011, 954012);
    add_rf('08 add file F1 same company',      954010, 954020);
    add_rf('09 add file F2 other company',     954010, 954022);
    add_rf('10 add file F1 nonexistent ticket', 954099999, 954020);
    add_rf('11 add file F1 again duplicate',   954010, 954020);
    rem_rf('12 remove file F3 same company',   954010, 954024);
    rem_rf('13 remove file F4 other company',  954010, 954026);
    rem_rf('14 remove file orphan 954098',     954010, 954098);
    rem_rf('15 remove file F2 no relation',    954010, 954022);
END;
/
