-- migration/test/pgtap/tt__escalation_interface__spec.sql
--
-- pgTAP verification for migration/spec/tt.escalation_interface.md. RED by construction:
-- none of tt.escalation_interface_* exists yet. Every assertion's description starts
-- with the spec clause ID it verifies (HARN-05, trace_lint.py). Source of expected
-- values is the SPEC only -- never pg_migration/output/, never a PL/pgSQL translation.
--
-- Two clauses (S-ESC-008, S-ESC-014) assert CORRECTED behaviour, not Oracle's: the
-- Oracle body "escalates" a nonexistent event silently (see the spec for the line-by-
-- line trace). The tests below pin the corrected contract: plog.err + RETURN, no data
-- side effect, no exception.
--
-- Fixture-initial values are always chosen to DIFFER from the post-CALL expected value
-- where the clause claims a change, and every "did NOT happen" assertion sits next to a
-- lives_ok proving the CALL actually ran (PITFALLS.md's asymmetric-coverage tell).
-- Pilot-owned rows use the 908xxx id range (disjoint from 9001xx osag_notify, 9006xx
-- event_interface, 905xxx ticket_interface).

BEGIN;
SET CONSTRAINTS ALL DEFERRED;
SELECT plan(74);

-------------------------------------------------------------------------------
-- S-ESC-001: all five routines exist as PostgreSQL PROCEDUREs (prokind='p'), the only
-- shape exec_event_type_actions' dynamic `CALL %I.%I($1)` can reach.
-------------------------------------------------------------------------------

SELECT ok(
    EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname = 'tt' AND p.proname = 'escalation_interface_escalate_os' AND p.prokind = 'p'),
    'S-ESC-001: tt.escalation_interface_escalate_os exists as a PostgreSQL PROCEDURE (prokind=p)'
);
SELECT ok(
    EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname = 'tt' AND p.proname = 'escalation_interface_escalate_customer' AND p.prokind = 'p'),
    'S-ESC-001: tt.escalation_interface_escalate_customer exists as a PostgreSQL PROCEDURE (prokind=p)'
);
SELECT ok(
    EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname = 'tt' AND p.proname = 'escalation_interface_escalate_isp_outage_to_os' AND p.prokind = 'p'),
    'S-ESC-001: tt.escalation_interface_escalate_isp_outage_to_os exists as a PostgreSQL PROCEDURE (prokind=p)'
);
SELECT ok(
    EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname = 'tt' AND p.proname = 'escalation_interface_nop' AND p.prokind = 'p'),
    'S-ESC-001: tt.escalation_interface_nop exists as a PostgreSQL PROCEDURE (prokind=p)'
);
SELECT ok(
    EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname = 'tt' AND p.proname = 'escalation_interface_clear_customer_escalation' AND p.prokind = 'p'),
    'S-ESC-001: tt.escalation_interface_clear_customer_escalation exists as a PostgreSQL PROCEDURE (prokind=p)'
);

-------------------------------------------------------------------------------
-- Fixtures. Reference rows reused from the template's masterdata: tt.status 2,
-- tt.ticket_type 1, tt.event_type 10001/30005/60001, tt.event_action 1
-- (= tt.escalation_interface.escalate_os), tt.escalation_status 0/10/11/20,
-- mss.operating_system 2, mss.service_component 27. mss.host and stop.company are NOT
-- in masterdata -- pilot-owned rows below. stop.company.short carries a
-- lower(short)=short CHECK; a NULL short passes it (used for S-ESC-018's NULL-concat
-- case).
-------------------------------------------------------------------------------

INSERT INTO stop.company (id, name, short) VALUES (908001, 'Pilot Esc Service Co', 'pltesc1');
INSERT INTO stop.company (id, name, short) VALUES (908002, 'Pilot Esc Ticket Co', 'pltesc2');
INSERT INTO stop.company (id, name, short) VALUES (908003, 'Pilot Esc No-Short Co', NULL);

INSERT INTO mss.host (id, name, operating_system_id, service_company_id, author, active)
    VALUES (908010, 'pilot-esc-active', 2, 908001, 'pilot', 1);
INSERT INTO mss.host (id, name, operating_system_id, service_company_id, author, active)
    VALUES (908011, 'pilot-esc-inactive', 2, 908001, 'pilot', 0);
INSERT INTO mss.host (id, name, operating_system_id, service_company_id, author, active)
    VALUES (908012, 'pilot-esc-noshort', 2, 908003, 'pilot', 1);

