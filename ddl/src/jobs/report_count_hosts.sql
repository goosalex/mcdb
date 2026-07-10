BEGIN
    -- run host count on the last day of the month
    DBMS_SCHEDULER.create_job (
            job_name        => 'report.count_hosts',
            job_type        => 'PLSQL_BLOCK',
            job_action      => 'BEGIN report.osag_channel.count_hosts; END;',
            start_date      => SYSTIMESTAMP AT TIME ZONE 'Europe/Zurich',
            repeat_interval => 'freq=monthly; bymonthday=-1; byhour=23;',
            end_date        => NULL,
            enabled         => TRUE,
            job_class       =>  'mc_jobs',
            comments        => 'job to run host count on the last day of the month');
END;
/
