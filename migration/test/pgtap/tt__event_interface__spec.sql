-- migration/test/pgtap/tt__event_interface__spec.sql
--
-- pgTAP verification for migration/spec/tt.event_interface.md. RED by construction: none
-- of tt.event_interface_* (nor the private tt.event_interface__is_esc_supp_active) exists
-- yet. Every assertion's description starts with the spec clause ID it verifies
-- (HARN-05, trace_lint.py).
--
-- Fixture-initial values are always chosen to DIFFER from the post-CALL expected value
-- (PITFALLS.md's asymmetric-coverage tell) -- a `lives_ok`/`throws_ok` wrapping a CALL
-- that never actually ran (because the object does not exist) must not let a follow-up
-- equality check vacuously pass by reading an untouched fixture value.

BEGIN;
SET CONSTRAINTS ALL DEFERRED;
SELECT plan(20);

-------------------------------------------------------------------------------
-- S-EVENT-034: ticket_type_for_event_type -- pure computation, no DB access, no
-- transitive COMMIT hazard (this spec's own closed FUNCTION/PROCEDURE question).
-------------------------------------------------------------------------------

SELECT is(
    tt.event_interface_ticket_type_for_event_type(10003),
    4::numeric,
    'S-EVENT-034: ticket_type_for_event_type maps ISP-outage-family event types (10003) to ticket type 4 (3rd party incident)'
);

SELECT is(
    tt.event_interface_ticket_type_for_event_type(30002),
    2::numeric,
    'S-EVENT-034: ticket_type_for_event_type maps change-request event types (30002) to ticket type 2'
);

SELECT is(
    tt.event_interface_ticket_type_for_event_type(50000),
    1::numeric,
    'S-EVENT-034: ticket_type_for_event_type defaults every other event type (50000, unmapped) to ticket type 1 (trouble ticket)'
);

-------------------------------------------------------------------------------
-- S-EVENT-042: add_history_event -- zero exception handler, unconditional notify call,
-- pure INSERT with no SELECT INTO of its own.
-------------------------------------------------------------------------------

INSERT INTO tt.ticket (id, type_id) VALUES (900601, 1);

SELECT lives_ok(
    $$CALL tt.event_interface_add_history_event(NULL, 900601, 101001, NULL, NULL, 'history text', NULL, TRUE, now(), NULL, NULL)$$,
    'S-EVENT-042: add_history_event succeeds for a valid ticket id with no host/company/contact'
);

SELECT is(
    (SELECT count(*) FROM tt.event WHERE ticket_id = 900601 AND details_public = 'history text'),
    1::bigint,
    'S-EVENT-042: add_history_event inserts exactly one event row carrying the supplied details_public text'
);

-------------------------------------------------------------------------------
-- S-EVENT-043 / S-EVENT-044: demote_event / promote_event -- zero exception block in
-- EITHER routine; a bad p_event_id propagates NO_DATA_FOUND fully unhandled.
-------------------------------------------------------------------------------

INSERT INTO tt.event (id, type_id, ticket_id, demoted) VALUES (900602, 101001, 900601, 0);

SELECT lives_ok(
    $$CALL tt.event_interface_demote_event(900602, NULL)$$,
    'S-EVENT-043: demote_event succeeds for an existing event/ticket pair'
);

SELECT is(
    (SELECT demoted FROM tt.event WHERE id = 900602),
    1::smallint,
    'S-EVENT-043: demote_event sets tt.event.demoted = 1 (fixture started at 0 -- a no-op CALL cannot vacuously satisfy this)'
);

SELECT throws_ok(
    $$CALL tt.event_interface_demote_event(900699999, NULL)$$,
    'P0002',
    NULL,
    'S-EVENT-043: demote_event propagates NO_DATA_FOUND unhandled for a nonexistent p_event_id (zero EXCEPTION blocks in the routine)'
);

SELECT lives_ok(
    $$CALL tt.event_interface_promote_event(900602, NULL)$$,
    'S-EVENT-044: promote_event succeeds for an existing event/ticket pair'
);

SELECT is(
    (SELECT demoted FROM tt.event WHERE id = 900602),
    0::smallint,
    'S-EVENT-044: promote_event sets tt.event.demoted back to 0 (fixture was set to 1 by the prior demote_event call)'
);

SELECT throws_ok(
    $$CALL tt.event_interface_promote_event(900699999, NULL)$$,
    'P0002',
    NULL,
    'S-EVENT-044: promote_event propagates the same unhandled NO_DATA_FOUND shape as demote_event'
);

-------------------------------------------------------------------------------
-- S-EVENT-033: moveevent -- its own 3-arm handler swallows a nonexistent new-ticket id
-- (logged, not raised) -- the routine's own acknowledged FIXME/BROKEN behavior is
-- reproduced as-is, not silently fixed.
-------------------------------------------------------------------------------

SELECT lives_ok(
    $$CALL tt.event_interface_moveevent(900602, 900601, 900699998)$$,
    'S-EVENT-033: moveevent swallows (logs, does not raise) a nonexistent p_newticket_id via its own local WHEN NO_DATA_FOUND'
);

SELECT ok(
    (SELECT count(*) FROM osag.plog_stub_log WHERE message LIKE '%new ticket does not exist%') >= 1,
    'S-EVENT-033: moveevent logs "...new ticket does not exist" via plog.warning for the swallowed NO_DATA_FOUND'
);

-------------------------------------------------------------------------------
-- S-EVENT-001: newevent_new's host2service join -- TOO_MANY_ROWS is structurally
-- reachable (mss.host2service's primary key spans host_id and service_id together,
-- not unique on host_id alone) and, unlike the local NO_DATA_FOUND arm, is caught only
-- by `WHEN OTHERS THEN RAISE` -- newevent_new has NO outer handler of its own, so it
-- propagates fully unhandled.
-------------------------------------------------------------------------------

INSERT INTO stop.company (id, name, short) VALUES (900603, 'Pilot Co', 'pilotco3');
INSERT INTO mss.host (id, name, operating_system_id, service_company_id, author, active)
    VALUES (900604, 'pilot-multi-service-host', 2, 900603, 'pilot', 1);
INSERT INTO mss.host2service (host_id, service_id) VALUES (900604, 900605);
INSERT INTO mss.host2service (host_id, service_id) VALUES (900604, 900606);

SELECT throws_ok(
    $$CALL tt.event_interface_newevent_new(NULL, 101001, 900604, 'evt details')$$,
    'P0003',
    NULL,
    'S-EVENT-001: newevent_new propagates TOO_MANY_ROWS unhandled for a host mapped to two services (WHEN OTHERS THEN RAISE re-raises; no outer net exists)'
);

-------------------------------------------------------------------------------
-- S-EVENT-003: newevent_new drops the event for an inactive host -- a normal early
-- RETURN, not an exception.
-------------------------------------------------------------------------------

INSERT INTO mss.host (id, name, operating_system_id, service_company_id, author, active)
    VALUES (900607, 'pilot-inactive-host', 2, 900603, 'pilot', 0);

SELECT lives_ok(
    $$CALL tt.event_interface_newevent_new(NULL, 101001, 900607, 'evt details')$$,
    'S-EVENT-003: newevent_new returns normally (no exception) for an inactive host, dropping the event'
);

SELECT is(
    (SELECT count(*) FROM tt.ticket WHERE host_id = 900607),
    0::bigint,
    'S-EVENT-003: newevent_new creates no ticket at all for a dropped (inactive-host) event'
);

-------------------------------------------------------------------------------
-- S-EVENT-021: addevent_new on a closed/deleted ticket (status_id > 101) re-raises the
-- named ticket_closed exception -- the package's ONE intentionally-propagated failure.
-------------------------------------------------------------------------------

INSERT INTO tt.ticket (id, type_id, status_id) VALUES (900608, 1, 102);

SELECT throws_like(
    $$CALL tt.event_interface_addevent_new(NULL, 900608, 101001, NULL, 'evt details')$$,
    '%closed%',
    'S-EVENT-021: addevent_new re-raises the named ticket_closed exception for a closed (status 102) ticket, unlike every other internal failure this package swallows'
);

-------------------------------------------------------------------------------
-- S-EVENT-019: addevent_new's merged-ticket lookup uses ROWNUM=1 in Oracle -- TWO
-- candidate merge-event rows exist for this ticket, so the translation MUST cap the
-- result at one row (LIMIT 1) rather than relying on STRICT alone, or it would raise
-- TOO_MANY_ROWS in a case Oracle structurally never could.
-------------------------------------------------------------------------------

INSERT INTO tt.ticket (id, type_id, status_id) VALUES (900609, 1, 110); -- merged
INSERT INTO tt.ticket (id, type_id, status_id) VALUES (900610, 1, 2);  -- merge target A
INSERT INTO tt.ticket (id, type_id, status_id) VALUES (900611, 1, 2);  -- merge target B
INSERT INTO tt.event (id, type_id, ticket_id, details_private)
    VALUES (900612, 100004, 900609, '900610');
INSERT INTO tt.event (id, type_id, ticket_id, details_private)
    VALUES (900613, 100004, 900609, '900611');

SELECT lives_ok(
    $$CALL tt.event_interface_addevent_new(NULL, 900609, 101001, NULL, 'evt details')$$,
    'S-EVENT-019: addevent_new does NOT raise TOO_MANY_ROWS for a merged ticket with two candidate merge-event rows -- the ROWNUM=1 -> LIMIT 1 translation must cap the query, not just add STRICT'
);

-------------------------------------------------------------------------------
-- S-EVENT-035: exec_event_type_actions, called directly (not via addevent_new's outer
-- swallow), propagates its own type_id lookup's NO_DATA_FOUND fully unhandled.
-------------------------------------------------------------------------------

SELECT throws_ok(
    $$CALL tt.event_interface_exec_event_type_actions(900699999)$$,
    'P0002',
    NULL,
    'S-EVENT-035: exec_event_type_actions, called directly, propagates NO_DATA_FOUND unhandled for a nonexistent p_event_id (no wrapping outer handler exists at this call path)'
);

-------------------------------------------------------------------------------
-- S-EVENT-038: the dynamic-SQL site (DYNAMIC-SQL-TRACE.md verdict: EXECUTE format(),
-- allowlist-validated). A procedure_name resolving to a real routine that is NOT on the
-- TT.ESCALATION_INTERFACE allowlist must be REJECTED (a labelled error), not silently
-- executed -- this is the test that stops a config-controlled value from calling an
-- unintended-but-syntactically-valid routine, per the trace's step-2 recommendation.
-------------------------------------------------------------------------------

INSERT INTO tt.event_type (id, name, source, sms_message_template_id, email_message_template_id)
    VALUES (900614, 'pilot dynamic-sql event type', 1, 1, 2);
INSERT INTO tt.event_action (id, name, procedure_name)
    VALUES (900615, 'pilot off-allowlist action', 'tt.osag_notify.send_test_notification');
INSERT INTO tt.event_type_action (event_action_id, event_type_id) VALUES (900615, 900614);
INSERT INTO tt.event (id, type_id, ticket_id) VALUES (900616, 900614, 900601);

SELECT throws_like(
    $$CALL tt.event_interface_exec_event_type_actions(900616)$$,
    '%allow%',
    'S-EVENT-038: exec_event_type_actions rejects a resolved procedure name that is real but NOT on the TT.ESCALATION_INTERFACE allowlist -- config data must not select an unintended callee'
);

SELECT * FROM finish();
ROLLBACK;
