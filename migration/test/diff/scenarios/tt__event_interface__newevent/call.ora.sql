-- tt__event_interface__newevent / call.ora.sql
-- newevent_new / addevent_new wrapped so an exception becomes data; a successful call records
-- whether the OUT event id was set. Optional arguments are passed BY NAME on both sides.
DECLARE
    -- SQLCODE/SQLERRM may not appear inside a SQL statement (ORA-00984); pass them as arguments.
    PROCEDURE log_err(p_step VARCHAR2, p_code NUMBER, p_msg VARCHAR2) IS
    BEGIN
        INSERT INTO diff_probe (step, code, msg) VALUES (p_step, TO_CHAR(p_code), SUBSTR(p_msg, 1, 4000));
    END;

    PROCEDURE new_event(p_step VARCHAR2, p_type NUMBER, p_host NUMBER, p_pub VARCHAR2, p_priv VARCHAR2,
                        p_contact NUMBER DEFAULT NULL, p_zitadel NUMBER DEFAULT NULL) IS
        v_e NUMBER;
    BEGIN
        tt.event_interface.newevent_new(v_e, p_type, p_host, p_pub, p_priv,
                                        p_contact_id => p_contact, p_zitadel_contact_id => p_zitadel);
        INSERT INTO diff_probe (step, s) VALUES (p_step, CASE WHEN v_e IS NOT NULL THEN 'event id set' ELSE 'event id null' END);
    EXCEPTION WHEN OTHERS THEN
        log_err(p_step, SQLCODE, SQLERRM);
    END;

    PROCEDURE add_event(p_step VARCHAR2, p_ticket NUMBER, p_type NUMBER, p_host NUMBER, p_pub VARCHAR2, p_priv VARCHAR2,
                        p_contact NUMBER DEFAULT NULL, p_public BOOLEAN DEFAULT TRUE, p_notify BOOLEAN DEFAULT FALSE) IS
        v_e NUMBER;
    BEGIN
        tt.event_interface.addevent_new(v_e, p_ticket, p_type, p_host, p_pub, p_priv,
                                        p_contact_id => p_contact, public_event => p_public, notify_event => p_notify);
        INSERT INTO diff_probe (step, s) VALUES (p_step, CASE WHEN v_e IS NOT NULL THEN 'event id set' ELSE 'event id null' END);
    EXCEPTION WHEN OTHERS THEN
        log_err(p_step, SQLCODE, SQLERRM);
    END;
BEGIN
    -- newevent_new
    new_event('01 new 10004 hardware notification, host, two-line details', 10004, 957005, 'Disk failure on sda' || CHR(10) || 'more text', 'private part');
    new_event('02 new 30002 email from customer, contact without admin role', 30002, 957005, 'Subject line here' || CHR(10) || 'Body of the mail', NULL, p_contact => 957002);
    new_event('03 new 30002 with zitadel contact id', 30002, 957005, 'Zitadel subject' || CHR(10) || 'Body', NULL, p_contact => 957002, p_zitadel => 957000111);
    new_event('04 new 50002 comment, no host, company from contact', 50002, NULL, 'a comment without host', NULL, p_contact => 957003);
    new_event('05 new 10001 on inactive host is dropped', 10001, 957006, 'dropped', NULL);
    new_event('06 new 10001 on host without host2service row', 10001, 957007, 'no service', NULL);
    new_event('08 new 10001 on nonexistent host', 10001, 957999, 'no such host', NULL);
    new_event('09 new nonexistent event type', 957999, 957005, 'no such type', NULL);
    new_event('10 new 10001 appended to recent automatic ticket', 10001, 957011, 'second down', NULL);
    new_event('11 new 10003 appended to recent connection-down ticket', 10003, 957011, 'isp outage follows', NULL);
    new_event('12 new 30002 single-line details, no newline', 30002, 957005, 'single line mail subject', NULL, p_contact => 957002);
    new_event('13 new 10004 single-line details, no newline', 10004, 957005, 'single line hardware notification', NULL);
    -- addevent_new
    add_event('21 add 50002 public comment', 957102, 50002, 957005, 'public comment', 'private note', p_contact => 957003);
    add_event('22 add 50002 private comment', 957102, 50002, 957005, 'private comment', NULL, p_contact => 957003, p_public => FALSE);
    add_event('23 add 50002 notified comment', 957102, 50002, 957005, 'notified comment', NULL, p_contact => 957003, p_notify => TRUE);
    add_event('24 add 30016 customer requests resolve', 957102, 30016, 957005, 'please resolve', NULL, p_contact => 957002);
    add_event('25 add 30002 email from customer makes ticket hot', 957103, 30002, 957005, 'customer mail', NULL, p_contact => 957002);
    add_event('26 add 10001 connection down to change ticket', 957104, 10001, 957005, 'down on change', NULL);
    add_event('27 add 30002 to isp outage ticket', 957108, 30002, 957005, 'customer mail on isp outage', NULL, p_contact => 957002);
    add_event('28 add to closed ticket', 957105, 50002, 957005, 'on closed', NULL);
    add_event('29 add to merged ticket', 957106, 50002, 957005, 'on merged', NULL, p_contact => 957003);
    add_event('30 add to nonexistent ticket', 957999, 50002, 957005, 'no such ticket', NULL);
    add_event('31 add nonexistent event type', 957102, 957999, 957005, 'no such type', NULL);
END;
/
