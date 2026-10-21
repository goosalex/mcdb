-- tt__event_interface__history_move / setup.sql -- dialect-neutral fixtures (957300-957499).
-- Reference rows reused from the master data present on both sides: tt.status 2, tt.ticket_type 1,
-- tt.event_type 101001 (new ticket, source 10) and 50002 (comment, source 5), mss.operating_system 2,
-- mss.service_type 6, mss.service_level 1.
INSERT INTO stop.company (id, name, short) VALUES (957301, 'Diff Hist Co', 'dfhist1');
INSERT INTO stop.contact (id, lastname, firstname, short, company_id) VALUES (957302, 'Historian', 'Diff', 'dfhstc1', 957301);
INSERT INTO mss.host (id, name, operating_system_id, service_company_id, author, active) VALUES (957305, 'diff-hist-host', 2, 957301, 'diff', 1);
INSERT INTO mss.service (id, service_type_id, company_id, service_level_id, name) VALUES (957307, 6, 957301, 1, 'diff-hist-svc');
INSERT INTO mss.host2service (host_id, service_id) VALUES (957305, 957307);
INSERT INTO tt.ticket (id, type_id, status_id, company_id, host_id, mss_service_id, subject, last_status_change_date) VALUES (957311, 1, 2, 957301, 957305, 957307, 'move source', CURRENT_TIMESTAMP - INTERVAL '1' HOUR);
INSERT INTO tt.ticket (id, type_id, status_id, company_id, host_id, mss_service_id, subject, last_status_change_date) VALUES (957312, 1, 2, 957301, 957305, 957307, 'move target and history', CURRENT_TIMESTAMP - INTERVAL '1' HOUR);
INSERT INTO tt.ticket (id, type_id, status_id, company_id, host_id, mss_service_id, subject, last_status_change_date) VALUES (957313, 1, 2, 957301, 957305, 957307, 'decoy', CURRENT_TIMESTAMP - INTERVAL '1' HOUR);
INSERT INTO tt.event (id, type_id, ticket_id, host_id, company_id, details_public) VALUES (957321, 101001, 957311, 957305, 957301, 'event to move');
INSERT INTO tt.event (id, type_id, ticket_id, host_id, company_id, details_public) VALUES (957322, 101001, 957311, 957305, 957301, 'sibling that must stay');
INSERT INTO tt.event (id, type_id, ticket_id, host_id, company_id, details_public) VALUES (957323, 101001, 957313, 957305, 957301, 'decoy event on another ticket');
INSERT INTO tt.event (id, type_id, ticket_id, host_id, company_id, details_public, demoted) VALUES (957324, 50002, 957312, 957305, 957301, 'demote me', 0);
