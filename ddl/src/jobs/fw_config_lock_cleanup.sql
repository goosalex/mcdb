BEGIN

    DBMS_SCHEDULER.create_job (
            job_name        => 'fw.config_lock_cleanup',
            job_type        => 'PLSQL_BLOCK',
            job_action      => 'BEGIN osag_fw.config_lock_cleanup; END;',
            start_date      => SYSTIMESTAMP AT TIME ZONE 'Europe/Zurich',
            repeat_interval => 'freq=hourly; interval=1; byminute=0;',
            end_date        => NULL,
            enabled         => TRUE,
            job_class       => 'mc_jobs',
            comments        => 'job to periodically clean outdated MING config locks');

END;
/
