-- tt__ticket_interface__deferral_ux / setup.sql -- dialect-neutral fixtures (952200-952299).
-- Master data reused from both sides: tt.status 2/11/60, tt.ticket_type 1/2/4/9/11/12,
-- mss.operating_system 2, mss.service_type 6, mss.service_level 1.
-- TIMESTAMP '...' literals are valid in both dialects; every ticket's UX start is fixed at
-- 2026-01-10 10:00 so the computed timeouts are deterministic wall-clock values.
INSERT INTO stop.company (id, name, short) VALUES (952201, 'Diff Defer Co', 'dfdefr1');
INSERT INTO stop.contact (id, lastname, firstname, short, company_id) VALUES (952202, 'Actor', 'Diff', 'dfdfac1', 952201);
INSERT INTO mss.host (id, name, operating_system_id, service_company_id, author) VALUES (952205, 'diff-defer-host', 2, 952201, 'diff');
INSERT INTO mss.service (id, service_type_id, company_id, service_level_id, name) VALUES (952206, 6, 952201, 1, 'diff-defer-svc');
INSERT INTO mss.host2service (host_id, service_id) VALUES (952205, 952206);
-- the deferred ticket (status 60) with a deferral date of 2026-01-12
INSERT INTO tt.ticket (id, type_id, status_id, handled_by_mcc, company_id, contact_id, host_id, subject, last_status_change_date,
                       ux_timeout_start, status_valid_until_date, last_deferral_date)
    VALUES (952210, 1, 60, 1, 952201, 952202, 952205, 'defer ticket deferred', CURRENT_TIMESTAMP - INTERVAL '1' HOUR,
            TIMESTAMP '2026-01-10 10:00:00', TIMESTAMP '2026-01-12 10:00:00', TIMESTAMP '2026-01-12 10:00:00');
-- one ticket per UX-timeout branch (type, status, handled_by_mcc)
INSERT INTO tt.ticket (id, type_id, status_id, handled_by_mcc, company_id, contact_id, host_id, subject, last_status_change_date, ux_timeout_start)
    VALUES (952211, 1, 2, 1, 952201, 952202, 952205, 'ux incident open', CURRENT_TIMESTAMP - INTERVAL '1' HOUR, TIMESTAMP '2026-01-10 10:00:00');
INSERT INTO tt.ticket (id, type_id, status_id, handled_by_mcc, company_id, contact_id, host_id, subject, last_status_change_date, ux_timeout_start)
    VALUES (952212, 2, 2, 1, 952201, 952202, 952205, 'ux change', CURRENT_TIMESTAMP - INTERVAL '1' HOUR, TIMESTAMP '2026-01-10 10:00:00');
INSERT INTO tt.ticket (id, type_id, status_id, handled_by_mcc, company_id, contact_id, host_id, subject, last_status_change_date, ux_timeout_start)
    VALUES (952213, 12, 2, 1, 952201, 952202, 952205, 'ux maintenance window after start', CURRENT_TIMESTAMP - INTERVAL '1' HOUR, TIMESTAMP '2026-01-10 10:00:00');
INSERT INTO tt.ticket (id, type_id, status_id, handled_by_mcc, company_id, contact_id, host_id, subject, last_status_change_date, ux_timeout_start)
    VALUES (952214, 12, 2, 1, 952201, 952202, 952205, 'ux maintenance no window', CURRENT_TIMESTAMP - INTERVAL '1' HOUR, TIMESTAMP '2026-01-10 10:00:00');
INSERT INTO tt.ticket (id, type_id, status_id, handled_by_mcc, company_id, contact_id, host_id, subject, last_status_change_date, ux_timeout_start)
    VALUES (952215, 4, 2, 1, 952201, 952202, 952205, 'ux third party incident', CURRENT_TIMESTAMP - INTERVAL '1' HOUR, TIMESTAMP '2026-01-10 10:00:00');
INSERT INTO tt.ticket (id, type_id, status_id, handled_by_mcc, company_id, contact_id, host_id, subject, last_status_change_date, ux_timeout_start)
    VALUES (952216, 1, 2, 0, 952201, 952202, 952205, 'ux non-mcc', CURRENT_TIMESTAMP - INTERVAL '1' HOUR, TIMESTAMP '2026-01-10 10:00:00');
INSERT INTO tt.ticket (id, type_id, status_id, handled_by_mcc, company_id, contact_id, host_id, subject, last_status_change_date, ux_timeout_start)
    VALUES (952217, 1, 11, 1, 952201, 952202, 952205, 'ux waiting', CURRENT_TIMESTAMP - INTERVAL '1' HOUR, TIMESTAMP '2026-01-10 10:00:00');
INSERT INTO tt.ticket (id, type_id, status_id, handled_by_mcc, company_id, contact_id, host_id, subject, last_status_change_date, ux_timeout_start)
    VALUES (952218, 11, 2, 1, 952201, 952202, 952205, 'ux problem', CURRENT_TIMESTAMP - INTERVAL '1' HOUR, TIMESTAMP '2026-01-10 10:00:00');
INSERT INTO tt.ticket (id, type_id, status_id, handled_by_mcc, company_id, contact_id, host_id, subject, last_status_change_date, ux_timeout_start)
    VALUES (952219, 9, 2, 1, 952201, 952202, 952205, 'ux purchase order', CURRENT_TIMESTAMP - INTERVAL '1' HOUR, TIMESTAMP '2026-01-10 10:00:00');
INSERT INTO tt.ticket (id, type_id, status_id, handled_by_mcc, company_id, contact_id, host_id, subject, last_status_change_date, ux_timeout_start)
    VALUES (952221, 12, 2, 1, 952201, 952202, 952205, 'ux maintenance window before start', CURRENT_TIMESTAMP - INTERVAL '1' HOUR, TIMESTAMP '2026-01-10 10:00:00');
-- service windows: one ending after the UX start (-> timeout = window end + 60 min), one ending before it (-> 480 min)
INSERT INTO tt.service_window (id, ticket_id, start_date, end_date, company_id)
    VALUES (952220, 952213, TIMESTAMP '2026-01-10 09:00:00', TIMESTAMP '2026-01-10 15:00:00', 952201);
INSERT INTO tt.service_window (id, ticket_id, start_date, end_date, company_id)
    VALUES (952222, 952221, TIMESTAMP '2026-01-10 08:00:00', TIMESTAMP '2026-01-10 09:30:00', 952201);
