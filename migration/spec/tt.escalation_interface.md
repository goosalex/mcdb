---
oracle_schema: TT
oracle_package: ESCALATION_INTERFACE
pg_schema: tt
pg_prefix: escalation_interface
clause_prefix: ESC
oracle_spec: ddl/src/pkg/tt_escalation_interface.sql
oracle_body: ddl/src/pkgb/tt_escalation_interface.sql
public_routines: 5
---

# TT.ESCALATION_INTERFACE — PostgreSQL spec

Per its header comment (`ddl/src/pkg/tt_escalation_interface.sql:5-8`), this package
"implements all the logic that is needed for escalating events/tickets to mission
control, pikett, securitas and the customers." In practice its five procedures are the
**targets of the dynamic dispatch** in `TT.EVENT_INTERFACE.exec_event_type_actions`
(`ddl/src/pkgb/tt_event_interface.sql:966-973`, the corpus's one `EXECUTE IMMEDIATE`
site, see `migration/spec/DYNAMIC-SQL-TRACE.md` and S-EVENT-038): `tt.event_action` id 1
is configured as `tt.escalation_interface.escalate_os` (`masterdata/TT/event_action.csv`),
and DBPROP keys 139/140/399 (`masterdata/MSS/key.csv`) default to `escalate_customer`,
`nop`, `nop` respectively, with regexp guards admitting only `nop`, `escalate_os`,
`escalate_customer` and `escalate_isp_outage_to_os`. The fifth routine,
`clear_customer_escalation`, is called statically from
`MC.MONITORING_TICKET_PROCESSES.new_event_up`
(`ddl/src/pkgb/mc_monitoring_ticket_processes.sql:132`).

Each `escalate_*` routine resolves the event's ticket, decides from
`tt.ticket.escalation_status_id` and `mss.host.active` whether an escalation is needed,
and — if so — stamps the ticket (`escalation_status_id = 10`, `last_escalation_date`)
and appends an "escalation to os" event (type 60001) through
`TT.EVENT_INTERFACE.addevent_new`. `escalate_isp_outage_to_os` instead opens a brand-new
hidden ticket through `TT.TICKET_INTERFACE.newticket_new`.

**This spec deliberately specifies CORRECTED behaviour at two sites** (S-ESC-008,
S-ESC-014) where the Oracle body is demonstrably broken — it escalates "nothing"
silently when the event it was asked to escalate does not exist. Per the project
owner's instruction ("don't mimic broken behaviour of Oracle routines, but annotate/
explain what changed with the correction"), those clauses state the corrected
behaviour explicitly, cite the Oracle lines that show the defect, and the tests assert
the corrected behaviour. Every other clause is Oracle-faithful.

## Routines

### escalate_os

- **Oracle signature:** `PROCEDURE escalate_os(p_event_id NUMBER)`
- **PostgreSQL name:** `tt.escalation_interface_escalate_os` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/tt_escalation_interface.sql:20`
- **Defined:** `ddl/src/pkgb/tt_escalation_interface.sql:12-77`
- Resolves event → ticket → (escalation status, host) → host.active; returns silently
  if the ticket is already in an OS escalation (status 10/11) or its host is inactive;
  otherwise sets `escalation_status_id = 10`, `last_escalation_date = SYSDATE` and adds
  a 60001 event via `event_interface.addevent_new`. Logs via `plog.debug`. Raises
  nothing of its own; has no handler around the `addevent_new` call (S-ESC-009).

### escalate_customer

- **Oracle signature:** `PROCEDURE escalate_customer(p_event_id NUMBER)`
- **PostgreSQL name:** `tt.escalation_interface_escalate_customer` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/tt_escalation_interface.sql:32`
- **Defined:** `ddl/src/pkgb/tt_escalation_interface.sql:86-139`
- Same resolution chain as `escalate_os`, but returns for ANY non-zero escalation
  status, and only adds the 60001 event if its race-guarded `UPDATE ... AND
  escalation_status_id <> 10` actually changed a row. **Despite its name and comments
  (which talk about a customer escalation, event 60101, status 20), the BODY escalates
  to OS: status 10, event 60001** — see S-ESC-012.

### escalate_isp_outage_to_os

- **Oracle signature:** `PROCEDURE escalate_isp_outage_to_os(p_event_id NUMBER)`
- **PostgreSQL name:** `tt.escalation_interface_escalate_isp_outage_to_os` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/tt_escalation_interface.sql:42`
- **Defined:** `ddl/src/pkgb/tt_escalation_interface.sql:146-203`
- Looks up host name, company short name and original ticket id for the event via a
  six-table join; on any failure logs via `plog.err` and returns. Otherwise composes a
  public and a private description and opens a NEW trouble ticket (type 1, no host, no
  company, service component 27) with an incident-report event (30005) through
  `tt.ticket_interface.newticket_new`.

### nop

- **Oracle signature:** `PROCEDURE nop(p_event_id NUMBER)`
- **PostgreSQL name:** `tt.escalation_interface_nop` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/tt_escalation_interface.sql:50`
- **Defined:** `ddl/src/pkgb/tt_escalation_interface.sql:208-213`
- Does nothing. Exists so that a DBPROP-configured event action can be "no action".

