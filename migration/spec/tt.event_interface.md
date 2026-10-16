---
oracle_schema: TT
oracle_package: EVENT_INTERFACE
pg_schema: tt
pg_prefix: event_interface
clause_prefix: EVENT
oracle_spec: ddl/src/pkg/tt_event_interface.sql
oracle_body: ddl/src/pkgb/tt_event_interface.sql
public_routines: 8
---

# TT.EVENT_INTERFACE — PostgreSQL spec

The primary DB-interface for the ticketing system: writes new events, either opening a
new ticket or appending to an existing open one, runs the per-event-type escalation
actions configured in `tt.event_action` (including the corpus's only genuine dynamic-SQL
site), records history events, and demotes/promotes events. Per its header comment
(`ddl/src/pkg/tt_event_interface.sql:5-8`) it "enables writing a new event to the db or
adding events to existing tickets." This is the pilot's `static_resolution: incomplete`
package — the phase's named research risk — and is **mutually recursive with
`TT.TICKET_INTERFACE`** (`migration/analyze/known_cycles.json`'s
`TT.EVENT_INTERFACE|TT.OSAG_NOTIFY|TT.TICKET_INTERFACE|TT.UTIL` cycle group). See
`## Assumptions / Unresolved` for the honest treatment of both facts, and
`migration/spec/DYNAMIC-SQL-TRACE.md` for the full hand-trace of the `EXECUTE IMMEDIATE`
at `ddl/src/pkgb/tt_event_interface.sql:971`, which this spec consumes rather than
re-derives.

## Routines

### newevent_new (PUBLIC)

- **Oracle signature:** `PROCEDURE newevent_new(p_event_id OUT NUMBER, p_type_id NUMBER, p_host_id NUMBER, p_details_public VARCHAR2, p_details_private VARCHAR2 DEFAULT NULL, p_contact_id NUMBER DEFAULT NULL, p_public_event BOOLEAN DEFAULT TRUE, p_eventdate DATE DEFAULT sysdate, p_ticket_type_id NUMBER DEFAULT NULL, p_service_component_id NUMBER DEFAULT NULL, p_zitadel_contact_id NUMBER DEFAULT NULL, p_company_id NUMBER DEFAULT NULL)`
- **PostgreSQL name:** `tt.event_interface_newevent_new` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/tt_event_interface.sql:34`
- **Defined:** `ddl/src/pkgb/tt_event_interface.sql:20-507`
- Adds a brand-new event: drops it if the host is inactive or an open service window
  disables events; searches open tickets of the same host for one to append to instead of
  opening a new one (a long automatic-event heuristic); if none is found, opens a new
  ticket, inserts the event, optionally records a history event, runs
  `exec_event_type_actions`, and — unless the ticket is a monitoring-outage ticket
  (type 6) — sends notifications via `TT.OSAG_NOTIFY.event_notify`. **No procedure-level
  `EXCEPTION` block at all** — only two small inline `BEGIN...EXCEPTION` blocks exist
  inside its body (S-EVENT-001, S-EVENT-006/007/008); anything else raised propagates
  fully unhandled to `newevent_new`'s own caller.

### addevent_new (PUBLIC)

- **Oracle signature:** `PROCEDURE addevent_new(p_event_id OUT NUMBER, p_ticket_id NUMBER, p_type_id NUMBER, p_host_id NUMBER, details_public VARCHAR2, details_private VARCHAR2 DEFAULT NULL, p_contact_id NUMBER DEFAULT NULL, public_event BOOLEAN DEFAULT TRUE, eventdate DATE DEFAULT sysdate, notify_event BOOLEAN DEFAULT FALSE, p_zitadel_contact_id NUMBER DEFAULT NULL, p_peer_contact_id NUMBER DEFAULT NULL)`
- **PostgreSQL name:** `tt.event_interface_addevent_new` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/tt_event_interface.sql:54`
- **Defined:** `ddl/src/pkgb/tt_event_interface.sql:519-828`
- Adds an event to an EXISTING ticket: if the ticket is merged, recurses onto the merge
  target; if closed/deleted (status > 101), raises a named "ticket closed" exception; else
  inserts the event, may promote the ticket to "hot", runs `exec_event_type_actions`, may
  reclassify the ticket type, may notify, may recompute `status_valid_until_date` via
  `TT.UTIL`, and recomputes several ticket rollup counters. **Has its own top-level
  `EXCEPTION` block** (S-EVENT-021, S-EVENT-032) that re-raises the named "ticket closed"
  exception but swallows (logs) every other error — the package's one asymmetric handler.

### moveevent (PUBLIC)

- **Oracle signature:** `PROCEDURE moveevent(p_event_id NUMBER, p_oldticket_id NUMBER, p_newticket_id NUMBER)`
- **PostgreSQL name:** `tt.event_interface_moveevent` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/tt_event_interface.sql:74`
- **Defined:** `ddl/src/pkgb/tt_event_interface.sql:868-889`
- Moves ONE event between tickets. **The routine's own header comment
  (`ddl/src/pkgb/tt_event_interface.sql:866`) says: "FIXME / BROKEN the p_event_id is not
  actually used! This moves ALL events of a ticket. Looks like this code is never run."**
  — the Oracle body's `UPDATE tt.event e SET ticket_id = p_newticket_id WHERE ticket_id =
  p_oldticket_id` (line 880) filters on the OLD ticket only, never on `p_event_id`.
  **CORRECTED on branch `phoenix/migrate_tt_only`** (project-owner instruction: "Don't
  mimic broken behaviour of oracle routines, but annotate/explain what changed with the
  correction"): the PostgreSQL translation restricts the `UPDATE` to `id = p_event_id AND
  ticket_id = p_oldticket_id`, honouring the package spec's own contract
  (`ddl/src/pkg/tt_event_interface.sql:67-73`: "moves an event from one ticket to
  another. If the event does not belong to the old ticket or the event is already attached
  to the new ticket then nothing happens. However if the event does not exist, or the new
  ticket does not exist a warning is written to the log"). S-EVENT-033 keeps the
  swallow/log semantics of the nonexistent-new-ticket path unchanged; S-EVENT-046 and
  S-EVENT-047 state the corrected move semantics. Before this amendment the spec
  documented the bug faithfully and the translation reproduced it as-is.

### ticket_type_for_event_type (PUBLIC, FUNCTION)

- **Oracle signature:** `FUNCTION ticket_type_for_event_type(p_event_type_id NUMBER) RETURN NUMBER`
- **PostgreSQL name:** `tt.event_interface_ticket_type_for_event_type` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/tt_event_interface.sql:80`
- **Defined:** `ddl/src/pkgb/tt_event_interface.sql:833-861`
- Maps an event type id to a ticket type id via a fixed `IF`/`ELSIF` table (no database
  access at all). The package's only `FUNCTION` (S-EVENT-034).

### exec_event_type_actions (PUBLIC)

- **Oracle signature:** `PROCEDURE exec_event_type_actions(p_event_id NUMBER)`
- **PostgreSQL name:** `tt.event_interface_exec_event_type_actions` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/tt_event_interface.sql:97`
- **Defined:** `ddl/src/pkgb/tt_event_interface.sql:894-986`
- Loops over `event_action`/`event_type_action` rows matching the event's type, and for
  each, either dispatches escalation-suppressed logging (S-EVENT-039), or resolves a
  procedure name (DBPROP lookup or table column) and dynamically `CALL`s it — **the
  package's one `static_resolution: incomplete` site** (S-EVENT-038, `line 971`). **No
  procedure-level `EXCEPTION` block**; two small inline blocks exist (S-EVENT-036 and the
  dynamic-SQL site's own local `WHEN OTHERS`).

### add_history_event (PUBLIC)

- **Oracle signature:** `PROCEDURE add_history_event(p_event_id OUT NUMBER, p_ticket_id NUMBER, p_event_type_id NUMBER, p_host_id NUMBER, p_company_id NUMBER, p_details_public VARCHAR2, p_details_private VARCHAR2 DEFAULT NULL, p_public_event BOOLEAN DEFAULT TRUE, p_eventdate DATE DEFAULT sysdate, p_contact_id NUMBER DEFAULT NULL, p_zitadel_contact_id NUMBER DEFAULT NULL)`
- **PostgreSQL name:** `tt.event_interface_add_history_event` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/tt_event_interface.sql:121`
- **Defined:** `ddl/src/pkgb/tt_event_interface.sql:1055-1101`
- Creates a plain history event row and unconditionally calls
  `TT.OSAG_NOTIFY.event_notify`. **No `EXCEPTION` block of any kind** — any failure
  (sequence, INSERT, or the notify call) propagates fully unhandled (S-EVENT-042).

### demote_event (PUBLIC)

- **Oracle signature:** `PROCEDURE demote_event(p_event_id NUMBER, p_contact_id NUMBER)`
- **PostgreSQL name:** `tt.event_interface_demote_event` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/tt_event_interface.sql:142`
- **Defined:** `ddl/src/pkgb/tt_event_interface.sql:1106-1135`
- Marks an event `demoted = 1` and looks up its ticket/host/company (unused today — the
  history-event write is commented out, per the routine's own inline note). **No
  `EXCEPTION` block** — a bad `p_event_id` propagates `NO_DATA_FOUND` fully unhandled
  (S-EVENT-043).

### promote_event (PUBLIC)

- **Oracle signature:** `PROCEDURE promote_event(p_event_id NUMBER, p_contact_id NUMBER)`
- **PostgreSQL name:** `tt.event_interface_promote_event` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/tt_event_interface.sql:152`
- **Defined:** `ddl/src/pkgb/tt_event_interface.sql:1140-1169`
- Mirror of `demote_event` (`demoted = 0`); same unhandled-lookup shape (S-EVENT-044).

## Private routine — naming convention

**1 private routine**, matching the Phase 1 inventory exactly: `is_esc_supp_active`
(forward-declared `ddl/src/pkgb/tt_event_interface.sql:15`, defined
`ddl/src/pkgb/tt_event_interface.sql:988-1050`). Per plan 02-05's convention (reused here,
not reinvented — see `migration/spec/tt.osag_notify.md`, "Private routines — naming
convention"): **`tt.event_interface__is_esc_supp_active`** (schema-level function, `__`
double-underscore marker prefix, `REVOKE ALL ... FROM PUBLIC`). Same standing caveat: this
convention lives outside `migration/mapping/name-map.csv` and is not finalized by this
spec — flagged again in this plan's SUMMARY.

