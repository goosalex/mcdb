-- migration/test/pgtap/tt__ticket_interface__selectinto.sql
--
-- pgTAP verification of migration/spec/tt.ticket_interface.md's `### SELECT INTO
-- strictness` table (77 sites) -- the sites NOT already exercised by
-- tt__ticket_interface__lifecycle.sql or tt__ticket_interface__changes.sql. Every
-- site here is driven with zero (or, where reachable, multi-) matching rows, per
-- PITFALLS.md's tell: "test failures on empty-result-set inputs that pass on
-- non-empty inputs (asymmetric coverage is the tell)". RED by construction.
--
-- Every assertion's description begins with the spec clause ID it verifies
-- (HARN-05, trace_lint.py). Source of expected values is
-- migration/spec/tt.ticket_interface.md ONLY (the_one_rule, plan 02-08).
--
-- See .planning/phases/02-spec-method-test-harness-pilot/02-08-SUMMARY.md for
-- the full 77-site reachability ledger (which sites are covered where, which
-- are shadowed by an earlier site in the same call and cannot be independently
-- triggered, and which have no STRICT concern at all and are not required).
--
-- Dangling foreign keys below (orphaned last_public_event_id, status_id,
-- host_id, company_id, type_id, todo_item.ticket_id, etc.) are only
-- constructible because every relevant FK in ddl/migrated/tables/constraints.pg.sql
-- is DEFERRABLE and this file runs SET CONSTRAINTS ALL DEFERRED -- the same
-- idiom tt__osag_notify__selectinto.sql established.

BEGIN;
SET CONSTRAINTS ALL DEFERRED;
SELECT plan(20);

-------------------------------------------------------------------------------
-- Fixtures (907xxx id range).
-------------------------------------------------------------------------------

INSERT INTO stop.company (id, name, short) VALUES (907001, 'Pilot SelectInto Co', 'pltisi1');
INSERT INTO stop.contact (id, lastname, firstname, short, company_id) VALUES (907002, 'Requester', 'Pilot', 'pltisrq', 907001);
INSERT INTO tt.event_type (id, name, source, sms_message_template_id, email_message_template_id)
    VALUES (907006, 'pilot si event type', 1, 1, 2);

-- A host with ONE service; the second host2service row below is the point of the
-- S-TICKET-001 assertion (amended 2026-10-21, TEST-AMENDMENTS A-027): Oracle's unique
-- index MSS.IDX_H2S_HOST_UN (ddl/generated/schema.oracle.sql:3700, confirmed live with
-- ORA-00001) makes a host with two services impossible, so site #2 can never see
-- TOO_MANY_ROWS. schema-fixes/29 adds the index to the PostgreSQL template.
INSERT INTO mss.host (id, name, operating_system_id, service_company_id, author)
    VALUES (907003, 'pilot-si-multisvc-host', 2, 907001, 'pilot');
INSERT INTO mss.service (id, service_type_id, company_id, service_level_id, name) VALUES (907004, 6, 907001, 1, 'pilot-si-svc-a');
INSERT INTO mss.service (id, service_type_id, company_id, service_level_id, name) VALUES (907005, 6, 907001, 1, 'pilot-si-svc-b');
INSERT INTO mss.host2service (host_id, service_id) VALUES (907003, 907004);

-------------------------------------------------------------------------------
-- Site #2 (S-TICKET-001, amended): the schema fact behind the clause -- a second
-- mss.host2service row for one host is refused (23505), exactly as Oracle refuses it
-- (ORA-00001, MSS.IDX_H2S_HOST_UN). newticket_new's plain SELECT INTO at site #2 is
-- therefore a zero-row hazard only (covered in tt__ticket_interface__lifecycle.sql).
-------------------------------------------------------------------------------

SELECT throws_ok(
    $$INSERT INTO mss.host2service (host_id, service_id) VALUES (907003, 907005)$$,
    '23505',
    NULL,
    'S-TICKET-001: a second mss.host2service row for one host is refused by the unique index idx_h2s_host_un (Oracle MSS.IDX_H2S_HOST_UN) -- TOO_MANY_ROWS at site #2 is structurally impossible, as amended'
);

-------------------------------------------------------------------------------
-- Site #13 (S-TICKET-008): change_status_event_id_out's conditional tt.event
-- lookup, reached only when the ticket's last_public_event_id is NOT NULL.
-------------------------------------------------------------------------------

INSERT INTO tt.ticket (id, type_id, status_id, company_id, last_public_event_id)
    VALUES (907010, 1, 2, 907001, 907099999);

SELECT throws_ok(
    $$CALL tt.ticket_interface_change_status(907010, 3, 907002, 'pub')$$,
    'P0002',
    NULL,
    'S-TICKET-008: change_status_event_id_out propagates NO_DATA_FOUND unhandled at site #13 (tt.event lookup) when the ticket''s last_public_event_id points at an event row that does not exist');

-------------------------------------------------------------------------------
-- Site #14 (S-TICKET-009): the NEW status name lookup, by a bad p_status_id.
-------------------------------------------------------------------------------

-- A-009: last_status_change_date added (see 907012 below) -- updateTicketTimeStats runs
-- before site #14 is reached, so a NULL date fails on open_time NOT NULL first.
INSERT INTO tt.ticket (id, type_id, status_id, company_id, last_status_change_date)
    VALUES (907011, 1, 2, 907001, now() - interval '1 hour');

SELECT throws_ok(
    $$CALL tt.ticket_interface_change_status(907011, 907099998, 907002, 'pub')$$,
    'P0002',
    NULL,
    'S-TICKET-009: change_status_event_id_out propagates NO_DATA_FOUND unhandled at site #14 (status name lookup by the NEW p_status_id) for a nonexistent status id'
);

-------------------------------------------------------------------------------
-- Site #15 (S-TICKET-009): the CURRENT status name lookup, when the ticket's
-- OWN status_id is orphaned (a real, if narrow, path -- tt.status has no
-- immediate/non-deferrable FK enforcement preventing this at write time).
-------------------------------------------------------------------------------

-- A-009: last_status_change_date added -- newticket_new always sets it; without it the
-- routine fails in updateTicketTimeStats before reaching site #15 (same class as A-008).
INSERT INTO tt.ticket (id, type_id, status_id, company_id, last_status_change_date)
    VALUES (907012, 1, 907099997, 907001, now() - interval '1 hour');

SELECT throws_ok(
    $$CALL tt.ticket_interface_change_status(907012, 3, 907002, 'pub')$$,
    'P0002',
    NULL,
    'S-TICKET-009: change_status_event_id_out propagates NO_DATA_FOUND unhandled at site #15 (status name lookup by the ticket''s OWN, orphaned, CURRENT status_id) even though the NEW status (3) resolves fine');

-------------------------------------------------------------------------------
-- Site #20 (S-TICKET-012): the ROWNUM=1-must-become-LIMIT-1 site. Only the
-- single-row (count>0) positive case is independently constructible in THIS
-- schema: ddl/migrated's tt.service_window carries `CREATE UNIQUE INDEX
-- ticket_id_uk1 ON tt.service_window (ticket_id)` (an immediate, non-deferrable
-- unique index, unlike every FK in this file), so a genuine multi-row fixture
-- for this site cannot be constructed at all -- recorded in the SUMMARY's
-- reachability ledger as a schema-driven limitation, not a gap in this suite.
-------------------------------------------------------------------------------

INSERT INTO tt.ticket (id, type_id, status_id, company_id) VALUES (907013, 12, 2, 907001);
INSERT INTO tt.service_window (id, ticket_id, start_date, end_date, company_id)
    VALUES (907014, 907013, now() - interval '1 hour', now() + interval '1 hour', 907001);

SELECT lives_ok(
    $$CALL tt.ticket_interface_update_ux_timeout_for_ticket(907013, FALSE)$$,
    'S-TICKET-012: update_ux_timeout_for_ticket succeeds for a maintenance ticket (type 12) with exactly one service_window row -- site #20''s ROWNUM=1-translated-as-LIMIT-1 requirement must not spuriously raise TOO_MANY_ROWS for the single-row case Oracle always saw'
);

-------------------------------------------------------------------------------
-- Site #32 (S-TICKET-020): change_label 3/4-arg overload's OLD label lookup,
-- reached only when the ticket's current label_id is NOT NULL but orphaned.
-------------------------------------------------------------------------------

INSERT INTO tt.ticket (id, type_id, status_id, company_id, label_id) VALUES (907015, 1, 2, 907001, 907099996);

SELECT throws_ok(
    $$CALL tt.ticket_interface_change_label(907015, 3, 907002)$$,
    'P0002',
    NULL,
    'S-TICKET-020: the 3/4-arg change_label overload propagates NO_DATA_FOUND unhandled at site #32 (OLD label lookup) when the ticket''s current label_id is orphaned');

-------------------------------------------------------------------------------
-- Site #33 (S-TICKET-020): the NEW label lookup, by a bad p_label_id.
-------------------------------------------------------------------------------

INSERT INTO tt.ticket (id, type_id, status_id, company_id) VALUES (907016, 1, 2, 907001);

SELECT throws_ok(
    $$CALL tt.ticket_interface_change_label(907016, 907099995, 907002)$$,
    'P0002',
    NULL,
    'S-TICKET-020: the 3/4-arg change_label overload propagates NO_DATA_FOUND unhandled at site #33 (NEW label lookup) for a nonexistent p_label_id'
);

-------------------------------------------------------------------------------
-- Site #36 (S-TICKET-023): change_owner's ELSE branch (p_owner_id NULL, no
-- Zitadel names), reached only for a nonexistent p_ticket_id.
-------------------------------------------------------------------------------

SELECT throws_ok(
    $$CALL tt.ticket_interface_change_owner(907099994, NULL, 907002)$$,
    'P0002',
    NULL,
    'S-TICKET-023: change_owner propagates NO_DATA_FOUND unhandled at site #36 (ELSE branch, tt.ticket lookup) for a nonexistent p_ticket_id when p_owner_id is NULL and no Zitadel names are supplied'
);

-------------------------------------------------------------------------------
-- Site #38 (S-TICKET-024): change_company's OLD host name lookup, reached only
-- when the ticket's CURRENT host_id is NOT NULL but orphaned.
-------------------------------------------------------------------------------

INSERT INTO tt.ticket (id, type_id, status_id, company_id, host_id) VALUES (907017, 1, 2, 907001, 907099993);

SELECT throws_ok(
    $$CALL tt.ticket_interface_change_company(907017, 907001, 907002)$$,
    'P0002',
    NULL,
    'S-TICKET-024: change_company propagates NO_DATA_FOUND unhandled at site #38 (OLD host name lookup) when the ticket''s current host_id is orphaned');

-------------------------------------------------------------------------------
-- Site #39 (S-TICKET-024): change_company's OLD company short-name lookup,
-- reached only when the ticket's CURRENT company_id is NOT NULL but orphaned.
-------------------------------------------------------------------------------

-- A-009: the orphan value belongs in company_id (this is the OLD-company lookup, site
-- #39), not in status_id; status_id must be a real status (2) so site #15 passes first.
INSERT INTO tt.ticket (id, type_id, status_id, company_id) VALUES (907018, 1, 2, 907099992);

SELECT throws_ok(
    $$CALL tt.ticket_interface_change_company(907018, 907001, 907002)$$,
    'P0002',
    NULL,
    'S-TICKET-024: change_company propagates NO_DATA_FOUND unhandled at site #39 (OLD company short-name lookup) when the ticket''s current company_id is orphaned');

-------------------------------------------------------------------------------
-- Site #43 (S-TICKET-030): change_type's OLD type-name lookup, reached for a
-- VALID ticket whose current type_id is orphaned -- "structurally
-- near-impossible for a live ticket" per the spec, but NOT schema-forbidden,
-- and genuinely constructible here since ticket_fk1 is deferrable.
-------------------------------------------------------------------------------

INSERT INTO tt.ticket (id, type_id, status_id, company_id) VALUES (907019, 907099991, 2, 907001);

SELECT throws_ok(
    $test11$
    DO $do11$
    DECLARE v_event_id numeric;
    BEGIN
        CALL tt.ticket_interface_change_type(v_event_id, 907019, 2, 907002);
    END
    $do11$;
    $test11$,
    'P0002',
    NULL,
    'S-TICKET-030: change_type propagates NO_DATA_FOUND unhandled at site #43 (OLD type-name lookup) for a ticket whose current type_id is orphaned -- reachable despite the spec calling this "structurally near-impossible for a live ticket", since it is not schema-forbidden'
);

-------------------------------------------------------------------------------
-- Site #44 (S-TICKET-030): the NEW type-name lookup, by a bad p_type_id.
-------------------------------------------------------------------------------

INSERT INTO tt.ticket (id, type_id, status_id, company_id) VALUES (907020, 1, 2, 907001);

SELECT throws_ok(
    $test12$
    DO $do12$
    DECLARE v_event_id numeric;
    BEGIN
        CALL tt.ticket_interface_change_type(v_event_id, 907020, 907099990, 907002);
    END
    $do12$;
    $test12$,
    'P0002',
    NULL,
    'S-TICKET-030: change_type propagates NO_DATA_FOUND unhandled at site #44 (NEW type-name lookup) for a nonexistent p_type_id');

-------------------------------------------------------------------------------
-- Sites #54 / #56 (S-TICKET-034): merge_tickets' conditional tt.event lookups,
-- reached only when the source/target ticket's last_public_event_id is
-- NOT NULL but orphaned.
-------------------------------------------------------------------------------

INSERT INTO tt.ticket (id, type_id, status_id, company_id, last_public_event_id) VALUES (907021, 1, 2, 907001, 907099989);
INSERT INTO tt.ticket (id, type_id, status_id, company_id) VALUES (907022, 1, 2, 907001);

SELECT throws_ok(
    $$CALL tt.ticket_interface_merge_tickets(907021, 907022, 907002)$$,
    'P0002',
    NULL,
    'S-TICKET-034: merge_tickets propagates NO_DATA_FOUND unhandled at site #54 (source ticket''s conditional tt.event lookup) when the SOURCE''s last_public_event_id is orphaned');

INSERT INTO tt.ticket (id, type_id, status_id, company_id) VALUES (907023, 1, 2, 907001);
INSERT INTO tt.ticket (id, type_id, status_id, company_id, last_public_event_id) VALUES (907024, 1, 2, 907001, 907099988);

SELECT throws_ok(
    $$CALL tt.ticket_interface_merge_tickets(907023, 907024, 907002)$$,
    'P0002',
    NULL,
    'S-TICKET-034: merge_tickets propagates NO_DATA_FOUND unhandled at site #56 (target ticket''s conditional tt.event lookup) when the TARGET''s last_public_event_id is orphaned');

-------------------------------------------------------------------------------
-- Site #61 (S-TICKET-054): handleDeferredTransitions, reached only when
-- change_status_event_id_out transitions a ticket INTO or OUT OF deferred
-- (status 60) -- a branch neither lifecycle.sql nor changes.sql exercises
-- (their own change_status calls never cross the deferred boundary).
-------------------------------------------------------------------------------

-- A-009: last_status_change_date added (see 907012 above).
INSERT INTO tt.ticket (id, type_id, status_id, company_id, last_status_change_date)
    VALUES (907025, 1, 2, 907001, now() - interval '1 hour');

SELECT lives_ok(
    $$CALL tt.ticket_interface_change_status(907025, 60, 907002, 'deferring this ticket')$$,
    'S-TICKET-054: change_status_event_id_out succeeds transitioning ticket 907025 INTO deferred (status 60), which calls the private handleDeferredTransitions -- its own whole-body WHEN OTHERS would swallow any internal failure there rather than let it propagate, so this call is expected to succeed outright'
);

-------------------------------------------------------------------------------
-- Site #66 (S-TICKET-045): remove_related_file's conditional mc.mc_file
-- lookup, reached when an orphaned ticket2mc_file relation references a
-- mc_file row that no longer exists. Oracle's whole-routine WHEN OTHERS
-- swallowed it; since the Q11 (d) correction (S-TICKET-060) the mirrored
-- NO_DATA_FOUND arm swallows it -- either way nothing propagates
-- (TEST-AMENDMENTS.md A-018: label only, assertion unchanged).
-------------------------------------------------------------------------------

INSERT INTO tt.ticket (id, type_id, status_id, company_id) VALUES (907026, 1, 2, 907001);
INSERT INTO tt.ticket2mc_file (ticket_id, mc_file_id) VALUES (907026, 907099987);

SELECT lives_ok(
    $$CALL tt.ticket_interface_remove_related_file(907026, 907099987, 907002)$$,
    'S-TICKET-045: remove_related_file succeeds (swallowed -- Oracle via WHEN OTHERS, the corrected translation via its mirrored NO_DATA_FOUND arm; nothing propagates) at site #66 when the ticket2mc_file relation exists but the mc_file row it references is orphaned'
);

-------------------------------------------------------------------------------
-- Site #71 (S-TICKET-050): update_todo_item_status' SECOND tt.ticket lookup,
-- reached only when the todo_item ITSELF resolves (site #70 succeeds) but the
-- ticket it (deferred-FK) references does not -- otherwise unreachable
-- through the same call, since site #70's join already requires a matching
-- ticket_id/seq_no pair.
-------------------------------------------------------------------------------

INSERT INTO tt.todo_item (id, ticket_id, seq_no, details, todo_item_status_id, is_public)
    VALUES (907027, 907099986, 1, 'pilot orphaned-ticket todo', 1, 1);

SELECT throws_ok(
    $$CALL tt.ticket_interface_update_todo_item_status(907099986, 1, 2, 907002)$$,
    'P0002',
    NULL,
    'S-TICKET-050: update_todo_item_status propagates NO_DATA_FOUND unhandled at site #71 (SECOND tt.ticket lookup) when the todo item itself resolves (site #70 succeeds) but its ticket_id is orphaned -- constructible only via a deferred FK, since site #70''s own join otherwise shadows this site for an ordinary nonexistent ticket'
);

-------------------------------------------------------------------------------
-- Site #72 (S-TICKET-050): the NEW status-name lookup, by a bad
-- p_todo_item_status_id.
-------------------------------------------------------------------------------

INSERT INTO tt.ticket (id, type_id, status_id, company_id) VALUES (907028, 1, 2, 907001);
INSERT INTO tt.todo_item (id, ticket_id, seq_no, details, todo_item_status_id, is_public)
    VALUES (907029, 907028, 1, 'pilot real todo', 1, 1);

SELECT throws_ok(
    $$CALL tt.ticket_interface_update_todo_item_status(907028, 1, 907099985, 907002)$$,
    'P0002',
    NULL,
    'S-TICKET-050: update_todo_item_status propagates NO_DATA_FOUND unhandled at site #72 (NEW status-name lookup) for a nonexistent p_todo_item_status_id'
);

-------------------------------------------------------------------------------
-- Site #73 (S-TICKET-055): updateTicketTimeStats' first-time-write path,
-- reached only via change_status_event_id_out transitioning a ticket INTO one
-- of the specific statuses {2,11,12,60,61,101} -- neither lifecycle.sql nor
-- changes.sql transitions any ticket into this set.
-------------------------------------------------------------------------------

-- A-009: status 4 -> 2: every sibling fixture starts at 2 (open); 4 is not in the
-- tracked-transition set {2,11,12,60,61,101}, so updateTicketTimeStats had nothing to
-- write and the "created a NEW row" assertion could never pass. last_status_change_date
-- added for the same reason as 907012.
INSERT INTO tt.ticket (id, type_id, status_id, company_id, last_status_change_date)
    VALUES (907030, 1, 2, 907001, now() - interval '1 hour');

SELECT lives_ok(
    $$CALL tt.ticket_interface_change_status(907030, 11, 907002, 'moving to waiting')$$,
    'S-TICKET-055: change_status_event_id_out succeeds transitioning ticket 907030 into status 11 (waiting), triggering updateTicketTimeStats'' first-ever-write path (site #73''s local NO_DATA_FOUND handler, then the race-avoiding MERGE, then the re-SELECT at site #75)'
);

SELECT ok(
    (SELECT count(*) FROM tt.ticket_time_statistic WHERE ticket_id = 907030) >= 1,
    'S-TICKET-055: updateTicketTimeStats created a NEW tt.ticket_time_statistic row for ticket 907030''s first-ever status-time write'
);

SELECT * FROM finish();
ROLLBACK;
