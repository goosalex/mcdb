-- tt__ticket_interface__newticket_signoff / call.ora.sql
DECLARE
    -- SQLCODE/SQLERRM may not appear inside a SQL statement (ORA-00984); pass them as arguments.
    PROCEDURE log_err(p_step VARCHAR2, p_code NUMBER, p_msg VARCHAR2) IS
    BEGIN
        INSERT INTO diff_probe (step, code, msg) VALUES (p_step, TO_CHAR(p_code), SUBSTR(p_msg, 1, 4000));
    END;

    PROCEDURE new_ticket(p_step VARCHAR2, p_subject VARCHAR2, p_event_type NUMBER,
                         p_contact NUMBER, p_worker NUMBER, p_zitadel NUMBER) IS
        v_t NUMBER; v_e NUMBER;
    BEGIN
        tt.ticket_interface.newticket_new(v_t, v_e, 1, p_subject, p_event_type, 951005, 'pub ' || p_subject, 'priv ' || p_subject,
                                          p_contact_id => p_contact, p_worker_id => p_worker,
                                          p_zitadel_contact_id => p_zitadel);
        INSERT INTO diff_probe (step, s) VALUES (p_step, CASE WHEN v_t IS NOT NULL AND v_e IS NOT NULL THEN 'ids set' ELSE 'ids null' END);
    EXCEPTION WHEN OTHERS THEN
        log_err(p_step, SQLCODE, SQLERRM);
    END;

    PROCEDURE change_worker(p_step VARCHAR2, p_subject VARCHAR2, p_worker NUMBER) IS
        v_t NUMBER;
    BEGIN
        SELECT id INTO v_t FROM tt.ticket WHERE subject = p_subject;
        tt.ticket_interface.change_worker(v_t, p_worker, 951002);
        INSERT INTO diff_probe (step, s) VALUES (p_step, 'ok');
    EXCEPTION WHEN OTHERS THEN
        log_err(p_step, SQLCODE, SQLERRM);
    END;
BEGIN
    new_ticket('01 A signoff zitadel, no contact, 30002', 'signoff A', 30002, NULL, NULL, 260976466693466175);
    new_ticket('02 B signoff zitadel, event 101002',       'signoff B', 101002, NULL, NULL, 260976466693466175);
    new_ticket('03 C non-signoff zitadel, 30002',          'signoff C', 30002, NULL, NULL, 123456789012345678);
    new_ticket('04 D explicit contact + signoff zitadel',  'signoff D', 30002, 951006, NULL, 260976466693466175);
    new_ticket('05 E signoff zitadel without login',       'signoff E', 30002, NULL, NULL, 249698997185305231);
    new_ticket('06 F1 worker with login',                  'signoff F1', 101002, NULL, 951003, NULL);
    new_ticket('07 F2 worker without login',               'signoff F2', 101002, NULL, 951004, NULL);
    change_worker('08 F2 change_worker to worker with login', 'signoff F2', 951003);
END;
/
