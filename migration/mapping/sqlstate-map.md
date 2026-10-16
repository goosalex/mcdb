# Oracle error code → PostgreSQL SQLSTATE map (XCUT-01, decided for the TT closure)

Status: **decided for every code the TT closure raises or catches** (2026-10-16,
branch `phoenix/migrate_tt_only`). Codes outside the TT closure are listed where they
were already encountered so Phase 4 extends this table instead of inventing a second one.
This file answers status-report question **Q4**.

## Rules

1. Oracle's predefined exceptions keep PL/pgSQL's own SQLSTATEs — there is no reason to
   invent codes for conditions PostgreSQL already names:

   | Oracle | PostgreSQL SQLSTATE | condition name |
   |---|---|---|
   | `NO_DATA_FOUND` (ORA-01403) | `P0002` | `no_data_found` |
   | `TOO_MANY_ROWS` (ORA-01422) | `P0003` | `too_many_rows` |
   | `VALUE_ERROR` (ORA-06502) | `22023` | `invalid_parameter_value` (when raised deliberately), native `22P02`/`22003` when the engine raises it |
   | `DUP_VAL_ON_INDEX` (ORA-00001) | `23505` | `unique_violation` |
   | NOT NULL constraint (ORA-01400/01407) | `23502` | `not_null_violation` |
   | `OTHERS` | any | `OTHERS` |

2. **The "no data found" message-parity shim stays** (14 sites today). `SELECT ... INTO
   STRICT` raises `P0002` with the text `query returned no rows`; Oracle callers and the
   pilot's tests pin the literal text `no data found`. The shim re-raises `P0002` with
   Oracle's wording at *externally reachable, unhandled* sites only. Keep it until the
   last Oracle client is gone, then delete it in one sweep (`grep -n "'no data found'"`).

3. Application errors (`RAISE_APPLICATION_ERROR(-20NNN, ...)` and `*_STATE` package
   exceptions bound with `PRAGMA EXCEPTION_INIT`) get a **custom SQLSTATE in class `OS`**
   (`OS` = Open Systems; not a class PostgreSQL uses), formed as `OS` + the last three
   digits of the Oracle code. The three digits keep the Oracle number recognisable in
   logs and let `client-rename-map.csv` consumers translate client-side `WHEN OTHERS
   THEN IF SQLCODE = -20980` branches mechanically (`SQLCODE = -20980` →
   `SQLSTATE = 'OS980'`).

4. Each custom SQLSTATE is raised with `RAISE EXCEPTION '<oracle message text>' USING
   ERRCODE = 'OSnnn'` and caught with `WHEN SQLSTATE 'OSnnn' THEN`. Callers that
   branched on the *named* exception (`WHEN event_interface_state.ticket_closed`) use the
   same `WHEN SQLSTATE` form — PostgreSQL has no package-scoped exception names.

## The table

| Oracle code | Declared in | Name | PostgreSQL SQLSTATE | Raised by (translated) | Status |
|---|---|---|---|---|---|
| -20980 | `TT.EVENT_INTERFACE_STATE` | `ticket_closed` | `OS980` | `tt.event_interface_addevent_new` (re-raised through its own `OTHERS` handler) | in use since plan 02-11 |
| -20981 | `TT.TICKET_INTERFACE_STATE` | `ticket_not_scheduled` | `OS981` | nothing — declared, never raised in `ddl/src/pkgb/tt_ticket_interface.sql` (verified: no `RAISE ticket_not_scheduled`, no `-20981`) | reserved, not emitted |
| -20982 | `TT.TICKET_INTERFACE_STATE` | `ticket_scheduling_open` | `OS982` | same — declared, never raised | reserved, not emitted |
| -20801 | `MSS.OSAG_DBPROP_STATE` | `unknown_dbprop` | `OS801` | `mss.osag_dbprop_get_string_by_host` | **to apply** — currently generic `P0001`; one-line change in `migration/pgsql/mss/osag_dbprop.sql` plus the citing test's expected code |
| unnumbered | `MSS.OSAG_DBPROP_STATE` | `e_abort` | `OS000` | internal control flow only | reserved |
| -20000 | `MSS.OSAG_IP_TEST` | unit-test failure | n/a | the Oracle unit tests become pgTAP assertions (`mss__osag_ip__spec.sql`); nothing raises -20000 in PostgreSQL | dropped |
| -20xxx | `AUTH.OSAG_AUTH_STATE` (`S_ERRNO_DUPLICATE_LOGIN`, `..._EMAIL`, `..._ALIAS`, `..._NO_LOGIN_RECORD`, `..._NO_PASSWORD_ONLY`, `..._PASSWORD_RECENTLY_USED`) | AUTH stays on Oracle in the TT-only split | `OS` + last 3 digits when AUTH is translated | — | out of TT scope; rule 3 applies |

The two `*_STATE` packages of TT therefore need **no PostgreSQL object at all**: they
hold one exception + one constant each, and the constant's only consumer is the
`RAISE_APPLICATION_ERROR` site that now says `ERRCODE = 'OS980'`. Document, do not port.

## Client-side consequences (feeds `client-rename-map.csv` application notes)

- `SQLCODE = -20980` / `ORA-20980` string matches in Perl/Java → `SQLSTATE = 'OS980'`
  (DBI: `$dbh->state`, JDBC: `SQLException.getSQLState()`).
- `ORA-01403: no data found` matches → SQLSTATE `P0002`; the message text is preserved by
  the shim, so text matches on `no data found` keep working.
- `ORA-01422` → `P0003`, message `query returned more than one row`.
