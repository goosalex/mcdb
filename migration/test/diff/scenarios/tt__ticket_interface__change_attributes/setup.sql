-- tt__ticket_interface__change_attributes / setup.sql -- dialect-neutral fixtures (952000-952099).
-- Reference rows reused from the master data present on both sides: tt.status 2,
-- tt.ticket_type 1, tt.label 1-4 (Dispatch, Routine, Process, SOC), mss.operating_system 2,
-- mss.service_type 6, mss.service_level 1. The host carries exactly one mss.host2service
-- row (STRICT lookups in osag_notify.event_notify, reached through add_status_change_event).
-- CURRENT_TIMESTAMP - INTERVAL '1' HOUR is valid in both dialects.
INSERT INTO stop.company (id, name, short) VALUES (952001, 'Diff Attr Co', 'dfattr1');
INSERT INTO stop.contact (id, lastname, firstname, short, company_id) VALUES (952002, 'Actor', 'Diff', 'dfatac1', 952001);
INSERT INTO mss.host (id, name, operating_system_id, service_company_id, author) VALUES (952005, 'diff-attr-host', 2, 952001, 'diff');
INSERT INTO mss.service (id, service_type_id, company_id, service_level_id, name) VALUES (952006, 6, 952001, 1, 'diff-attr-svc');
INSERT INTO mss.host2service (host_id, service_id) VALUES (952005, 952006);
-- ticket A: no label, no references, no summaries
INSERT INTO tt.ticket (id, type_id, status_id, company_id, contact_id, host_id, subject, last_status_change_date)
    VALUES (952010, 1, 2, 952001, 952002, 952005, 'attr ticket A', CURRENT_TIMESTAMP - INTERVAL '1' HOUR);
-- ticket B: label Routine (2), both summaries set, 5 summary-relevant events counted
INSERT INTO tt.ticket (id, type_id, status_id, company_id, contact_id, host_id, subject, label_id,
                       summary_private, summary_public, summary_relevant_events_count, last_status_change_date)
    VALUES (952011, 1, 2, 952001, 952002, 952005, 'attr ticket B', 2,
            'old private', 'old public', 5, CURRENT_TIMESTAMP - INTERVAL '1' HOUR);
