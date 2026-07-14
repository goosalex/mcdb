-- migration/test/pgtap/tt__ticket_interface__lifecycle.sql
--
-- pgTAP verification of migration/spec/tt.ticket_interface.md's ticket-lifecycle
-- routines: newticket_new, change_status(_event_id_out), expire_status,
-- change_deferral_date, update_ux_timeout_for_ticket, updateTicketFlow,
-- trigger_escalation, merge_tickets, deleteTicket, get_next_recent_ticket.
--
-- RED by construction: tt.ticket_interface_* does not exist yet -- the translation
-- lands in plan 02-12, deliberately after this suite. Every assertion's description
-- begins with the spec clause ID it verifies (HARN-05, trace_lint.py). Source of
-- expected values is migration/spec/tt.ticket_interface.md ONLY -- never
-- pg_migration/output/, never a PL/pgSQL translation (the_one_rule, plan 02-08).

BEGIN;
SET CONSTRAINTS ALL DEFERRED;
SELECT plan(39);

-------------------------------------------------------------------------------
-- Fixtures. Reference rows reused from the template's masterdata (status ids
-- 1/2/3/4/11/12/60/61/101/110/120, ticket_type ids 1/12, event_type_message ids
-- 1/2, operating_system id 2) -- see migration/test/pgtap/tt__osag_notify__spec.sql
-- for the identical reuse idiom. Pilot-owned rows use the 905xxx id range,
-- disjoint from the osag_notify (9001xx) and event_interface pilot ranges.
-------------------------------------------------------------------------------

INSERT INTO stop.company (id, name, short) VALUES (905001, 'Pilot Ticket Co', 'pltick1');
INSERT INTO stop.contact (id, lastname, firstname, short, company_id) VALUES (905002, 'Requester', 'Pilot', 'pltirq1', 905001);
INSERT INTO stop.contact (id, lastname, firstname, short, company_id) VALUES (905003, 'Worker', 'Pilot', 'pltiwk1', 905001);
INSERT INTO mss.host (id, name, operating_system_id, service_company_id, author)
    VALUES (905005, 'pilot-ti-host', 2, 905001, 'pilot');
INSERT INTO tt.event_type (id, name, source, sms_message_template_id, email_message_template_id)
    VALUES (905006, 'pilot ti event type', 1, 1, 2);

-- Ticket A: open (status 2), fully populated -- the "happy path" ticket used by
-- change_status/change_status_event_id_out/update_ux_timeout_for_ticket/
-- updateTicketFlow/trigger_escalation.
INSERT INTO tt.ticket (id, type_id, status_id, company_id, contact_id, worker_id, host_id)
    VALUES (905010, 1, 2, 905001, 905002, 905003, 905005);
INSERT INTO tt.event (id, type_id, ticket_id) VALUES (905011, 905006, 905010);

-- Ticket B: deferred (status 60) -- the positive branch of change_deferral_date.
INSERT INTO tt.ticket (id, type_id, status_id, company_id, host_id)
    VALUES (905012, 1, 60, 905001, 905005);

-- Tickets C (source) and D (target) for merge_tickets.
INSERT INTO tt.ticket (id, type_id, status_id, company_id, contact_id, partner_reference)
    VALUES (905013, 1, 2, 905001, 905002, 'src-partner-ref');
INSERT INTO tt.ticket (id, type_id, status_id, company_id, contact_id)
    VALUES (905014, 1, 2, 905001, 905002);
INSERT INTO tt.event (id, type_id, ticket_id) VALUES (905015, 905006, 905013);
INSERT INTO tt.event (id, type_id, ticket_id) VALUES (905016, 905006, 905014);
UPDATE tt.ticket SET last_public_event_id = 905015 WHERE id = 905013;
UPDATE tt.ticket SET last_public_event_id = 905016 WHERE id = 905014;

