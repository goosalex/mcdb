-- migration/test/regress/sql/tt__ticket_interface__errors.sql
-- verifies: S-TICKET-011, S-TICKET-048, S-TICKET-038
--
-- Expected-output harness half: pins the EXACT psql error text (including SQLSTATE via
-- the plain error message) for two of TT.TICKET_INTERFACE's deliberately-unhandled
-- propagation paths, and demonstrates the swallow-not-reraise contract of its 10
-- WHEN OTHERS handlers (none of which ever re-raises -- this package has zero
-- RAISE_APPLICATION_ERROR calls and zero named-exception raises anywhere, per the
-- spec's Checklist dimension 3). RED right now because none of tt.ticket_interface_*
-- exists yet -- run with ON_ERROR_STOP=0 (the harness's expected-output convention), so
-- every statement below runs and its own outcome is captured independently rather than
-- aborting the whole script after the first one.
--
-- Per the golden-file convention established in 02-04 (see
-- .planning/phases/02-spec-method-test-harness-pilot/02-04-SUMMARY.md, "Decisions
-- Made"): the expected/*.out golden below is authored from the SPEC's expected
-- SUBSTANCE (PL/pgSQL's own default STRICT error text, and the swallow's silent
-- success), not from today's actual output ("function/procedure ... does not exist").
-- Today's mismatch against that golden IS the RED proof itself; reconciling only the
-- CONTEXT line's internal function/line-number formatting (never the substance) is
-- deferred to whichever plan lands the real translation (plan 02-12).

-- S-TICKET-011: update_ux_timeout_for_ticket has no EXCEPTION block anywhere in its
-- 85-line body -- a nonexistent p_ticket_id propagates NO_DATA_FOUND unhandled at site
-- #18, which PL/pgSQL's own STRICT default renders as the literal text "no data found".
CALL tt.ticket_interface_update_ux_timeout_for_ticket(999888771, FALSE);

-- S-TICKET-048: clear_todo_list's tt.ticket lookup (site #68) runs unconditionally when
-- p_add_history_event=1 (the default, taken here since only the two required args are
-- supplied) -- no EXCEPTION block exists to catch the resulting NO_DATA_FOUND.
CALL tt.ticket_interface_clear_todo_list(999888772, 1001);

-- S-TICKET-038: trigger_escalation's own whole-body `WHEN OTHERS THEN plog.err(c_prefix
-- ||'unexpected error: '||sqlerrm)` swallows ANY internal failure (here,
-- add_history_event's own unhandled NO_DATA_FOUND for the same nonexistent
-- p_ticket_id) and never propagates -- this CALL is expected to succeed silently (a
-- successful CALL to a procedure produces no output at all), and the swallow is only
-- observable via the plog stub's logged row below, asserted WITHOUT a rollback (see
-- migration/pgsql/osag/osag_plog.FINDINGS.md -- rollback-survival of logging is Phase
-- 3's XCUT-02, not this suite's claim).
CALL tt.ticket_interface_trigger_escalation(999888773, 1001, 1002);

SELECT count(*) AS swallowed_error_logged FROM osag.plog_stub_log WHERE message LIKE '%unexpected error%';
