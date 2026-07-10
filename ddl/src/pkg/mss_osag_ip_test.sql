--liquibase formatted sql logicalFilePath:pkg/mss_osag_ip_test.sql
--changeset sys:1 runOnChange:true endDelimiter:/ contextFilter:unit-tests
CREATE OR REPLACE PACKAGE MSS.OSAG_IP_TEST IS
  procedure test_num2ipv6;
  procedure test_ipv62nums;
END OSAG_IP_TEST;
/
