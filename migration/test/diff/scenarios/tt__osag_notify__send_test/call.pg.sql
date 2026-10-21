-- tt__osag_notify__send_test / call.pg.sql -- PostgreSQL twin of call.ora.sql.
-- Name from migration/mapping/name-map.csv: tt.osag_notify.send_test_notification ->
-- tt.osag_notify_send_test_notification (procedure -> CALL).
CREATE FUNCTION pg_temp.step_test(p_step text, p_dest text, p_type numeric, p_event_type numeric, p_last text, p_first text) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
    CALL tt.osag_notify_send_test_notification(p_dest, p_type, 958200, 'dfs test subject', 'diff-send-host', p_event_type,
                                               TIMESTAMPTZ '2026-10-20 10:30:00+00', p_last, p_first);
    INSERT INTO diff_probe (step, s) VALUES (p_step, 'ok');
EXCEPTION WHEN OTHERS THEN
    INSERT INTO diff_probe (step, code, msg) VALUES (p_step, SQLSTATE, left(SQLERRM, 4000));
END $f$;

DO $$
BEGIN
    PERFORM pg_temp.step_test('01 test sms', '+41790002001', 1, 101002, 'Tester', 'Diff');
    PERFORM pg_temp.step_test('02 test email named', 'tester@diff.invalid', 2, 101002, 'Tester', 'Diff');
    PERFORM pg_temp.step_test('03 test email anonymous', 'tester@diff.invalid', 2, 101002, NULL, NULL);
    PERFORM pg_temp.step_test('04 test fax type no-op', 'tester@diff.invalid', 3, 101002, NULL, NULL);
    PERFORM pg_temp.step_test('05 nonexistent event type', '+41790002001', 1, 958999999, NULL, NULL);
END $$;