## Clauses

### S-EVENT-001

- **routines:** newevent_new
- **claim:** SELECT INTO site #1 (inventory line 79): `SELECT h.service_company_id,
  h2s.service_id INTO v_company_id, v_mss_service_id FROM mss.host h, mss.host2service h2s
  WHERE h.id = p_host_id AND h.id = h2s.host_id`. Zero rows is reachable (a host with no
  `host2service` row) and is caught locally: `EXCEPTION WHEN NO_DATA_FOUND THEN
  plog.warning(...)` (lines 84-85). **`TOO_MANY_ROWS` is ALSO structurally reachable
  here** — `mss.host2service`'s primary key is `(HOST_ID, SERVICE_ID)`
  (`ddl/generated/schema.oracle.sql:81`), not unique on `HOST_ID` alone, so a host mapped
  to more than one service returns more than one row from this join. Because the local
  handler only names `WHEN NO_DATA_FOUND`, a `TOO_MANY_ROWS` here falls to
  `WHEN OTHERS THEN RAISE` (lines 86-87) — which **RE-RAISES it**. `newevent_new` has NO
  procedure-level `EXCEPTION` block of its own, so a re-raised `TOO_MANY_ROWS` from this
  site propagates fully unhandled straight out of `newevent_new` to whatever called it.
  This is a genuine, previously-undocumented multi-row hazard (same table and cardinality
  fact as `migration/spec/tt.osag_notify.md`'s S-NOTIFY-003), not merely theoretical.
- **source:** `ddl/src/pkgb/tt_event_interface.sql:77-88`

### S-EVENT-002

- **routines:** newevent_new
- **claim:** SELECT INTO site #2 (inventory line 94): `SELECT company_id INTO v_company_id
  FROM stop.contact WHERE contact.id = p_contact_id`, reached only when
  `p_contact_id IS NOT NULL AND v_company_id IS NULL`. `stop.contact.id` is `CONTACT_PK`
  (`ddl/generated/schema.oracle.sql:71`) so `TOO_MANY_ROWS` is structurally impossible;
  zero rows is reachable for a bad `p_contact_id`. No handler anywhere in `newevent_new` —
  propagates fully unhandled.
- **source:** `ddl/src/pkgb/tt_event_interface.sql:93-97`

### S-EVENT-003

- **routines:** newevent_new
- **claim:** SELECT INTO site #3 (inventory line 104): `SELECT h.active INTO active FROM
  mss.host h WHERE h.id = p_host_id`. `HOST_PK` — `TOO_MANY_ROWS` impossible; zero rows
  reachable for a bad `p_host_id`, no handler, propagates fully unhandled. If found and
  `active = 0`, `newevent_new` logs and `RETURN`s immediately — a normal early exit
  (dropping the event for an inactive host), not an exception path.
- **source:** `ddl/src/pkgb/tt_event_interface.sql:103-109`

### S-EVENT-004

- **routines:** newevent_new
- **claim:** SELECT INTO site #4 (inventory line 118), `SELECT COUNT(*) INTO
  v_disable_event_ticket_id FROM ...` (an open service window with `disable_events` set
  for this host) — a `COUNT` aggregate, always exactly one row, no `STRICT` concern of any
  kind. If the count is `> 0`, `newevent_new` logs and `RETURN`s immediately — the event is
  deliberately dropped, a normal early exit.
- **source:** `ddl/src/pkgb/tt_event_interface.sql:116-139`

### S-EVENT-005

- **routines:** newevent_new
- **claim:** SELECT INTO site #5 (inventory line 157): `SELECT source INTO v_new_source
  FROM event_type WHERE id = p_type_id`. `EVENTTYPE_PK` — `TOO_MANY_ROWS` impossible; zero
  rows reachable for a bad `p_type_id`. This site sits BETWEEN the two inline
  `BEGIN...EXCEPTION` blocks (the first ends at line 88, the ticket-search block starts at
  line 162) — no handler covers it at all; propagates fully unhandled. Immediately
  followed by a call to `ticket_type_for_event_type` (S-EVENT-034) to resolve
  `v_ticket_type_id`.
- **source:** `ddl/src/pkgb/tt_event_interface.sql:157-159`

### S-EVENT-006

- **routines:** newevent_new
- **claim:** SELECT INTO site #6 (inventory line 165), `SELECT MIN(t.id) INTO
  v_monitoring_ticket_id FROM tt.ticket t WHERE t.company_id = v_company_id AND
  t.type_id = 6 AND t.status_id < 60` — a `MIN` aggregate (always exactly one row, `NULL`
  on no match), no `STRICT` concern. Lexically inside the ticket-search `BEGIN` block
  whose own `WHEN OTHERS` (S-EVENT-007) covers everything in this branch, though an
  aggregate cannot itself raise `NO_DATA_FOUND`/`TOO_MANY_ROWS`. If a monitoring ticket is
  found, the event is appended to it and `v_ticket_type_id` is forced to `6` (preventing
  custom event-type actions later, per the inline comment).
- **source:** `ddl/src/pkgb/tt_event_interface.sql:163-173`

### S-EVENT-007

- **routines:** newevent_new
- **claim:** SELECT INTO site #7 (inventory line 176), `SELECT MAX(t.id) INTO
  v_collect_event_ticket_id FROM ...` (open service window requesting event collection
  for this host) — `MAX` aggregate, no `STRICT` concern. **The entire ticket-search block
  (`ddl/src/pkgb/tt_event_interface.sql:162-294`) is wrapped in one
  `EXCEPTION WHEN OTHERS THEN plog.err(...)`** (lines 295-297) that logs and swallows —
  any exception raised anywhere in this block that is not caught by a more local handler
  (S-EVENT-008's inline `NO_DATA_FOUND`) ends here, not propagated further.
- **source:** `ddl/src/pkgb/tt_event_interface.sql:176-190, 295-298`

### S-EVENT-008

- **routines:** newevent_new
- **claim:** SELECT INTO site #8 (inventory line 203), inside a `WHILE` loop over
  `tt.ticket_interface.get_next_recent_ticket(...)` results: `SELECT t.type_id,
  t.open_date, e.type_id, ety.source INTO v_recent_ticket_type, ... FROM tt.ticket t,
  tt.event e, tt.event_type ety WHERE t.id = v_recent_ticket_id AND e.ticket_id = t.id AND
  e.type_id = ety.id AND e.id = (SELECT MIN(id) FROM tt.event WHERE ticket_id = t.id)`.
  Zero rows is reachable at the structural edge (`t.id` is `TICKET_PK`, so if the
  recent-ticket id resolves to no row, or its minimum-id event doesn't join cleanly);
  `TOO_MANY_ROWS` is structurally impossible (`TICKET_PK`, the `MIN(id)` subquery pins a
  single event, `EVENTTYPE_PK`). **Has its own local
  `EXCEPTION WHEN NO_DATA_FOUND THEN NULL`** (lines 280-282) — the loop simply continues
  to the next candidate ticket (line 288) rather than treating a miss as fatal.
- **source:** `ddl/src/pkgb/tt_event_interface.sql:198-211, 280-291`

### S-EVENT-009

- **routines:** newevent_new
- **claim:** The recent-ticket search loop's driver,
  `tt.ticket_interface.get_next_recent_ticket(...)` (lines 199, 288), is a call INTO
  `TT.TICKET_INTERFACE` — one of the twelve call sites this package makes into its cycle
  partner (`migration/analyze/depgraph.json`'s edge `TT.EVENT_INTERFACE -> 
  TT.TICKET_INTERFACE`, call sites `[199, 222, 288, 326, 419, 496, 620, 621, 676, 707, 720,
  737]`). See S-EVENT-045 for the cycle group's translation-order consequence.
- **source:** `ddl/src/pkgb/tt_event_interface.sql:199, 288`

### S-EVENT-010

- **routines:** newevent_new
- **claim:** SELECT INTO site #9 (inventory line 344), reached only in the "create a new
  ticket" branch (no existing ticket found): `SELECT name INTO subject FROM event_type
  WHERE id=p_type_id`. `EVENTTYPE_PK` — `TOO_MANY_ROWS` impossible; zero rows reachable for
  a bad `p_type_id`. This site is textually AFTER the ticket-search `BEGIN...EXCEPTION`
  block has already closed (line 298) — no handler of any kind covers it; propagates fully
  unhandled.
- **source:** `ddl/src/pkgb/tt_event_interface.sql:333-346`

### S-EVENT-011

- **routines:** newevent_new
- **claim:** SELECT INTO site #10 (inventory line 377), `SELECT ticket_sequence.NextVal
  INTO v_ticket_id FROM DUAL` — a sequence pull via `DUAL`, always exactly one row, no
  `STRICT` concern. The Oracle `sequence.NextVal FROM DUAL` idiom has no direct PostgreSQL
  syntax (`nextval('tt.ticket_sequence')` or equivalent, per whatever Phase 3/4 decides for
  sequence naming — a corpus-wide mechanic, not specific to this package).
- **source:** `ddl/src/pkgb/tt_event_interface.sql:377`

### S-EVENT-012

- **routines:** newevent_new
- **claim:** SELECT INTO site #11 (inventory line 384), reached when `v_mss_service_id IS
  NULL`: `SELECT count(*) INTO v_count FROM auth.permission p, auth.login l WHERE
  p.login_id = l.id AND l.contact_id = p_contact_id AND p.role_id = 2 AND p.company_id =
  v_company_id` — a `COUNT` aggregate, no `STRICT` concern regardless of `auth.permission`
  being a materialized view over several underlying role mappings
  (`ddl/migrated/mviews/auth.sql:108-140`) whose own row cardinality this spec does not
  need to resolve, precisely because the query is an aggregate.
- **source:** `ddl/src/pkgb/tt_event_interface.sql:383-386`

### S-EVENT-013

- **routines:** newevent_new
- **claim:** SELECT INTO site #12 (inventory line 389), the parallel branch when
  `v_mss_service_id IS NOT NULL`: `SELECT count(*) INTO v_count FROM
  auth.mv_service_access sa, auth.login l WHERE ...` — `COUNT` aggregate, no `STRICT`
  concern, same reasoning as S-EVENT-012. `v_count > 0` (either branch) determines whether
  the new ticket gets `p_contact_id` as its confirmed owner (lines 403-413).
- **source:** `ddl/src/pkgb/tt_event_interface.sql:388-391`

### S-EVENT-014

- **routines:** newevent_new
- **claim:** SELECT INTO site #13 (inventory line 423), `SELECT event_sequence.NextVal
  INTO p_event_id FROM DUAL` — sequence pull, no `STRICT` concern, same corpus-wide
  mechanic as S-EVENT-011. The subsequent `INSERT INTO event` (lines 452-464) and the two
  conditional ticket-rollup `UPDATE`s (lines 467-478) are ordinary DML with no
  `SELECT INTO` risk. If the event type source is not automatic (`!= 1`),
  `add_history_event` (S-EVENT-042) is called; `exec_event_type_actions` (S-EVENT-035
  onward) always runs; and unless the ticket type is `6` (monitoring outage),
  `TT.OSAG_NOTIFY.event_notify` is called (line 504) — the notification call this spec's
  sibling `tt.osag_notify.md` documents as fully swallowing on the receiving end
  (S-NOTIFY-001).
- **source:** `ddl/src/pkgb/tt_event_interface.sql:422-505`

### S-EVENT-015

- **routines:** newevent_new, addevent_new
- **claim:** **A Pitfall-2 (`''`/`NULL` collapsing) hazard shared by both procedures.**
  `v_scope_info VARCHAR2(30000)` is declared with NO default (`newevent_new`:
  `ddl/src/pkgb/tt_event_interface.sql:50`; `addevent_new`:
  `ddl/src/pkgb/tt_event_interface.sql:555`), so it starts SQL `NULL` on every call. Inside
  the alerting-log block (reached only for a fixed set of event types, e.g. hardware/
  application/system notification/failure), it is built via
  `v_scope_info := v_scope_info || ' company_id=' || v_company_id;` then optionally
  `v_scope_info := v_scope_info || ' host_id=' || p_host_id;`
  (`newevent_new`: lines 442-447; `addevent_new`: lines 658-663). **In Oracle,
  `NULL || 'x' = 'x'`**, so the accumulator seeds correctly from nothing on its first
  concatenation. **In PL/pgSQL, `NULL || 'x' = NULL`** — a literal port leaves
  `v_scope_info` permanently `NULL`, silently dropping the `company_id=`/`host_id=` suffix
  from the `plog.notice(...)` alerting-log line (lines 448, 664) even though the log call
  itself still fires. This is a log-content-only divergence (no data-table effect), but it
  is real and reachable — the translation must seed `v_scope_info := ''` at declaration (or
  `COALESCE`-normalize at each `||`), not port the bare concatenation.
- **source:** `ddl/src/pkgb/tt_event_interface.sql:50, 442-448, 555, 658-664`

### S-EVENT-016

- **routines:** addevent_new
- **claim:** SELECT INTO site #14 (inventory line 561): `SELECT t.type_id, t.status_id
  INTO v_ticket_type, v_ticket_status FROM tt.ticket t WHERE t.id = p_ticket_id`.
  `TICKET_PK` — `TOO_MANY_ROWS` impossible; zero rows reachable for a bad `p_ticket_id`. No
  local handler; escalates to `addevent_new`'s own outer `EXCEPTION` block
  (S-EVENT-032), which for a generic `NO_DATA_FOUND` logs via `plog.err`/`plog.notice` and
  swallows (does not re-raise — only the named `ticket_closed` exception, S-EVENT-021, is
  re-raised).
- **source:** `ddl/src/pkgb/tt_event_interface.sql:560-564`

### S-EVENT-017

- **routines:** addevent_new
- **claim:** SELECT INTO site #15 (inventory line 566): `SELECT source INTO
  v_event_source FROM tt.event_type WHERE id = p_type_id`. `EVENTTYPE_PK` — `TOO_MANY_ROWS`
  impossible; zero rows reachable for a bad `p_type_id`; no local handler, escalates to
  `addevent_new`'s outer swallow (S-EVENT-032), same shape as S-EVENT-016.
- **source:** `ddl/src/pkgb/tt_event_interface.sql:566`

### S-EVENT-018

- **routines:** addevent_new
- **claim:** SELECT INTO site #16 (inventory line 567): `SELECT autopin INTO v_pinned
  FROM tt.event_type WHERE id = p_type_id`. Same shape as S-EVENT-017 (`EVENTTYPE_PK`, no
  local handler, escalates to the outer swallow).
- **source:** `ddl/src/pkgb/tt_event_interface.sql:567`

### S-EVENT-019

- **routines:** addevent_new
- **claim:** SELECT INTO site #17 (inventory line 580), reached only when the ticket is
  merged (`v_ticket_status = 110`): `SELECT TO_NUMBER(e.details_private) INTO
  v_merged_ticket_id FROM tt.event e WHERE e.ticket_id = p_ticket_id AND e.type_id = 100004
  AND TO_NUMBER(e.details_private) != p_ticket_id AND EXISTS (SELECT 1 FROM tt.ticket t
  WHERE t.id = TO_NUMBER(e.details_private)) AND ROWNUM=1`. Zero rows is reachable
  (no matching merge event) and is caught locally:
  `EXCEPTION WHEN NO_DATA_FOUND THEN v_merged_ticket_id := -1` (lines 587-589).
  **`TOO_MANY_ROWS` is structurally impossible here ONLY because of the trailing
  `ROWNUM=1` predicate** — Oracle evaluates `ROWNUM` as it builds the row source, so the
  query is capped at one candidate row before `SELECT INTO` ever has a chance to see more
  than one. This is a **translation hazard, not a simplification**: `ROWNUM` has no
  PostgreSQL equivalent (it is not a real pseudo-column outside Oracle-compatibility
  layers); the predicate must become a trailing `LIMIT 1` on the query, not merely be
  dropped — with `LIMIT 1` in place, PL/pgSQL's own `STRICT` can likewise never see more
  than one row, correctly mirroring Oracle's guarantee. Dropping `ROWNUM=1` without adding
  `LIMIT 1` would let a translation's own `STRICT` raise `TOO_MANY_ROWS` in a case Oracle
  structurally could not — a corpus-wide mechanic worth naming explicitly since this is its
  first appearance in the pilot.
- **source:** `ddl/src/pkgb/tt_event_interface.sql:579-590`

### S-EVENT-020

- **routines:** addevent_new
- **claim:** If a merge target is found (`v_merged_ticket_id > 0`), `addevent_new` recurses
  onto the target ticket, then attributes the newly-created event back to the ORIGINAL
  (merged-from) ticket via `UPDATE tt.event SET org_ticket_id = p_ticket_id WHERE id =
  p_event_id and org_ticket_id IS NULL` — an ordinary `UPDATE`, no `SELECT INTO` risk.
- **source:** `ddl/src/pkgb/tt_event_interface.sql:592-607`

### S-EVENT-021

- **routines:** addevent_new
- **claim:** **The package's one intentionally re-raised (never swallowed) exception.**
  If the ticket's status is closed/deleted/archived (`v_ticket_status > 101`),
  `addevent_new` logs a notice and calls
  `RAISE_APPLICATION_ERROR(EVENT_INTERFACE_STATE.S_ERRNO_TICKET_CLOSED, 'Ticket with id '||
  p_ticket_id || ' is closed/deleted')` (line 611) — a call through a NAMED CONSTANT
  (`EVENT_INTERFACE_STATE.S_ERRNO_TICKET_CLOSED`, resolving to Oracle error code `-20980`,
  declared `ddl/src/pkg/tt_event_interface_state.sql:8`), which is why Phase 1's
  `raise_application_error[]` regex (numeric-literal-only) does NOT list it in
  `inventory.json` — traced by hand here per `CHECKLIST.md`'s own documented blind spot.
  `addevent_new`'s own outer handler explicitly re-raises this one exception,
  `WHEN EVENT_INTERFACE_STATE.ticket_closed THEN RAISE` (lines 823-824), BEFORE its generic
  `WHEN OTHERS` (S-EVENT-032) — this is the ONLY exception this entire package propagates
  to a caller on purpose, everything else this routine's outer handler catches is logged
  and swallowed. Translation must map Oracle error `-20980` to a PostgreSQL condition (a
  custom SQLSTATE via `RAISE EXCEPTION ... USING ERRCODE = ...`, or a dedicated PL/pgSQL
  exception) that survives being re-raised through the `CALL` chain — the exact mapping
  mechanism is Phase 3's XCUT-01, recorded here as an input, not settled.
- **source:** `ddl/src/pkgb/tt_event_interface.sql:609-611, 822-824`, `ddl/src/pkg/tt_event_interface_state.sql:7-9`

### S-EVENT-022

- **routines:** addevent_new
- **claim:** SELECT INTO site #18 (inventory line 615), reached in the "not merged, not
  closed" (normal) branch: `SELECT event_sequence.NextVal INTO ev_id FROM DUAL` —
  sequence pull, no `STRICT` concern, same mechanic as S-EVENT-011. `p_event_id := ev_id`
  fills the `OUT` parameter. The subsequent placeholder substitution
  (`tt.ticket_interface.replace_id_placeholders(...)`, lines 620-621) is delegated entirely
  to `TT.TICKET_INTERFACE` — its own internal `SELECT INTO`/exception behavior is out of
  scope for this package's spec (see S-EVENT-045/Assumptions).
- **source:** `ddl/src/pkgb/tt_event_interface.sql:615-621`

### S-EVENT-023

- **routines:** addevent_new
- **claim:** SELECT INTO sites #19 and #20 (inventory lines 631, 636), an `IF`/`ELSE` pair
  resolving `v_company_id`: `SELECT h.service_company_id INTO v_company_id FROM mss.host h
  WHERE h.id = p_host_id` (line 630-633, when `p_host_id IS NOT NULL`) or
  `SELECT company_id INTO v_company_id FROM tt.ticket WHERE ticket.id = p_ticket_id`
  (line 634-638, the `ELSE` branch). Both are single-row PK lookups (`HOST_PK`,
  `TICKET_PK`) — `TOO_MANY_ROWS` structurally impossible at either; zero rows is reachable
  at the `mss.host` branch for a bad `p_host_id`, and structurally near-impossible (but not
  forbidden) at the `tt.ticket` branch since `p_ticket_id` was already validated to exist
  at S-EVENT-016 earlier in this same call. Neither has a local handler; both escalate to
  `addevent_new`'s outer swallow (S-EVENT-032).
- **source:** `ddl/src/pkgb/tt_event_interface.sql:630-639`

### S-EVENT-024

- **routines:** addevent_new
- **claim:** SELECT INTO site #21 (inventory line 674), reached only for a public MC event
  (`public_event AND p_type_id BETWEEN 40000 AND 60000`): `SELECT from_tz(cast(eventdate as
  timestamp), 'EUROPE/ZURICH') INTO v_ux_timeout_start FROM tt.event WHERE id = ev_id`.
  `EVENT_PK` — `TOO_MANY_ROWS` impossible; zero rows is structurally near-impossible (the
  row was inserted moments earlier in the SAME transaction, at line 667-670, and is
  therefore visible to this session) but is recorded here rather than silently assumed
  safe, per this checklist's own discipline. No local handler; escalates to the outer
  swallow.
- **source:** `ddl/src/pkgb/tt_event_interface.sql:672-677`

### S-EVENT-025

- **routines:** addevent_new
- **claim:** For a fixed set of event types (10002, 10003, 10008, 10013, 10014, 10040,
  10050, 10060, 10100, and several `300xx` customer/portal event types),
  `addevent_new` promotes the ticket to "hot" (status 3) via
  `tt.ticket_interface.change_status(...)` unless it is already hot — an ordinary
  cross-package call, no local `SELECT INTO` risk here. `exec_event_type_actions(p_event_id)`
  (line 711) then always runs, triggering escalations if configured — see S-EVENT-035
  onward for that callee's own strictness sites and their caller-dependent propagation
  (this call site is inside `addevent_new`'s own outer `BEGIN...EXCEPTION`, so anything
  unhandled inside `exec_event_type_actions` reached via THIS call site is swallowed here).
- **source:** `ddl/src/pkgb/tt_event_interface.sql:683-711`

### S-EVENT-026

- **routines:** addevent_new
- **claim:** SELECT INTO site #22 (inventory line 718), reached only when the ticket type
  is 4 (ISP outage) or 5 (customer information): `SELECT source INTO v_event_source FROM
  event_type WHERE id = p_type_id` — a RE-lookup of the same `p_type_id` already resolved
  at S-EVENT-017. `EVENTTYPE_PK` — `TOO_MANY_ROWS` impossible; zero rows is structurally
  near-impossible (same id, same transaction) but recorded, not assumed. No local handler;
  escalates to the outer swallow. If the source is `3`/`4`/`5` (customer/OSAG-originated)
  and the event is public, the ticket type is changed to `1` (trouble ticket) via
  `TT.TICKET_INTERFACE.change_type`.
- **source:** `ddl/src/pkgb/tt_event_interface.sql:717-722`

### S-EVENT-027

- **routines:** addevent_new
- **claim:** SELECT INTO site #23 (inventory line 729), reached for a connection-down
  event (`p_type_id = 10001`) on a ticket type not already in `(1,4,6)`:
  `SELECT COUNT(*) INTO v_ticket_has_service_window FROM tt.service_window s, tt.ticket t
  WHERE ...` — a `COUNT` aggregate, no `STRICT` concern. If zero (no active service
  window), the ticket type is changed to `1` (incident); otherwise a notice is logged and
  the type is left alone.
- **source:** `ddl/src/pkgb/tt_event_interface.sql:728-741`

### S-EVENT-028

- **routines:** addevent_new
- **claim:** For a non-monitoring-outage ticket (`v_ticket_type != 6`) with
  `notify_event = TRUE`, `addevent_new` calls `TT.OSAG_NOTIFY.event_notify(ev_id,
  p_ticket_id)` (line 747) — the same fully-swallowing notification callee documented in
  `migration/spec/tt.osag_notify.md` (S-NOTIFY-001). No local `SELECT INTO` risk at this
  call site itself.
- **source:** `ddl/src/pkgb/tt_event_interface.sql:744-749`

### S-EVENT-029

- **routines:** addevent_new
- **claim:** For a fixed set of publicly-visible event types (30001, 30008, 30009, 40002,
  50001, 50002, 50003) on a public event, `addevent_new` calls
  `tt.util.update_status_valid_until(p_ticket_id)` (line 761) — one of exactly TWO current
  call sites into `TT.UTIL` in the whole corpus, per `migration/spec/tt.util.md`'s
  S-UTIL-015 (the other being `TT.TICKET_INTERFACE.change_status_event_id_out`). That spec
  already confirms both current callers are declared `PROCEDURE` (as is `addevent_new`
  itself, `ddl/src/pkg/tt_event_interface.sql:54`), so no FUNCTION/PROCEDURE-COMMIT
  collision currently exists for this call — but `update_status_valid_until` ITSELF has
  zero exception handlers (`tt.util.md` S-UTIL-003), so any `NO_DATA_FOUND` it raises (a
  nonexistent `p_ticket_id` — structurally near-impossible here since the ticket was
  already validated at S-EVENT-016) propagates OUT of `TT.UTIL` and is then caught by
  `addevent_new`'s own outer swallow (S-EVENT-032), same as every other unhandled site in
  this routine.
- **source:** `ddl/src/pkgb/tt_event_interface.sql:760-762`

### S-EVENT-030

- **routines:** addevent_new
- **claim:** SELECT INTO site #24 (inventory line 765): `SELECT t.fast_resolvable,
  t.last_public_event_id, t.recoverable_status_id, t.summary_relevant_events_count,
  t.todo_relevant_events_count INTO ... FROM tt.ticket t WHERE t.id = p_ticket_id` — a
  RE-query of the same ticket resolved at S-EVENT-016 (the routine's own comment notes
  "don't move this up, the attributes might change until here"). `TICKET_PK` —
  `TOO_MANY_ROWS` impossible; zero rows structurally near-impossible (same ticket, same
  transaction) but recorded. No local handler; escalates to the outer swallow.
- **source:** `ddl/src/pkgb/tt_event_interface.sql:764-768`

### S-EVENT-031

- **routines:** addevent_new
- **claim:** SELECT INTO site #25 (inventory line 806): `SELECT COUNT(*) INTO
  v_change_request_pending FROM tt.CHANGE_REQUEST cr where cr.TICKET_ID = p_ticket_id AND
  cr.CHANGE_REQUEST_STATE_ID IN (2, 6)` — `COUNT` aggregate, no `STRICT` concern. Used only
  to decide whether `v_recoverable_status_id` (already possibly cleared above) can also be
  cleared for the "waiting for sign-off" (61) case.
- **source:** `ddl/src/pkgb/tt_event_interface.sql:805-819`

### S-EVENT-032

- **routines:** addevent_new
- **claim:** `addevent_new`'s procedure-level `EXCEPTION` block (lines 822-828) has TWO
  arms: `WHEN EVENT_INTERFACE_STATE.ticket_closed THEN RAISE` (re-raises — S-EVENT-021) and
  `WHEN OTHERS THEN plog.err(...); plog.notice(DBMS_UTILITY.format_error_backtrace)` (logs
  BOTH the error message and a full backtrace, then swallows — does NOT re-raise). This is
  the asymmetric shape that every unhandled site inside `addevent_new`
  (S-EVENT-016/017/018/023/024/026/030) ultimately reaches: from `addevent_new`'s own
  caller's point of view, only the named ticket-closed condition is ever observable; every
  other internal failure is logged (with a backtrace, unlike this package's other
  swallow-sites) and absorbed.
- **source:** `ddl/src/pkgb/tt_event_interface.sql:822-828`

### S-EVENT-033

- **routines:** moveevent
- **claim:** SELECT INTO site #26 (inventory line 879): `SELECT id INTO v_dummy FROM
  tt.ticket WHERE id = p_newticket_id` — reached only if all three parameters are non-NULL.
  `TICKET_PK` — `TOO_MANY_ROWS` impossible; zero rows reachable for a bad
  `p_newticket_id`. `moveevent` has its OWN 3-arm procedure-level handler:
  `WHEN NO_DATA_FOUND THEN plog.warning(...'new ticket does not exist')` (lines 883-884),
  `WHEN DUP_VAL_ON_INDEX THEN plog.info(...'event is already in new ticket')` (lines
  885-886 — reachable from the subsequent `UPDATE tt.event e SET ticket_id =
  p_newticket_id ...` at line 880 hitting a unique-constraint conflict, not from this
  `SELECT` itself, but lexically inside the same block), and
  `WHEN OTHERS THEN plog.err(...)` (lines 887-888) — all three arms log and swallow;
  nothing this routine raises is ever observable to ITS caller. **The routine's own header
  comment flags it as broken** (see `## Routines`, `moveevent`). **Amended (correction,
  branch `phoenix/migrate_tt_only`):** this clause's handler semantics are UNCHANGED by the
  correction — a nonexistent `p_newticket_id` is still swallowed by the local
  `NO_DATA_FOUND` arm and logged as `'...new ticket does not exist'` via `plog.warning`;
  the three-parameter non-NULL gate (line 878) is unchanged; nothing is ever raised to the
  caller. What the correction changes is only the row set of the subsequent `UPDATE`
  (line 880) — see S-EVENT-046/S-EVENT-047. The `DUP_VAL_ON_INDEX` arm remains
  structurally unreachable (`tt.event` has no unique key involving `ticket_id`) and is
  kept for shape parity.
