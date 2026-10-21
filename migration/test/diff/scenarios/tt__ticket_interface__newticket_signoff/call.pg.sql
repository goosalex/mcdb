-- tt__ticket_interface__newticket_signoff / call.pg.sql -- PostgreSQL twin of call.ora.sql.
-- Names from migration/mapping/name-map.csv: tt.ticket_interface.newticket_new ->
-- tt.ticket_interface_newticket_new, change_worker -> tt.ticket_interface_change_worker.
CREATE FUNCTION pg_temp.new_ticket(p_step text, p_subject text, p_event_type numeric,
                                   p_contact numeric, p_worker numeric, p_zitadel numeric) RETURNS void LANGUAGE plpgsql AS $f$
DECLARE v_t numeric; v_e numeric;
BEGIN
    CALL tt.ticket_interface_newticket_new(v_t, v_e, 1, p_subject, p_event_type, 951005, 'pub ' || p_subject, 'priv ' || p_subject,
                                           p_contact_id => p_contact, p_worker_id => p_worker,
                                           p_zitadel_contact_id => p_zitadel);
    INSERT INTO diff_probe (step, s) VALUES (p_step, CASE WHEN v_t IS NOT NULL AND v_e IS NOT NULL THEN 'ids set' ELSE 'ids null' END);
EXCEPTION WHEN OTHERS THEN
    INSERT INTO diff_probe (step, code, msg) VALUES (p_step, SQLSTATE, left(SQLERRM, 4000));
END $f$;

CREATE FUNCTION pg_temp.change_worker(p_step text, p_subject text, p_worker numeric) RETURNS void LANGUAGE plpgsql AS $f$
DECLARE v_t numeric;
BEGIN
    SELECT id INTO STRICT v_t FROM tt.ticket WHERE subject = p_subject;
    CALL tt.ticket_interface_change_worker(v_t, p_worker, 951002);
    INSERT INTO diff_probe (step, s) VALUES (p_step, 'ok');
EXCEPTION WHEN OTHERS THEN
    INSERT INTO diff_probe (step, code, msg) VALUES (p_step, SQLSTATE, left(SQLERRM, 4000));
END $f$;

DO $$
BEGIN
    PERFORM pg_temp.new_ticket('01 A signoff zitadel, no contact, 30002', 'signoff A', 30002, NULL, NULL, 260976466693466175);
    PERFORM pg_temp.new_ticket('02 B signoff zitadel, event 101002',       'signoff B', 101002, NULL, NULL, 260976466693466175);
    PERFORM pg_temp.new_ticket('03 C non-signoff zitadel, 30002',          'signoff C', 30002, NULL, NULL, 123456789012345678);
    PERFORM pg_temp.new_ticket('04 D explicit contact + signoff zitadel',  'signoff D', 30002, 951006, NULL, 260976466693466175);
    PERFORM pg_temp.new_ticket('05 E signoff zitadel without login',       'signoff E', 30002, NULL, NULL, 249698997185305231);
    PERFORM pg_temp.new_ticket('06 F1 worker with login',                  'signoff F1', 101002, NULL, 951003, NULL);
    PERFORM pg_temp.new_ticket('07 F2 worker without login',               'signoff F2', 101002, NULL, 951004, NULL);
    PERFORM pg_temp.change_worker('08 F2 change_worker to worker with login', 'signoff F2', 951003);
END $$;
