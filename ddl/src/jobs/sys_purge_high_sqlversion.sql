/* SYS job that automatically purges SQL with high version count from
   the shared pool. High version counts (insufficient cursor sharing)
   can cause catastrophic performance.
 */
BEGIN
  DBMS_SCHEDULER.CREATE_JOB (
  job_name => 'SYS.PURGE_HIGH_SQLVERSION',
  job_type => 'PLSQL_BLOCK',
  job_action => 'begin
  for r in (select address, hash_value, version_count
            from v$sqlarea
            where version_count > 199
            order by version_count desc) loop
    DBMS_SHARED_POOL.purge(r.ADDRESS ||'', ''|| r.hash_value, ''C'');
  end loop;
end;',
  number_of_arguments => 0,
  start_date => SYSTIMESTAMP AT TIME ZONE 'Europe/Zurich',
  repeat_interval => 'FREQ=HOURLY',
  end_date => NULL,
  enabled => TRUE,
  auto_drop => FALSE,
  comments => 'Purge SQL with high version count from shared pool');

  DBMS_SCHEDULER.SET_ATTRIBUTE(
  name => 'SYS.PURGE_HIGH_SQLVERSION',
  attribute => 'store_output', value => TRUE);

  DBMS_SCHEDULER.SET_ATTRIBUTE(
  name => 'SYS.PURGE_HIGH_SQLVERSION',
  attribute => 'logging_level', value => DBMS_SCHEDULER.LOGGING_OFF);

END;
/
