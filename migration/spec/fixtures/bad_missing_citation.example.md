---
oracle_schema: ZZ
oracle_package: FIXTURE_PKG
pg_schema: zz
pg_prefix: fixture_pkg
clause_prefix: FIXTURE
oracle_spec: ddl/src/pkg/mss_osag_dbprop.sql
oracle_body: ddl/src/pkgb/mss_osag_dbprop.sql
public_routines: 1
---

# ZZ.FIXTURE_PKG — PostgreSQL spec (BAD: citation past end-of-file)

Throwaway fixture used only to prove spec_lint.py rejects a clause whose `source:`
citation points at a line number beyond the cited file's actual length -- this is how a
hallucinated/fabricated citation gets caught (T-02-05). `ddl/src/pkg/mss_osag_dbprop.sql`
is 32 lines long; the clause below cites line 9999.

## Routines

### do_thing

- **Oracle signature:** `DO_THING(NUMBER) RETURN VARCHAR2`
- **PostgreSQL name:** `zz.fixture_pkg_do_thing`
- **Declared:** `ddl/src/pkg/mss_osag_dbprop.sql:23`
- **Defined:** `ddl/src/pkgb/mss_osag_dbprop.sql:11`
- Returns a fixed string for testing purposes only.

## Clauses

### S-FIXTURE-001

- **routines:** do_thing
- **claim:** Returns a non-null string for any input, per the fixture's own contract.
- **source:** `ddl/src/pkg/mss_osag_dbprop.sql:9999`

## Checklist

### 1. Empty-string / NULL handling

N/A -- no VARCHAR2/CLOB values, verified by inspecting the single routine signature above.

### 2. SELECT INTO strictness

N/A -- this fixture package has no SELECT INTO sites.

### 3. Exception codes

N/A -- this fixture raises no exceptions.

### 4. Package state

N/A -- this fixture declares no package-body-level state.

### 5. FUNCTION vs PROCEDURE

N/A -- `do_thing` is declared FUNCTION and contains no COMMIT/ROLLBACK.

## Assumptions / Unresolved

Nothing is unresolved. This is a synthetic fixture with no real Oracle body; the only
purpose of this file is to trigger spec_lint.py's citation-line-exists check.
