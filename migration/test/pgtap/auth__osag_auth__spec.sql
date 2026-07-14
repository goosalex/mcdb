-- migration/test/pgtap/auth__osag_auth__spec.sql
--
-- pgTAP verification for migration/spec/auth.osag_auth.md. RED by construction: none of
-- auth.osag_auth_* exists yet. Every assertion's description starts with the spec clause
-- ID it verifies (HARN-05, trace_lint.py).
--
-- delete_login's own body calls TT.OSAG_NOTIFY.delete_notifications_for_login
-- (S-AUTH-002) — that transitive dependency is not translated in this plan either, so
-- once auth.osag_auth_delete_login itself exists (a later plan), it will still need
-- OSAG_NOTIFY's translation to exist before it can run cleanly end to end. Not this
-- plan's concern (see the spec's Assumptions section); recorded here only so a future
-- reader isn't surprised when this suite stays partially RED even after
-- auth.osag_auth_delete_login lands.

BEGIN;
SET CONSTRAINTS ALL DEFERRED;
SELECT plan(10);

-- Fixture: one login (contact_id/company_id are fake -- deferred FKs, see
-- SET CONSTRAINTS above, since stop.contact/stop.company have no masterdata rows to
-- reuse and this transaction always rolls back) with one AUTOMATIC profile
-- (is_automatic=1, matching S-AUTH-004's cleanup branch) and a user_permission granting
-- an existing masterdata user_role (id=1, 'mca-access').
INSERT INTO auth.login (id, login, contact_id, company_id, enabled, locked)
    VALUES (900201, 'pilot-login', 900299, 900298, 1, 0);
INSERT INTO auth.profile (id, name, is_automatic) VALUES (900202, 'pilot-automatic-profile', 1);
INSERT INTO auth.login2profile (login_id, profile_id) VALUES (900201, 900202);
INSERT INTO auth.user_permission (id, user_role_id, profile_id) VALUES (900203, 1, 900202);

-- S-AUTH-001: deleting a login id that does not exist at all propagates the fully
-- unhandled NO_DATA_FOUND from the initial contact_id lookup (no local handler at that
-- site) up through the routine's outer WHEN OTHERS (S-AUTH-007), which logs then
-- re-raises -- the caller still sees "no data found".
SELECT throws_like(
    $$CALL auth.osag_auth_delete_login(900299999)$$,
    '%no data found%',
    'S-AUTH-001: delete_login propagates NO_DATA_FOUND unhandled for a nonexistent login id'
);

-- S-AUTH-007: that propagated exception is logged once via plog.err before re-raising,
-- observable on the plog stub without forcing a rollback (see osag_plog.FINDINGS.md).
SELECT ok(
    EXISTS(SELECT 1 FROM osag.plog_stub_log WHERE message LIKE '%caught exception%'),
    'S-AUTH-007: delete_login logs via plog.err before re-raising any unhandled exception'
);

-- S-AUTH-004 / S-AUTH-005: deleting an existing login removes its automatic profile,
-- the login2profile link, the user_permission row, and the login row itself.
SELECT lives_ok(
    $$CALL auth.osag_auth_delete_login(900201)$$,
    'S-AUTH-005: delete_login succeeds for an existing login id with a clean fixture'
);

SELECT is(
    (SELECT count(*) FROM auth.login WHERE id = 900201)::int,
    0,
    'S-AUTH-005: delete_login removes the auth.login row itself'
);

SELECT is(
    (SELECT count(*) FROM auth.profile WHERE id = 900202)::int,
    0,
    'S-AUTH-004: delete_login removes the AUTOMATIC profile (is_automatic=1) it created for this login'
);

SELECT is(
    (SELECT count(*) FROM auth.user_permission WHERE id = 900203)::int,
    0,
    'S-AUTH-004: delete_login removes user_permission rows scoped to the deleted profile'
);

-- S-AUTH-008: grant_role only special-cases p_role_id = 3; any other role id raises
-- VALUE_ERROR after logging (no RAISE_APPLICATION_ERROR code -- a bare predefined
-- exception).
INSERT INTO auth.login (id, login, contact_id, company_id, enabled, locked)
    VALUES (900204, 'pilot-login-2', 900297, 900296, 1, 0);

SELECT throws_ok(
    $$CALL auth.osag_auth_grant_role(900204, 99)$$,
    '22023',
    NULL,
    'S-AUTH-008: grant_role raises for any p_role_id other than 3 (VALUE_ERROR -> PostgreSQL invalid_parameter_value)'
);

-- S-AUTH-009: grant_user_role's v_company_id lookup (the one unguarded, non-aggregate
-- SELECT INTO site) propagates NO_DATA_FOUND for a login id that does not exist.
SELECT throws_like(
    $$CALL auth.osag_auth_grant_user_role(900299999, 1000)$$,
    '%no data found%',
    'S-AUTH-009: grant_user_role propagates NO_DATA_FOUND from the v_company_id lookup for a nonexistent login id'
);

-- S-AUTH-011: granting the SAME user_role to the SAME login twice is a silent no-op the
-- second time (unique-constraint swallow), not an error -- genuine idempotency, not mere
-- logging suppression.
SELECT lives_ok(
    $$CALL auth.osag_auth_grant_user_role(900204, 1000)$$,
    'S-AUTH-011: grant_user_role succeeds on the first grant'
);

SELECT lives_ok(
    $$CALL auth.osag_auth_grant_user_role(900204, 1000)$$,
    'S-AUTH-011: grant_user_role silently no-ops on a re-grant of the same (login, user_role) pair'
);

SELECT * FROM finish();
ROLLBACK;
