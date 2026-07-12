# migration/test/schema-fixes/

Additive fixes for ora2pg output errors this plan's pilot surfaced, applied AFTER the
base load (`bootstrap/20_ddl.sh`) completes. **`ddl/migrated/` itself is never edited**
(D-P7) — every fix here is a separate file layered on top, so the ora2pg export stays
the untouched artifact of record and Phase 5 can diff against it cleanly.

## Files

- `10_ora2pg_fixes.sql` — the actual fix SQL (15 FK column-type widenings + their 15
  FK constraints, 3 reconstructed CHECK constraints, and the 3 view drop/recreates
  those FK fixes require). Loaded with `-v ON_ERROR_STOP=on` and MUST complete with
  zero errors — every failure here is either fixed, or it isn't in this file.

## Where the OTHER two fixes live

Two more ora2pg gaps this plan found are fixed in `../bootstrap/10_schemas_roles.sql`
instead of here, because they must exist **before** `tables.pg.sql` loads (a table
statement referencing a schema that doesn't exist yet cannot be "fixed after the fact"
in the same sense a constraint can — the CREATE TABLE itself never ran):

- **Fix #1**: the `postgresadmin` role every `ddl/migrated/users/*.sql` file assumes
  exists.
- **Fix #2**: the `checklist` schema, whose `ddl/migrated/users/CHECKLIST.sql` role file
  is simply missing from the export (every OTHER schema referenced in `tables.pg.sql`
  has a matching `users/` file; checklist is the one exception).

## The full ledger

See `../SCHEMA-FIXES.md` for the complete table: every fix (all four), every error it
resolves, its root cause in ora2pg's conversion behaviour, and the action Phase 5 should
take (re-apply this file verbatim, or fix the ora2pg configuration and regenerate).
`SCHEMA-FIXES.md` also records every failure left deliberately UNFIXED (the 4
`views.pg.sql` errors) and why each was out of the pilot's reach.

## Why line-number reconciliation, not silent tolerance

`bootstrap/20_ddl.sh` does not just "continue past errors and hope for the best" when
loading the constraint/view files that are known to fail at this stage. It captures the
exact source line number of every failing statement and diffs that set against a
hardcoded expected list. A match is an explicitly reconciled, ledgered, and printed
discrepancy — not a silently swallowed one. Any failure OUTSIDE the expected set (a
regression, or ora2pg output that changed underneath this plan's fixed expectations)
aborts the whole build non-zero. This is what "errors surfaced, not swallowed" means in
practice for files that the plan's own design (D-P7: fixes are additive, applied after
the base load) requires to partially fail before this directory's fixes run.