### clear_customer_escalation

- **Oracle signature:** `PROCEDURE clear_customer_escalation(p_ticket_id tt.ticket.id%TYPE)`
- **PostgreSQL name:** `tt.escalation_interface_clear_customer_escalation` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/tt_escalation_interface.sql:60`
- **Defined:** `ddl/src/pkgb/tt_escalation_interface.sql:215-220`
- Single `UPDATE`: resets `escalation_status_id` from 20 (customer escalation) to 0;
  never touches a ticket in any other escalation status.

## Clauses

### S-ESC-001

- **routines:** escalate_os, escalate_customer, escalate_isp_outage_to_os, nop, clear_customer_escalation
- **claim:** All five public routines are Oracle `PROCEDURE`s taking exactly one `IN`
  parameter (`p_event_id NUMBER` for the first four, `p_ticket_id tt.ticket.id%TYPE`
  for the last); none returns a value, none issues `COMMIT`/`ROLLBACK`, none carries
  `PRAGMA AUTONOMOUS_TRANSACTION`. `name-map.csv` carries `pg_kind=procedure` for all
  five. The single-`NUMBER`-argument shape is load-bearing: `exec_event_type_actions`
  dispatches them as `'call ' || v_proc_str || '(:eventid)'`
  (`ddl/src/pkgb/tt_event_interface.sql:969-971`).
- **source:** `ddl/src/pkg/tt_escalation_interface.sql:20, 32, 42, 50, 60`, `ddl/src/pkgb/tt_event_interface.sql:969-971`

### S-ESC-002

- **routines:** escalate_os
- **claim:** `escalate_os` resolves its inputs with FOUR `SELECT ... INTO` statements
  inside ONE `BEGIN ... EXCEPTION WHEN NO_DATA_FOUND THEN v_host_id := NULL; END`
  block: (a) `tt.event.ticket_id` by `e.id = p_event_id` (line 27); (b)
  `tt.ticket.escalation_status_id` by `id = v_ticket_id` (line 32); (c)
  `tt.ticket.host_id` by the same key (line 35); (d) `mss.host.active` by
  `h.id = v_host_id` (line 41). All four are keyed on a primary key (`tt.event.id`,
  `tt.ticket.id`, `mss.host.id`), so `TOO_MANY_ROWS` is structurally impossible at every
  site. The handler is shared: whichever of the four raises `NO_DATA_FOUND`, control
  lands on line 47 with every variable assigned AFTER the failing statement still at its
  initial `NULL`.
- **source:** `ddl/src/pkgb/tt_escalation_interface.sql:25-48`

### S-ESC-003

- **routines:** escalate_os
- **claim:** If the ticket's `escalation_status_id` is 10 or 11 (already in an OS
  escalation, or "escalation to pikett failed"), `escalate_os` `RETURN`s immediately
  with no `UPDATE` and no event added — regardless of the host's state. This check is
  evaluated BEFORE the host-activity check; it is the header's measure 7 ("If a ticket
  is already marked for escalation, it will not be escalated again").
- **source:** `ddl/src/pkgb/tt_escalation_interface.sql:53-57`, `ddl/src/pkg/tt_escalation_interface.sql:84-85`

### S-ESC-004

- **routines:** escalate_os
- **claim:** When the ticket's host is active (`mss.host.active = 1`) and the ticket is
  not in status 10/11, `escalate_os` (1) `UPDATE`s `tt.ticket` setting
  `escalation_status_id = 10` and `last_escalation_date = SYSDATE` for `id =
  v_ticket_id`, then (2) calls `event_interface.addevent_new(v_event_id OUT,
  v_ticket_id, 60001, v_host_id, 'Starting escalation to Open Systems Mission
  Control', 'Event added by tt.escalation_interface.escalate_os. Caused by event ' ||
  p_event_id)` — all other `addevent_new` parameters at their defaults (no contact,
  public, `SYSDATE`, no notification). The resulting `tt.event` row therefore has
  `type_id = 60001`, `ticket_id = v_ticket_id`, `host_id = v_host_id`, and a
  `details_private` ending in the causing event's id.
- **source:** `ddl/src/pkgb/tt_escalation_interface.sql:60-75`

### S-ESC-005

- **routines:** escalate_os
- **claim:** A ticket with NO host (`tt.ticket.host_id IS NULL`) IS escalated — the
  branch condition is `v_host_active = 1 OR v_host_id IS NULL`, per the inline comment
  "if no host was specified we need escalation anyway" (line 59). The same outcome
  applies when `host_id` is set but no `mss.host` row exists for it: site (d) raises
  `NO_DATA_FOUND`, the shared handler sets `v_host_id := NULL` (line 47), and the
  ticket is escalated with the 60001 event carrying `host_id = NULL`. In both cases
  (b) has already run, so the S-ESC-003 status check still applies first.
- **source:** `ddl/src/pkgb/tt_escalation_interface.sql:41-47, 59-60`

### S-ESC-006

- **routines:** escalate_os
- **claim:** When the ticket's host exists and is INACTIVE (`mss.host.active = 0`),
  `escalate_os` does nothing: no `UPDATE`, no event, no exception — it simply falls off
  the `IF` (line 75) and returns. This is the body header's stated rule: "The ticket is
  not escalated if the host is inactive, that means if mss.host.active is 0."
- **source:** `ddl/src/pkgb/tt_escalation_interface.sql:10, 60, 75-77`

### S-ESC-007

- **routines:** escalate_os
- **claim:** Any escalation status OTHER than 10/11 — including 0 ("no escalation")
  and 20 ("escalation to customer") — passes the S-ESC-003 gate: a ticket marked for
  customer escalation is overridden to OS escalation (status 10 + 60001 event) by
  `escalate_os`. This implements header measure 8 ("If a deferred ticket marked for
  escalation to customer gets hot again, it will be marked for escalation to os").
- **source:** `ddl/src/pkgb/tt_escalation_interface.sql:55, 65`, `ddl/src/pkg/tt_escalation_interface.sql:86-87`

### S-ESC-008

- **routines:** escalate_os
- **claim:** **CORRECTED BEHAVIOUR (Oracle defect).** If `p_event_id` names no
  `tt.event` row, or the event's ticket cannot be found, `escalate_os` logs an error via
  `plog.err` and `RETURN`s with NO side effects: no `tt.ticket` row is updated, no
  `addevent_new` call is made, and no exception propagates to the caller. *Oracle's
  actual behaviour, and why it is a defect:* site (a) (line 27) raises `NO_DATA_FOUND`
  for a nonexistent event; the shared handler (lines 45-48) only nulls `v_host_id` and
  does NOT return, so execution continues with `v_ticket_id`,
  `v_escalation_status_id`, `v_host_active` all `NULL`. Line 55's `IN (10,11)` test is
  `NULL` (not true), line 60's `v_host_id IS NULL` is TRUE, so Oracle runs `UPDATE
  tt.ticket ... WHERE id = NULL` (zero rows, line 65) and then calls
  `addevent_new(v_event_id, NULL, 60001, NULL, ...)` (lines 68-73) — whose own first
  `SELECT ... FROM tt.ticket WHERE t.id = NULL` raises `NO_DATA_FOUND`, swallowed and
  logged as "unknown error for ticket:" by `addevent_new`'s outer `WHEN OTHERS`
  (`ddl/src/pkgb/tt_event_interface.sql:825-827`). Net Oracle effect: an "escalation"
  of nothing, surfacing only as a misleading `addevent_new` error log. (Note
  `tt.event.ticket_id` is `NOT NULL` in both the Oracle export and the migrated
  schema, so "event exists but ticket_id is NULL" is structurally unreachable; the
  reachable defect paths are "event missing" and "ticket row missing" — the latter only
  under deferred FK checking.) The correction keeps S-ESC-005's "host not found → treat
  as no host → escalate anyway" semantics untouched: only sites (a)-(c) trigger the
  early return, site (d) keeps Oracle's `v_host_id := NULL` handling. The error text
  follows the package's own `escalate_isp_outage_to_os` wording (line 175):
  `'tt.escalation_interface.escalate_os(): event with id ' || p_event_id || ' or its
  ticket not found. This is needed for escalation. Aborting escalation.'`. The
  `plog.debug('escalate_to_os called for event id ' || p_event_id)` on line 23 still
  fires first (it precedes the lookup block).
