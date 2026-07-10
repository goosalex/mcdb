--liquibase formatted sql logicalFilePath:pkgb/mss_osag_ip_test.sql
--changeset sys:1 runOnChange:true endDelimiter:/ contextFilter:unit-tests
CREATE OR REPLACE PACKAGE BODY MSS.OSAG_IP_TEST IS
  PROCEDURE test_num2ipv6 IS
    TYPE test_case_record IS RECORD (
      in_left  NUMBER,
      in_right NUMBER,
      expected VARCHAR2(64)
    );
    TYPE test_case_table IS TABLE OF test_case_record INDEX BY PLS_INTEGER;
    test_cases test_case_table;
    expected varchar2(64);
    actual varchar2(64);
  
  BEGIN
    -- define test cases
    test_cases(1).in_left := 0;
    test_cases(1).in_right := 0;
    test_cases(1).expected := '::';

    test_cases(2).in_left := 0;
    test_cases(2).in_right := 1;
    test_cases(2).expected := '::1';

    test_cases(3).in_left := 281474976710656;
    test_cases(3).in_right := 0;
    test_cases(3).expected := '1::';

    test_cases(4).in_left := 1152921504606846976;
    test_cases(4).in_right := 0;
    test_cases(4).expected := '1000::';

    test_cases(5).in_left := 17293822569102704640;
    test_cases(5).in_right := 0;
    test_cases(5).expected := 'f000::';

    test_cases(6).in_left := 0;
    test_cases(6).in_right := 15;
    test_cases(6).expected := '::f';

    test_cases(7).in_left := 281479576813568;
    test_cases(7).in_right := 1249835548673;
    test_cases(7).expected := '1:1:1230::123:1:1';

    test_cases(8).in_left := 281479539064832;
    test_cases(8).in_right := 17523466633217;
    test_cases(8).expected := '1:1:ff0::ff0:1:1';
    
    -- run test cases
    FOR i IN 1 .. test_cases.COUNT LOOP
      expected := test_cases(i).expected;
      actual := MSS.OSAG_IP.num2ipv6(test_cases(i).in_left, test_cases(i).in_right);
      
      if actual != expected then
        raise_application_error(
          -20000,
          'unit-test test_num2ipv6: test case nr. ' || i || ' failed: expected ' || expected || ', got ' || actual
        );
      end if;
    end loop;
  END test_num2ipv6;

  PROCEDURE test_ipv62nums IS
    TYPE test_case_record IS RECORD (
      input  VARCHAR2(64),
      expected_left NUMBER,
      expected_right NUMBER
    );
    TYPE test_case_table IS TABLE OF test_case_record INDEX BY PLS_INTEGER;
    test_cases test_case_table;
    expected_left number;
    expected_right number;
    actual_left number;
    actual_right number;
  
  BEGIN
    -- define test cases
    test_cases(1).input := '::';
    test_cases(1).expected_left := 0;
    test_cases(1).expected_right := 0;

    test_cases(2).input := '::1';
    test_cases(2).expected_left := 0;
    test_cases(2).expected_right := 1;

    test_cases(3).input := '1::';
    test_cases(3).expected_left := 281474976710656;
    test_cases(3).expected_right := 0;

    test_cases(4).input := '0:0:0:0:0:0:0001';
    test_cases(4).expected_left := 0;
    test_cases(4).expected_right := 1;

    test_cases(5).input := '::1:2:3:4:5:6:7';
    test_cases(5).expected_left := 4295098371;
    test_cases(5).expected_right := 1125921382072327;

    test_cases(6).input := '1:2:3:4:5:6:7::';
    test_cases(6).expected_left := 281483566841860;
    test_cases(6).expected_right := 1407400653815808;

    test_cases(7).input := '1:2::6:7';
    test_cases(7).expected_left := 281483566645248;
    test_cases(7).expected_right := 393223;

    test_cases(8).input := '1:0::7';
    test_cases(8).expected_left := 281474976710656;
    test_cases(8).expected_right := 7;

    test_cases(9).input := '1::0:7';
    test_cases(9).expected_left := 281474976710656;
    test_cases(9).expected_right := 7;
    
    -- run test cases
    FOR i IN 1 .. test_cases.COUNT LOOP
      expected_left := test_cases(i).expected_left;
      expected_right := test_cases(i).expected_right;
      actual_left := MSS.OSAG_IP.ipv6left(test_cases(i).input);
      actual_right := MSS.OSAG_IP.ipv6right(test_cases(i).input);
      
      if actual_left != expected_left or actual_right != expected_right then
        raise_application_error(
          -20000,
          'unit-test test_ipv62nums: test case nr. ' || i || ' failed: expected ' ||
          expected_left || ' ' || expected_right || ', got ' || actual_left || ' ' || actual_right
        );
      end if;
    end loop;
  END test_ipv62nums;
END OSAG_IP_TEST;
/
