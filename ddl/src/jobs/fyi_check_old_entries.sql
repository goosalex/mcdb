/*
 * this script is used to schedule the procedures i.e. from fyi.OSAG_FYI that automate
 * some tasks for the FYI Notification Framework
 * see fyi.OSAG_FYI to get detailed information about the scheduled procedures.
 *
 */

BEGIN

    -- submit the job that checks and deletes old entries in the fyi tables
    -- this job runs daily
    DBMS_SCHEDULER.create_job (
            job_name        => 'fyi.check_old_entries',
            job_type        => 'PLSQL_BLOCK',
            job_action      => 'BEGIN fyi.osag_fyi.check_old_entries; END;',
            start_date      => SYSTIMESTAMP AT TIME ZONE 'Europe/Zurich',
            repeat_interval => 'freq=daily; byhour=3; byminute=0; bysecond=0;',
            end_date        => NULL,
            enabled         => TRUE,
            job_class       => 'mc_jobs',
            comments        => 'job purges old entries in message_history, notification_event and target tables daily at 3h');

END;
/