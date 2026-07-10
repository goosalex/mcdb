-- -----------------------------------------------------------------------------
--
-- create_job_sync_domain_scheduler.sql: Create job to periodically start
--	                                     the sync domain scheduler
--
-- -----------------------------------------------------------------------------

BEGIN

    DBMS_SCHEDULER.create_job (
            job_name        => 'auth.sync_domain_scheduler',
            job_type        => 'PLSQL_BLOCK',
            job_action      => 'BEGIN osag_auth_passport.sync_domain_scheduler; END;',
            start_date      => SYSTIMESTAMP AT TIME ZONE 'Europe/Zurich',
            repeat_interval => 'freq=minutely; interval=5; bysecond=0;',
            end_date        => NULL,
            enabled         => TRUE,
            job_class       =>  'mc_jobs',
            comments        => 'job to periodically start the sync domain scheduler');

END;
/
