-- tt__ticket_interface__status_engine / call.ora.sql
-- After every successful call the step records '<status> <valid-until set|null> <ev set|null>'
-- in s (ev = the OUT event id of change_status_event_id_out; expire_status has none and
-- records 'ev n/a'); failed steps record the error code. Spec clauses: S-TICKET-021
-- (expire_status), S-TICKET-008..010 and S-TICKET-054 (change_status_event_id_out and
-- handleDeferredTransitions).
DECLARE
    -- SQLCODE/SQLERRM may not appear inside a SQL statement (ORA-00984); pass them as arguments.
    PROCEDURE log_err(p_step VARCHAR2, p_code NUMBER, p_msg VARCHAR2) IS
    BEGIN
        INSERT INTO diff_probe (step, code, msg) VALUES (p_step, TO_CHAR(p_code), SUBSTR(p_msg, 1, 4000));
    END;

    PROCEDURE rec(p_step VARCHAR2, p_ticket NUMBER, p_ev VARCHAR2) IS
        v_s VARCHAR2(60);
    BEGIN
        SELECT status_id || CASE WHEN status_valid_until_date IS NULL THEN ' null ' ELSE ' set ' END || p_ev
        INTO v_s FROM tt.ticket WHERE id = p_ticket;
        INSERT INTO diff_probe (step, s) VALUES (p_step, v_s);
    END;

    PROCEDURE expire(p_step VARCHAR2, p_ticket NUMBER, p_valid_until DATE, p_last_change DATE, p_status NUMBER, p_status_name VARCHAR2) IS
    BEGIN
        tt.ticket_interface.expire_status(p_ticket, p_valid_until, p_last_change, p_status, p_status_name, 1);
        rec(p_step, p_ticket, 'ev n/a');
    EXCEPTION WHEN OTHERS THEN log_err(p_step, SQLCODE, SQLERRM);
    END;

    PROCEDURE cs(p_step VARCHAR2, p_ticket NUMBER, p_status NUMBER, p_contact NUMBER, p_pub VARCHAR2, p_priv VARCHAR2,
                 p_valid_until DATE, p_escalate BOOLEAN, p_hot_reason VARCHAR2, p_zitadel NUMBER) IS
        v_e NUMBER;
    BEGIN
        tt.ticket_interface.change_status_event_id_out(v_e, p_ticket, p_status, p_contact, p_pub, p_priv,
                                                       p_valid_until, NULL, p_escalate, p_hot_reason, p_zitadel);
        rec(p_step, p_ticket, CASE WHEN v_e IS NOT NULL THEN 'ev set' ELSE 'ev null' END);
    EXCEPTION WHEN OTHERS THEN log_err(p_step, SQLCODE, SQLERRM);
    END;
BEGIN
    expire('01 expire waiting 2.5 hours',  952310, TIMESTAMP '2026-01-10 12:30:00', TIMESTAMP '2026-01-10 10:00:00', 11, 'waiting');
    expire('02 expire waiting 2 hours',    952311, TIMESTAMP '2026-01-10 12:00:00', TIMESTAMP '2026-01-10 10:00:00', 11, 'waiting');
    expire('03 expire non-mcc 20 minutes', 952312, TIMESTAMP '2026-01-10 10:20:00', TIMESTAMP '2026-01-10 10:00:00', 11, 'waiting');
    cs('04 open -> deferred escalate',     952313, 60, 952302, 'deferring', NULL, TIMESTAMP '2026-01-30 10:00:00', TRUE, NULL, NULL);
    cs('05 deferred -> hot with reason',   952313, 3, 952302, 'back from deferral', NULL, NULL, NULL, 'customer called', NULL);
    cs('06 open -> resolved',              952314, 101, 952302, 'resolving', 'private note', NULL, NULL, NULL, NULL);
    -- make the resolved period deterministic (30 min) before reopening: the two calls run
    -- within the same second on Oracle (SYSDATE) and within one statement on PostgreSQL
    -- (statement_timestamp()), so the accumulated resolved_time would otherwise depend on timing
    UPDATE tt.ticket SET last_status_change_date = CURRENT_TIMESTAMP - INTERVAL '30' MINUTE WHERE id = 952314;
    cs('07 resolved -> open',              952314, 2, 952302, 'reopening', NULL, NULL, NULL, NULL, NULL);
    cs('08 escalated open -> acknowledged', 952315, 4, 952302, 'acknowledging', NULL, NULL, NULL, NULL, NULL);
    cs('09 open -> open no-op',            952316, 2, 952302, 'same status', NULL, NULL, NULL, NULL, NULL);
    cs('10 open -> acknowledged by zitadel', 952316, 4, NULL, 'ack by zitadel actor', NULL, NULL, NULL, NULL, 952777);
    cs('11 nonexistent ticket',            952999999, 3, 952302, 'x', NULL, NULL, NULL, NULL, NULL);
    expire('12 expire nonexistent ticket', 952999999, TIMESTAMP '2026-01-10 12:00:00', TIMESTAMP '2026-01-10 10:00:00', 11, 'waiting');
END;
/
