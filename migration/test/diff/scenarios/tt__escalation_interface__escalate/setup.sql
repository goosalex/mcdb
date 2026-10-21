-- tt__escalation_interface__escalate / setup.sql -- dialect-neutral fixtures (956700-956899).
-- Reference rows reused from the master data present on both sides: tt.status 2, tt.ticket_type 1,
-- tt.event_type 10001 (connection down, source 1) and 60001, tt.escalation_status 0/10/11/20,
-- mss.operating_system 2, mss.service_type 6, mss.service_level 1. FKs are DEFERRABLE on both
-- sides (ticket 956717's host_id has no mss.host row on purpose, S-ESC-005 second half).
INSERT INTO stop.company (id, name, short) VALUES (956701, 'Diff Esc Co', 'dfesc1');
INSERT INTO mss.host (id, name, operating_system_id, service_company_id, author, active) VALUES (956705, 'diff-esc-active', 2, 956701, 'diff', 1);
INSERT INTO mss.host (id, name, operating_system_id, service_company_id, author, active) VALUES (956706, 'diff-esc-inactive', 2, 956701, 'diff', 0);
INSERT INTO mss.service (id, service_type_id, company_id, service_level_id, name) VALUES (956707, 6, 956701, 1, 'diff-esc-svc');
INSERT INTO mss.host2service (host_id, service_id) VALUES (956705, 956707);
INSERT INTO mss.host2service (host_id, service_id) VALUES (956706, 956707);

-- escalate_os tickets (one 10001 event each)
INSERT INTO tt.ticket (id, type_id, status_id, company_id, host_id, escalation_status_id, subject, last_status_change_date) VALUES (956711, 1, 2, 956701, 956705, 0,  'os active host status 0', CURRENT_TIMESTAMP - INTERVAL '1' HOUR);
INSERT INTO tt.ticket (id, type_id, status_id, company_id, host_id, escalation_status_id, subject, last_status_change_date) VALUES (956712, 1, 2, 956701, 956705, 10, 'os already status 10', CURRENT_TIMESTAMP - INTERVAL '1' HOUR);
INSERT INTO tt.ticket (id, type_id, status_id, company_id, host_id, escalation_status_id, subject, last_status_change_date) VALUES (956713, 1, 2, 956701, 956705, 11, 'os pikett failed status 11', CURRENT_TIMESTAMP - INTERVAL '1' HOUR);
INSERT INTO tt.ticket (id, type_id, status_id, company_id, host_id, escalation_status_id, subject, last_status_change_date) VALUES (956714, 1, 2, 956701, NULL,   0,  'os no host', CURRENT_TIMESTAMP - INTERVAL '1' HOUR);
INSERT INTO tt.ticket (id, type_id, status_id, company_id, host_id, escalation_status_id, subject, last_status_change_date) VALUES (956715, 1, 2, 956701, 956706, 0,  'os inactive host', CURRENT_TIMESTAMP - INTERVAL '1' HOUR);
INSERT INTO tt.ticket (id, type_id, status_id, company_id, host_id, escalation_status_id, subject, last_status_change_date) VALUES (956716, 1, 2, 956701, 956705, 20, 'os customer escalation status 20', CURRENT_TIMESTAMP - INTERVAL '1' HOUR);
INSERT INTO tt.ticket (id, type_id, status_id, company_id, host_id, escalation_status_id, subject, last_status_change_date) VALUES (956717, 1, 2, 956701, 956799, 0,  'os dangling host id', CURRENT_TIMESTAMP - INTERVAL '1' HOUR);
INSERT INTO tt.event (id, type_id, ticket_id, host_id, details_public) VALUES (956811, 10001, 956711, 956705, 'fixture event');
INSERT INTO tt.event (id, type_id, ticket_id, host_id, details_public) VALUES (956812, 10001, 956712, 956705, 'fixture event');
INSERT INTO tt.event (id, type_id, ticket_id, host_id, details_public) VALUES (956813, 10001, 956713, 956705, 'fixture event');
INSERT INTO tt.event (id, type_id, ticket_id, host_id, details_public) VALUES (956814, 10001, 956714, NULL,   'fixture event');
INSERT INTO tt.event (id, type_id, ticket_id, host_id, details_public) VALUES (956815, 10001, 956715, 956706, 'fixture event');
INSERT INTO tt.event (id, type_id, ticket_id, host_id, details_public) VALUES (956816, 10001, 956716, 956705, 'fixture event');
INSERT INTO tt.event (id, type_id, ticket_id, host_id, details_public) VALUES (956817, 10001, 956717, NULL,   'fixture event');

-- escalate_customer tickets
INSERT INTO tt.ticket (id, type_id, status_id, company_id, host_id, escalation_status_id, subject, last_status_change_date) VALUES (956721, 1, 2, 956701, 956705, 0,  'cust active host status 0', CURRENT_TIMESTAMP - INTERVAL '1' HOUR);
INSERT INTO tt.ticket (id, type_id, status_id, company_id, host_id, escalation_status_id, subject, last_status_change_date) VALUES (956722, 1, 2, 956701, 956705, 20, 'cust status 20 blocks', CURRENT_TIMESTAMP - INTERVAL '1' HOUR);
INSERT INTO tt.ticket (id, type_id, status_id, company_id, host_id, escalation_status_id, subject, last_status_change_date) VALUES (956723, 1, 2, 956701, 956705, 10, 'cust status 10 blocks', CURRENT_TIMESTAMP - INTERVAL '1' HOUR);
INSERT INTO tt.ticket (id, type_id, status_id, company_id, host_id, escalation_status_id, subject, last_status_change_date) VALUES (956724, 1, 2, 956701, 956706, 0,  'cust inactive host', CURRENT_TIMESTAMP - INTERVAL '1' HOUR);
INSERT INTO tt.ticket (id, type_id, status_id, company_id, host_id, escalation_status_id, subject, last_status_change_date) VALUES (956725, 1, 2, 956701, NULL,   0,  'cust no host', CURRENT_TIMESTAMP - INTERVAL '1' HOUR);
INSERT INTO tt.event (id, type_id, ticket_id, host_id, details_public) VALUES (956821, 10001, 956721, 956705, 'fixture event');
INSERT INTO tt.event (id, type_id, ticket_id, host_id, details_public) VALUES (956822, 10001, 956722, 956705, 'fixture event');
INSERT INTO tt.event (id, type_id, ticket_id, host_id, details_public) VALUES (956823, 10001, 956723, 956705, 'fixture event');
INSERT INTO tt.event (id, type_id, ticket_id, host_id, details_public) VALUES (956824, 10001, 956724, 956706, 'fixture event');
INSERT INTO tt.event (id, type_id, ticket_id, host_id, details_public) VALUES (956825, 10001, 956725, NULL,   'fixture event');

-- clear_customer_escalation tickets (a fixed last_escalation_date so "no other column changed" is checkable)
INSERT INTO tt.ticket (id, type_id, status_id, company_id, escalation_status_id, last_escalation_date, subject, last_status_change_date) VALUES (956731, 1, 2, 956701, 20, TIMESTAMP '2020-01-01 00:00:00', 'clear status 20', CURRENT_TIMESTAMP - INTERVAL '1' HOUR);
INSERT INTO tt.ticket (id, type_id, status_id, company_id, escalation_status_id, last_escalation_date, subject, last_status_change_date) VALUES (956732, 1, 2, 956701, 10, TIMESTAMP '2020-01-01 00:00:00', 'clear status 10 untouched', CURRENT_TIMESTAMP - INTERVAL '1' HOUR);
