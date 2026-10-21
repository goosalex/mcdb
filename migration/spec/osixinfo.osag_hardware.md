---
oracle_schema: OSIXINFO
oracle_package: OSAG_HARDWARE
pg_schema: osixinfo
pg_prefix: osag_hardware
clause_prefix: HW
oracle_spec: ddl/src/pkg/osixinfo_osag_hardware.sql
oracle_body: ddl/src/pkgb/osixinfo_osag_hardware.sql
public_routines: 3
---

# OSIXINFO.OSAG_HARDWARE — PostgreSQL spec

Per its header (`ddl/src/pkg/osixinfo_osag_hardware.sql:5-12`), this package was "copied
over from GUMA2.OSAG_GUMA by phm@open.ch in 2024 to get rid of guma pipeline" and
"contains a bunch of functions that are used related to the hardware replacement
process". Three public procedures: `check_replaced_hw_for_host` — called "by the
'submit_heartbeat' procedure" (`ddl/src/pkgb/osixinfo_osag_hardware.sql:156`, an
external heartbeat receiver; no PL/SQL caller exists in `ddl/src/**`) when a host
reports a MAC address: if it equals the MAC of the host's registered REPLACEMENT
hardware, the replacement is carried out and a **10017 "hardware installation"** event
is raised through `TT.EVENT_INTERFACE.newevent_new`; `replace_hardware` — the
replacement itself (archive the old hardware to `mss.hardware_history`, stamp its
disposal date, swap `mss.host.hardware_id`, append two lifecycle items), "called by the
gumaserver" (`pkg:45`); and `add_hardware_lifecycle_item` — one lifecycle row plus the
back-link on `mss.hardware`. One private helper, `dump_to_hw_history`.

The companion package `OSIXINFO.OSAG_EXCEPTIONS` (`ddl/src/pkg/osixinfo_osag_exceptions.sql`,
two exception declarations, empty body) needs NO PostgreSQL object: its `e_abort` becomes
SQLSTATE `OS010`, its never-raised `e_silentexit` is reserved as `OS011` (S-HW-012,
PROVISIONAL per `migration/mapping/sqlstate-map.md` rule 3/4). The two public constants
in this package's spec (`HW_CHANGED_EVENT_TYPE`, `TODO_PRIVATE_HW_MIG`) are inlined
(S-HW-001). No behaviour is corrected in this spec — every clause is Oracle-faithful;
the one shape worth knowing before reading on is that `check_replaced_hw_for_host`'s
`WHEN no_data_found THEN return` also swallows `NO_DATA_FOUND` raised deep inside
`replace_hardware` (S-HW-013).

## Routines

### check_replaced_hw_for_host

- **Oracle signature:** `PROCEDURE check_replaced_hw_for_host(p_host_id mss.host.id%TYPE, p_reported_mac mss.hardware.mac_address%TYPE)`
- **PostgreSQL name:** `osixinfo.osag_hardware_check_replaced_hw_for_host` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/osixinfo_osag_hardware.sql:28-29`
- **Defined:** `ddl/src/pkgb/osixinfo_osag_hardware.sql:162-203`
- Joins the host to its current and replacement hardware, filtered on the replacement's
  MAC = `p_reported_mac`; on a match runs `replace_hardware` and raises a 10017 event
  with a "First heartbeat received" text; on no match returns silently. Catches
  `NO_DATA_FOUND` (silent return) and `OSAG_EXCEPTIONS.e_abort` (`plog.warning`).

### add_hardware_lifecycle_item

- **Oracle signature:** `PROCEDURE add_hardware_lifecycle_item(p_hardware_id mss.hardware.id%TYPE, p_hardware_lc_state_id mss.hardware_lifecycle_item.hardware_lc_state_id%TYPE, p_hardware_lc_location_id mss.hardware_lifecycle_item.hardware_lc_location_id%TYPE, p_creator mss.hardware_lifecycle_item.creator%TYPE)`
- **PostgreSQL name:** `osixinfo.osag_hardware_add_hardware_lifecycle_item` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/osixinfo_osag_hardware.sql:36-40`
- **Defined:** `ddl/src/pkgb/osixinfo_osag_hardware.sql:83-105`
- Pulls `mss.hardware_lifecycle_item_seq`, inserts one `mss.hardware_lifecycle_item` row
  and points `mss.hardware.hardware_lifecycle_item_id` at it. No exception handler.

