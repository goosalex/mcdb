-- tt__ticket_interface__relations / call.pg.sql -- PostgreSQL twin of call.ora.sql.
-- Names from migration/mapping/name-map.csv: tt.ticket_interface.<name> ->
-- tt.ticket_interface_<name> (procedures -> CALL).
CREATE FUNCTION pg_temp.ok(p_step text) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
    INSERT INTO diff_probe (step, s) VALUES (p_step, 'ok');
END $f$;

CREATE FUNCTION pg_temp.add_rt(p_step text, p_t numeric, p_r numeric) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
    CALL tt.ticket_interface_add_related_ticket(p_t, p_r, 954003);
    PERFORM pg_temp.ok(p_step);
EXCEPTION WHEN OTHERS THEN
    INSERT INTO diff_probe (step, code, msg) VALUES (p_step, SQLSTATE, left(SQLERRM, 4000));
END $f$;

CREATE FUNCTION pg_temp.rem_rt(p_step text, p_t numeric, p_r numeric) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
    CALL tt.ticket_interface_remove_related_ticket(p_t, p_r, 954003);
    PERFORM pg_temp.ok(p_step);
EXCEPTION WHEN OTHERS THEN
    INSERT INTO diff_probe (step, code, msg) VALUES (p_step, SQLSTATE, left(SQLERRM, 4000));
END $f$;

CREATE FUNCTION pg_temp.add_rf(p_step text, p_t numeric, p_f numeric) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
    CALL tt.ticket_interface_add_related_file(p_t, p_f, 954003);
    PERFORM pg_temp.ok(p_step);
EXCEPTION WHEN OTHERS THEN
    INSERT INTO diff_probe (step, code, msg) VALUES (p_step, SQLSTATE, left(SQLERRM, 4000));
END $f$;

CREATE FUNCTION pg_temp.rem_rf(p_step text, p_t numeric, p_f numeric) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
    CALL tt.ticket_interface_remove_related_file(p_t, p_f, 954003);
    PERFORM pg_temp.ok(p_step);
EXCEPTION WHEN OTHERS THEN
    INSERT INTO diff_probe (step, code, msg) VALUES (p_step, SQLSTATE, left(SQLERRM, 4000));
END $f$;

DO $$
BEGIN
    PERFORM pg_temp.add_rt('01 add T1-T2',                     954010, 954011);
    PERFORM pg_temp.add_rt('02 add T1-T2 again duplicate',     954010, 954011);
    PERFORM pg_temp.add_rt('03 add T1-T1 equal ids',           954010, 954010);
    PERFORM pg_temp.add_rt('04 add T1-nonexistent',            954010, 954099999);
    PERFORM pg_temp.add_rt('05 add T1-T3 other company',       954010, 954012);
    PERFORM pg_temp.rem_rt('06 remove T3-T2 reverse direction', 954012, 954011);
    PERFORM pg_temp.rem_rt('07 remove T2-T3',                  954011, 954012);
    PERFORM pg_temp.add_rf('08 add file F1 same company',      954010, 954020);
    PERFORM pg_temp.add_rf('09 add file F2 other company',     954010, 954022);
    PERFORM pg_temp.add_rf('10 add file F1 nonexistent ticket', 954099999, 954020);
    PERFORM pg_temp.add_rf('11 add file F1 again duplicate',   954010, 954020);
    PERFORM pg_temp.rem_rf('12 remove file F3 same company',   954010, 954024);
    PERFORM pg_temp.rem_rf('13 remove file F4 other company',  954010, 954026);
    PERFORM pg_temp.rem_rf('14 remove file orphan 954098',     954010, 954098);
    PERFORM pg_temp.rem_rf('15 remove file F2 no relation',    954010, 954022);
END $$;
