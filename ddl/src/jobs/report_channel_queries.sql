BEGIN

    -- check every minute for queries to run
    DBMS_SCHEDULER.create_job (
            job_name        => 'report.channel_queries',
            job_type        => 'PLSQL_BLOCK',
            job_action      => 'BEGIN report.osag_channel.run_queries; END;',
            start_date      => SYSTIMESTAMP AT TIME ZONE 'Europe/Zurich',
            repeat_interval => 'freq=minutely; bysecond=0;',
            end_date        => NULL,
            enabled         => TRUE,
            job_class       =>  'mc_jobs',
            comments        => 'job to run necessary channel queries every minute');
END;
/