-- A pilot-owned event type, mapped to event_action 1 (escalate_os) for the dispatch
-- test. Outside is_esc_supp_active's 10002/10005/10007/10009 set, so no service-window
-- suppression can engage. tt.event_type_action is empty in masterdata.
INSERT INTO tt.event_type (id, name, source, sms_message_template_id, email_message_template_id)
    VALUES (908020, 'pilot esc dispatch type', 1, 1, 2);
INSERT INTO tt.event_type_action (event_action_id, event_type_id) VALUES (1, 908020);

-- escalate_os tickets (one event each; event type 10001 = connection down, masterdata).
-- last_status_change_date is set on every ticket (A-008 precedent).
INSERT INTO tt.ticket (id, type_id, status_id, company_id, host_id, escalation_status_id, last_status_change_date)
    VALUES (908100, 1, 2, 908001, 908010, 0, now() - interval '1 hour');   -- active host, status 0
INSERT INTO tt.ticket (id, type_id, status_id, company_id, host_id, escalation_status_id, last_status_change_date)
    VALUES (908101, 1, 2, 908001, 908010, 10, now() - interval '1 hour');  -- already in OS escalation
INSERT INTO tt.ticket (id, type_id, status_id, company_id, host_id, escalation_status_id, last_status_change_date)
    VALUES (908102, 1, 2, 908001, 908010, 11, now() - interval '1 hour');  -- pikett failed
INSERT INTO tt.ticket (id, type_id, status_id, company_id, host_id, escalation_status_id, last_status_change_date)
    VALUES (908103, 1, 2, 908001, NULL, 0, now() - interval '1 hour');     -- NO host
INSERT INTO tt.ticket (id, type_id, status_id, company_id, host_id, escalation_status_id, last_status_change_date)
    VALUES (908104, 1, 2, 908001, 908011, 0, now() - interval '1 hour');   -- INACTIVE host
INSERT INTO tt.ticket (id, type_id, status_id, company_id, host_id, escalation_status_id, last_status_change_date)
    VALUES (908105, 1, 2, 908001, 908010, 20, now() - interval '1 hour');  -- customer escalation
INSERT INTO tt.ticket (id, type_id, status_id, company_id, host_id, escalation_status_id, last_status_change_date)
    VALUES (908106, 1, 2, 908001, 908099, 0, now() - interval '1 hour');   -- host_id with NO mss.host row (FK deferred)
INSERT INTO tt.ticket (id, type_id, status_id, company_id, host_id, escalation_status_id, last_status_change_date)
    VALUES (908107, 1, 102, 908001, 908010, 0, now() - interval '1 hour'); -- CLOSED ticket
INSERT INTO tt.event (id, type_id, ticket_id, host_id) VALUES (908200, 10001, 908100, 908010);
INSERT INTO tt.event (id, type_id, ticket_id, host_id) VALUES (908201, 10001, 908101, 908010);
INSERT INTO tt.event (id, type_id, ticket_id, host_id) VALUES (908202, 10001, 908102, 908010);
INSERT INTO tt.event (id, type_id, ticket_id, host_id) VALUES (908203, 10001, 908103, NULL);
INSERT INTO tt.event (id, type_id, ticket_id, host_id) VALUES (908204, 10001, 908104, 908011);
INSERT INTO tt.event (id, type_id, ticket_id, host_id) VALUES (908205, 10001, 908105, 908010);
INSERT INTO tt.event (id, type_id, ticket_id, host_id) VALUES (908206, 10001, 908106, NULL);
INSERT INTO tt.event (id, type_id, ticket_id, host_id) VALUES (908207, 10001, 908107, 908010);

-- escalate_customer tickets.
INSERT INTO tt.ticket (id, type_id, status_id, company_id, host_id, escalation_status_id, last_status_change_date)
    VALUES (908110, 1, 2, 908001, 908010, 0, now() - interval '1 hour');   -- active host, status 0
INSERT INTO tt.ticket (id, type_id, status_id, company_id, host_id, escalation_status_id, last_status_change_date)
    VALUES (908111, 1, 2, 908001, 908010, 20, now() - interval '1 hour');  -- customer escalation -> blocks
INSERT INTO tt.ticket (id, type_id, status_id, company_id, host_id, escalation_status_id, last_status_change_date)
    VALUES (908112, 1, 2, 908001, 908010, 10, now() - interval '1 hour');  -- OS escalation -> blocks