-- Ticket E, fully cross-referenced, for deleteTicket's cascade/non-cascade proof.
INSERT INTO tt.ticket (id, type_id, status_id, company_id, contact_id)
    VALUES (905017, 1, 2, 905001, 905002);
INSERT INTO tt.event (id, type_id, ticket_id) VALUES (905020, 905006, 905017);
INSERT INTO tt.todo_item (id, ticket_id, seq_no, details, todo_item_status_id)
    VALUES (905021, 905017, 1, 'pilot todo', 1);
INSERT INTO tt.ticket_docs_page (id, ticket_id, page_id, page_version)
    VALUES (905022, 905017, 700001, 1);
INSERT INTO tt.ticket_rating (id, rating, event_id) VALUES (905023, 5, 905020);
UPDATE tt.ticket SET customer_ticket_rating_id = 905023 WHERE id = 905017;

-- Ticket F: no open ticket_flow entry -- the insert-new branch of updateTicketFlow.
INSERT INTO tt.ticket (id, type_id, status_id, company_id, handled_by_mcc)
    VALUES (905018, 1, 2, 905001, 1);

-- Ticket G: has an already-open ticket_flow entry -- the close-existing branch.
INSERT INTO tt.ticket (id, type_id, status_id, company_id, handled_by_mcc)
    VALUES (905019, 1, 4, 905001, 0);
INSERT INTO tt.ticket_flow (id, ticket_id, flow_in_date, flow_out_date)
    VALUES (905024, 905019, now() - interval '1 hour', NULL);

-------------------------------------------------------------------------------
-- newticket_new (S-TICKET-001 .. S-TICKET-005)
-------------------------------------------------------------------------------

SELECT throws_ok(
    $$CALL tt.ticket_interface_newticket_new(NULL, NULL, 1, 'pilot subj', 905006, 905099999, 'pub', 'priv')$$,
    'P0002',
    NULL,
    'S-TICKET-001: newticket_new propagates NO_DATA_FOUND unhandled for a nonexistent p_host_id (site #1, mss.host lookup)'
);

SELECT throws_ok(
    $$CALL tt.ticket_interface_newticket_new(NULL, NULL, 1, 'pilot subj', 905006, NULL, 'pub', 'priv', 905099998)$$,
    'P0002',
    NULL,
    'S-TICKET-002: newticket_new propagates NO_DATA_FOUND unhandled for a nonexistent p_contact_id when p_host_id is NULL (site #3, stop.contact lookup)'
);

SELECT throws_ok(
    $$CALL tt.ticket_interface_newticket_new(NULL, NULL, 1, 'pilot subj', 905099997, NULL, 'pub', 'priv')$$,
    'P0002',
    NULL,
    'S-TICKET-003: newticket_new propagates NO_DATA_FOUND unhandled for a nonexistent p_event_type_id (site #5, tt.event_type lookup)'
);

SELECT throws_ok(
    $$CALL tt.ticket_interface_newticket_new(NULL, NULL, 1, 'pilot subj', 905006, NULL, 'pub', 'priv', NULL, 905099996)$$,
    'P0002',
    NULL,
    'S-TICKET-004: newticket_new propagates NO_DATA_FOUND unhandled for a nonexistent p_worker_id when p_host_id is NULL (site #6, stop.contact lookup)'
);

SELECT lives_ok(
    $test1$
    DO $do1$
    DECLARE
        v_ticket_id numeric;
        v_event_id numeric;
    BEGIN
        CALL tt.ticket_interface_newticket_new(v_ticket_id, v_event_id, 1, 'pilot new ticket', 905006, NULL, 'public details', 'private details', 905002);
        IF v_ticket_id IS NULL OR v_event_id IS NULL THEN
            RAISE EXCEPTION 'newticket_new left OUT ticket_id/event_id NULL for a valid request';
        END IF;
    END
    $do1$;
    $test1$,
    'S-TICKET-005: newticket_new pulls non-NULL p_ticket_id/p_event_id from ticket_sequence/event_sequence (sites #7-#8) for a valid new ticket'
);

