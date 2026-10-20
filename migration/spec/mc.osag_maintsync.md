---
oracle_schema: MC
oracle_package: OSAG_MAINTSYNC
pg_schema: mc
pg_prefix: osag_maintsync
clause_prefix: MAINT
oracle_spec: ddl/src/pkg/mc_osag_maintsync.sql
oracle_body: ddl/src/pkgb/mc_osag_maintsync.sql
public_routines: 4
---

# MC.OSAG_MAINTSYNC — PostgreSQL spec

Per its header comment (`ddl/src/pkg/mc_osag_maintsync.sql:6-7`), this package manages the
"synchronization of the maintenance status" of hosts and ISP links. It derives, for every
`mss.host` / `mss.isp_link`, a **maintenance status** (`mc.maintenance_status`: 1 unknown,
2 active, 3 inactive, 4 maintenance) from two facts — is the entity's host active, and is
the host currently inside a *maintenance window* (an open TT ticket's service window that
is running right now and carries a `maintenance_window` or `cust_maintenance_window`
row that disables events or connection escalation, `ddl/src/pkgb/mc_osag_maintsync.sql:28-44`) —
and, whenever the derived status differs from the stored one, writes a history row
(`mc.host_maintenance_history` / `mc.isp_link_maintenance_history`) and updates the
stored status. Two batch procedures do this for all hosts / all ISP links and are scheduled
every minute by Oracle jobs (`ddl/src/jobs/mc_jobs.sql:7,19`); two single-entity
procedures do it for one host / one ISP link on request. Every routine swallows every
error into a `plog.err` line. The five-table maintenance-window join is written out four
times in the body (lines 28-44, 95-115, 198-214, 262-282); the translation keeps that
duplication (no shared view in this plan) and records it in its FINDINGS.

**This spec deliberately specifies CORRECTED behaviour at four sites** (S-MAINT-012,
S-MAINT-016, S-MAINT-017, S-MAINT-018), all in the two single-entity routines, where the
Oracle body is demonstrably broken: `update_single_isp_link`'s status query is missing its
`p_isp_link_id` predicate, tests `maintenance_status_id = NULL` (never true), and reuses
the batch cursor's "a change is needed" filter inside a `SELECT INTO` whose
`NO_DATA_FOUND` handler assumes "no row" means "no interface", so an up-to-date link is
flipped to *unknown*; `update_single_host` reuses the same filter and therefore logs an
ERROR for the normal "nothing to do" case. Per the project owner's standing instruction
(correct provably broken Oracle code, annotate the correction), those clauses state the
corrected behaviour, cite the Oracle lines that are wrong, and the tests assert the
corrected behaviour. Every other clause is Oracle-faithful.

## Routines

### update_host_maint_status

- **Oracle signature:** `PROCEDURE update_host_maint_status`
- **PostgreSQL name:** `mc.osag_maintsync_update_host_maint_status` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/mc_osag_maintsync.sql:16`
- **Defined:** `ddl/src/pkgb/mc_osag_maintsync.sql:10-71`
- Cursor loop over every host (operating system other than 21) whose derived
  maintenance status differs from the stored one (or whose stored status is NULL); for each,
  inserts a `mc.host_maintenance_history` row and updates `mss.host.maintenance_status_id`.
  Any error is logged via `plog.err` and swallowed. Called by the Oracle job
  `mc.update_host_maint_status` every minute (`ddl/src/jobs/mc_jobs.sql:4-13`).

### update_isp_link_maint_status

- **Oracle signature:** `PROCEDURE update_isp_link_maint_status`
- **PostgreSQL name:** `mc.osag_maintsync_update_isp_link_maint_status` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/mc_osag_maintsync.sql:23`
- **Defined:** `ddl/src/pkgb/mc_osag_maintsync.sql:78-174`
- Two cursor loops: (1) every ISP link attached to at least one interface whose derived
  status differs from the stored one (or is NULL or 1) gets a history row, a `plog.notice`
  line and an update; (2) every ISP link attached to NO interface whose stored status is
  not 1 (or NULL) is reset to 1 (unknown) with a history row. Any error is logged via
  `plog.err` and swallowed. Called by the Oracle job `mc.update_isp_link_maint_status`
  every minute (`ddl/src/jobs/mc_jobs.sql:16-25`).

