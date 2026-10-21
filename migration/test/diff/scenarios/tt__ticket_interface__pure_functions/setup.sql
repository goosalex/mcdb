-- tt__ticket_interface__pure_functions / setup.sql -- dialect-neutral fixtures (954070-954099).
-- Reference rows reused from the master data present on both sides: tt.status
-- 2/3/60/101/102, tt.ticket_type 1/2/12, mss.operating_system 2.
INSERT INTO stop.company (id, name, short) VALUES (954071, 'Diff Pure Co', 'dfpure');
INSERT INTO stop.contact (id, lastname, firstname, short, company_id) VALUES (954072, 'Requester', 'DiffPure', 'dfpurerq', 954071);
INSERT INTO mss.host (id, name, operating_system_id, service_company_id, author) VALUES (954075, 'diff-pure-host', 2, 954071, 'diff');
INSERT INTO mss.host (id, name, operating_system_id, service_company_id, author) VALUES (954076, 'diff-pure-host-2', 2, 954071, 'diff');
-- G1 open, G2 deferred (excluded), G3 closed (excluded), G4 resolved 2 hours ago, G5 hot of type 2,
-- G6 open without host of type 12, G7 open on another host
INSERT INTO tt.ticket (id, type_id, status_id, company_id, contact_id, host_id, subject, last_status_change_date)
    VALUES (954080, 1, 2, 954071, 954072, 954075, 'diff pure G1', CURRENT_TIMESTAMP - INTERVAL '1' HOUR);
INSERT INTO tt.ticket (id, type_id, status_id, company_id, contact_id, host_id, subject, last_status_change_date)
    VALUES (954081, 1, 60, 954071, 954072, 954075, 'diff pure G2', CURRENT_TIMESTAMP - INTERVAL '1' HOUR);
INSERT INTO tt.ticket (id, type_id, status_id, company_id, contact_id, host_id, subject, last_status_change_date)
    VALUES (954082, 1, 102, 954071, 954072, 954075, 'diff pure G3', CURRENT_TIMESTAMP - INTERVAL '1' HOUR);
INSERT INTO tt.ticket (id, type_id, status_id, company_id, contact_id, host_id, subject, last_status_change_date, last_resolved_date)
    VALUES (954083, 1, 101, 954071, 954072, 954075, 'diff pure G4', CURRENT_TIMESTAMP - INTERVAL '2' HOUR, CURRENT_TIMESTAMP - INTERVAL '2' HOUR);
INSERT INTO tt.ticket (id, type_id, status_id, company_id, contact_id, host_id, subject, last_status_change_date)
    VALUES (954084, 2, 3, 954071, 954072, 954075, 'diff pure G5', CURRENT_TIMESTAMP - INTERVAL '1' HOUR);
INSERT INTO tt.ticket (id, type_id, status_id, company_id, contact_id, subject, last_status_change_date)
    VALUES (954085, 12, 2, 954071, 954072, 'diff pure G6', CURRENT_TIMESTAMP - INTERVAL '1' HOUR);
INSERT INTO tt.ticket (id, type_id, status_id, company_id, contact_id, host_id, subject, last_status_change_date)
    VALUES (954086, 1, 2, 954071, 954072, 954076, 'diff pure G7', CURRENT_TIMESTAMP - INTERVAL '1' HOUR);
