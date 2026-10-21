-- tt__util__close_old_dev / call.pg.sql -- PostgreSQL twin of call.ora.sql.
-- Name from migration/mapping/name-map.csv: tt.util.close_old_dev_tickets ->
-- tt.util_close_old_dev_tickets. A TOP-LEVEL CALL, deliberately not wrapped in a DO block
-- with an EXCEPTION clause: the procedure issues COMMIT / ROLLBACK itself, which PL/pgSQL
-- allows only when no subtransaction is active (COMMITS=yes: no transaction block either).
-- A failure of the CALL would surface as a psql error line in the capture (a visible DIFF),
-- not as a probe row.
CALL tt.util_close_old_dev_tickets();
INSERT INTO diff_probe (step, s) VALUES ('01 close_old_dev_tickets', 'ok');
