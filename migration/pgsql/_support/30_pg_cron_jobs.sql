-- migration/pgsql/_support/30_pg_cron_jobs.sql
--
-- PostgreSQL replacement for the four DBMS_SCHEDULER jobs of the TT closure
-- (ddl/src/jobs/tt_check_resolved_tickets.sql, tt_check_ticket_status.sql,
-- tt_resolve_dnids_tickets.sql, ticketevolution_incremental_update.sql). Oracle ran
-- them in job class mc_jobs, Europe/Zurich. pg_cron schedules are evaluated in the
-- server's `cron.timezone` (set it to Europe/Zurich in postgresql.conf for parity).
--
-- Guarded: pg_cron is an extension that may not be installed on a test instance (it
-- is not in mcdb_tmpl). When absent, this file only prints a NOTICE -- the jobs are
-- then expected to be driven by the container's cron (Phase 5), with the SAME four
-- CALL statements. The COMMIT-bearing procedures (tt.util_close_old_dev_tickets is NOT
-- scheduled here -- Oracle did not schedule it either; ticketevolution's
-- materialize_incremental is) must run as top-level CALLs, which is what pg_cron does.

DO $do$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        RAISE NOTICE 'pg_cron not installed: TT jobs not scheduled here (see file header)';
        RETURN;
    END IF;
    -- idempotent: unschedule by name, then schedule
    PERFORM cron.unschedule(jobname) FROM cron.job
     WHERE jobname IN ('tt.check_resolved_tickets', 'tt.check_ticket_status',
                       'tt.resolve_dnids_tickets', 'ticketevolution.incremental_update');
    PERFORM cron.schedule('tt.check_resolved_tickets',          '0 * * * *',  'CALL tt.util_check_resolved_tickets()');
    PERFORM cron.schedule('tt.check_ticket_status',             '* * * * *',  'CALL tt.util_check_ticket_status()');
    PERFORM cron.schedule('tt.resolve_dnids_tickets',           '0 7 * * *',  'CALL tt.util_check_dnids_tickets_to_resolve()');
    PERFORM cron.schedule('ticketevolution.incremental_update', '*/5 * * * *', 'CALL ticketevolution.calculator_materialize_incremental()');
END
$do$;