### update_single_host

- **Oracle signature:** `PROCEDURE update_single_host(p_host_id MSS.HOST.ID%TYPE)`
- **PostgreSQL name:** `mc.osag_maintsync_update_single_host` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/mc_osag_maintsync.sql:28`
- **Defined:** `ddl/src/pkgb/mc_osag_maintsync.sql:179-237`
- Derives the maintenance status of one host with the same rules as the batch routine
  and, if it differs from the stored status (or the stored status is NULL), writes a
  history row and updates the host. Any error is logged via `plog.err` and swallowed. No
  caller inside the database (only `pgmig` name-map data references it); client code may
  call it.

### update_single_isp_link

- **Oracle signature:** `PROCEDURE update_single_isp_link(p_isp_link_id MSS.ISP_LINK.ID%TYPE)`
- **PostgreSQL name:** `mc.osag_maintsync_update_single_isp_link` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/mc_osag_maintsync.sql:33`
- **Defined:** `ddl/src/pkgb/mc_osag_maintsync.sql:242-315`
- Reads the stored status of one ISP link, derives its current status (1/unknown when the
  link is attached to no interface) and, if it differs (or the stored status is NULL),
  writes a history row and updates the link. Any error is logged via `plog.err` and
  swallowed. No caller inside the database.

## Clauses

### S-MAINT-001

- **routines:** update_host_maint_status, update_isp_link_maint_status, update_single_host, update_single_isp_link
- **claim:** All four routines are Oracle `PROCEDURE`s with no return value; the two batch
  routines take no parameter, the two single-entity routines take exactly one numeric id
  (`MSS.HOST.ID%TYPE` / `MSS.ISP_LINK.ID%TYPE`). They are created as PostgreSQL
  PROCEDUREs (`pg_kind=procedure` in `name-map.csv` for all four).
- **source:** `ddl/src/pkg/mc_osag_maintsync.sql:16`, `ddl/src/pkg/mc_osag_maintsync.sql:23`, `ddl/src/pkg/mc_osag_maintsync.sql:28`, `ddl/src/pkg/mc_osag_maintsync.sql:33`

### S-MAINT-002

- **routines:** update_host_maint_status, update_isp_link_maint_status, update_single_host, update_single_isp_link
- **claim:** A host is "in a maintenance window" exactly when there exists a `tt.ticket`
  with `status_id < 101` whose `tt.service_window` (joined on `s.ticket_id = t.id`) is
  running right now (`s.start_date < now AND s.end_date > now`, both strict), is linked to
  the host through `tt.host2service_window`, and has a `tt.maintenance_window` OR a
  `tt.cust_maintenance_window` row (both outer-joined on `service_window_id`) with
  `disable_conn_escalation = 1` or `disable_events = 1`. A service window with neither
  kind of maintenance row, or whose flags are all 0, is NOT a maintenance window. When
  several tickets qualify for one host, the maintenance ticket is the one with the
  highest `tt.ticket.id` (`max(t.id)`). The same definition, written out four times, is
  used by all four routines (for ISP links the host is reached through
  `mss.interface` → `mss.interface2isp_link`).
- **source:** `ddl/src/pkgb/mc_osag_maintsync.sql:28-44`, `ddl/src/pkgb/mc_osag_maintsync.sql:95-115`, `ddl/src/pkgb/mc_osag_maintsync.sql:198-214`, `ddl/src/pkgb/mc_osag_maintsync.sql:262-282`

### S-MAINT-003

- **routines:** update_host_maint_status, update_isp_link_maint_status, update_single_host, update_single_isp_link
- **claim:** The derived maintenance status is 3 (inactive) when the host is inactive
  (`h.active = 0`; for ISP links when `MAX(h.active)` over all hosts of the link's
  interfaces is 0), otherwise 2 (active) when the host is in no maintenance window, otherwise
  4 (maintenance). The derived status is never 1.
