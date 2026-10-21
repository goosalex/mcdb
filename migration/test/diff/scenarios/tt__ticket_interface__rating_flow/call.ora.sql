-- tt__ticket_interface__rating_flow / call.ora.sql
-- rate_ticket's OUT rating id is sequence-generated (differs per engine): only id set/null
-- is recorded; the rating value is probed through the ticket's rating column.
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

    PROCEDURE rate(p_step VARCHAR2, p_t NUMBER, p_event NUMBER, p_by_eng NUMBER, p_value NUMBER) IS
        v_id NUMBER;
    BEGIN
        tt.ticket_interface.rate_ticket(v_id, p_t, p_event, 954202, p_by_eng, p_value);
        ok(p_step, CASE WHEN v_id IS NOT NULL THEN 'id set' ELSE 'id null' END);
    EXCEPTION WHEN OTHERS THEN log_err(p_step, SQLCODE, SQLERRM);
    END;

    PROCEDURE escalate(p_step VARCHAR2, p_t NUMBER, p_event NUMBER) IS
    BEGIN
        tt.ticket_interface.trigger_escalation(p_t, 954202, p_event);
        ok(p_step);
    EXCEPTION WHEN OTHERS THEN log_err(p_step, SQLCODE, SQLERRM);
    END;

    -- p_minutes: minutes ago of the previous status change (NULL = no previous status given)
    PROCEDURE flow(p_step VARCHAR2, p_t NUMBER, p_prev NUMBER, p_minutes NUMBER) IS
        v_prev_date DATE;
    BEGIN
        IF p_minutes IS NOT NULL THEN
            v_prev_date := SYSDATE - p_minutes / 1440;
        END IF;
        tt.ticket_interface.updateTicketFlow(p_t, p_prev, v_prev_date);
        ok(p_step);
    EXCEPTION WHEN OTHERS THEN log_err(p_step, SQLCODE, SQLERRM);
    END;
BEGIN
    rate('01 R1 engineer rating 2',           954210, 954220, 1, 2);
    rate('02 R2 customer rating 5',           954211, 954221, 0, 5);
    rate('03 R3 customer rating 1 to hot',    954212, 954222, 0, 1);
    rate('04 R1 engineer rating 4 replaces',  954210, 954220, 1, 4);
    rate('05 nonexistent ticket engineer 2',  954099999, 954220, 1, 2);
    escalate('06 escalation E',               954213, 954223);
    escalate('07 escalation nonexistent ticket', 954099999, 954223);
    flow('08 F1 open MCC enters queue',       954214, NULL, NULL);
    flow('09 F1 again already queued',        954214, NULL, NULL);
    flow('10 F2 type 4 never queued',         954215, NULL, NULL);
    flow('11 F3 hot stays prev open 60m',     954216, 2, 60);
    flow('12 F4 not MCC leaves open 30m',     954217, NULL, NULL);
    flow('13 F5 waiting leaves prev open 45m', 954218, 2, 45);
    flow('14 F6 third party leaves no prev',  954219, NULL, NULL);
    flow('15 nonexistent ticket',             954099999, NULL, NULL);
END;
/
