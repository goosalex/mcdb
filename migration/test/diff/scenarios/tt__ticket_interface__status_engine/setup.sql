-- tt__ticket_interface__status_engine / setup.sql -- dialect-neutral fixtures (952300-952399).
-- Master data reused from both sides: tt.status 2/3/4/11/60/101, tt.ticket_type 1,
-- tt.event_type 101xxx/100008/60001/60102, mss.operating_system 2, mss.service_type 6,
-- mss.service_level 1. ux_timeout_start is fixed so "moved by the routine" is a clean flag.
INSERT INTO stop.company (id, name, short) VALUES (952301, 'Diff Status Co', 'dfstat1');
INSERT INTO stop.contact (id, lastname, firstname, short, company_id) VALUES (952302, 'Actor', 'Diff', 'dfstac1', 952301);
INSERT INTO mss.host (id, name, operating_system_id, service_company_id, author) VALUES (952305, 'diff-status-host', 2, 952301, 'diff');
INSERT INTO mss.service (id, service_type_id, company_id, service_level_id, name) VALUES (952306, 6, 952301, 1, 'diff-status-svc');
INSERT INTO mss.host2service (host_id, service_id) VALUES (952305, 952306);
-- three waiting tickets for expire_status (the third is non-MCC)
INSERT INTO tt.ticket (id, type_id, status_id, handled_by_mcc, company_id, contact_id, host_id, subject, last_status_change_date, ux_timeout_start, status_valid_until_date)
    VALUES (952310, 1, 11, 1, 952301, 952302, 952305, 'status expire 2.5h', CURRENT_TIMESTAMP - INTERVAL '1' HOUR, TIMESTAMP '2026-01-10 10:00:00', CURRENT_TIMESTAMP - INTERVAL '1' MINUTE);
INSERT INTO tt.ticket (id, type_id, status_id, handled_by_mcc, company_id, contact_id, host_id, subject, last_status_change_date, ux_timeout_start, status_valid_until_date)
    VALUES (952311, 1, 11, 1, 952301, 952302, 952305, 'status expire 2h', CURRENT_TIMESTAMP - INTERVAL '1' HOUR, TIMESTAMP '2026-01-10 10:00:00', CURRENT_TIMESTAMP - INTERVAL '1' MINUTE);
INSERT INTO tt.ticket (id, type_id, status_id, handled_by_mcc, company_id, contact_id, host_id, subject, last_status_change_date, ux_timeout_start, status_valid_until_date)
    VALUES (952312, 1, 11, 0, 952301, 952302, 952305, 'status expire non-mcc', CURRENT_TIMESTAMP - INTERVAL '1' HOUR, TIMESTAMP '2026-01-10 10:00:00', CURRENT_TIMESTAMP - INTERVAL '1' MINUTE);
-- open tickets for change_status_event_id_out
INSERT INTO tt.ticket (id, type_id, status_id, handled_by_mcc, company_id, contact_id, host_id, subject, last_status_change_date, ux_timeout_start)
    VALUES (952313, 1, 2, 1, 952301, 952302, 952305, 'status defer and back', CURRENT_TIMESTAMP - INTERVAL '1' HOUR, TIMESTAMP '2026-01-10 10:00:00');
INSERT INTO tt.ticket (id, type_id, status_id, handled_by_mcc, company_id, contact_id, host_id, subject, last_status_change_date, ux_timeout_start)
    VALUES (952314, 1, 2, 1, 952301, 952302, 952305, 'status resolve and reopen', CURRENT_TIMESTAMP - INTERVAL '1' HOUR, TIMESTAMP '2026-01-10 10:00:00');
-- a pending escalation to the customer (20)
INSERT INTO tt.ticket (id, type_id, status_id, handled_by_mcc, escalation_status_id, company_id, contact_id, host_id, subject, last_status_change_date, ux_timeout_start)
    VALUES (952315, 1, 2, 1, 20, 952301, 952302, 952305, 'status escalated ack', CURRENT_TIMESTAMP - INTERVAL '1' HOUR, TIMESTAMP '2026-01-10 10:00:00');
INSERT INTO tt.ticket (id, type_id, status_id, handled_by_mcc, company_id, contact_id, host_id, subject, last_status_change_date, ux_timeout_start)
    VALUES (952316, 1, 2, 1, 952301, 952302, 952305, 'status no-op and zitadel', CURRENT_TIMESTAMP - INTERVAL '1' HOUR, TIMESTAMP '2026-01-10 10:00:00');