### replace_hardware

- **Oracle signature:** `PROCEDURE replace_hardware(p_host_id mss.host.id%TYPE, p_old_hw_id mss.hardware.id%TYPE, p_new_hw_id mss.hardware.id%TYPE)`
- **PostgreSQL name:** `osixinfo.osag_hardware_replace_hardware` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/osixinfo_osag_hardware.sql:47-49`
- **Defined:** `ddl/src/pkgb/osixinfo_osag_hardware.sql:114-150`
- Archives the old hardware via `dump_to_hw_history`, sets its `disposal_date`, swaps
  the host's `hardware_id` to the new hardware and clears `replacement_hardware_id`, then
  adds lifecycle items "Disposed" (old) and "Installed" (new) at location 9 or 3. No
  exception handler — everything `dump_to_hw_history` raises propagates to the caller.

Private helper (body only): `dump_to_hw_history(p_host_id, p_old_hardware_id)`, line 10.

## Clauses

### S-HW-001

- **routines:** check_replaced_hw_for_host, add_hardware_lifecycle_item, replace_hardware
- **claim:** All three public routines are Oracle `PROCEDURE`s with `IN` parameters only
  (2, 4 and 3 respectively, all `%TYPE`-anchored to `mss.host`/`mss.hardware`/
  `mss.hardware_lifecycle_item` columns — numeric ids except `p_reported_mac`, a
  `VARCHAR2(128)`); none returns a value, none issues `COMMIT`/`ROLLBACK`, none carries
  `PRAGMA AUTONOMOUS_TRANSACTION`. `name-map.csv` carries `pg_kind=procedure` for all
  three. The package spec additionally declares two public constants:
  `HW_CHANGED_EVENT_TYPE CONSTANT NUMBER := '10017'` (a string literal implicitly
  converted; value 10017, `tt.event_type` "hardware installation") and
  `TODO_PRIVATE_HW_MIG CONSTANT VARCHAR2(1024)` = `'To Do:' || CHR(10) || ' - Check
  ticket type. Must be: migration' || CHR(10) || ' - Check that this ticket is a hardware
  migration tracking ticket.' || CHR(10) || '   If not: check if a matching migration
  ticket is deferred. Inform TAM.'`. Both are used only inside this package (lines 188,
  193); they get no PostgreSQL object and are inlined in the translation. The single
  body-only helper `dump_to_hw_history` (line 10, not declared in the spec) is private:
  the translation exposes it as `osixinfo.osag_hardware__dump_to_hw_history` with
  `EXECUTE` revoked from `PUBLIC` (the project's private-routine convention), never under
  a public `osag_hardware_<name>` name.
- **source:** `ddl/src/pkg/osixinfo_osag_hardware.sql:28-29, 36-40, 47-49, 56, 64-68`, `ddl/src/pkgb/osixinfo_osag_hardware.sql:10, 188, 193`

### S-HW-002

- **routines:** add_hardware_lifecycle_item
- **claim:** `add_hardware_lifecycle_item` executes exactly three statements, in order,
  with no exception handler: (1) `SELECT mss.hardware_lifecycle_item_seq.nextval INTO
  l_hardware_lifecycle_item_id FROM dual`; (2) `INSERT INTO mss.hardware_lifecycle_item
  (id, hardware_id, hardware_lc_state_id, hardware_lc_location_id, creator) VALUES
  (l_id, p_hardware_id, p_hardware_lc_state_id, p_hardware_lc_location_id, p_creator)` —
  `created`/`activated` take their column defaults (current timestamp),
  `hardware_lc_transit_state_id`/`_info_id` stay `NULL`; (3) `UPDATE mss.hardware SET
  hardware_lifecycle_item_id = l_id WHERE hardware.id = p_hardware_id`. After the call
  the hardware row points at the NEW lifecycle item (replacing any previous link) and
  exactly one new lifecycle row exists for it. `p_creator` may be `NULL` (both
  `replace_hardware` calls pass `NULL`, lines 147-148). A `p_hardware_id` with no
  `mss.hardware` row updates zero rows at (3) and fails the lifecycle row's FK
  (`hardware_lifecycle_item_fk1`) when constraints are checked — not asserted (deferred
  FKs in the test transaction).
- **source:** `ddl/src/pkgb/osixinfo_osag_hardware.sql:89-104, 147-148`

### S-HW-003

- **routines:** replace_hardware
- **claim:** `replace_hardware(p_host_id, p_old_hw_id, p_new_hw_id)` executes, in order
  and with no exception handler: (1) `dump_to_hw_history(p_host_id, p_old_hw_id)`
  (S-HW-004..007) — BEFORE any data change, so every failure it raises leaves the
  database untouched; (2) `UPDATE mss.hardware SET disposal_date = SYSDATE WHERE id =
  p_old_hw_id`; (3) `UPDATE mss.host SET hardware_id = p_new_hw_id,
  replacement_hardware_id = NULL WHERE id = p_host_id`; (4) `l_hardware_lc_location_id :=
  9` if a `mss.host` row with `id = p_host_id AND service_company_id = 6` exists, else
  `3` (`SELECT CASE WHEN EXISTS(...) THEN 9 ELSE 3 END INTO ... FROM dual` — always one
  row); (5) `add_hardware_lifecycle_item(p_old_hw_id, 6, l_loc, NULL)` ("Disposed");
  (6) `add_hardware_lifecycle_item(p_new_hw_id, 4, l_loc, NULL)` ("Installed"). Net
  effect for a well-formed host: one `mss.hardware_history` row, old hardware
  `disposal_date` set, host now on the new hardware with no replacement registered, two
  new lifecycle items (state 6 on the old, state 4 on the new, same location), both
  hardware rows linked to their new lifecycle item.
- **source:** `ddl/src/pkgb/osixinfo_osag_hardware.sql:114-150`

### S-HW-004

- **routines:** replace_hardware, check_replaced_hw_for_host
- **claim:** `dump_to_hw_history` first reads the whole old hardware row (`SELECT * INTO
  v_oldhardware FROM mss.hardware WHERE id = p_old_hardware_id`, line 27; a missing row
  raises `NO_DATA_FOUND`, unhandled in this helper and in `replace_hardware`), then
  applies two sanity checks IN THIS ORDER: if `hardware_disposal_contact_id IS NULL` →
  `plog.err('dump_to_hw_history: hardware_disposal_contact_id is NULL while replacing hw
  for host_id: ' || p_host_id || ' hw_id: ' || p_old_hardware_id)` and `RAISE
  OSAG_EXCEPTIONS.e_abort`; else if `hardware_disposal_reason_id IS NULL` →
  `plog.err('dump_to_hw_history: hardware_disposal_reason_id is NULL while replacing hw
  for host_id: ' || p_host_id || ' hw_id: ' || p_old_hardware_id)` and `RAISE
  OSAG_EXCEPTIONS.e_abort`. When both ids are `NULL` only the CONTACT message is logged.
  No DML has happened at this point (S-HW-003 (1)).
- **source:** `ddl/src/pkgb/osixinfo_osag_hardware.sql:15, 27-40`

### S-HW-005

- **routines:** replace_hardware, check_replaced_hw_for_host
- **claim:** The archived `log` text is `'hardware_type=' || mss.hardware_type.short ||
  ';disposal_contact=' || stop.contact.email || ';disposal_reason=' ||
  mss.hardware_disposal_reason.name`, read by INNER-joining `mss.hardware` to its type,
  disposal reason and disposal contact (line 43-50). `stop.contact.email` is nullable:
  Oracle's `||` yields `...;disposal_contact=;disposal_reason=...` for a contact without
  e-mail — the translation must preserve that (NULL-as-empty concatenation). A disposal
  contact or reason id that references no row (possible only under deferred FK checking)
  makes the join empty → `NO_DATA_FOUND`.
- **source:** `ddl/src/pkgb/osixinfo_osag_hardware.sql:42-50`

### S-HW-006

- **routines:** replace_hardware, check_replaced_hw_for_host
- **claim:** Host name, service-company short and service-type internal code come from
  ONE `SELECT ... INTO` over `mss.host INNER JOIN stop.company ON host.service_company_id
  = company.id INNER JOIN mss.host2service ON host.id = host2service.host_id INNER JOIN
  mss.service ON host2service.service_id = service.id INNER JOIN mss.service_type ON
  service.service_type_id = service_type.id WHERE host.id = p_host_id` (lines 53-60).
  A host with NO service raises `NO_DATA_FOUND`, handled neither in `dump_to_hw_history`
  nor in `replace_hardware`. **`TOO_MANY_ROWS` is structurally IMPOSSIBLE here (amended
  2026-10-21).** This clause originally derived a two-services case from
  `mss.host2service`'s primary key `(host_id, service_id)` alone; the export also carries
  `CREATE UNIQUE INDEX MSS.IDX_H2S_HOST_UN ON MSS.HOST2SERVICE(HOST_ID)`
  (`ddl/generated/schema.oracle.sql:3700`), so a host is mapped to AT MOST ONE service and
  this join returns at most one row. Confirmed live against the Oracle container on
  2026-10-21 (differential scenario `tt__event_interface__newevent`: a second
  `mss.host2service` row for one host is refused with `ORA-00001 (MSS.IDX_H2S_HOST_UN)`).
  The PostgreSQL template lacked the index (not in the ora2pg output);
  `migration/test/schema-fixes/29_host2service_unique_fixes.sql` adds it, so PostgreSQL
  refuses the second row exactly as Oracle does (`23505`). The absence of any
  `TOO_MANY_ROWS` handler in the package is therefore moot for this site. `stop.company.short` (nullable) and
  `mss.service_type.internal_code` (nullable) are copied as read.
- **source:** `ddl/src/pkgb/osixinfo_osag_hardware.sql:52-60`

### S-HW-007

- **routines:** replace_hardware, check_replaced_hw_for_host
- **claim:** `dump_to_hw_history` ends with ONE `INSERT INTO mss.hardware_history`
  carrying: `id = mss.hardwarehistory_seq.nextval`; `barcode`, `hardware_disposal_comments`,
  `hardware_disposal_contact_id`, `hardware_disposal_reason_id`, `hardware_type_id`,
  `mac_address`, `purchase_date`, `serial_number`, `hardware_deploy_reason_id` copied from
  the old hardware row; `company_short` = the host's service company short; `host_name`
  = the host's name; `service_type_internal_code` = the service type's internal code;
  `log` = S-HW-005's text; `disposal_date = NVL(v_oldhardware.disposal_date, SYSDATE)`
  (an already-stamped disposal date is kept, otherwise "now"); `history_date = SYSDATE`.
  `mss.hardware_history.company_short`, `host_name`, `purchase_date`, `disposal_date`,
  `history_date`, `hardware_disposal_reason_id`, `hardware_disposal_contact_id`,
  `hardware_type_id` are `NOT NULL` (Oracle export `ddl/export/schema.oracle.sql:34`,
  same in the migrated schema): an old hardware row with `purchase_date IS NULL`, or a
  service company with `short IS NULL`, makes the INSERT fail with a NOT NULL violation
  (Oracle ORA-01400, PostgreSQL `23502`) that nothing in the package handles — it
  propagates out of `replace_hardware` and `check_replaced_hw_for_host` alike.
- **source:** `ddl/src/pkgb/osixinfo_osag_hardware.sql:64-72`

### S-HW-008

- **routines:** check_replaced_hw_for_host
- **claim:** `check_replaced_hw_for_host` resolves `new_hardware.mac_address,
  old_hardware.id, host.name, new_hardware.id` with ONE `SELECT ... INTO` over `mss.host
  JOIN mss.hardware new_hardware ON host.replacement_hardware_id = new_hardware.id JOIN
  mss.hardware old_hardware ON host.hardware_id = old_hardware.id WHERE host.id =
  p_host_id AND new_hardware.mac_address = p_reported_mac` (PK joins: at most one row).
  Zero rows — no such host, host without `replacement_hardware_id`, host without
  `hardware_id`, dangling ids, a `p_reported_mac` that differs from the replacement's
  MAC (string equality, case-sensitive), or a `NULL` `p_reported_mac` — raises
  `NO_DATA_FOUND`, caught by the procedure's `WHEN no_data_found THEN return` ("nothing
  to replace"): NO log line, NO data change, NO exception. The subsequent `IF
  (l_replacement_mac = p_reported_mac)` (line 184) is always true after that `WHERE`.
- **source:** `ddl/src/pkgb/osixinfo_osag_hardware.sql:176-184, 197-198`

### S-HW-009

- **routines:** check_replaced_hw_for_host
- **claim:** On a MAC match, `check_replaced_hw_for_host` (1) runs
  `replace_hardware(p_host_id, l_old_hardware_id, l_replacement_id)` (S-HW-003, with the
  ids found by S-HW-008) and then (2) calls `tt.event_interface.newevent_new(v_event_id
  OUT, 10017, p_host_id, <public>, TODO_PRIVATE_HW_MIG)` with every other parameter
  defaulted. `<public>` = `'First heartbeat received ' || CHR(10) || CHR(10) || 'Received
  first heartbeat from hardware with the MAC address: ' || l_replacement_mac || '. ' ||
  'The heartbeat was sent from the host: ' || l_hostname || '. ' || 'This usually happens
  when a replacement hardware is plugged in for the first time.'` (note the trailing
  space after `received`). Observable TT side effect (per `migration/spec/tt.event_interface.md`,
  S-EVENT-010/011/014; 10017 is appended only to a recent migration/installation ticket
  of type 8/15, otherwise a NEW ticket is opened): a `tt.ticket` (type 1, subject
  `'hardware installation'`, `host_id = p_host_id`) and one `tt.event` with `type_id =
  10017`, `host_id = p_host_id`, `details_public` = the text above and `details_private`
  = the `TODO_PRIVATE_HW_MIG` text (S-HW-001).
