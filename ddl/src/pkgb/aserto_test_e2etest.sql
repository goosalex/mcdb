--liquibase formatted sql logicalFilePath:pkgb/aserto_test_e2etest.sql
--changeset sys:1 runOnChange:true contextFilter:unit-tests
--comment: grant permissions here because they are no on PROD and hence never exported
GRANT EXEMPT ACCESS POLICY TO "ASERTO_TEST";
GRANT SELECT,INSERT,UPDATE,DELETE ON stop.COMPANY TO ASERTO_TEST;
GRANT SELECT,INSERT,UPDATE,DELETE ON stop.COMP_COMPTYPE_REF TO ASERTO_TEST;
GRANT SELECT,INSERT,UPDATE,DELETE ON stop.CONTACT TO ASERTO_TEST;
GRANT SELECT,INSERT,UPDATE,DELETE ON stop.CONTACT_LIST TO ASERTO_TEST;
GRANT SELECT,INSERT,UPDATE,DELETE ON stop.CONTACT_HANDLING TO ASERTO_TEST;
GRANT SELECT,INSERT,UPDATE,DELETE ON stop.COMPANY_UNIT TO ASERTO_TEST;
GRANT SELECT,INSERT,UPDATE,DELETE ON mss.SERVICE TO ASERTO_TEST;
GRANT SELECT,INSERT,UPDATE,DELETE ON mss.HOST TO ASERTO_TEST;
GRANT SELECT,INSERT,UPDATE,DELETE ON mss.HOST2SERVICE TO ASERTO_TEST;
GRANT EXECUTE ON auth.OSAG_AUTH TO ASERTO_TEST;
GRANT SELECT,INSERT,UPDATE,DELETE ON auth.login TO ASERTO_TEST;
GRANT SELECT,INSERT,UPDATE,DELETE ON auth.USER_SERVICE_SCOPE TO ASERTO_TEST;
GRANT SELECT,INSERT,UPDATE,DELETE ON auth.USER_COMPANY_UNIT_SCOPE TO ASERTO_TEST;
GRANT SELECT,INSERT,UPDATE,DELETE ON auth.USER_COMPANY_SCOPE TO ASERTO_TEST;
GRANT SELECT,INSERT,UPDATE,DELETE ON auth.USER_PERMISSION TO ASERTO_TEST;
GRANT SELECT,INSERT,UPDATE,DELETE ON auth.profile TO ASERTO_TEST;
GRANT SELECT,INSERT,UPDATE,DELETE ON auth.login2profile TO ASERTO_TEST;
GRANT SELECT ON AUTH.SEQ_PROFILE TO ASERTO_TEST;
GRANT SELECT ON AUTH.SEQ_USER_PERMISSION TO ASERTO_TEST;
GRANT SELECT ON AUTH.SEQ_USER_COMPANY_UNIT_SCOPE TO ASERTO_TEST;
GRANT SELECT ON AUTH.SEQ_USER_COMPANY_SCOPE TO ASERTO_TEST;
GRANT SELECT ON AUTH.SEQ_USER_SERVICE_SCOPE TO ASERTO_TEST;
GRANT SELECT ON MCDB_MONITOR.PLOG_OUTPUT TO ASERTO_TEST;

