# Coding Conventions

**Analysis Date:** 2026-07-10

## Naming Patterns

**Files:**
- SQL files follow semantic names: `<prefix>_<package_name>.sql` for packages, `changelog-*.sql` for change logs
- Package specs: `<prefix>_<name>.sql` in `ddl/src/pkg/`
- Package bodies: `<prefix>_<name>.sql` in `ddl/src/pkgb/`
- Test packages: `<prefix>_<name>_test.sql` marked with `contextFilter:unit-tests`
- Migration output organized by pattern: `ddl/src/pkg/mss_osag_ip.sql` → `pg_migration/output/package_in_name/FUNCTION.pg.sql`

**Functions/Procedures:**
- Mixed case with descriptive names: `getbcast()`, `getnet()`, `ip2num()`, `num2ip()`, `runOsCmdGetResult()`
- Action-verb prefix pattern: `delete_*`, `grant_*`, `test_*`
- Deprecated procedures noted: e.g., "runOsCmd: Procedure is deprecated, use runOsCmdGetResult instead!" (`ddl/src/pkg/osag_osag_ext.sql`)

**Variables:**
- Prefix convention strictly enforced:
  - `p_` for IN/OUT parameters (e.g., `p_ip`, `p_mask`, `p_cmd`, `p_length`)
  - `v_` for local variables (e.g., `v_maskrange`, `v_byte_no`, `v_cmd_out`)
  - `c_` for constants within procedures (e.g., `c_prefix`)
  - `S_PREFIX` or all-caps for module-level string constants (e.g., `S_PREFIX CONSTANT VARCHAR2(32) := 'runOsCmd(): '`)
  - `C_` for package-level constants (e.g., `C_TEST_CASES CONSTANT NUMBER := 57`)

**Types:**
- Record types use descriptive naming: `test_case_record`, `test_case_table`
- Index BY PLS_INTEGER for array-like collections (e.g., `TYPE test_case_table IS TABLE OF test_case_record INDEX BY PLS_INTEGER`)

**Packages:**
- Schema-qualified names: `MSS.OSAG_IP`, `AUTH.OSAG_AUTH`, `FW.DELETE_AUTO_IP_GROUPS_TEST`, `ASERTO_TEST.E2ETEST`
- Public synonyms created for every package: `CREATE OR REPLACE PUBLIC SYNONYM osag_auth FOR auth.osag_auth` (`ddl/src/pkg/auth_osag_auth.sql`)
- Naming convention: `<SCHEMA>.<PREFIX>_<DOMAIN>_<FUNCTION>`

## Code Style

**Formatting:**
- No formal linter detected (no .eslintrc, .prettierrc, or eslint.config files found)
- Custom formatting guidelines evident from source:
  - 4-space indentation standard
  - Multi-line function definitions aligned with block keywords (IS, AS)
  - Comment blocks use double-dash `--` with aligned section separators
  - Long comment headers use dashes: `-------------------------------------------------------------------------------------------`

**Linting/Formatting:**
- No explicit linting configuration found
- SQL adheres to Oracle PL/SQL syntax standards
- Manual code review likely (CLAUDE.md indicates this is a conversion task)

## Import Organization

**Path Aliases:**
- Liquibase formatted SQL uses `logicalFilePath` attribute:
  ```sql
  --liquibase formatted sql logicalFilePath:pkg/mss_osag_ip.sql
  --changeset sys:1 runOnChange:true endDelimiter:/ splitStatements:true
  ```

**Schema References:**
- Explicit schema qualification for cross-schema access: `OSAG.OSAG_EXT`, `MSS.OSAG_IP`, `AUTH.OSAG_AUTH`
- Public synonyms provide unqualified access

**Package Dependencies:**
- Declared in package specs with comments noting state packages:
  ```sql
  -- NOTE:
  -- Please declare constants, exceptions, and global variables
  -- in the according state package (e.g. OSAG_AUTH_STATE for OSAG_AUTH)
  ```
  (`ddl/src/pkg/auth_osag_auth.sql`)

## Error Handling

**Patterns:**
- Unified logging via `plog` package (custom logging framework):
  - `plog.debug(message)` for debug logs (`ddl/src/pkgb/mss_osag_ip.sql`)
  - `plog.err(message)` for errors (`ddl/src/pkgb/osag_osag_ext.sql`)
  - `plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT)` for audit logging

