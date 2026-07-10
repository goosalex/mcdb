--liquibase formatted sql logicalFilePath:pkgb/fw_delete_auto_ip_groups_test.sql
--changeset sys:1 runOnChange:true endDelimiter:/ contextFilter:unit-tests
CREATE OR REPLACE PACKAGE BODY FW.DELETE_AUTO_IP_GROUPS_TEST IS
  C_MEMBER_TYPE_ID CONSTANT NUMBER := 5;
  C_MEMBER_USAGE_ID CONSTANT NUMBER := 10;

  PROCEDURE assert_equals(p_expected NUMBER, p_actual NUMBER, p_message VARCHAR2) IS
  BEGIN
    IF p_expected != p_actual THEN
      raise_application_error(
        -20000,
        'unit-test ' || p_message || ': expected=' || p_expected || ', actual=' || p_actual
      );
    END IF;
  END assert_equals;

  PROCEDURE cleanup_test_rows IS
  BEGIN
    DELETE FROM FW.IP_GROUP_MEMBER WHERE ID BETWEEN 999710 AND 999799;
    DELETE FROM FW.IP_GROUP WHERE ID BETWEEN 999710 AND 999799;
    COMMIT;
  END cleanup_test_rows;

  PROCEDURE test_null_args IS
    l_count NUMBER;
  BEGIN
    cleanup_test_rows;

    INSERT INTO FW.IP_GROUP (ID, VERSION, NAME, AUTOMATIC)
    VALUES (999710, 0, 'null_args_control', 1);

    FW.DELETE_AUTO_IP_GROUPS(NULL, NULL, NULL);

    SELECT COUNT(*) INTO l_count FROM FW.IP_GROUP WHERE ID = 999710;
    assert_equals(1, l_count, 'test_null_args keeps unrelated ip_group');

    cleanup_test_rows;
  END test_null_args;

  PROCEDURE test_delete_group_and_member IS
    l_group_count NUMBER;
    l_member_count NUMBER;
  BEGIN
    cleanup_test_rows;

    INSERT INTO FW.IP_GROUP (ID, VERSION, NAME, AUTOMATIC)
    VALUES (999720, 0, 'delete_group', 1);

    INSERT INTO FW.IP_GROUP_MEMBER (ID, IP_GROUP_ID, MEMBER_TYPE_ID, MEMBER_USAGE_ID, SUBTRACT)
    VALUES (999721, 999720, C_MEMBER_TYPE_ID, C_MEMBER_USAGE_ID, 0);

    FW.DELETE_AUTO_IP_GROUPS(999720, NULL, NULL);

    SELECT COUNT(*) INTO l_member_count FROM FW.IP_GROUP_MEMBER WHERE ID = 999721;
    SELECT COUNT(*) INTO l_group_count FROM FW.IP_GROUP WHERE ID = 999720;

    assert_equals(0, l_member_count, 'test_delete_group_and_member deletes ip_group_member');
    assert_equals(0, l_group_count, 'test_delete_group_and_member deletes ip_group');

    cleanup_test_rows;
  END test_delete_group_and_member;

  PROCEDURE test_unrelated_groups_unchanged IS
    l_target_count NUMBER;
    l_target_member_count NUMBER;
    l_other_group_count NUMBER;
    l_other_member_count NUMBER;
  BEGIN
    cleanup_test_rows;

    INSERT INTO FW.IP_GROUP (ID, VERSION, NAME, AUTOMATIC)
    VALUES (999750, 0, 'target_auto_group', 1);

    INSERT INTO FW.IP_GROUP (ID, VERSION, NAME, AUTOMATIC)
    VALUES (999751, 0, 'other_auto_group', 1);

    INSERT INTO FW.IP_GROUP_MEMBER (ID, IP_GROUP_ID, MEMBER_TYPE_ID, MEMBER_USAGE_ID, SUBTRACT)
    VALUES (999752, 999750, C_MEMBER_TYPE_ID, C_MEMBER_USAGE_ID, 0);

    INSERT INTO FW.IP_GROUP_MEMBER (ID, IP_GROUP_ID, MEMBER_TYPE_ID, MEMBER_USAGE_ID, SUBTRACT)
    VALUES (999753, 999751, C_MEMBER_TYPE_ID, C_MEMBER_USAGE_ID, 0);

    FW.DELETE_AUTO_IP_GROUPS(999750, NULL, NULL);

    SELECT COUNT(*) INTO l_target_count FROM FW.IP_GROUP WHERE ID = 999750;
    SELECT COUNT(*) INTO l_target_member_count FROM FW.IP_GROUP_MEMBER WHERE ID = 999752;
    SELECT COUNT(*) INTO l_other_group_count FROM FW.IP_GROUP WHERE ID = 999751;
    SELECT COUNT(*) INTO l_other_member_count FROM FW.IP_GROUP_MEMBER WHERE ID = 999753;

    assert_equals(0, l_target_count, 'test_unrelated_groups_unchanged deletes target group');
    assert_equals(0, l_target_member_count, 'test_unrelated_groups_unchanged deletes target member');
    assert_equals(1, l_other_group_count, 'test_unrelated_groups_unchanged keeps unrelated group');
    assert_equals(1, l_other_member_count, 'test_unrelated_groups_unchanged keeps unrelated member');

    cleanup_test_rows;
  END test_unrelated_groups_unchanged;

  PROCEDURE test_non_automatic_group_unchanged IS
    l_group_count NUMBER;
    l_member_count NUMBER;
  BEGIN
    cleanup_test_rows;

    INSERT INTO FW.IP_GROUP (ID, VERSION, NAME, AUTOMATIC)
    VALUES (999760, 0, 'non_automatic_group', 0);

    INSERT INTO FW.IP_GROUP_MEMBER (ID, IP_GROUP_ID, MEMBER_TYPE_ID, MEMBER_USAGE_ID, SUBTRACT)
    VALUES (999761, 999760, C_MEMBER_TYPE_ID, C_MEMBER_USAGE_ID, 0);

    FW.DELETE_AUTO_IP_GROUPS(999760, NULL, NULL);

    SELECT COUNT(*) INTO l_group_count FROM FW.IP_GROUP WHERE ID = 999760;
    SELECT COUNT(*) INTO l_member_count FROM FW.IP_GROUP_MEMBER WHERE ID = 999761;

    assert_equals(1, l_group_count, 'test_non_automatic_group_unchanged keeps non-automatic group');
    assert_equals(1, l_member_count, 'test_non_automatic_group_unchanged keeps non-automatic member');

    cleanup_test_rows;
  END test_non_automatic_group_unchanged;

  PROCEDURE test_member_ip_group_fk_violation IS
    l_violation_raised BOOLEAN := FALSE;
  BEGIN
    cleanup_test_rows;

    INSERT INTO FW.IP_GROUP (ID, VERSION, NAME, AUTOMATIC)
    VALUES (999740, 0, 'target_group', 1);

    INSERT INTO FW.IP_GROUP (ID, VERSION, NAME, AUTOMATIC)
    VALUES (999741, 0, 'holder_group', 1);

    INSERT INTO FW.IP_GROUP_MEMBER (ID, IP_GROUP_ID, MEMBER_TYPE_ID, MEMBER_USAGE_ID, SUBTRACT, MEMBER_IP_GROUP_ID)
    VALUES (999744, 999741, C_MEMBER_TYPE_ID, C_MEMBER_USAGE_ID, 0, 999740);

    BEGIN
      FW.DELETE_AUTO_IP_GROUPS(999740, 999740, NULL);
    EXCEPTION
      WHEN OTHERS THEN
        IF SQLCODE = -2292 THEN
          l_violation_raised := TRUE;
        ELSE
          RAISE;
        END IF;
    END;

    IF NOT l_violation_raised THEN
      raise_application_error(
        -20000,
        'unit-test test_member_ip_group_fk_violation: expected FK violation ORA-02292'
      );
    END IF;

    cleanup_test_rows;
  END test_member_ip_group_fk_violation;

  PROCEDURE run_all IS
  BEGIN
    test_null_args;
    test_delete_group_and_member;
    test_unrelated_groups_unchanged;
    test_non_automatic_group_unchanged;
    test_member_ip_group_fk_violation;
  END run_all;
END DELETE_AUTO_IP_GROUPS_TEST;
/
