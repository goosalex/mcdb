--liquibase formatted sql logicalFilePath:tests/fw_delete_auto_ip_groups.sql
--changeset sys:1 runAlways:true endDelimiter:/ contextFilter:unit-tests
begin
  FW.DELETE_AUTO_IP_GROUPS_TEST.run_all();
end;
/