- **source:** `ddl/src/pkgb/osixinfo_osag_hardware.sql:184-194`, `ddl/src/pkg/osixinfo_osag_hardware.sql:56, 64-68`

### S-HW-010

- **routines:** check_replaced_hw_for_host
- **claim:** If `dump_to_hw_history`'s sanity checks (S-HW-004) raise
  `OSAG_EXCEPTIONS.e_abort` for the matched old hardware, `check_replaced_hw_for_host`'s
  second handler arm logs via `plog.warning` `'check_replaced_hw_for_host: skipped host '
  || p_host_id` and returns: because the abort happens before any DML (S-HW-003 (1)), the
  host still points at its old hardware, `replacement_hardware_id` is still set, no
  history row, no lifecycle item, no `disposal_date`, no 10017 event, and no exception
  reaches the caller. The `plog.err` line from S-HW-004 precedes the warning (in the
  translation it is emitted by this handler from the exception's message, see S-HW-011 —
  same two lines, same order).
- **source:** `ddl/src/pkgb/osixinfo_osag_hardware.sql:31-40, 122, 167, 200-201`

### S-HW-011

- **routines:** replace_hardware
- **claim:** `replace_hardware` has NO exception handler, so when called directly: a
  `NULL` disposal contact/reason on the old hardware raises `OSAG_EXCEPTIONS.e_abort` to
  the caller (PostgreSQL SQLSTATE `OS010`, S-HW-012) after the S-HW-004 `plog.err`; a
  nonexistent `p_old_hw_id` raises `NO_DATA_FOUND` (`P0002`, message `no data found`);
  a host with two services raises `TOO_MANY_ROWS` (`P0003`). In every one of these cases
  the database is unchanged (the failure precedes all DML). A nonexistent `p_host_id`
  likewise fails in S-HW-006's join with `NO_DATA_FOUND` before any change. **Observability
  of the S-HW-004 log line on this path:** Oracle's `plog.err` ran in an AUTONOMOUS
  transaction (`PRAGMA AUTONOMOUS_TRANSACTION` + `COMMIT`, `ddl/src/pkgb/osag_osag_plog.sql:47,
  54`), so the line survived the propagating `e_abort`. The PostgreSQL plog stub is
  transactional (`migration/pgsql/osag/osag_plog.FINDINGS.md`, "Rollback limitation"), so
  when `e_abort` leaves `replace_hardware` and the caller rolls back, NO log row can
  survive — a test cannot observe it through `osag.plog_stub_log`. The translated `e_abort`
  therefore carries the S-HW-004 log line as its exception MESSAGE_TEXT (Oracle's
  `ORA-06510: PL/SQL: unhandled user-defined exception` carried no text, so no client
  depends on the old wording), and a test pins the reason through the exception message
  instead. Inside `check_replaced_hw_for_host` (S-HW-010) the catching handler emits the
  carried line itself, so there the row IS observable, before the `WARNING`.
