--liquibase formatted sql logicalFilePath:pkg/aserto_test_e2etest.sql
--changeset sys:1 runOnChange:true endDelimiter:/ contextFilter:unit-tests
CREATE OR REPLACE PACKAGE ASERTO_TEST.E2ETEST IS
  C_TEST_CASES CONSTANT NUMBER := 57;
  C_GENERIC_ID CONSTANT NUMBER := 999;
  C_COMPANY_ID CONSTANT NUMBER := 9991;
  C_CUNIT_ID   CONSTANT NUMBER := 9992;
  C_CUNIT2_ID  CONSTANT NUMBER := 9993;
  C_SERVICE_ID CONSTANT NUMBER := 9994;
  C_SERVICE2_ID CONSTANT NUMBER := 9995;
  C_HOST_ID    CONSTANT NUMBER := 9996;
  C_HOST2_ID   CONSTANT NUMBER := 9997;
  C_LOGIN_1    CONSTANT NUMBER := 9991;
  C_LOGIN_2    CONSTANT NUMBER := 9992;
  C_LOGIN_3    CONSTANT NUMBER := 9993;
  C_LOGIN_4    CONSTANT NUMBER := 9994;
  C_LOGIN_5    CONSTANT NUMBER := 9995;
  C_LOGIN_6    CONSTANT NUMBER := 9996;
  C_ZITADEL1_ID CONSTANT VARCHAR2(32) := '1testasertoasertoaserto';
  C_ZITADEL2_ID CONSTANT VARCHAR2(32) := '2testasertoasertoaserto';
  C_ZITADEL3_ID CONSTANT VARCHAR2(32) := '3testasertoasertoaserto';
  C_ZITADEL4_ID CONSTANT VARCHAR2(32) := '4testasertoasertoaserto';
  C_ZITADEL5_ID CONSTANT VARCHAR2(32) := '5testasertoasertoaserto';
  C_ZITADEL6_ID CONSTANT VARCHAR2(32) := '6testasertoasertoaserto';
  C_LOGIN_7    CONSTANT NUMBER := 9990;
  C_ZITADEL7_ID CONSTANT VARCHAR2(32) := '7testasertoasertoaserto';


  -- creates company, unit, service, host
  procedure test_create;

  -- deletes company, unit, service, host
  procedure test_delete;

  -- checks the result of test_create and test_delete.
  -- give it a few seconds to write the logs before calling this.
  procedure assert_logs;

END E2ETEST;
/