- **source:** `ddl/src/pkgb/tt_escalation_interface.sql:23, 27-29, 45-48, 55, 60, 65-73, 175`, `ddl/src/pkgb/tt_event_interface.sql:825-827`

### S-ESC-009

- **routines:** escalate_os, escalate_customer
- **claim:** Neither `escalate_os` nor `escalate_customer` has an exception handler
  around its `event_interface.addevent_new` call (the only `EXCEPTION` block in either
  routine is the lookup block, lines 45-48 / 114-117). `addevent_new` re-raises exactly
  one condition — `EVENT_INTERFACE_STATE.ticket_closed` (`RAISE_APPLICATION_ERROR(-20980)`
  for a ticket with `status_id > 101`, `ddl/src/pkgb/tt_event_interface.sql:609-611,
  823-824`) — and that error therefore propagates OUT of `escalate_os` /
  `escalate_customer` to their caller, AFTER the `UPDATE` on line 65 / 127 has already
  executed. (When the caller is `exec_event_type_actions`, its own `WHEN OTHERS`
  around the dynamic call, `ddl/src/pkgb/tt_event_interface.sql:973-974`, swallows and
  logs it.) All OTHER internal `addevent_new` failures are swallowed inside
  `addevent_new` itself and never reach this package.
- **source:** `ddl/src/pkgb/tt_escalation_interface.sql:45-48, 65-77, 114-117, 127-139`, `ddl/src/pkgb/tt_event_interface.sql:609-611, 823-827, 973-974`

