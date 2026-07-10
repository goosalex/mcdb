/*
 * Create a job group that holds all our jobs
 */

BEGIN
  DBMS_SCHEDULER.CREATE_JOB_CLASS (
   job_class_name             =>  'MC_JOBS');
  
  -- set log retention time to 1 day
  DBMS_SCHEDULER.SET_ATTRIBUTE(
    name => 'SYS."MC_JOBS"',
    attribute => 'log_history', value => 1);
    
END;
/

GRANT EXECUTE ON SYS.MC_JOBS TO PUBLIC;
