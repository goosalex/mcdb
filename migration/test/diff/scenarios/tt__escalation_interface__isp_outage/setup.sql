-- tt__escalation_interface__isp_outage / setup.sql -- dialect-neutral fixtures (957500-957699).
-- Reference rows reused from the master data present on both sides: tt.status 2, tt.ticket_type 4,
-- tt.event_type 10003 (ISP outage) and 30005 (incident report), mss.service_component 27,
-- mss.operating_system 2, mss.service_type 6, mss.service_level 1. stop.company.short is nullable
-- on both sides (PostgreSQL's CHECK lower(short) = short passes for NULL); company 957503 has no
-- short name on purpose (S-ESC-018).
INSERT INTO stop.company (id, name, short) VALUES (957501, 'Diff ISP Service Co', 'dfisp1');
INSERT INTO stop.company (id, name, short) VALUES (957502, 'Diff ISP Ticket Co', 'dfisp2');
INSERT INTO stop.company (id, name, short) VALUES (957503, 'Diff ISP No Short Co', NULL);
INSERT INTO mss.host (id, name, operating_system_id, service_company_id, author, active) VALUES (957505, 'diff-isp-active', 2, 957501, 'diff', 1);
INSERT INTO mss.host (id, name, operating_system_id, service_company_id, author, active) VALUES (957506, 'diff-isp-noshort', 2, 957503, 'diff', 1);
INSERT INTO mss.service (id, service_type_id, company_id, service_level_id, name) VALUES (957507, 6, 957501, 1, 'diff-isp-svc');
INSERT INTO mss.service (id, service_type_id, company_id, service_level_id, name) VALUES (957508, 6, 957503, 1, 'diff-isp-svc-noshort');
INSERT INTO mss.host2service (host_id, service_id) VALUES (957505, 957507);
INSERT INTO mss.host2service (host_id, service_id) VALUES (957506, 957508);

-- original ISP outage tickets (type 4)
INSERT INTO tt.ticket (id, type_id, status_id, company_id, host_id, escalation_status_id, subject, last_status_change_date) VALUES (957511, 4, 2, 957502, 957505, 0, 'isp original ticket host and company', CURRENT_TIMESTAMP - INTERVAL '1' HOUR);
INSERT INTO tt.ticket (id, type_id, status_id, company_id, host_id, escalation_status_id, subject, last_status_change_date) VALUES (957512, 4, 2, NULL,   NULL,   0, 'isp original no company no host', CURRENT_TIMESTAMP - INTERVAL '1' HOUR);
INSERT INTO tt.ticket (id, type_id, status_id, company_id, host_id, escalation_status_id, subject, last_status_change_date) VALUES (957513, 4, 2, 957501, NULL,   0, 'isp original no host anywhere', CURRENT_TIMESTAMP - INTERVAL '1' HOUR);
-- the ISP outage events (fixed dates: the 30005 text carries them as YYYY-MM-DD HH24:MI:SS)
INSERT INTO tt.event (id, type_id, ticket_id, host_id, company_id, eventdate, details_public) VALUES (957521, 10003, 957511, NULL,   NULL,   TIMESTAMP '2024-03-05 14:07:09', 'falls back to ticket host and ticket company');
INSERT INTO tt.event (id, type_id, ticket_id, host_id, company_id, eventdate, details_public) VALUES (957522, 10003, 957512, 957506, NULL,   TIMESTAMP '2024-03-05 14:07:10', 'event host whose service company has no short');
INSERT INTO tt.event (id, type_id, ticket_id, host_id, company_id, eventdate, details_public) VALUES (957523, 10003, 957511, NULL,   957501, TIMESTAMP '2024-03-05 14:07:11', 'event company wins over ticket company');
INSERT INTO tt.event (id, type_id, ticket_id, host_id, company_id, eventdate, details_public) VALUES (957524, 10003, 957513, NULL,   NULL,   TIMESTAMP '2024-03-05 14:07:12', 'no host on event or ticket');