INSERT INTO tt.ticket (id, type_id, status_id, company_id, host_id, escalation_status_id, last_status_change_date)
    VALUES (908113, 1, 2, 908001, 908011, 0, now() - interval '1 hour');   -- INACTIVE host
INSERT INTO tt.ticket (id, type_id, status_id, company_id, host_id, escalation_status_id, last_status_change_date)
    VALUES (908114, 1, 2, 908001, NULL, 0, now() - interval '1 hour');     -- NO host
INSERT INTO tt.ticket (id, type_id, status_id, company_id, host_id, escalation_status_id, last_status_change_date)
    VALUES (908115, 1, 102, 908001, 908010, 0, now() - interval '1 hour'); -- CLOSED ticket
INSERT INTO tt.event (id, type_id, ticket_id, host_id) VALUES (908210, 10001, 908110, 908010);
INSERT INTO tt.event (id, type_id, ticket_id, host_id) VALUES (908211, 10001, 908111, 908010);
INSERT INTO tt.event (id, type_id, ticket_id, host_id) VALUES (908212, 10001, 908112, 908010);
INSERT INTO tt.event (id, type_id, ticket_id, host_id) VALUES (908213, 10001, 908113, 908011);
INSERT INTO tt.event (id, type_id, ticket_id, host_id) VALUES (908214, 10001, 908114, NULL);
INSERT INTO tt.event (id, type_id, ticket_id, host_id) VALUES (908215, 10001, 908115, 908010);

-- escalate_isp_outage_to_os: original tickets + ISP outage events (type 10003).
INSERT INTO tt.ticket (id, type_id, status_id, company_id, host_id, escalation_status_id, last_status_change_date)
    VALUES (908120, 4, 2, 908002, 908010, 0, now() - interval '1 hour');   -- ticket company pltesc2, host pltesc1
INSERT INTO tt.ticket (id, type_id, status_id, company_id, host_id, escalation_status_id, last_status_change_date)
    VALUES (908121, 4, 2, NULL, NULL, 0, now() - interval '1 hour');       -- no company, no host on the ticket
INSERT INTO tt.ticket (id, type_id, status_id, company_id, host_id, escalation_status_id, last_status_change_date)
    VALUES (908122, 4, 2, 908001, NULL, 0, now() - interval '1 hour');     -- no host anywhere
INSERT INTO tt.event (id, type_id, ticket_id, host_id, company_id, eventdate)
    VALUES (908220, 10003, 908120, NULL, NULL, '2024-03-05 14:07:09');     -- falls back to ticket host + ticket company
INSERT INTO tt.event (id, type_id, ticket_id, host_id, company_id, eventdate)
    VALUES (908221, 10003, 908121, 908012, NULL, '2024-03-05 14:07:10');   -- event host whose service company has NULL short
INSERT INTO tt.event (id, type_id, ticket_id, host_id, company_id, eventdate)
    VALUES (908222, 10003, 908120, NULL, 908001, '2024-03-05 14:07:11');   -- event company wins over ticket company
INSERT INTO tt.event (id, type_id, ticket_id, host_id, company_id, eventdate)
    VALUES (908223, 10003, 908122, NULL, NULL, '2024-03-05 14:07:12');     -- no host on event or ticket

-- clear_customer_escalation tickets.
INSERT INTO tt.ticket (id, type_id, status_id, company_id, escalation_status_id, last_escalation_date, last_status_change_date)
    VALUES (908130, 1, 2, 908001, 20, '2020-01-01 00:00:00', now() - interval '1 hour');
INSERT INTO tt.ticket (id, type_id, status_id, company_id, escalation_status_id, last_escalation_date, last_status_change_date)
    VALUES (908131, 1, 2, 908001, 10, '2020-01-01 00:00:00', now() - interval '1 hour');

-- dispatch integration: ticket + event of the mapped pilot type.
INSERT INTO tt.ticket (id, type_id, status_id, company_id, host_id, escalation_status_id, last_status_change_date)
    VALUES (908150, 1, 2, 908001, 908010, 0, now() - interval '1 hour');
INSERT INTO tt.event (id, type_id, ticket_id, host_id) VALUES (908250, 908020, 908150, NULL);

-------------------------------------------------------------------------------
-- escalate_os
-------------------------------------------------------------------------------