- **source:** `ddl/src/pkgb/osixinfo_osag_hardware.sql:27-28, 34, 39, 53-60, 114-150`, `ddl/src/pkgb/osag_osag_plog.sql:47, 54`

### S-HW-012

- **routines:** check_replaced_hw_for_host, replace_hardware
- **claim:** `OSIXINFO.OSAG_EXCEPTIONS` declares exactly two exceptions and nothing
  else: `e_abort` ("abort this procedure") and `e_silentexit` ("exit procedure silently");
  its body is empty. Within `ddl/src/**` only this package references it: `e_abort` is
  raised at lines 34/39 and caught at line 200; `e_silentexit` is referenced NOWHERE
  (grep over `ddl/src` finds the name only in its declaration). Mapping (PROVISIONAL,
  XCUT-01, following `migration/mapping/sqlstate-map.md` rules 3-4 and its `OS000`
  precedent for unnumbered control-flow exceptions): `e_abort` → `OS010` (raised with
  `RAISE EXCEPTION ... USING ERRCODE = 'OS010'`, caught with `WHEN SQLSTATE 'OS010'`),
  `e_silentexit` → `OS011` (reserved, never emitted). No PostgreSQL object is created for
  `OSAG_EXCEPTIONS`; the codes are documented in the translation's FINDINGS and left for
  the integration plan (06-07) to add to the shared `sqlstate-map.md` table. Oracle
  clients never saw a numeric code for these (`ORA-06510: unhandled user-defined
  exception`), so no client branch depends on the chosen value.