### S-ESC-010

- **routines:** escalate_customer
- **claim:** `escalate_customer` resolves its inputs with THREE `SELECT ... INTO`
  statements under one shared `WHEN NO_DATA_FOUND THEN v_host_id := NULL` handler:
  (a) `tt.event.ticket_id` by `e.id = p_event_id` (line 98); (b)
  `tt.ticket.escalation_status_id, host_id` in ONE select by `t.id = v_ticket_id`
  (line 104); (c) `mss.host.active` by `h.id = v_host_id` (line 110). All PK-keyed;
  `TOO_MANY_ROWS` structurally impossible. Same shared-handler semantics as S-ESC-002.
- **source:** `ddl/src/pkgb/tt_escalation_interface.sql:96-117`

### S-ESC-011

- **routines:** escalate_customer
- **claim:** `escalate_customer` `RETURN`s with no side effects if the ticket's
  `escalation_status_id <> 0` — i.e. for ANY escalation already in progress (10, 11 AND
  20), per the comment "we only escalate to a customer if there is no other escalation
  in process". This is STRICTER than `escalate_os`'s gate (S-ESC-003/007): status 20
  blocks `escalate_customer` but not `escalate_os`. (The comparison is NULL-unsafe in
  Oracle — `NULL <> 0` is not true — but `tt.ticket.escalation_status_id` is `NOT NULL
  DEFAULT 0`, so a `NULL` here only arises on the S-ESC-014 defect path.)
- **source:** `ddl/src/pkgb/tt_escalation_interface.sql:119-123`

### S-ESC-012

- **routines:** escalate_customer
- **claim:** When the ticket is in escalation status 0 and its host is active OR
  `NULL` (same `v_host_active = 1 OR v_host_id IS NULL` shape as S-ESC-005),
  `escalate_customer` runs `UPDATE tt.ticket SET escalation_status_id = 10,
  last_escalation_date = SYSDATE WHERE ticket.id = v_ticket_id AND
  escalation_status_id <> 10` (the race guard of header measure 4), and ONLY IF
  `SQL%ROWCOUNT > 0` calls `addevent_new(v_event_id OUT, v_ticket_id, 60001, v_host_id,
  'Starting escalation to Open Systems Mission Control', 'Event added by
  tt.escalation_interface.escalate_customer. Caused by event ' || p_event_id)`.
  **Documentation/body mismatch, recorded, NOT "fixed":** the package spec comment
  (`pkg:22-32`) and the body's section header (`pkgb:82-84`) describe a CUSTOMER
  escalation (event 60101 / status 20, picked up by the Securitas wizard), but the
  BODY writes status **10** and event type **60001** — an escalation to OS, identical
  in effect to `escalate_os`. The body is authoritative; the translation and tests
  assert 10 / 60001.
- **source:** `ddl/src/pkgb/tt_escalation_interface.sql:82-84, 125-138`, `ddl/src/pkg/tt_escalation_interface.sql:22-32, 79-81`

### S-ESC-013

- **routines:** escalate_customer
- **claim:** When the ticket's host exists and is inactive (`mss.host.active = 0`),
  `escalate_customer` does nothing (no `UPDATE`, no event, no exception) — same rule as
  S-ESC-006.
- **source:** `ddl/src/pkgb/tt_escalation_interface.sql:126, 138-139`

### S-ESC-014

- **routines:** escalate_customer
- **claim:** **CORRECTED BEHAVIOUR (Oracle defect, same shape as S-ESC-008).** If
  `p_event_id` names no `tt.event` row, or the event's ticket cannot be found,
  `escalate_customer` logs an error via `plog.err` and `RETURN`s with no side effects
  and no exception. *Oracle's actual behaviour:* site (a) (line 98) raises
  `NO_DATA_FOUND`; the shared handler (lines 114-117) nulls `v_host_id` and continues;
  line 121's `NULL <> 0` is not true so the gate does not fire; line 126's `v_host_id
  IS NULL` is true; the `UPDATE ... WHERE ticket.id = NULL` (line 127) touches zero
  rows, so `SQL%ROWCOUNT = 0` and line 130 skips `addevent_new`. Net Oracle effect: a
  completely SILENT no-op — no log, no error, nothing — for a request to escalate an
  event that does not exist. The correction changes no data-side effect (there were
  none) but makes the failure observable (`plog.err`) instead of silent. Error text,
  same wording as S-ESC-008 / line 175: `'tt.escalation_interface.escalate_customer():
  event with id ' || p_event_id || ' or its ticket not found. This is needed for
  escalation. Aborting escalation.'`. `escalate_customer` has no `plog.debug` lines
  at all (lines 94-139), so this is its only log output on that path.
