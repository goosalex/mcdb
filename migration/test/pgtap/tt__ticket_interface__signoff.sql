-- migration/test/pgtap/tt__ticket_interface__signoff.sql
--
-- pgTAP verification of migration/spec/tt.ticket_interface.md clauses S-TICKET-061,
-- S-TICKET-062 and S-TICKET-063 -- the behaviour the 2026-10-20 Oracle export (commit
-- 0e5c990) added to newticket_new and change_worker: ServiceNow sign-off senders known
-- only by Zitadel user ID are mapped to their auth.login contact, the change-request rule
-- also fires for them, and both routines write tt.ticket.worker_zitadel_id.
--
-- RED by construction: the translation re-synced with that export lands after this
-- file. Every assertion's description begins with the spec clause ID it verifies
-- (HARN-05, trace_lint.py). Expected values come from the spec ONLY.

BEGIN;
SET CONSTRAINTS ALL DEFERRED;
SELECT plan(22);

-------------------------------------------------------------------------------
-- Fixtures (9086xx). Reference rows reused from masterdata: tt.event_type 30002
-- (change request) and 101002, mss.operating_system 2, tt.change_request_state 3.
-- Every call passes p_host_id so the company comes from the host and the
-- company-wide-admin owner check (p_host_id IS NULL branch) is not entered -- the
-- mapped contact is kept as ticket contact exactly as the spec describes.
-------------------------------------------------------------------------------
INSERT INTO stop.company (id, name, short) VALUES (908601, 'Signoff Co', 'sgnoff1');
INSERT INTO stop.contact (id, lastname, firstname, short, company_id) VALUES (908602, 'ServiceNow', 'Desk', 'sgnsnd1', 908601);
INSERT INTO stop.contact (id, lastname, firstname, short, company_id) VALUES (908603, 'Worker', 'WithLogin', 'sgnwk1', 908601);
INSERT INTO stop.contact (id, lastname, firstname, short, company_id) VALUES (908604, 'Worker', 'NoLogin', 'sgnwk2', 908601);
INSERT INTO stop.contact (id, lastname, firstname, short, company_id) VALUES (908606, 'Explicit', 'Contact', 'sgnex1', 908601);
INSERT INTO mss.host (id, name, operating_system_id, service_company_id, author) VALUES (908605, 'signoff-host', 2, 908601, 'signoff');
-- the login behind one of the eight sign-off Zitadel IDs, and a worker with a login
INSERT INTO auth.login (id, login, contact_id, company_id, oidc_zitadel_id) VALUES (908610, 'sgn-servicenow', 908602, 908601, '260976466693466175');
INSERT INTO auth.login (id, login, contact_id, company_id, oidc_zitadel_id) VALUES (908611, 'sgn-worker', 908603, 908601, '908600111222333444');

-------------------------------------------------------------------------------
-- A: sign-off Zitadel sender, no p_contact_id, event type 30002 (S-TICKET-061/062)
-------------------------------------------------------------------------------
SELECT lives_ok(
    $$CALL tt.ticket_interface_newticket_new(NULL, NULL, 1, 'signoff A', 30002, 908605, 'pub A', 'priv A', NULL, NULL, TRUE, statement_timestamp(), NULL, NULL, 260976466693466175)$$,
    'S-TICKET-061: newticket_new succeeds for a ServiceNow sign-off sender given only by Zitadel user ID (event type 30002, no p_contact_id)'
);
SELECT is((SELECT contact_id::text FROM tt.ticket WHERE subject = 'signoff A'), '908602',
    'S-TICKET-061: the ticket contact is the contact of the auth.login row carrying that Zitadel ID (MAX(contact_id), site #78)');
SELECT is((SELECT company_id::text FROM tt.ticket WHERE subject = 'signoff A'), '908601',
    'S-TICKET-061: the company is resolved through the mapped sender contact (site #3 reads v_sender_contact_id)');
SELECT is((SELECT type_id::text FROM tt.ticket WHERE subject = 'signoff A'), '2',
    'S-TICKET-062: the sign-off sender forces ticket type 2 (change) although p_ticket_type_id was 1');
SELECT is((SELECT requester_id::text || '/' || approver_id::text || '/' || change_request_state_id::text
             FROM tt.change_request WHERE ticket_id = (SELECT id FROM tt.ticket WHERE subject = 'signoff A')),
    '908602/908602/3',
    'S-TICKET-062: one pre-approved change request (state 3) with requester = approver = the mapped sender contact');
SELECT is((SELECT min(contact_id)::text FROM tt.event WHERE ticket_id = (SELECT id FROM tt.ticket WHERE subject = 'signoff A') AND type_id = 30002), '908602',
    'S-TICKET-061: the first event''s contact is the mapped sender (event-contact fallback: p_worker_id, else v_sender_contact_id)');

-------------------------------------------------------------------------------
-- B: same Zitadel ID but event type 101002 -> no mapping at all (S-TICKET-061/062)
-------------------------------------------------------------------------------
SELECT lives_ok(
    $$CALL tt.ticket_interface_newticket_new(NULL, NULL, 1, 'signoff B', 101002, 908605, 'pub B', 'priv B', NULL, NULL, TRUE, statement_timestamp(), NULL, NULL, 260976466693466175)$$,
    'S-TICKET-061: outside event type 30002 a sign-off Zitadel ID changes nothing -- the call succeeds as before the export'
);
SELECT ok((SELECT contact_id IS NULL FROM tt.ticket WHERE subject = 'signoff B'),
    'S-TICKET-061: no contact is mapped for event type 101002 (ticket contact stays NULL)');
