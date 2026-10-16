-- migration/test/regress/sql/tt__osag_notify__errors.sql
-- verifies: S-NOTIFY-018, S-NOTIFY-022
--
-- Expected-output harness half: pins the EXACT psql error text (including SQLSTATE)
-- for two of TT.OSAG_NOTIFY's deliberately-unhandled propagation paths. RED right now
-- because none of tt.osag_notify_* exists yet -- run with ON_ERROR_STOP=0 (the
-- harness's expected-output convention), so every statement below runs and its own
-- error is captured independently rather than aborting the whole script after the
-- first one.
--
-- Per the golden-file convention established in 02-04 (see
-- .planning/phases/02-spec-method-test-harness-pilot/02-04-SUMMARY.md, "Decisions
-- Made"): the expected/*.out golden below is authored from the SPEC's expected
-- SUBSTANCE (PL/pgSQL's own default STRICT/NOT NULL error text), not from today's
-- actual output ("function ... does not exist"). Today's mismatch against that
-- golden IS the RED proof itself; reconciling only the CONTEXT line's internal
-- function/line-number formatting (never the substance) is deferred to whichever
-- plan lands the real translation.

-- S-NOTIFY-018 (site #10): send_test_notification has NO exception handler anywhere
-- in its body -- a nonexistent p_event_type_id propagates NO_DATA_FOUND unhandled,
-- which PL/pgSQL's own STRICT default renders as the literal text "no data found".
CALL tt.osag_notify_send_test_notification('+41000000000', 1, 900301, 'subj', 'host', 900399999, now());

-- S-NOTIFY-022: add_notification_event has zero SELECT INTO sites and zero exception
-- handling -- a NULL p_event_type_id (the column is NOT NULL on tt.event) raises a
-- bare not_null_violation, uncaught, exactly as PostgreSQL's own INSERT would.
-- A-010: the DETAIL line of this not-null violation prints the whole failing row,
-- including a live sequence value and statement_timestamp() -- non-deterministic by
-- construction. VERBOSITY terse drops DETAIL/CONTEXT for this one statement; the
-- ERROR text and SQLSTATE (the substance this file pins) are unaffected.
\set VERBOSITY terse
CALL tt.osag_notify_add_notification_event(900301, NULL, 'x', NULL);
\set VERBOSITY default
