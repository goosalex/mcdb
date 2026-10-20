-- tt__event_interface__ticket_type / call.pg.sql -- PostgreSQL twin of call.ora.sql.
DO $$
DECLARE
    r record;
BEGIN
    FOR r IN SELECT id FROM tt.event_type ORDER BY id LOOP
        BEGIN
            INSERT INTO diff_probe (step, n)
            VALUES ('event_type ' || r.id::text, tt.event_interface_ticket_type_for_event_type(r.id));
        EXCEPTION WHEN OTHERS THEN
            INSERT INTO diff_probe (step, code, msg)
            VALUES ('event_type ' || r.id::text, SQLSTATE, left(SQLERRM, 4000));
        END;
    END LOOP;
    BEGIN
        INSERT INTO diff_probe (step, n)
        VALUES ('unknown id 999999999', tt.event_interface_ticket_type_for_event_type(999999999));
    EXCEPTION WHEN OTHERS THEN
        INSERT INTO diff_probe (step, code, msg) VALUES ('unknown id 999999999', SQLSTATE, left(SQLERRM, 4000));
    END;
    BEGIN
        INSERT INTO diff_probe (step, n)
        VALUES ('null id', tt.event_interface_ticket_type_for_event_type(NULL));
    EXCEPTION WHEN OTHERS THEN
        INSERT INTO diff_probe (step, code, msg) VALUES ('null id', SQLSTATE, left(SQLERRM, 4000));
    END;
    INSERT INTO diff_probe (step, n) SELECT 'event_type count', count(*) FROM tt.event_type;
END $$;
