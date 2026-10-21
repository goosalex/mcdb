-- tt__util__close_old_dev / setup.sql -- PostgreSQL fixtures (9584xx); setup.ora.sql is the
-- same plus a COMMIT (see meta.env). No company/contact/host: the cursor of
-- close_old_dev_tickets reads tt.ticket only, and a committed fixture must be FK-complete.
-- 958400: eligible (handled_by_mcc = 1, hot, opened 40 days ago)
INSERT INTO tt.ticket (id, type_id, status_id, handled_by_mcc, subject, open_date, last_status_change_date)
    VALUES (958400, 1, 3, 1, 'dfc old mcc hot ticket', CURRENT_TIMESTAMP - INTERVAL '40' DAY, CURRENT_TIMESTAMP - INTERVAL '40' DAY);
-- 958401: not handled by MCC
INSERT INTO tt.ticket (id, type_id, status_id, handled_by_mcc, subject, open_date, last_status_change_date)
    VALUES (958401, 1, 3, 0, 'dfc old non-mcc hot ticket', CURRENT_TIMESTAMP - INTERVAL '40' DAY, CURRENT_TIMESTAMP - INTERVAL '40' DAY);
-- 958402: closed (102) is excluded by the cursor (open, 2, is excluded too, but Oracle's deferred
-- check C_TICKET_2 'STATUS_ID != 2 OR WORKER_ID IS NOT NULL' would reject an open fixture
-- without a worker at the COMMIT of setup.ora.sql)
INSERT INTO tt.ticket (id, type_id, status_id, handled_by_mcc, subject, open_date, last_status_change_date)
    VALUES (958402, 1, 102, 1, 'dfc old mcc closed ticket', CURRENT_TIMESTAMP - INTERVAL '40' DAY, CURRENT_TIMESTAMP - INTERVAL '40' DAY);
