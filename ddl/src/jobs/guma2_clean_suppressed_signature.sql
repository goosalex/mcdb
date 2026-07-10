BEGIN
    -- clean up guma signature suppressions
    -- that are already beyond their end date
    -- i.e. are not in place any longer
    DBMS_SCHEDULER.create_job (
            job_name        => 'guma2.clean_suppressed_signature',
            job_type        => 'PLSQL_BLOCK',
            job_action      => 'BEGIN guma2.osag_guma.clean_suppressed_signature(); END;',
            start_date      => SYSTIMESTAMP AT TIME ZONE 'Europe/Zurich',
            repeat_interval => 'freq=hourly; byminute=20; bysecond=0;',
            end_date        => NULL,
            enabled         => FALSE,
            job_class       =>  'mc_jobs',
            comments        => 'job to clean up old suppressed signatures at 20 min past every hour');


END;
/
