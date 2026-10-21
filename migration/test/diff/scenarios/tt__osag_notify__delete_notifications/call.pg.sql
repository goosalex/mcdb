-- tt__osag_notify__delete_notifications / call.pg.sql -- PostgreSQL twin of call.ora.sql.
-- Names from migration/mapping/name-map.csv: tt.osag_notify.delete_notifications_for_login ->
-- tt.osag_notify_delete_notifications_for_login, delete_ticket_notifications ->
-- tt.osag_notify_delete_ticket_notifications, add_notification_event ->
-- tt.osag_notify_add_notification_event (all procedures -> CALL).
CREATE FUNCTION pg_temp.record_state(p_step text) RETURNS void LANGUAGE plpgsql AS $f$
DECLARE v_left numeric;
BEGIN
    SELECT count(*) INTO v_left FROM tt.event_notification WHERE login_id IN (958010, 958011, 958012);
    INSERT INTO diff_probe (step, n, s) VALUES (p_step, v_left, 'ok');
END $f$;

CREATE FUNCTION pg_temp.step_login(p_step text, p_login numeric) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
    CALL tt.osag_notify_delete_notifications_for_login(p_login);
    PERFORM pg_temp.record_state(p_step);
EXCEPTION WHEN OTHERS THEN
    INSERT INTO diff_probe (step, code, msg) VALUES (p_step, SQLSTATE, left(SQLERRM, 4000));
END $f$;

CREATE FUNCTION pg_temp.step_ticket(p_step text, p_ticket numeric) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
    CALL tt.osag_notify_delete_ticket_notifications(p_ticket);
    PERFORM pg_temp.record_state(p_step);
EXCEPTION WHEN OTHERS THEN
    INSERT INTO diff_probe (step, code, msg) VALUES (p_step, SQLSTATE, left(SQLERRM, 4000));
END $f$;

CREATE FUNCTION pg_temp.step_ticket_login(p_step text, p_ticket numeric, p_login numeric, p_suffix text) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
    CALL tt.osag_notify_delete_ticket_notifications(p_ticket, p_login, p_suffix);
    PERFORM pg_temp.record_state(p_step);
EXCEPTION WHEN OTHERS THEN
    INSERT INTO diff_probe (step, code, msg) VALUES (p_step, SQLSTATE, left(SQLERRM, 4000));
END $f$;

CREATE FUNCTION pg_temp.step_add(p_step text, p_ticket numeric, p_type numeric, p_text text, p_contact numeric, p_peer numeric, p_public numeric) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
    CALL tt.osag_notify_add_notification_event(p_ticket, p_type, p_text, p_contact, p_peer, p_public);
    PERFORM pg_temp.record_state(p_step);
EXCEPTION WHEN OTHERS THEN
    INSERT INTO diff_probe (step, code, msg) VALUES (p_step, SQLSTATE, left(SQLERRM, 4000));
END $f$;

DO $$
BEGIN
    PERFORM pg_temp.record_state('00 initial');
    PERFORM pg_temp.step_login('01 delete_notifications_for_login alpha', 958010);
    PERFORM pg_temp.step_ticket('02 delete_ticket_notifications ticket A all logins', 958020);
    PERFORM pg_temp.step_ticket('03 delete_ticket_notifications ticket C osag', 958022);
    PERFORM pg_temp.step_ticket('04 delete_ticket_notifications ticket D bad type swallowed', 958023);
    PERFORM pg_temp.step_ticket('05 delete_ticket_notifications nonexistent ticket', 958999999);
    PERFORM pg_temp.step_login('06 delete_notifications_for_login nonexistent login', 958999999);
    PERFORM pg_temp.step_ticket_login('07 delete_ticket_notifications ticket B beta no rows', 958021, 958011, 'suffix never used');
    PERFORM pg_temp.step_add('08 add_notification_event public', 958021, 20001, 'dfn public text', 958002, 958003, 1);
    PERFORM pg_temp.step_add('09 add_notification_event private', 958021, 20003, 'dfn private text', 958002, NULL, 0);
    PERFORM pg_temp.step_add('10 add_notification_event null type id', 958021, NULL, 'dfn never written', 958002, NULL, 1);
END $$;
