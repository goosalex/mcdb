-- migration/test/regress/sql/ticketevolution__calculator__txn.sql
-- verifies: S-TICKEV-018, S-TICKEV-019, S-TICKEV-020, S-TICKEV-002, S-TICKEV-004
--
-- The transaction-semantics test for TICKETEVOLUTION.CALCULATOR: CALLs the COMMIT-bearing
-- ticketevolution.calculator_materialize_incremental at the TOP LEVEL, exactly as its only
-- real caller does (the hourly DBMS_SCHEDULER job in
-- ddl/src/jobs/ticketevolution_incremental_update.sql). Like tt__util__txn.sql this file is
-- NOT wrapped in BEGIN/ROLLBACK: psql autocommit, every statement its own transaction, so
-- the procedure's internal COMMITs are legal and every SELECT below observes only what the
-- procedure durably committed. RED right now because the procedure does not exist yet.
--
-- Fixture ids: 9091xx. The file is self-cleaning so it can be re-run against a reused
-- database (run-tests.sh reuses --db between runs); the pgTAP half never commits, so the
-- only LAST_RUN row this database can ever hold is the one this file provokes.

DELETE FROM ticketevolution.tickev WHERE ticket_id = 909101;
DELETE FROM tt.event WHERE ticket_id = 909101;
DELETE FROM tt.ticket WHERE id = 909101;
DELETE FROM ticketevolution.state WHERE key = 'LAST_RUN';

INSERT INTO tt.ticket (id, type_id, status_id) VALUES (909101, 1, 2);
INSERT INTO tt.event (id, type_id, ticket_id, eventdate, db_date, details_public)
    VALUES (909102, 101002, 909101, timestamp '2024-03-01 10:00:00', timestamp '2024-03-01 10:00:00', 'New status: open');

-- Run 1: no LAST_RUN row exists -> S-TICKEV-018 initialises it (now - 365 d), so the
-- ticket inserted a moment ago is newer than the watermark and gets materialized.
CALL ticketevolution.calculator_materialize_incremental();

-- S-TICKEV-018 / S-TICKEV-020: exactly one LAST_RUN row, set to this run's start time
-- (whole-second precision, never in the future), committed by the procedure itself.
SELECT key,
       value_dt = date_trunc('second', value_dt) AS whole_seconds,
       value_dt <= statement_timestamp()          AS not_in_future,
       value_dt > statement_timestamp() - interval '10 minutes' AS set_by_this_run
FROM ticketevolution.state
WHERE key = 'LAST_RUN';

-- S-TICKEV-019 / S-TICKEV-004: the ticket's replay was committed per ticket and is visible
-- from this new top-level statement -- the pseudo 'new' row plus the 'open' row.
SELECT event_id, ticket_status, ticket_status_id, deleted
FROM ticketevolution.tickev
WHERE ticket_id = 909101
ORDER BY deleted, ticket_status_id;

-- Run 2: the watermark now equals run 1's start; the ticket has not been touched since
-- (its update_timestamp, truncated to the second, is <= the watermark) -> not replayed,
-- so no second generation appears.
CALL ticketevolution.calculator_materialize_incremental();

SELECT count(*) FILTER (WHERE deleted = 0) AS live_rows,
       count(*) FILTER (WHERE deleted = 1) AS deleted_rows
FROM ticketevolution.tickev
WHERE ticket_id = 909101;

-- Run 3: touch the ticket so its second-truncated update_timestamp is strictly newer than
-- the watermark (+5 s guards against the touch landing in the same second as run 2's
-- start) -> replayed again: the first generation is soft-deleted (S-TICKEV-002) and a
-- fresh live one committed.
UPDATE tt.ticket SET update_timestamp = statement_timestamp() + interval '5 seconds' WHERE id = 909101;

CALL ticketevolution.calculator_materialize_incremental();

SELECT count(*) FILTER (WHERE deleted = 0) AS live_rows,
       count(*) FILTER (WHERE deleted = 1) AS deleted_rows
FROM ticketevolution.tickev
WHERE ticket_id = 909101;

-- S-TICKEV-018: the initialising INSERT happens only on the NO_DATA_FOUND path -- three
-- runs, still exactly one watermark row.
SELECT count(*) AS watermark_rows FROM ticketevolution.state WHERE key = 'LAST_RUN';
