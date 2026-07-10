BEGIN
    -- submit the job that checks if there are resolved tickets to close
    -- this job runs every hour
    DBMS_SCHEDULER.create_job (
            job_name        => 'tt.check_resolved_tickets',
            job_type        => 'PLSQL_BLOCK',
            job_action      => 'BEGIN tt.util.check_resolved_tickets; END;',
            start_date      => SYSTIMESTAMP AT TIME ZONE 'Europe/Zurich',
            repeat_interval => 'freq=hourly; byminute=0; bysecond=0;',
            end_date        => NULL,
            enabled         => TRUE,
            job_class       =>  'mc_jobs',
            comments        => 'job to check if there are resolved tickets to close every hour');
END;
/