--changeset sys:2 runOnChange:true endDelimiter:/ contextFilter:unit-tests
CREATE OR REPLACE PACKAGE BODY ASERTO_TEST.E2ETEST IS
  procedure test_create is
    v_ap_id number;
    v_new_permission_id number;
  begin
    -- this line bumps the md5sum :)
    -- company
    insert into stop.company(ID, NAME, SHORT)
    values (C_COMPANY_ID, 'aserto_test', 'aserto');
    insert into stop.COMP_COMPTYPE_REF(COMPANY_ID, COMPTYPE_ID)
    values (C_COMPANY_ID, 1);

    -- company unit
    insert into stop.CONTACT_LIST(id, COMMENTS)
    values (C_GENERIC_ID, 'aserto_cl');
    insert into stop.CONTACT_HANDLING(ID, NAME, COMPANY_ID, EMERGENCY_CONTACT_LIST_ID)
    values (C_GENERIC_ID, 'aserto_ch', C_COMPANY_ID, C_GENERIC_ID);

    insert into stop.COMPANY_UNIT(id, name, company_id, CONTACT_HANDLING_ID)
    values (C_CUNIT_ID, 'aserto_default', C_COMPANY_ID, C_GENERIC_ID);
    update stop.COMPANY set DEFAULT_COMPANY_UNIT_ID = C_CUNIT_ID where id = C_COMPANY_ID;

    insert into stop.COMPANY_UNIT(id, name, company_id, CONTACT_HANDLING_ID)
    values (C_CUNIT2_ID, 'aserto_other', C_COMPANY_ID, C_GENERIC_ID);

    -- host
    insert into mss.host(id, name, OPERATING_SYSTEM_ID, SERVICE_COMPANY_ID, AUTHOR)
    values (C_HOST_ID, 'aserto-ts001-xx-tst-1', 22, C_COMPANY_ID, USER);
    insert into mss.host(id, name, OPERATING_SYSTEM_ID, SERVICE_COMPANY_ID, AUTHOR)
    values (C_HOST2_ID, 'aserto-ts002-xx-tst-1', 22, C_COMPANY_ID, USER);

    -- service
    insert into mss.SERVICE(id, NAME, SERVICE_TYPE_ID, COMPANY_ID, COMPANY_UNIT_ID, SERVICE_LEVEL_ID)
    values (C_SERVICE_ID, 'aserto-ts001-xx-tst', 6, C_COMPANY_ID, C_CUNIT_ID, 0);
    insert into mss.SERVICE(id, NAME, SERVICE_TYPE_ID, COMPANY_ID, COMPANY_UNIT_ID, SERVICE_LEVEL_ID)
    values (C_SERVICE2_ID, 'aserto-ts002-xx-tst', 6, C_COMPANY_ID, null, 0);

    insert into mss.HOST2SERVICE(HOST_ID, SERVICE_ID)
    values (C_HOST_ID, C_SERVICE_ID);
    insert into mss.HOST2SERVICE(HOST_ID, SERVICE_ID)
    values (C_HOST2_ID, C_SERVICE2_ID);

    -- change default BU: changes BU of service2
    update stop.COMPANY set DEFAULT_COMPANY_UNIT_ID = C_CUNIT2_ID where id = C_COMPANY_ID;

    -- login with company scope perms
    insert into stop.contact(ID, SHORT, COMPANY_ID, LASTNAME)
    values (C_LOGIN_1, 'aserto1',C_COMPANY_ID, 'Aserto');
    insert into auth.login(id, login, COMPANY_ID, CONTACT_ID, OIDC_ZITADEL_ID)
    values (C_LOGIN_1, 'aserto1', C_COMPANY_ID, C_LOGIN_1, C_ZITADEL1_ID);

    -- creates profile, login2profile, user_permission, user_company_scope
    auth.OSAG_AUTH.GRANT_USER_ROLE(C_LOGIN_1, 1000); -- mc-cust-access
    auth.OSAG_AUTH.GRANT_USER_ROLE(C_LOGIN_1, 1001); -- mc-cust-admin

    -- login with company unit scope perms
    insert into stop.contact(ID, SHORT, COMPANY_ID, LASTNAME)
    values (C_LOGIN_2, 'aserto2',C_COMPANY_ID, 'Aserto');
    insert into auth.login(id, login, COMPANY_ID, CONTACT_ID, OIDC_ZITADEL_ID)
    values (C_LOGIN_2, 'aserto2', C_COMPANY_ID, C_LOGIN_2, C_ZITADEL2_ID);
    SELECT auth.seq_profile.nextVal INTO v_ap_id FROM dual;
    INSERT INTO auth.profile (id, name, is_automatic) values (v_ap_id, 'automatic profile', 1);
    INSERT INTO auth.login2profile (login_id, profile_id) values (C_LOGIN_2, v_ap_id);
    SELECT auth.seq_user_permission.nextVal INTO v_new_permission_id FROM dual;
    INSERT INTO auth.user_permission(id, user_role_id, profile_id) values (v_new_permission_id, 1002, v_ap_id);
    INSERT INTO auth.USER_COMPANY_UNIT_SCOPE(ID, COMPANY_UNIT_ID, PERMISSION_ID) values (auth.SEQ_USER_COMPANY_UNIT_SCOPE.nextval, C_CUNIT_ID, v_new_permission_id);

    -- login with service scope perms
    insert into stop.contact(ID, SHORT, COMPANY_ID, LASTNAME)
    values (C_LOGIN_3, 'aserto3',C_COMPANY_ID, 'Aserto');
    insert into auth.login(id, login, COMPANY_ID, CONTACT_ID, OIDC_ZITADEL_ID)
    values (C_LOGIN_3, 'aserto3', C_COMPANY_ID, C_LOGIN_3, C_ZITADEL3_ID);
    SELECT auth.seq_profile.nextVal INTO v_ap_id FROM dual;
    INSERT INTO auth.profile (id, name, is_automatic) values (v_ap_id, 'automatic profile', 1);
    INSERT INTO auth.login2profile (login_id, profile_id) values (C_LOGIN_3, v_ap_id);
    SELECT auth.seq_user_permission.nextVal INTO v_new_permission_id FROM dual;
    INSERT INTO auth.user_permission(id, user_role_id, profile_id) values (v_new_permission_id, 1003, v_ap_id);
    INSERT INTO auth.USER_SERVICE_SCOPE(ID, SERVICE_ID, PERMISSION_ID) values (auth.SEQ_USER_SERVICE_SCOPE.nextval, C_SERVICE_ID, v_new_permission_id);

    -- login with MC perms
    insert into stop.contact(ID, SHORT, COMPANY_ID, LASTNAME)
    values (C_LOGIN_4, 'aserto4',C_COMPANY_ID, 'Aserto');
    insert into auth.login(id, login, COMPANY_ID, CONTACT_ID, OIDC_ZITADEL_ID)
    values (C_LOGIN_4, 'aserto4', C_COMPANY_ID, C_LOGIN_4, C_ZITADEL4_ID);
    auth.OSAG_AUTH.GRANT_USER_ROLE(C_LOGIN_4, 201); -- mc-osag-admin

    -- login provisioned only when permissions have been granted already
    insert into stop.contact(ID, SHORT, COMPANY_ID, LASTNAME)
    values (C_LOGIN_5, 'aserto5',C_COMPANY_ID, 'Aserto');
    insert into auth.login(id, login, COMPANY_ID, CONTACT_ID)
    values (C_LOGIN_5, 'aserto5', C_COMPANY_ID, C_LOGIN_5);
    SELECT auth.seq_profile.nextVal INTO v_ap_id FROM dual;
    INSERT INTO auth.profile (id, name, is_automatic) values (v_ap_id, 'automatic profile', 1);
    INSERT INTO auth.login2profile (login_id, profile_id) values (C_LOGIN_5, v_ap_id);
    SELECT auth.seq_user_permission.nextVal INTO v_new_permission_id FROM dual;
    INSERT INTO auth.user_permission(id, user_role_id, profile_id) values (v_new_permission_id, 1003, v_ap_id);
    INSERT INTO auth.USER_SERVICE_SCOPE(ID, SERVICE_ID, PERMISSION_ID) values (auth.SEQ_USER_SERVICE_SCOPE.nextval, C_SERVICE_ID, v_new_permission_id);
    update auth.login set OIDC_ZITADEL_ID = C_ZITADEL5_ID where id = C_LOGIN_5;

    -- login with cert self-service (company + company_unit + service scopes)
    insert into stop.contact(ID, SHORT, COMPANY_ID, LASTNAME)
    values (C_LOGIN_6, 'aserto6', C_COMPANY_ID, 'Aserto');
    insert into auth.login(id, login, COMPANY_ID, CONTACT_ID, OIDC_ZITADEL_ID)
    values (C_LOGIN_6, 'aserto6', C_COMPANY_ID, C_LOGIN_6, C_ZITADEL6_ID);
    SELECT auth.seq_profile.nextVal INTO v_ap_id FROM dual;
    INSERT INTO auth.profile (id, name, is_automatic) values (v_ap_id, 'automatic profile', 1);
    INSERT INTO auth.login2profile (login_id, profile_id) values (C_LOGIN_6, v_ap_id);
    SELECT auth.seq_user_permission.nextVal INTO v_new_permission_id FROM dual;
    INSERT INTO auth.user_permission(id, user_role_id, profile_id) values (v_new_permission_id, 2005, v_ap_id);
    INSERT INTO auth.USER_COMPANY_SCOPE(ID, COMPANY_ID, PERMISSION_ID) values (auth.SEQ_USER_COMPANY_SCOPE.nextval, C_COMPANY_ID, v_new_permission_id);
    INSERT INTO auth.USER_COMPANY_UNIT_SCOPE(ID, COMPANY_UNIT_ID, PERMISSION_ID) values (auth.SEQ_USER_COMPANY_UNIT_SCOPE.nextval, C_CUNIT_ID, v_new_permission_id);
    INSERT INTO auth.USER_SERVICE_SCOPE(ID, SERVICE_ID, PERMISSION_ID) values (auth.SEQ_USER_SERVICE_SCOPE.nextval, C_SERVICE_ID, v_new_permission_id);

    -- login with network requestor (company + company_unit + service scopes)
    insert into stop.contact(ID, SHORT, COMPANY_ID, LASTNAME)
    values (C_LOGIN_7, 'aserto7', C_COMPANY_ID, 'Aserto');
    insert into auth.login(id, login, COMPANY_ID, CONTACT_ID, OIDC_ZITADEL_ID)
    values (C_LOGIN_7, 'aserto7', C_COMPANY_ID, C_LOGIN_7, C_ZITADEL7_ID);
    SELECT auth.seq_profile.nextVal INTO v_ap_id FROM dual;
    INSERT INTO auth.profile (id, name, is_automatic) values (v_ap_id, 'automatic profile', 1);
    INSERT INTO auth.login2profile (login_id, profile_id) values (C_LOGIN_7, v_ap_id);
    SELECT auth.seq_user_permission.nextVal INTO v_new_permission_id FROM dual;
    INSERT INTO auth.user_permission(id, user_role_id, profile_id) values (v_new_permission_id, 2015, v_ap_id);
    INSERT INTO auth.USER_COMPANY_SCOPE(ID, COMPANY_ID, PERMISSION_ID) values (auth.SEQ_USER_COMPANY_SCOPE.nextval, C_COMPANY_ID, v_new_permission_id);
    INSERT INTO auth.USER_COMPANY_UNIT_SCOPE(ID, COMPANY_UNIT_ID, PERMISSION_ID) values (auth.SEQ_USER_COMPANY_UNIT_SCOPE.nextval, C_CUNIT_ID, v_new_permission_id);
    INSERT INTO auth.USER_SERVICE_SCOPE(ID, SERVICE_ID, PERMISSION_ID) values (auth.SEQ_USER_SERVICE_SCOPE.nextval, C_SERVICE_ID, v_new_permission_id);
  end test_create;

  procedure test_delete is
  begin
    AUTH.OSAG_AUTH.delete_login(C_LOGIN_1);
    AUTH.OSAG_AUTH.delete_login(C_LOGIN_2);
    AUTH.OSAG_AUTH.delete_login(C_LOGIN_3);
    AUTH.OSAG_AUTH.delete_login(C_LOGIN_4);
    AUTH.OSAG_AUTH.delete_login(C_LOGIN_5);
    AUTH.OSAG_AUTH.delete_login(C_LOGIN_6);
    AUTH.OSAG_AUTH.delete_login(C_LOGIN_7);

    delete from mss.HOST2SERVICE where HOST_ID = C_HOST_ID and SERVICE_ID = C_SERVICE_ID;
    delete from mss.HOST2SERVICE where HOST_ID = C_HOST2_ID and SERVICE_ID = C_SERVICE2_ID;
    delete from mss.SERVICE where id = C_SERVICE_ID;
    delete from mss.SERVICE where id = C_SERVICE2_ID;
    delete from mss.HOST where id = C_HOST_ID;
    delete from mss.HOST where id = C_HOST2_ID;
    update stop.COMPANY set DEFAULT_COMPANY_UNIT_ID = null where id = C_COMPANY_ID;
    delete from stop.COMPANY_UNIT where id = C_CUNIT_ID;
    delete from stop.COMPANY_UNIT where id = C_CUNIT2_ID;
    delete from stop.CONTACT_HANDLING where id = C_GENERIC_ID;
    delete from stop.CONTACT_LIST where id = C_GENERIC_ID;
    delete from stop.COMP_COMPTYPE_REF where COMPANY_ID = C_COMPANY_ID;
    delete from stop.COMPANY where id = C_COMPANY_ID;
  end test_delete;

  procedure expect_log(p_event varchar2, p_subject varchar2, p_object varchar2, p_expected number default 1) is
    n number;
  begin
    select count(*) into n
    from (select *
          from MCDB_MONITOR.PLOG_OUTPUT
          where message like '{ "specversion": "1.0.2", "type": "ch.open.syncify", %')
    where json_value(json(message), '$.data[0].event_type') = p_event
      and json_value(json(message), '$.data[0].subject_type') = p_subject
      and json_value(json(message), '$.data[0].object_type') = p_object;

    if n != p_expected then
      raise_application_error(-20000, 'unit-test expect_log failed: expected: '|| p_expected ||', but got '|| n
      ||': '|| p_event ||', '|| p_subject ||', '|| p_object);
    end if;
  end expect_log;

  procedure expect_val(p_event varchar2, p_st varchar2, p_s varchar2, p_ot varchar2, p_o varchar2, p_expected number default 1) is
    n number;
  begin
    select count(*) into n
    from (select *
          from MCDB_MONITOR.PLOG_OUTPUT
          where message like '{ "specversion": "1.0.2", "type": "ch.open.syncify", %')
    where json_value(json(message), '$.data[0].event_type') = p_event
      and json_value(json(message), '$.data[0].subject_type') = p_st
      and json_value(json(message), '$.data[0].object_type') = p_ot
      and json_value(json(message), '$.data[0].subject_id') like p_s
      and json_value(json(message), '$.data[0].object_id') like p_o;

    if n != p_expected then
      raise_application_error(-20000, 'unit-test expect_val  failed: expected: '|| p_expected ||', but got '|| n
      ||': '|| p_event ||', '|| p_st ||', '|| p_ot ||', '|| p_s ||', '|| p_o);
    end if;
  end expect_val;

  procedure assert_logs IS
    n number;
  begin
    /* To debug:
     select json_value(json(message), '$.data[0].event_type') event_type,
       json_value(json(message), '$.data[0].subject_type') subject_type,
       json_value(json(message), '$.data[0].subject_id') subject_id,
       json_value(json(message), '$.data[0].relation') relation,
       json_value(json(message), '$.data[0].object_type') object_type,
       json_value(json(message), '$.data[0].object_id') object_id,
       message
  from (select message
from MCDB_MONITOR.PLOG_OUTPUT
where message like '{ "specversion": "1.0.2", "type": "ch.open.syncify", %');
     */
    expect_log('create', 'company_group', 'company');
    expect_log('create', 'company', 'company_object_relation_management');
    expect_log('create', 'company_group_object_relation_management', 'company_object_relation_management');
    expect_log('create', 'company', 'company_unit', 2);
    expect_log('create', 'company_unit', 'company', 2);
    expect_log('create', 'company', 'service', 2);
    expect_log('create', 'service', 'company', 2);
    expect_log('create', 'company_unit', 'service', 2);
    expect_log('create', 'service', 'host', 2);

    expect_val('create', 'user', C_ZITADEL1_ID, 'company', '%', 2);
    expect_val('create', 'user',C_ZITADEL2_ID, 'company_unit', '%');
    expect_val('create', 'user',C_ZITADEL3_ID, 'service', '%');
    expect_val('create', 'user', C_ZITADEL4_ID, 'company_group', '%', 2);
    expect_val('create', 'user',C_ZITADEL5_ID, 'service', '%');
    expect_val('create', 'user', C_ZITADEL6_ID, 'company', '%');
    expect_val('create', 'user', C_ZITADEL6_ID, 'company_unit', '%');
    expect_val('create', 'user', C_ZITADEL6_ID, 'service', '%');
    expect_val('create', 'user', C_ZITADEL7_ID, 'company', '%');
    expect_val('create', 'user', C_ZITADEL7_ID, 'company_unit', '%');
    expect_val('create', 'user', C_ZITADEL7_ID, 'service', '%');


    expect_log('delete', 'company_group', 'company');
    expect_log('delete', 'company', 'company_object_relation_management');
    expect_log('delete', 'company_group_object_relation_management', 'company_object_relation_management');
    expect_log('delete', 'company', 'company_unit', 2);
    expect_log('delete', 'company_unit', 'company', 2);
    expect_log('delete', 'company', 'service', 2);
    expect_log('delete', 'service', 'company', 2);
    expect_log('delete', 'company_unit', 'service', 3);
    expect_log('delete', 'service', 'host', 2);

    expect_val('delete', 'user', C_ZITADEL1_ID, 'company', '%', 2);
    expect_val('delete', 'user',C_ZITADEL2_ID, 'company_unit', '%');
    expect_val('delete', 'user',C_ZITADEL3_ID, 'service', '%');
    expect_val('delete', 'user', C_ZITADEL4_ID, 'company_group', '%', 2);
    expect_val('delete', 'user',C_ZITADEL5_ID, 'service', '%');
    expect_val('delete', 'user', C_ZITADEL6_ID, 'company', '%');
    expect_val('delete', 'user', C_ZITADEL6_ID, 'company_unit', '%');
    expect_val('delete', 'user', C_ZITADEL6_ID, 'service', '%');
    expect_val('delete', 'user', C_ZITADEL7_ID, 'company', '%');
    expect_val('delete', 'user', C_ZITADEL7_ID, 'company_unit', '%');
    expect_val('delete', 'user', C_ZITADEL7_ID, 'service', '%');

    select count(*) into n from MCDB_MONITOR.PLOG_OUTPUT where message like '%ch.open.syncify%';
    if n != C_TEST_CASES then
      raise_application_error(-20000, 'unit-test failed: expected: '|| C_TEST_CASES ||' messages, but got '|| n);
    end if;
  end assert_logs;
END E2ETEST;
/
