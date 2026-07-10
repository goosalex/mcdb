-- ---------------------------------------------------------
--
-- LOGON trigger to set NLS date formats for all sessions
--
-- We need this for Datanucleus to work properly
-- Setting default values for all sessions via NLS_INSTANCE_PARAMETERS
-- is currently not recommended by Oracle
-- cf. https://support.oracle.com/epmos/faces/DocumentDisplay?id=241047.1
--
-- This is executed as user 'SYS'
-- 
-- ---------------------------------------------------------
CREATE OR REPLACE TRIGGER nls_login_trigger
AFTER LOGON ON DATABASE
BEGIN
  EXECUTE IMMEDIATE 'ALTER SESSION SET NLS_DATE_FORMAT=''YYYY-MM-DD''';
  EXECUTE IMMEDIATE 'ALTER SESSION SET NLS_TIME_FORMAT=''HH24:MI:SSXFF2''';
  EXECUTE IMMEDIATE 'ALTER SESSION SET NLS_TIME_TZ_FORMAT=''HH24:MI:SSXFF2 TZR''';
  EXECUTE IMMEDIATE 'ALTER SESSION SET NLS_TIMESTAMP_FORMAT=''YYYY-MM-DD HH24:MI:SSXFF2''';
  EXECUTE IMMEDIATE 'ALTER SESSION SET NLS_TIMESTAMP_TZ_FORMAT=''YYYY-MM-DD HH24:MI:SSXFF2 TZR''';
END nls_login_trigger;
/
