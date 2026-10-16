-- migration/test/pgtap/tt__event_interface__corrections.sql
--
-- pgTAP verification of the CORRECTED moveevent semantics in
-- migration/spec/tt.event_interface.md (S-EVENT-046, S-EVENT-047 -- branch
-- phoenix/migrate_tt_only, status report 2026-10-13 Q11 (a)). Oracle's body ignores
-- p_event_id and re-parents EVERY event of the old ticket (its own header comment:
-- "FIXME / BROKEN"); the project owner's instruction for this branch is not to mimic
-- that. This file is deliberately SEPARATE from tt__event_interface__spec.sql so the
-- locked suite (including S-EVENT-033's two assertions, which still hold) is not
-- edited.
--
-- RED by construction against the pre-correction translation (which reproduces the
-- Oracle bug): the "sibling event untouched" assertions and the "event does not exist"
-- warning fail until the translation is corrected. Every assertion's description
-- starts with the spec clause ID it verifies (HARN-05, trace_lint.py).
--
-- Fixture ids: 910600+ (Q11 range 910000+, disjoint from the 9006xx spec-file range).

BEGIN;
SET CONSTRAINTS ALL DEFERRED;
SELECT plan(10);

-------------------------------------------------------------------------------
-- Fixtures: three tickets, two events on the OLD ticket, one on a decoy ticket.
-- Both old-ticket events start on 910601 (differs from the post-CALL expected
-- ticket 910602 for the moved one -- PITFALLS.md asymmetric-coverage tell).
-------------------------------------------------------------------------------

INSERT INTO stop.company (id, name, short) VALUES (910600, 'Q11 moveevent Co', 'q11mvco');
INSERT INTO tt.ticket (id, type_id, status_id, company_id) VALUES (910601, 1, 2, 910600);
INSERT INTO tt.ticket (id, type_id, status_id, company_id) VALUES (910602, 1, 2, 910600);
INSERT INTO tt.ticket (id, type_id, status_id, company_id) VALUES (910603, 1, 2, 910600);
INSERT INTO tt.event (id, type_id, ticket_id, company_id, details_public)
    VALUES (910611, 101001, 910601, 910600, 'q11 event to be moved');
INSERT INTO tt.event (id, type_id, ticket_id, company_id, details_public)
    VALUES (910612, 101001, 910601, 910600, 'q11 sibling event that must stay');
INSERT INTO tt.event (id, type_id, ticket_id, company_id, details_public)
    VALUES (910613, 101001, 910603, 910600, 'q11 decoy event on another ticket');

-------------------------------------------------------------------------------
-- S-EVENT-046: only the event named by p_event_id moves.
-------------------------------------------------------------------------------

SELECT lives_ok(
    $$CALL tt.event_interface_moveevent(910611, 910601, 910602)$$,
    'S-EVENT-046: moveevent call succeeded for an existing event/old ticket/new ticket triple'
);

SELECT is(
    (SELECT ticket_id FROM tt.event WHERE id = 910611),
    910602::numeric,
    'S-EVENT-046: moveevent moved the event named by p_event_id (910611) to p_newticket_id (910602)'
);

SELECT is(
    (SELECT ticket_id FROM tt.event WHERE id = 910612),
    910601::numeric,
    'S-EVENT-046: moveevent left the OLD ticket''s other event (910612) on 910601 -- Oracle''s UPDATE ... WHERE ticket_id = p_oldticket_id (line 880) would have moved it too'
);

SELECT is(
    (SELECT ticket_id FROM tt.event WHERE id = 910613),
    910603::numeric,
    'S-EVENT-046: moveevent did not touch an unrelated ticket''s event (910613 stays on 910603)'
);

-------------------------------------------------------------------------------
-- S-EVENT-047 (i): event exists but does not belong to p_oldticket_id -> nothing
-- happens, nothing logged. 910612 is on 910601; we name 910603 as the old ticket.
-------------------------------------------------------------------------------

SELECT lives_ok(
    $$CALL tt.event_interface_moveevent(910612, 910603, 910602)$$,
    'S-EVENT-047: moveevent call succeeded (no raise) when the event does not belong to p_oldticket_id'
);

SELECT is(
    (SELECT ticket_id FROM tt.event WHERE id = 910612),
    910601::numeric,
    'S-EVENT-047: moveevent did NOT move event 910612 because it is not attached to the named old ticket 910603 -- "nothing happens" per the package-spec contract'
);

SELECT is(
    (SELECT count(*) FROM osag.plog_stub_log WHERE message LIKE '%cannot move event 910612 from ticket 910603%'),
    0::bigint,
    'S-EVENT-047: the wrong-old-ticket no-op logged nothing (the contract says nothing happens, not a warning)'
);

-------------------------------------------------------------------------------
-- S-EVENT-047 (ii): the event does not exist -> nothing modified, warning logged.
-- Under the Oracle bug this call would have moved 910612 (every event of 910601).
-------------------------------------------------------------------------------

SELECT lives_ok(
    $$CALL tt.event_interface_moveevent(910699999, 910601, 910602)$$,
    'S-EVENT-047: moveevent call succeeded (no raise) for a nonexistent p_event_id'
);

SELECT is(
    (SELECT ticket_id FROM tt.event WHERE id = 910612),
    910601::numeric,
    'S-EVENT-047: a nonexistent p_event_id modified nothing -- event 910612 is still on 910601 (Oracle''s body would have re-parented it)'
);

SELECT ok(
    (SELECT count(*) FROM osag.plog_stub_log
      WHERE message LIKE '%cannot move event 910699999 from ticket 910601 to ticket 910602: event does not exist%') >= 1,
    'S-EVENT-047: moveevent logged "...event does not exist" via plog.warning for the nonexistent p_event_id, using the same v_errmsg prefix as the existing "new ticket does not exist" warning'
);

SELECT * FROM finish();
ROLLBACK;