- **source:** `ddl/src/pkgb/tt_event_interface.sql:866-889`

### S-EVENT-034

- **routines:** ticket_type_for_event_type
- **claim:** **Closes this plan's own flagged question.** `ticket_type_for_event_type` is
  a pure `IF`/`ELSIF` lookup over its input parameter with NO `SELECT` of any kind and NO
  call to any other package or procedure (confirmed by reading its full 29-line body,
  `ddl/src/pkgb/tt_event_interface.sql:833-861`, in full) — it therefore cannot
  transitively reach `TT.UTIL`'s `COMMIT`-bearing `close_old_dev_tickets` or any other
  `COMMIT`/`ROLLBACK` site. **There is no FUNCTION/PROCEDURE-COMMIT hazard for this
  routine.** It returns `4` for event types `(10003, 10110, 10102, 10019)`, `2` for
  `(30002, 30009)`, and `1` otherwise.
- **source:** `ddl/src/pkgb/tt_event_interface.sql:833-861`

### S-EVENT-035

- **routines:** exec_event_type_actions
- **claim:** SELECT INTO site #27 (inventory line 918): `SELECT type_id into
  v_event_type_id FROM event WHERE id = p_event_id`. `EVENT_PK` — `TOO_MANY_ROWS`
  impossible; zero rows reachable for a bad `p_event_id`. `exec_event_type_actions` has NO
  procedure-level `EXCEPTION` block of its own (confirmed reading the full 93-line body,
  `ddl/src/pkgb/tt_event_interface.sql:894-986`) — so whether this `NO_DATA_FOUND`
  propagates unhandled or gets swallowed is entirely **caller-dependent**: called from
  `newevent_new` (line 498, which itself has no outer handler at all) it propagates FULLY
  unhandled; called from `addevent_new` (line 711, inside that routine's own outer
  `BEGIN...EXCEPTION`, S-EVENT-032) it is logged and swallowed. Both current callers are in
  this same package (S-EVENT-014, S-EVENT-025).
- **source:** `ddl/src/pkgb/tt_event_interface.sql:917-920`

### S-EVENT-036

- **routines:** exec_event_type_actions
- **claim:** SELECT INTO site #28 (inventory line 927): `SELECT e.host_id INTO v_host_id
  FROM tt.event e WHERE e.id = p_event_id`. `EVENT_PK` — `TOO_MANY_ROWS` impossible; zero
  rows reachable. **Has its own local 2-arm handler**:
  `WHEN NO_DATA_FOUND THEN v_host_id := NULL` (lines 930-931) and
  `WHEN OTHERS THEN plog.err(...)` (lines 932-934 — this arm does NOT itself assign
  `v_host_id`, leaving it at whatever it held before this block, which is its
  uninitialized/`NULL` declared state since it was never assigned earlier). Both arms
  swallow; neither propagates further.
- **source:** `ddl/src/pkgb/tt_event_interface.sql:925-934`

### S-EVENT-037

- **routines:** exec_event_type_actions
- **claim:** SELECT INTO site #29 (inventory line 939): `SELECT ticket_id INTO
  v_ticket_id FROM tt.event WHERE id = p_event_id`. `EVENT_PK` — `TOO_MANY_ROWS`
  impossible; zero rows reachable. No local handler — same caller-dependent
  unhandled/swallowed split as S-EVENT-035 (unhandled via `newevent_new`, swallowed via
  `addevent_new`).
- **source:** `ddl/src/pkgb/tt_event_interface.sql:938-941`

### S-EVENT-038

- **routines:** exec_event_type_actions
- **claim:** **The package's `static_resolution: incomplete` site.** For each
  `event_action_cur` cursor row not suppressed by `is_esc_supp_active` (S-EVENT-040/041),
  `exec_event_type_actions` resolves a procedure name — from a per-host DBPROP lookup
  (`mss.OSAG_DBPROP.get_string_by_host_key_id`, line 955) if a `procedure_key_id` and
  `v_host_id` are both present, falling back to the cursor row's own `procedure_name`
  column (line 960) — then, if a name was resolved, dynamically dispatches it:
  `stmt_str := 'call ' || v_proc_str || '(:eventid)'; EXECUTE IMMEDIATE stmt_str USING
  p_event_id` (lines 970-971), wrapped in its own local
  `EXCEPTION WHEN OTHERS THEN plog.err(...)` (lines 972-974, swallows). **Full trace,
  injection analysis, statement-set enumeration, and translation recommendation are in
  `migration/spec/DYNAMIC-SQL-TRACE.md`** (this spec does not re-derive them): `v_proc_str`
  is DATA-controlled (a DBPROP value or a table column), never a literal in this package's
  own source, reaching the statement text via unquoted `||` concatenation — the trace's
  verdict is **`EXECUTE format()`** (genuinely dynamic; the resolved 2-part name must be
  rewritten from Oracle's 3-part `<schema>.<package>.<routine>` shape and validated against
  an explicit allowlist before execution, with the bind parameter kept as a real parameter,
  never concatenated). The trace ALSO surfaces a depgraph gap this spec must carry
  forward honestly: `TT.EVENT_INTERFACE` has a REAL, previously-undeclared runtime
  dependency on `TT.ESCALATION_INTERFACE` (the callee this dynamic call resolves to for
  every value seen in current data) that `migration/analyze/depgraph.json`'s edge list
  does not capture — see `## Assumptions / Unresolved`.
