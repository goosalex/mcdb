-- tt__event_interface__ticket_type / call.ora.sql
DECLARE
    -- SQLCODE/SQLERRM may not appear inside a SQL statement (ORA-00984); pass them as arguments.
    PROCEDURE log_err(p_step VARCHAR2, p_code NUMBER, p_msg VARCHAR2) IS
    BEGIN
        INSERT INTO diff_probe (step, code, msg) VALUES (p_step, TO_CHAR(p_code), SUBSTR(p_msg, 1, 4000));
    END;
BEGIN
    FOR r IN (SELECT id FROM tt.event_type ORDER BY id) LOOP
        BEGIN
            INSERT INTO diff_probe (step, n)
            VALUES ('event_type ' || TO_CHAR(r.id), tt.event_interface.ticket_type_for_event_type(r.id));
        EXCEPTION WHEN OTHERS THEN
            log_err('event_type ' || TO_CHAR(r.id), SQLCODE, SQLERRM);
        END;
    END LOOP;
    -- the function never reads tt.event_type: an unknown id and NULL fall through to the default
    BEGIN
        INSERT INTO diff_probe (step, n)
        VALUES ('unknown id 999999999', tt.event_interface.ticket_type_for_event_type(999999999));
    EXCEPTION WHEN OTHERS THEN
        log_err('unknown id 999999999', SQLCODE, SQLERRM);
    END;
    BEGIN
        INSERT INTO diff_probe (step, n)
        VALUES ('null id', tt.event_interface.ticket_type_for_event_type(NULL));
    EXCEPTION WHEN OTHERS THEN
        log_err('null id', SQLCODE, SQLERRM);
    END;
    INSERT INTO diff_probe (step, n) SELECT 'event_type count', COUNT(*) FROM tt.event_type;
END;
/