- **source:** `ddl/src/pkgb/mc_osag_maintsync.sql:20-23`, `ddl/src/pkgb/mc_osag_maintsync.sql:87-90`, `ddl/src/pkgb/mc_osag_maintsync.sql:117-118`, `ddl/src/pkgb/mc_osag_maintsync.sql:189-192`, `ddl/src/pkgb/mc_osag_maintsync.sql:254-257`

### S-MAINT-004

- **routines:** update_host_maint_status
- **claim:** `update_host_maint_status` considers only hosts with `operating_system_id != 21`,
  and touches a host only when its stored `maintenance_status_id` IS NULL, or it is inactive
  with stored status != 3, or it is active (`h.active = 1`) in no maintenance window with
  stored status != 2, or it is active in a maintenance window with stored status != 4. A
  host whose stored status already equals the derived one, and every host with operating
  system 21, gets neither a history row nor an update.
- **source:** `ddl/src/pkgb/mc_osag_maintsync.sql:46-50`

### S-MAINT-005

- **routines:** update_host_maint_status
- **claim:** For every selected host, `update_host_maint_status` inserts one
  `mc.host_maintenance_history` row with `id` from `mc.host_maint_history_seq`, the host
  id, `change_date` = the current timestamp, `new_maintenance_status_id` = the derived
  status, `old_maintenance_status_id` = the stored status with NULL replaced by 1
  (`NVL(..., 1)`), and `ticket_id` = the maintenance ticket (NULL when the host is not in a
  maintenance window) — and then sets `mss.host.maintenance_status_id` to the derived
  status.
- **source:** `ddl/src/pkgb/mc_osag_maintsync.sql:59-61`, `ddl/src/pkgb/mc_osag_maintsync.sql:63`

### S-MAINT-006

- **routines:** update_host_maint_status
- **claim:** Any error raised while `update_host_maint_status` runs (including a failed
  history INSERT) is caught by its `WHEN OTHERS` handler, logged via `plog.err` as
  `'update_host_maint_status(): caught exception: ' || <error message>`, and NOT re-raised:
  the call completes normally. The log text after the fixed prefix is the engine's own
  error message (Oracle `SQLERRM`, PostgreSQL `SQLERRM`) and is therefore not pinned
  beyond the prefix.
- **source:** `ddl/src/pkgb/mc_osag_maintsync.sql:12`, `ddl/src/pkgb/mc_osag_maintsync.sql:67-69`

### S-MAINT-007

- **routines:** update_isp_link_maint_status
- **claim:** The first loop of `update_isp_link_maint_status` considers only ISP links
  attached to at least one `mss.interface` (through `mss.interface2isp_link`, inner-joined
  `hosts` subquery), with `host_active = MAX(h.active)` over all hosts of those interfaces
  (so one active host makes the link "active"), and touches a link only when its stored
  `maintenance_status_id` IS NULL, or equals 1, or the link is inactive with stored status
  != 3, or active in no maintenance window with stored status != 2, or active in a
  maintenance window with stored status != 4. A link whose stored status already equals
  the derived one gets neither a history row nor an update; a link at status 1 is always
  re-derived (its derived status is never 1, S-MAINT-003).
- **source:** `ddl/src/pkgb/mc_osag_maintsync.sql:117-127`

### S-MAINT-008

- **routines:** update_isp_link_maint_status
- **claim:** For every link selected by S-MAINT-007, `update_isp_link_maint_status` logs
  via `plog.notice` the text `'updating status for link ' || <link id> || ': new status is '
  || <derived status> || ': old status is ' || <stored status>` — with Oracle `||`
  semantics, so a NULL stored status renders as nothing after `'old status is '` — then
  inserts one `mc.isp_link_maintenance_history` row (`id` from
  `mc.isp_link_maint_history_seq`, link id, current timestamp, derived status, stored
  status with NULL replaced by 1, maintenance ticket or NULL) and sets
  `mss.isp_link.maintenance_status_id` to the derived status.
