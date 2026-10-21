-- tt__escalation_interface__closed_ticket / setup.sql -- dialect-neutral fixtures (956900-956949).
-- Reference rows: tt.status 102 (closed), tt.ticket_type 1, tt.event_type 10001, mss.operating_system 2,
-- mss.service_type 6, mss.service_level 1.
INSERT INTO stop.company (id, name, short) VALUES (956901, 'Diff Esc Closed Co', 'dfescc1');
INSERT INTO mss.host (id, name, operating_system_id, service_company_id, author, active) VALUES (956905, 'diff-esc-closed-host', 2, 956901, 'diff', 1);
INSERT INTO mss.service (id, service_type_id, company_id, service_level_id, name) VALUES (956907, 6, 956901, 1, 'diff-esc-closed-svc');
INSERT INTO mss.host2service (host_id, service_id) VALUES (956905, 956907);
INSERT INTO tt.ticket (id, type_id, status_id, company_id, host_id, escalation_status_id, subject, last_status_change_date) VALUES (956911, 1, 102, 956901, 956905, 0, 'closed ticket escalate_os', CURRENT_TIMESTAMP - INTERVAL '1' HOUR);
INSERT INTO tt.ticket (id, type_id, status_id, company_id, host_id, escalation_status_id, subject, last_status_change_date) VALUES (956912, 1, 102, 956901, 956905, 0, 'closed ticket escalate_customer', CURRENT_TIMESTAMP - INTERVAL '1' HOUR);
INSERT INTO tt.event (id, type_id, ticket_id, host_id, details_public) VALUES (956921, 10001, 956911, 956905, 'fixture event');
INSERT INTO tt.event (id, type_id, ticket_id, host_id, details_public) VALUES (956922, 10001, 956912, 956905, 'fixture event');
