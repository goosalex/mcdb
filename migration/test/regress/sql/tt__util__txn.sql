-- migration/test/regress/sql/tt__util__txn.sql
-- verifies: S-UTIL-010, S-UTIL-012, S-UTIL-013
--
-- The transaction-semantics test: CALLs the COMMIT-bearing tt.util_close_old_dev_tickets
-- at the TOP LEVEL. Unlike pgtap/tt__util__spec.sql, this file is NOT wrapped in its own
-- BEGIN/ROLLBACK -- pgTAP's wrapping transaction cannot host a real COMMIT inside a
-- nested CALL, which is exactly why this second half of the harness exists (each
-- statement below runs and commits independently, psql's default autocommit mode,
-- exactly as a real top-level scheduled-job caller would invoke it). RED right now
-- because tt.util_close_old_dev_tickets does not exist yet.
--
-- TEST-ONLY ASSUMPTION (NOT a spec claim -- see tt.util.md's "Assumptions / Unresolved"
-- section, S-UTIL-011). How a translated close_old_dev_tickets will determine "is this a
-- dev instance" is UNRESOLVED: Oracle's V$INSTANCE has no PostgreSQL equivalent. This
-- fixture sets a placeholder custom GUC purely so this test CAN exercise S-UTIL-013's
-- per-iteration COMMIT semantics once a translation exists; it is a test-harness
-- convenience, not a claim about what XCUT-04/05 will actually decide. Whatever they
-- decide may require rewriting this fixture -- that rewrite is anticipated, not a
-- surprise (see migration/spec/TEST-AMENDMENTS.md's escape hatch for exactly this case).
SET mcdb.force_dev_instance = 'true';

-- Fixture: one abandoned MCC ticket, handled_by_mcc=1, status "open" (2, not in the
-- excluded set (2,102) -- wait, status 2 IS excluded per the cursor's own
-- `STATUS_ID NOT IN (2, 102)` filter (ddl/src/pkgb/tt_util.sql:214) -- use "hot" (3)
-- instead, which is NOT excluded, open 31 days ago (past the 30-day cutoff).
INSERT INTO tt.ticket (id, type_id, status_id, handled_by_mcc, open_date)
    VALUES (900401, 1, 3, 1, statement_timestamp() - interval '31 days');

CALL tt.util_close_old_dev_tickets();

-- S-UTIL-013: if the procedure ran, its per-ticket COMMIT means this SELECT --  a brand
-- new, independent top-level statement, exactly what "a caller observes afterwards"
-- means -- already sees the closed (102) status durably, without this script itself
-- ever issuing a COMMIT of its own.
SELECT id, status_id FROM tt.ticket WHERE id = 900401;
