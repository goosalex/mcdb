-- tt__ticket_interface__todo_docs / call.ora.sql
-- OUT ids (docs page id, todo item id) are sequence-generated and differ per engine, so
-- only "id set"/"id null" is recorded in s; failed steps record the error code.
DECLARE
    -- SQLCODE/SQLERRM may not appear inside a SQL statement (ORA-00984); pass them as arguments.
    PROCEDURE log_err(p_step VARCHAR2, p_code NUMBER, p_msg VARCHAR2) IS
    BEGIN
        INSERT INTO diff_probe (step, code, msg) VALUES (p_step, TO_CHAR(p_code), SUBSTR(p_msg, 1, 4000));
    END;

    PROCEDURE ok(p_step VARCHAR2, p_s VARCHAR2 DEFAULT 'ok') IS
    BEGIN
        INSERT INTO diff_probe (step, s) VALUES (p_step, p_s);
    END;

    PROCEDURE add_page(p_step VARCHAR2, p_t NUMBER, p_page NUMBER, p_ver NUMBER, p_title VARCHAR2, p_hot NUMBER) IS
        v_id NUMBER;
    BEGIN
        tt.ticket_interface.add_docs_page(v_id, p_t, p_page, p_ver, p_title, p_hot, 954102);
        ok(p_step, CASE WHEN v_id IS NOT NULL THEN 'id set' ELSE 'id null' END);
    EXCEPTION WHEN OTHERS THEN log_err(p_step, SQLCODE, SQLERRM);
    END;

    PROCEDURE rem_page(p_step VARCHAR2, p_id NUMBER, p_title VARCHAR2) IS
    BEGIN
        tt.ticket_interface.remove_docs_page(p_id, p_title, 954102);
        ok(p_step);
    EXCEPTION WHEN OTHERS THEN log_err(p_step, SQLCODE, SQLERRM);
    END;

    PROCEDURE add_todo(p_step VARCHAR2, p_t NUMBER, p_seq NUMBER, p_details VARCHAR2, p_status NUMBER, p_public NUMBER) IS
        v_id NUMBER;
    BEGIN
        tt.ticket_interface.add_todo_item(v_id, p_t, p_seq, p_details, p_status, 954102, p_public);
        ok(p_step, CASE WHEN v_id IS NOT NULL THEN 'id set' ELSE 'id null' END);
    EXCEPTION WHEN OTHERS THEN log_err(p_step, SQLCODE, SQLERRM);
    END;

    PROCEDURE upd_todo(p_step VARCHAR2, p_t NUMBER, p_seq NUMBER, p_status NUMBER) IS
    BEGIN
        tt.ticket_interface.update_todo_item_status(p_t, p_seq, p_status, 954102);
        ok(p_step);
    EXCEPTION WHEN OTHERS THEN log_err(p_step, SQLCODE, SQLERRM);
    END;

    PROCEDURE clear_todo(p_step VARCHAR2, p_t NUMBER, p_hist NUMBER) IS
    BEGIN
        tt.ticket_interface.clear_todo_list(p_t, 954102, p_hist);
        ok(p_step);
    EXCEPTION WHEN OTHERS THEN log_err(p_step, SQLCODE, SQLERRM);
    END;

    PROCEDURE classify(p_step VARCHAR2, p_t NUMBER, p_class NUMBER) IS
    BEGIN
        tt.ticket_interface.classify_request(p_t, p_class, 954102);
        ok(p_step);
    EXCEPTION WHEN OTHERS THEN log_err(p_step, SQLCODE, SQLERRM);
    END;
BEGIN
    add_page('01 add page',                      954110, 700010, 1, 'Diff Page', 0);
    add_page('02 add hot issue page',            954110, 700011, 2, 'Hot Page', 1);
    add_page('03 add page nonexistent ticket',   954099999, 700012, 1, 'Ghost Page', 0);
    rem_page('04 remove fixture page',           954130, 'Old Page');
    rem_page('05 remove nonexistent page',       954099998, 'No Page');
    add_todo('06 add public todo',               954110, 0, 'step one', 1, 1);
    add_todo('07 add public done',               954110, 1, 'step two', 2, 1);
    add_todo('08 add private todo',              954110, 2, 'private step', 1, 0);
    upd_todo('09 public todo to done',           954110, 0, 2);
    upd_todo('10 public done to active',         954110, 1, 3);
    upd_todo('11 private todo to skipped',       954110, 2, 4);
    upd_todo('12 TD3 bad status id',             954112, 0, 999);
    upd_todo('13 nonexistent seq',               954110, 9, 2);
    clear_todo('14 clear TD4 without history',   954113, 0);
    clear_todo('15 clear nonexistent no history', 954099999, 0);
    clear_todo('16 clear nonexistent with history', 954099998, 1);
    clear_todo('17 clear TD with history',       954110, 1);
    classify('18 classify TD very precise',      954110, 1);
    classify('19 classify TD invalid 7 to standard', 954110, 7);
    classify('20 classify TD2 null to standard', 954111, NULL);
    classify('21 classify nonexistent imprecise', 954099997, 3);
END;
/
