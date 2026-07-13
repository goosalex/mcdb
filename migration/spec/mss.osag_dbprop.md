---
oracle_schema: MSS
oracle_package: OSAG_DBPROP
pg_schema: mss
pg_prefix: osag_dbprop
clause_prefix: DBPROP
oracle_spec: ddl/src/pkg/mss_osag_dbprop.sql
oracle_body: ddl/src/pkgb/mss_osag_dbprop.sql
public_routines: 3
---

# MSS.OSAG_DBPROP — PostgreSQL spec

Retrieval-only accessors for "DB properties" — host- or key-scoped configuration values
stored in `mss.key`/`mss.value` (via the `mss.V_HOST_KEY_VALUE` view). Per the package's
own header comment (`ddl/src/pkg/mss_osag_dbprop.sql:4-11`), only retrieval is implemented
today; set/delete are explicitly future work, not present in this package at all.

## Routines

### get_number_by_host

- **Oracle signature:** `FUNCTION get_number_by_host(i_host_id NUMBER, i_property_name VARCHAR2) RETURN NUMBER`
- **PostgreSQL name:** `mss.osag_dbprop_get_number_by_host` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/mss_osag_dbprop.sql:23`
- **Defined:** `ddl/src/pkgb/mss_osag_dbprop.sql:11-24`
- Delegates to `get_string_by_host` and collapses its result to `1` (string value `'1'`)
  or `0` (anything else, including `NULL`). Despite the `NUMBER` return type this is a
  boolean-shaped accessor — the body's own header comment flags this as an odd,
  possibly-misnamed implementation (`ddl/src/pkgb/mss_osag_dbprop.sql:6-8`).

### get_string_by_host

- **Oracle signature:** `FUNCTION get_string_by_host(i_host_id NUMBER, i_property_name VARCHAR2) RETURN VARCHAR2`
- **PostgreSQL name:** `mss.osag_dbprop_get_string_by_host` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/mss_osag_dbprop.sql:24`
- **Defined:** `ddl/src/pkgb/mss_osag_dbprop.sql:67-87`
- Resolves `i_property_name` to a `mss.key.id` and delegates to
  `get_string_by_host_key_id`. Raises an application error if the property name is
  unknown (no matching `mss.key` row); logs and re-raises on any other error.

### get_string_by_host_key_id

