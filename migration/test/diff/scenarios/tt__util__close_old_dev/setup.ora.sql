-- tt__util__close_old_dev / setup.ora.sql -- the Oracle fixtures: setup.sql plus a COMMIT,
-- so that the routine's AUTONOMOUS_TRANSACTION could see the tickets on a dev instance
-- (it cannot see the caller's uncommitted rows). cleanup.ora.sql removes them afterwards.
INSERT INTO tt.ticket (id, type_id, status_id, handled_by_mcc, subject, open_date, last_status_change_date)
    VALUES (958400, 1, 3, 1, 'dfc old mcc hot ticket', CURRENT_TIMESTAMP - INTERVAL '40' DAY, CURRENT_TIMESTAMP - INTERVAL '40' DAY);
INSERT INTO tt.ticket (id, type_id, status_id, handled_by_mcc, subject, open_date, last_status_change_date)
    VALUES (958401, 1, 3, 0, 'dfc old non-mcc hot ticket', CURRENT_TIMESTAMP - INTERVAL '40' DAY, CURRENT_TIMESTAMP - INTERVAL '40' DAY);
INSERT INTO tt.ticket (id, type_id, status_id, handled_by_mcc, subject, open_date, last_status_change_date)
    VALUES (958402, 1, 102, 1, 'dfc old mcc closed ticket', CURRENT_TIMESTAMP - INTERVAL '40' DAY, CURRENT_TIMESTAMP - INTERVAL '40' DAY);
COMMIT;
