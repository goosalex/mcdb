BEGIN

    DBMS_SCHEDULER.create_job (
            job_name        => 'guma2.prune_syslog_messages',
            job_type        => 'PLSQL_BLOCK',
            job_action      => 'BEGIN guma2.osag_guma.prune_syslog_message(183); END;',
            start_date      => SYSTIMESTAMP AT TIME ZONE 'Europe/Zurich',
            repeat_interval => 'freq=daily; byhour=2; byminute=0; bysecond=0;',
            end_date        => NULL,
            enabled         => FALSE,
            job_class       =>  'mc_jobs',
            comments        => 'job purge old syslog messages daily at 2h');
END;
/
