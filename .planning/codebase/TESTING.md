# Testing Patterns

**Analysis Date:** 2026-07-10

## Test Framework

**Runner:**
- Native Oracle PL/SQL unit test framework (no external test framework)
- Test packages embedded in source files as `.sql` files
- Liquibase context filter: `contextFilter:unit-tests` — tests executed only when unit-tests context is active
- No JUnit or pytest integration at SQL level (Java integration tests exist in `tests/src/main/` and `tests/src/test/`)

**Configuration:**
- Liquibase manages test execution via changesets with context filters
- Test database properties: `tests/src/test/resources/testcontainers.properties` and `tests/src/main/resources/testcontainers.properties`
- Container-based CI verification: `tests/ci-verify-orm.sh` for ORM layer validation

**Assertion Library:**
- Manual assertion via `raise_application_error()` with error code -20000
- Pattern: `raise_application_error(-20000, 'unit-test <test_name>: <message>')`

**Run Commands:**
```bash
# Test package execution (Oracle SQL*Plus or equivalent):
BEGIN
  MSS.OSAG_IP_TEST.test_num2ipv6();
  MSS.OSAG_IP_TEST.test_ipv62nums();
END;
/

# CI verification (ORM layer):
./tests/ci-verify-orm.sh

# Database schema check:
./tests/update_dx_orm.sh
```

## Test File Organization

**Location:**
- Test packages co-located with production packages
- Test specs: `ddl/src/pkg/<prefix>_<name>_test.sql`
- Test bodies: `ddl/src/pkgb/<prefix>_<name>_test.sql`
- Java integration tests: `tests/src/test/java/`

**Naming:**
- Package spec: `<SCHEMA>.<PREFIX>_<NAME>_TEST IS ... END <PREFIX>_<NAME>_TEST;`
- Examples: `MSS.OSAG_IP_TEST`, `FW.DELETE_AUTO_IP_GROUPS_TEST`, `ASERTO_TEST.E2ETEST`
- Test procedures: `test_*` or `assert_*` naming convention

**Structure:**
```
ddl/src/pkg/
├── mss_osag_ip.sql              # Production package spec
├── mss_osag_ip_test.sql         # Test package spec (contextFilter:unit-tests)
├── fw_delete_auto_ip_groups_test.sql
└── aserto_test_e2etest.sql

ddl/src/pkgb/
├── mss_osag_ip.sql              # Production package body
├── mss_osag_ip_test.sql         # Test package body (contextFilter:unit-tests)
├── fw_delete_auto_ip_groups_test.sql
└── aserto_test_e2etest.sql
```

## Test Structure

**Suite Organization:**
```plsql
CREATE OR REPLACE PACKAGE MSS.OSAG_IP_TEST IS
  PROCEDURE test_num2ipv6;
  PROCEDURE test_ipv62nums;
END OSAG_IP_TEST;
/

CREATE OR REPLACE PACKAGE BODY MSS.OSAG_IP_TEST IS
  PROCEDURE test_num2ipv6 IS
    TYPE test_case_record IS RECORD (
      in_left  NUMBER,
      in_right NUMBER,
      expected VARCHAR2(64)
    );
    TYPE test_case_table IS TABLE OF test_case_record INDEX BY PLS_INTEGER;
    test_cases test_case_table;
  BEGIN
    -- define test cases
    test_cases(1).in_left := 0;
    test_cases(1).in_right := 0;
    test_cases(1).expected := '::';
    
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
END OSAG_IP_TEST;
/
```

**Patterns:**
- **Setup pattern:** Inline test data definition using PL/SQL records and collections
  ```plsql
  TYPE test_case_record IS RECORD (in_left NUMBER, in_right NUMBER, expected VARCHAR2(64));
  TYPE test_case_table IS TABLE OF test_case_record INDEX BY PLS_INTEGER;
  test_cases test_case_table;
  ```

- **Teardown pattern:** Explicit cleanup via `PROCEDURE cleanup_test_rows()` — deletes test data ranges
  ```plsql
  PROCEDURE cleanup_test_rows IS
  BEGIN
    DELETE FROM FW.IP_GROUP_MEMBER WHERE ID BETWEEN 999710 AND 999799;
    DELETE FROM FW.IP_GROUP WHERE ID BETWEEN 999710 AND 999799;
    COMMIT;
  END cleanup_test_rows;
  ```
  (`ddl/src/pkgb/fw_delete_auto_ip_groups_test.sql`)

- **Assertion pattern:** Manual comparison + `raise_application_error(-20000, message)`
  ```plsql
  PROCEDURE assert_equals(p_expected NUMBER, p_actual NUMBER, p_message VARCHAR2) IS
  BEGIN
    IF p_expected != p_actual THEN
      raise_application_error(-20000, 'unit-test ' || p_message || ': expected=' || p_expected || ', actual=' || p_actual);
    END IF;
  END assert_equals;
  ```

## Mocking

**Framework:** 
- No explicit mocking framework used in SQL tests
- Tests use real database tables and direct SQL manipulation

