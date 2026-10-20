-- tt__event_interface__ticket_type / call.ora.sql
BEGIN
    FOR r IN (SELECT id FROM tt.event_type ORDER BY id) LOOP
        BEGIN
            INSERT INTO diff_probe (step, n)
            VALUES ('event_type ' || TO_CHAR(r.id), tt.event_interface.ticket_type_for_event_type(r.id));
        EXCEPTION WHEN OTHERS THEN
            INSERT INTO diff_probe (step, code, msg)
            VALUES ('event_type ' || TO_CHAR(r.id), TO_CHAR(SQLCODE), SUBSTR(SQLERRM, 1, 4000));
        END;
    END LOOP;
    -- the function never reads tt.event_type: an unknown id and NULL fall through to the default
    BEGIN
        INSERT INTO diff_probe (step, n)
        VALUES ('unknown id 999999999', tt.event_interface.ticket_type_for_event_type(999999999));
    EXCEPTION WHEN OTHERS THEN
        INSERT INTO diff_probe (step, code, msg) VALUES ('unknown id 999999999', TO_CHAR(SQLCODE), SUBSTR(SQLERRM, 1, 4000));
    END;
    BEGIN
        INSERT INTO diff_probe (step, n)
        VALUES ('null id', tt.event_interface.ticket_type_for_event_type(NULL));
    EXCEPTION WHEN OTHERS THEN
        INSERT INTO diff_probe (step, code, msg) VALUES ('null id', TO_CHAR(SQLCODE), SUBSTR(SQLERRM, 1, 4000));
    END;
    INSERT INTO diff_probe (step, n) SELECT 'event_type count', COUNT(*) FROM tt.event_type;
END;
/