- **source:** `ddl/src/pkgb/tt_event_interface.sql:945-978`, `migration/spec/DYNAMIC-SQL-TRACE.md`

### S-EVENT-039

- **routines:** exec_event_type_actions
- **claim:** If `is_esc_supp_active` returns `TRUE` (an active service window suppresses
  this escalation), `exec_event_type_actions` does NOT run the dynamic dispatch at all;
  instead it logs a notice and calls `addevent_new` RECURSIVELY with a fixed event type
  (`60010`, "escalation suppressed") and a fixed message pair — an ordinary (non-dynamic)
  procedure call, no `SELECT INTO` risk at this call site itself. This recursive call
  re-enters `addevent_new`'s own full strictness/exception profile (S-EVENT-016 onward).
- **source:** `ddl/src/pkgb/tt_event_interface.sql:979-984`

### S-EVENT-040

- **routines:** is_esc_supp_active
- **claim:** SELECT INTO site #30 (inventory line 1001), reached only for GUMA-suppressible
  event types (10002, 10005, 10007, 10009): `SELECT COUNT(*) INTO
  v_guma_suppressor_exists FROM ...` (an active service window with
  `disable_guma_escalation` set for this host) — `COUNT` aggregate, no `STRICT` concern.
  `> 0` returns `TRUE` immediately.