**Patterns:**
- Direct INSERT into test tables (`DELETE FROM FW.IP_GROUP WHERE ID BETWEEN 999710 AND 999799;`)
- No transaction isolation or savepoint management (commits after cleanup)
- Foreign key constraint testing: procedures designed to expect constraint violations (`test_member_ip_group_fk_violation` raises ORA-02292)

**What to Mock:**
- External dependencies (file systems, OS commands) wrapped in external procedures
- Example: `OSAG.OSAG_EXT.runOsCmdExt()` is EXTERNAL and can be stubbed
- IO operations handled via dedicated procedures in separate packages

**What NOT to Mock:**
- Database tables — use live tables with ID ranges allocated for tests (999xxx series)
- Trigger logic — test database state after DML
- Package state — test packages are stateless procedural units

## Fixtures and Factories

**Test Data:**
- Inline PL/SQL record definitions (no factory classes):
  ```plsql
  test_cases(1).in_left := 281474976710656;
  test_cases(1).in_right := 0;
  test_cases(1).expected := '1::';
  ```
  (`ddl/src/pkgb/mss_osag_ip_test.sql`)

- Hardcoded test constants:
  ```plsql
  C_TEST_CASES CONSTANT NUMBER := 57;
  C_GENERIC_ID CONSTANT NUMBER := 999;
  C_COMPANY_ID CONSTANT NUMBER := 9991;
  C_CUNIT_ID   CONSTANT NUMBER := 9992;
  ```
  (`ddl/src/pkg/aserto_test_e2etest.sql`)

**Location:**
- Test data defined inline within test procedures
- Reusable constants declared in test package spec
- Master data snapshots stored in `masterdata/` directory (CSV format from production)

## Coverage

**Requirements:** 
- No explicit coverage measurement detected
- Code review process (implied by Liquibase tagging and changeset tracking)
- ORM layer validation: `tests/ci-verify-orm.sh` checks if database changes require ORM updates

**View Coverage:**
- No coverage tool configured for SQL
- Schema drift detection via CI: `git diff` on `changes/changelog*.sql` files
- Integration testing via Testcontainers (Java test framework in `tests/src/`)

## Test Types

**Unit Tests:**
- Scope: Single function/procedure in isolation
- Approach: Input test vectors → direct function call → assertion on return value
- Examples:
  - `test_num2ipv6()` tests IPv6 address number conversion
  - `test_ipv62nums()` tests IPv6 address parsing
  - Test ranges provided: 8-10 test cases per function
- Table-free functions preferred (deterministic functions marked `DETERMINISTIC`)

**Integration Tests:**
- Scope: Multi-table DML operations and constraint enforcement
- Approach: INSERT test rows → call procedure → SELECT to verify state → cleanup
- Examples:
  - `test_delete_group_and_member()` verifies cascading deletes (`ddl/src/pkgb/fw_delete_auto_ip_groups_test.sql`)
  - `test_member_ip_group_fk_violation()` verifies foreign key enforcement
  - `assert_logs()` in E2E tests validates audit trail after operations (`ddl/src/pkg/aserto_test_e2etest.sql`)

**E2E Tests:**
- Scope: Full workflow across multiple schemas (e.g., ASERTO auth system)
- Approach: `test_create()` → `test_delete()` → `assert_logs()` validation
- Example: `ASERTO_TEST.E2ETEST` package with 57 test cases (`ddl/src/pkg/aserto_test_e2etest.sql`)
- Relies on logging system for cross-component validation

## Common Patterns

**Async Testing:**
- Not applicable (PL/SQL is synchronous)
- Audit trail validation uses time-based polling: "give it a few seconds to write the logs before calling this" (`ddl/src/pkg/aserto_test_e2etest.sql`)

**Error Testing:**
```plsql
-- Testing expected exceptions
PROCEDURE test_member_ip_group_fk_violation IS
  l_violation_raised BOOLEAN := FALSE;
BEGIN
  cleanup_test_rows;
  
  -- Create referential constraint violation
  INSERT INTO FW.IP_GROUP (ID, VERSION, NAME, AUTOMATIC) VALUES (999740, 0, 'target_group', 1);
  INSERT INTO FW.IP_GROUP (ID, VERSION, NAME, AUTOMATIC) VALUES (999741, 0, 'holder_group', 1);
  INSERT INTO FW.IP_GROUP_MEMBER (ID, IP_GROUP_ID, ..., MEMBER_IP_GROUP_ID)
    VALUES (999744, 999741, ..., 999740);

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
    raise_application_error(-20000, 'unit-test test_member_ip_group_fk_violation: expected FK violation ORA-02292');
  END IF;
END test_member_ip_group_fk_violation;
```
(`ddl/src/pkgb/fw_delete_auto_ip_groups_test.sql`)

**Parametric Testing:**
- Test vectors defined as PL/SQL table types with FOR loop iteration:
  ```plsql
  FOR i IN 1 .. test_cases.COUNT LOOP
    expected := test_cases(i).expected;
    actual := MSS.OSAG_IP.num2ipv6(test_cases(i).in_left, test_cases(i).in_right);
    if actual != expected then
      raise_application_error(-20000, 'test case nr. ' || i || ' failed: ...');
    end if;
  end loop;
  ```

---

*Testing analysis: 2026-07-10*
