# MSS.OSAG_DBPROP -- FINDINGS

**Source:** `ddl/src/pkg/mss_osag_dbprop.sql` (spec, 32 lines), `ddl/src/pkgb/mss_osag_dbprop.sql`
(body, 90 lines). **Spec:** `migration/spec/mss.osag_dbprop.md`. **Target:**
`migration/pgsql/mss/osag_dbprop.sql`.

## AuditUsage deletion count

**3 of 3** `plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT)` call
sites deleted outright (one per routine: `get_number_by_host` line 17,
`get_string_by_host_key_id` line 37, `get_string_by_host` line 73 of the Oracle body).
Confirmed by `grep -c AuditUsage ddl/src/pkgb/mss_osag_dbprop.sql` -> 3. Per XCUT-06 /
`.planning/research/PITFALLS.md` Pitfall 4.3, the feature is unused (write-only;
nothing reads `osag.plsql_audit`) and is deleted, not stubbed or ported.

## Formatting-parity decision: the "line 1 at RAISE" golden CONTEXT line

`migration/test/regress/expected/mss__osag_dbprop__errors.out` (authored in plan 02-04,
locked, not touchable by this plan) pins:

```
CONTEXT:  PL/pgSQL function mss.osag_dbprop_get_string_by_host(integer,character varying) line 1 at RAISE
```

This is a real constraint on the FUNCTION's parameter types (`integer`, not
`bigint`/`numeric`; `character varying`/`varchar`, not `text`) and on the physical
source-line position of the `RAISE EXCEPTION` statement inside the dollar-quoted
function body. PL/pgSQL's CONTEXT line counter counts physical newlines from the start
of the body text (the line containing the opening `$fn$` delimiter counts as line 1);
verified empirically against a live local PostgreSQL 17.10 instance (a `CALL`/`RAISE`
on the exact same physical line as the opening delimiter reports "line 1"; one newline
before it reports "line 2"). To reproduce "line 1" without touching the pinned golden
file, `get_string_by_host`'s `DECLARE`/`BEGIN`/`SELECT INTO STRICT`/`EXCEPTION WHEN
NO_DATA_FOUND`/`CALL osag.osag_plog_err(...)`/`RAISE EXCEPTION` sequence for the
"unknown db property" arm is written on one long physical source line, immediately
after `AS $fn$`. The `WHEN OTHERS` arm (untested by the golden file, since it is never
reached by these fixtures) keeps normal multi-line formatting. This is a **cosmetic**
decision forced by a locked test artifact, not a behavioral one -- flagged here loudly
so a future maintainer does not "clean up" this one line and silently break the
red-before/green-after gate.

## Oracle's `''`/`NULL` collapsing (S-DBPROP-009)

`get_string_by_host` is the package's only `VARCHAR2` parameter that takes part in an
equality comparison. `NULLIF(i_property_name, '')` reproduces Oracle's implicit
`''`-collapses-to-`NULL` behavior explicitly at the boundary (Pitfall 2), so both `''`
and `NULL` inputs produce the identical "unknown db property" outcome, matching the
pgTAP suite's S-DBPROP-009 assertions and the golden regress file's line 13/15 (both
render as `unknown db property ''`, via `coalesce(i_property_name, '')` in the raised
message text -- this is necessary because PL/pgSQL's `RAISE ... %, expr` substitutes a
literal NULL argument as the string `<NULL>`, not an empty string, unlike Oracle's `||`
concatenation which silently drops NULL operands).

## Two distinct exception paths (S-DBPROP-006/007), provisional pending XCUT-01

- Unknown property name (`-20801` in Oracle, `OSAG_DBPROP_STATE.S_ERRNO_UNKNOWN_DBPROP`):
  translated as a plain `RAISE EXCEPTION` with no explicit `ERRCODE` (defaults to
  `P0001`, PL/pgSQL's generic `raise_exception`). Message text is pinned by the golden
  regress file; the SQLSTATE itself is NOT yet pinned by any test in this plan and is
  left at the PL/pgSQL default, explicitly flagged for Phase 3's XCUT-01 to assign a
  real, documented custom SQLSTATE (in the same spirit as `-20801`) if client code needs
  to distinguish it from other errors.
- `OSAG_DBPROP_STATE.e_abort` (no `PRAGMA EXCEPTION_INIT`, no fixed Oracle code):
  translated as a bare `RAISE;` re-raise inside the `WHEN OTHERS` arm, after logging via
  `osag.osag_plog_err`. This deliberately stays a DIFFERENT PostgreSQL error path from
  the one above (no shared ERRCODE), matching the spec's requirement that the two must
  not collapse into the same translated error.

## SELECT INTO strictness (both sites STRICT, matching the spec exactly)

- `get_number_by_host`'s `SELECT ... FROM DUAL`-equivalent (no `FROM` needed in
  PostgreSQL -- a bare `SELECT expr INTO STRICT var;` always returns exactly one row):
  `STRICT`, no handler -- structurally can never trip.
- `get_string_by_host`'s `mss.key` lookup: `STRICT` with a `NO_DATA_FOUND` handler
  (unique index `u_key_name` makes `TOO_MANY_ROWS` structurally impossible, matching the
  spec -- no handler needed for that arm).

## Sequences / package state

None in this package (no sequences used; `package_state: []` per the spec, confirmed by
reading the full 90-line body -- no non-`CONSTANT` package-body-level declarations).

## Verification performed

- Loaded cleanly into a `bootstrap.sh --template mcdb_tmpl` clone with `osag_plog.sql`
  already installed.
- `run-tests.sh --package mss.osag_dbprop` -- both pgTAP (`mss__osag_dbprop__spec.sql`,
  10 assertions) and expected-output (`mss__osag_dbprop__errors.sql` vs. its golden
  `.out`) halves reported GREEN.
- `grep -nEi "dbms_|utl_|auditusage"` over this file: zero matches.
