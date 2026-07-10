BEGIN
    -- submit job to auto resolve customer incident tickets
    -- that have ALLCLEAN as their last event
    DBMS_SCHEDULER.create_job (
            job_name        => 'tt.resolve_dnids_tickets',
            job_type        => 'PLSQL_BLOCK',
            job_action      => 'BEGIN tt.util.check_dnids_tickets_to_resolve; END;',
            start_date      => SYSTIMESTAMP AT TIME ZONE 'Europe/Zurich',
            repeat_interval => 'freq=daily; byhour=7; byminute=0; bysecond=0;',
            end_date        => NULL,
            enabled         => TRUE,
            job_class       =>  'mc_jobs',
            comments        => 'job to resolve old DNIDS tickets daily at 7h');
END;
/
