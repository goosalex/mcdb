BEGIN

    -- submit the job to remove old DMARC reports, before faulty Perl scripts can block on clumsy housekeeping attempts
    DBMS_SCHEDULER.create_job (
            job_name        => 'mail.cleanup_dmarc_reports',
            job_type        => 'PLSQL_BLOCK',
            job_action      => 'BEGIN MAIL.DMARC_CLEANUP.cleanup_reports_aged_days(740); END;',
            start_date      => SYSTIMESTAMP AT TIME ZONE 'Europe/Zurich',
            repeat_interval => 'freq=daily; byhour=18; byminute=08;',
            end_date        => NULL,
            enabled         => TRUE,
            job_class       =>  'mc_jobs',
            comments        => 'Clear old DMARC reports, (older than 740 days) so dmarc scripts will not block over it.');

END;
/