SELECT is((SELECT count(*)::text FROM tt.change_request WHERE ticket_id = (SELECT id FROM tt.ticket WHERE subject = 'signoff B')), '0',
    'S-TICKET-062: no change request for event type 101002');
SELECT is((SELECT type_id::text FROM tt.ticket WHERE subject = 'signoff B'), '1',
    'S-TICKET-062: ticket type stays the requested 1 for event type 101002');

-------------------------------------------------------------------------------
-- C: event type 30002 but a Zitadel ID outside the sign-off list (S-TICKET-061/062)
-------------------------------------------------------------------------------
SELECT lives_ok(
    $$CALL tt.ticket_interface_newticket_new(NULL, NULL, 1, 'signoff C', 30002, 908605, 'pub C', 'priv C', NULL, NULL, TRUE, statement_timestamp(), NULL, NULL, 123456789012345678)$$,
    'S-TICKET-061: a Zitadel ID that is not a sign-off sender is not mapped -- the call succeeds'
);
SELECT ok((SELECT contact_id IS NULL FROM tt.ticket WHERE subject = 'signoff C'),
    'S-TICKET-061: no contact is mapped for a non-sign-off Zitadel ID');
SELECT is((SELECT count(*)::text FROM tt.change_request WHERE ticket_id = (SELECT id FROM tt.ticket WHERE subject = 'signoff C')), '0',
    'S-TICKET-062: no change request for a non-sign-off Zitadel ID with no legacy contact');

-------------------------------------------------------------------------------
-- D: explicit p_contact_id AND a sign-off Zitadel ID -> the explicit contact wins,
--    the change request is still created via v_sign_off_sender (S-TICKET-061/062)
-------------------------------------------------------------------------------
SELECT lives_ok(
    $$CALL tt.ticket_interface_newticket_new(NULL, NULL, 1, 'signoff D', 30002, 908605, 'pub D', 'priv D', 908606, NULL, TRUE, statement_timestamp(), NULL, NULL, 260976466693466175)$$,
    'S-TICKET-061: an explicit p_contact_id together with a sign-off Zitadel ID succeeds'
);
SELECT is((SELECT contact_id::text FROM tt.ticket WHERE subject = 'signoff D'), '908606',
    'S-TICKET-061: an explicitly passed p_contact_id always wins over the Zitadel mapping');
SELECT is((SELECT requester_id::text || '/' || change_request_state_id::text FROM tt.change_request WHERE ticket_id = (SELECT id FROM tt.ticket WHERE subject = 'signoff D')), '908606/3',
    'S-TICKET-062: the change request is created through v_sign_off_sender = 1 with the explicit contact as requester');

-------------------------------------------------------------------------------
-- E: sign-off Zitadel ID with NO auth.login row -> contact NULL, CR still created
--    with NULL requester/approver (S-TICKET-061/062)
-------------------------------------------------------------------------------
SELECT lives_ok(
    $$CALL tt.ticket_interface_newticket_new(NULL, NULL, 1, 'signoff E', 30002, 908605, 'pub E', 'priv E', NULL, NULL, TRUE, statement_timestamp(), NULL, NULL, 249698997185305231)$$,
    'S-TICKET-062: a sign-off Zitadel sender with no auth.login row still succeeds (MAX over zero rows is NULL, no NO_DATA_FOUND)'
);
SELECT ok((SELECT requester_id IS NULL AND approver_id IS NULL FROM tt.change_request WHERE ticket_id = (SELECT id FROM tt.ticket WHERE subject = 'signoff E')),
    'S-TICKET-062: the change request exists with NULL requester and approver (both columns nullable)');
SELECT ok((SELECT contact_id IS NULL FROM tt.ticket WHERE subject = 'signoff E'),
    'S-TICKET-061: the ticket contact is NULL when the sign-off Zitadel ID maps to no login');

-------------------------------------------------------------------------------
-- F: worker_zitadel_id on insert and on change_worker (S-TICKET-063)
-------------------------------------------------------------------------------
SELECT lives_ok(
    $$CALL tt.ticket_interface_newticket_new(NULL, NULL, 1, 'signoff F1', 101002, 908605, 'pub F1', 'priv F1', NULL, 908603, TRUE, statement_timestamp(), NULL, NULL, NULL)$$,
    'S-TICKET-063: newticket_new with a worker that owns a login succeeds'
);
SELECT is((SELECT worker_zitadel_id FROM tt.ticket WHERE subject = 'signoff F1'), '908600111222333444',
    'S-TICKET-063: newticket_new writes worker_zitadel_id from auth.login.oidc_zitadel_id of p_worker_id');
SELECT lives_ok(
    $$CALL tt.ticket_interface_newticket_new(NULL, NULL, 1, 'signoff F2', 101002, 908605, 'pub F2', 'priv F2', NULL, 908604, TRUE, statement_timestamp(), NULL, NULL, NULL)$$,
    'S-TICKET-063: newticket_new with a worker without any login succeeds (scalar subquery over zero rows is NULL)'
);
SELECT ok((SELECT worker_zitadel_id IS NULL FROM tt.ticket WHERE subject = 'signoff F2'),
    'S-TICKET-063: worker_zitadel_id is NULL when the worker has no login');
SELECT lives_ok(
    $$CALL tt.ticket_interface_change_worker((SELECT id FROM tt.ticket WHERE subject = 'signoff F2'), 908603, 908602)$$,
    'S-TICKET-063: change_worker to a worker with a login succeeds'
);
SELECT is((SELECT worker_zitadel_id FROM tt.ticket WHERE subject = 'signoff F2'), '908600111222333444',
    'S-TICKET-063: change_worker writes worker_zitadel_id in the same UPDATE as worker_id');

SELECT * FROM finish();
ROLLBACK;