- **source:** `ddl/src/pkgb/mc_osag_maintsync.sql:146-148`, `ddl/src/pkgb/mc_osag_maintsync.sql:150-152`, `ddl/src/pkgb/mc_osag_maintsync.sql:154`

### S-MAINT-009

- **routines:** update_isp_link_maint_status
- **claim:** The second loop of `update_isp_link_maint_status` selects every ISP link
  attached to NO interface (`NOT EXISTS` in `mss.interface2isp_link`) whose stored status
  is not 1 or IS NULL, inserts one history row with `new_maintenance_status_id = 1`,
  `old_maintenance_status_id` = stored status with NULL replaced by 1, and NO ticket id
  (the column is not in the INSERT list, so it is NULL), and sets the link's status to 1.
  An unattached link already at status 1 is not touched. The two loops are disjoint
  (attached vs. unattached) and the second runs after the first.
- **source:** `ddl/src/pkgb/mc_osag_maintsync.sql:132-138`, `ddl/src/pkgb/mc_osag_maintsync.sql:159-167`

### S-MAINT-010

- **routines:** update_isp_link_maint_status
- **claim:** Any error raised while `update_isp_link_maint_status` runs is caught by its
  `WHEN OTHERS` handler, logged via `plog.err` as
  `'update_isp_link_maint_status(): caught exception: ' || <error message>` and NOT
  re-raised: the call completes normally.
- **source:** `ddl/src/pkgb/mc_osag_maintsync.sql:80`, `ddl/src/pkgb/mc_osag_maintsync.sql:170-172`

### S-MAINT-011

- **routines:** update_single_host
- **claim:** `update_single_host(p_host_id)` derives the status of exactly the host
  `p_host_id` (operating system other than 21) with the S-MAINT-002/003 rules and, when the
  derived status differs from the stored one or the stored one IS NULL, inserts one
  `mc.host_maintenance_history` row (`id` from `mc.host_maint_history_seq`, `p_host_id`,
  current timestamp, derived status, stored status with NULL replaced by 1, maintenance
  ticket or NULL) and sets `mss.host.maintenance_status_id` to the derived status.
- **source:** `ddl/src/pkgb/mc_osag_maintsync.sql:189-195`, `ddl/src/pkgb/mc_osag_maintsync.sql:216`, `ddl/src/pkgb/mc_osag_maintsync.sql:222-228`

### S-MAINT-012

- **routines:** update_single_host
- **claim:** **CORRECTED BEHAVIOUR.** When the host exists, has an operating system other
  than 21, and its stored status already equals the derived status, `update_single_host`
  does nothing: no history row, no update, no log line, no error. (Oracle: the `SELECT INTO`
  at lines 189-220 copies the batch cursor's "a change is needed" filter into its WHERE
  clause (217-220), so the normal nothing-to-do case returns no row, raises
  `NO_DATA_FOUND`, falls into the `WHEN OTHERS` handler (233-235) and is logged as an
  ERROR `update_single_host(): caught exception: ORA-01403: no data found` — while the
  `IF (v_current_status != v_old_status OR v_old_status IS NULL)` guard at line 222, which
  exists precisely to decide whether a change is needed, can never be false and is dead
  code. The filter in the WHERE clause is the defect; the translation derives the status
  without it and lets the line-222 guard decide.)
- **source:** `ddl/src/pkgb/mc_osag_maintsync.sql:217-220`, `ddl/src/pkgb/mc_osag_maintsync.sql:222`, `ddl/src/pkgb/mc_osag_maintsync.sql:233-235`

### S-MAINT-013

- **routines:** update_single_host
- **claim:** When `p_host_id` names no `mss.host` row, or a host with
  `operating_system_id = 21`, the status `SELECT INTO` finds no row; the resulting
  `NO_DATA_FOUND` has no handler of its own and is caught by the routine's `WHEN OTHERS`,
  which logs `'update_single_host(): caught exception: ' || <error message>` via `plog.err`
  and swallows it: the call completes normally, nothing is written.
- **source:** `ddl/src/pkgb/mc_osag_maintsync.sql:181`, `ddl/src/pkgb/mc_osag_maintsync.sql:216`, `ddl/src/pkgb/mc_osag_maintsync.sql:233-235`

