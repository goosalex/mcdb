-- tt__ticket_interface__relations / setup.sql -- dialect-neutral fixtures (954001-954099).
-- Satisfies the NOT NULL columns of BOTH engines (checked against dba_tab_columns and
-- information_schema on 2026-10-21): MC.MC_FILE needs uploader_id, display_name,
-- description, filename, mime_type, mc_file_type_id (the FK to mc.mc_file_type is
-- DEFERRABLE on both sides and mc.mc_file_type is empty in the PostgreSQL template, so a
-- nonexistent type id 954099 is used, like the pgTAP fixtures do). Reference rows reused
-- from the master data present on both sides: tt.status 2, tt.ticket_type 1,
-- mss.operating_system 2, mss.service_type 6, mss.service_level 1.
INSERT INTO stop.company (id, name, short) VALUES (954001, 'Diff Rel Co A', 'dfrela');
INSERT INTO stop.company (id, name, short) VALUES (954002, 'Diff Rel Co B', 'dfrelb');
INSERT INTO stop.contact (id, lastname, firstname, short, company_id) VALUES (954003, 'Requester', 'DiffRel', 'dfrelrq', 954001);
INSERT INTO stop.contact (id, lastname, firstname, short, company_id) VALUES (954004, 'Uploader', 'DiffRel', 'dfrelup', 954001);
INSERT INTO mss.host (id, name, operating_system_id, service_company_id, author) VALUES (954005, 'diff-rel-host', 2, 954001, 'diff');
INSERT INTO mss.service (id, service_type_id, company_id, service_level_id, name) VALUES (954006, 6, 954001, 1, 'diff-rel-svc');
INSERT INTO mss.host2service (host_id, service_id) VALUES (954005, 954006);
-- T1 and T2 belong to company A, T3 to company B
INSERT INTO tt.ticket (id, type_id, status_id, company_id, contact_id, host_id, subject, last_status_change_date)
    VALUES (954010, 1, 2, 954001, 954003, 954005, 'diff rel T1', CURRENT_TIMESTAMP - INTERVAL '1' HOUR);
INSERT INTO tt.ticket (id, type_id, status_id, company_id, contact_id, subject, last_status_change_date)
    VALUES (954011, 1, 2, 954001, 954003, 'diff rel T2', CURRENT_TIMESTAMP - INTERVAL '1' HOUR);
INSERT INTO tt.ticket (id, type_id, status_id, company_id, subject, last_status_change_date)
    VALUES (954012, 1, 2, 954002, 'diff rel T3', CURRENT_TIMESTAMP - INTERVAL '1' HOUR);
-- a pre-existing relation T2 -> T3 (remove_related_ticket is direction-sensitive)
INSERT INTO tt.ticket2related_ticket (ticket_id, related_ticket_id) VALUES (954011, 954012);
-- F1: released to company A (attachable to T1)
INSERT INTO mc.mc_file (id, uploader_id, display_name, description, filename, mime_type, mc_file_type_id)
    VALUES (954020, 954004, 'diff-f1.txt', 'diff file 1', 'diff-f1.txt', 'text/plain', 954099);
INSERT INTO mc.mc_file_release (id, company_id, mc_file_id) VALUES (954021, 954001, 954020);
-- F2: released to company B only (cross-company for T1)
INSERT INTO mc.mc_file (id, uploader_id, display_name, description, filename, mime_type, mc_file_type_id)
    VALUES (954022, 954004, 'diff-f2.txt', 'diff file 2', 'diff-f2.txt', 'text/plain', 954099);
INSERT INTO mc.mc_file_release (id, company_id, mc_file_id) VALUES (954023, 954002, 954022);
-- F3: released to company A, already related to T1 (same-company detach)
INSERT INTO mc.mc_file (id, uploader_id, display_name, description, filename, mime_type, mc_file_type_id)
    VALUES (954024, 954004, 'diff-f3.txt', 'diff file 3', 'diff-f3.txt', 'text/plain', 954099);
INSERT INTO mc.mc_file_release (id, company_id, mc_file_id) VALUES (954025, 954001, 954024);
INSERT INTO tt.ticket2mc_file (ticket_id, mc_file_id) VALUES (954010, 954024);
-- F4: released to company B only, but already related to T1 (cross-company detach, S-TICKET-060)
INSERT INTO mc.mc_file (id, uploader_id, display_name, description, filename, mime_type, mc_file_type_id)
    VALUES (954026, 954004, 'diff-f4.txt', 'diff file 4', 'diff-f4.txt', 'text/plain', 954099);
INSERT INTO mc.mc_file_release (id, company_id, mc_file_id) VALUES (954027, 954002, 954026);
INSERT INTO tt.ticket2mc_file (ticket_id, mc_file_id) VALUES (954010, 954026);
-- an orphaned relation: no mc.mc_file row 954098 exists (FK deferred on both sides)
INSERT INTO tt.ticket2mc_file (ticket_id, mc_file_id) VALUES (954010, 954098);
