-- tt__ticket_interface__pure_functions / call.ora.sql
-- get_next_recent_ticket results go to n (NULL when no ticket matches, S-TICKET-033);
-- replace_id_placeholders results go to s (S-TICKET-037). NULL vs '' is collapsed by the
-- normaliser, so the NULL-text case is encoded as data ('<null>').
DECLARE
    -- SQLCODE/SQLERRM may not appear inside a SQL statement (ORA-00984); pass them as arguments.
    PROCEDURE log_err(p_step VARCHAR2, p_code NUMBER, p_msg VARCHAR2) IS
    BEGIN
        INSERT INTO diff_probe (step, code, msg) VALUES (p_step, TO_CHAR(p_code), SUBSTR(p_msg, 1, 4000));
    END;

    PROCEDURE next_ticket(p_step VARCHAR2, p_last NUMBER, p_host NUMBER, p_type NUMBER, p_age NUMBER) IS
        v_n NUMBER;
    BEGIN
        v_n := tt.ticket_interface.get_next_recent_ticket(p_last, p_host, p_type, p_age);
        INSERT INTO diff_probe (step, n, s) VALUES (p_step, v_n, CASE WHEN v_n IS NULL THEN 'null' ELSE 'found' END);
    EXCEPTION WHEN OTHERS THEN log_err(p_step, SQLCODE, SQLERRM);
    END;

    PROCEDURE placeholders(p_step VARCHAR2, p_text VARCHAR2, p_ticket NUMBER, p_event NUMBER) IS
        v_s VARCHAR2(4000);
    BEGIN
        v_s := tt.ticket_interface.replace_id_placeholders(p_text, p_ticket, p_event);
        INSERT INTO diff_probe (step, s) VALUES (p_step, CASE WHEN v_s IS NULL THEN '<null>' ELSE v_s END);
    EXCEPTION WHEN OTHERS THEN log_err(p_step, SQLCODE, SQLERRM);
    END;
BEGIN
    next_ticket('01 first on host',                 NULL,   954075, NULL, NULL);
    next_ticket('02 after G1 on host',              954080, 954075, NULL, NULL);
    next_ticket('03 after G1 resolve age 60s',      954080, 954075, NULL, 60);
    next_ticket('04 after G1 resolve age 3h',       954080, 954075, NULL, 10800);
    next_ticket('05 after G1 type 2',               954080, 954075, 2,    NULL);
    next_ticket('06 after G5 on host none left',    954084, 954075, NULL, NULL);
    next_ticket('07 host 0 means no host type 12',  NULL,   0,      12,   NULL);
    next_ticket('08 host 0 type 1 none',            NULL,   0,      1,    NULL);
    next_ticket('09 other host G7',                 NULL,   954076, NULL, NULL);
    next_ticket('10 host without tickets',          NULL,   954077, NULL, NULL);
    placeholders('11 both placeholders',  'Ticket ##ticket_id## has event ##event_id##', 954080, 42);
    placeholders('12 no placeholders',    'plain text', 954080, 42);
    placeholders('13 null text',          NULL, 954080, 42);
    placeholders('14 repeated',           '##ticket_id##/##ticket_id##/##event_id##', 7, 8);
    placeholders('15 null event id',      'e=##event_id## t=##ticket_id##', 954080, NULL);
    placeholders('16 null ticket id',     'e=##event_id## t=##ticket_id##', NULL, 42);
    placeholders('17 both ids null no placeholders', 'nothing to replace', NULL, NULL);
END;
/