- **source:** `ddl/src/pkgb/tt_escalation_interface.sql:94, 98-100, 114-117, 121, 126-130, 175`

### S-ESC-015

- **routines:** escalate_isp_outage_to_os
- **claim:** `escalate_isp_outage_to_os`'s ONLY lookup is a single six-table
  `SELECT h.name, COALESCE(ec.short, tc.SHORT, sc.SHORT), t.id INTO v_host_name,
  v_company_short, v_ticket_id` joining: `tt.event e` (`e.id = p_event_id`) INNER to
  `tt.ticket t` (`e.ticket_id = t.id`); INNER to `mss.host h` on
  `h.id = NVL(e.host_id, t.host_id)` (the event's own host if set, else the ticket's);
  INNER to `stop.company sc` on `h.service_company_id = sc.id`; and OUTER (`(+)`) to
  `stop.company ec` on `e.company_id` and `stop.company tc` on `t.company_id`. The
  company short name is therefore taken from the event's company first, then the
  ticket's, then the host's service company. All join keys are PKs, so the query
  yields at most one row (`TOO_MANY_ROWS` impossible).
- **source:** `ddl/src/pkgb/tt_escalation_interface.sql:160-171`

### S-ESC-016

- **routines:** escalate_isp_outage_to_os
- **claim:** If the S-ESC-015 join yields no row (`NO_DATA_FOUND`) — reachable when the
  event does not exist, when neither the event nor its ticket has a host, when the host
  row is missing, or when the host's service company is missing — the routine logs
  `c_prefix || 'either ticket, host or company not found for event with id: ' ||
  p_event_id || ' This is needed for escalation. Aborting escalation.'` via `plog.err`
  and `RETURN`s: no ticket is created, no exception propagates. Any OTHER error in that
  select (`WHEN OTHERS`) is likewise logged (`'Error while retrieving company and host
  name for event with id: '...`) and swallowed with a `RETURN`.
- **source:** `ddl/src/pkgb/tt_escalation_interface.sql:173-180`

### S-ESC-017

- **routines:** escalate_isp_outage_to_os
- **claim:** After the handled block, `SELECT eventdate INTO v_org_event_date FROM
  event WHERE id = p_event_id` (line 182) runs OUTSIDE any handler. Because the
  S-ESC-015 select has just proven that exact `tt.event` row exists (inner join on
  `e.id = p_event_id`), `NO_DATA_FOUND` here is unreachable short of a concurrent
  delete between the two statements; `TOO_MANY_ROWS` is impossible (PK). The
  unqualified `event` resolves to `tt.event` (package owner schema). Translation:
  `STRICT`, no handler, no message shim (not an externally reachable error site).
- **source:** `ddl/src/pkgb/tt_escalation_interface.sql:182`

### S-ESC-018

- **routines:** escalate_isp_outage_to_os
- **claim:** The public description is composed, with `CHR(10)` line breaks, as:
  `'Critical ISP Outage escalation'`, `'Host: ' || v_host_name`, `'Company: ' ||
  v_company_short`, `'Time of original event: ' || TO_CHAR(v_org_event_date,
  'YYYY-MM-DD HH24:MI:SS')`, `'Original ticket ' || v_ticket_id`. The private
  description is `'To Do:'`, the wiki URL
  `https://open-systems.atlassian.net/wiki/x/3xYBAQ`, a blank line, `'Do not add any
  further events to this escalation ticket.'`, `'Use the original ticket ' ||
  v_ticket_id || ' for tracking any work!'`, `'This ticket is intentionally hidden from
  the customer, so do not merge it. '`. **Ordering is load-bearing:** both strings are
  built (lines 184-194) BEFORE `v_ticket_id` is reused as the OUT parameter of
  `newticket_new` (line 199), so the ticket id in both texts is the ORIGINAL ticket's
  id, never the new ticket's. **NULL-concatenation (Pitfall 2):** `stop.company.short`
  is nullable, so `v_company_short` can be `NULL` (every company in the COALESCE chain
  having a `NULL` short); Oracle's `'Company: ' || NULL` yields `'Company: '` and the
  rest of the text survives — the translation must preserve that (PostgreSQL's `||`
  would null out the entire string).
- **source:** `ddl/src/pkgb/tt_escalation_interface.sql:184-194, 199`

### S-ESC-019

