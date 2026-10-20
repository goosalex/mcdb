-- migration/test/regress/sql/mcaudit__osag_audit__errors.sql
-- verifies: S-AUDIT-007, S-AUDIT-010
--
-- Expected-output harness half for MCAUDIT.OSAG_AUDIT's two externally reachable error
-- texts: the unresolved-short NO_DATA_FOUND (Oracle ORA-01403 -> SQLSTATE P0002 with the
-- message-parity text "no data found", S-AUDIT-010) and the NOT NULL violation for a
-- NULL message (ORA-01400 -> 23502, S-AUDIT-007). Both statements FAIL, so nothing is
-- persisted and no transaction wrapper is needed (each CALL is its own transaction).
-- VERBOSITY terse keeps CONTEXT/DETAIL lines (which carry PL/pgSQL line numbers) out of
-- the golden. Every statement is on ONE line so psql's "psql:<file>:<line>:" prefix is
-- stable. Run with ON_ERROR_STOP=0 (the harness's expected-output convention).
--
-- RED right now because none of mcaudit.osag_audit_* exists: each CALL errors with
-- "procedure ... does not exist", which cannot match the golden.

\set VERBOSITY terse

CALL mcaudit.osag_audit_add_record('p0601_nope', 'authsys', 'login_modify', 'info', NULL, 'p0601 regress unknown short', NULL);

CALL mcaudit.osag_audit_add_record2('guma', 'authsys', 'login_modify', 'p0601_nope', NULL, 'p0601 regress unknown severity', NULL);

CALL mcaudit.osag_audit_add_record_raw2(1, 12, 4, 10, NULL, NULL, 'p0601 regress null message');