-------------------------------------------------------------------------------
-- change_deferral_date (S-TICKET-006)
-------------------------------------------------------------------------------

SELECT throws_ok(
    $$CALL tt.ticket_interface_change_deferral_date(905099995, 905002, now()::date, 'pub')$$,
    'P0002',
    NULL,
    'S-TICKET-006: change_deferral_date propagates NO_DATA_FOUND unhandled for a nonexistent p_ticket_id (site #10, tt.ticket lookup)'
);

SELECT lives_ok(
    $$CALL tt.ticket_interface_change_deferral_date(905010, 905002, now()::date, 'pub')$$,
    'S-TICKET-006: change_deferral_date is a silent no-op (not an exception) for a ticket whose current status (2, open) is not 60 (deferred)'
);

SELECT lives_ok(
    $$CALL tt.ticket_interface_change_deferral_date(905012, 905002, (now() + interval '1 day')::date, 'pub')$$,
    'S-TICKET-006: change_deferral_date updates status_valid_until_date/last_deferral_date for a ticket that IS currently deferred (status 60)'
);

SELECT is(
    (SELECT status_valid_until_date::date FROM tt.ticket WHERE id = 905012),
    (now() + interval '1 day')::date,
    'S-TICKET-006: change_deferral_date wrote the new p_defer_date onto status_valid_until_date for the deferred ticket'
);

-------------------------------------------------------------------------------
-- change_status / change_status_event_id_out (S-TICKET-007 .. S-TICKET-010)
-------------------------------------------------------------------------------

SELECT throws_ok(
    $$CALL tt.ticket_interface_change_status(905099994, 3, 905002, 'pub')$$,
    'P0002',
    'S-TICKET-007: change_status (pure delegator) propagates change_status_event_id_out''s S-TICKET-008 unhandled NO_DATA_FOUND for a nonexistent p_ticket_id (site #12)'
);

SELECT throws_ok(
    $test2$
    DO $do2$
    DECLARE
        v_event_id numeric;
    BEGIN
        CALL tt.ticket_interface_change_status_event_id_out(v_event_id, 905099993, 3, 905002, 'pub');
    END
    $do2$;
    $test2$,
    'P0002',
    'S-TICKET-008: change_status_event_id_out propagates NO_DATA_FOUND unhandled for a nonexistent p_ticket_id (site #12, 8-column tt.ticket lookup)'
);

SELECT lives_ok(
    $$CALL tt.ticket_interface_change_status(905010, 2, 905002, 'no-op same status')$$,
    'S-TICKET-008: change_status_event_id_out RETURNs immediately (no-op, not an exception) when the new status equals the ticket''s current status'
);

SELECT lives_ok(
    $$CALL tt.ticket_interface_change_status(905010, 3, 905002, 'moved to hot')$$,
    'S-TICKET-009: change_status successfully changes ticket 905010 from open (2) to hot (3), resolving both status names (sites #14-#15) without error'
);

SELECT is(
    (SELECT status_id FROM tt.ticket WHERE id = 905010),
    3::numeric,
    'S-TICKET-009: change_status wrote the new status_id (3, hot) onto the ticket row'
);

-------------------------------------------------------------------------------
-- update_ux_timeout_for_ticket (S-TICKET-011, S-TICKET-012)
-------------------------------------------------------------------------------

SELECT throws_ok(
    $$CALL tt.ticket_interface_update_ux_timeout_for_ticket(905099992, FALSE)$$,
    'P0002',
    NULL,
    'S-TICKET-011: update_ux_timeout_for_ticket propagates NO_DATA_FOUND unhandled for a nonexistent p_ticket_id (site #18, 5-column tt.ticket lookup)'
);

SELECT lives_ok(
    $$CALL tt.ticket_interface_update_ux_timeout_for_ticket(905010, FALSE)$$,
    'S-TICKET-011: update_ux_timeout_for_ticket succeeds for a valid, non-excluded ticket type/status without raising'
);

