/* SYS job that automatically kills blocking sessions.
 */
BEGIN
  DBMS_SCHEDULER.CREATE_JOB (
  job_name => 'SYS.KILL_BLOCKERS',
  job_type => 'PLSQL_BLOCK',
  job_action => 'begin
 for n in (select 1 from MCDB_MONITOR.LAST_CONSISTENCY_CHECK_RESULTS
           where check_id=''SEL_session_wait''
             and MESSAGE is not null) loop
   for r in (SELECT s.sid, s.SERIAL#
             FROM dba_blockers b, v$session s
            WHERE s.sid = b.holding_session
              and s.USERNAME != ''SYS''
            ) loop
     execute immediate ''ALTER SYSTEM KILL SESSION ''''''||r.sid||'',''||r.serial#||'''''''';
   end loop;
 end loop;
end;',
  number_of_arguments => 0,
  start_date => SYSTIMESTAMP AT TIME ZONE 'Europe/Zurich',
  repeat_interval => 'FREQ=MINUTELY; INTERVAL=10',
  end_date => NULL,
  enabled => TRUE,
  auto_drop => FALSE,
  comments => 'Kill blocking sessions');

  DBMS_SCHEDULER.SET_ATTRIBUTE(
  name => 'SYS.KILL_BLOCKERS',
  attribute => 'store_output', value => TRUE);

  DBMS_SCHEDULER.SET_ATTRIBUTE(
  name => 'SYS.KILL_BLOCKERS',
  attribute => 'logging_level', value => DBMS_SCHEDULER.LOGGING_OFF);

END;
/
