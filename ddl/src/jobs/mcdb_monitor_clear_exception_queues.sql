BEGIN
    sys.dbms_scheduler.create_job(
            job_name => '"MCDB_MONITOR"."CLEAR_EXCEPTION_QUEUES_JOB"',
            job_type => 'PLSQL_BLOCK',
            job_action => 'begin
                    MCDB_MONITOR.NOOP_CONSUMER.CLEAN_QUEUE(''MCDB_MONITOR.AQ$_PLOG_MESSAGES_TABLE_E'');
                end;',
            repeat_interval => 'FREQ=HOURLY',
            start_date => systimestamp at time zone 'Europe/Vienna',
            job_class => '"DEFAULT_JOB_CLASS"',
            auto_drop => TRUE,
            enabled => FALSE);
    sys.dbms_scheduler.set_attribute( name => '"MCDB_MONITOR"."CLEAR_EXCEPTION_QUEUES_JOB"', attribute => 'max_run_duration', value => numtodsinterval(2, 'minute'));
    sys.dbms_scheduler.set_attribute( name => '"MCDB_MONITOR"."CLEAR_EXCEPTION_QUEUES_JOB"', attribute => 'raise_events', value => dbms_scheduler.job_failed + dbms_scheduler.job_chain_stalled);
    sys.dbms_scheduler.enable( '"MCDB_MONITOR"."CLEAR_EXCEPTION_QUEUES_JOB"' );
END;
/
