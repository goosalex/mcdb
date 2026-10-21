-- tt__ticket_interface__deferral_ux / call.ora.sql
-- After every successful call the ticket's ux_timeout is recorded in s as 'ux <day>/<hour>'
-- (wall clock of CAST(ux_timeout AS TIMESTAMP)) or 'ux null'; failed steps record the code.
-- Contact 952202 acts throughout. Spec clauses: S-TICKET-006 (change_deferral_date),
-- S-TICKET-011/012 (update_ux_timeout_for_ticket), S-TICKET-025 (change_emergency).
DECLARE
    -- SQLCODE/SQLERRM may not appear inside a SQL statement (ORA-00984); pass them as arguments.
    PROCEDURE log_err(p_step VARCHAR2, p_code NUMBER, p_msg VARCHAR2) IS
    BEGIN
        INSERT INTO diff_probe (step, code, msg) VALUES (p_step, TO_CHAR(p_code), SUBSTR(p_msg, 1, 4000));
    END;

    PROCEDURE rec_ux(p_step VARCHAR2, p_ticket NUMBER) IS
        v_s VARCHAR2(60);
    BEGIN
        SELECT CASE WHEN ux_timeout IS NULL THEN 'ux null'
                    ELSE 'ux ' || EXTRACT(DAY FROM CAST(ux_timeout AS TIMESTAMP)) || '/' || EXTRACT(HOUR FROM CAST(ux_timeout AS TIMESTAMP)) END
        INTO v_s FROM tt.ticket WHERE id = p_ticket;
        INSERT INTO diff_probe (step, s) VALUES (p_step, v_s);
    END;

    PROCEDURE deferral(p_step VARCHAR2, p_ticket NUMBER, p_date DATE, p_text VARCHAR2) IS
    BEGIN
        tt.ticket_interface.change_deferral_date(p_ticket, 952202, p_date, p_text);
        rec_ux(p_step, p_ticket);
    EXCEPTION WHEN OTHERS THEN log_err(p_step, SQLCODE, SQLERRM);
    END;

    PROCEDURE ux(p_step VARCHAR2, p_ticket NUMBER, p_initial BOOLEAN) IS
    BEGIN
        tt.ticket_interface.update_ux_timeout_for_ticket(p_ticket, p_initial);
        rec_ux(p_step, p_ticket);
    EXCEPTION WHEN OTHERS THEN log_err(p_step, SQLCODE, SQLERRM);
    END;

    PROCEDURE emergency(p_step VARCHAR2, p_ticket NUMBER, p_flag NUMBER, p_new NUMBER, p_zitadel NUMBER) IS
    BEGIN
        tt.ticket_interface.change_emergency(p_ticket, p_flag, 952202, p_new, p_zitadel);
        rec_ux(p_step, p_ticket);
    EXCEPTION WHEN OTHERS THEN log_err(p_step, SQLCODE, SQLERRM);
    END;
BEGIN
    deferral('01 deferral_date on deferred ticket',   952210, TIMESTAMP '2026-01-20 10:00:00', 'moved the deferral');
    deferral('02 deferral_date on open ticket',       952211, TIMESTAMP '2026-01-20 10:00:00', 'should only warn');
    deferral('03 deferral_date nonexistent ticket',   952999999, TIMESTAMP '2026-01-20 10:00:00', 'x');
    ux('04 ux incident not initial',                  952211, FALSE);
    ux('05 ux incident initial',                      952211, TRUE);
    ux('06 ux change',                                952212, FALSE);
    ux('07 ux maintenance window after start',        952213, FALSE);
    ux('08 ux maintenance no window',                 952214, FALSE);
    ux('09 ux third party incident',                  952215, FALSE);
    ux('10 ux non-mcc',                               952216, FALSE);
    ux('11 ux waiting status',                        952217, FALSE);
    ux('12 ux problem',                               952218, FALSE);
    ux('13 ux purchase order',                        952219, FALSE);
    ux('14 ux maintenance window before start',       952221, FALSE);
    ux('15 ux nonexistent ticket',                    952999999, FALSE);
    emergency('16 emergency 1 not new',               952211, 1, 0, NULL);
    emergency('17 emergency 0 not new',               952211, 0, 0, NULL);
    emergency('18 emergency 1 new ticket',            952211, 1, 1, NULL);
    emergency('19 emergency 1 with zitadel',          952212, 1, 0, 952777);
    emergency('20 emergency nonexistent ticket',      952999999, 1, 0, NULL);
END;
/