- **source:** `ddl/src/pkg/osixinfo_osag_exceptions.sql:10-11`, `ddl/src/pkgb/osixinfo_osag_exceptions.sql:3-5`, `ddl/src/pkgb/osixinfo_osag_hardware.sql:34, 39, 200`

### S-HW-013

- **routines:** check_replaced_hw_for_host
- **claim:** `check_replaced_hw_for_host`'s `WHEN no_data_found THEN return` (line
  197-198) is procedure-wide: it also swallows `NO_DATA_FOUND` raised INSIDE
  `replace_hardware` → `dump_to_hw_history` after the MAC match — a matched host with no
  `mss.host2service` row (S-HW-006), or a disposal contact/reason id with no row
  (S-HW-005) — so such a host is silently treated as "nothing to replace": no log, no
  change (the failing selects precede all DML), no exception. This is Oracle's shape and
  is preserved; the spec records it because it hides a data problem (a monitored host
  without a service) behind silence. `TOO_MANY_ROWS` and NOT NULL violations
  (S-HW-006/007) are NOT swallowed and propagate out of `check_replaced_hw_for_host`.
  Transaction-scope note (recorded, not asserted): a `NO_DATA_FOUND` raised by
  `newevent_new` AFTER `replace_hardware`'s DML would, in Oracle, leave the replacement
  in place while PL/pgSQL's handler subtransaction undoes it — but every `SELECT INTO`
  in `newevent_new` that could raise it for this call shape (host active flag, event type
  10017) has just been proven to have a row, so the path is unreachable in practice.
