-- migration/test/pgtap/tt__util__spec.sql
--
-- pgTAP verification for migration/spec/tt.util.md. RED by construction: none of
-- tt.util_* exists yet. Every assertion's description starts with the spec clause ID it
-- verifies (HARN-05, trace_lint.py).
--
-- The COMMIT-bearing paths of close_old_dev_tickets (S-UTIL-010/012/013/014) cannot run
-- inside pgTAP's own wrapping transaction (pgTAP wraps every file in BEGIN/ROLLBACK; a
-- COMMIT inside a nested CALL would either error or commit pgTAP's own bookkeeping) --
-- those live in migration/test/regress/sql/tt__util__txn.sql instead, exercised via a
-- top-level `CALL`, exactly as the plan requires.

BEGIN;
SET CONSTRAINTS ALL DEFERRED;
SELECT plan(10);

-- S-UTIL-015 / Checklist dimension 5: every routine's pg_kind is currently PROCEDURE per
-- name-map.csv. Right now none of the five exist at all -- these checks fail cleanly
-- (metadata lookup, no error) rather than aborting, which is exactly the RED evidence
-- this plan wants: not merely "the call errored" but "the object literally isn't there
-- yet, in the expected shape."
SELECT ok(
    EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname = 'tt' AND p.proname = 'util_check_resolved_tickets' AND p.prokind = 'p'),
    'S-UTIL-001: tt.util_check_resolved_tickets exists as a PostgreSQL PROCEDURE (prokind=p)'
);

SELECT ok(
    EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname = 'tt' AND p.proname = 'util_check_ticket_status' AND p.prokind = 'p'),
    'S-UTIL-002: tt.util_check_ticket_status exists as a PostgreSQL PROCEDURE (prokind=p)'
);

SELECT ok(
    EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname = 'tt' AND p.proname = 'util_update_status_valid_until' AND p.prokind = 'p'),
    'S-UTIL-015: tt.util_update_status_valid_until exists as a PostgreSQL PROCEDURE (prokind=p) -- its 2 current callers are both PROCEDURE too, so this is not yet a FUNCTION-caller collision'
);

SELECT ok(
    EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname = 'tt' AND p.proname = 'util_check_dnids_tickets_to_resolve' AND p.prokind = 'p'),
    'S-UTIL-008: tt.util_check_dnids_tickets_to_resolve exists as a PostgreSQL PROCEDURE (prokind=p)'
);

SELECT ok(
    EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname = 'tt' AND p.proname = 'util_close_old_dev_tickets' AND p.prokind = 'p'),
    'S-UTIL-010: tt.util_close_old_dev_tickets exists as a PostgreSQL PROCEDURE (prokind=p) -- the COMMIT-bearing, autonomous-transaction-carrying routine'
);

-- Fixture: tickets in various statuses (existing masterdata tt.status/tt.ticket_type
-- rows) for update_status_valid_until's business logic. type_id=1 (incident, existing
-- masterdata row).
INSERT INTO tt.ticket (id, type_id, status_id, emergency, status_valid_until_date, last_deferral_date)
    VALUES (900301, 1, 60, 0, NULL, NULL);                         -- deferred: no-op expected
INSERT INTO tt.ticket (id, type_id, status_id, emergency, status_valid_until_date, last_deferral_date)
    VALUES (900302, 1, 2, 0, statement_timestamp() + interval '1 day', NULL);  -- open: reset expected
INSERT INTO tt.ticket (id, type_id, status_id, emergency, status_valid_until_date, last_deferral_date)
    VALUES (900303, 1, 11, 0, NULL, statement_timestamp());        -- waiting, non-emergency

-- S-UTIL-004: status 60 (deferred) is an immediate no-op -- status_valid_until_date stays
-- untouched (still NULL).
SELECT lives_ok(
    $$CALL tt.util_update_status_valid_until(900301, NULL)$$,
    'S-UTIL-004: update_status_valid_until on a deferred (status 60) ticket returns immediately with no writes'
);

-- NOTE: a separate "status_valid_until_date is still NULL" check is deliberately NOT
-- added here -- it started NULL, so it would trivially still read NULL even if the CALL
-- above died without running at all (exactly the RED-defeating tautology
-- T-02-13/PITFALLS.md warns about: a value that never changes cannot distinguish
-- "correctly did nothing" from "failed to do anything"). The `lives_ok` above is the
-- honest RED-failing assertion for this no-op clause.

-- S-UTIL-006: a ticket in a status outside (11,12,60,61) -- e.g. open (2) -- has
-- status_valid_until_date reset to NULL, even though it started non-NULL.
SELECT lives_ok(
    $$CALL tt.util_update_status_valid_until(900302, NULL)$$,
    'S-UTIL-006: update_status_valid_until runs for an ''other'' status (open, 2) without error'
);

SELECT is(
    (SELECT status_valid_until_date FROM tt.ticket WHERE id = 900302),
    NULL,
    'S-UTIL-006: update_status_valid_until resets status_valid_until_date to NULL for a ticket in a status outside (11,12,60,61)'
);

-- S-UTIL-007: for a waiting-family status (11), calling the 1-arg form (NULL date)
-- unconditionally nulls out last_deferral_date too, even though it started non-NULL.
SELECT lives_ok(
    $$CALL tt.util_update_status_valid_until(900303, NULL)$$,
    'S-UTIL-007: update_status_valid_until runs for a waiting (status 11) ticket without error'
);

-- S-UTIL-003: a ticket id that does not exist at all propagates NO_DATA_FOUND fully
-- unhandled (this package has zero exception handlers anywhere).
SELECT throws_like(
    $$CALL tt.util_update_status_valid_until(900399999, NULL)$$,
    '%no data found%',
    'S-UTIL-003: update_status_valid_until propagates NO_DATA_FOUND unhandled for a nonexistent ticket id (package has zero exception handlers)'
);

SELECT * FROM finish();
ROLLBACK;