-- S-ESC-004: the happy path -- active host, status 0.
SELECT lives_ok(
    $$CALL tt.escalation_interface_escalate_os(908200)$$,
    'S-ESC-004: escalate_os succeeds for an event on a status-0 ticket with an active host'
);
SELECT is(
    (SELECT escalation_status_id FROM tt.ticket WHERE id = 908100),
    10::numeric,
    'S-ESC-004: escalate_os sets escalation_status_id = 10 (fixture started at 0)'
);
SELECT ok(
    (SELECT last_escalation_date FROM tt.ticket WHERE id = 908100) IS NOT NULL,
    'S-ESC-004: escalate_os stamps last_escalation_date (fixture started NULL)'
);
SELECT is(
    (SELECT count(*) FROM tt.event
     WHERE ticket_id = 908100 AND type_id = 60001 AND host_id = 908010
       AND details_public = 'Starting escalation to Open Systems Mission Control'
       AND details_private = 'Event added by tt.escalation_interface.escalate_os. Caused by event 908200'),
    1::bigint,
    'S-ESC-004: escalate_os adds exactly one 60001 event carrying the ticket host and the Oracle-verbatim public/private texts naming the causing event'
);

-- S-ESC-003: already in OS escalation (10 / 11) -> immediate return, no event.
SELECT lives_ok(
    $$CALL tt.escalation_interface_escalate_os(908201)$$,
    'S-ESC-003: escalate_os returns without error for a ticket already in escalation status 10'
);
SELECT is(
    (SELECT count(*) FROM tt.event WHERE ticket_id = 908101 AND type_id = 60001),
    0::bigint,
    'S-ESC-003: escalate_os adds NO 60001 event for a ticket already in escalation status 10'
);
SELECT lives_ok(
    $$CALL tt.escalation_interface_escalate_os(908202)$$,
    'S-ESC-003: escalate_os returns without error for a ticket in escalation status 11'
);
SELECT is(
    (SELECT count(*) FROM tt.event WHERE ticket_id = 908102 AND type_id = 60001),
    0::bigint,
    'S-ESC-003: escalate_os adds NO 60001 event for a ticket in escalation status 11 (pikett failed)'
);
SELECT is(
    (SELECT escalation_status_id FROM tt.ticket WHERE id = 908102),
    11::numeric,
    'S-ESC-003: escalate_os leaves a status-11 ticket at 11 -- the 10/11 gate fires before any UPDATE'
);

-- S-ESC-005: no host at all -> escalated anyway, event carries host_id NULL.
SELECT lives_ok(
    $$CALL tt.escalation_interface_escalate_os(908203)$$,
    'S-ESC-005: escalate_os succeeds for a ticket with NO host'
);
SELECT is(
    (SELECT escalation_status_id FROM tt.ticket WHERE id = 908103),
    10::numeric,
    'S-ESC-005: escalate_os escalates a ticket with NO host ("if no host was specified we need escalation anyway")'
);
SELECT is(
    (SELECT count(*) FROM tt.event WHERE ticket_id = 908103 AND type_id = 60001 AND host_id IS NULL),
    1::bigint,
    'S-ESC-005: the 60001 event for a host-less ticket carries host_id NULL'
);

-- S-ESC-005 (second half): host_id set but no mss.host row -> treated as no host.
SELECT lives_ok(
    $$CALL tt.escalation_interface_escalate_os(908206)$$,
    'S-ESC-005: escalate_os succeeds for a ticket whose host_id has no mss.host row'
);
SELECT is(
    (SELECT escalation_status_id FROM tt.ticket WHERE id = 908106),
    10::numeric,
    'S-ESC-005: escalate_os escalates a ticket whose host row is missing (NO_DATA_FOUND on mss.host -> v_host_id := NULL -> escalate)'
);
SELECT is(
    (SELECT count(*) FROM tt.event WHERE ticket_id = 908106 AND type_id = 60001 AND host_id IS NULL),
    1::bigint,
    'S-ESC-005: the 60001 event for a missing-host ticket carries host_id NULL, not the dangling id'
);

-- S-ESC-006: inactive host -> nothing happens.
SELECT lives_ok(
    $$CALL tt.escalation_interface_escalate_os(908204)$$,
    'S-ESC-006: escalate_os returns without error for a ticket whose host is inactive'
);
SELECT is(
    (SELECT escalation_status_id FROM tt.ticket WHERE id = 908104),
    0::numeric,
    'S-ESC-006: escalate_os leaves escalation_status_id at 0 for an inactive host'
);
SELECT is(
    (SELECT count(*) FROM tt.event WHERE ticket_id = 908104 AND type_id = 60001),
    0::bigint,
    'S-ESC-006: escalate_os adds NO 60001 event for an inactive host'
);