- Oracle-specific exceptions:
  - `WHEN OTHERS THEN plog.err(...); RAISE;` pattern for re-raising (`ddl/src/pkgb/osag_osag_ext.sql`)
  - Named exceptions: `EXTERNAL_TIMEOUT EXCEPTION; PRAGMA EXCEPTION_INIT (EXTERNAL_TIMEOUT, -20103);`
  - Application-specific exceptions declared in state packages (e.g., `OSAG_AUTH_STATE`, `TT_EVENT_INTERFACE_STATE`)

- PostgreSQL equivalent (migration):
  - `plog` schema with procedures `Debug()`, `Info()`, `Notice()`, `Warning()`, `Err()`, `Crit()`, `Alert()`, `Emerg()` (`pg_migration/preparation/302_helper_procedures.sql`)
  - RAISE statement usage (PostgreSQL PLPGSQL)

## Logging

**Framework:** Custom `plog` package (Oracle-specific)

**Procedures exposed:**
- `plog.debug(message)` - debug level
- `plog.err(message)` - error level
- `plog.AuditUsage(unit_owner, unit_type, unit)` - audit trail
- Syslog-style levels in PostgreSQL migration: 0=Emerg, 1=Alert, 2=Crit, 3=Err, 4=Warning, 5=Notice, 6=Info, 7=Debug

**Patterns:**
- Log messages prefixed with procedure name: `c_prefix := 'OSAG_IP.ip2num(): '` then logged as `plog.debug(c_prefix||'not enough dots in ip address')` (`ddl/src/pkgb/mss_osag_ip.sql`)
- Output truncation for long values: truncate to 35 characters with ellipsis (`ddl/src/pkgb/osag_osag_ext.sql:102-103`)

## Comments

**When to Comment:**
- Mandatory header block per file with Liquibase metadata:
  ```sql
  --liquibase formatted sql logicalFilePath:pkg/mss_osag_ip.sql 
  --changeset sys:1 runOnChange:true endDelimiter:/ splitStatements:true
  ```

- Copyright/author attribution where applicable:
  ```sql
  -- written by ok@open.ch, January 2002;
  -- copyright 2002-2003 Open Systems AG, Switzerland
  ```

- Section headers with alignment dashes (minimum 80 dashes):
  ```sql
  -------------------------------------------------------------------------------------------
  -- FUNCTION getbcast
  -------------------------------------------------------------------------------------------
  ```

- Parameter documentation blocks for procedures/functions with input/output descriptions:
  ```sql
  -- input parameters:
  --   p_cmd:      command to execute
  --   p_length:   max. length of returned command output
  -- output parameters:
  --   p_cmd_out:  command output
  --   p_cmd_exit: exit code of executed command
  ```

**JSDoc/TSDoc:**
- Not applicable (PL/SQL uses block comments)
- Extensive block documentation standard for all functions
- Deprecation notices included inline: "Procedure is deprecated, use runOsCmdGetResult instead!"

## Function Design

**Size:** 
- Functions typically 30-150 lines
- Package bodies split by function (labeled sections with dashes)
- Longer procedures use FOR loops for clarity (e.g., IPv6 address parsing: `FOR v_byte_no IN 1..4 LOOP`)

**Parameters:**
- Strongly typed to table columns using `%TYPE` anchor: `p_login_id login.id%TYPE` (`ddl/src/pkg/auth_osag_auth.sql`)
- Deterministic functions marked explicitly: `FUNCTION num2ip(p_number NUMBER) RETURN VARCHAR2 DETERMINISTIC`
- IN/OUT/IN OUT keywords required

**Return Values:**
- Explicit RETURN statements with type
- NULL returns documented when applicable: "if p_string is null then return null; end if;"
- Success indicated by return type match (no void-like procedures in functional style)

## Module Design

**Exports:**
- Package specs (`ddl/src/pkg/`) declare public interface
- Package bodies (`ddl/src/pkgb/`) provide implementation
- Public synonyms expose packages without schema prefix

**Barrel Files:**
- Not used (database packages are monolithic)
- State packages pattern: separate package for constants/exceptions (e.g., `OSAG_AUTH` main logic, `OSAG_AUTH_STATE` for state)

**Compilation Directives:**
- Liquibase changesets control deployment:
  - `runOnChange:true` — re-execute if body changes
  - `splitStatements:true` — split on `/` delimiter
  - `contextFilter:unit-tests` — only apply in test context
  - `endDelimiter:/` — use `/` as statement terminator

---

*Convention analysis: 2026-07-10*
