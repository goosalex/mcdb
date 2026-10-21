-- tt__event_interface__ticket_type / call.ora.sql
-- The function is pure (it never reads tt.event_type), so it is driven with an EXPLICIT
-- list of ids covering every branch of ddl/src/pkgb/tt_event_interface.sql: the four
-- 3rd-party-incident ids (-> 4), the two change-request ids (-> 2), representative ids of
-- every other event-type family and of the ids only one side's master data has (-> 1),
-- an unknown id and NULL. Iterating tt.event_type would compare master-data drift
-- (Oracle 134 rows vs PostgreSQL 131 on 2026-10-21), not the function.
DECLARE
    -- SQLCODE/SQLERRM may not appear inside a SQL statement (ORA-00984); pass them as arguments.
    PROCEDURE log_err(p_step VARCHAR2, p_code NUMBER, p_msg VARCHAR2) IS
    BEGIN
        INSERT INTO diff_probe (step, code, msg) VALUES (p_step, TO_CHAR(p_code), SUBSTR(p_msg, 1, 4000));
    END;
    PROCEDURE probe(p_id NUMBER) IS
        v_step VARCHAR2(100) := 'event_type ' || NVL(TO_CHAR(p_id), 'NULL');
    BEGIN
        INSERT INTO diff_probe (step, n) VALUES (v_step, tt.event_interface.ticket_type_for_event_type(p_id));
    EXCEPTION WHEN OTHERS THEN
        log_err(v_step, SQLCODE, SQLERRM);
    END;
BEGIN
    -- 3rd party incident family
    probe(10003); probe(10110); probe(10102); probe(10019);
    -- change request family
    probe(30002); probe(30009);
    -- default (trouble ticket): neighbours of the special ids and one id per family
    probe(10001); probe(10002); probe(10004); probe(10101); probe(10103); probe(10109); probe(10111);
    probe(10501); probe(10602); probe(20001); probe(30001); probe(30003); probe(30008); probe(30010);
    probe(30024); probe(30025); probe(40001); probe(50001); probe(50011); probe(60104); probe(101002);
    -- not an event type at all, and NULL
    probe(999999999); probe(NULL);
END;
/
