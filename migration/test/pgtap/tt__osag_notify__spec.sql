-- migration/test/pgtap/tt__osag_notify__spec.sql
--
-- pgTAP verification for migration/spec/tt.osag_notify.md's PUBLIC contract. RED by
-- construction: none of tt.osag_notify_* (nor the private tt.osag_notify__* helpers)
-- exists yet. Every assertion's description starts with the spec clause ID it verifies
-- (HARN-05, trace_lint.py).
--
-- This file covers the "package never lets an internal failure become caller-visible"
-- headline finding (S-NOTIFY-001) and the four public routines that are cheap to
-- fixture (add_notification_event, is_notify_suppressor_active,
-- delete_notifications_for_login, delete_ticket_notifications). The 30-site SELECT INTO
-- enumeration itself, including the pilot's one TOO_MANY_ROWS handler, lives in the
-- sibling file tt__osag_notify__selectinto.sql.

BEGIN;
SET CONSTRAINTS ALL DEFERRED;
SELECT plan(10);

-- Fixture: a ticket + event pair with no host/service/company (all NULL), so the
-- suppression gate and the company-unit-resolution branch (S-NOTIFY-007) are skipped
-- cleanly (see selectinto.sql for the sites that need populated host/service data).
INSERT INTO tt.ticket_type (id, name) VALUES (900101, 'pilot ticket type');
INSERT INTO tt.event_type (id, name, source, sms_message_template_id, email_message_template_id)
    VALUES (900102, 'pilot event type', 1, 1, 2);
INSERT INTO tt.ticket (id, type_id) VALUES (900103, 900101);
INSERT INTO tt.event (id, type_id, ticket_id) VALUES (900104, 900102, 900103);

-- S-NOTIFY-001: event_notify's entire body is wrapped in one top-level
-- `WHEN OTHERS THEN plog.warning(...); plog.warning(...)` with no RAISE -- it NEVER
-- raises to its caller, even for a completely bogus event id (site #1's NO_DATA_FOUND,
-- unhandled locally, escalates here and is swallowed).
SELECT lives_ok(
    $$CALL tt.osag_notify_event_notify(p_event_id => 900199999)$$,
    'S-NOTIFY-001: event_notify never raises to its caller, even for a nonexistent p_event_id'
);

-- S-NOTIFY-002: that swallowed NO_DATA_FOUND (site #1, tt.event lookup) is still
-- observable via the plog stub -- event_notify logs the message + sqlerrm pair before
-- swallowing (ddl/src/pkgb/tt_osag_notify.sql:756-757), without needing a rollback (see
-- osag_plog.FINDINGS.md).
SELECT ok(
    (SELECT count(*) FROM osag.plog_stub_log WHERE message LIKE '%sending of notification for event ID%failed%') >= 1,
    'S-NOTIFY-002: event_notify logs via plog.warning before swallowing an internal NO_DATA_FOUND'
);

-- S-NOTIFY-023: is_notify_suppressor_active's one SELECT INTO site is a COUNT(*)
-- aggregate (always exactly one row -- no STRICT concern at all). A host with zero
-- active suppressing service windows returns FALSE.
SELECT is(
    (SELECT tt.osag_notify_is_notify_suppressor_active(900199998)),
    FALSE,
    'S-NOTIFY-023: is_notify_suppressor_active returns FALSE for a host with no active suppressing service window'
);

-- S-NOTIFY-022: add_notification_event routes p_text to details_public when
-- p_is_public_event = 1 (the default), and explicitly nulls details_private.
SELECT lives_ok(
    $$CALL tt.osag_notify_add_notification_event(900103, 900102, 'public test event', NULL)$$,
    'S-NOTIFY-022: add_notification_event succeeds for a public event with valid FKs'
);

SELECT results_eq(
    $$SELECT details_public, details_private FROM tt.event WHERE ticket_id = 900103 AND details_public = 'public test event'$$,
    $$VALUES ('public test event'::text, NULL::text)$$,
    'S-NOTIFY-022: add_notification_event(p_is_public_event=1) writes details_public and leaves details_private NULL'
);

-- S-NOTIFY-022: the reverse routing for a private event (p_is_public_event = 0).
SELECT lives_ok(
    $$CALL tt.osag_notify_add_notification_event(900103, 900102, 'private test event', NULL, NULL, 0)$$,
    'S-NOTIFY-022: add_notification_event succeeds for a private event'
);

SELECT results_eq(
    $$SELECT details_public, details_private FROM tt.event WHERE ticket_id = 900103 AND details_private = 'private test event'$$,
    $$VALUES (NULL::text, 'private test event'::text)$$,
    'S-NOTIFY-022: add_notification_event(p_is_public_event=0) writes details_private and leaves details_public NULL'
);

-- S-NOTIFY-019: delete_notifications_for_login is a plain cursor FOR loop over
-- tt.event_notification -- zero matching rows for a login with no notifications at all
-- is a normal empty-loop no-op, not an exception (the routine has no EXCEPTION block).
SELECT lives_ok(
    $$CALL tt.osag_notify_delete_notifications_for_login(900199997)$$,
    'S-NOTIFY-019: delete_notifications_for_login is a no-op (not an exception) for a login with zero notifications'
);

-- S-NOTIFY-021/S-NOTIFY-036: delete_ticket_notifications' own top-level
-- `WHEN OTHERS` (ddl/src/pkgb/tt_osag_notify.sql:932-935) swallows ANY internal
-- failure, including the private get_notification_type_name's fully-unhandled
-- NO_DATA_FOUND (site #30) when a fixture event_notification row references an
-- event_notification_type_id that does not exist.
INSERT INTO auth.login (id, contact_id, company_id) VALUES (900105, 900106, 900107);
INSERT INTO tt.event_notification (id, login_id, event_notification_type_id, ticket_id)
    VALUES (900108, 900105, 900199996, 900103);

SELECT lives_ok(
    $$CALL tt.osag_notify_delete_ticket_notifications(900103)$$,
    'S-NOTIFY-021: delete_ticket_notifications swallows get_notification_type_name''s unhandled NO_DATA_FOUND (site #30) via its own top-level WHEN OTHERS'
);

SELECT ok(
    (SELECT count(*) FROM osag.plog_stub_log WHERE message LIKE '%deletion of notifications for ticket%failed%') >= 1,
    'S-NOTIFY-021: delete_ticket_notifications logs via plog.warning when it swallows an internal failure'
);

SELECT * FROM finish();
ROLLBACK;
