-- tt__event_interface__newevent / call.pg.sql -- PostgreSQL twin of call.ora.sql.
-- Names from migration/mapping/name-map.csv: tt.event_interface.newevent_new ->
-- tt.event_interface_newevent_new, addevent_new -> tt.event_interface_addevent_new (CALL).
-- Optional arguments by name (the OUT parameter comes first in both signatures).
CREATE FUNCTION pg_temp.new_event(p_step text, p_type numeric, p_host numeric, p_pub text, p_priv text,
                                  p_contact numeric DEFAULT NULL, p_zitadel numeric DEFAULT NULL) RETURNS void LANGUAGE plpgsql AS $f$
DECLARE v_e numeric;
BEGIN
    CALL tt.event_interface_newevent_new(v_e, p_type, p_host, p_pub, p_priv,
                                         p_contact_id => p_contact, p_zitadel_contact_id => p_zitadel);
    INSERT INTO diff_probe (step, s) VALUES (p_step, CASE WHEN v_e IS NOT NULL THEN 'event id set' ELSE 'event id null' END);
EXCEPTION WHEN OTHERS THEN
    INSERT INTO diff_probe (step, code, msg) VALUES (p_step, SQLSTATE, left(SQLERRM, 4000));
END $f$;

CREATE FUNCTION pg_temp.add_event(p_step text, p_ticket numeric, p_type numeric, p_host numeric, p_pub text, p_priv text,
                                  p_contact numeric DEFAULT NULL, p_public boolean DEFAULT TRUE, p_notify boolean DEFAULT FALSE) RETURNS void LANGUAGE plpgsql AS $f$
DECLARE v_e numeric;
BEGIN
    CALL tt.event_interface_addevent_new(v_e, p_ticket, p_type, p_host, p_pub, p_priv,
                                         p_contact_id => p_contact, public_event => p_public, notify_event => p_notify);
    INSERT INTO diff_probe (step, s) VALUES (p_step, CASE WHEN v_e IS NOT NULL THEN 'event id set' ELSE 'event id null' END);
EXCEPTION WHEN OTHERS THEN
    INSERT INTO diff_probe (step, code, msg) VALUES (p_step, SQLSTATE, left(SQLERRM, 4000));
END $f$;

DO $$
BEGIN
    -- newevent_new
    PERFORM pg_temp.new_event('01 new 10004 hardware notification, host, two-line details', 10004, 957005, 'Disk failure on sda' || chr(10) || 'more text', 'private part');
    PERFORM pg_temp.new_event('02 new 30002 email from customer, contact without admin role', 30002, 957005, 'Subject line here' || chr(10) || 'Body of the mail', NULL, p_contact => 957002);
    PERFORM pg_temp.new_event('03 new 30002 with zitadel contact id', 30002, 957005, 'Zitadel subject' || chr(10) || 'Body', NULL, p_contact => 957002, p_zitadel => 957000111);
    PERFORM pg_temp.new_event('04 new 50002 comment, no host, company from contact', 50002, NULL, 'a comment without host', NULL, p_contact => 957003);
    PERFORM pg_temp.new_event('05 new 10001 on inactive host is dropped', 10001, 957006, 'dropped', NULL);
    PERFORM pg_temp.new_event('06 new 10001 on host without host2service row', 10001, 957007, 'no service', NULL);
    PERFORM pg_temp.new_event('08 new 10001 on nonexistent host', 10001, 957999, 'no such host', NULL);
    PERFORM pg_temp.new_event('09 new nonexistent event type', 957999, 957005, 'no such type', NULL);
    PERFORM pg_temp.new_event('10 new 10001 appended to recent automatic ticket', 10001, 957011, 'second down', NULL);
    PERFORM pg_temp.new_event('11 new 10003 appended to recent connection-down ticket', 10003, 957011, 'isp outage follows', NULL);
    PERFORM pg_temp.new_event('12 new 30002 single-line details, no newline', 30002, 957005, 'single line mail subject', NULL, p_contact => 957002);
    PERFORM pg_temp.new_event('13 new 10004 single-line details, no newline', 10004, 957005, 'single line hardware notification', NULL);
    -- addevent_new
    PERFORM pg_temp.add_event('21 add 50002 public comment', 957102, 50002, 957005, 'public comment', 'private note', p_contact => 957003);
    PERFORM pg_temp.add_event('22 add 50002 private comment', 957102, 50002, 957005, 'private comment', NULL, p_contact => 957003, p_public => FALSE);
    PERFORM pg_temp.add_event('23 add 50002 notified comment', 957102, 50002, 957005, 'notified comment', NULL, p_contact => 957003, p_notify => TRUE);
    PERFORM pg_temp.add_event('24 add 30016 customer requests resolve', 957102, 30016, 957005, 'please resolve', NULL, p_contact => 957002);
    PERFORM pg_temp.add_event('25 add 30002 email from customer makes ticket hot', 957103, 30002, 957005, 'customer mail', NULL, p_contact => 957002);
    PERFORM pg_temp.add_event('26 add 10001 connection down to change ticket', 957104, 10001, 957005, 'down on change', NULL);
    PERFORM pg_temp.add_event('27 add 30002 to isp outage ticket', 957108, 30002, 957005, 'customer mail on isp outage', NULL, p_contact => 957002);
    PERFORM pg_temp.add_event('28 add to closed ticket', 957105, 50002, 957005, 'on closed', NULL);
    PERFORM pg_temp.add_event('29 add to merged ticket', 957106, 50002, 957005, 'on merged', NULL, p_contact => 957003);
    PERFORM pg_temp.add_event('30 add to nonexistent ticket', 957999, 50002, 957005, 'no such ticket', NULL);
    PERFORM pg_temp.add_event('31 add nonexistent event type', 957102, 957999, 957005, 'no such type', NULL);
END $$;
