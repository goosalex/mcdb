--liquibase formatted sql logicalFilePath:tests/aserto.sql
--changeset sys:1 runAlways:true endDelimiter:/ contextFilter:unit-tests
begin
  delete from MCDB_MONITOR.PLOG_OUTPUT;
  commit;
  -- run test suite
  ASERTO_TEST.E2ETEST.TEST_CREATE();
  commit;
  ASERTO_TEST.E2ETEST.TEST_DELETE();
  commit;
  -- give messages time to reach the log table from the queue
  DBMS_SESSION.sleep(1);
  ASERTO_TEST.E2ETEST.assert_logs();
end;
/