- **source:** `ddl/src/pkgb/osixinfo_osag_hardware.sql:27-28, 43-60, 122, 185-198`

### S-HW-014

- **routines:** replace_hardware
- **claim:** The lifecycle LOCATION is decided by the host's service company alone:
  `service_company_id = 6` → location 9 ("Internal"), anything else → 3 ("Customer"),
  and BOTH lifecycle items of one replacement use the same location (lines 135-148).
  The STATE ids are fixed: 6 ("Disposed") for the old hardware, 4 ("Installed") for the
  new one. `mss.hardware_lc_state` 4/6 and `mss.hardware_lc_location` 3/9 exist in
  `masterdata/MSS/`.
- **source:** `ddl/src/pkgb/osixinfo_osag_hardware.sql:135-148`

## Checklist

### 1. Empty-string / NULL handling

The only `VARCHAR2` PARAMETER is `p_reported_mac` (`mss.hardware.mac_address%TYPE`,
`check_replaced_hw_for_host`). It appears in `new_hardware.mac_address = p_reported_mac`
(line 182) and `l_replacement_mac = p_reported_mac` (184). `''` is reachable from a
PostgreSQL caller; Oracle collapses it to `NULL`, so `= NULL` matches nothing →
`NO_DATA_FOUND` → silent return (S-HW-008). In PostgreSQL `''` would only match a
hardware row whose `mac_address` is literally `''` — none can exist from Oracle data
(Oracle cannot store `''`). Decision: normalise at the boundary with `NULLIF(p_reported_mac,
'')` so `''` behaves exactly like `NULL` (silent return). Other string sites: the
`||` log/text concatenations at lines 33, 38 (numeric operands, never `NULL` — both ids
are `NOT NULL` by the time they are used), 43-44 (`stop.contact.email` nullable →
`concat()` semantics, S-HW-005; `hardware_type.short` and `hardware_disposal_reason.name`
are `NOT NULL`), 189-192 (`l_replacement_mac` equals the non-`NULL` `p_reported_mac`,
`l_hostname` is `NOT NULL`), 201 (numeric). `v_compshort`/`v_stypeicode` (nullable
columns) are only INSERTed, never compared or concatenated — a `NULL` short fails the
`NOT NULL` column (S-HW-007) in both engines. No `IS NULL` test is made against a string
anywhere (the two `IS NULL` checks, lines 31/36, are numeric id columns).

