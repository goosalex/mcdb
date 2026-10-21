-- tt__osag_notify__event_notify / setup.sql -- dialect-neutral fixtures (9581xx).
-- Reference rows reused from the master data present on both sides: tt.ticket_type 1,
-- tt.status 2, tt.event_type 10001 (connection down, source 1 automatic, group 1) and 50008
-- (question), tt.event_type_message 1/2/19/20, mss.operating_system 2, mss.service_type 6,
-- mss.service_level 1, mss.local_contact_type 1 (on-site intervention) / 2 (DNIDS alert),
-- tt.event_notification_type 1 (SMS) / 2 (email). mss.city is empty in both containers; the
-- address rows point at a nonexistent city (every FK is DEFERRABLE, the run is rolled back).
-- Event dates are fixed literals so the composed message text does not depend on the clock.
INSERT INTO stop.company (id, name, short) VALUES (6, 'Diff OSAG placeholder', 'dfosag');
INSERT INTO stop.company (id, name, short) VALUES (958101, 'Diff Notify Ev Co', 'dfnev1');
INSERT INTO stop.contact (id, lastname, firstname, short, company_id, mobile, email) VALUES (958102, 'Requester', 'Ev', 'dfevrq', 958101, NULL, NULL);
INSERT INTO stop.contact (id, lastname, firstname, short, company_id, mobile, email) VALUES (958103, 'Onsite', 'Sms', 'dfevsm', 958101, '+41790001003', NULL);
INSERT INTO stop.contact (id, lastname, firstname, short, company_id, mobile, email) VALUES (958104, 'Onsite', 'Mail', 'dfevml', 958101, NULL, 'onsite.mail@diff.invalid');
INSERT INTO mss.address (id, company_id, city_id, address_lines) VALUES (958105, 958101, 958999, 'diff sms address');
INSERT INTO mss.address (id, company_id, city_id, address_lines) VALUES (958108, 958101, 958999, 'diff mail address');
INSERT INTO mss.host (id, name, operating_system_id, service_company_id, author, address_id) VALUES (958106, 'diff-ev-host-sms', 2, 958101, 'diff', 958105);
INSERT INTO mss.host (id, name, operating_system_id, service_company_id, author, address_id) VALUES (958107, 'diff-ev-host-mail', 2, 958101, 'diff', 958108);
INSERT INTO mss.host (id, name, operating_system_id, service_company_id, author, address_id) VALUES (958109, 'diff-ev-host-suppressed', 2, 958101, 'diff', 958105);
INSERT INTO mss.host (id, name, operating_system_id, service_company_id, author, address_id) VALUES (958110, 'diff-ev-host-capped', 2, 958101, 'diff', 958105);
-- on-site intervention contacts: SMS at the sms address, email at the mail address; a
-- DNIDS-alert contact (type 2) at the sms address must never be notified
INSERT INTO mss.local_contact (id, priority, contact_id, local_contact_type_id, address_id) VALUES (958111, 1, 958103, 1, 958105);
INSERT INTO mss.local_contact (id, priority, contact_id, local_contact_type_id, address_id) VALUES (958112, 1, 958104, 1, 958108);
INSERT INTO mss.local_contact (id, priority, contact_id, local_contact_type_id, address_id) VALUES (958113, 2, 958104, 2, 958105);
INSERT INTO mss.local_contact_notification (id, local_contact_id, event_notification_type_id) VALUES (958114, 958111, 1);
INSERT INTO mss.local_contact_notification (id, local_contact_id, event_notification_type_id) VALUES (958115, 958112, 2);
INSERT INTO mss.local_contact_notification (id, local_contact_id, event_notification_type_id) VALUES (958116, 958113, 2);
INSERT INTO mss.service (id, service_type_id, company_id, service_level_id, name) VALUES (958117, 6, 958101, 1, 'diff-ev-svc');
-- tickets: the service comes from tt.ticket.mss_service_id (no mss.host2service rows)
INSERT INTO tt.ticket (id, type_id, status_id, company_id, contact_id, host_id, mss_service_id, subject, last_status_change_date)
    VALUES (958120, 1, 2, 958101, 958102, 958106, 958117, 'dfe ticket sms', CURRENT_TIMESTAMP - INTERVAL '1' HOUR);
INSERT INTO tt.ticket (id, type_id, status_id, company_id, contact_id, host_id, mss_service_id, subject, last_status_change_date)
    VALUES (958121, 1, 2, 958101, 958102, 958107, 958117, 'dfe ticket mail', CURRENT_TIMESTAMP - INTERVAL '1' HOUR);
INSERT INTO tt.ticket (id, type_id, status_id, company_id, contact_id, host_id, mss_service_id, subject, last_status_change_date)
    VALUES (958122, 1, 2, 958101, 958102, 958106, NULL, 'dfe ticket noservice', CURRENT_TIMESTAMP - INTERVAL '1' HOUR);
