BEGIN
    sys.dbms_scheduler.create_job(
            job_name => '"MCDB_CHECKS"."CONSISTENCY_CHECKS_SYSLOG_JOB"',
            job_type => 'PLSQL_BLOCK',
            job_action => 'begin
    MCDB_CHECKS.CONSISTENCY.EXECUTE_CHECKS_GROUP(''default'', false, true);
end;',
            repeat_interval => 'FREQ=DAILY',
            start_date => trunc(systimestamp at time zone 'Europe/Vienna')  + 1 + 10/24,
            job_class => '"DEFAULT_JOB_CLASS"',
            auto_drop => TRUE,
            enabled => FALSE);
    sys.dbms_scheduler.set_attribute( name => '"MCDB_CHECKS"."CONSISTENCY_CHECKS_SYSLOG_JOB"', attribute => 'max_run_duration', value => numtodsinterval(2, 'minute'));
    sys.dbms_scheduler.set_attribute( name => '"MCDB_CHECKS"."CONSISTENCY_CHECKS_SYSLOG_JOB"', attribute => 'raise_events', value => dbms_scheduler.job_failed + dbms_scheduler.job_chain_stalled);
    sys.dbms_scheduler.enable( '"MCDB_CHECKS"."CONSISTENCY_CHECKS_SYSLOG_JOB"' );
END;
/