### 2. SELECT INTO strictness

Six `SELECT ... INTO` sites, matching the inventory's `select_into_sites` `[27, 43, 53,
92, 135, 177]` exactly:

| # | line | routine | zero rows possible? | >1 row possible? | Oracle handler | translation |
|---|---|---|---|---|---|---|
| 1 | 27 | dump_to_hw_history | yes (bad old hw id) | no (PK) | none in helper or `replace_hardware`; `check_replaced_hw_for_host`'s `WHEN no_data_found` swallows (S-HW-013); direct `replace_hardware` callers see it unhandled (S-HW-011) | `STRICT`, no local handler; "no data found" message-parity shim at the `replace_hardware` boundary (externally reachable, unhandled) |
| 2 | 43 | dump_to_hw_history | only under deferred FK (dangling contact/reason/type) | no (PK joins) | same as #1 | `STRICT`, no handler (shared shim) |
| 3 | 53 | dump_to_hw_history | yes (host with no service / no host) | **yes** (host with ≥2 services, `host2service` PK `(host_id, service_id)`) | same as #1 for NDF; `TOO_MANY_ROWS` handled nowhere (S-HW-006) | `STRICT`, no handler; `P0003` propagates from both entry points |
| 4 | 92 | add_hardware_lifecycle_item | no (`FROM dual` sequence pull) | no | none | `SELECT nextval(...) INTO STRICT` |
| 5 | 135 | replace_hardware | no (`CASE ... FROM dual`) | no | none | plain assignment from `EXISTS(...)` |
| 6 | 177 | check_replaced_hw_for_host | yes (S-HW-008 cases) | no (PK joins) | local `WHEN no_data_found THEN return` (197-198) | `STRICT` + same handler |

Inventory cross-check: `exception_handlers: NO_DATA_FOUND 1, TOO_MANY_ROWS 0, OTHERS 0`
— confirmed (line 197 is the only `NO_DATA_FOUND` arm; line 200 is the `e_abort` arm; no
`OTHERS` anywhere). The "no data found" message-parity shim (`sqlstate-map.md` rule 2) is
applied ONCE, around `replace_hardware`'s body, because `NO_DATA_FOUND` from sites #1-#3
is externally reachable and unhandled there; inside `check_replaced_hw_for_host` the
re-raised `P0002` is caught by its own `NO_DATA_FOUND` arm exactly as Oracle's is.

### 3. Exception codes

No `RAISE_APPLICATION_ERROR` (inventory `raise_application_error: []`, confirmed). Two
`RAISE OSAG_EXCEPTIONS.e_abort` sites (lines 34, 39), one `WHEN OSAG_EXCEPTIONS.e_abort`
handler (line 200); `e_abort` escapes the package through `replace_hardware` (no
handler) and is swallowed in `check_replaced_hw_for_host`. Mapping `e_abort` → `OS010`,
`e_silentexit` → `OS011` (unused), **PROVISIONAL** (S-HW-012). Predefined exceptions
that leave the package: `NO_DATA_FOUND` (`P0002`, via `replace_hardware` only),
`TOO_MANY_ROWS` (`P0003`, via both entry points), NOT NULL violations from the history
insert (`23502`, both entry points), FK violations at constraint-check time (`23503`).
No bare `RAISE`, no `WHEN OTHERS`.

### 4. Package state

None. The body has NO declare section — line 3 (`CREATE OR REPLACE PACKAGE BODY ... IS`)
is followed directly by the `dump_to_hw_history` section comment and `PROCEDURE
dump_to_hw_history` (lines 5-10) — and no trailing initialisation block (file ends `END
OSAG_HARDWARE;` at line 205). The package SPEC declares two `CONSTANT`s (lines 56,
64-68), immutable, inlined (S-HW-001). Matches the inventory's `package_state: []`,
`has_init_block: false`. (`OSAG_EXCEPTIONS` is likewise state-free: two exception
declarations, empty body.)

### 5. FUNCTION vs PROCEDURE

All three routines are `PROCEDURE`s (`ddl/src/pkg/osixinfo_osag_hardware.sql:28, 36,
47`); `name-map.csv` says `pg_kind=procedure` for all three; `dump_to_hw_history` is a
`PROCEDURE` too (body line 10). No `COMMIT`, `ROLLBACK` or `PRAGMA
AUTONOMOUS_TRANSACTION` (inventory `has_commit: false`, `has_rollback: false`,
`autonomous_transaction: false`; confirmed by reading all 206 lines). Callers: none in
`ddl/src/**` ("submit_heartbeat" / "gumaserver" are external; `GUMA2.OSAG_GUMA` carries
its OWN older copy of these three routines, `ddl/src/pkg/guma2_osag_guma.sql:34-55`,
translated by plan 06-03 — this package does not call it). Callee:
`tt.event_interface.newevent_new`, a `PROCEDURE` with a leading `OUT` parameter → `CALL
tt.event_interface_newevent_new(v_event_id, 10017, p_host_id, <public>, <private>)`.
Internal calls (`replace_hardware` → `dump_to_hw_history`, `add_hardware_lifecycle_item`;
`check_replaced_hw_for_host` → `replace_hardware`) become `CALL`s between PROCEDUREs. No
XCUT-04 collision.

## Assumptions / Unresolved

- **No behaviour is corrected in this package.** The one questionable shape — the
  procedure-wide `NO_DATA_FOUND` swallow in `check_replaced_hw_for_host` hiding a
  host-without-service data problem (S-HW-013) — is preserved because it is explicitly
  Oracle's own "nothing to replace" contract and the data stays consistent (the failure
  precedes all DML); it is flagged here for the project owner rather than changed.
- **Log lines written immediately before a raise** are only observable in PostgreSQL where
  a handler of this package catches the exception (S-HW-010); when the exception leaves the
  package (S-HW-011) the transactional plog stub loses the row — a known stub limitation
  (`osag_plog.FINDINGS.md`), resolved by Phase 3's non-transactional shipper (XCUT-02). Until
  then the exception message carries the text.
- **SQLSTATE values `OS010`/`OS011`** for `OSAG_EXCEPTIONS` are this plan's proposal; the
  shared `sqlstate-map.md` table was deliberately not edited by a wave-parallel plan.
  06-07 must add the rows (and reconcile with 06-03/06-04, which map their own `*_STATE`
  exceptions). No client can observe the value (Oracle raised an unnumbered user-defined
  exception).
- **`service_company_id = 6` → "Internal"**: the meaning of company 6 (presumably Open
  Systems itself) is a data fact outside the repo (`stop.company` has no masterdata); the
  spec keeps the literal.
- **`HW_CHANGED_EVENT_TYPE := '10017'`** is a string constant assigned to a `NUMBER` —
  Oracle converts implicitly; translated as the numeric literal 10017.
- **Which ticket the 10017 event lands on** is `newevent_new`'s business (append to a
  recent type-8/15 migration/installation ticket, else a new type-1 ticket); the test
  asserts the new-ticket case only, which is what a fresh host sees.
- **Message-text parity** of the propagated `NO_DATA_FOUND`: the shim gives
  `replace_hardware` callers Oracle's `no data found` wording; `TOO_MANY_ROWS`'s text
  (`query returned more than one row` vs `ORA-01422`) is not shimmed, per the project's
  rule-2 scope (shim only `no data found`).
- Nothing else is unresolved: all six `SELECT INTO` sites, both `e_abort` raise sites,
  both handler arms, the `newevent_new` call site, both `add_hardware_lifecycle_item`
  call sites, the (absent) declare section and the `OSAG_EXCEPTIONS` spec/body were
  reviewed against the full text of the three Oracle files; `tt.event_type` 10017 exists
  in `masterdata/TT/event_type.csv`; the `mss.hardwarehistory_seq` /
  `mss.hardware_lifecycle_item_seq` sequences exist in `ddl/generated/sequences/`.