-- S-ESC-007: customer escalation (20) is overridden to OS escalation.
SELECT lives_ok(
    $$CALL tt.escalation_interface_escalate_os(908205)$$,
    'S-ESC-007: escalate_os succeeds for a ticket in customer escalation (20)'
);
SELECT is(
    (SELECT escalation_status_id FROM tt.ticket WHERE id = 908105),
    10::numeric,
    'S-ESC-007: escalate_os overrides escalation status 20 (customer) to 10 (OS) -- only 10/11 block it'
);
SELECT is(
    (SELECT count(*) FROM tt.event WHERE ticket_id = 908105 AND type_id = 60001),
    1::bigint,
    'S-ESC-007: escalate_os adds the 60001 event when overriding a customer escalation'
);

-- S-ESC-008 (CORRECTED): nonexistent event -> plog.err + RETURN, no exception, no data.
SELECT lives_ok(
    $$CALL tt.escalation_interface_escalate_os(908999999)$$,
    'S-ESC-008: escalate_os does NOT raise for a nonexistent event id (corrected: log + return)'
);
SELECT ok(
    (SELECT count(*) FROM osag.plog_stub_log
     WHERE levelname = 'ERR'
       AND message LIKE 'tt.escalation_interface.escalate_os(): event with id 908999999 or its ticket not found.%') >= 1,
    'S-ESC-008: escalate_os logs an ERR "event with id 908999999 or its ticket not found" via plog.err for a nonexistent event'
);
SELECT is(
    (SELECT count(*) FROM tt.event WHERE type_id = 60001 AND details_private LIKE '%Caused by event 908999999'),
    0::bigint,
    'S-ESC-008: escalate_os adds NO 60001 event for a nonexistent event (Oracle would call addevent_new with a NULL ticket)'
);

-- S-ESC-009: addevent_new's ticket_closed propagates out of escalate_os unhandled.
SELECT throws_like(
    $$CALL tt.escalation_interface_escalate_os(908207)$$,
    '%closed%',
    'S-ESC-009: escalate_os propagates addevent_new''s ticket_closed error for a closed (status 102) ticket -- no handler of its own'
);

-------------------------------------------------------------------------------
-- escalate_customer
-------------------------------------------------------------------------------

-- S-ESC-012: body escalates to OS (10 / 60001) despite the "customer" name.
SELECT lives_ok(
    $$CALL tt.escalation_interface_escalate_customer(908210)$$,
    'S-ESC-012: escalate_customer succeeds for an event on a status-0 ticket with an active host'
);
SELECT is(
    (SELECT escalation_status_id FROM tt.ticket WHERE id = 908110),
    10::numeric,
    'S-ESC-012: escalate_customer sets escalation_status_id = 10 (NOT 20 -- the body, not the comment, is authoritative)'
);
SELECT ok(
    (SELECT last_escalation_date FROM tt.ticket WHERE id = 908110) IS NOT NULL,
    'S-ESC-012: escalate_customer stamps last_escalation_date'
);
SELECT is(
    (SELECT count(*) FROM tt.event
     WHERE ticket_id = 908110 AND type_id = 60001 AND host_id = 908010
       AND details_public = 'Starting escalation to Open Systems Mission Control'
       AND details_private = 'Event added by tt.escalation_interface.escalate_customer. Caused by event 908210'),
    1::bigint,
    'S-ESC-012: escalate_customer adds exactly one 60001 event (NOT 60101) with the escalate_customer-specific private text'
);

-- S-ESC-011: ANY non-zero status blocks escalate_customer, including 20.
SELECT lives_ok(
    $$CALL tt.escalation_interface_escalate_customer(908211)$$,
    'S-ESC-011: escalate_customer returns without error for a ticket in escalation status 20'
);
SELECT is(
    (SELECT escalation_status_id FROM tt.ticket WHERE id = 908111),
    20::numeric,
    'S-ESC-011: escalate_customer leaves a status-20 ticket at 20 (unlike escalate_os, 20 blocks it)'
);
SELECT is(
    (SELECT count(*) FROM tt.event WHERE ticket_id = 908111 AND type_id = 60001),
    0::bigint,
    'S-ESC-011: escalate_customer adds NO event for a status-20 ticket'
);
SELECT lives_ok(
    $$CALL tt.escalation_interface_escalate_customer(908212)$$,
    'S-ESC-011: escalate_customer returns without error for a ticket in escalation status 10'
);
SELECT is(
    (SELECT count(*) FROM tt.event WHERE ticket_id = 908112 AND type_id = 60001),
    0::bigint,
    'S-ESC-011: escalate_customer adds NO event for a status-10 ticket'
);

