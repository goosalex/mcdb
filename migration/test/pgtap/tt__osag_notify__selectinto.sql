-- migration/test/pgtap/tt__osag_notify__selectinto.sql
--
-- pgTAP verification of migration/spec/tt.osag_notify.md's `### SELECT INTO
-- strictness` table (Checklist dimension 2) -- the whole reason TT.OSAG_NOTIFY is in
-- this pilot. RED by construction. Every assertion's description starts with the spec
-- clause ID it verifies (HARN-05, trace_lint.py).
--
-- This suite deliberately drives ZERO-matching-row and MULTI-matching-row inputs at
-- the sites that need it, per PITFALLS.md's tell: "test failures on empty-result-set
-- inputs that pass on non-empty inputs (asymmetric coverage is the tell)". A suite
-- that only ever fed matching rows would go green against a translation that silently
-- dropped STRICT everywhere -- see migration/spec/tt.osag_notify.md's
-- Assumptions/Checklist-2 for why several sites below are asserted via return-value/
-- plog-content rather than a raised exception: EVERY exception path in this package,
-- including its one TOO_MANY_ROWS handler, is swallowed somewhere before it ever
-- reaches a caller (S-NOTIFY-001, S-NOTIFY-009, S-NOTIFY-031) -- that is the package's
-- actual, honest contract, not a gap in this suite.

BEGIN;
SET CONSTRAINTS ALL DEFERRED;
-- A-005 (TEST-AMENDMENTS.md): the file contains 13 assertions; the original plan(14)
-- was an off-by-one that failed the file's TAP plan even with every assertion passing.
SELECT plan(13);

-------------------------------------------------------------------------------
-- S-NOTIFY-018 (site #10, send_test_notification): fully unhandled NO_DATA_FOUND.
-------------------------------------------------------------------------------

SELECT throws_ok(
    $$CALL tt.osag_notify_send_test_notification('+41000000000', 1, 900201, 'subj', 'host', 900299999, now())$$,
    'P0002',
    NULL,
    'S-NOTIFY-018: send_test_notification (SMS branch) propagates NO_DATA_FOUND unhandled for a nonexistent p_event_type_id (site #10)'
);

SELECT throws_ok(
    $$CALL tt.osag_notify_send_test_notification('test@example.com', 2, 900201, 'subj', 'host', 900299999, now())$$,
    'P0002',
    NULL,
    'S-NOTIFY-018: send_test_notification (email branch) propagates the SAME unhandled site #10 for a nonexistent p_event_type_id'
);

-------------------------------------------------------------------------------
-- S-NOTIFY-026 / S-NOTIFY-028 (sites #14/#15 compose_email_msg, #16/#17
-- compose_sms_msg): the event_type row itself resolves (site #10 succeeds), but its
-- template ids are dangling references into tt.event_type_message -- these are
-- fixtures only reachable with deferred FK checking (SET CONSTRAINTS ALL DEFERRED,
-- above), since a real tt.event_type row's template columns are themselves
-- FK-constrained; we need them to exist at the tt.event_type level but NOT resolve at
-- the tt.event_type_message level, to isolate sites #15/#17 specifically.
-------------------------------------------------------------------------------

INSERT INTO tt.event_type (id, name, source, sms_message_template_id, email_message_template_id)
    VALUES (900202, 'pilot dangling-template event type', 1, 900299998, 900299997);

SELECT throws_ok(
    $$CALL tt.osag_notify_send_test_notification('+41000000000', 1, 900201, 'subj', 'host', 900202, now())$$,
    'P0002',
    NULL,
    'S-NOTIFY-028: send_test_notification (SMS) -> compose_sms_msg propagates NO_DATA_FOUND unhandled for a dangling sms_message_template_id (site #17)'
);

SELECT throws_ok(
    $$CALL tt.osag_notify_send_test_notification('test@example.com', 2, 900201, 'subj', 'host', 900202, now())$$,
    'P0002',
    NULL,
    'S-NOTIFY-026: send_test_notification (email) -> compose_email_msg propagates NO_DATA_FOUND unhandled for a dangling email_message_template_id (site #15)'
);

-------------------------------------------------------------------------------
-- S-NOTIFY-024 / S-NOTIFY-025 (sites #12/#13, private send_notification_by_type):
-- called directly via its declared private-routine name (tt.osag_notify__<name>,
-- this plan's chosen naming convention -- see the spec's front-matter section). No
-- EXCEPTION block in this routine at all; a nonexistent p_login_id propagates
-- NO_DATA_FOUND unhandled regardless of which branch (SMS vs email) is taken.
-------------------------------------------------------------------------------

SELECT throws_ok(
    $$CALL tt.osag_notify__send_notification_by_type(1, 900201, 900299996, 'evt', 'host', now(), 'details', 'subj', 'body', 'sms', 1)$$,
    'P0002',
    NULL,
    'S-NOTIFY-024: send_notification_by_type (SMS branch, type=1) propagates NO_DATA_FOUND unhandled for a nonexistent p_login_id (site #12)'
);

SELECT throws_ok(
    $$CALL tt.osag_notify__send_notification_by_type(2, 900201, 900299996, 'evt', 'host', now(), 'details', 'subj', 'body', 'sms', 1)$$,
    'P0002',
    NULL,
    'S-NOTIFY-025: send_notification_by_type (email branch, type=2) propagates the SAME unhandled site #13 for a nonexistent p_login_id'
);

-------------------------------------------------------------------------------
-- S-NOTIFY-022: add_notification_event has NO SELECT INTO at all and NO exception
-- handler -- a NOT NULL violation (not an FK violation, so it fires regardless of
-- this file's SET CONSTRAINTS ALL DEFERRED) propagates fully unhandled, exactly as
-- the spec's "deliberate let-it-fail-loudly contract" claims.
-------------------------------------------------------------------------------

SELECT throws_ok(
    $$CALL tt.osag_notify_add_notification_event(900201, NULL, 'x', NULL)$$,
    '23502',
    NULL,
    'S-NOTIFY-022: add_notification_event has no input validation -- a NULL p_event_type_id raises a bare NOT NULL violation, uncaught'
);

-------------------------------------------------------------------------------
-- S-NOTIFY-031 (site #22, private get_isp_link_id_for_host_id): the pilot's ONE
-- TOO_MANY_ROWS handler. Zero / one / many matching rows, driven through the
-- routine's real name (tt.osag_notify__get_isp_link_id_for_host_id), each verdict
-- checked by RETURN VALUE and plog content -- not by throws_ok, because Oracle's own
-- handler swallows ALL THREE arms (NO_DATA_FOUND, TOO_MANY_ROWS, OTHERS) to NULL and
-- never raises. This is the honest reflection of the source, not weaker coverage:
-- distinguishing "NULL because nothing matched" from "NULL because too many matched,
-- logged" from "a real single match" is exactly what proves STRICT-without-a-TMR-arm
-- would be wrong here.
-------------------------------------------------------------------------------

INSERT INTO stop.company (id, name, short) VALUES (900203, 'Pilot ISP Co', 'pilotco2');
INSERT INTO mss.host (id, name, operating_system_id, service_company_id, author)
    VALUES (900204, 'pilot-host-many', 2, 900203, 'pilot');
INSERT INTO mss.host (id, name, operating_system_id, service_company_id, author)
    VALUES (900205, 'pilot-host-one', 2, 900203, 'pilot');
INSERT INTO mss.host (id, name, operating_system_id, service_company_id, author)
    VALUES (900206, 'pilot-host-none', 2, 900203, 'pilot');

-- network_id is left NULL: its DEFAULT of 1 does not resolve to a real mss.network
-- row in mcdb_tmpl (a real ora2pg/masterdata gap, not something this fixture should
-- paper over by inventing a network row -- see migration/test/SCHEMA-FIXES.md).
INSERT INTO mss.interface (id, name, host_id, mgmtaccess, network_id, author, description)
    VALUES (900207, 'eth0', 900204, 1, NULL, 'pilot', 'pilot fixture');
INSERT INTO mss.interface (id, name, host_id, mgmtaccess, network_id, author, description)
    VALUES (900208, 'eth0', 900205, 1, NULL, 'pilot', 'pilot fixture');

INSERT INTO mss.isp_link (id, router_ip_address1, event_type_id, currency_id, isp_link_sourcing_type_id)
    VALUES (900209, 16909060, 10003, 1, 1);
INSERT INTO mss.isp_link (id, router_ip_address1, event_type_id, currency_id, isp_link_sourcing_type_id)
    VALUES (900210, 16909061, 10003, 1, 1);

-- host-many's ONE interface maps to TWO isp_links: mss.interface2isp_link's PK is
-- (interface_id, isp_link_id), NOT unique on interface_id alone (see spec S-NOTIFY-031).
INSERT INTO mss.interface2isp_link (interface_id, isp_link_id) VALUES (900207, 900209);
INSERT INTO mss.interface2isp_link (interface_id, isp_link_id) VALUES (900207, 900210);
-- host-one's ONE interface maps to exactly ONE isp_link.
INSERT INTO mss.interface2isp_link (interface_id, isp_link_id) VALUES (900208, 900209);
-- host-none has no mgmtaccess interface at all (zero rows, no further fixture needed).

SELECT is(
    tt.osag_notify__get_isp_link_id_for_host_id(900206),
    NULL::numeric,
    'S-NOTIFY-031: get_isp_link_id_for_host_id returns NULL (silently, no log) for a host with no mgmtaccess interface at all -- the NO_DATA_FOUND arm'
);

SELECT is(
    tt.osag_notify__get_isp_link_id_for_host_id(900205),
    900209::numeric,
    'S-NOTIFY-031: get_isp_link_id_for_host_id returns the single matching isp_link_id for a host with exactly one mgmtaccess interface mapped to one ISP link'
);

SELECT is(
    tt.osag_notify__get_isp_link_id_for_host_id(900204),
    NULL::numeric,
    'S-NOTIFY-031: get_isp_link_id_for_host_id returns NULL for a host whose single mgmtaccess interface maps to TWO isp_links -- the TOO_MANY_ROWS arm, not an unhandled STRICT failure'
);

SELECT ok(
    (SELECT count(*) FROM osag.plog_stub_log WHERE message LIKE '%has too many ISP links%') >= 1,
    'S-NOTIFY-031: get_isp_link_id_for_host_id logs "...has too many ISP links" via plog.err specifically for the TOO_MANY_ROWS arm (distinguishing it from the silent NO_DATA_FOUND arm above)'
);

-------------------------------------------------------------------------------
-- S-NOTIFY-009 (site #9, event_notify's event_type_group lookup): the local handler
-- catches NO_DATA_FOUND only; a TOO_MANY_ROWS here (event_type mapped to 2 groups,
-- structurally possible since tt.event_type2event_type_group's PK is
-- (group_id, event_type_id), not unique on event_type_id) is NOT caught locally --
-- it escalates to event_notify's own outer WHEN OTHERS (S-NOTIFY-001) and aborts the
-- REST of the procedure, including the notify-count updates (S-NOTIFY-015/016) that
-- would otherwise follow. Observable via: (a) the call still succeeds without raising
-- (swallowed, not propagated), (b) the ticket's counters were never touched, and (c)
-- plog logged the swallow.
-------------------------------------------------------------------------------

INSERT INTO tt.ticket_type (id, name) VALUES (900211, 'pilot ticket type');
INSERT INTO tt.event_type (id, name, source, sms_message_template_id, email_message_template_id)
    VALUES (900212, 'pilot multi-group event type', 1, 1, 2);
INSERT INTO tt.event_type2event_type_group (event_type_group_id, event_type_id) VALUES (1, 900212);
INSERT INTO tt.event_type2event_type_group (event_type_group_id, event_type_id) VALUES (2, 900212);
INSERT INTO tt.ticket (id, type_id, event_notify_count) VALUES (900213, 900211, NULL);
INSERT INTO tt.event (id, type_id, ticket_id) VALUES (900214, 900212, 900213);

SELECT lives_ok(
    $$CALL tt.osag_notify_event_notify(p_event_id => 900214)$$,
    'S-NOTIFY-009: event_notify never raises even when site #9''s event_type_group lookup hits TOO_MANY_ROWS (unhandled locally, escalates to the outer WHEN OTHERS)'
);

SELECT is(
    (SELECT event_notify_count FROM tt.ticket WHERE id = 900213),
    NULL::numeric,
    'S-NOTIFY-009: once site #9 escalates to the outer WHEN OTHERS, the REST of event_notify (including the notify-count update, S-NOTIFY-015) never ran'
);

SELECT * FROM finish();
ROLLBACK;
