BEGIN

    -- submit the job that updates the release installation counts
    -- this job runs 4 times an hour (5,20,35,50)
    DBMS_SCHEDULER.create_job (
            job_name        => 'mss.osag_software_release_update',
            job_type        => 'PLSQL_BLOCK',
            job_action      => 'BEGIN mss.osag_software_release.update_release_installations; END;',
            start_date      => SYSTIMESTAMP AT TIME ZONE 'Europe/Zurich',
            repeat_interval => 'freq=hourly; byminute=5,20,35,50; bysecond=0;',
            end_date        => NULL,
            enabled         => TRUE,
            job_class       => 'mc_jobs',
            comments        => 'job to update the release installation counts every 15 minutes');
END;
/
