--liquibase formatted sql logicalFilePath:oracle_side/prune.sql
--changeset phoenix:tt_prune runOnChange:false endDelimiter:/ splitStatements:true
-- =====================================================================================
-- Oracle objects that lose their purpose once TT / TICKETEVOLUTION live on PostgreSQL.
-- Ordered so that each step leaves the database compiling. Steps 1-4 are safe before
-- the data copy; step 5 ONLY after the PostgreSQL copy has been verified
-- (pg_migration/run_oradata2pg.sh + row-count/checksum comparison) and the stubs
-- (tt_stubs.sql) + replicas (tt_maintenance_replica.sql) are in place.
-- UNTESTED DRAFT -- no Oracle instance available (README.md).
-- =====================================================================================

-- 1. Scheduler jobs now running on PostgreSQL (pg_cron, migration/pgsql/_support/30_pg_cron_jobs.sql)
BEGIN
    FOR j IN (SELECT owner, job_name FROM dba_scheduler_jobs
              WHERE (owner = 'TT' AND job_name IN ('CHECK_RESOLVED_TICKETS', 'CHECK_TICKET_STATUS', 'RESOLVE_DNIDS_TICKETS'))
                 OR (owner = 'TICKETEVOLUTION' AND job_name = 'INCREMENTAL_UPDATE'))
    LOOP
        DBMS_SCHEDULER.DROP_JOB(j.owner || '.' || j.job_name, force => TRUE);
    END LOOP;
END;
/

-- 2. BIREADER's 12 one-to-one wrapper views: BIREADER reads PostgreSQL directly.
BEGIN
    FOR v IN (SELECT view_name FROM dba_views WHERE owner = 'BIREADER' AND view_name LIKE 'V\_TT\_%' ESCAPE '\')
    LOOP
        EXECUTE IMMEDIATE 'DROP VIEW bireader.' || v.view_name;
    END LOOP;
END;
/

-- 3. The 22 inbound foreign keys into TT (ddl/migrated/constraints/fk-constraints.pg.sql,
--    "FK-INTO-TT" list in README.md). Columns stay as logical references; integrity is
--    now the bridge callbacks' job (tt.bridge_callback).
BEGIN
    FOR c IN (SELECT c.owner, c.table_name, c.constraint_name
              FROM dba_constraints c JOIN dba_constraints r ON r.owner = c.r_owner AND r.constraint_name = c.r_constraint_name
              WHERE c.constraint_type = 'R' AND r.owner = 'TT' AND c.owner <> 'TT')
    LOOP
        EXECUTE IMMEDIATE 'ALTER TABLE ' || c.owner || '.' || c.table_name || ' DROP CONSTRAINT ' || c.constraint_name;
    END LOOP;
END;
/

-- 4. Real package bodies/specs and triggers -> replaced by tt_stubs.sql (which must be
--    applied right after this step, in the same change window). UTIL has no external
--    caller and gets no stub; its three jobs are already gone (step 1).
DROP PACKAGE tt.util
/
DROP PACKAGE tt.ticket_interface_state
/
DROP TRIGGER tt.ticket_update_trg
/
DROP TRIGGER tt.todo_item_update_trg
/
-- (tt.event_interface, tt.ticket_interface, tt.escalation_interface, tt.osag_notify,
--  tt.event_interface_state are CREATE OR REPLACEd by tt_stubs.sql -- not dropped here,
--  so dependent packages never go invalid.)

-- 5. Tables -- ONLY after data verification. Listed, not executed by default.
--    TT (34): see ddl/generated/tables/TT*.sql; TICKETEVOLUTION (3): tickev, state, recalc.
--    Suggested: RENAME to <name>_migrated first, keep one release cycle, then DROP.
-- BEGIN
--     FOR t IN (SELECT owner, table_name FROM dba_tables WHERE owner IN ('TT','TICKETEVOLUTION')
--               AND table_name NOT IN ('BRIDGE_CONFIG','HOST_MAINTENANCE_STATE','EVENT_MIN','TICKET_MIN','EVENT_TYPE_REF'))
--     LOOP
--         EXECUTE IMMEDIATE 'ALTER TABLE ' || t.owner || '.' || t.table_name || ' RENAME TO ' || SUBSTR(t.table_name, 1, 21) || '_migrated';
--     END LOOP;
-- END;
-- /
