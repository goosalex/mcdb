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

# ZZ.FIXTURE_PKG — PostgreSQL spec

Throwaway fixture package used only to prove spec_lint.py accepts a well-formed spec. Not
a real Oracle package -- `ZZ.FIXTURE_PKG` does not exist in `ddl/src/`; the citations below
point at a real file (`mss_osag_dbprop.sql`) purely so the citation-line-exists check has
something real to validate against. `spec_lint.py` skips the name-map.csv / inventory.json
SSOT cross-checks for any path under `fixtures/`, which is exactly what lets this fixture
exist without adding fake rows to either SSOT file.

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
- **source:** `ddl/src/pkg/mss_osag_dbprop.sql:23`

## Checklist

### 1. Empty-string / NULL handling

N/A -- `do_thing` takes a single NUMBER parameter; no VARCHAR2/CLOB values participate in
any NULL/''-sensitive comparison, verified by inspecting the single routine signature above.

### 2. SELECT INTO strictness

N/A -- this fixture package has no SELECT INTO sites; it exists only to test spec_lint.py's
structural checks, not to model real Oracle SELECT behaviour.

### 3. Exception codes

N/A -- this fixture raises no exceptions.

### 4. Package state

N/A -- this fixture declares no package-body-level state; it is a linter test fixture, not
a real package body.

### 5. FUNCTION vs PROCEDURE

N/A -- `do_thing` is declared FUNCTION and contains no COMMIT/ROLLBACK; this is a linter
test fixture with no real body to check.

## Assumptions / Unresolved

Nothing is unresolved. This is a synthetic fixture with no real Oracle body; every field
above is fabricated for the sole purpose of exercising spec_lint.py's structural checks
against a well-formed input.