- **Oracle signature:** `FUNCTION get_string_by_host_key_id(i_host_id NUMBER, i_property_key_id NUMBER) RETURN VARCHAR2`
- **PostgreSQL name:** `mss.osag_dbprop_get_string_by_host_key_id` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/mss_osag_dbprop.sql:25`
- **Defined:** `ddl/src/pkgb/mss_osag_dbprop.sql:31-58`
- Iterates every `mss.V_HOST_KEY_VALUE`/`mss.KEY` row matching the given host and key id,
  returns `NULL` if none match, the common value if all matches agree, and logs
  (but does not raise) when matches disagree.

## Clauses

### S-DBPROP-001

- **routines:** get_number_by_host
- **claim:** `get_number_by_host` obtains its underlying value via
  `SELECT get_string_by_host(i_host_id, i_property_name) INTO l_string FROM DUAL` — a
  `SELECT ... INTO` against `DUAL`, which always returns exactly one row. This site can
  never raise `NO_DATA_FOUND`/`TOO_MANY_ROWS` by construction; only the wrapped
  `get_string_by_host` call itself can raise, and that exception (if any) propagates
  unchanged since `get_number_by_host` has no exception handler at all.
- **source:** `ddl/src/pkgb/mss_osag_dbprop.sql:18`

### S-DBPROP-002

- **routines:** get_number_by_host
- **claim:** `get_number_by_host` returns `1` when the underlying string equals the
  literal `'1'`, and `0` for every other case — including `NULL` and any other non-`'1'`
  string. This is the AS-WRITTEN behaviour; the body's own comment calls it "odd" and
  suggests it should have been named `get_boolean_by_host` and returned `BOOLEAN`, but
  the spec preserves the AS-WRITTEN contract, not the suggested one.
- **source:** `ddl/src/pkgb/mss_osag_dbprop.sql:19-23`

### S-DBPROP-003

- **routines:** get_string_by_host_key_id
- **claim:** `get_string_by_host_key_id` uses a cursor `FOR` loop (not a `SELECT ... INTO`)
  over the `mss.V_HOST_KEY_VALUE`/`mss.KEY` join. Zero matching rows is not an error
  condition for a cursor `FOR` loop — the loop body simply never executes and `l_string`
  stays at its initialized `NULL`, which is returned. No exception of any kind is raised
  for the "no such host/key combination" case.
- **source:** `ddl/src/pkgb/mss_osag_dbprop.sql:39-58`

### S-DBPROP-004

- **routines:** get_string_by_host_key_id
- **claim:** When more than one matching row is found and every row's `string_value`
  agrees, `get_string_by_host_key_id` logs a `plog.warning` ("has multiple but consistent
  values") and still returns that common value — this is not an error path, merely a
  logged observation.
- **source:** `ddl/src/pkgb/mss_osag_dbprop.sql:46-50`

### S-DBPROP-005

- **routines:** get_string_by_host_key_id
- **claim:** When matching rows disagree on `string_value`, `get_string_by_host_key_id`
  logs a `plog.err` ("has multiple inconsistently values") but does NOT raise an
  exception and does NOT stop iterating — it returns whichever value it had already
  settled on (the first value seen), silently ignoring the later, conflicting rows
  processed after the first disagreement is logged.
- **source:** `ddl/src/pkgb/mss_osag_dbprop.sql:51-55, 57`

### S-DBPROP-006

- **routines:** get_string_by_host
- **claim:** `get_string_by_host` resolves `i_property_name` via
  `SELECT id INTO v_key_id FROM mss.key WHERE name = i_property_name`. `mss.key.name`
  carries a unique index (`u_key_name`, `ddl/migrated/tables/tables.pg.sql:1993`), so
  `TOO_MANY_ROWS` is structurally impossible at this site (no handler for it exists or is
  needed). Zero rows (unknown property name) IS handled explicitly: `plog.err` is logged
  and `RAISE_APPLICATION_ERROR(OSAG_DBPROP_STATE.S_ERRNO_UNKNOWN_DBPROP, ...)` is raised
  — code `-20801` (declared `ddl/src/pkg/mss_osag_dbprop_state.sql:7-8`).
- **source:** `ddl/src/pkgb/mss_osag_dbprop.sql:75-79`

### S-DBPROP-007

- **routines:** get_string_by_host
- **claim:** `get_string_by_host`'s inline block also has a `WHEN OTHERS` handler that
  logs `plog.err` (including `sqlerrm`) and then `RAISE`s the named package exception
  `OSAG_DBPROP_STATE.e_abort` — a DIFFERENT exception from the `-20801` above.
  `e_abort` (declared `ddl/src/pkg/mss_osag_dbprop_state.sql:5`) has **no**
  `PRAGMA EXCEPTION_INIT`, unlike `unknown_dbprop`/`-20801`, so it carries no fixed Oracle
  error code of its own — these two exception paths must not be collapsed into the same
  PostgreSQL error in translation.
- **source:** `ddl/src/pkgb/mss_osag_dbprop.sql:80-82`

### S-DBPROP-008

- **routines:** get_string_by_host
- **claim:** After resolving `v_key_id`, `get_string_by_host` returns
  `get_string_by_host_key_id(i_host_id, v_key_id)` directly — i.e. it inherits every
  behaviour of S-DBPROP-003/004/005 (no-match → `NULL`, consistent-duplicate → logged
  warning, inconsistent-duplicate → logged error, first value wins).
- **source:** `ddl/src/pkgb/mss_osag_dbprop.sql:85`

### S-DBPROP-009

- **routines:** get_string_by_host
- **claim:** `i_property_name` participates in an equality comparison
  (`WHERE name = i_property_name`, S-DBPROP-006) but never in an `IS NULL`/`IS NOT NULL`
  check or a `||` concatenation anywhere in this package. Under Oracle, a caller passing
  `''` and a caller passing `NULL` are indistinguishable at this comparison (Oracle
  collapses `''` to `NULL`), so both produce zero rows and therefore the SAME
  `-20801 unknown db property` exception (S-DBPROP-006), assuming (as the current
  masterdata confirms) no `mss.key` row is ever literally named `''`. Under PostgreSQL,
  `''` is a distinct value from `NULL` — `name = ''` would only match a key literally
  named `''`. The translation must therefore either (a) rely on the fact that no such key
  exists (fragile, undocumented invariant) or (b) explicitly normalize `''` to `NULL` (or
  add an explicit `i_property_name IS NULL OR i_property_name = ''` guard) before the
  lookup so the two inputs are provably indistinguishable in PostgreSQL too, exactly as
  they are in Oracle.
- **source:** `ddl/src/pkgb/mss_osag_dbprop.sql:75`

## Checklist

### 1. Empty-string / NULL handling

`i_property_name` (`get_string_by_host`) is the only `VARCHAR2` parameter in the package
and is the only identifier that takes part in a comparison against caller-supplied data
(`WHERE name = i_property_name`, line 75). See S-DBPROP-009: Oracle's `''`/`NULL`
collapsing makes the two inputs behaviourally identical (both raise the "unknown db
property" exception, assuming — as verified against the current `mss.key` masterdata —
no key is ever named `''`); PostgreSQL does not collapse them, so the translation must add
an explicit boundary normalization (`NULLIF(i_property_name, '')` or an equivalent guard)
to preserve the Oracle contract rather than relying on the absence of a `''`-named key as
an implicit invariant. `i_host_id` is `NUMBER`-typed throughout and never participates in
a string comparison; not applicable to it. Verified by reading every line of both
`ddl/src/pkg/mss_osag_dbprop.sql` (32 lines) and `ddl/src/pkgb/mss_osag_dbprop.sql`
(90 lines) for every `IS NULL`, `IS NOT NULL`, `=`, `!=`/`<>`, and `||` site.

### 2. SELECT INTO strictness

Two `SELECT ... INTO` sites in this package, matching the Phase 1 inventory count:

- `ddl/src/pkgb/mss_osag_dbprop.sql:18` (`get_number_by_host`) — `SELECT <fn-call> INTO
  l_string FROM DUAL`. `DUAL` always has exactly one row; `NO_DATA_FOUND`/`TOO_MANY_ROWS`
  are structurally impossible here. No handler exists at this site and none is needed —
  translate as `SELECT ... INTO STRICT` with no local handler; it will never actually trip.
- `ddl/src/pkgb/mss_osag_dbprop.sql:75` (`get_string_by_host`) — `SELECT id INTO v_key_id
  FROM mss.key WHERE name = i_property_name`. `mss.key.name` has a unique index
  (`u_key_name`), so `TOO_MANY_ROWS` is structurally impossible; `NO_DATA_FOUND` IS
  reachable (unknown property name) and IS explicitly handled (S-DBPROP-006/007) —
  translate as `SELECT ... INTO STRICT` with a matching `NO_DATA_FOUND`/PostgreSQL
  `NO_DATA_FOUND`-equivalent handler that reproduces the `-20801` raise.

`get_string_by_host_key_id` has NO `SELECT ... INTO` site at all — it is a cursor `FOR`
loop (S-DBPROP-003), which has no strictness question in the first place; zero rows is a
normal, non-exceptional outcome (empty loop body).

### 3. Exception codes

Two distinct exception paths, both PROVISIONAL pending Phase 3's XCUT-01 authoritative
SQLSTATE mapping table:

- `OSAG_DBPROP_STATE.S_ERRNO_UNKNOWN_DBPROP` = `-20801`, declared with
  `PRAGMA EXCEPTION_INIT` (`ddl/src/pkg/mss_osag_dbprop_state.sql:7-8`), raised via
  `RAISE_APPLICATION_ERROR` at `ddl/src/pkgb/mss_osag_dbprop.sql:79` (S-DBPROP-006).
- `OSAG_DBPROP_STATE.e_abort`, declared WITHOUT `PRAGMA EXCEPTION_INIT`
  (`ddl/src/pkg/mss_osag_dbprop_state.sql:5`), raised via bare `RAISE` at
  `ddl/src/pkgb/mss_osag_dbprop.sql:82` (S-DBPROP-007) — carries no fixed Oracle error
  code of its own and must not be mapped to the same PostgreSQL error as the `-20801` case.

This spec records both call sites and their distinctness; it does not invent the final
SQLSTATE assignment for either.

### 4. Package state

None. Verified by reading the full 90-line package body
(`ddl/src/pkgb/mss_osag_dbprop.sql`) top to bottom: the body opens directly with
`FUNCTION get_number_by_host` at line 11, immediately after the `IS`/comment header —
there is no declare section between the package body's opening and its first routine, and
the file ends at line 89-90 (`END OSAG_DBPROP; /`) with no trailing unnamed
initialization block. Matches the Phase 1 inventory's `package_state: []` for this package.

### 5. FUNCTION vs PROCEDURE

None of the three routines issues `COMMIT`/`ROLLBACK`, and none carries
`PRAGMA AUTONOMOUS_TRANSACTION` — verified by reading the full 90-line body (matches the
inventory's `has_commit: false`, `has_rollback: false`, `autonomous_transaction: false` for
this package). All three are declared `FUNCTION` in Oracle
(`ddl/src/pkg/mss_osag_dbprop.sql:23-25`) and map straightforwardly to PostgreSQL
`FUNCTION`s; there is no transaction-control hazard for this package.

## Assumptions / Unresolved

- Whether `mss.key.name` could ever literally hold the empty string `''` in production
  data cannot be verified from static Oracle source alone (no live Oracle instance is
  available for this phase, and the checked-in `masterdata/MSS/key.csv` is a reference
  snapshot, not a guarantee about all historical/future rows). S-DBPROP-009 records the
  translation decision (explicit `''`/`NULL` normalization at the boundary) precisely so
  the translation does not silently depend on this unverified invariant.
- `OSAG_DBPROP_STATE.e_abort`'s effective Oracle error code (the number Oracle would
  actually assign at runtime to an uncaught, non-`EXCEPTION_INIT`'d named exception) is
  general PL/SQL behaviour, not something this repo's static source or a live Oracle
  instance can confirm for this specific case. Phase 3's XCUT-01 owns the final
  SQLSTATE mapping for it; this spec only asserts that it must be DISTINCT from the
  `-20801` case.
- Nothing else is unresolved: every `SELECT ... INTO` site (2), every `RAISE_APPLICATION_ERROR`/named-exception raise (2), the full declare section (none), and every `VARCHAR2`
  comparison/concatenation site in the package were reviewed against the full text of both
  `ddl/src/pkg/mss_osag_dbprop.sql` and `ddl/src/pkgb/mss_osag_dbprop.sql`.