- **routines:** escalate_isp_outage_to_os
- **claim:** `escalate_isp_outage_to_os` opens the escalation ticket via
  `tt.ticket_interface.newticket_new(v_ticket_id OUT, v_event_id OUT, 1, 'Critical ISP
  Outage escalation', 30005, NULL, v_public_details, v_private_details, NULL, NULL,
  TRUE, SYSDATE, NULL, 27)` — i.e. ticket type 1 (trouble ticket), subject `'Critical
  ISP Outage escalation'`, first event of type 30005 (incident report), NO host, NO
  contact, NO worker, public event, NO company (per the comment: "this ticket does not
  have the company set to hide it from the customer"), service component 27 ("other").
  The new ticket's and event's ids are returned into `v_ticket_id` / `v_event_id` and
  not used afterwards. The ORIGINAL ticket is not modified by this routine at all.
- **source:** `ddl/src/pkgb/tt_escalation_interface.sql:196-201`

### S-ESC-020

- **routines:** nop
- **claim:** `nop` has no side effects whatsoever (`NULL;` body) and accepts ANY
  `p_event_id`, including one that names no event — it never reads the database and
  never raises.
- **source:** `ddl/src/pkgb/tt_escalation_interface.sql:208-213`

### S-ESC-021

- **routines:** clear_customer_escalation
- **claim:** `clear_customer_escalation` executes exactly one statement: `UPDATE
  tt.ticket SET escalation_status_id = 0 WHERE id = p_ticket_id AND
  escalation_status_id = 20`. A ticket in status 20 is reset to 0; a ticket in any
  other escalation status (0, 10, 11) is left untouched (header measure 5: "ensures
  that the update statement does not clear an escalation to os"); a nonexistent
  `p_ticket_id` updates zero rows and raises nothing. No `last_escalation_date` or any
  other column is changed.
- **source:** `ddl/src/pkgb/tt_escalation_interface.sql:215-220`, `ddl/src/pkg/tt_escalation_interface.sql:82-83`

### S-ESC-022

- **routines:** escalate_os
- **claim:** **End-to-end dynamic dispatch.** `escalate_os` is the configured
  `procedure_name` of `tt.event_action` id 1 (`masterdata/TT/event_action.csv`). When
  `tt.event_type_action` maps an event type to action 1 and
  `TT.EVENT_INTERFACE.exec_event_type_actions(p_event_id)` is called for an event of
  that type (with no active escalation-suppressing service window), the cursor loop
  resolves `v_proc_str = 'tt.escalation_interface.escalate_os'` (no `procedure_key_id`
  on action 1, so the DBPROP branch is skipped and the column value is used, lines
  951-961) and executes `call tt.escalation_interface.escalate_os(:eventid)` with
  `p_event_id` bound (lines 969-971). The observable result for an eligible ticket
  (status 0, active or NULL host) is exactly S-ESC-004: `escalation_status_id = 10`
  and a new 60001 event on the ticket. (The 60001 event itself goes through
  `addevent_new` → `exec_event_type_actions` again; 60001 has no configured action, so
  the recursion terminates.)
- **source:** `ddl/src/pkgb/tt_event_interface.sql:902-906, 951-971`, `ddl/src/pkgb/tt_escalation_interface.sql:60-75`

## Checklist

### 1. Empty-string / NULL handling

No routine declares a `VARCHAR2`/`CLOB` parameter (all five signatures:
`ddl/src/pkg/tt_escalation_interface.sql:20,32,42,50,60` — four `NUMBER`, one
`tt.ticket.id%TYPE`), so `''` can never ARRIVE from a caller. The `VARCHAR2` locals and
`||` sites that exist:

- `escalate_os` / `escalate_customer`: `'... Caused by event ' || p_event_id` (lines 73,
  135) — numeric operand, never `''`/`NULL` by the time it is reached (S-ESC-008/014
  return earlier when the event is missing). The `plog.debug('ticket id is ' ||
  v_ticket_id)` / `'host id is ' || v_host_id` lines (50-51, 61) CAN see a `NULL`
  `v_host_id` (S-ESC-005): Oracle logs `'host id is '`, PostgreSQL's `||` would log
  `NULL`. Log text only — translation uses `concat()`-style NULL-tolerant
  concatenation there so the debug line stays readable; no behavioural claim.
- `escalate_isp_outage_to_os`: `v_host_name` (`mss.host.name`, `NOT NULL`),
  `v_company_short` (nullable `stop.company.short` through `COALESCE`, line 163),
  `v_org_event_date` (`tt.event.eventdate`, `NOT NULL`) are concatenated into
  `v_public_details` (lines 184-188); `v_ticket_id` (`NOT NULL` PK) into both texts
  (188, 193). The ONE site where `NULL` is reachable is `'Company: ' ||
  v_company_short` — covered by S-ESC-018: the translation must not let PostgreSQL's
  NULL-propagating `||` erase the whole description. No `IS NULL`/`=`/`<>` check is
  ever made against a string in this package; `''` vs `NULL` therefore changes no
  branch anywhere. Decision: `concat()`/`COALESCE(x, '')` at the concatenation sites
  only; no boundary `NULLIF` needed (nothing string-typed crosses the boundary).

### 2. SELECT INTO strictness

Nine `SELECT ... INTO` sites, matching the Phase 1 inventory's `select_into_sites`
`[27, 32, 35, 41, 98, 104, 110, 163, 182]` exactly:

| # | line | routine | zero rows possible? | >1 row possible? | Oracle handler | translation |
|---|---|---|---|---|---|---|
| 1 | 27 | escalate_os | yes (bad event id) | no (PK) | shared `WHEN NO_DATA_FOUND` lines 45-48 (nulls `v_host_id`, continues — the S-ESC-008 defect) | `STRICT`; local `NO_DATA_FOUND` → `plog.err` + `RETURN` (corrected) |
| 2 | 32 | escalate_os | only via deferred FK | no (PK) | same shared handler | same corrected handler as #1 |
| 3 | 35 | escalate_os | only via deferred FK | no (PK) | same shared handler | same corrected handler as #1 |
| 4 | 41 | escalate_os | yes (`host_id` NULL or missing host) | no (PK) | same shared handler → `v_host_id := NULL` (intended, S-ESC-005) | `STRICT`; own `NO_DATA_FOUND` → `v_host_id := NULL` |
| 5 | 98 | escalate_customer | yes (bad event id) | no (PK) | shared `WHEN NO_DATA_FOUND` lines 114-117 (S-ESC-014 defect) | `STRICT`; local `NO_DATA_FOUND` → `plog.err` + `RETURN` (corrected) |
| 6 | 104 | escalate_customer | only via deferred FK | no (PK) | same shared handler | same corrected handler as #5 |
| 7 | 110 | escalate_customer | yes (`host_id` NULL or missing host) | no (PK) | same shared handler → `v_host_id := NULL` (intended) | `STRICT`; own `NO_DATA_FOUND` → `v_host_id := NULL` |
| 8 | 163 | escalate_isp_outage_to_os | yes (S-ESC-016 cases) | no (all PK joins) | local `NO_DATA_FOUND` → log + `RETURN`; `OTHERS` → log + `RETURN` (lines 173-180) | `STRICT` + same two-arm handler |
| 9 | 182 | escalate_isp_outage_to_os | practically no (S-ESC-017) | no (PK) | none at any scope | `STRICT`, no handler, no shim |

Inventory cross-check: `exception_handlers: NO_DATA_FOUND 3, TOO_MANY_ROWS 0, OTHERS 1`
— confirmed by reading the body (lines 46, 115, 174, 177). No `TOO_MANY_ROWS` handler
is needed anywhere: every site is PK-keyed.

### 3. Exception codes

No `RAISE_APPLICATION_ERROR` call, no named exception declared or raised, and no bare
`RAISE` anywhere in the package (full 223-line body read; inventory
`raise_application_error: []`). The two `WHEN OTHERS` (line 177) / `WHEN NO_DATA_FOUND`
(lines 46, 115, 174) arms all SWALLOW. The only error that can leave this package is
one it does not raise itself: `EVENT_INTERFACE_STATE.ticket_closed` (Oracle `-20980`,
`ddl/src/pkgb/tt_event_interface.sql:611`), re-raised by `addevent_new` and propagating
unhandled through `escalate_os`/`escalate_customer` (S-ESC-009). Its PostgreSQL SQLSTATE
is whatever `TT.EVENT_INTERFACE`'s translation assigned (`OS980`, **PROVISIONAL**
pending XCUT-01) — this package neither maps nor re-maps it. The corrected early
returns (S-ESC-008/014) raise nothing. Nothing for XCUT-01 to map here.

### 4. Package state

None. The package spec declares `TYPE ref_cursor IS REF CURSOR`
(`ddl/src/pkg/tt_escalation_interface.sql:10`), a type with no state, never referenced
by any routine (confirmed by grepping the body). The body has NO declare section — line
3 (`CREATE OR REPLACE PACKAGE BODY ... IS`) is followed directly by the `escalate_os`
section comment and `PROCEDURE escalate_os` (lines 4-12) — and no trailing
initialization block (file ends `END escalation_interface;` at line 222). Matches the
inventory's `package_state: []`, `has_init_block: false`.

### 5. FUNCTION vs PROCEDURE

All five routines are `PROCEDURE` (`ddl/src/pkg/tt_escalation_interface.sql:20,32,42,
50,60`); `name-map.csv` says `pg_kind=procedure` for all five. No `COMMIT`, `ROLLBACK`
or `PRAGMA AUTONOMOUS_TRANSACTION` exists in the body (inventory `has_commit: false`,
`has_rollback: false`, `autonomous_transaction: false`; confirmed by reading). Callers:
`exec_event_type_actions` (a `PROCEDURE`, `ddl/src/pkgb/tt_event_interface.sql:894`)
via dynamic `call ...` (line 969-971), and `MC.MONITORING_TICKET_PROCESSES.new_event_up`
(a `PROCEDURE`, `ddl/src/pkgb/mc_monitoring_ticket_processes.sql:83`) statically at line
132. Callees: `event_interface.addevent_new` and `tt.ticket_interface.newticket_new`,
both `PROCEDURE`s with leading `OUT` parameters — so the PostgreSQL call shape is `CALL
tt.event_interface_addevent_new(v_event_id, ...)` / `CALL
tt.ticket_interface_newticket_new(v_ticket_id, v_event_id, ...)`, OUT variables first,
and these procedures MUST themselves stay `PROCEDURE`s (a `CALL` from a FUNCTION body
is fine as long as nobody in the chain commits — nobody here does). Because this package
is reached ONLY by `CALL` (dynamic `EXECUTE format('CALL %I.%I($1)')` in
`exec_event_type_actions`, static `CALL` in `mc.monitoring`), `procedure` is the only
`pg_kind` that works for the dispatch path at all. No XCUT-04 collision.

## Assumptions / Unresolved

- **Deviation from Oracle is intentional at S-ESC-008 and S-ESC-014** (and nowhere
  else). Both are "event/ticket cannot be resolved → `plog.err` + `RETURN`" corrections
  of an Oracle body that otherwise escalates nothing silently (traced line by line in
  the clauses). The S-ESC-005 "missing host → escalate without host" behaviour is
  deliberately NOT treated as a defect: the inline comment on line 59 states it is
  intended. The translation must mark both corrected sites `-- DEVIATION(ORACLE-BUG)`.
- **Transaction-scope delta on the S-ESC-009 path, not resolved here.** In Oracle, when
  `ticket_closed` propagates out of `escalate_os` into `exec_event_type_actions`'s
  swallowing `WHEN OTHERS`, the line-65 `UPDATE` (status := 10) is NOT undone — Oracle
  only rolls back the failing statement. In PL/pgSQL, a `BEGIN ... EXCEPTION` block is a
  subtransaction: when `exec_event_type_actions` catches the error, everything the
  dynamic `CALL` did (including that `UPDATE`) is rolled back. So a closed ticket ends
  with `escalation_status_id = 10` in Oracle and `0` in PostgreSQL. Reachable only for
  a ticket that is simultaneously closed (`status_id > 101`) and receiving an
  escalation-triggering event — arguably the PostgreSQL outcome is the saner one, but
  this spec does not decide; it is recorded for XCUT-05 and is NOT asserted by any test
  of this package.
- **`escalate_customer`'s name/comment vs body mismatch (S-ESC-012)** cannot be
  resolved from static source: whether the body was deliberately changed to escalate to
  OS (plausible — the header's "measure 8" says customer-escalated tickets that get hot
  again go to OS) or the comments were simply never updated is unknowable without the
  authors. The BODY is treated as authoritative per the project's standing rule.
- **Service-window suppression on the dispatch path (S-ESC-022)** is
  `TT.EVENT_INTERFACE`'s concern (`is_esc_supp_active`, only consulted for event types
  10002/10005/10007/10009): the end-to-end test uses a pilot-owned event type outside
  that set, so suppression never engages. Not a claim about this package.
