-- migration/test/regress/sql/tt__escalation_interface__errors.sql
-- verifies: S-ESC-008, S-ESC-014, S-ESC-016, S-ESC-020, S-ESC-021
--
-- Expected-output harness half for TT.ESCALATION_INTERFACE's error paths. This package
-- raises NOTHING of its own: every "bad input" path is a logged swallow -- two of them
-- (S-ESC-008, S-ESC-014) are CORRECTED behaviour (Oracle silently "escalated" a
-- nonexistent event; the translation logs via plog.err and returns), one (S-ESC-016) is
-- Oracle's own log-and-return handler. So the golden below pins (1) that every CALL
-- succeeds silently (a successful CALL produces no output at all) and (2) the EXACT
-- log lines the plog stub recorded for the five inputs, in order.
--
-- RED right now because none of tt.escalation_interface_* exists: each CALL errors with
-- "procedure ... does not exist" (and, inside the transaction, every later statement
-- errors with "current transaction is aborted"), which cannot match the golden. Run
-- with ON_ERROR_STOP=0 (the harness's expected-output convention).
--
-- Wrapped in BEGIN/ROLLBACK so the plog stub rows (which ride in the caller's own
-- transaction, see migration/pgsql/osag/osag_plog.FINDINGS.md) never accumulate across
-- re-runs against the same database -- no fixture rows are needed, every id below is
-- deliberately nonexistent.

BEGIN;

-- S-ESC-008 (corrected): nonexistent event -> DEBUG "called for" line (Oracle line 23,
-- precedes the lookup) then ERR "not found", RETURN, no exception.
CALL tt.escalation_interface_escalate_os(908999999);

-- S-ESC-014 (corrected): nonexistent event -> ERR "not found" (escalate_customer has no
-- debug lines at all), RETURN, no exception. Oracle was completely silent here.
CALL tt.escalation_interface_escalate_customer(908999998);

-- S-ESC-016 (Oracle-faithful): the six-table join finds no row -> Oracle-verbatim ERR
-- text, RETURN, no exception, no ticket created.
CALL tt.escalation_interface_escalate_isp_outage_to_os(908999997);

-- S-ESC-020: nop never touches the database -- no log line, no error.
CALL tt.escalation_interface_nop(908999996);

-- S-ESC-021: a nonexistent ticket id updates zero rows -- no log line, no error.
CALL tt.escalation_interface_clear_customer_escalation(908999995);

SELECT levelname, message
FROM osag.plog_stub_log
WHERE message LIKE '%90899999_%'
ORDER BY id;

ROLLBACK;