-- S-ESC-013: inactive host -> nothing.
SELECT lives_ok(
    $$CALL tt.escalation_interface_escalate_customer(908213)$$,
    'S-ESC-013: escalate_customer returns without error for an inactive host'
);
SELECT is(
    (SELECT escalation_status_id FROM tt.ticket WHERE id = 908113),
    0::numeric,
    'S-ESC-013: escalate_customer leaves escalation_status_id at 0 for an inactive host'
);
SELECT is(
    (SELECT count(*) FROM tt.event WHERE ticket_id = 908113 AND type_id = 60001),
    0::bigint,
    'S-ESC-013: escalate_customer adds NO event for an inactive host'
);

-- S-ESC-012 (NULL-host arm): no host -> escalated anyway.
SELECT lives_ok(
    $$CALL tt.escalation_interface_escalate_customer(908214)$$,
    'S-ESC-012: escalate_customer succeeds for a ticket with NO host'
);
SELECT is(
    (SELECT escalation_status_id FROM tt.ticket WHERE id = 908114),
    10::numeric,
    'S-ESC-012: escalate_customer escalates a host-less ticket (v_host_id IS NULL arm)'
);
SELECT is(
    (SELECT count(*) FROM tt.event WHERE ticket_id = 908114 AND type_id = 60001 AND host_id IS NULL),
    1::bigint,
    'S-ESC-012: escalate_customer adds the 60001 event with host_id NULL for a host-less ticket (SQL%ROWCOUNT > 0 arm)'
);

-- S-ESC-014 (CORRECTED): nonexistent event -> plog.err + RETURN.
SELECT lives_ok(
    $$CALL tt.escalation_interface_escalate_customer(908999998)$$,
    'S-ESC-014: escalate_customer does NOT raise for a nonexistent event id (corrected: log + return)'
);
SELECT ok(
    (SELECT count(*) FROM osag.plog_stub_log
     WHERE levelname = 'ERR'
       AND message LIKE 'tt.escalation_interface.escalate_customer(): event with id 908999998 or its ticket not found.%') >= 1,
    'S-ESC-014: escalate_customer logs an ERR "event with id 908999998 or its ticket not found" (Oracle was completely silent here)'
);
SELECT is(
    (SELECT count(*) FROM tt.event WHERE type_id = 60001 AND details_private LIKE '%Caused by event 908999998'),
    0::bigint,
    'S-ESC-014: escalate_customer adds NO event for a nonexistent event'
);

-- S-ESC-009: ticket_closed propagates out of escalate_customer too.
SELECT throws_like(
    $$CALL tt.escalation_interface_escalate_customer(908215)$$,
    '%closed%',
    'S-ESC-009: escalate_customer propagates addevent_new''s ticket_closed error for a closed (status 102) ticket'
);

-------------------------------------------------------------------------------
-- escalate_isp_outage_to_os
-------------------------------------------------------------------------------

