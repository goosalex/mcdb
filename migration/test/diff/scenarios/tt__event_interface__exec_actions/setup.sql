-- tt__event_interface__exec_actions / setup.sql -- dialect-neutral fixtures (956000-956699).
-- Reference rows reused from the master data present on both sides: tt.status 2/102,
-- tt.ticket_type 1/4, tt.event_action 1 (escalate_os) and 2 (DBPROP key 139, no procedure name),
-- mss.key 139, mss.operating_system 2, mss.service_type 6, mss.service_level 1,
-- mss.service_component 27, tt.escalation_status 0/20. tt.event_type_action is EMPTY in both
-- databases (checked 2026-10-21), so every mapping below is scenario-owned.
-- Oracle NOT NULL columns satisfied: STOP.COMPANY(id,name,short), MSS.HOST(id,name,
-- operating_system_id,service_company_id,author), MSS.SERVICE(id,service_type_id,company_id,
-- service_level_id,name), TT.EVENT_TYPE(id,name,source,sms_message_template_id,
-- email_message_template_id), TT.SERVICE_WINDOW(id,ticket_id,start_date,end_date,company_id),
-- TT.MAINTENANCE_WINDOW(id,service_window_id). FKs are DEFERRABLE on both sides.
INSERT INTO stop.company (id, name, short) VALUES (956001, 'Diff Exec Co', 'dfexec1');
INSERT INTO mss.host (id, name, operating_system_id, service_company_id, author, active) VALUES (956005, 'diff-exec-host', 2, 956001, 'diff', 1);
INSERT INTO mss.host (id, name, operating_system_id, service_company_id, author, active) VALUES (956006, 'diff-exec-inactive', 2, 956001, 'diff', 0);
INSERT INTO mss.host (id, name, operating_system_id, service_company_id, author, active) VALUES (956008, 'diff-exec-dbprop-host', 2, 956001, 'diff', 1);
INSERT INTO mss.service (id, service_type_id, company_id, service_level_id, name) VALUES (956007, 6, 956001, 1, 'diff-exec-svc');
INSERT INTO mss.host2service (host_id, service_id) VALUES (956005, 956007);
INSERT INTO mss.host2service (host_id, service_id) VALUES (956006, 956007);
INSERT INTO mss.host2service (host_id, service_id) VALUES (956008, 956007);

-- pilot event types (source 1 = automatic) and their action mappings
INSERT INTO tt.event_type (id, name, source, sms_message_template_id, email_message_template_id) VALUES (956301, 'diff exec escalate_os type', 1, 1, 2);
INSERT INTO tt.event_type (id, name, source, sms_message_template_id, email_message_template_id) VALUES (956302, 'diff exec escalate_customer type', 1, 1, 2);
INSERT INTO tt.event_type (id, name, source, sms_message_template_id, email_message_template_id) VALUES (956303, 'diff exec nop type', 1, 1, 2);
INSERT INTO tt.event_type (id, name, source, sms_message_template_id, email_message_template_id) VALUES (956304, 'diff exec isp outage type', 1, 1, 2);
INSERT INTO tt.event_type (id, name, source, sms_message_template_id, email_message_template_id) VALUES (956305, 'diff exec off-allowlist type', 1, 1, 2);
INSERT INTO tt.event_type (id, name, source, sms_message_template_id, email_message_template_id) VALUES (956306, 'diff exec dbprop type', 1, 1, 2);
INSERT INTO tt.event_type (id, name, source, sms_message_template_id, email_message_template_id) VALUES (956307, 'diff exec unmapped type', 1, 1, 2);
INSERT INTO tt.event_type (id, name, source, sms_message_template_id, email_message_template_id) VALUES (956308, 'diff exec suppressed type', 1, 1, 2);
INSERT INTO tt.event_action (id, name, procedure_name) VALUES (956401, 'diff exec customer action', 'tt.escalation_interface.escalate_customer');
INSERT INTO tt.event_action (id, name, procedure_name) VALUES (956402, 'diff exec nop action', 'tt.escalation_interface.nop');
INSERT INTO tt.event_action (id, name, procedure_name) VALUES (956403, 'diff exec isp outage action', 'tt.escalation_interface.escalate_isp_outage_to_os');
INSERT INTO tt.event_action (id, name, procedure_name) VALUES (956404, 'diff exec off-allowlist action', 'tt.escalation_interface.clear_customer_escalation');
INSERT INTO tt.event_type_action (event_action_id, event_type_id) VALUES (1, 956301);
INSERT INTO tt.event_type_action (event_action_id, event_type_id) VALUES (956401, 956302);
INSERT INTO tt.event_type_action (event_action_id, event_type_id) VALUES (956402, 956303);
INSERT INTO tt.event_type_action (event_action_id, event_type_id) VALUES (956403, 956304);
INSERT INTO tt.event_type_action (event_action_id, event_type_id) VALUES (956404, 956305);
INSERT INTO tt.event_type_action (event_action_id, event_type_id) VALUES (2, 956306);
INSERT INTO tt.event_type_action (event_action_id, event_type_id) VALUES (2, 956308);