-------------------------------------------------------------------------------
-- expire_status (S-TICKET-021 -- doc/body disagreement: no change_label call)
-------------------------------------------------------------------------------

SELECT lives_ok(
    $$CALL tt.ticket_interface_expire_status(905019, now()::date, (now() - interval '2 hours')::date, 3, 'hot', 1)$$,
    'S-TICKET-021: expire_status succeeds and forces the ticket to hot (status 3) via change_status alone -- p_label_id is accepted but never read, per the body (not the doc comment) being authoritative'
);

SELECT is(
    (SELECT status_id FROM tt.ticket WHERE id = 905019),
    3::numeric,
    'S-TICKET-021: expire_status forced ticket 905019 to status 3 (hot), exactly as change_status(p_ticket_id, 3, ...) does -- no change_label side effect exists to check'
);

SELECT is(
    (SELECT label_id FROM tt.ticket WHERE id = 905019),
    NULL::bigint,
    'S-TICKET-021: expire_status left label_id untouched (NULL) -- proof that p_label_id=1 was silently ignored, matching the doc/body disagreement this clause records'
);

-------------------------------------------------------------------------------
-- updateTicketFlow (S-TICKET-051)
-------------------------------------------------------------------------------

SELECT throws_ok(
    $$CALL tt.ticket_interface_updateticketflow(905099991)$$,
    'P0002',
    'S-TICKET-051: updateTicketFlow propagates NO_DATA_FOUND unhandled for a nonexistent p_ticket_id (site #77, unconditional tt.ticket lookup) -- site #76''s local NO_DATA_FOUND handler runs first and cannot mask this later, unguarded site'
);

SELECT lives_ok(
    $$CALL tt.ticket_interface_updateticketflow(905018)$$,
    'S-TICKET-051: updateTicketFlow succeeds for a ticket with no currently-open flow entry (site #76''s local NO_DATA_FOUND handler defaults v_flow_id to NULL, a normal no-op, not an error)'
);

SELECT ok(
    (SELECT count(*) FROM tt.ticket_flow WHERE ticket_id = 905018) >= 1,
    'S-TICKET-051: updateTicketFlow inserted a new open ticket_flow row for ticket 905018, which had none before'
);

SELECT lives_ok(
    $$CALL tt.ticket_interface_updateticketflow(905019, 2, now() - interval '1 hour')$$,
    'S-TICKET-051: updateTicketFlow succeeds for ticket 905019, which already has an open flow entry, closing it rather than inserting a second one'
);

-------------------------------------------------------------------------------
-- trigger_escalation (S-TICKET-038 -- swallows, never propagates)
-------------------------------------------------------------------------------

SELECT lives_ok(
    $$CALL tt.ticket_interface_trigger_escalation(905099990, 905002, 905011)$$,
    'S-TICKET-038: trigger_escalation never raises to its caller, even for a nonexistent p_ticket_id, because its own whole-body WHEN OTHERS logs and swallows any internal failure'
);

-------------------------------------------------------------------------------
-- merge_tickets (S-TICKET-034 .. S-TICKET-036) -- cascade/non-cascade proof
-------------------------------------------------------------------------------

SELECT throws_ok(
    $$CALL tt.ticket_interface_merge_tickets(905099989, 905014, 905002)$$,
    'P0002',
    NULL,
    'S-TICKET-034: merge_tickets propagates NO_DATA_FOUND unhandled for a nonexistent source p_ticket_id (site #53, source tt.ticket lookup)'
);

SELECT throws_ok(
    $$CALL tt.ticket_interface_merge_tickets(905013, 905099988, 905002)$$,
    'P0002',
    NULL,
    'S-TICKET-034: merge_tickets propagates NO_DATA_FOUND unhandled for a nonexistent target p_mticket_id (site #55, target tt.ticket lookup)'
);

