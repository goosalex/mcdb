BEGIN
  -- submit the job that checks if there are resolved tickets to close
  -- this job runs every hour
  DBMS_SCHEDULER.create_job (
  job_name        => 'ticketevolution.incremental_update',
  job_type        => 'PLSQL_BLOCK',
  job_action      => 'BEGIN ticketevolution.CALCULATOR.materialize_incremental; END;',
  start_date      => SYSTIMESTAMP AT TIME ZONE 'Europe/Zurich',
  repeat_interval => 'freq=hourly; byminute=0; bysecond=0;',
  end_date        => NULL,
  enabled         => TRUE,
  job_class       =>  'mc_jobs',
  comments        => 'job incrementally update ticketevolution data');
END;
/
