-- migration/test/pgtap/tt__ticket_interface__corrections.sql
--
-- pgTAP verification of the CORRECTED behaviours in
-- migration/spec/tt.ticket_interface.md introduced on branch phoenix/migrate_tt_only
-- (status report 2026-10-13, Q11):
--   (b) S-TICKET-059 -- add_status_change_event resolves the audit event's company_id
--       from the ticket (Oracle never assigned cust_id: every such event had NULL);
--   (d) S-TICKET-060 -- remove_related_file carries the same same-company guard as
--       add_related_file (Oracle let any caller detach a relation across companies).
-- Q11 (c) (expire_status / change_label) was decided "behaviour kept" -- the locked
-- S-TICKET-021 assertions in tt__ticket_interface__lifecycle.sql remain its tests.
--
-- Deliberately a SEPARATE file so the locked suites are edited as little as possible
-- (the one fixture amendment they did need is ledgered: TEST-AMENDMENTS.md A-014/A-015).
--
-- RED by construction against the pre-correction translation (which reproduces both
-- Oracle defects). Every assertion's description starts with the spec clause ID it
-- verifies (HARN-05, trace_lint.py). Every "did NOT happen" check sits next to the
-- "call succeeded" check for the same call.
--
-- Fixture ids: 910000-910099 (Q11 range 910000+; disjoint from the 9056xx/9066xx/9076xx
-- ranges of the locked files and from tt__event_interface__corrections.sql's 9106xx).

BEGIN;
SET CONSTRAINTS ALL DEFERRED;
SELECT plan(15);

-------------------------------------------------------------------------------
-- Fixtures
-------------------------------------------------------------------------------

INSERT INTO stop.company (id, name, short) VALUES (910001, 'Q11 Ticket Co', 'q11tco');
INSERT INTO stop.company (id, name, short) VALUES (910002, 'Q11 Other Co', 'q11oco');
INSERT INTO stop.contact (id, lastname, firstname, short, company_id)
    VALUES (910003, 'Corrections', 'Q11', 'q11ctc', 910001);

-- (d) one ticket of company 910001 with two related files: 910021 released to the
-- ticket's OWN company, 910022 released ONLY to the other company.
INSERT INTO tt.ticket (id, type_id, status_id, company_id) VALUES (910010, 1, 2, 910001);
INSERT INTO mc.mc_file (id, uploader_id, display_name, description, filename, mime_type, mc_file_type_id)
    VALUES (910021, 910003, 'q11-same-co.txt', 'q11 same-company file', 'q11-same-co.txt', 'text/plain', 900299999);
INSERT INTO mc.mc_file (id, uploader_id, display_name, description, filename, mime_type, mc_file_type_id)
    VALUES (910022, 910003, 'q11-other-co.txt', 'q11 other-company file', 'q11-other-co.txt', 'text/plain', 900299999);
INSERT INTO mc.mc_file_release (id, company_id, mc_file_id) VALUES (910031, 910001, 910021);
INSERT INTO mc.mc_file_release (id, company_id, mc_file_id) VALUES (910032, 910002, 910022);
INSERT INTO tt.ticket2mc_file (ticket_id, mc_file_id) VALUES (910010, 910021);
INSERT INTO tt.ticket2mc_file (ticket_id, mc_file_id) VALUES (910010, 910022);

-- (b) one ticket of company 910001 for the attribute-change audit events.
INSERT INTO tt.ticket (id, type_id, status_id, company_id, contact_id, last_status_change_date)
    VALUES (910011, 1, 2, 910001, 910003, now() - interval '1 hour');

-------------------------------------------------------------------------------
-- S-TICKET-060 (d): cross-company detach is refused (logged, swallowed, no delete,
-- no history event); same-company detach still works exactly as before.
-------------------------------------------------------------------------------

SELECT lives_ok(
    $$CALL tt.ticket_interface_remove_related_file(910010, 910022, 910003)$$,
    'S-TICKET-060: remove_related_file call succeeded (nothing raised to the caller) for a file released only to ANOTHER company'
);

SELECT is(
    (SELECT count(*) FROM tt.ticket2mc_file WHERE ticket_id = 910010 AND mc_file_id = 910022),
    1::bigint,
    'S-TICKET-060: remove_related_file did NOT delete the cross-company relation (910010/910022) -- Oracle''s un-guarded lookup would have'
);

SELECT ok(
    (SELECT count(*) FROM osag.plog_stub_log
      WHERE message LIKE 'remove_related_file(): %belong to different companies%') >= 1,
    'S-TICKET-060: remove_related_file logged the mirrored "does not exist or they belong to different companies" message via plog.err for the refused cross-company detach'
);

SELECT is(
    (SELECT count(*) FROM tt.event WHERE ticket_id = 910010 AND type_id = 100019),
    0::bigint,
    'S-TICKET-060: no "removed related document" history event (100019) was written for the refused cross-company detach'
);

SELECT lives_ok(
    $$CALL tt.ticket_interface_remove_related_file(910010, 910021, 910003)$$,
    'S-TICKET-060: remove_related_file call succeeded for a file released to the ticket''s OWN company'
);

SELECT is(
    (SELECT count(*) FROM tt.ticket2mc_file WHERE ticket_id = 910010 AND mc_file_id = 910021),
    0::bigint,
    'S-TICKET-060: remove_related_file deleted the same-company relation (910010/910021) -- the guard changes nothing for the legitimate case'
);

SELECT is(
    (SELECT count(*) FROM tt.event WHERE ticket_id = 910010 AND type_id = 100019),
    1::bigint,
    'S-TICKET-060: exactly ONE 100019 history event exists for ticket 910010 -- the same-company detach wrote it, the refused cross-company attempt did not'
);

-------------------------------------------------------------------------------
-- S-TICKET-059 (b): audit events written through add_status_change_event carry the
-- ticket's company_id; a nonexistent ticket now raises NO_DATA_FOUND from the lookup.
-------------------------------------------------------------------------------

SELECT lives_ok(
    $$CALL tt.ticket_interface_change_customer_reference(910011, 'q11-ref', 910003)$$,
    'S-TICKET-059: change_customer_reference call succeeded for an existing ticket of company 910001'
);

SELECT is(
    (SELECT company_id FROM tt.event
      WHERE ticket_id = 910011 AND type_id = 100003 AND details_public = 'customer reference changed to q11-ref'),
    910001::numeric,
    'S-TICKET-059: the customer-reference audit event carries the ticket''s company_id (910001) -- Oracle''s add_status_change_event inserted the never-assigned cust_id (NULL)'
);

SELECT lives_ok(
    $$CALL tt.ticket_interface_change_partner_reference(910011, 'q11-partner', 910003)$$,
    'S-TICKET-059: change_partner_reference call succeeded (private-text branch of add_status_change_event)'
);

SELECT is(
    (SELECT company_id FROM tt.event
      WHERE ticket_id = 910011 AND type_id = 100003 AND details_private = 'partner reference changed to q11-partner'),
    910001::numeric,
    'S-TICKET-059: the partner-reference (hidden) audit event carries the ticket''s company_id (910001)'
);

SELECT lives_ok(
    $$CALL tt.ticket_interface_change_emergency(910011, 1, 910003)$$,
    'S-TICKET-059: change_emergency call succeeded (5-positional-argument caller of add_status_change_event)'
);

SELECT is(
    (SELECT company_id FROM tt.event
      WHERE ticket_id = 910011 AND type_id = 100003 AND details_public = 'ticket changed to emergency'),
    910001::numeric,
    'S-TICKET-059: the emergency audit event carries the ticket''s company_id (910001)'
);

SELECT throws_ok(
    $$CALL tt.ticket_interface_change_customer_reference(910999999, 'q11-orphan', 910003)$$,
    'P0002',
    NULL,
    'S-TICKET-059: change_customer_reference raises NO_DATA_FOUND (P0002) for a nonexistent ticket -- the company lookup is STRICT and unhandled, like change_subject''s site #29'
);

SELECT is(
    (SELECT count(*) FROM tt.event WHERE ticket_id = 910999999),
    0::bigint,
    'S-TICKET-059: no audit event was written for the nonexistent ticket (the raise happens before the INSERT; Oracle would have written the row and failed later on the FK)'
);

SELECT * FROM finish();
ROLLBACK;
