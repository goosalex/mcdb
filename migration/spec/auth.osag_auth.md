---
oracle_schema: AUTH
oracle_package: OSAG_AUTH
pg_schema: auth
pg_prefix: osag_auth
clause_prefix: AUTH
oracle_spec: ddl/src/pkg/auth_osag_auth.sql
oracle_body: ddl/src/pkgb/auth_osag_auth.sql
public_routines: 3
---

# AUTH.OSAG_AUTH — PostgreSQL spec

Login lifecycle mutations for the `auth` scheme: deleting a login and its dependent rows,
and granting roles/user-roles. Per the package header comment
(`ddl/src/pkg/auth_osag_auth.sql:6-8`), "Manages the scheme auth - provides function for
altering records - selects are done directly" — i.e. this package is a write-path helper,
not a read API.

## Routines

### delete_login

- **Oracle signature:** `PROCEDURE delete_login(p_login_id login.id%TYPE)`
- **PostgreSQL name:** `auth.osag_auth_delete_login` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/auth_osag_auth.sql:19`
- **Defined:** `ddl/src/pkgb/auth_osag_auth.sql:7-85`
- Deletes a login and every row that references it (consented terms, news-entry links,
  user-permission scopes, automatic profiles, the login row itself, and conditionally the
  underlying contact), delegating notification cleanup to `TT.OSAG_NOTIFY`. Logs and
  re-raises on unexpected errors; deliberately swallows the "no profile for this login"
  case and any contact-cleanup failure.

### grant_role

- **Oracle signature:** `PROCEDURE grant_role(p_login_id login.id%TYPE, p_role_id role.id%TYPE)`
- **PostgreSQL name:** `auth.osag_auth_grant_role` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/auth_osag_auth.sql:23`
- **Defined:** `ddl/src/pkgb/auth_osag_auth.sql:90-102`
- DEPRECATED (per its own header comment and `grant_user_role`'s doc, "use
  grant_user_role instead"). Only handles the single hardcoded case
  `p_role_id = 3` (`mc-cust-radius`), delegating to `grant_user_role`; any other
  `p_role_id` raises `VALUE_ERROR` after logging.

### grant_user_role

- **Oracle signature:** `PROCEDURE grant_user_role(p_login_id login.id%TYPE, p_user_role_id user_role.id%TYPE)`
- **PostgreSQL name:** `auth.osag_auth_grant_user_role` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/auth_osag_auth.sql:28`
- **Defined:** `ddl/src/pkgb/auth_osag_auth.sql:106-153`
- Grants a user-role to a login's automatic profile, creating that automatic profile
  first if none exists yet. No-ops (via a special-cased unique-constraint swallow) if the
  grant already exists.

## Clauses

### S-AUTH-001

- **routines:** delete_login
- **claim:** `delete_login` resolves the login's `contact_id` via
  `SELECT contact_id INTO v_contact_id FROM login WHERE id = p_login_id`. `login.id` is
  the primary key, so `TOO_MANY_ROWS` is structurally impossible. There is NO local
  `NO_DATA_FOUND` handler at this specific site — a nonexistent `p_login_id` propagates
  `NO_DATA_FOUND` up to the routine's own outermost `WHEN OTHERS` handler (S-AUTH-007),
  which logs it and re-raises to the caller.
- **source:** `ddl/src/pkgb/auth_osag_auth.sql:21-23`

### S-AUTH-002

- **routines:** delete_login
- **claim:** `delete_login` delegates login-notification cleanup to
  `TT.OSAG_NOTIFY.delete_notifications_for_login(p_login_id)` — an out-of-scope
  transitive dependency (a separate package, not specced in this plan). This spec records
  only that the call exists and happens unconditionally, before any of `delete_login`'s
  own `DELETE` statements.
- **source:** `ddl/src/pkgb/auth_osag_auth.sql:25`

### S-AUTH-003

- **routines:** delete_login
- **claim:** `delete_login` unconditionally deletes `auth.consented_term` and
  `mss.news_entry_2_login` rows referencing `p_login_id`, with no existence check and no
  error if zero rows match (`DELETE` never raises `NO_DATA_FOUND` in Oracle or
  PostgreSQL, regardless of match count).
- **source:** `ddl/src/pkgb/auth_osag_auth.sql:27-28`

### S-AUTH-004

- **routines:** delete_login
- **claim:** The nested block that removes user-permission scopes and automatic profiles
  (cursor `c_all_user_permission_ids` over `auth.user_permission` joined through
  `auth.login2profile`/`auth.profile`, plus a second inline query for automatic
  (`is_automatic = 1`) profiles) uses two cursor `FOR` loops, NOT `SELECT ... INTO`. Its
  own `EXCEPTION WHEN NO_DATA_FOUND THEN NULL` handler is therefore dead code with
  respect to those loops: a cursor `FOR` loop over zero rows is simply an empty loop, not
  an exception — so this handler can never actually fire from the loops it wraps. Its
  `WHEN OTHERS THEN RAISE` bare re-raise DOES matter: any real error from inside the loop
  bodies (e.g. a constraint violation on one of the nested `DELETE`s) propagates to
  `delete_login`'s own outermost handler (S-AUTH-007) unchanged.
- **source:** `ddl/src/pkgb/auth_osag_auth.sql:13-17, 30-53`

### S-AUTH-005

- **routines:** delete_login
- **claim:** After the nested block, `delete_login` unconditionally deletes the
  `auth.login` row itself. Because S-AUTH-001's `SELECT ... INTO` already raised
  `NO_DATA_FOUND` (and aborted the routine) if `p_login_id` did not exist, this `DELETE`
  is only ever reached when the target row is known to exist.
- **source:** `ddl/src/pkgb/auth_osag_auth.sql:55`

### S-AUTH-006

- **routines:** delete_login
- **claim:** `delete_login`'s contact-cleanup block deletes the `stop.contact` row for
  `v_contact_id` ONLY if no other `login` row still references it and no
  `mcaudit.record` references it; if the contact survives (still referenced elsewhere),
  its `short` column is cleared to `NULL` instead (to avoid a future unique-constraint
  collision on `stop.contact.short` when a new login is created later). This entire block
  has its OWN `WHEN OTHERS` handler that logs via `plog.notice` and does **not** re-raise
  — the one place in this package where an exception is deliberately absorbed rather than
  propagated, so a contact-cleanup failure must never abort the overall `delete_login`
  call.
- **source:** `ddl/src/pkgb/auth_osag_auth.sql:58-76`

### S-AUTH-007

- **routines:** delete_login
- **claim:** `delete_login`'s outermost `EXCEPTION WHEN OTHERS` logs via `plog.err`
  (including `sqlerrm`) and then bare `RAISE`s — every unhandled exception reaching this
  point (including the propagated `NO_DATA_FOUND` of S-AUTH-001, and any real error from
  S-AUTH-004's nested block) is logged exactly once here and then surfaced to the caller
  unchanged.
- **source:** `ddl/src/pkgb/auth_osag_auth.sql:80-84`

### S-AUTH-008

- **routines:** grant_role
- **claim:** `grant_role` handles exactly one case: `p_role_id = 3`, which delegates to
  `grant_user_role(p_login_id, 1000)`. For ANY other `p_role_id`, it logs a `plog.notice`
  and raises the PL/SQL predefined exception `VALUE_ERROR` (Oracle's `ORA-06502`) — not a
  custom `RAISE_APPLICATION_ERROR` code. PostgreSQL has no directly-named equivalent
  exception; the mapping is deferred to Phase 3's XCUT-01.
- **source:** `ddl/src/pkgb/auth_osag_auth.sql:94-100`

### S-AUTH-009

- **routines:** grant_user_role
- **claim:** `grant_user_role` has three unguarded `SELECT ... INTO` sites with different
  strictness profiles: `v_count` (line 117, `SELECT COUNT(*) INTO ...`) and `v_ap_id`
  (line 121, `SELECT NVL(MIN(p.id), 0) INTO ...`) are both aggregate queries that ALWAYS
  return exactly one row regardless of match count — `NO_DATA_FOUND` is structurally
  impossible for either. `v_company_id` (line 125,
  `SELECT company_id INTO v_company_id FROM auth.login WHERE id = p_login_id`) is NOT an
  aggregate and CAN raise `NO_DATA_FOUND` if `p_login_id` does not exist; there is no
  local handler for this specific site, so it propagates to the routine's own outermost
  `WHEN OTHERS` (S-AUTH-011).
- **source:** `ddl/src/pkgb/auth_osag_auth.sql:117, 121, 125`

### S-AUTH-010

- **routines:** grant_user_role
- **claim:** If no existing grant is found (`v_count = 0`) and the login has no
  "automatic" profile yet (`v_ap_id = 0`), `grant_user_role` creates one: fetches
  `auth.seq_profile.nextval` via `SELECT ... INTO ... FROM DUAL` (line 132 — a `DUAL`
  select, always exactly one row, same structural guarantee as S-DBPROP-001), inserts the
  new `auth.profile` row (`is_automatic = 1`) and links it via `auth.login2profile`. It
  then always fetches `auth.seq_user_permission.nextval` (line 136, same `DUAL`
  guarantee) and inserts the new `auth.user_permission` plus its
  `auth.user_company_scope` row.
- **source:** `ddl/src/pkgb/auth_osag_auth.sql:129-139`

### S-AUTH-011

- **routines:** grant_user_role
- **claim:** `grant_user_role`'s outermost `WHEN OTHERS` handler swallows ONLY unique
  constraint violations — checking `SQLCODE != -00001` before logging/re-raising means a
  `SQLCODE = -1` (`ORA-00001`, unique constraint violated — PostgreSQL's `23505`
  `unique_violation`) is silently absorbed with the code comment "don't raise... e.g. the
  record exists already", making a re-grant of an existing permission a silent no-op.
  EVERY other error is logged via `plog.err` and re-raised. This is genuine business
  logic (idempotent re-grant), not merely logging, and the translation must reproduce the
  exact `SQLCODE`/`SQLSTATE` discrimination, not merely catch-and-swallow everything.
- **source:** `ddl/src/pkgb/auth_osag_auth.sql:144-151`

## Checklist

### 1. Empty-string / NULL handling

N/A — verified by reading all three public routine signatures
(`ddl/src/pkg/auth_osag_auth.sql:19,23,28`): every parameter is a `NUMBER`-based `%TYPE`
anchor (`login.id%TYPE`, `role.id%TYPE`, `user_role.id%TYPE`). The only `VARCHAR2`-typed
identifiers anywhere in the package body are the `S_PREFIX` log-message constants (e.g.
`ddl/src/pkgb/auth_osag_auth.sql:9`), which are concatenated (`||`) only with other
constant text and `sqlerrm` (never `NULL` inside an exception handler) for cosmetic log
formatting — never compared against or derived from caller-supplied data. No parameter,
column, or local variable in this package takes part in an `IS NULL`/`IS NOT NULL` check,
an equality/inequality comparison, or a `||` concatenation against a `VARCHAR2`/`CLOB`
value that originates from a caller.

### 2. SELECT INTO strictness

Six `SELECT ... INTO` sites, matching the Phase 1 inventory count exactly:

- `ddl/src/pkgb/auth_osag_auth.sql:21` (`delete_login`, `v_contact_id`) — no local
  handler; `login.id` is PK so only `NO_DATA_FOUND` is reachable; propagates to the
  routine's outermost `WHEN OTHERS` (S-AUTH-001/007).
- `ddl/src/pkgb/auth_osag_auth.sql:117` (`grant_user_role`, `v_count`) — `COUNT(*)`
  aggregate, always exactly one row; `NO_DATA_FOUND` structurally impossible
  (S-AUTH-009).
- `ddl/src/pkgb/auth_osag_auth.sql:121` (`grant_user_role`, `v_ap_id`) — `NVL(MIN(...),0)`
  aggregate, always exactly one row; structurally impossible (S-AUTH-009).
- `ddl/src/pkgb/auth_osag_auth.sql:125` (`grant_user_role`, `v_company_id`) — plain
  (non-aggregate) select on `auth.login.id` (PK); no local handler; `NO_DATA_FOUND`
  reachable if `p_login_id` doesn't exist, propagates to the routine's outermost
  `WHEN OTHERS` (S-AUTH-009/011).
- `ddl/src/pkgb/auth_osag_auth.sql:132` (`grant_user_role`, `v_ap_id` from
  `auth.seq_profile.nextval` via `DUAL`) — `DUAL` select, always exactly one row
  (S-AUTH-010).
- `ddl/src/pkgb/auth_osag_auth.sql:136` (`grant_user_role`, `v_new_permission_id` from
  `auth.seq_user_permission.nextval` via `DUAL`) — same `DUAL` guarantee (S-AUTH-010).

Translation: all six become `SELECT ... INTO STRICT`. The two reachable-`NO_DATA_FOUND`
sites (21, 125) have NO local handler in Oracle either — the strict translation must
likewise have no local handler, letting the exception propagate to the enclosing
`WHEN OTHERS` exactly as Oracle does. The other four are aggregate/`DUAL` selects where
`STRICT` can never actually trip.

### 3. Exception codes

Three distinct raise/re-raise shapes, all PROVISIONAL pending Phase 3's XCUT-01:

- `VALUE_ERROR` (PL/SQL predefined, `ORA-06502`), raised in `grant_role` for any
  `p_role_id != 3` (S-AUTH-008, `ddl/src/pkgb/auth_osag_auth.sql:99`).
- A special-cased Oracle unique-constraint check (`SQLCODE != -00001`) in
  `grant_user_role`'s `WHEN OTHERS`, which swallows `ORA-00001` and re-raises everything
  else (S-AUTH-011, `ddl/src/pkgb/auth_osag_auth.sql:144-151`) — PostgreSQL's equivalent
  discriminator is `SQLSTATE '23505'` (`unique_violation`), not a numeric `SQLCODE`.
- Bare `RAISE` re-raises after logging, in `delete_login`'s outermost handler
  (`ddl/src/pkgb/auth_osag_auth.sql:82-83`) and `grant_user_role`'s outermost handler
  (`ddl/src/pkgb/auth_osag_auth.sql:149-150`) — these preserve whatever the ORIGINAL
  exception was (including the two propagated `NO_DATA_FOUND` cases above), they do not
  introduce a new code.

No `RAISE_APPLICATION_ERROR` call exists anywhere in this package (0 sites) — confirmed
by reading the full 156-line body.

### 4. Package state

None. Verified by reading the full 156-line package body
(`ddl/src/pkgb/auth_osag_auth.sql`): the body opens directly with
`PROCEDURE delete_login` immediately after `IS` (line 3-7), with no package-level declare
section, and the file ends at line 155-156 (`END OSAG_AUTH; /`) with no trailing unnamed
initialization block. Matches the Phase 1 inventory's `package_state: []` for this
package.

### 5. FUNCTION vs PROCEDURE

None of the three routines issues `COMMIT`/`ROLLBACK`, and none carries
`PRAGMA AUTONOMOUS_TRANSACTION` — verified by reading the full 156-line body (matches the
inventory's `has_commit: false`, `has_rollback: false`, `autonomous_transaction: false`
for this package). All three are declared `PROCEDURE` in Oracle
(`ddl/src/pkg/auth_osag_auth.sql:19,23,28`) and map straightforwardly to PostgreSQL
`PROCEDURE`s. `delete_login` calls `TT.OSAG_NOTIFY.delete_notifications_for_login`
(S-AUTH-002) — whether THAT transitive dependency itself has any transaction-control
implications is a question for `OSAG_NOTIFY`'s own (not-yet-written) spec, not this one;
recorded as a dependency boundary below.

## Assumptions / Unresolved

- Whether `TT.OSAG_NOTIFY.delete_notifications_for_login` (called by `delete_login`,
  S-AUTH-002) itself performs any `COMMIT`/`ROLLBACK` or has other transaction-control
  implications that would affect `delete_login`'s eventual FUNCTION/PROCEDURE
  classification is OUT OF SCOPE for this spec — `OSAG_NOTIFY` is a separate transitive
  dependency package with its own spec, not written in this plan. Recorded as a
  dependency boundary, not resolved here.
- `VALUE_ERROR`'s exact Oracle error code (`ORA-06502`, from general PL/SQL predefined-
  exception behaviour) cannot be independently confirmed against a live instance of this
  specific database — no live Oracle exists for this phase. Phase 3's XCUT-01 owns the
  authoritative mapping to a PostgreSQL SQLSTATE.
- `grant_role` is documented as deprecated in favour of `grant_user_role`, and the source
  gives no evidence of whether it still has live callers today (static analysis of
  `ddl/src/**` alone cannot determine this — that would require either a live Oracle
  instance's dependency views or an application-code-level grep outside this repo's
  scope). The spec preserves the AS-WRITTEN redirect-to-role-1000 behaviour rather than
  assuming it is dead code, since there is no positive evidence either way.
- Nothing else is unresolved: every `SELECT ... INTO` site (6), every `RAISE`/named
  exception (`VALUE_ERROR`, the `SQLCODE`-guarded unique-constraint swallow, both bare
  re-raises), the full declare section (none), and the single `WHEN OTHERS`-swallows-and-
  does-not-re-raise site (S-AUTH-006) were reviewed against the full text of both
  `ddl/src/pkg/auth_osag_auth.sql` and `ddl/src/pkgb/auth_osag_auth.sql`. `AUTH.OSAG_AUTH`
  does not reference `AUTH.OSAG_AUTH_STATE` anywhere in either file (confirmed by grep);
  no separate note on that package is needed here.
