-- tt__event_interface__newevent / setup.sql -- dialect-neutral fixtures (957000-957299).
-- Reference rows reused from the master data present on both sides: tt.status 2/102/110,
-- tt.ticket_type 1/2/4, tt.event_type 10001/10003/10004/30002/30016/50002/100004,
-- mss.operating_system 2, mss.service_type 6, mss.service_level 1. tt.event_type_action is empty
-- on both sides, so exec_event_type_actions dispatches nothing here. FKs are DEFERRABLE.
INSERT INTO stop.company (id, name, short) VALUES (957001, 'Diff New Co', 'dfnew1');
INSERT INTO stop.contact (id, lastname, firstname, short, company_id) VALUES (957002, 'Requester', 'Diff', 'dfnwrq1', 957001);
INSERT INTO stop.contact (id, lastname, firstname, short, company_id) VALUES (957003, 'Commenter', 'Diff', 'dfnwcm1', 957001);
INSERT INTO mss.host (id, name, operating_system_id, service_company_id, author, active) VALUES (957005, 'diff-new-host', 2, 957001, 'diff', 1);
INSERT INTO mss.host (id, name, operating_system_id, service_company_id, author, active) VALUES (957006, 'diff-new-inactive', 2, 957001, 'diff', 0);
INSERT INTO mss.host (id, name, operating_system_id, service_company_id, author, active) VALUES (957007, 'diff-new-noservice', 2, 957001, 'diff', 1);
INSERT INTO mss.host (id, name, operating_system_id, service_company_id, author, active) VALUES (957011, 'diff-new-append-host', 2, 957001, 'diff', 1);
INSERT INTO mss.service (id, service_type_id, company_id, service_level_id, name) VALUES (957009, 6, 957001, 1, 'diff-new-svc');
-- exactly ONE host2service row per host: Oracle's unique index MSS.IDX_H2S_HOST_UN refuses a
-- second one (ORA-00001, observed live 2026-10-21 -- S-EVENT-001 amended, schema-fix 29)
INSERT INTO mss.host2service (host_id, service_id) VALUES (957005, 957009);
INSERT INTO mss.host2service (host_id, service_id) VALUES (957006, 957009);
INSERT INTO mss.host2service (host_id, service_id) VALUES (957011, 957009);

-- the open automatic ticket on the append host: its first event is a connection down (10001)
INSERT INTO tt.ticket (id, type_id, status_id, company_id, host_id, mss_service_id, subject, last_status_change_date) VALUES (957101, 1, 2, 957001, 957011, 957009, 'append target', CURRENT_TIMESTAMP - INTERVAL '1' HOUR);
INSERT INTO tt.event (id, type_id, ticket_id, host_id, company_id, details_public) VALUES (957201, 10001, 957101, 957011, 957001, 'first down');

-- addevent_new tickets
INSERT INTO tt.ticket (id, type_id, status_id, company_id, host_id, mss_service_id, subject, fast_resolvable, recoverable_status_id, last_status_change_date) VALUES (957102, 1, 2, 957001, 957005, 957009, 'add comments', 1, 61, CURRENT_TIMESTAMP - INTERVAL '1' HOUR);
INSERT INTO tt.ticket (id, type_id, status_id, company_id, host_id, mss_service_id, subject, last_status_change_date) VALUES (957103, 1, 2, 957001, 957005, 957009, 'add email from customer', CURRENT_TIMESTAMP - INTERVAL '1' HOUR);
INSERT INTO tt.ticket (id, type_id, status_id, company_id, host_id, mss_service_id, subject, last_status_change_date) VALUES (957104, 2, 2, 957001, 957005, 957009, 'add connection down to change', CURRENT_TIMESTAMP - INTERVAL '1' HOUR);
INSERT INTO tt.ticket (id, type_id, status_id, company_id, host_id, mss_service_id, subject, last_status_change_date) VALUES (957105, 1, 102, 957001, 957005, 957009, 'add to closed', CURRENT_TIMESTAMP - INTERVAL '1' HOUR);
INSERT INTO tt.ticket (id, type_id, status_id, company_id, host_id, mss_service_id, subject, last_status_change_date) VALUES (957106, 1, 110, 957001, 957005, 957009, 'add to merged', CURRENT_TIMESTAMP - INTERVAL '1' HOUR);
INSERT INTO tt.ticket (id, type_id, status_id, company_id, host_id, mss_service_id, subject, last_status_change_date) VALUES (957107, 1, 2, 957001, 957005, 957009, 'merge target', CURRENT_TIMESTAMP - INTERVAL '1' HOUR);
INSERT INTO tt.ticket (id, type_id, status_id, company_id, host_id, mss_service_id, subject, last_status_change_date) VALUES (957108, 4, 2, 957001, 957005, 957009, 'add email to isp outage', CURRENT_TIMESTAMP - INTERVAL '1' HOUR);
INSERT INTO tt.event (id, type_id, ticket_id, host_id, company_id, details_public) VALUES (957202, 10001, 957102, 957005, 957001, 'fixture event');
INSERT INTO tt.event (id, type_id, ticket_id, host_id, company_id, details_public) VALUES (957203, 10001, 957103, 957005, 957001, 'fixture event');
INSERT INTO tt.event (id, type_id, ticket_id, host_id, company_id, details_public) VALUES (957204, 30002, 957104, 957005, 957001, 'fixture event');
INSERT INTO tt.event (id, type_id, ticket_id, host_id, company_id, details_public) VALUES (957205, 10001, 957105, 957005, 957001, 'fixture event');
-- the merge event of ticket 957106 names the merge target in details_private (S-EVENT-019)
INSERT INTO tt.event (id, type_id, ticket_id, host_id, company_id, details_public, details_private) VALUES (957206, 100004, 957106, 957005, 957001, 'ticket merged', '957107');
INSERT INTO tt.event (id, type_id, ticket_id, host_id, company_id, details_public) VALUES (957207, 10001, 957107, 957005, 957001, 'fixture event');
INSERT INTO tt.event (id, type_id, ticket_id, host_id, company_id, details_public) VALUES (957208, 10003, 957108, 957005, 957001, 'fixture event');