SELECT lives_ok(
    $$CALL tt.ticket_interface_merge_tickets(905013, 905014, 905002)$$,
    'S-TICKET-035: merge_tickets succeeds merging source ticket 905013 into target ticket 905014 without raising'
);

SELECT is(
    (SELECT status_id FROM tt.ticket WHERE id = 905013),
    110::numeric,
    'S-TICKET-035: the SOURCE ticket does NOT get deleted -- it survives with status 110 (merged)'
);

SELECT is(
    (SELECT merged_into_ticket_id FROM tt.ticket WHERE id = 905013),
    905014::bigint,
    'S-TICKET-035: the SOURCE ticket''s merged_into_ticket_id points at the target after the merge'
);

SELECT is(
    (SELECT status_id FROM tt.ticket WHERE id = 905014),
    3::numeric,
    'S-TICKET-036: as merge_tickets'' VERY LAST statement, the TARGET ticket is forced to status 3 (hot) with a hot-reason mentioning the merge'
);

SELECT is(
    (SELECT partner_reference FROM tt.ticket WHERE id = 905014),
    'src-partner-ref',
    'S-TICKET-035: the source''s partner_reference (''src-partner-ref'') CASCADES onto the target, which had NULL before the merge'
);

SELECT ok(
    (SELECT count(*) FROM tt.event WHERE ticket_id = 905014 AND org_ticket_id = 905013) >= 1,
    'S-TICKET-035: the source ticket''s tt.event rows CASCADE to the target (ticket_id re-pointed, original id preserved in org_ticket_id)'
);

-------------------------------------------------------------------------------
-- deleteTicket (S-TICKET-052) -- cascade/non-cascade proof, both halves
-------------------------------------------------------------------------------

SELECT lives_ok(
    $$CALL tt.ticket_interface_deleteticket(905017)$$,
    'S-TICKET-052: deleteTicket succeeds for ticket 905017, which has events/todo items/docs pages/ratings attached, without raising (no EXCEPTION block exists to swallow a failure -- this call must actually succeed)'
);

SELECT is(
    (SELECT count(*) FROM tt.ticket WHERE id = 905017),
    0::bigint,
    'S-TICKET-052: deleteTicket''s FINAL statement removed the TT.TICKET row itself -- the thing that SHOULD be removed, removed'
);

SELECT is(
    (SELECT count(*) FROM tt.event WHERE ticket_id = 905017),
    0::bigint,
    'S-TICKET-052: deleteTicket removed all tt.event rows for the deleted ticket -- a thing that should cascade, cascaded'
);

SELECT is(
    (SELECT count(*) FROM tt.todo_item WHERE ticket_id = 905017),
    0::bigint,
    'S-TICKET-052: deleteTicket removed all tt.todo_item rows for the deleted ticket'
);

SELECT is(
    (SELECT count(*) FROM tt.ticket_docs_page WHERE ticket_id = 905017),
    0::bigint,
    'S-TICKET-052: deleteTicket removed the ticket_docs_page row for the deleted ticket'
);

SELECT ok(
    (SELECT count(*) FROM stop.company WHERE id = 905001) = 1,
    'S-TICKET-052: deleteTicket does NOT cascade to stop.company -- a table this 31-statement routine never touches survives untouched (the "does NOT cascade" half of the proof)'
);

-------------------------------------------------------------------------------
-- get_next_recent_ticket (S-TICKET-033) -- swallows via whole-function WHEN OTHERS
-------------------------------------------------------------------------------

SELECT lives_ok(
    $$SELECT tt.ticket_interface_get_next_recent_ticket(0, NULL, NULL, NULL)$$,
    'S-TICKET-033: get_next_recent_ticket never raises to its caller (whole-function WHEN OTHERS logs and RETURNs NULL) even in a boundary case with no matching open ticket'
);

SELECT * FROM finish();
ROLLBACK;