- **source:** `ddl/src/pkgb/tt_event_interface.sql:993-1020`

### S-EVENT-041

- **routines:** is_esc_supp_active
- **claim:** SELECT INTO site #31 (inventory line 1028), reached only for connection-down
  (`event_action_id = 2`) or ISP-down (`event_action_id = 1 AND event_type_id = 10050`)
  actions: `SELECT COUNT(*) INTO v_conn_suppressor_exists FROM ...` (an active service
  window with `disable_conn_escalation` set) — `COUNT` aggregate, no `STRICT` concern.
  `> 0` returns `TRUE`; otherwise the private function falls through to `RETURN FALSE`
  (line 1049).
- **source:** `ddl/src/pkgb/tt_event_interface.sql:1022-1049`

### S-EVENT-042

- **routines:** add_history_event
- **claim:** SELECT INTO site #32 (inventory line 1081): `SELECT event_sequence.NextVal
  INTO p_event_id FROM DUAL` — sequence pull, no `STRICT` concern, same corpus-wide
  mechanic as S-EVENT-011/022. `add_history_event` has NO `EXCEPTION` block of any kind
  (confirmed reading its full 47-line body, `ddl/src/pkgb/tt_event_interface.sql:1055-1101`)
  — the subsequent `INSERT INTO event` (lines 1084-1096) and the UNCONDITIONAL call
  `TT.OSAG_NOTIFY.event_notify(p_event_id, p_ticket_id)` (line 1099) both propagate any
  failure fully unhandled to this routine's caller.
- **source:** `ddl/src/pkgb/tt_event_interface.sql:1080-1099`

### S-EVENT-043

- **routines:** demote_event
- **claim:** SELECT INTO site #33 (inventory line 1122): `SELECT e.ticket_id, t.host_id,
  t.company_id INTO v_ticket_id, v_host_id, v_company_id FROM tt.event e, tt.ticket t WHERE
  e.id = p_event_id AND e.ticket_id = t.id` — a 1:1 PK-to-PK join (`EVENT_PK`,
  `TICKET_PK`), `TOO_MANY_ROWS` structurally impossible; zero rows reachable for a bad
  `p_event_id`. `demote_event` has NO `EXCEPTION` block anywhere (confirmed reading its
  full 30-line body) — this `NO_DATA_FOUND` propagates FULLY UNHANDLED to whatever called
  `demote_event`. The `UPDATE tt.event SET demoted = 1 WHERE id = p_event_id` immediately
  before this `SELECT` (lines 1118-1120) is an unconditional, zero-row-tolerant `UPDATE` (no
  row-count check) — it succeeds silently even for a nonexistent `p_event_id`, so the
  SUBSEQUENT `SELECT INTO` is where the bad-id case actually surfaces to the caller. The
  would-be history-event write is commented out in source
  (`ddl/src/pkgb/tt_event_interface.sql:1131-1133`, "for the time being, we do not write
  history events for this") — this spec records that as Oracle's actual current behavior,
  not a gap to silently fill in translation.
- **source:** `ddl/src/pkgb/tt_event_interface.sql:1117-1133`

### S-EVENT-044

- **routines:** promote_event
- **claim:** SELECT INTO site #34 (inventory line 1156) — the exact mirror of
  S-EVENT-043 (`UPDATE tt.event SET demoted = 0` then the same `tt.event`×`tt.ticket` join
  by `p_event_id`), same PK-join safety analysis, same total absence of an `EXCEPTION`
  block, same fully-unhandled `NO_DATA_FOUND` propagation, and the same commented-out
  history-event write (`ddl/src/pkgb/tt_event_interface.sql:1165-1167`).
- **source:** `ddl/src/pkgb/tt_event_interface.sql:1151-1167`

### S-EVENT-045

- **routines:** newevent_new, addevent_new, exec_event_type_actions
- **claim:** **The accepted mutual-recursion cycle.** `TT.EVENT_INTERFACE` calls INTO
  `TT.TICKET_INTERFACE` at twelve sites (`migration/analyze/depgraph.json` edge
  `TT.EVENT_INTERFACE -> TT.TICKET_INTERFACE`, call sites `[199, 222, 288, 326, 419, 496,
  620, 621, 676, 707, 720, 737]` — spanning `newevent_new`, `addevent_new`, and reachable
  via `TT.UTIL.update_status_valid_until`'s own two callers per `tt.util.md` S-UTIL-015),
  and `TT.TICKET_INTERFACE` calls BACK into `TT.EVENT_INTERFACE` at twenty-two sites (same
  file, edge `TT.TICKET_INTERFACE -> TT.EVENT_INTERFACE`, call sites `[237, 250, 303, 459,
  475, 509, 513, 1542, 1718, 1731, 1806, 1840, 1883, 1897, 1899, 1950, 1980, 2017, 2060,
  2118, 2155, 2297]`). This is one of exactly two accepted cycle groups in
  `migration/analyze/known_cycles.json` (`TT.EVENT_INTERFACE|TT.OSAG_NOTIFY|
  TT.TICKET_INTERFACE|TT.UTIL`). Neither package can be translated strictly before the
  other. **Translation consequence:** both `CREATE FUNCTION`/`CREATE PROCEDURE` statements
  must be loaded (in either order, or interleaved) before either is ever EXECUTED —
  PL/pgSQL does not resolve a called routine's existence at `CREATE` time, only at first
  call, so a forward reference to a not-yet-created sibling routine is perfectly legal at
  load time and only fails if the sibling is still missing when actually invoked. The
  translation plan for this pair must land both together in the same migration step (or
  ordered such that the last-loaded one's `CREATE` happens before anything actually calls
  into the cycle), not panic at an apparent forward reference.
- **source:** `ddl/src/pkgb/tt_event_interface.sql:199, 222, 288, 326, 419, 496, 620, 621, 676, 707, 720, 737`

### S-EVENT-046

- **routines:** moveevent
- **claim:** **CORRECTION of an acknowledged Oracle bug (branch `phoenix/migrate_tt_only`).**
  Oracle's `UPDATE tt.event e SET ticket_id = p_newticket_id WHERE ticket_id =
  p_oldticket_id` (`ddl/src/pkgb/tt_event_interface.sql:880`) never references
  `p_event_id`, so a single call re-parents EVERY event of `p_oldticket_id` — the
  routine's own header comment (line 866: "FIXME / BROKEN the p_event_id is not actually
  used! This moves ALL events of a ticket") and the package spec's contract
  (`ddl/src/pkg/tt_event_interface.sql:67-73`, "moves an event from one ticket to
  another") both say this is wrong. The corrected behaviour: when all three parameters are
  non-NULL and `p_newticket_id` exists (S-EVENT-033's existence check still runs first),
  the `UPDATE` is restricted to `id = p_event_id AND ticket_id = p_oldticket_id` — exactly
  the one event named by `p_event_id` moves to `p_newticket_id`; every other event of
  `p_oldticket_id` keeps its `ticket_id`. No other statement of the routine changes.
- **source:** `ddl/src/pkgb/tt_event_interface.sql:866-880`, `ddl/src/pkg/tt_event_interface.sql:67-74`

### S-EVENT-047

- **routines:** moveevent
- **claim:** **CORRECTION, companion to S-EVENT-046 — the "nothing happens" and "event does
  not exist" branches the package spec promises.** Per `ddl/src/pkg/tt_event_interface.sql:
  68-71`: "If the event does not belong to the old ticket or the event is already attached
  to the new ticket then nothing happens. However if the event does not exist ... a
  warning is written to the log." The Oracle body (`ddl/src/pkgb/tt_event_interface.sql:
  878-880`) implements neither branch (it cannot — it never looks at `p_event_id`). The
  corrected behaviour: (i) if the event identified by `p_event_id` exists but its
  `ticket_id` is not `p_oldticket_id` (including the case where it is already
  `p_newticket_id`), the `UPDATE` matches zero rows, nothing is modified and nothing is
  logged; (ii) if no `tt.event` row with `id = p_event_id` exists, nothing is modified
  and `plog.warning(c_prefix||v_errmsg||'event does not exist')` is logged, using the
  same `v_errmsg` prefix (line 877) as the existing `'new ticket does not exist'` warning
  (line 884). Neither branch raises to the caller (the 3-arm swallow of S-EVENT-033 is
  unchanged).
- **source:** `ddl/src/pkg/tt_event_interface.sql:67-74`, `ddl/src/pkgb/tt_event_interface.sql:877-884`

## Checklist

### 1. Empty-string / NULL handling

**One genuine, reachable Pitfall-2 hazard found** (S-EVENT-015): `v_scope_info`
(`VARCHAR2(30000)`, no default) in both `newevent_new` and `addevent_new` is built via
`x := x || 'literal'` starting from `NULL` — Oracle's `NULL || 'x' = 'x'` seeds it
correctly; PL/pgSQL's `NULL || 'x' = NULL` would leave it permanently `NULL`, silently
dropping the `company_id=`/`host_id=` suffix from an alerting-log line. Translation must
seed `v_scope_info := ''` (or `COALESCE` at each `||`), not port the bare concatenation.

**A second, narrower reachable hazard**: `v_details_public := SUBSTRB(p_details_public,1,
30000)` (`newevent_new`, line 71) then `IF (v_details_public is not null AND p_type_id IN
(...))` (line 438) gates the alerting log. In Oracle, `SUBSTRB('', 1, 30000)` returns `NULL`
(Oracle collapses `''` universally), so a caller passing an empty string `p_details_public`
is indistinguishable from passing `NULL` — the `IS NOT NULL` check is `FALSE` either way.
In PostgreSQL, `substr('', 1, 30000)` returns a real, distinct `''` — the same call would
make `v_details_public IS NOT NULL` evaluate `TRUE`, taking the alerting-log branch when
Oracle would not have. `tt.event.details_public` has no `NOT NULL`/check constraint
forbidding `''` at the column level, and callers pass `p_details_public` as a plain
parameter with no constraint of its own — this is reachable, not theoretical. Translation
must normalize at the `SUBSTRB`/`substr` boundary (`NULLIF(substr(...), '')`), not port the
bare `IS NOT NULL` check. `addevent_new` has the identical shape via its own
`v_details_public` (assigned from `tt.ticket_interface.replace_id_placeholders(...)`,
line 620) and its own `IF (v_details_public is not null AND ...)` gate (line 654) — same
hazard, same fix required, though the intermediate `replace_id_placeholders` call means the
`''`-producing boundary is technically inside `TT.TICKET_INTERFACE`, not this package; this
spec flags the OBSERVABLE symptom in `addevent_new`'s own gate regardless of which
package's code produces the `''`.

Every other `VARCHAR2`/`CLOB` identifier taking part in an `IS NULL`/`IS NOT NULL`/`||`
site was reviewed (grep-confirmed against the full 1172-line body) and found NOT to be a
collapsing hazard: `v_reason` (`newevent_new`) is explicitly initialized to a real `''`
literal at declaration (line 61: `v_reason VARCHAR2(1024) := '';`), so its later `||`
accumulation behaves identically in both engines (`'' || 'x' = 'x'` in both); `subject`/
`eventSubject` (`newevent_new`, lines 344-374) are always assigned from a `SELECT ... INTO`
or a `SUBSTR` of that non-NULL result before any `||`, never left at their declared `NULL`
state when concatenated; `c_prefix`/`C_PREFIX` constants throughout are compile-time
literals, never NULL; `v_errmsg` (`moveevent`) is always fully assigned before use, never
concatenated from an unseeded state.

### 2. SELECT INTO strictness

**All 34 sites from the Phase 1 inventory's `select_into_sites` array for
`TT.EVENT_INTERFACE` are enumerated below, one row each, none omitted.** Verdict legend
(same as `tt.osag_notify.md`): `STRICT + handler` = a local or enclosing Oracle handler
exists and must be reproduced; `STRICT + handler (indirect)` = no LOCAL handler, but the
routine's own outer `WHEN OTHERS` swallows it; `STRICT, unhandled` = no handler anywhere
reachable, Oracle's own contract IS unhandled propagation; `STRICT, mixed by caller` = the
routine itself has no handler and its propagation fate depends entirely on which of this
package's OWN routines called it; `no STRICT` = zero rows is structurally impossible
(aggregate query or `DUAL` sequence pull).

| # | ddl/src/pkgb/tt_event_interface.sql:LINE | target(s) | zero rows possible? | multi rows possible? | Oracle handler | PG translation | clause |
|---|---|---|---|---|---|---|---|
| 1 | `ddl/src/pkgb/tt_event_interface.sql:79` | `v_company_id, v_mss_service_id` (mss.host x mss.host2service, newevent_new) | yes (no host2service row) | **yes** (`mss.host2service` PK `(host_id,service_id)`, not unique on `host_id`) | local `WHEN NO_DATA_FOUND` (84-85); `WHEN OTHERS THEN RAISE` (86-87) re-raises TOO_MANY_ROWS | STRICT + handler (NDF only; TMR re-raises, then unhandled -- no outer net in newevent_new) | S-EVENT-001 |
| 2 | `ddl/src/pkgb/tt_event_interface.sql:94` | `v_company_id` (stop.contact by id) | yes (bad p_contact_id) | no (CONTACT_PK) | none anywhere in newevent_new | STRICT, unhandled | S-EVENT-002 |
| 3 | `ddl/src/pkgb/tt_event_interface.sql:104` | `active` (mss.host by id) | yes (bad p_host_id) | no (HOST_PK) | none | STRICT, unhandled | S-EVENT-003 |
| 4 | `ddl/src/pkgb/tt_event_interface.sql:118` | `v_disable_event_ticket_id` (COUNT) | no (aggregate) | no | n/a | no STRICT | S-EVENT-004 |
| 5 | `ddl/src/pkgb/tt_event_interface.sql:157` | `v_new_source` (event_type by id) | yes | no (EVENTTYPE_PK) | none | STRICT, unhandled | S-EVENT-005 |
| 6 | `ddl/src/pkgb/tt_event_interface.sql:165` | `v_monitoring_ticket_id` (MIN) | no (aggregate) | no | n/a | no STRICT | S-EVENT-006 |
| 7 | `ddl/src/pkgb/tt_event_interface.sql:176` | `v_collect_event_ticket_id` (MAX) | no (aggregate) | no | n/a | no STRICT | S-EVENT-007 |
| 8 | `ddl/src/pkgb/tt_event_interface.sql:203` | `v_recent_ticket_type` etc. (ticket x event x event_type join) | yes | no (PK joins + MIN(id) subquery pins one row) | local `WHEN NO_DATA_FOUND THEN NULL` (280-282) | STRICT + handler | S-EVENT-008 |
| 9 | `ddl/src/pkgb/tt_event_interface.sql:344` | `subject` (event_type by id, new-ticket branch) | yes | no (EVENTTYPE_PK) | none (after ticket-search block closed) | STRICT, unhandled | S-EVENT-010 |
| 10 | `ddl/src/pkgb/tt_event_interface.sql:377` | `v_ticket_id` (ticket_sequence.NextVal via DUAL) | no (DUAL) | no | n/a | no STRICT | S-EVENT-011 |
| 11 | `ddl/src/pkgb/tt_event_interface.sql:384` | `v_count` (COUNT via auth.permission) | no (aggregate) | no | n/a | no STRICT | S-EVENT-012 |
| 12 | `ddl/src/pkgb/tt_event_interface.sql:389` | `v_count` (COUNT via auth.mv_service_access) | no (aggregate) | no | n/a | no STRICT | S-EVENT-013 |
| 13 | `ddl/src/pkgb/tt_event_interface.sql:423` | `p_event_id` (event_sequence.NextVal via DUAL) | no (DUAL) | no | n/a | no STRICT | S-EVENT-014 |
| 14 | `ddl/src/pkgb/tt_event_interface.sql:561` | `v_ticket_type, v_ticket_status` (tt.ticket by id, addevent_new) | yes (bad p_ticket_id) | no (TICKET_PK) | none local; outer WHEN OTHERS (822-828) swallows | STRICT + handler (indirect) | S-EVENT-016 |
| 15 | `ddl/src/pkgb/tt_event_interface.sql:566` | `v_event_source` (event_type by id) | yes | no (EVENTTYPE_PK) | none local; outer swallow | STRICT + handler (indirect) | S-EVENT-017 |
| 16 | `ddl/src/pkgb/tt_event_interface.sql:567` | `v_pinned` (event_type.autopin by id) | yes | no (EVENTTYPE_PK) | none local; outer swallow | STRICT + handler (indirect) | S-EVENT-018 |
| 17 | `ddl/src/pkgb/tt_event_interface.sql:580` | `v_merged_ticket_id` (tt.event by ticket/type/ROWNUM=1) | yes | **impossible only because of ROWNUM=1** (translation hazard: needs LIMIT 1, not bare STRICT) | local `WHEN NO_DATA_FOUND THEN v_merged_ticket_id := -1` (587-589) | STRICT + handler, MUST add LIMIT 1 | S-EVENT-019 |
| 18 | `ddl/src/pkgb/tt_event_interface.sql:615` | `ev_id` (event_sequence.NextVal via DUAL) | no (DUAL) | no | n/a | no STRICT | S-EVENT-022 |
| 19 | `ddl/src/pkgb/tt_event_interface.sql:631` | `v_company_id` (mss.host by id, IF branch) | yes (bad p_host_id) | no (HOST_PK) | none local; outer swallow | STRICT + handler (indirect) | S-EVENT-023 |
| 20 | `ddl/src/pkgb/tt_event_interface.sql:636` | `v_company_id` (tt.ticket by id, ELSE branch) | yes (structurally near-impossible; ticket pre-validated) | no (TICKET_PK) | none local; outer swallow | STRICT + handler (indirect) | S-EVENT-023 |
| 21 | `ddl/src/pkgb/tt_event_interface.sql:674` | `v_ux_timeout_start` (tt.event by id=ev_id, just-inserted) | yes (structurally near-impossible; same-txn own insert) | no (EVENT_PK) | none local; outer swallow | STRICT + handler (indirect) | S-EVENT-024 |
| 22 | `ddl/src/pkgb/tt_event_interface.sql:718` | `v_event_source` (event_type by id, re-lookup) | yes (structurally near-impossible; same id validated at #15) | no (EVENTTYPE_PK) | none local; outer swallow | STRICT + handler (indirect) | S-EVENT-026 |
| 23 | `ddl/src/pkgb/tt_event_interface.sql:729` | `v_ticket_has_service_window` (COUNT) | no (aggregate) | no | n/a | no STRICT | S-EVENT-027 |
| 24 | `ddl/src/pkgb/tt_event_interface.sql:765` | `v_fast_resolvable` etc. (tt.ticket by id, re-query) | yes (structurally near-impossible; same ticket validated at #14) | no (TICKET_PK) | none local; outer swallow | STRICT + handler (indirect) | S-EVENT-030 |
| 25 | `ddl/src/pkgb/tt_event_interface.sql:806` | `v_change_request_pending` (COUNT) | no (aggregate) | no | n/a | no STRICT | S-EVENT-031 |
| 26 | `ddl/src/pkgb/tt_event_interface.sql:879` | `v_dummy` (tt.ticket by id=p_newticket_id, moveevent) | yes (bad p_newticket_id) | no (TICKET_PK) | local 3-arm: NDF (883-884), DUP_VAL_ON_INDEX (885-886), OTHERS (887-888) -- all swallow | STRICT + handler (all arms) | S-EVENT-033 |
| 27 | `ddl/src/pkgb/tt_event_interface.sql:918` | `v_event_type_id` (event by id=p_event_id, exec_event_type_actions) | yes (bad p_event_id) | no (EVENT_PK) | none in this routine; caller-dependent (unhandled via newevent_new, swallowed via addevent_new) | STRICT, mixed by caller | S-EVENT-035 |
| 28 | `ddl/src/pkgb/tt_event_interface.sql:927` | `v_host_id` (tt.event by id=p_event_id) | yes | no (EVENT_PK) | local 2-arm: NDF sets NULL (930-931), OTHERS logs (932-934) -- both swallow | STRICT + handler | S-EVENT-036 |
| 29 | `ddl/src/pkgb/tt_event_interface.sql:939` | `v_ticket_id` (tt.event by id=p_event_id) | yes | no (EVENT_PK) | none in this routine; same caller-dependent split as #27 | STRICT, mixed by caller | S-EVENT-037 |
| 30 | `ddl/src/pkgb/tt_event_interface.sql:1001` | `v_guma_suppressor_exists` (COUNT, is_esc_supp_active) | no (aggregate) | no | n/a | no STRICT | S-EVENT-040 |
| 31 | `ddl/src/pkgb/tt_event_interface.sql:1028` | `v_conn_suppressor_exists` (COUNT, is_esc_supp_active) | no (aggregate) | no | n/a | no STRICT | S-EVENT-041 |
| 32 | `ddl/src/pkgb/tt_event_interface.sql:1081` | `p_event_id` (event_sequence.NextVal via DUAL, add_history_event) | no (DUAL) | no | n/a | no STRICT | S-EVENT-042 |
| 33 | `ddl/src/pkgb/tt_event_interface.sql:1122` | `v_ticket_id, v_host_id, v_company_id` (tt.event x tt.ticket, demote_event) | yes (bad p_event_id) | no (1:1 PK join) | **none anywhere in demote_event** (zero EXCEPTION blocks) | STRICT, unhandled | S-EVENT-043 |
| 34 | `ddl/src/pkgb/tt_event_interface.sql:1156` | same shape (promote_event) | yes | no (1:1 PK join) | **none anywhere in promote_event** | STRICT, unhandled | S-EVENT-044 |

### 3. Exception codes

**One `RAISE_APPLICATION_ERROR` call in the whole 1172-line body**
(`ddl/src/pkgb/tt_event_interface.sql:611`), and it is invoked through a NAMED CONSTANT
(`EVENT_INTERFACE_STATE.S_ERRNO_TICKET_CLOSED`, Oracle code `-20980`, declared in the
companion `*_STATE` package `ddl/src/pkg/tt_event_interface_state.sql:7-9`) rather than a
numeric literal — exactly the blind spot `CHECKLIST.md` warns Phase 1's lexer has (a call
through a named constant does not appear in `inventory.json`'s `raise_application_error[]`,
confirmed empty for this package; traced by hand here, S-EVENT-021). This is also the
package's ONE exception that is intentionally re-raised rather than swallowed
(`addevent_new`'s own `WHEN EVENT_INTERFACE_STATE.ticket_closed THEN RAISE`,
lines 823-824, S-EVENT-021/S-EVENT-032). A second named exception surface exists:
`moveevent`'s `WHEN DUP_VAL_ON_INDEX` (line 885) — Oracle's built-in unique-constraint
exception, which PostgreSQL's `unique_violation` SQLSTATE (`23505`) already maps to
directly (no corpus-specific mapping decision needed here). The authoritative Oracle-code
-> PostgreSQL SQLSTATE mapping table (including `-20980`) is Phase 3's XCUT-01; this spec
records what it needs and marks the mapping **PROVISIONAL**.

### 4. Package state

None. Verified by reading the full 1172-line package body: it opens with the private
function's forward declaration (`FUNCTION is_esc_supp_active(...)`,
`ddl/src/pkgb/tt_event_interface.sql:15`) immediately after `IS` (line 3) — no
package-level `DECLARE`-equivalent section of any kind between them. The file ends at
lines 1171-1172 (`END event_interface; /`) with no trailing unnamed initialization block.
Matches the Phase 1 inventory's `package_state: []` and (implicitly, no `has_init_block`
field reported as true) exactly.

### 5. FUNCTION vs PROCEDURE

**Zero `COMMIT`, zero `ROLLBACK`, zero `PRAGMA AUTONOMOUS_TRANSACTION` anywhere in this
package itself** (confirmed: inventory's `has_commit: false`, `has_rollback: false`,
`autonomous_transaction: false` for `TT.EVENT_INTERFACE`; grep-confirmed independently
against the full body). Seven of the eight public routines are `PROCEDURE`s;
`ticket_type_for_event_type` is the package's only `FUNCTION` — and **this spec's
own required check closes cleanly**: `ticket_type_for_event_type` performs zero database
access and calls zero other routines (S-EVENT-034), so it cannot transitively reach
`TT.UTIL.close_old_dev_tickets`'s `COMMIT` (`tt.util.md` Checklist dimension 5) or any
other `COMMIT`/`ROLLBACK` site in the cycle group. **There is no FUNCTION/PROCEDURE-COMMIT
hazard within this package.**

This package DOES call OUT into `TT.UTIL.update_status_valid_until` (S-EVENT-029, from
`addevent_new`, a `PROCEDURE`) — per `tt.util.md`'s own S-UTIL-015, this is one of exactly
two current callers of that routine, both `PROCEDURE`s today, so no collision exists in
the CURRENT static call graph. It also calls into `TT.TICKET_INTERFACE` at twelve sites
and is called back from it at twenty-two (S-EVENT-045) — `TT.TICKET_INTERFACE`'s own 38
routines' `pg_kind`/COMMIT profile is NOT reviewed by this spec (its own spec is a separate
plan in this phase); whether any of those 38 routines' eventual `pg_kind` collides with a
call made FROM this package into it is unresolved here (see `## Assumptions /
Unresolved`). `pg_kind` remains PROVISIONAL for all 8 of this package's own routines
(Phase 3 XCUT-04), per `migration/README.md`'s standing warning.

## Assumptions / Unresolved

- **The dynamic-SQL verdict (S-EVENT-038), restated with its translation consequence.**
  `migration/spec/DYNAMIC-SQL-TRACE.md` traces the sole `EXECUTE IMMEDIATE`
  (`ddl/src/pkgb/tt_event_interface.sql:971`) by hand and concludes **`EXECUTE format()`**
  — genuinely dynamic (not spurious, because `tt.event_action` is a live, editable table
  and DBPROP key `399` has no documented value constraint), requiring: (1) rewriting
  Oracle's 3-part `<schema>.<package>.<routine>` name to this project's flattened
  2-part `package_in_name` convention before executing anything (new work Oracle never
  needed), (2) validating the resolved name against an explicit allowlist BEFORE
  execution (not relying on `%I` quoting alone, since `%I` prevents syntax injection but
  not a config value naming an unintended-but-valid callee), and (3) keeping the bind
  parameter a genuine parameter (`USING p_event_id`), never string-concatenated. **The
  trace itself flags one sub-item `UNRESOLVED — DO NOT GUESS`**: whether the allowlist
  should be scoped narrowly to `TT.ESCALATION_INTERFACE.*` (everything ever seen in
  current data) or more broadly to "any single-`NUMBER`-argument procedure" is a
  translation-TIME policy decision Oracle's own source does not settle — this spec
  carries that unresolved status forward UNCHANGED, not silently narrowed to a guess.
- **The depgraph edge-list gap the trace closes, and the NEW cycle it surfaces.**
  `migration/analyze/depgraph.json`'s edge list for `TT.EVENT_INTERFACE` does not include
  an edge to `TT.ESCALATION_INTERFACE`, because the callee is assembled at runtime and was
  never textually visible to the lexer. The trace closes this gap FOR THE IDENTIFIERS
  CURRENTLY IN DATA (`TT.ESCALATION_INTERFACE.{escalate_os, escalate_customer,
  escalate_isp_outage_to_os, nop}`, all confirmed real in `name-map.csv`). It also
  surfaces that `TT.ESCALATION_INTERFACE` already has a VISIBLE edge calling INTO
  `TT.EVENT_INTERFACE` (`depgraph.json` in-edges, call sites `[68, 131]`) — meaning the
  dynamic-SQL edge this trace adds makes `TT.EVENT_INTERFACE` <-> `TT.ESCALATION_INTERFACE`
  a SECOND, previously-invisible mutual-recursion pair, on top of the already-accepted
  4-member cycle group (S-EVENT-045) that `TT.ESCALATION_INTERFACE` is not currently a
  member of in `migration/analyze/known_cycles.json`. This spec does NOT add it there
  (a `depgraph.py`/`known_cycles.json` maintenance decision, out of scope for this plan)
  — it is flagged here, loudly, again in this plan's SUMMARY, so Phase 4's
  translation-order planning does not miss it.
- **S-EVENT-001's `TOO_MANY_ROWS` re-raise-then-unhandled path is a genuine, reachable
  hazard, not a theoretical one.** `mss.host2service`'s primary key `(HOST_ID,
  SERVICE_ID)` structurally permits a host mapped to more than one service; `newevent_new`
  has no procedure-level `EXCEPTION` block at all, so a re-raised `TOO_MANY_ROWS` from this
  site propagates all the way to `newevent_new`'s own caller today. Whether this has ever
  actually fired in production cannot be determined from static source alone (no live
  Oracle exists for this phase to check against) — the column-level fact alone (not a
  unique index on `HOST_ID`) is sufficient to make this a real spec-level finding.
- **The `ROWNUM=1` -> `LIMIT 1` translation mechanic (S-EVENT-019)** is this pilot's first
  occurrence of an Oracle `ROWNUM` predicate inside a `SELECT INTO`'s `WHERE` clause acting
  as an implicit `TOO_MANY_ROWS` suppressor. Neither `tt.osag_notify.md` nor `tt.util.md`
  needed to record this mechanic; it is flagged here as corpus-wide (Phase 4 will very
  likely hit `ROWNUM` again), not package-specific.
- **`moveevent`'s acknowledged bug** (`ddl/src/pkgb/tt_event_interface.sql:866`,
  "FIXME / BROKEN the p_event_id is not actually used! ... Looks like this code is never
  run.") was originally recorded here as Oracle's ACTUAL current behavior, with the
  fix-or-reproduce decision explicitly deferred. **Decided on branch
  `phoenix/migrate_tt_only`** (status report 2026-10-13, Q11 (a); project-owner
  instruction "Don't mimic broken behaviour of oracle routines, but annotate/explain what
  changed with the correction"): the translation is CORRECTED — S-EVENT-046/S-EVENT-047
  state the corrected semantics, S-EVENT-033 keeps the unchanged swallow/log path, and
  `migration/pgsql/tt/event_interface.FINDINGS.md` ("Deviations from Oracle") records the
  `DEVIATION(ORACLE-BUG)`. Still open: whether any Oracle-side caller ever relied on the
  move-everything behaviour cannot be determined statically (the body comment says the
  code "is never run"; no caller of `moveevent` exists in `ddl/src/`).
- **`TT.TICKET_INTERFACE`'s own internal behavior (its 38 routines' `SELECT INTO`
  strictness, exception handling, package state, and `pg_kind`) is entirely OUT OF SCOPE
  for this spec** — its own spec is a separate, not-yet-written plan in this phase. Only
  the CALL-GRAPH EDGES into and out of it (from `migration/analyze/depgraph.json`,
  S-EVENT-009/S-EVENT-045) are cited here. Whether any FUNCTION/PROCEDURE-COMMIT collision
  exists between this package's calls into `TT.TICKET_INTERFACE` and that package's own
  eventual `pg_kind` resolution is unresolved by this spec and deferred to that package's
  own spec plus Phase 3's XCUT-04.
- **Whether production `tt.event_action`/DBPROP data ever diverges from the
  `masterdata/` snapshot in a way that exercises a dynamic-dispatch target beyond the
  four `TT.ESCALATION_INTERFACE` routines currently seen** is already flagged in
  `migration/spec/DYNAMIC-SQL-TRACE.md` and restated here only for spec-level visibility —
  not re-litigated; no live Oracle exists for this phase to settle it.
- **The `v_scope_info`/`v_details_public` `''`/`NULL` boundary hazards (Checklist
  dimension 1, S-EVENT-015)** are translation-DECISION items (an explicit seed/normalize
  choice), not merely observational — flagged here so the eventual translation plan does
  not treat them as optional polish.
- **`pg_kind` (FUNCTION vs PROCEDURE) remains PROVISIONAL for all 8 public routines**, per
  `migration/README.md`'s standing warning — this spec confirms no COMMIT/ROLLBACK/
  autonomous-transaction hazard exists WITHIN this package (Checklist dimension 5) and
  specifically closes the plan's own flagged question about `ticket_type_for_event_type`
  (S-EVENT-034), but the final call for every routine belongs to Phase 3's XCUT-04.
- Nothing else is unresolved: all 34 `SELECT ... INTO` sites (cross-checked
  programmatically against `migration/analyze/inventory.json`'s `select_into_sites`
  array — all 34 present), all 5 `NO_DATA_FOUND` handlers, all 6 `WHEN OTHERS` handlers,
  the 1 `DUP_VAL_ON_INDEX` handler (outside the tracked NDF/TMR/OTHERS categories, hence
  not reflected in the inventory's own handler counts but recorded here), the 1
  `RAISE_APPLICATION_ERROR` call (via named constant, traced by hand since it evades
  Phase 1's numeric-literal-only regex), the full absence of package state, the full
  absence of `COMMIT`/`ROLLBACK`/`PRAGMA`, and both `type_refs` (`ticket.id%TYPE`,
  `event_action_cur%ROWTYPE`) were reviewed against the complete text of
  `ddl/src/pkg/tt_event_interface.sql`, `ddl/src/pkgb/tt_event_interface.sql`,
  `ddl/src/pkg/tt_event_interface_state.sql`, the relevant `ddl/generated/schema.oracle.sql`
  table/constraint definitions cited throughout this spec (`mss.host`, `mss.host2service`,
  `stop.contact`, `tt.ticket`, `tt.event`, `tt.event_type`, `tt.change_request`,
  `tt.event_action`, `tt.event_type_action`, `tt.service_window`,
  `tt.host2service_window`), and `migration/analyze/depgraph.json`'s edges into and out of
  `TT.EVENT_INTERFACE`.
