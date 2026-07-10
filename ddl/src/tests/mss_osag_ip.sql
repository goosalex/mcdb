--liquibase formatted sql logicalFilePath:tests/mss_osag_ip.sql
--changeset sys:1 runAlways:true endDelimiter:/ contextFilter:unit-tests
begin
  MSS.OSAG_IP_TEST.test_num2ipv6();
  MSS.OSAG_IP_TEST.test_ipv62nums();
end;
/