### S-MAINT-014

- **routines:** update_single_isp_link
- **claim:** `update_single_isp_link(p_isp_link_id)` first reads the stored status of the
  link with an unguarded `SELECT INTO`; when `p_isp_link_id` names no `mss.isp_link` row
  the `NO_DATA_FOUND` is caught by the routine's `WHEN OTHERS`, logged via `plog.err` as
  `'update_single_isp_link(): caught exception: ' || <error message>` and swallowed: the
  call completes normally, nothing is written.
- **source:** `ddl/src/pkgb/mc_osag_maintsync.sql:244`, `ddl/src/pkgb/mc_osag_maintsync.sql:251`, `ddl/src/pkgb/mc_osag_maintsync.sql:311-313`

### S-MAINT-015

- **routines:** update_single_isp_link
- **claim:** When the link is attached to NO interface, the status query finds no row and
  the local `NO_DATA_FOUND` handler sets the derived status to 1 (unknown) and the
  maintenance ticket to NULL. Then, if the stored status is not 1 or IS NULL, one
  `mc.isp_link_maintenance_history` row is inserted (`id` from
  `mc.isp_link_maint_history_seq`, `p_isp_link_id`, current timestamp, new status 1, stored
  status with NULL replaced by 1, `ticket_id` NULL) and the link's status is set to 1; an
  unattached link already at status 1 is not touched and nothing is logged.
- **source:** `ddl/src/pkgb/mc_osag_maintsync.sql:296-301`, `ddl/src/pkgb/mc_osag_maintsync.sql:304-308`

### S-MAINT-016