-- S-ESC-015/018/019: event without host/company falls back to the ticket's host and
-- company; a new hidden trouble ticket is opened with the composed texts.
SELECT lives_ok(
    $$CALL tt.escalation_interface_escalate_isp_outage_to_os(908220)$$,
    'S-ESC-019: escalate_isp_outage_to_os succeeds for an ISP outage event whose ticket has a host and a company'
);
SELECT is(
    (SELECT count(*) FROM tt.ticket t
     WHERE t.subject = 'Critical ISP Outage escalation' AND t.type_id = 1
       AND t.host_id IS NULL AND t.company_id IS NULL AND t.service_component_id = 27
       AND t.id <> 908120
       AND EXISTS (SELECT 1 FROM tt.event e WHERE e.ticket_id = t.id AND e.type_id = 30005
                   AND e.details_public LIKE '%Original ticket 908120')),
    1::bigint,
    'S-ESC-019: escalate_isp_outage_to_os opens exactly one NEW ticket (type 1, subject "Critical ISP Outage escalation", no host, no company, service component 27) with a 30005 event naming the ORIGINAL ticket'
);
SELECT ok(
    EXISTS (SELECT 1 FROM tt.event e
            WHERE e.type_id = 30005 AND e.public_event = 1
              AND e.details_public LIKE '%Critical ISP Outage escalation' || chr(10) || 'Host: pilot-esc-active' || chr(10) || 'Company: pltesc2' || chr(10) || 'Time of original event: 2024-03-05 14:07:09' || chr(10) || 'Original ticket 908120'),
    'S-ESC-018: the public details carry host name (from the TICKET host, NVL fallback), company short (from the TICKET company, COALESCE fallback), the original event date as YYYY-MM-DD HH24:MI:SS, and the ORIGINAL ticket id'
);
SELECT ok(
    EXISTS (SELECT 1 FROM tt.event e
            WHERE e.type_id = 30005
              AND e.details_public LIKE '%Original ticket 908120'
              AND e.details_private = 'To Do:' || chr(10) || 'https://open-systems.atlassian.net/wiki/x/3xYBAQ' || chr(10) || chr(10)
                  || 'Do not add any further events to this escalation ticket.' || chr(10)
                  || 'Use the original ticket 908120 for tracking any work!' || chr(10)
                  || 'This ticket is intentionally hidden from the customer, so do not merge it. '),
    'S-ESC-018: the private details are the Oracle-verbatim To-Do text naming the ORIGINAL ticket id (captured before v_ticket_id is reused as newticket_new''s OUT parameter)'
);
SELECT is(
    (SELECT escalation_status_id FROM tt.ticket WHERE id = 908120),
    0::numeric,
    'S-ESC-019: escalate_isp_outage_to_os leaves the ORIGINAL ticket untouched (escalation_status_id still 0)'
);

-- S-ESC-015 (event company wins) -- second event on the same original ticket.
SELECT lives_ok(
    $$CALL tt.escalation_interface_escalate_isp_outage_to_os(908222)$$,
    'S-ESC-015: escalate_isp_outage_to_os succeeds for an event carrying its own company_id'
);
SELECT ok(
    EXISTS (SELECT 1 FROM tt.event e
            WHERE e.type_id = 30005
              AND e.details_public LIKE '%Host: pilot-esc-active' || chr(10) || 'Company: pltesc1' || chr(10) || 'Time of original event: 2024-03-05 14:07:11' || chr(10) || 'Original ticket 908120'),
    'S-ESC-015: the event''s own company short (pltesc1) wins over the ticket''s (pltesc2) in COALESCE(ec.short, tc.short, sc.short)'
);

-- S-ESC-015/018 (NULL company short): event host wins over (absent) ticket host; the
-- host's service company has a NULL short -> 'Company: ' line survives, text not NULL.
SELECT lives_ok(
    $$CALL tt.escalation_interface_escalate_isp_outage_to_os(908221)$$,
    'S-ESC-018: escalate_isp_outage_to_os succeeds when every company in the COALESCE chain has a NULL short name'
);
SELECT ok(
    EXISTS (SELECT 1 FROM tt.event e
            WHERE e.type_id = 30005
              AND e.details_public LIKE '%Host: pilot-esc-noshort' || chr(10) || 'Company: ' || chr(10) || 'Time of original event: 2024-03-05 14:07:10' || chr(10) || 'Original ticket 908121'),
    'S-ESC-018: a NULL company short yields "Company: " (Oracle NULL-concat semantics) -- the rest of the public text survives, and the EVENT host (NVL(e.host_id, t.host_id)) was used'
);

