-- tt__ticket_interface__newticket_signoff / setup.sql -- dialect-neutral fixtures (951xxx).
-- Reference rows reused from the master data present on both sides: tt.event_type 30002 and
-- 101002, mss.operating_system 2, mss.service_type 6, mss.service_level 1, tt.change_request_state 3.
INSERT INTO stop.company (id, name, short) VALUES (951001, 'Diff Signoff Co', 'dfsgn1');
INSERT INTO stop.contact (id, lastname, firstname, short, company_id) VALUES (951002, 'ServiceNow', 'Desk', 'dfsgsnd', 951001);
INSERT INTO stop.contact (id, lastname, firstname, short, company_id) VALUES (951003, 'Worker', 'WithLogin', 'dfsgwk1', 951001);
INSERT INTO stop.contact (id, lastname, firstname, short, company_id) VALUES (951004, 'Worker', 'NoLogin', 'dfsgwk2', 951001);
INSERT INTO stop.contact (id, lastname, firstname, short, company_id) VALUES (951006, 'Explicit', 'Contact', 'dfsgex1', 951001);
INSERT INTO mss.host (id, name, operating_system_id, service_company_id, author) VALUES (951005, 'diff-signoff-host', 2, 951001, 'diff');
INSERT INTO mss.service (id, service_type_id, company_id, service_level_id, name) VALUES (951007, 6, 951001, 1, 'diff-signoff-svc');
INSERT INTO mss.host2service (host_id, service_id) VALUES (951005, 951007);
-- the login behind one of the eight sign-off Zitadel IDs, and a worker with a login
INSERT INTO auth.login (id, login, contact_id, company_id, oidc_zitadel_id) VALUES (951010, 'dsg-servicenow', 951002, 951001, '260976466693466175');
INSERT INTO auth.login (id, login, contact_id, company_id, oidc_zitadel_id) VALUES (951011, 'dsg-worker', 951003, 951001, '951000111222333444');
