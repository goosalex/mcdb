/*
 * this script commits the DBMS scheduler jobs for the prx schema
 * run it as user prx!!
 */

BEGIN

    -- check every day for old miscategorization entries and remove them
    DBMS_SCHEDULER.create_job (
            job_name        => 'prx.cleanup_url_miscat',
            job_type        => 'PLSQL_BLOCK',
            job_action      => 'BEGIN delete from prx.url_miscategorization where creation_date < TRUNC(SYSDATE) - (5 * 365); END;',
            start_date      => SYSTIMESTAMP AT TIME ZONE 'Europe/Zurich',
            repeat_interval => 'freq=daily; byhour=04; byminute=04; bysecond=0;',
            end_date        => NULL,
            enabled         => TRUE,
            job_class       =>  'mc_jobs',
            comments        => 'job to remove old URL miscategorization requests');

END;
/