- **`tt.event_type_action` is EMPTY in `masterdata/`** (`masterdata/TT/` has no
  event_type_action rows loaded into the template), so in a fresh container NOTHING is
  dispatched to this package until an operator maps event types to action 1. Whether
  production maps 30005 (the incident-report event this package's own
  `escalate_isp_outage_to_os` creates, per the pkg comment "which is then
  automatically escalated", `ddl/src/pkg/tt_escalation_interface.sql:38`) to action 1
  cannot be known from the repo; the S-ESC-019 test therefore asserts only what
  `newticket_new` itself does, not a second-order escalation of the new ticket.
- Nothing else is unresolved: all nine `SELECT INTO` sites, all four handler arms, both
  `addevent_new` call sites, the `newticket_new` call, the (absent) declare section, and
  both static callers were reviewed against the full text of
  `ddl/src/pkg/tt_escalation_interface.sql`, `ddl/src/pkgb/tt_escalation_interface.sql`,
  the relevant sections of `ddl/src/pkgb/tt_event_interface.sql` (lines 519-828,
  894-975) and `ddl/src/pkgb/mc_monitoring_ticket_processes.sql` (line 132), and the
  Oracle `TT.EVENT`/`TT.TICKET` DDL in `ddl/export/schema.oracle.sql` (lines 130, 200)
  for the `NOT NULL` facts cited above.
