-- tt__osag_notify__delete_notifications / call.ora.sql
-- After every step the number of surviving fixture notifications is recorded in n, so the
-- cascade is compared step by step, not only as an end state.
DECLARE
    -- SQLCODE/SQLERRM may not appear inside a SQL statement (ORA-00984); pass them as arguments.
    PROCEDURE log_err(p_step VARCHAR2, p_code NUMBER, p_msg VARCHAR2) IS
    BEGIN
        INSERT INTO diff_probe (step, code, msg) VALUES (p_step, TO_CHAR(p_code), SUBSTR(p_msg, 1, 4000));
    END;

    PROCEDURE record_state(p_step VARCHAR2) IS
        v_left NUMBER;
    BEGIN
        SELECT COUNT(*) INTO v_left FROM tt.event_notification WHERE login_id IN (958010, 958011, 958012);
        INSERT INTO diff_probe (step, n, s) VALUES (p_step, v_left, 'ok');
    END;

    PROCEDURE step_login(p_step VARCHAR2, p_login NUMBER) IS
    BEGIN
        tt.osag_notify.delete_notifications_for_login(p_login);
        record_state(p_step);
    EXCEPTION WHEN OTHERS THEN
        log_err(p_step, SQLCODE, SQLERRM);
    END;

    PROCEDURE step_ticket(p_step VARCHAR2, p_ticket NUMBER) IS
    BEGIN
        tt.osag_notify.delete_ticket_notifications(p_ticket);
        record_state(p_step);
    EXCEPTION WHEN OTHERS THEN
        log_err(p_step, SQLCODE, SQLERRM);
    END;

    PROCEDURE step_ticket_login(p_step VARCHAR2, p_ticket NUMBER, p_login NUMBER, p_suffix VARCHAR2) IS
    BEGIN
        tt.osag_notify.delete_ticket_notifications(p_ticket, p_login, p_suffix);
        record_state(p_step);
    EXCEPTION WHEN OTHERS THEN
        log_err(p_step, SQLCODE, SQLERRM);
    END;

    PROCEDURE step_add(p_step VARCHAR2, p_ticket NUMBER, p_type NUMBER, p_text VARCHAR2, p_contact NUMBER, p_peer NUMBER, p_public NUMBER) IS
    BEGIN
        tt.osag_notify.add_notification_event(p_ticket, p_type, p_text, p_contact, p_peer, p_public);
        record_state(p_step);
    EXCEPTION WHEN OTHERS THEN
        log_err(p_step, SQLCODE, SQLERRM);
    END;
BEGIN
    record_state('00 initial');
    -- S-NOTIFY-019: tickets A and B for login alpha, then the company-wide row 958032
    step_login('01 delete_notifications_for_login alpha', 958010);
    -- S-NOTIFY-020/021: beta (public line) and the OSAG login (private line) on ticket A
    step_ticket('02 delete_ticket_notifications ticket A all logins', 958020);
    -- OSAG login on an OSAG ticket: the line stays public
    step_ticket('03 delete_ticket_notifications ticket C osag', 958022);
    -- S-NOTIFY-036 via S-NOTIFY-021: nonexistent notification type, swallowed, row survives
    step_ticket('04 delete_ticket_notifications ticket D bad type swallowed', 958023);
    step_ticket('05 delete_ticket_notifications nonexistent ticket', 958999999);
    step_login('06 delete_notifications_for_login nonexistent login', 958999999);
    -- login-scoped call with an explicit suffix on a ticket that has no row left for it
    step_ticket_login('07 delete_ticket_notifications ticket B beta no rows', 958021, 958011, 'suffix never used');
    -- S-NOTIFY-022
    step_add('08 add_notification_event public', 958021, 20001, 'dfn public text', 958002, 958003, 1);
    step_add('09 add_notification_event private', 958021, 20003, 'dfn private text', 958002, NULL, 0);
    step_add('10 add_notification_event null type id', 958021, NULL, 'dfn never written', 958002, NULL, 1);
END;
/
