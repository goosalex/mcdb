-- tt__ticket_interface__status_engine / call.pg.sql -- PostgreSQL twin of call.ora.sql.
-- Names from migration/mapping/name-map.csv: tt.ticket_interface.expire_status ->
-- tt.ticket_interface_expire_status, change_status_event_id_out ->
-- tt.ticket_interface_change_status_event_id_out (OUT event_id received in a variable;
-- all arguments are typed variables, so positional notation resolves like Oracle's).
CREATE FUNCTION pg_temp.rec(p_step text, p_ticket numeric, p_ev text) RETURNS void LANGUAGE plpgsql AS $f$
DECLARE v_s text;
BEGIN
    SELECT status_id || CASE WHEN status_valid_until_date IS NULL THEN ' null ' ELSE ' set ' END || p_ev
    INTO STRICT v_s FROM tt.ticket WHERE id = p_ticket;
    INSERT INTO diff_probe (step, s) VALUES (p_step, v_s);
END $f$;

CREATE FUNCTION pg_temp.expire(p_step text, p_ticket numeric, p_valid_until timestamp, p_last_change timestamp, p_status numeric, p_status_name text) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
    CALL tt.ticket_interface_expire_status(p_ticket, p_valid_until, p_last_change, p_status, p_status_name, 1);
    PERFORM pg_temp.rec(p_step, p_ticket, 'ev n/a');
EXCEPTION WHEN OTHERS THEN
    INSERT INTO diff_probe (step, code, msg) VALUES (p_step, SQLSTATE, left(SQLERRM, 4000));
END $f$;

CREATE FUNCTION pg_temp.cs(p_step text, p_ticket numeric, p_status numeric, p_contact numeric, p_pub text, p_priv text,
                           p_valid_until timestamp, p_escalate boolean, p_hot_reason text, p_zitadel numeric) RETURNS void LANGUAGE plpgsql AS $f$
DECLARE v_e numeric;
BEGIN
    CALL tt.ticket_interface_change_status_event_id_out(v_e, p_ticket, p_status, p_contact, p_pub, p_priv,
                                                        p_valid_until, NULL, p_escalate, p_hot_reason, p_zitadel);
    PERFORM pg_temp.rec(p_step, p_ticket, CASE WHEN v_e IS NOT NULL THEN 'ev set' ELSE 'ev null' END);
EXCEPTION WHEN OTHERS THEN
    INSERT INTO diff_probe (step, code, msg) VALUES (p_step, SQLSTATE, left(SQLERRM, 4000));
END $f$;

DO $$
BEGIN
    PERFORM pg_temp.expire('01 expire waiting 2.5 hours',  952310, TIMESTAMP '2026-01-10 12:30:00', TIMESTAMP '2026-01-10 10:00:00', 11, 'waiting');
    PERFORM pg_temp.expire('02 expire waiting 2 hours',    952311, TIMESTAMP '2026-01-10 12:00:00', TIMESTAMP '2026-01-10 10:00:00', 11, 'waiting');
    PERFORM pg_temp.expire('03 expire non-mcc 20 minutes', 952312, TIMESTAMP '2026-01-10 10:20:00', TIMESTAMP '2026-01-10 10:00:00', 11, 'waiting');
    PERFORM pg_temp.cs('04 open -> deferred escalate',     952313, 60, 952302, 'deferring', NULL, TIMESTAMP '2026-01-30 10:00:00', TRUE, NULL, NULL);
    PERFORM pg_temp.cs('05 deferred -> hot with reason',   952313, 3, 952302, 'back from deferral', NULL, NULL, NULL, 'customer called', NULL);
    PERFORM pg_temp.cs('06 open -> resolved',              952314, 101, 952302, 'resolving', 'private note', NULL, NULL, NULL, NULL);
    -- make the resolved period deterministic (30 min) before reopening: the two calls run
    -- within the same second on Oracle (SYSDATE) and within one statement on PostgreSQL
    -- (statement_timestamp()), so the accumulated resolved_time would otherwise depend on timing
    UPDATE tt.ticket SET last_status_change_date = CURRENT_TIMESTAMP - INTERVAL '30' MINUTE WHERE id = 952314;
    PERFORM pg_temp.cs('07 resolved -> open',              952314, 2, 952302, 'reopening', NULL, NULL, NULL, NULL, NULL);
    PERFORM pg_temp.cs('08 escalated open -> acknowledged', 952315, 4, 952302, 'acknowledging', NULL, NULL, NULL, NULL, NULL);
    PERFORM pg_temp.cs('09 open -> open no-op',            952316, 2, 952302, 'same status', NULL, NULL, NULL, NULL, NULL);
    PERFORM pg_temp.cs('10 open -> acknowledged by zitadel', 952316, 4, NULL, 'ack by zitadel actor', NULL, NULL, NULL, NULL, 952777);
    PERFORM pg_temp.cs('11 nonexistent ticket',            952999999, 3, 952302, 'x', NULL, NULL, NULL, NULL, NULL);
    PERFORM pg_temp.expire('12 expire nonexistent ticket', 952999999, TIMESTAMP '2026-01-10 12:00:00', TIMESTAMP '2026-01-10 10:00:00', 11, 'waiting');
END $$;
