--liquibase formatted sql logicalFilePath:pkg/fw_delete_auto_ip_groups_test.sql
--changeset sys:1 runOnChange:true endDelimiter:/ contextFilter:unit-tests
CREATE OR REPLACE PACKAGE FW.DELETE_AUTO_IP_GROUPS_TEST IS
  PROCEDURE test_null_args;
  PROCEDURE test_delete_group_and_member;
  PROCEDURE test_unrelated_groups_unchanged;
  PROCEDURE test_non_automatic_group_unchanged;
  PROCEDURE test_member_ip_group_fk_violation;
  PROCEDURE run_all;
END DELETE_AUTO_IP_GROUPS_TEST;
/
