-- migration/test/regress/sql/mc__osag_maintsync__errors.sql
-- verifies: S-MAINT-013, S-MAINT-014
--
-- Expected-output harness half for MC.OSAG_MAINTSYNC's error paths. This package raises
-- NOTHING: every failure is swallowed into a plog.err line, so the golden pins (1) that
-- both CALLs succeed silently (a successful CALL produces no output) and (2) the EXACT
-- log lines the plog stub recorded for a nonexistent host and a nonexistent ISP link --
-- the fixed Oracle prefix "<routine>(): caught exception: " followed by the engine's
-- own SQLERRM for the unhandled SELECT INTO STRICT ("query returned no rows"; Oracle
-- said "ORA-01403: no data found" here -- the spec pins the prefix only, this golden
-- additionally documents the PostgreSQL text).
--
-- Wrapped in BEGIN/ROLLBACK so the plog stub rows (which ride in the caller's own
-- transaction, see migration/pgsql/osag/osag_plog.FINDINGS.md) never accumulate across
-- re-runs. No fixture rows are needed: both ids are deliberately nonexistent.
--
-- RED right now because none of mc.osag_maintsync_* exists: each CALL errors with
-- "procedure ... does not exist" (and every later statement with "current transaction is
-- aborted"), which cannot match the golden. Run with ON_ERROR_STOP=0.

\set VERBOSITY terse

BEGIN;

CALL mc.osag_maintsync_update_single_host(929999);

CALL mc.osag_maintsync_update_single_isp_link(929998);

SELECT levelname, message FROM osag.plog_stub_log WHERE message LIKE 'update_single_%(): caught exception: %' ORDER BY id;

ROLLBACK;