- **routines:** update_single_isp_link
- **claim:** **CORRECTED BEHAVIOUR.** `update_single_isp_link(p_isp_link_id)` derives the
  status of exactly the link `p_isp_link_id` and of no other link: other links' states have
  no influence on what is written for `p_isp_link_id`, and no other link is written.
  (Oracle: the status query's WHERE clause at line 286 — `WHERE l.id = hosts.isp_link_id
  AND l.id = sw.isp_link_id(+) AND (...)` — has NO `l.id = p_isp_link_id` predicate, unlike
  its sibling `update_single_host` (line 216, `WHERE h.id = p_host_id AND ...`), so the
  `SELECT INTO` ranges over every attached link needing a change: with exactly one such
  link anywhere in the database its status is applied to `p_isp_link_id` (lines 304-308),
  with several `TOO_MANY_ROWS` is raised, missed by the `NO_DATA_FOUND` handler and
  logged by `WHEN OTHERS`. The missing predicate is the defect; the UPDATE at line 308
  (`WHERE l.id = p_isp_link_id`) shows the intended target.)
- **source:** `ddl/src/pkgb/mc_osag_maintsync.sql:286`, `ddl/src/pkgb/mc_osag_maintsync.sql:216`, `ddl/src/pkgb/mc_osag_maintsync.sql:308`

### S-MAINT-017

- **routines:** update_single_isp_link
- **claim:** **CORRECTED BEHAVIOUR.** When the link is attached to at least one interface
  and its stored status already equals the derived status (S-MAINT-003), `update_single_isp_link`
  does nothing: no history row, no update, no log line. (Oracle: the status query reuses
  the batch cursor's "a change is needed" filter (288-294), so the nothing-to-do case
  returns no row and the `NO_DATA_FOUND` handler (296-301) — whose own comment says "the
  isp link is not attached to an interface" — sets the derived status to 1; line 304 then
  sees `stored != 1` and writes a history row and status 1 (unknown) for a perfectly
  up-to-date attached link; the next call sees status 1, re-derives 2/3/4 and writes it
  back, so repeated calls flip-flop and write a history row each time. The filter in the
  WHERE clause is the defect; the translation derives the status without it — for an
  attached link the query always returns exactly one row — and lets the line-304 guard
  decide, which is exactly the batch routine's selection logic (S-MAINT-007).)
- **source:** `ddl/src/pkgb/mc_osag_maintsync.sql:288-294`, `ddl/src/pkgb/mc_osag_maintsync.sql:296-301`, `ddl/src/pkgb/mc_osag_maintsync.sql:304`

### S-MAINT-018

- **routines:** update_single_isp_link
- **claim:** **CORRECTED BEHAVIOUR.** An attached link whose stored status IS NULL gets its
  derived status (2, 3 or 4 per S-MAINT-003) with a history row whose old status is 1,
  exactly like the batch routine. (Oracle: line 288 tests `l.maintenance_status_id = NULL`,
  which is never true, where the batch cursor's line 121 tests `IS NULL`; combined with the
  S-MAINT-017 defect an attached NULL-status link was set to 1 instead. With S-MAINT-017's
  correction the comparison disappears from the query altogether.)
- **source:** `ddl/src/pkgb/mc_osag_maintsync.sql:288`, `ddl/src/pkgb/mc_osag_maintsync.sql:121`

### S-MAINT-019

- **routines:** update_single_isp_link
- **claim:** For a link attached to at least one interface whose stored status differs from
  the derived status (or IS NULL), `update_single_isp_link` inserts one
  `mc.isp_link_maintenance_history` row (`id` from `mc.isp_link_maint_history_seq`,
  `p_isp_link_id`, current timestamp, derived status, stored status with NULL replaced by 1,
  maintenance ticket — the highest qualifying ticket id over all hosts of the link's
  interfaces, or NULL) and sets `mss.isp_link.maintenance_status_id` to the derived status.
- **source:** `ddl/src/pkgb/mc_osag_maintsync.sql:254-259`, `ddl/src/pkgb/mc_osag_maintsync.sql:262-285`, `ddl/src/pkgb/mc_osag_maintsync.sql:304-308`

### S-MAINT-020

- **routines:** update_host_maint_status, update_isp_link_maint_status, update_single_host, update_single_isp_link
- **claim:** Each routine's first statement is `plog.AuditUsage(...)` (4 call sites). Per
  XCUT-06 the usage audit is deleted, not ported: the translation contains no AuditUsage
  call and no replacement.
- **source:** `ddl/src/pkgb/mc_osag_maintsync.sql:54`, `ddl/src/pkgb/mc_osag_maintsync.sql:141`, `ddl/src/pkgb/mc_osag_maintsync.sql:187`, `ddl/src/pkgb/mc_osag_maintsync.sql:250`

### S-MAINT-021

- **routines:** update_host_maint_status, update_isp_link_maint_status
- **claim:** The batch cursors lock the rows they will update (`FOR UPDATE OF
  h.maintenance_status_id` / `FOR UPDATE OF l.maintenance_status_id`) for the duration
  of the loop; the translation keeps a row lock on the `mss.host` / `mss.isp_link` rows
  it iterates (`FOR UPDATE OF h` / `FOR UPDATE OF l`).
- **source:** `ddl/src/pkgb/mc_osag_maintsync.sql:51`, `ddl/src/pkgb/mc_osag_maintsync.sql:128`, `ddl/src/pkgb/mc_osag_maintsync.sql:138`

## Checklist

### 1. Empty-string / NULL handling

This package has **no `VARCHAR2`/`CLOB` parameter** at all (the two parameters are
`MSS.HOST.ID%TYPE` / `MSS.ISP_LINK.ID%TYPE`, numeric, `ddl/src/pkg/mc_osag_maintsync.sql:28,33`),
and its only string locals are the four `S_PREFIX CONSTANT VARCHAR2` literals
(`ddl/src/pkgb/mc_osag_maintsync.sql:12,80,181,244`), never NULL. No string takes part in
an `IS NULL` / `=` / `<>` check anywhere (every such check is on numeric status columns).
The `||` sites: (a) the four `plog.err(S_PREFIX||'caught exception: '||sqlerrm)` lines
(69, 172, 235, 313) — `sqlerrm` is never NULL inside a handler; (b) the `plog.notice` at
146-148, where `r_maint_status_changed.maintenance_status_old` CAN be NULL (a link whose
stored status IS NULL is selected by line 121): Oracle renders `'...: old status is '`,
PostgreSQL's `||` would null the whole message. Decision: the translation uses
NULL-tolerant `concat()` at that one site (S-MAINT-008 pins the rendered text for a NULL
old status); plain `||` elsewhere. No boundary `NULLIF` is needed — nothing string-typed
crosses the boundary. `''` is unreachable everywhere in this package.

### 2. SELECT INTO strictness

Three `SELECT ... INTO` sites, matching the Phase 1 inventory's `select_into_sites`
`[189, 251, 254]` exactly:

| # | line | routine | zero rows possible? | >1 row possible? | Oracle handler | translation |
|---|---|---|---|---|---|---|
| 1 | 189-220 | update_single_host | yes: host missing, OS 21 — AND, in Oracle, "nothing to do" (the batch filter at 217-220, the S-MAINT-012 defect) | no (`h.id` PK; `sw` is `GROUP BY host_id`) | none for `NO_DATA_FOUND`; the routine-level `WHEN OTHERS` at 233-235 logs and swallows | `INTO STRICT`; query CORRECTED to drop the 217-220 filter (the IF at 222 decides); the remaining zero-row cases (missing host, OS 21) fall into the same `WHEN OTHERS` log-and-swallow as Oracle (S-MAINT-013) |
| 2 | 251 | update_single_isp_link | yes (link missing) | no (`l.id` PK) | none for `NO_DATA_FOUND`; routine-level `WHEN OTHERS` at 311-313 | `INTO STRICT`, no local handler, caught by the same `WHEN OTHERS` (S-MAINT-014) |
| 3 | 254-294 | update_single_isp_link | yes: link attached to no interface (intended, 296-301) — AND, in Oracle, "nothing to do" (the 288-294 filter, S-MAINT-017 defect) | **yes in Oracle** — the WHERE at 286 lacks `l.id = p_isp_link_id` (S-MAINT-016), so every changed link in the database is a candidate row; `TOO_MANY_ROWS` is not caught by the 296-301 `NO_DATA_FOUND` handler and lands in `WHEN OTHERS` 311-313 | local `WHEN NO_DATA_FOUND THEN v_current_status := 1; v_maint_ticket := NULL` (296-301) | `INTO STRICT` + the same local `NO_DATA_FOUND` handler; query CORRECTED to add `l.id = p_isp_link_id` and drop the 288-294 filter, after which zero rows means exactly "no interface" and >1 row is impossible (`l.id` PK, `hosts`/`sw` grouped by `isp_link_id`) |

Inventory cross-check: `exception_handlers: NO_DATA_FOUND 1, TOO_MANY_ROWS 0, OTHERS 4`
— confirmed by reading the body (297; 68, 171, 234, 312). The two batch routines use
cursor FOR loops (lines 56, 143, 159), not `SELECT INTO`: an empty result is an empty
loop, never an exception. The sequence pulls (`...seq.nextval` at 60, 151, 163, 225, 306)
are expressions inside INSERTs, not `SELECT INTO` sites.

### 3. Exception codes

No `RAISE_APPLICATION_ERROR` call, no named exception declared or raised, no bare `RAISE`
anywhere (full 319-line body read; inventory `raise_application_error: []`). The four
`WHEN OTHERS` handlers (68, 171, 234, 312) all SWALLOW after a `plog.err`; the one
`WHEN NO_DATA_FOUND` (297) swallows into a default value. **No error can leave this
package** — the only externally observable failure signal is the `plog.err` line
(`'<routine>(): caught exception: ' || sqlerrm`). The engine-specific part of that text
differs by construction (Oracle `ORA-01403: no data found` vs PostgreSQL `query returned
no rows`; Oracle `ORA-00001: unique constraint ... violated` vs PostgreSQL `duplicate key
value violates unique constraint ...`): the spec pins the prefix only (S-MAINT-006/010/
013/014). Nothing for XCUT-01 to map. **Transaction-scope delta (XCUT-05, recorded not
asserted):** Oracle's handler leaves the loop iterations committed-so-far in place (only
the failing statement is rolled back); PL/pgSQL's `EXCEPTION` block is a subtransaction,
so a failure in iteration N rolls back iterations 1..N-1 of the same call too. The next
minute's job run redoes them, so the steady state is identical; the per-call outcome is
not. The S-MAINT-006/010 tests provoke the failure on the FIRST iteration, where both
engines agree (nothing written).

### 4. Package state

None. The body's declare section is empty: line 3 (`CREATE OR REPLACE PACKAGE BODY
MC.OSAG_MAINTSYNC IS`) is followed only by blank lines and the `update_host_maint_status`
comment block before `PROCEDURE update_host_maint_status AS` at line 10; the four
`S_PREFIX` constants (12, 80, 181, 244) are routine-local `CONSTANT`s; there is no
trailing initialization block (the file ends `END OSAG_MAINTSYNC;` at line 318). Matches
the inventory's `package_state: []`, `has_init_block: false`.

### 5. FUNCTION vs PROCEDURE

All four routines are `PROCEDURE` (`ddl/src/pkg/mc_osag_maintsync.sql:16,23,28,33`);
`name-map.csv` says `pg_kind=procedure` for all four; the translation creates PostgreSQL
PROCEDUREs (S-MAINT-001). No `COMMIT`, `ROLLBACK` or `PRAGMA AUTONOMOUS_TRANSACTION`
exists in the body (inventory `has_commit: false`, `has_rollback: false`,
`autonomous_transaction: false`; confirmed by grep). The two batch routines are invoked
by Oracle scheduler jobs as anonymous `BEGIN ... END;` blocks every minute
(`ddl/src/jobs/mc_jobs.sql:7,19`) — the job's own transaction commits; in PostgreSQL the
equivalent is a `pg_cron` `CALL`, which is not part of this plan (open question below).

## Assumptions / Unresolved

- **Corrected behaviour is specified, not Oracle's, at S-MAINT-012/016/017/018.** The
  defects are provable from the source alone (a comparison with `= NULL`, a missing
  `p_isp_link_id` predicate next to a sibling that has it, a `NO_DATA_FOUND` handler whose
  comment contradicts the query's filter, a dead `IF`), but whether any client ever calls
  `update_single_isp_link` / `update_single_host` — and so whether anything ever observed
  the Oracle behaviour — cannot be known from this repository: no PL/SQL in `ddl/src/`
  calls either of them (grep over `pkgb/`, `proc/`, `triggers/`); only the two batch jobs
  are referenced. If production clients rely on the flip-flop (unlikely: it writes a
  spurious history row per call), the differential harness (06-05/06-06) will show it.
- **`change_date` precision.** Oracle writes `SYSTIMESTAMP` into a `DATE`-typed
  `change_date`? — the Oracle column type is not in `ddl/src/`; ora2pg produced `timestamp
  without time zone`. The translation writes `statement_timestamp()` (the established
  convention, see `tt/osag_notify.sql`), implicitly truncated to the column's precision.
  Tests assert "recent", not an exact value.
- **`h.active` values other than 0/1.** The CASE treats anything non-zero as active, the
  selection filters test `h.active = 1`; `mss.host.active` is a `NUMBER(1)`-shaped flag
  (`smallint NOT NULL DEFAULT 0` after ora2pg) and no other value is written anywhere in
  `ddl/src/`, so the two tests are assumed equivalent. Not tested.
- **Scheduling.** The Oracle jobs run both batch routines every minute. Whether the
  PostgreSQL side schedules them (via `pg_cron`, see `migration/pgsql/_support/30_pg_cron_jobs.sql`,
  which does not list them today) is a project decision outside this spec.
- **The maintenance-window join is duplicated four times.** The spec treats the four
  copies as one definition (S-MAINT-002) because they are textually identical except for
  the ISP-link path (`mss.interface` → `mss.interface2isp_link`); the translation keeps the
  duplication on instruction (no shared view in this plan).
- **`SQLERRM` text.** Only the fixed prefix of the four log lines is pinned; the engine's
  message differs between Oracle and PostgreSQL by construction (Checklist 3).