INSERT INTO tt.ticket (id, type_id, status_id, company_id, contact_id, host_id, mss_service_id, subject, last_status_change_date)
    VALUES (958123, 1, 2, 958101, 958102, 958109, 958117, 'dfe ticket suppressed', CURRENT_TIMESTAMP - INTERVAL '1' HOUR);
INSERT INTO tt.ticket (id, type_id, status_id, company_id, contact_id, host_id, mss_service_id, subject, last_status_change_date, event_notify_count, event_notify_count_osag)
    VALUES (958124, 1, 2, 958101, 958102, 958110, 958117, 'dfe ticket capped', CURRENT_TIMESTAMP - INTERVAL '1' HOUR, 5, 5);
INSERT INTO tt.ticket (id, type_id, status_id, company_id, contact_id, host_id, mss_service_id, subject, last_status_change_date, event_notify_count)
    VALUES (958125, 1, 2, 958101, 958102, 958106, 958117, 'dfe ticket fourth', CURRENT_TIMESTAMP - INTERVAL '1' HOUR, 4);
-- the events to notify about
INSERT INTO tt.event (id, type_id, ticket_id, host_id, eventdate, details_public) VALUES (958130, 10001, 958120, 958106, TIMESTAMP '2026-10-20 10:30:00', 'dfe link down sms');
INSERT INTO tt.event (id, type_id, ticket_id, host_id, eventdate, details_public) VALUES (958131, 10001, 958121, 958107, TIMESTAMP '2026-10-20 10:31:00', 'dfe link down mail');
INSERT INTO tt.event (id, type_id, ticket_id, host_id, eventdate, details_public) VALUES (958132, 10001, 958122, 958106, TIMESTAMP '2026-10-20 10:32:00', 'dfe link down noservice');
INSERT INTO tt.event (id, type_id, ticket_id, host_id, eventdate, details_public) VALUES (958133, 10001, 958123, 958109, TIMESTAMP '2026-10-20 10:33:00', 'dfe link down suppressed');
INSERT INTO tt.event (id, type_id, ticket_id, host_id, eventdate, details_public) VALUES (958134, 50008, 958123, 958109, TIMESTAMP '2026-10-20 10:34:00', 'dfe question during window');
INSERT INTO tt.event (id, type_id, ticket_id, host_id, eventdate, details_public) VALUES (958135, 10001, 958124, 958110, TIMESTAMP '2026-10-20 10:35:00', 'dfe link down capped');
INSERT INTO tt.event (id, type_id, ticket_id, host_id, eventdate, details_public) VALUES (958136, 10001, 958125, 958106, TIMESTAMP '2026-10-20 10:36:00', 'dfe link down fourth');
-- service windows: active + disable_notification on host 958109 (suppresses); active
-- without the flag on host 958106 (does not); expired with the flag on host 958110 (does not)
INSERT INTO tt.service_window (id, ticket_id, start_date, end_date, company_id, title) VALUES (958140, 958123, CURRENT_TIMESTAMP - INTERVAL '1' HOUR, CURRENT_TIMESTAMP + INTERVAL '1' HOUR, 958101, 'dfe active suppressing');
INSERT INTO tt.host2service_window (host_id, service_window_id) VALUES (958109, 958140);
INSERT INTO tt.maintenance_window (id, service_window_id, disable_events, collect_events, disable_guma_escalation, disable_conn_escalation, disable_notification) VALUES (958141, 958140, 0, 0, 0, 0, 1);
INSERT INTO tt.service_window (id, ticket_id, start_date, end_date, company_id, title) VALUES (958142, 958120, CURRENT_TIMESTAMP - INTERVAL '1' HOUR, CURRENT_TIMESTAMP + INTERVAL '1' HOUR, 958101, 'dfe active not suppressing');
INSERT INTO tt.host2service_window (host_id, service_window_id) VALUES (958106, 958142);
INSERT INTO tt.maintenance_window (id, service_window_id, disable_events, collect_events, disable_guma_escalation, disable_conn_escalation, disable_notification) VALUES (958143, 958142, 0, 0, 0, 0, 0);
INSERT INTO tt.service_window (id, ticket_id, start_date, end_date, company_id, title) VALUES (958144, 958124, CURRENT_TIMESTAMP - INTERVAL '3' HOUR, CURRENT_TIMESTAMP - INTERVAL '2' HOUR, 958101, 'dfe expired suppressing');
INSERT INTO tt.host2service_window (host_id, service_window_id) VALUES (958110, 958144);
INSERT INTO tt.maintenance_window (id, service_window_id, disable_events, collect_events, disable_guma_escalation, disable_conn_escalation, disable_notification) VALUES (958145, 958144, 0, 0, 0, 0, 1);
