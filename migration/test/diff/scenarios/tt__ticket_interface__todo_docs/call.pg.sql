-- tt__ticket_interface__todo_docs / call.pg.sql -- PostgreSQL twin of call.ora.sql.
-- Names from migration/mapping/name-map.csv: tt.ticket_interface.<name> ->
-- tt.ticket_interface_<name> (procedures -> CALL). OUT parameters are received in
-- variables; trailing optional arguments are passed by name.
CREATE FUNCTION pg_temp.ok(p_step text, p_s text DEFAULT 'ok') RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
    INSERT INTO diff_probe (step, s) VALUES (p_step, p_s);
END $f$;

CREATE FUNCTION pg_temp.add_page(p_step text, p_t numeric, p_page numeric, p_ver numeric, p_title text, p_hot numeric) RETURNS void LANGUAGE plpgsql AS $f$
DECLARE v_id numeric;
BEGIN
    CALL tt.ticket_interface_add_docs_page(v_id, p_t, p_page, p_ver, p_title, p_hot, 954102);
    PERFORM pg_temp.ok(p_step, CASE WHEN v_id IS NOT NULL THEN 'id set' ELSE 'id null' END);
EXCEPTION WHEN OTHERS THEN
    INSERT INTO diff_probe (step, code, msg) VALUES (p_step, SQLSTATE, left(SQLERRM, 4000));
END $f$;

CREATE FUNCTION pg_temp.rem_page(p_step text, p_id numeric, p_title text) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
    CALL tt.ticket_interface_remove_docs_page(p_id, p_title, 954102);
    PERFORM pg_temp.ok(p_step);
EXCEPTION WHEN OTHERS THEN
    INSERT INTO diff_probe (step, code, msg) VALUES (p_step, SQLSTATE, left(SQLERRM, 4000));
END $f$;

CREATE FUNCTION pg_temp.add_todo(p_step text, p_t numeric, p_seq numeric, p_details text, p_status numeric, p_public numeric) RETURNS void LANGUAGE plpgsql AS $f$
DECLARE v_id numeric;
BEGIN
    CALL tt.ticket_interface_add_todo_item(v_id, p_t, p_seq, p_details, p_status, 954102, p_todo_item_is_public => p_public);
    PERFORM pg_temp.ok(p_step, CASE WHEN v_id IS NOT NULL THEN 'id set' ELSE 'id null' END);
EXCEPTION WHEN OTHERS THEN
    INSERT INTO diff_probe (step, code, msg) VALUES (p_step, SQLSTATE, left(SQLERRM, 4000));
END $f$;

CREATE FUNCTION pg_temp.upd_todo(p_step text, p_t numeric, p_seq numeric, p_status numeric) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
    CALL tt.ticket_interface_update_todo_item_status(p_t, p_seq, p_status, 954102);
    PERFORM pg_temp.ok(p_step);
EXCEPTION WHEN OTHERS THEN
    INSERT INTO diff_probe (step, code, msg) VALUES (p_step, SQLSTATE, left(SQLERRM, 4000));
END $f$;

CREATE FUNCTION pg_temp.clear_todo(p_step text, p_t numeric, p_hist numeric) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
    CALL tt.ticket_interface_clear_todo_list(p_t, 954102, p_add_history_event => p_hist);
    PERFORM pg_temp.ok(p_step);
EXCEPTION WHEN OTHERS THEN
    INSERT INTO diff_probe (step, code, msg) VALUES (p_step, SQLSTATE, left(SQLERRM, 4000));
END $f$;

CREATE FUNCTION pg_temp.classify(p_step text, p_t numeric, p_class numeric) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
    CALL tt.ticket_interface_classify_request(p_t, p_class, 954102);
    PERFORM pg_temp.ok(p_step);
EXCEPTION WHEN OTHERS THEN
    INSERT INTO diff_probe (step, code, msg) VALUES (p_step, SQLSTATE, left(SQLERRM, 4000));
END $f$;

DO $$
BEGIN
    PERFORM pg_temp.add_page('01 add page',                      954110, 700010, 1, 'Diff Page', 0);
    PERFORM pg_temp.add_page('02 add hot issue page',            954110, 700011, 2, 'Hot Page', 1);
    PERFORM pg_temp.add_page('03 add page nonexistent ticket',   954099999, 700012, 1, 'Ghost Page', 0);
    PERFORM pg_temp.rem_page('04 remove fixture page',           954130, 'Old Page');
    PERFORM pg_temp.rem_page('05 remove nonexistent page',       954099998, 'No Page');
    PERFORM pg_temp.add_todo('06 add public todo',               954110, 0, 'step one', 1, 1);
    PERFORM pg_temp.add_todo('07 add public done',               954110, 1, 'step two', 2, 1);
    PERFORM pg_temp.add_todo('08 add private todo',              954110, 2, 'private step', 1, 0);
    PERFORM pg_temp.upd_todo('09 public todo to done',           954110, 0, 2);
    PERFORM pg_temp.upd_todo('10 public done to active',         954110, 1, 3);
    PERFORM pg_temp.upd_todo('11 private todo to skipped',       954110, 2, 4);
    PERFORM pg_temp.upd_todo('12 TD3 bad status id',             954112, 0, 999);
    PERFORM pg_temp.upd_todo('13 nonexistent seq',               954110, 9, 2);
    PERFORM pg_temp.clear_todo('14 clear TD4 without history',   954113, 0);
    PERFORM pg_temp.clear_todo('15 clear nonexistent no history', 954099999, 0);
    PERFORM pg_temp.clear_todo('16 clear nonexistent with history', 954099998, 1);
    PERFORM pg_temp.clear_todo('17 clear TD with history',       954110, 1);
    PERFORM pg_temp.classify('18 classify TD very precise',      954110, 1);
    PERFORM pg_temp.classify('19 classify TD invalid 7 to standard', 954110, 7);
    PERFORM pg_temp.classify('20 classify TD2 null to standard', 954111, NULL);
    PERFORM pg_temp.classify('21 classify nonexistent imprecise', 954099997, 3);
END $$;
