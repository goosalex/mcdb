BEGIN

    -- submit the job to monitor maintenance status of hosts every minute
    DBMS_SCHEDULER.create_job (
            job_name        => 'mc.update_host_maint_status',
            job_type        => 'PLSQL_BLOCK',
            job_action      => 'BEGIN MC.OSAG_MAINTSYNC.UPDATE_HOST_MAINT_STATUS; END;',
            start_date      => SYSTIMESTAMP AT TIME ZONE 'Europe/Zurich',
            repeat_interval => 'freq=minutely; bysecond=0;',
            end_date        => NULL,
            enabled         => TRUE,
            job_class       =>  'mc_jobs',
            comments        => 'job to update the host maintenance status every minute');

    -- submit the job to monitor maintenance status of isp links every minute
    DBMS_SCHEDULER.create_job (
            job_name        => 'mc.update_isp_link_maint_status',
            job_type        => 'PLSQL_BLOCK',
            job_action      => 'BEGIN MC.OSAG_MAINTSYNC.UPDATE_ISP_LINK_MAINT_STATUS; END;',
            start_date      => SYSTIMESTAMP AT TIME ZONE 'Europe/Zurich',
            repeat_interval => 'freq=minutely; bysecond=0;',
            end_date        => NULL,
            enabled         => TRUE,
            job_class       =>  'mc_jobs',
            comments        => 'job to update the ISP link maintenance status every minute');

END;
/
