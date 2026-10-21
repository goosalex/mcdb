-- tt__event_interface__history_move / call.ora.sql
DECLARE
    -- SQLCODE/SQLERRM may not appear inside a SQL statement (ORA-00984); pass them as arguments.
    PROCEDURE log_err(p_step VARCHAR2, p_code NUMBER, p_msg VARCHAR2) IS
    BEGIN
        INSERT INTO diff_probe (step, code, msg) VALUES (p_step, TO_CHAR(p_code), SUBSTR(p_msg, 1, 4000));
    END;

    PROCEDURE hist(p_step VARCHAR2, p_ticket NUMBER, p_pub VARCHAR2, p_priv VARCHAR2, p_public BOOLEAN, p_contact NUMBER) IS
        v_e NUMBER;
    BEGIN
        tt.event_interface.add_history_event(v_e, p_ticket, 101001, 957305, 957301, p_pub, p_priv, p_public,
                                             p_contact_id => p_contact);
        INSERT INTO diff_probe (step, s) VALUES (p_step, CASE WHEN v_e IS NOT NULL THEN 'event id set' ELSE 'event id null' END);
    EXCEPTION WHEN OTHERS THEN
        log_err(p_step, SQLCODE, SQLERRM);
    END;

    PROCEDURE demote(p_step VARCHAR2, p_event NUMBER) IS
    BEGIN
        tt.event_interface.demote_event(p_event, 957302);
        INSERT INTO diff_probe (step, s) VALUES (p_step, 'ok');
    EXCEPTION WHEN OTHERS THEN
        log_err(p_step, SQLCODE, SQLERRM);
    END;

    PROCEDURE promote(p_step VARCHAR2, p_event NUMBER) IS
    BEGIN
        tt.event_interface.promote_event(p_event, 957302);
        INSERT INTO diff_probe (step, s) VALUES (p_step, 'ok');
    EXCEPTION WHEN OTHERS THEN
        log_err(p_step, SQLCODE, SQLERRM);
    END;

    PROCEDURE move(p_step VARCHAR2, p_event NUMBER, p_old NUMBER, p_new NUMBER) IS
    BEGIN
        tt.event_interface.moveevent(p_event, p_old, p_new);
        INSERT INTO diff_probe (step, s) VALUES (p_step, 'ok');
    EXCEPTION WHEN OTHERS THEN
        log_err(p_step, SQLCODE, SQLERRM);
    END;
BEGIN
    hist('01 history event public with contact',   957312, 'history text', 'history private', TRUE, 957302);
    hist('02 history event private without contact', 957312, 'private history', NULL, FALSE, NULL);
    hist('03 history event on nonexistent ticket', 957999, 'orphan history', NULL, TRUE, 957302);
    demote('11 demote existing event',             957324);
    demote('12 demote nonexistent event',          957999999);
    promote('13 promote existing event',           957324);
    promote('14 promote nonexistent event',        957999999);
    move('31 move decoy event not on old ticket',  957323, 957311, 957312);
    move('32 move event from old to new ticket',   957321, 957311, 957312);
    move('33 move nonexistent event',              957999999, 957313, 957312);
    move('34 move to nonexistent new ticket',      957322, 957311, 957999);
    move('35 move with NULL event id',             NULL, 957311, 957312);
END;
/
