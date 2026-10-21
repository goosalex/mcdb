-- tt__ticket_interface__rating_flow / call.pg.sql -- PostgreSQL twin of call.ora.sql.
-- Names from migration/mapping/name-map.csv: tt.ticket_interface.rate_ticket ->
-- tt.ticket_interface_rate_ticket, trigger_escalation -> tt.ticket_interface_trigger_escalation,
-- updateTicketFlow -> tt.ticket_interface_updateticketflow (procedures -> CALL). The date
-- argument is passed by name (p_prev_status_change_date is timestamptz).
CREATE FUNCTION pg_temp.ok(p_step text, p_s text DEFAULT 'ok') RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
    INSERT INTO diff_probe (step, s) VALUES (p_step, p_s);
END $f$;

CREATE FUNCTION pg_temp.rate(p_step text, p_t numeric, p_event numeric, p_by_eng numeric, p_value numeric) RETURNS void LANGUAGE plpgsql AS $f$
DECLARE v_id numeric;
BEGIN
    CALL tt.ticket_interface_rate_ticket(v_id, p_t, p_event, 954202, p_by_eng, p_value);
    PERFORM pg_temp.ok(p_step, CASE WHEN v_id IS NOT NULL THEN 'id set' ELSE 'id null' END);
EXCEPTION WHEN OTHERS THEN
    INSERT INTO diff_probe (step, code, msg) VALUES (p_step, SQLSTATE, left(SQLERRM, 4000));
END $f$;

CREATE FUNCTION pg_temp.escalate(p_step text, p_t numeric, p_event numeric) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
    CALL tt.ticket_interface_trigger_escalation(p_t, 954202, p_event);
    PERFORM pg_temp.ok(p_step);
EXCEPTION WHEN OTHERS THEN
    INSERT INTO diff_probe (step, code, msg) VALUES (p_step, SQLSTATE, left(SQLERRM, 4000));
END $f$;

-- p_minutes: minutes ago of the previous status change (NULL = no previous status given)
CREATE FUNCTION pg_temp.flow(p_step text, p_t numeric, p_prev numeric, p_minutes numeric) RETURNS void LANGUAGE plpgsql AS $f$
DECLARE v_prev_date timestamptz;
BEGIN
    IF p_minutes IS NOT NULL THEN
        v_prev_date := statement_timestamp() - make_interval(mins => p_minutes::int);
    END IF;
    CALL tt.ticket_interface_updateticketflow(p_t, p_prev, p_prev_status_change_date => v_prev_date);
    PERFORM pg_temp.ok(p_step);
EXCEPTION WHEN OTHERS THEN
    INSERT INTO diff_probe (step, code, msg) VALUES (p_step, SQLSTATE, left(SQLERRM, 4000));
END $f$;

DO $$
BEGIN
    PERFORM pg_temp.rate('01 R1 engineer rating 2',           954210, 954220, 1, 2);
    PERFORM pg_temp.rate('02 R2 customer rating 5',           954211, 954221, 0, 5);
    PERFORM pg_temp.rate('03 R3 customer rating 1 to hot',    954212, 954222, 0, 1);
    PERFORM pg_temp.rate('04 R1 engineer rating 4 replaces',  954210, 954220, 1, 4);
    PERFORM pg_temp.rate('05 nonexistent ticket engineer 2',  954099999, 954220, 1, 2);
    PERFORM pg_temp.escalate('06 escalation E',               954213, 954223);
    PERFORM pg_temp.escalate('07 escalation nonexistent ticket', 954099999, 954223);
    PERFORM pg_temp.flow('08 F1 open MCC enters queue',       954214, NULL, NULL);
    PERFORM pg_temp.flow('09 F1 again already queued',        954214, NULL, NULL);
    PERFORM pg_temp.flow('10 F2 type 4 never queued',         954215, NULL, NULL);
    PERFORM pg_temp.flow('11 F3 hot stays prev open 60m',     954216, 2, 60);
    PERFORM pg_temp.flow('12 F4 not MCC leaves open 30m',     954217, NULL, NULL);
    PERFORM pg_temp.flow('13 F5 waiting leaves prev open 45m', 954218, 2, 45);
    PERFORM pg_temp.flow('14 F6 third party leaves no prev',  954219, NULL, NULL);
    PERFORM pg_temp.flow('15 nonexistent ticket',             954099999, NULL, NULL);
END $$;