-- S-ESC-016: no host on either the event or the ticket -> logged, no ticket created.
SELECT lives_ok(
    $$CALL tt.escalation_interface_escalate_isp_outage_to_os(908223)$$,
    'S-ESC-016: escalate_isp_outage_to_os returns without error when neither event nor ticket has a host'
);
SELECT ok(
    (SELECT count(*) FROM osag.plog_stub_log
     WHERE levelname = 'ERR'
       AND message = 'tt.escalation_interface.escalate_isp_outage_to_os(): either ticket, host or company not found for event with id: 908223 This is needed for escalation. Aborting escalation.') >= 1,
    'S-ESC-016: escalate_isp_outage_to_os logs the Oracle-verbatim "either ticket, host or company not found" ERR for a host-less event/ticket pair'
);
SELECT is(
    (SELECT count(*) FROM tt.event WHERE type_id = 30005 AND details_public LIKE '%Original ticket 908122'),
    0::bigint,
    'S-ESC-016: escalate_isp_outage_to_os creates NO escalation ticket when the join finds no host'
);
SELECT lives_ok(
    $$CALL tt.escalation_interface_escalate_isp_outage_to_os(908999997)$$,
    'S-ESC-016: escalate_isp_outage_to_os returns without error for a nonexistent event id'
);
SELECT ok(
    (SELECT count(*) FROM osag.plog_stub_log
     WHERE levelname = 'ERR'
       AND message = 'tt.escalation_interface.escalate_isp_outage_to_os(): either ticket, host or company not found for event with id: 908999997 This is needed for escalation. Aborting escalation.') >= 1,
    'S-ESC-016: escalate_isp_outage_to_os logs the "not found" ERR for a nonexistent event id'
);
SELECT is(
    (SELECT count(*) FROM tt.ticket WHERE subject = 'Critical ISP Outage escalation'),
    3::bigint,
    'S-ESC-016: no fourth escalation ticket was created by the two failing calls (three successful calls above opened exactly three)'
);

-------------------------------------------------------------------------------
-- nop
-------------------------------------------------------------------------------

SELECT lives_ok(
    $$CALL tt.escalation_interface_nop(908999996)$$,
    'S-ESC-020: nop accepts a nonexistent event id without error (never touches the database)'
);

-------------------------------------------------------------------------------
-- clear_customer_escalation
-------------------------------------------------------------------------------

SELECT lives_ok(
    $$CALL tt.escalation_interface_clear_customer_escalation(908130)$$,
    'S-ESC-021: clear_customer_escalation succeeds for a ticket in customer escalation (20)'
);
SELECT is(
    (SELECT escalation_status_id FROM tt.ticket WHERE id = 908130),
    0::numeric,
    'S-ESC-021: clear_customer_escalation resets escalation status 20 to 0'
);
SELECT is(
    (SELECT last_escalation_date FROM tt.ticket WHERE id = 908130),
    '2020-01-01 00:00:00'::timestamp,
    'S-ESC-021: clear_customer_escalation changes no other column (last_escalation_date untouched)'
);
SELECT lives_ok(
    $$CALL tt.escalation_interface_clear_customer_escalation(908131)$$,
    'S-ESC-021: clear_customer_escalation succeeds for a ticket in OS escalation (10)'
);
SELECT is(
    (SELECT escalation_status_id FROM tt.ticket WHERE id = 908131),
    10::numeric,
    'S-ESC-021: clear_customer_escalation never clears an OS escalation (10 stays 10)'
);
SELECT lives_ok(
    $$CALL tt.escalation_interface_clear_customer_escalation(908999995)$$,
    'S-ESC-021: clear_customer_escalation updates zero rows and raises nothing for a nonexistent ticket id'
);

-------------------------------------------------------------------------------
-- S-ESC-022: END-TO-END DYNAMIC DISPATCH. exec_event_type_actions resolves event_action
-- 1 (procedure_name = tt.escalation_interface.escalate_os, masterdata) for the mapped
-- pilot event type, passes the allowlist, and EXECUTEs the CALL -- the first time this
-- path can succeed at all. exec_event_type_actions swallows execution errors (Oracle's
-- own WHEN OTHERS), so the lives_ok alone proves nothing; the two data assertions do.
-------------------------------------------------------------------------------

SELECT lives_ok(
    $$CALL tt.event_interface_exec_event_type_actions(908250)$$,
    'S-ESC-022: exec_event_type_actions runs for an event whose type is mapped to event_action 1 (escalate_os)'
);
SELECT is(
    (SELECT escalation_status_id FROM tt.ticket WHERE id = 908150),
    10::numeric,
    'S-ESC-022: dynamic dispatch reached escalate_os -- the ticket is now in escalation status 10 (fixture started at 0)'
);
SELECT is(
    (SELECT count(*) FROM tt.event
     WHERE ticket_id = 908150 AND type_id = 60001
       AND details_private = 'Event added by tt.escalation_interface.escalate_os. Caused by event 908250'),
    1::bigint,
    'S-ESC-022: dynamic dispatch produced exactly one 60001 event naming the dispatched event id as its cause'
);

SELECT * FROM finish();
ROLLBACK;
