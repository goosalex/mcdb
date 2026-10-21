-- tt__osag_notify__send_test / call.ora.sql
DECLARE
    -- SQLCODE/SQLERRM may not appear inside a SQL statement (ORA-00984); pass them as arguments.
    PROCEDURE log_err(p_step VARCHAR2, p_code NUMBER, p_msg VARCHAR2) IS
    BEGIN
        INSERT INTO diff_probe (step, code, msg) VALUES (p_step, TO_CHAR(p_code), SUBSTR(p_msg, 1, 4000));
    END;

    PROCEDURE step_test(p_step VARCHAR2, p_dest VARCHAR2, p_type NUMBER, p_event_type NUMBER, p_last VARCHAR2, p_first VARCHAR2) IS
    BEGIN
        tt.osag_notify.send_test_notification(p_dest, p_type, 958200, 'dfs test subject', 'diff-send-host', p_event_type,
                                              TIMESTAMP '2026-10-20 10:30:00 +00:00', p_last, p_first);
        INSERT INTO diff_probe (step, s) VALUES (p_step, 'ok');
    EXCEPTION WHEN OTHERS THEN
        log_err(p_step, SQLCODE, SQLERRM);
    END;
BEGIN
    -- S-NOTIFY-028 via send_sms: the SMTP failure is swallowed inside OSAG_MSG.send_sms
    step_test('01 test sms', '+41790002001', 1, 101002, 'Tester', 'Diff');
    -- S-NOTIFY-026 via send_mail: the SMTP failure is re-raised, no handler here
    step_test('02 test email named', 'tester@diff.invalid', 2, 101002, 'Tester', 'Diff');
    step_test('03 test email anonymous', 'tester@diff.invalid', 2, 101002, NULL, NULL);
    -- type 3 (fax): neither branch, returns after the event-type lookup
    step_test('04 test fax type no-op', 'tester@diff.invalid', 3, 101002, NULL, NULL);
    -- S-NOTIFY-018: site 10 NO_DATA_FOUND propagates
    step_test('05 nonexistent event type', '+41790002001', 1, 958999999, NULL, NULL);
END;
/
