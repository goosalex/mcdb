-- tt__event_interface__ticket_type / call.pg.sql -- PostgreSQL twin of call.ora.sql.
-- Name from migration/mapping/name-map.csv: tt.event_interface.ticket_type_for_event_type
-- -> tt.event_interface_ticket_type_for_event_type (FUNCTION).
CREATE FUNCTION pg_temp.probe(p_id numeric) RETURNS void LANGUAGE plpgsql AS $f$
DECLARE
    v_step text := 'event_type ' || coalesce(p_id::text, 'NULL');
BEGIN
    INSERT INTO diff_probe (step, n) VALUES (v_step, tt.event_interface_ticket_type_for_event_type(p_id));
EXCEPTION WHEN OTHERS THEN
    INSERT INTO diff_probe (step, code, msg) VALUES (v_step, SQLSTATE, left(SQLERRM, 4000));
END $f$;
DO $$
BEGIN
    -- 3rd party incident family
    PERFORM pg_temp.probe(10003); PERFORM pg_temp.probe(10110); PERFORM pg_temp.probe(10102); PERFORM pg_temp.probe(10019);
    -- change request family
    PERFORM pg_temp.probe(30002); PERFORM pg_temp.probe(30009);
    -- default (trouble ticket)
    PERFORM pg_temp.probe(10001); PERFORM pg_temp.probe(10002); PERFORM pg_temp.probe(10004); PERFORM pg_temp.probe(10101);
    PERFORM pg_temp.probe(10103); PERFORM pg_temp.probe(10109); PERFORM pg_temp.probe(10111); PERFORM pg_temp.probe(10501);
    PERFORM pg_temp.probe(10602); PERFORM pg_temp.probe(20001); PERFORM pg_temp.probe(30001); PERFORM pg_temp.probe(30003);
    PERFORM pg_temp.probe(30008); PERFORM pg_temp.probe(30010); PERFORM pg_temp.probe(30024); PERFORM pg_temp.probe(30025);
    PERFORM pg_temp.probe(40001); PERFORM pg_temp.probe(50001); PERFORM pg_temp.probe(50011); PERFORM pg_temp.probe(60104);
    PERFORM pg_temp.probe(101002);
    -- not an event type at all, and NULL
    PERFORM pg_temp.probe(999999999); PERFORM pg_temp.probe(NULL);
END $$;
