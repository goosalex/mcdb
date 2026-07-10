BEGIN
    -- submit the job that checks if there are tickets staying to long in a
    -- certain status and if yes, change their state / reset the worker
    -- this job runs every minute
    DBMS_SCHEDULER.create_job (
            job_name        => 'tt.check_ticket_status',
            job_type        => 'PLSQL_BLOCK',
            job_action      => 'BEGIN tt.util.check_ticket_status; END;',
            start_date      => SYSTIMESTAMP AT TIME ZONE 'Europe/Zurich',
            repeat_interval => 'freq=minutely; bysecond=0;',
            end_date        => NULL,
            enabled         => TRUE,
            job_class       =>  'mc_jobs',
            comments        => 'job to check for necessary status changes in tickets every minute');
END;
/
