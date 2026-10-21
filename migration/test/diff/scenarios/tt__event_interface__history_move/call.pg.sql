-- tt__event_interface__history_move / call.pg.sql -- PostgreSQL twin of call.ora.sql.
-- Names from migration/mapping/name-map.csv: tt.event_interface.<routine> ->
-- tt.event_interface_<routine> (all procedures -> CALL; OUT parameter first).
CREATE FUNCTION pg_temp.hist(p_step text, p_ticket numeric, p_pub text, p_priv text, p_public boolean, p_contact numeric) RETURNS void LANGUAGE plpgsql AS $f$
DECLARE v_e numeric;
BEGIN
    CALL tt.event_interface_add_history_event(v_e, p_ticket, 101001, 957305, 957301, p_pub, p_priv, p_public,
                                              p_contact_id => p_contact);
    INSERT INTO diff_probe (step, s) VALUES (p_step, CASE WHEN v_e IS NOT NULL THEN 'event id set' ELSE 'event id null' END);
EXCEPTION WHEN OTHERS THEN
    INSERT INTO diff_probe (step, code, msg) VALUES (p_step, SQLSTATE, left(SQLERRM, 4000));
END $f$;

CREATE FUNCTION pg_temp.demote(p_step text, p_event numeric) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
    CALL tt.event_interface_demote_event(p_event, 957302);
    INSERT INTO diff_probe (step, s) VALUES (p_step, 'ok');
EXCEPTION WHEN OTHERS THEN
    INSERT INTO diff_probe (step, code, msg) VALUES (p_step, SQLSTATE, left(SQLERRM, 4000));
END $f$;

CREATE FUNCTION pg_temp.promote(p_step text, p_event numeric) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
    CALL tt.event_interface_promote_event(p_event, 957302);
    INSERT INTO diff_probe (step, s) VALUES (p_step, 'ok');
EXCEPTION WHEN OTHERS THEN
    INSERT INTO diff_probe (step, code, msg) VALUES (p_step, SQLSTATE, left(SQLERRM, 4000));
END $f$;

CREATE FUNCTION pg_temp.move(p_step text, p_event numeric, p_old numeric, p_new numeric) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
    CALL tt.event_interface_moveevent(p_event, p_old, p_new);
    INSERT INTO diff_probe (step, s) VALUES (p_step, 'ok');
EXCEPTION WHEN OTHERS THEN
    INSERT INTO diff_probe (step, code, msg) VALUES (p_step, SQLSTATE, left(SQLERRM, 4000));
END $f$;

DO $$
BEGIN
    PERFORM pg_temp.hist('01 history event public with contact',   957312, 'history text', 'history private', TRUE, 957302);
    PERFORM pg_temp.hist('02 history event private without contact', 957312, 'private history', NULL, FALSE, NULL);
    PERFORM pg_temp.hist('03 history event on nonexistent ticket', 957999, 'orphan history', NULL, TRUE, 957302);
    PERFORM pg_temp.demote('11 demote existing event',             957324);
    PERFORM pg_temp.demote('12 demote nonexistent event',          957999999);
    PERFORM pg_temp.promote('13 promote existing event',           957324);
    PERFORM pg_temp.promote('14 promote nonexistent event',        957999999);
    PERFORM pg_temp.move('31 move decoy event not on old ticket',  957323, 957311, 957312);
    PERFORM pg_temp.move('32 move event from old to new ticket',   957321, 957311, 957312);
    PERFORM pg_temp.move('33 move nonexistent event',              957999999, 957313, 957312);
    PERFORM pg_temp.move('34 move to nonexistent new ticket',      957322, 957311, 957999);
    PERFORM pg_temp.move('35 move with NULL event id',             NULL, 957311, 957312);
END $$;