-- tickets (status 2 = open unless noted) and the events the dispatch is run for
INSERT INTO tt.ticket (id, type_id, status_id, company_id, host_id, escalation_status_id, subject, last_status_change_date) VALUES (956101, 1, 2, 956001, 956005, 0, 'exec escalate_os', CURRENT_TIMESTAMP - INTERVAL '1' HOUR);
INSERT INTO tt.ticket (id, type_id, status_id, company_id, host_id, escalation_status_id, subject, last_status_change_date) VALUES (956102, 1, 2, 956001, 956005, 0, 'exec escalate_customer', CURRENT_TIMESTAMP - INTERVAL '1' HOUR);
INSERT INTO tt.ticket (id, type_id, status_id, company_id, host_id, escalation_status_id, subject, last_status_change_date) VALUES (956103, 1, 2, 956001, 956005, 20, 'exec nop', CURRENT_TIMESTAMP - INTERVAL '1' HOUR);
INSERT INTO tt.ticket (id, type_id, status_id, company_id, host_id, escalation_status_id, subject, last_status_change_date) VALUES (956104, 4, 2, 956001, 956005, 0, 'exec isp outage original', CURRENT_TIMESTAMP - INTERVAL '1' HOUR);
INSERT INTO tt.ticket (id, type_id, status_id, company_id, host_id, escalation_status_id, subject, last_status_change_date) VALUES (956105, 1, 2, 956001, 956005, 20, 'exec off-allowlist', CURRENT_TIMESTAMP - INTERVAL '1' HOUR);
INSERT INTO tt.ticket (id, type_id, status_id, company_id, host_id, escalation_status_id, subject, last_status_change_date) VALUES (956106, 1, 2, 956001, 956008, 0, 'exec dbprop', CURRENT_TIMESTAMP - INTERVAL '1' HOUR);
INSERT INTO tt.ticket (id, type_id, status_id, company_id, host_id, escalation_status_id, subject, last_status_change_date) VALUES (956107, 1, 2, 956001, 956005, 0, 'exec unmapped', CURRENT_TIMESTAMP - INTERVAL '1' HOUR);
INSERT INTO tt.ticket (id, type_id, status_id, company_id, host_id, escalation_status_id, subject, last_status_change_date) VALUES (956108, 1, 2, 956001, 956006, 0, 'exec inactive host', CURRENT_TIMESTAMP - INTERVAL '1' HOUR);
INSERT INTO tt.ticket (id, type_id, status_id, company_id, host_id, escalation_status_id, subject, last_status_change_date) VALUES (956109, 1, 102, 956001, 956005, 0, 'exec closed ticket', CURRENT_TIMESTAMP - INTERVAL '1' HOUR);
INSERT INTO tt.ticket (id, type_id, status_id, company_id, host_id, escalation_status_id, subject, last_status_change_date) VALUES (956110, 1, 2, 956001, 956005, 0, 'exec suppressed', CURRENT_TIMESTAMP - INTERVAL '1' HOUR);
INSERT INTO tt.event (id, type_id, ticket_id, host_id, details_public) VALUES (956201, 956301, 956101, 956005, 'fixture event escalate_os');
INSERT INTO tt.event (id, type_id, ticket_id, host_id, details_public) VALUES (956202, 956302, 956102, 956005, 'fixture event escalate_customer');
INSERT INTO tt.event (id, type_id, ticket_id, host_id, details_public) VALUES (956203, 956303, 956103, 956005, 'fixture event nop');
INSERT INTO tt.event (id, type_id, ticket_id, host_id, company_id, eventdate, details_public) VALUES (956204, 956304, 956104, 956005, NULL, TIMESTAMP '2024-03-05 14:07:09', 'fixture event isp outage');
-- the off-allowlist event carries the SAME id as its ticket: clear_customer_escalation(:eventid)
-- then addresses ticket 956105 (escalation status 20) when an engine executes it
INSERT INTO tt.event (id, type_id, ticket_id, host_id, details_public) VALUES (956105, 956305, 956105, 956005, 'fixture event off-allowlist');
INSERT INTO tt.event (id, type_id, ticket_id, host_id, details_public) VALUES (956206, 956306, 956106, 956008, 'fixture event dbprop');
INSERT INTO tt.event (id, type_id, ticket_id, host_id, details_public) VALUES (956207, 956307, 956107, 956005, 'fixture event unmapped');
INSERT INTO tt.event (id, type_id, ticket_id, host_id, details_public) VALUES (956208, 956301, 956108, 956006, 'fixture event inactive host');
INSERT INTO tt.event (id, type_id, ticket_id, host_id, details_public) VALUES (956209, 956301, 956109, 956005, 'fixture event closed ticket');
INSERT INTO tt.event (id, type_id, ticket_id, host_id, details_public) VALUES (956210, 956308, 956110, 956005, 'fixture event suppressed');

-- an open service window on ticket 956110 for host 956005 with disable_conn_escalation set:
-- is_esc_supp_active(956005, action 2, 956308) is TRUE (S-EVENT-041)
INSERT INTO tt.service_window (id, ticket_id, start_date, end_date, company_id) VALUES (956501, 956110, CURRENT_TIMESTAMP - INTERVAL '1' HOUR, CURRENT_TIMESTAMP + INTERVAL '1' HOUR, 956001);
INSERT INTO tt.host2service_window (host_id, service_window_id) VALUES (956005, 956501);
INSERT INTO tt.maintenance_window (id, service_window_id, disable_conn_escalation) VALUES (956601, 956501, 1);
