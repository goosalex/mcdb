-- tt__ticket_interface__merge_delete / call.pg.sql -- PostgreSQL twin of call.ora.sql.
-- Names from migration/mapping/name-map.csv: tt.ticket_interface.merge_tickets ->
-- tt.ticket_interface_merge_tickets, deleteTicket -> tt.ticket_interface_deleteticket.
CREATE FUNCTION pg_temp.ok(p_step text) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
    INSERT INTO diff_probe (step, s) VALUES (p_step, 'ok');
END $f$;

CREATE FUNCTION pg_temp.merge(p_step text, p_src numeric, p_tgt numeric) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
    CALL tt.ticket_interface_merge_tickets(p_src, p_tgt, 954302);
    PERFORM pg_temp.ok(p_step);
EXCEPTION WHEN OTHERS THEN
    INSERT INTO diff_probe (step, code, msg) VALUES (p_step, SQLSTATE, left(SQLERRM, 4000));
END $f$;

CREATE FUNCTION pg_temp.del(p_step text, p_t numeric) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
    CALL tt.ticket_interface_deleteticket(p_t);
    PERFORM pg_temp.ok(p_step);
EXCEPTION WHEN OTHERS THEN
    INSERT INTO diff_probe (step, code, msg) VALUES (p_step, SQLSTATE, left(SQLERRM, 4000));
END $f$;

DO $$
BEGIN
    PERFORM pg_temp.merge('01 merge SRC into TGT',             954320, 954321);
    PERFORM pg_temp.merge('02 merge SRC2 into TGT2',           954323, 954322);
    PERFORM pg_temp.merge('03 merge nonexistent source',       954099999, 954322);
    PERFORM pg_temp.merge('04 merge into nonexistent target',  954323, 954099999);
    PERFORM pg_temp.del('05 delete DEL',                       954325);
    PERFORM pg_temp.del('06 delete nonexistent ticket',        954099999);
END $$;
