---
oracle_schema: TT
oracle_package: OSAG_NOTIFY
pg_schema: tt
pg_prefix: osag_notify
clause_prefix: NOTIFY
oracle_spec: ddl/src/pkg/tt_osag_notify.sql
oracle_body: ddl/src/pkgb/tt_osag_notify.sql
public_routines: 6
---

# TT.OSAG_NOTIFY — PostgreSQL spec

Sends ticket-system notifications (email, SMS) to registered listeners
(`tt.event_notification`), local emergency contacts, and ISP support contacts, and
manages the housekeeping around notifications (deletion on login/ticket removal,
service-window suppression). Per its header comment (`ddl/src/pkgb/tt_osag_notify.sql:6-11`)
it replaces the older `tt.notify` package (2008). It is a **transitive dependency** of
the pilot, not one of the four user-named packages, but three of the four call it —
`AUTH.OSAG_AUTH` (call site 25), `TT.EVENT_INTERFACE` (call sites 504, 747, 1099),
`TT.TICKET_INTERFACE` (call sites 234, 497, 1700) — and `TT.UTIL` also calls it (call
site 29, `check_resolved_tickets` deleting notifications on ticket close), per
`migration/analyze/depgraph.json`'s edges into `TT.OSAG_NOTIFY`.

**This package is the pilot's SELECT INTO proving ground: 30 `SELECT ... INTO` sites**
(the richest concentration in the pilot dependency set) **and the pilot's only
`TOO_MANY_ROWS` handler** (S-NOTIFY-031). See the `### SELECT INTO strictness` table
under Checklist dimension 2 for the full per-site enumeration.

**A second, equally important structural fact, found while tracing every exception
handler for this spec: every one of the 11 `WHEN OTHERS` handlers in this package
SWALLOWS (logs, or does nothing, but never re-raises).** There is not one
`RAISE`/`RAISE_APPLICATION_ERROR` anywhere in `ddl/src/pkgb/tt_osag_notify.sql` (grep
confirmed: zero matches). This package's own top-level handler in its flagship public
routine, `event_notify` (S-NOTIFY-001), means that from `event_notify`'s caller's point
of view, **no internal `SELECT INTO` failure — NO_DATA_FOUND, TOO_MANY_ROWS, or
anything else — is ever observable as a caller-visible exception.** `event_notify`
always returns normally; failures are logged and silently absorbed. This has a direct
translation consequence: a PL/pgSQL `tt.osag_notify_event_notify` that (correctly)
adds `STRICT` everywhere but forgets to wrap the whole body in an outer
`EXCEPTION WHEN OTHERS` block would start raising errors to ticket-update transactions
that Oracle never did — this is exactly the kind of divergence Pitfall 1 warns about,
and it bites hardest at the routine most callers actually invoke.

## Routines

### event_notify (PUBLIC)

- **Oracle signature:** `PROCEDURE event_notify(p_event_id NUMBER, p_ticket_id NUMBER DEFAULT NULL, p_question VARCHAR2 DEFAULT NULL)`
- **PostgreSQL name:** `tt.osag_notify_event_notify` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/tt_osag_notify.sql:27`
- **Defined:** `ddl/src/pkgb/tt_osag_notify.sql:278-759`
- The package's flagship entry point: resolves the event/ticket/host/service context,
  determines whether notifications are suppressed by an active service window,
  dispatches ISP and local-contact notifications for connectivity events, composes SMS
  and email messages, iterates three separate notification-recipient cursors
  (non-service customers, service-scoped customers, OSAG staff), calls the private
  `send_notification_by_type` per matching row, and finally bumps two independent
  notify-count columns with a "limit reached" ticket event once each hits 5. **Every
  exception anywhere in this ~480-line body is caught by its own top-level
  `WHEN OTHERS` (line 754-758), logged via `plog.warning`, and swallowed — this
  procedure never raises to its caller** (S-NOTIFY-001).

### send_test_notification (PUBLIC)

- **Oracle signature:** `PROCEDURE send_test_notification(p_destination_address VARCHAR2, p_notification_type_id NUMBER, p_ticket_id NUMBER, p_ticket_subject VARCHAR2, p_host_name VARCHAR2, p_event_type_id NUMBER, p_eventdate TIMESTAMP WITH TIME ZONE, p_contact_last_name VARCHAR2 DEFAULT NULL, p_contact_first_name VARCHAR2 DEFAULT NULL)`
- **PostgreSQL name:** `tt.osag_notify_send_test_notification` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/tt_osag_notify.sql:51`
- **Defined:** `ddl/src/pkgb/tt_osag_notify.sql:764-844`
- Sends a manually-triggered test SMS (`p_notification_type_id=1`) or test email
  (`=2`) to a caller-specified destination address, prefixed with a "THIS IS ONLY A
  TEST" banner. **Has NO exception handler of any kind — the only one of the six
  public routines with no safety net at all** (S-NOTIFY-018). This is the pilot's
  primary reachable "STRICT, unhandled" test target.

### delete_notifications_for_login (PUBLIC)

- **Oracle signature:** `PROCEDURE delete_notifications_for_login(p_login_id NUMBER)`
- **PostgreSQL name:** `tt.osag_notify_delete_notifications_for_login` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/tt_osag_notify.sql:73`
- **Defined:** `ddl/src/pkgb/tt_osag_notify.sql:849-869`
- Cursor-loops over every distinct ticket that has a notification for this login,
  delegating each to `delete_ticket_notifications` (with a fixed suffix, "because the
  user was deleted"), then bulk-deletes any remaining (non-ticket) notifications for
  the login in one `DELETE`. Zero matching tickets is a normal empty-loop outcome, not
  an exception (S-NOTIFY-019) — this routine itself has no `EXCEPTION` block.

### delete_ticket_notifications (PUBLIC)

- **Oracle signature:** `PROCEDURE delete_ticket_notifications(p_ticket_id NUMBER, p_login_id NUMBER DEFAULT NULL, p_event_details_suffix VARCHAR DEFAULT NULL)`
- **PostgreSQL name:** `tt.osag_notify_delete_ticket_notifications` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/tt_osag_notify.sql:91`
- **Defined:** `ddl/src/pkgb/tt_osag_notify.sql:874-937`
- Cursor-loops over the ticket's (optionally login-scoped) notifications, building a
  public/private details string describing which notifications were deleted (routed
  by whether the notified login is an OSAG login viewing a non-OSAG ticket), deleting
  each `tt.event_notification` row, then — if any details text was built — records a
  ticket history event via `TT.TICKET_INTERFACE.change_notification`. **Has its own
  top-level `WHEN OTHERS` (line 932-935) that swallows and logs — same shape as
  `event_notify`'s.** Contains a genuine NULL/`''` concatenation hazard
  (S-NOTIFY-020) that is this package's best example of Pitfall 2 outside
  `format_customer_reference`.

### add_notification_event (PUBLIC)

- **Oracle signature:** `PROCEDURE add_notification_event(p_ticket_id NUMBER, p_event_type_id NUMBER, p_text VARCHAR2, p_contact_id NUMBER, p_peer_contact_id NUMBER DEFAULT NULL, p_is_public_event DECIMAL DEFAULT 1)`
- **PostgreSQL name:** `tt.osag_notify_add_notification_event` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/tt_osag_notify.sql:108`
- **Defined:** `ddl/src/pkgb/tt_osag_notify.sql:942-974`
- Pure `INSERT` into `tt.event`, routing `p_text` to `details_public` or
  `details_private` by `p_is_public_event`. **No `SELECT ... INTO` at all** — the only
  public routine with zero SELECT INTO sites. No exception handler; any `INSERT`
  failure (e.g. an FK violation on `p_contact_id`/`p_ticket_id`/`p_peer_contact_id`)
  propagates fully unhandled to the caller (S-NOTIFY-022).

### is_notify_suppressor_active (PUBLIC, FUNCTION)

- **Oracle signature:** `FUNCTION is_notify_suppressor_active(p_host_id NUMBER) RETURN BOOLEAN`
- **PostgreSQL name:** `tt.osag_notify_is_notify_suppressor_active` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/tt_osag_notify.sql:125`
- **Defined:** `ddl/src/pkgb/tt_osag_notify.sql:979-1008`
- Returns `TRUE` if the given host currently has an active service window with
  `disable_notification` set, via a `SELECT COUNT(*) INTO` aggregate — always exactly
  one row, so **this is the package's one clean "no STRICT concern" site**
  (S-NOTIFY-023). The only `FUNCTION` (returns `BOOLEAN`) among the six public
  routines; all others are `PROCEDURE`s.

## Private routines — naming convention (design decision, Phase 4-relevant)

**13 private routines**, matching the Phase 1 inventory count exactly (confirmed by
reading the full 1844-line body and counting every declaration below the
`-- private procedures and functions` marker at `ddl/src/pkgb/tt_osag_notify.sql:1012`).
None has a `name-map.csv` row (by design — that SSOT covers public routines only).

**Convention chosen: (a) schema-level function with a `__` (double-underscore) marker
prefix, `REVOKE ALL ... FROM PUBLIC`**, per the plan's recommendation. Thirteen private
routines is too many to inline into their six callers without destroying readability,
and this exact situation (public package interface hiding a private implementation
namespace with no native PostgreSQL equivalent) recurs in every one of the remaining
44 packages Phase 4 will translate — so the convention set here is offered as the
corpus-wide default, **not a decision this spec is authorized to finalize**: it lives
outside `migration/mapping/name-map.csv`, which is exactly the kind of invented-name
drift `migration/README.md`'s consumer contract warns against. Flagged loudly again in
this plan's SUMMARY as a Phase 4 (and possibly name-map-generator) decision.

| Oracle (private) | Proposed PostgreSQL name | Declared | Defined |
|---|---|---|---|
| `send_notification_by_type` | `tt.osag_notify__send_notification_by_type` | `ddl/src/pkgb/tt_osag_notify.sql:22-32` | `ddl/src/pkgb/tt_osag_notify.sql:1019-1118` |
| `compose_email_msg` | `tt.osag_notify__compose_email_msg` | `ddl/src/pkgb/tt_osag_notify.sql:59-74` | `ddl/src/pkgb/tt_osag_notify.sql:1123-1225` |
| `compose_sms_msg` | `tt.osag_notify__compose_sms_msg` | `ddl/src/pkgb/tt_osag_notify.sql:92-99` | `ddl/src/pkgb/tt_osag_notify.sql:1230-1292` |
| `notify_local_contacts` | `tt.osag_notify__notify_local_contacts` | `ddl/src/pkgb/tt_osag_notify.sql:122-133` | `ddl/src/pkgb/tt_osag_notify.sql:1297-1382` |
| `compose_local_contact_message` | `tt.osag_notify__compose_local_contact_message` | `ddl/src/pkgb/tt_osag_notify.sql:148-151` | `ddl/src/pkgb/tt_osag_notify.sql:1387-1403` |
| `notify_isp` | `tt.osag_notify__notify_isp` | `ddl/src/pkgb/tt_osag_notify.sql:168-173` | `ddl/src/pkgb/tt_osag_notify.sql:1408-1481` |
| `get_isp_link_id_for_host_id` | `tt.osag_notify__get_isp_link_id_for_host_id` | `ddl/src/pkgb/tt_osag_notify.sql:184` | `ddl/src/pkgb/tt_osag_notify.sql:1486-1517` |
| `get_message_for_isp_outage` | `tt.osag_notify__get_message_for_isp_outage` | `ddl/src/pkgb/tt_osag_notify.sql:201-206` | `ddl/src/pkgb/tt_osag_notify.sql:1522-1679` |
| `get_message_for_connection_up` | `tt.osag_notify__get_message_for_connection_up` | `ddl/src/pkgb/tt_osag_notify.sql:223-228` | `ddl/src/pkgb/tt_osag_notify.sql:1684-1785` |
| `format_customer_reference` | `tt.osag_notify__format_customer_reference` | `ddl/src/pkgb/tt_osag_notify.sql:240` | `ddl/src/pkgb/tt_osag_notify.sql:1790-1800` |
| `get_notification_type_name` | `tt.osag_notify__get_notification_type_name` | `ddl/src/pkgb/tt_osag_notify.sql:252-253` | `ddl/src/pkgb/tt_osag_notify.sql:1805-1812` |
| `email_footer` | `tt.osag_notify__email_footer` | `ddl/src/pkgb/tt_osag_notify.sql:264` | `ddl/src/pkgb/tt_osag_notify.sql:1817-1826` |
| `email_signature` | `tt.osag_notify__email_signature` | `ddl/src/pkgb/tt_osag_notify.sql:271` | `ddl/src/pkgb/tt_osag_notify.sql:1831-1841` |

## Clauses

### S-NOTIFY-001

- **routines:** event_notify
- **claim:** `event_notify`'s entire body is wrapped in one `BEGIN...EXCEPTION WHEN
  OTHERS THEN plog.warning(...); plog.warning(...); END` (no `RAISE`). Every one of the
  ~20 `SELECT INTO` sites and private-routine calls reachable from this procedure,
  whatever exception they raise (including ones with no local handler at all — see
  S-NOTIFY-003/007/024/025/026/028 below), is caught HERE if not caught closer to its
  source, logged, and swallowed. `event_notify` **never** raises to its own caller.
- **source:** `ddl/src/pkgb/tt_osag_notify.sql:334, 754-758`

### S-NOTIFY-002

- **routines:** event_notify
- **claim:** SELECT INTO site #1 (inventory line 345): if `p_ticket_id` is NULL,
  `v_ticket_id` is resolved via `SELECT e.ticket_id INTO v_ticket_id FROM tt.event e
  WHERE e.id = p_event_id`. `tt.event.id` is the primary key (`EVENT_PK`), so
  `TOO_MANY_ROWS` is structurally impossible; zero rows is reachable for a
  nonexistent `p_event_id`. No local handler; propagates to S-NOTIFY-001's outer
  swallow.
- **source:** `ddl/src/pkgb/tt_osag_notify.sql:343-349`

### S-NOTIFY-003

- **routines:** event_notify
- **claim:** SELECT INTO site #2 (inventory line 352), the main event/ticket/
  event_type/host/host2service join, is BOTH a zero-row risk (join integrity edge
  case) AND, less obviously, a **multi-row risk**: `mss.host2service`'s primary key is
  `(HOST_ID, SERVICE_ID)` (`ddl/generated/schema.oracle.sql:81`) — `HOST_ID` alone is
  NOT unique, so a host mapped to more than one service makes the `h2s.host_id(+) =
  COALESCE(...)` outer join return more than one row, i.e. `TOO_MANY_ROWS` is
  genuinely reachable here, not merely theoretical. No local handler for either
  case; both propagate to S-NOTIFY-001's outer swallow.
- **source:** `ddl/src/pkgb/tt_osag_notify.sql:352-363`

### S-NOTIFY-004

- **routines:** event_notify
- **claim:** If both the customer and OSAG notify counters are already at the
  5-notification cap (`MAX_EVENT_NOTIFY_COUNT`) AND the event's source is
  "automatic" (`event_source.id = 1`), `event_notify` logs and `RETURN`s immediately —
  a normal early exit, not an exception path.
- **source:** `ddl/src/pkgb/tt_osag_notify.sql:366-370`

### S-NOTIFY-005

- **routines:** event_notify
- **claim:** SELECT INTO site #3 (inventory line 380), only reached for
  `v_event_type_id = 50020` ("change request approved by engineer"), appends the
  approving peer contact's name to the event type label. Zero rows is reachable
  (`e.peer_contact_id` may be NULL or unmapped); `TOO_MANY_ROWS` is structurally
  impossible (`stop.contact.id` is `CONTACT_PK`). **Has its own local
  `EXCEPTION WHEN NO_DATA_FOUND THEN NULL`** (line 387) — the lookup is simply
  skipped, `v_event_type_name` keeps its unmodified value.
- **source:** `ddl/src/pkgb/tt_osag_notify.sql:377-389`

### S-NOTIFY-006

- **routines:** event_notify
- **claim:** Registered-listener notification is gated: it runs only if
  `NOT is_notify_suppressor_active(v_host_id) OR v_event_type_id = 50008` — i.e.
  "question" events (50008) are never suppressed by an active service window, even
  when everything else would be.
- **source:** `ddl/src/pkgb/tt_osag_notify.sql:393`

### S-NOTIFY-007

- **routines:** event_notify
- **claim:** SELECT INTO sites #4-#8 (inventory lines 397, 402, 408, 415, 425) resolve
  the ticket's company/type/worker, ticket-type name, and company-unit chain (service
  branch, service-with-no-default-unit branch, no-service-but-company branch). All
  five are single-row primary-key lookups (`tt.ticket.id`, `tt.ticket_type.id`,
  `mss.service.id`, `stop.company.id` are each that table's PK) so `TOO_MANY_ROWS` is
  structurally impossible at every one; zero rows is reachable at each if the
  resolved id doesn't exist (line 402's `ty.id = v_ticket_type_id` is reachable with
  zero rows specifically because `TT.TICKET.TYPE_ID` has **no `NOT NULL`
  constraint** — `ddl/generated/schema.oracle.sql:203` — so a ticket with a NULL
  `type_id` makes this lookup legitimately return zero rows, not just a
  data-integrity edge case). None of the five has a local handler; all propagate to
  S-NOTIFY-001's outer swallow.
- **source:** `ddl/src/pkgb/tt_osag_notify.sql:396-432`

### S-NOTIFY-008

- **routines:** event_notify
- **claim:** For `v_event_type_id = 10003` ("isp outage"), `event_notify` calls the
  private `notify_isp` unconditionally within the suppression-gated block (before the
  event-type-group lookup) — see S-NOTIFY-030 for `notify_isp` itself, including the
  package's one `TOO_MANY_ROWS` handler that it transitively reaches.
- **source:** `ddl/src/pkgb/tt_osag_notify.sql:440-447`

### S-NOTIFY-009

- **routines:** event_notify
- **claim:** SELECT INTO site #9 (inventory line 451) resolves the event's
  notification group via `tt.event_type2event_type_group`. **This mapping table's
  primary key is `(EVENT_TYPE_GROUP_ID, EVENT_TYPE_ID)`**
  (`ddl/generated/schema.oracle.sql:501`) — `EVENT_TYPE_ID` alone is NOT unique, so one
  event type CAN belong to more than one group, making `TOO_MANY_ROWS` structurally
  reachable here too. The local handler at this site is
  `EXCEPTION WHEN NO_DATA_FOUND THEN v_event_type_group_id := NULL` (lines 456-458)
  **only** — it does **not** catch `TOO_MANY_ROWS`. If this site's join ever matches
  more than one group, the exception is NOT swallowed here; it propagates one level
  further, to `event_notify`'s own outer `WHEN OTHERS` (S-NOTIFY-001), which does
  catch it. This two-tier structure (local NDF handler, no local TMR handler, outer
  OTHERS catches TMR) must be reproduced exactly, not simplified to "one STRICT
  handler catches everything" — a naive translation that adds a single
  `WHEN NO_DATA_FOUND OR TOO_MANY_ROWS` at this site would (harmlessly, since both
  paths currently end in "treat as ungrouped") work out equivalently in THIS
  particular case, but the general principle — local handlers catch only what Oracle's
  source says they catch — is the point of this whole checklist dimension and is
  preserved here for exactly that reason.
- **source:** `ddl/src/pkgb/tt_osag_notify.sql:450-459`

### S-NOTIFY-010

- **routines:** event_notify
- **claim:** Local-contact notification (private `notify_local_contacts`, S-NOTIFY-029)
  fires only when `v_event_type_group_id = 1` (connectivity-related, per inline
  comment) AND `v_host_id IS NOT NULL`.
- **source:** `ddl/src/pkgb/tt_osag_notify.sql:461-481`

### S-NOTIFY-011

- **routines:** event_notify
- **claim:** SMS and email messages are always composed (via the private
  `compose_sms_msg`/`compose_email_msg`, S-NOTIFY-028/S-NOTIFY-026) once the
  suppression gate passes, regardless of which/whether any recipient cursor below
  actually finds a match — composition is unconditional, dispatch is conditional.
- **source:** `ddl/src/pkgb/tt_osag_notify.sql:484-510`

### S-NOTIFY-012

- **routines:** event_notify
- **claim:** When `v_service_id IS NULL`, customer notifications are selected via
  `notify_cur` restricted to company-wide, `role_id = 1` ("mc-cust-monitor")
  permissions (excluding OSAG logins, `l.company_id != 6`), and each matched row is
  dispatched via the private `send_notification_by_type`. Zero matches is a normal
  empty-loop outcome (cursor `FOR`, not `SELECT INTO`); no NO_DATA_FOUND risk at the
  cursor-open itself.
- **source:** `ddl/src/pkgb/tt_osag_notify.sql:521-574`

### S-NOTIFY-013

- **routines:** event_notify
- **claim:** When `v_service_id IS NOT NULL`, the parallel cursor instead joins
  `auth.mv_service_access` (`role_id = 1`) to check per-service access, since
  company-wide permission alone isn't sufficient once a specific service is known.
  Same empty-loop, no-exception shape as S-NOTIFY-012.
- **source:** `ddl/src/pkgb/tt_osag_notify.sql:575-626`

### S-NOTIFY-014

- **routines:** event_notify
- **claim:** OSAG-staff notifications (`l.company_id = 6`, `p.role_id = 6`
  "mc-osag-monitor") are selected by a third cursor with its own filter set
  (`regexp` against `e.details_public`, `only_if_worker` against the ticket's
  assigned worker contact). If the ticket's own company is non-OSAG
  (`v_company_id IS NOT NULL AND != 6`), these notifications are marked PRIVATE
  (`v_notif_event_is_public := 0`) — customers must never see that OSAG staff were
  separately notified about their own ticket.
- **source:** `ddl/src/pkgb/tt_osag_notify.sql:631-689`

### S-NOTIFY-015

- **routines:** event_notify
- **claim:** If any customer notification was sent (`v_notified_customer`), the
  ticket's `event_notify_count` is incremented (first-time NULL treated as 1) and
  written unconditionally; if the new count hits exactly 5, an additional public
  ticket event (type 20010) is inserted announcing "no more notifications". This
  `INSERT` uses `event_sequence.NextVal` for the id — an Oracle sequence call with no
  PostgreSQL 1:1 syntax (translation must use `nextval('tt.event_sequence')` or
  equivalent per whatever Phase 3/4 decides for sequence naming).
- **source:** `ddl/src/pkgb/tt_osag_notify.sql:692-717`

### S-NOTIFY-016

- **routines:** event_notify
- **claim:** The identical counter/threshold pattern repeats for OSAG staff
  (`event_notify_count_osag`), except the "limit reached" event is inserted as a
  PRIVATE event (`public_event = 0`, explicit 6th column/value pair) rather than
  omitting the column (which defaults `public_event = 1` per
  `ddl/generated/schema.oracle.sql:133`, matching S-NOTIFY-015's public case).
- **source:** `ddl/src/pkgb/tt_osag_notify.sql:719-745`

### S-NOTIFY-017

- **routines:** event_notify
- **claim:** A perf-monitoring warning (`plog.warning`) is logged if the procedure's
  own elapsed time, MINUS the time spent inside `send_notification_by_type` calls,
  exceeds 500 centiseconds (2s). This is purely observational logging with no
  behavioral/data effect — `DBMS_UTILITY.GET_TIME` has no direct PostgreSQL
  equivalent; a translation can use `clock_timestamp()` deltas, but this is a
  monitoring nicety, not a spec-level correctness requirement.
- **source:** `ddl/src/pkgb/tt_osag_notify.sql:747-752`

### S-NOTIFY-018

- **routines:** send_test_notification
- **claim:** SELECT INTO site #10 (inventory line 785), `SELECT name INTO
  v_event_type_name FROM tt.event_type et WHERE et.id = p_event_type_id`, is a
  single-row PK lookup (`tt.event_type.id` is `EVENTTYPE_PK`) — `TOO_MANY_ROWS`
  structurally impossible, zero rows reachable for a bad `p_event_type_id`.
  **`send_test_notification` has NO `EXCEPTION` block anywhere in its 81-line body**
  (confirmed by reading `ddl/src/pkgb/tt_osag_notify.sql:764-844` in full) — this
  `NO_DATA_FOUND`, if raised, is FULLY UNHANDLED and propagates straight out of
  `send_test_notification` to WHATEVER called it. This is the one public routine
  where Oracle's contract really is "an unhandled exception is the caller's
  problem" — it must translate to `SELECT ... INTO STRICT` with **no wrapping
  handler added**, matching Oracle exactly.
- **source:** `ddl/src/pkgb/tt_osag_notify.sql:764-788`

### S-NOTIFY-019

- **routines:** delete_notifications_for_login
- **claim:** `delete_notifications_for_login` uses a cursor
  (`SELECT DISTINCT en.ticket_id FROM tt.event_notification en WHERE en.login_id =
  p_login_id AND en.ticket_id IS NOT NULL`) in a `FOR` loop, delegating each matched
  ticket to `delete_ticket_notifications`. Zero matching tickets is a normal empty
  loop, not an exception. After the loop, a single bulk
  `DELETE FROM tt.event_notification WHERE login_id = p_login_id` removes any
  remaining (non-ticket-scoped) notifications unconditionally — this statement has no
  row-count check and succeeds even if zero rows match.
- **source:** `ddl/src/pkgb/tt_osag_notify.sql:849-869`

### S-NOTIFY-020

- **routines:** delete_ticket_notifications
- **claim:** **A genuine NULL/`''` concatenation hazard (Pitfall 2), independent of
  any `SELECT INTO`.** `v_event_details_public`/`v_event_details_private` are
  declared with NO default value (`ddl/src/pkgb/tt_osag_notify.sql:897-898`), so both
  start as SQL NULL. The loop body accumulates each deletion line via
  `v_event_details_public := v_event_details_public || '  -deleted ' || ... ||
  CHR(10)` (lines 906, 909). **In Oracle, `NULL || 'x'` evaluates to `'x'`** (Oracle
  treats `NULL` as `''` for the `||` operator specifically), so the FIRST loop
  iteration correctly seeds the accumulator from nothing. **In PL/pgSQL,
  `NULL || 'x'` evaluates to `NULL`** (standard SQL NULL propagation) — a literal
  port of this accumulation pattern would leave `v_event_details_public` (and
  `_private`) permanently `NULL`, silently dropping every "deleted notification"
  description text even though the underlying rows ARE actually deleted. **The same
  hazard recurs at the suffix append** (`v_event_details_public :=
  v_event_details_public || p_event_details_suffix`, lines 917/920): if
  `p_event_details_suffix` is left at its default (`NULL`, since the parameter's
  default is `NULL`), Oracle's `x || NULL = x` leaves the accumulated text
  untouched, while PL/pgSQL's `x || NULL = NULL` would WIPE OUT everything
  accumulated so far. Both sites require an explicit `COALESCE(x, '')` boundary
  normalization in translation, not a bare `||` port.
- **source:** `ddl/src/pkgb/tt_osag_notify.sql:897-898, 904-911, 916-921`

### S-NOTIFY-021

- **routines:** delete_ticket_notifications
- **claim:** `TT.TICKET_INTERFACE.change_notification` (a history-event write) is
  called only if `v_event_details_public IS NOT NULL OR v_event_details_private IS
  NOT NULL` — i.e. only if S-NOTIFY-020's accumulator actually holds text. This
  routine's own top-level `EXCEPTION WHEN OTHERS` (lines 932-935) logs
  `plog.warning` twice (message + `sqlerrm`) and swallows — same shape as
  `event_notify`'s (S-NOTIFY-001). Any of this routine's private-callee exceptions
  (including S-NOTIFY-035's unhandled `get_notification_type_name` site) that reach
  here are caught at this level.
- **source:** `ddl/src/pkgb/tt_osag_notify.sql:900-935`

### S-NOTIFY-022

- **routines:** add_notification_event
- **claim:** Pure `INSERT` into `tt.event`, routing `p_text` to `details_public` (and
  nulling `details_private`) when `p_is_public_event = 1`, or the reverse otherwise.
  **Zero `SELECT ... INTO` sites** — the only public routine with none. No
  `EXCEPTION` block; an `INSERT` failure (FK violation on `p_contact_id`,
  `p_peer_contact_id`, `p_ticket_id`, or `p_event_type_id`) propagates fully
  unhandled to the caller — this is a deliberate, not incidental, "let it fail
  loudly" contract for this one routine.
- **source:** `ddl/src/pkgb/tt_osag_notify.sql:952-973`

### S-NOTIFY-023

- **routines:** is_notify_suppressor_active
- **claim:** SELECT INTO site #11 (inventory line 987),
  `SELECT COUNT(*) INTO v_entry_exists FROM ...`, is a `COUNT` aggregate — always
  exactly one row, structurally safe from both `NO_DATA_FOUND` and `TOO_MANY_ROWS`.
  `v_entry_exists > 0` → `TRUE`; otherwise `FALSE`. This is the package's one
  legitimate "no STRICT concern" site.
- **source:** `ddl/src/pkgb/tt_osag_notify.sql:979-1008`

### S-NOTIFY-024

- **routines:** send_notification_by_type (private)
- **claim:** SELECT INTO site #12 (inventory line 1050), the SMS-branch contact
  lookup (`p_event_notification_type_id = 1`), joins `auth.login`/`stop.contact` by
  `login.id = p_login_id AND contact.id = login.contact_id` — a 1:1 PK-to-PK join
  (`AUTH_LOGIN` PK on `id`, `stop.contact` PK on `id`), so `TOO_MANY_ROWS` is
  structurally impossible; zero rows is reachable for a bad `p_login_id` or a login
  whose `contact_id` doesn't resolve. `send_notification_by_type` has **no
  `EXCEPTION` block of its own** (confirmed reading the full 100-line body,
  `ddl/src/pkgb/tt_osag_notify.sql:1019-1118`). Its only 3 call sites are all inside
  `event_notify` (lines 560, 611, 675) — so an unhandled `NO_DATA_FOUND` here
  propagates, through the notification cursor's `FOR` loop and its enclosing
  `DECLARE...BEGIN...END` (neither of which has a handler either), all the way to
  `event_notify`'s own outer `WHEN OTHERS` (S-NOTIFY-001).
- **source:** `ddl/src/pkgb/tt_osag_notify.sql:1048-1054`

### S-NOTIFY-025

- **routines:** send_notification_by_type (private)
- **claim:** SELECT INTO site #13 (inventory line 1072), the email-branch contact
  lookup (`p_event_notification_type_id = 2`), is the same shape as S-NOTIFY-024
  (1:1 PK join, no local handler, same escalation to `event_notify`'s outer
  swallow). The envelope-from address differs by `p_is_public_event`
  (`ttbounce+<ticket>@open.ch` vs. `ttbounce-private+<ticket>@open.ch`) — a
  deliberate routing distinction, not an error path.
- **source:** `ddl/src/pkgb/tt_osag_notify.sql:1070-1076, 1102-1106`

### S-NOTIFY-026

- **routines:** compose_email_msg (private)
- **claim:** SELECT INTO sites #14 and #15 (inventory lines 1150, 1155) resolve the
  event type's email template id, then the template's subject/message text.
  `tt.event_type.id` and `tt.event_type_message.id` are each that table's PK, so
  `TOO_MANY_ROWS` is structurally impossible at either; zero rows is reachable at
  #14 for a bad `p_event_type_id`, and at #15 if `EMAIL_MESSAGE_TEMPLATE_ID` (which
  IS `NOT NULL` per `ddl/generated/schema.oracle.sql:459`) points at a template row
  that doesn't exist (orphaned reference — schema does not forbid this, only forbids
  the column being `NULL`). **`compose_email_msg` has no `EXCEPTION` block of its
  own.** It has TWO current callers with DIFFERENT safety nets: `event_notify` (line
  495, inside S-NOTIFY-001's outer swallow) and `send_test_notification` (line 813,
  which per S-NOTIFY-018 has NO handler at all) — so the SAME unhandled
  `NO_DATA_FOUND` here is silently swallowed when reached via `event_notify`, but
  propagates all the way out of `send_test_notification` to ITS caller when reached
  that way. Both behaviors must be preserved; this is not a candidate for adding a
  uniform handler.
- **source:** `ddl/src/pkgb/tt_osag_notify.sql:1149-1158`

### S-NOTIFY-027

- **routines:** compose_email_msg (private)
- **claim:** Message composition after the template lookup is pure `REPLACE()`
  placeholder substitution (`$#TICKET_SUBJECT#$`, `$#HOST_NAME#$`, etc.) — no
  further `SELECT`, no NULL/`''` hazard (all replacement values are either
  caller-supplied non-null parameters or already-defaulted locals). Two event types
  get extra injected content: 50008 ("question") replaces `$#QUESTION#$` with
  `p_details_public`, truncated to 29000 chars; 30012/50004 (customer/engineer
  rating) inject up to 2000 chars of `p_details_public`/`p_details_private`
  respectively into `$#PUBLIC_DETAILS#$`/`$#PRIVATE_DETAILS#$`.
- **source:** `ddl/src/pkgb/tt_osag_notify.sql:1160-1221`

### S-NOTIFY-028

- **routines:** compose_sms_msg (private)
- **claim:** SELECT INTO sites #16 and #17 (inventory lines 1249, 1254) mirror
  S-NOTIFY-026's template lookup chain for the SMS template instead of the email
  one — same PK-lookup structure, same "no `TOO_MANY_ROWS`, zero rows reachable"
  profile. **`compose_sms_msg` has no `EXCEPTION` block.** It has THREE current
  callers, each with a different safety net: `event_notify` (line 484, outer
  swallow), `send_test_notification` (line 797, no handler at all), and the private
  `notify_local_contacts` (line 1354, which per S-NOTIFY-029 has its own routine-level
  `WHEN NO_DATA_FOUND` that DOES cover this call since it's lexically inside that
  routine's `BEGIN...EXCEPTION` block). Three different observable outcomes for the
  identical unhandled exception, depending purely on the call path.
- **source:** `ddl/src/pkgb/tt_osag_notify.sql:1249-1257`

### S-NOTIFY-029

- **routines:** notify_local_contacts (private)
- **claim:** SELECT INTO sites #18, #19, #20 (inventory lines 1336, 1342, 1347)
  resolve the service-type name, company name, and event-type name (all single-row
  PK lookups: `mss.service_type.id`, `stop.company.id`, `tt.event_type.id` —
  `TOO_MANY_ROWS` structurally impossible at all three; zero rows reachable if
  `p_service_id`/`p_company_id`/`p_event_type_id` is NULL or orphaned). **All three
  are covered by ONE routine-level handler**,
  `EXCEPTION WHEN NO_DATA_FOUND THEN plog.err(...); RETURN;` (lines 1378-1381),
  since all three SELECTs are lexically inside the same `BEGIN...EXCEPTION` block
  that wraps the whole routine body. A subtlety worth recording exactly: the `OUT`
  parameter `p_notified_cust` is only assigned starting at line 1357 (AFTER all
  three SELECTs) — if any of the three raises `NO_DATA_FOUND`, `p_notified_cust` is
  NEVER assigned at all inside this call. Oracle leaves an unassigned `OUT`
  parameter at its caller-supplied initial value (effectively `NULL` here, since
  `event_notify` declares `v_local_contact_notified BOOLEAN` with no default at line
  313); `event_notify`'s own check (`IF v_local_contact_notified THEN`, line 478)
  treats `NULL` as not-`TRUE` in both Oracle's `IF` semantics and PL/pgSQL's
  identical `NULL`-is-falsy `IF` behavior — so this specific interaction is
  confirmed to translate without a delta, but it is subtle enough to be worth
  recording rather than silently relying on.
- **source:** `ddl/src/pkgb/tt_osag_notify.sql:1334-1382`

### S-NOTIFY-030

- **routines:** notify_isp (private)
- **claim:** After an early `RETURN` if `get_isp_link_id_for_host_id` (S-NOTIFY-031)
  found no ISP link, SELECT INTO site #21 (inventory line 1438) resolves the ISP
  link's notification flag, router IP, and support contact's email/id via a join to
  `stop.contact` — 1:1 PK-to-PK (`mss.isp_link.id`, `stop.contact.id`), so
  `TOO_MANY_ROWS` is structurally impossible; zero rows is reachable if
  `support_id` is NULL or orphaned. **Has its own local handler covering BOTH cases
  Oracle actually anticipates**: `WHEN NO_DATA_FOUND THEN v_isp_support_mail :=
  NULL` and `WHEN OTHERS THEN plog.err(...); v_isp_support_mail := NULL` (lines
  1444-1449) — both swallow to `NULL` and let execution continue. The subsequent
  `IF (v_isp_notification = 0)` check (line 1451) then compares a possibly-`NULL`
  `v_isp_notification` against `0`; in both Oracle and PostgreSQL, `NULL = 0`
  evaluates to `NULL`, and `IF NULL THEN` is treated as `FALSE` in both languages —
  so execution correctly falls through to the notification-send logic rather than
  incorrectly short-circuiting, confirmed identical in both engines.
- **source:** `ddl/src/pkgb/tt_osag_notify.sql:1429-1453`

### S-NOTIFY-031

- **routines:** get_isp_link_id_for_host_id (private)
- **claim:** **The pilot's one and only `TOO_MANY_ROWS` handler.** SELECT INTO site
  #22 (inventory line 1496) joins `mss.host` → `mss.interface` (`mgmtaccess = 1`) →
  `mss.interface2isp_link`. Multi-row IS structurally reachable, for two independent
  reasons confirmed from the DDL: (1) `mss.interface`'s primary key is `id` alone —
  `host_id` is NOT unique, so a single host CAN have more than one interface with
  `mgmtaccess = 1`; (2) `mss.interface2isp_link`'s primary key is
  `(INTERFACE_ID, ISP_LINK_ID)` (`ddl/generated/schema.oracle.sql:341`) — a single
  interface CAN map to more than one ISP link. Either condition alone (let alone
  both together) makes this join legitimately return multiple rows for one host,
  which is exactly what Oracle's explicit
  `WHEN TOO_MANY_ROWS THEN plog.err('...has too many ISP links'); RETURN NULL;`
  (lines 1507-1510) exists to handle — Oracle EXPECTED this case, it is not
  incidental defensive code. Zero rows (`WHEN NO_DATA_FOUND THEN RETURN NULL`, lines
  1505-1506) and any other error (`WHEN OTHERS THEN plog.err(...); RETURN NULL`,
  lines 1511-1513) are ALSO explicitly handled — all three paths swallow to `NULL`,
  never raise. **PostgreSQL translation MUST reproduce all three arms explicitly**
  (`STRICT` alone only distinguishes zero-vs-one; the multi-row arm needs its own
  `WHEN TOO_MANY_ROWS`-equivalent, i.e. PL/pgSQL's own `TOO_MANY_ROWS` exception,
  which — unlike Oracle — **is only raised by `SELECT INTO STRICT` when a `LIMIT` is
  not otherwise implied**; PL/pgSQL's `TOO_MANY_ROWS` (SQLSTATE `P0003`) behaves
  the same way as Oracle's for this purpose and is available to catch here).
- **source:** `ddl/src/pkgb/tt_osag_notify.sql:1486-1517`

### S-NOTIFY-032

- **routines:** get_message_for_isp_outage (private)
- **claim:** Three independent `SELECT ... INTO` sites (#23, #24, #25 — inventory
  lines 1556, 1571, 1583), each wrapped in its OWN small `BEGIN...EXCEPTION` block
  that swallows unconditionally and independently of the others (`WHEN OTHERS THEN
  v_acc_mgr_lastname := ''` at 1556; `WHEN OTHERS THEN NULL` at 1571 and 1583) — so a
  failure at any one site never prevents the other two (or the message composition
  that follows) from running. A **fourth** site (#26, inventory line 1601) resolves
  the connection-down timestamp from `mc.connection_interrupt_open`, also
  `WHEN OTHERS THEN NULL`-guarded; the inline comment ("assume there's one open
  outage for that service") is an ASSUMPTION, not schema-enforced — see Assumptions
  section. None of these four sites is `TOO_MANY_ROWS`-impossible by PK alone except
  site #23/#24 (both single-row PK joins: `mss.isp_link.id`, `stop.company.id`);
  site #25 (`mss.host.id` PK join, city/country outer joins all PK-keyed) is also
  single-row-safe; site #26 (`mc.connection_interrupt_open` keyed by `host_id`,
  which is **NOT** unique per that table's schema — see Assumptions) is the one
  genuinely uncertain one, though harmlessly caught by its `WHEN OTHERS`
  regardless of which specific exception fires.
- **source:** `ddl/src/pkgb/tt_osag_notify.sql:1553-1608`

### S-NOTIFY-033

- **routines:** get_message_for_connection_up (private)
- **claim:** Mirrors S-NOTIFY-032's first three sites exactly (#27, #28, #29 —
  inventory lines 1704, 1719, 1731; same swallow-independently shape, same
  structural safety analysis) for the "connection restored" message variant. This
  variant has **no** fourth (`connection_interrupt_open`) lookup — a deliberate
  content difference between the outage and restoration messages, not an omission.
- **source:** `ddl/src/pkgb/tt_osag_notify.sql:1701-1743`

### S-NOTIFY-034

- **routines:** get_message_for_isp_outage, get_message_for_connection_up (private)
- **claim:** **A second Pitfall-2 (`''`/NULL collapsing) hazard, distinct from
  S-NOTIFY-020.** Both routines populate `v_acc_mgr_lastname`/`v_acc_mgr_firstname`
  via `NVL(stop.contact.lastname, '')` (lines 1556, 1704) — in Oracle, a NULL
  `lastname` becomes literal `''`, which Oracle's own storage/comparison semantics
  then treat as indistinguishable from `NULL` again, so the later
  `IF (v_acc_mgr_lastname IS NULL) THEN ... ELSE ...` check (lines 1665, 1772)
  correctly detects "no account manager" whether the underlying column was `NULL`
  or an actual `''`. **In PostgreSQL, `NVL(NULL, '')` (via `orafce`) returns a real,
  non-NULL empty string** — so `v_acc_mgr_lastname IS NULL` would evaluate `FALSE`
  for a contact with a NULL lastname, taking the WRONG branch (the "we have an
  account manager" branch, printing an empty name instead of the "n/a" fallback).
  Translation must replace the `IS NULL` check with an explicit
  `= '' OR IS NULL` test (or normalize at the `NVL` boundary instead, e.g. skip the
  `NVL` and check `IS NULL` on the raw column) — a bare 1:1 port of both lines is
  wrong.
- **source:** `ddl/src/pkgb/tt_osag_notify.sql:1556-1558, 1665-1669, 1704-1706, 1772-1776`

### S-NOTIFY-035

- **routines:** format_customer_reference (private)
- **claim:** **The clearest Pitfall-2 hazard in this package.**
  `IF (p_customer_reference IS NULL) THEN v_prepared_customer_reference := ''; ELSE
  v_prepared_customer_reference := ' [' || p_customer_reference || ']'; END IF;`
  In Oracle, a caller passing an empty string `''` for `p_customer_reference` is
  indistinguishable from passing `NULL` — both hit the `IS NULL` branch, producing
  `''` (no bracketed reference at all). **In PostgreSQL, `''` is a real, distinct
  value** — the same call would fall into the `ELSE` branch and produce `' []'` (a
  visible, empty bracket pair) instead of nothing. Every one of this package's four
  callers of `format_customer_reference` (`compose_email_msg` line 1165,
  `notify_local_contacts`... actually not called there; call sites are
  `compose_email_msg:1165`, `notify_isp:1459,1466`, `notify_local_contacts:1352`)
  passes a caller-supplied `tt.ticket.customer_reference` value straight through —
  and `TT.TICKET.CUSTOMER_REFERENCE` has no `NOT NULL`/check constraint forbidding
  `''` at the column level (`ddl/generated/schema.oracle.sql:203`), so this is a
  live, reachable divergence, not a theoretical one. Translation must normalize at
  the boundary — `NULLIF(p_customer_reference, '')` before the `IS NULL` check, or
  an explicit `= '' OR IS NULL` test.
- **source:** `ddl/src/pkgb/tt_osag_notify.sql:1790-1800`

### S-NOTIFY-036

- **routines:** get_notification_type_name (private)
- **claim:** SELECT INTO site #30 (inventory line 1810),
  `SELECT name INTO v_event_notification_type_name FROM tt.event_notification_type
  WHERE id = p_event_notification_type_id`, is a single-row PK lookup
  (`EVENTNOTIFICATIONTYPE_PK`) — `TOO_MANY_ROWS` structurally impossible; zero rows
  reachable for a bad id. **No `EXCEPTION` block of its own.** Its only two call
  sites (lines 906, 909) are both inside `delete_ticket_notifications`'s own
  `BEGIN...EXCEPTION` block (S-NOTIFY-021), whose top-level `WHEN OTHERS` catches
  and swallows this unhandled `NO_DATA_FOUND` if it fires.
- **source:** `ddl/src/pkgb/tt_osag_notify.sql:1805-1812`

### S-NOTIFY-037

- **routines:** (none directly — package-wide, private helpers only)
- **claim:** `email_footer` and `email_signature` are pure string builders with zero
  database access and zero parameters (`email_signature`) or one (`email_footer`,
  used only to compose a link, not queried) — no `SELECT`, no NULL-boundary risk of
  any kind. Documented for translation completeness only.
- **source:** `ddl/src/pkgb/tt_osag_notify.sql:1817-1841`

### S-NOTIFY-038

- **routines:** compose_email_msg, compose_sms_msg, compose_local_contact_message (private)
- **claim:** Every rendered date in the composed messages is followed by the **current
  Zurich time-zone abbreviation**: the `$#EVENT_DATE#$` and `$#STATUS_VALID_UNTIL#$`
  placeholders of the SMS template (lines 1269, 1272) and of the email subject/body
  templates (lines 1178, 1183, 1196), and the `Date:` line of the local-contact message
  (line 1398), are all built as `TO_CHAR(<date>, 'DD.MM.YYYY HH24:MI') || ' ' ||
  TO_CHAR(SYSTIMESTAMP AT TIME ZONE 'EUROPE/ZURICH', 'TZD')`. `TZD` is the abbreviation
  of the zone at the moment of composition — `CET` or `CEST` — **not** of the rendered
  date itself, and never empty: on the live Oracle container (2026-10-21) a fixed event
  date `2026-10-20 10:30` rendered as `20.10.2026 10:30 CEST`
  (`tt__osag_notify__event_notify` differential scenario, the 20003 event text). A
  translation that produces `20.10.2026 10:30 ` (empty abbreviation) is wrong; PostgreSQL's
  `to_char(ts, 'TZ')` is empty for a `timestamp without time zone`, which is what
  `clock_timestamp() AT TIME ZONE 'Europe/Zurich'` yields.
- **source:** `ddl/src/pkgb/tt_osag_notify.sql:1178, 1183, 1196, 1269, 1272, 1398`

## Checklist

### 1. Empty-string / NULL handling

Three genuine Pitfall-2 (`''`/`NULL` collapsing) hazards found by tracing every
`VARCHAR2`/`CLOB` identifier through every `IS NULL`/`IS NOT NULL`/`||` site in the
1844-line body — all three require an explicit boundary-normalization decision in
translation, not a bare 1:1 port:

1. **`format_customer_reference`'s `IS NULL` check on `p_customer_reference`**
   (S-NOTIFY-035) — the clearest case: Oracle collapses caller-supplied `''` to
   `NULL` before the check; PostgreSQL will not. `tt.ticket.customer_reference` has
   no `NOT NULL`/check constraint forbidding `''`, so this is reachable, not
   theoretical.
2. **`delete_ticket_notifications`'s NULL-seeded accumulator concatenation**
   (S-NOTIFY-020) — `v_event_details_public`/`_private` start `NULL` (no default),
   accumulated via `x := x || 'text'`. Oracle's `NULL || 'x' = 'x'`; PL/pgSQL's
   `NULL || 'x' = NULL`. A literal port leaves both variables permanently `NULL`,
   silently dropping every deletion-description line even though the underlying
   `DELETE`s succeed. The suffix append (`x := x || p_event_details_suffix`) has the
   identical hazard when the suffix parameter is left at its `NULL` default.
3. **`get_message_for_isp_outage`/`get_message_for_connection_up`'s
   `NVL(contact.lastname, '') ... IS NULL` round-trip** (S-NOTIFY-034) — Oracle's
   `NVL(NULL, '')` still reads as `NULL` on the later `IS NULL` check (Oracle's
   universal `''`≡`NULL` collapsing); PostgreSQL's `orafce` `NVL` returns a real,
   distinct `''`, so the later `IS NULL` check silently evaluates `FALSE` and takes
   the wrong branch.

Every other `IS NULL`/`IS NOT NULL` site in the package (grep-confirmed, all ~45
occurrences reviewed) is either (a) a numeric/id comparison with no `''` collapsing
relevance at all (e.g. `v_service_id IS NOT NULL`, `v_company_id IS NULL`), or (b) a
`VARCHAR2` check against a value that is never assigned `''` anywhere in this
package's own code — e.g. `p_host_name IS NOT NULL AND p_host_name != 'unspecified'`
(lines 1171, 1188, 1263) checks against a value already coalesced via
`NVL(h.name, 'unspecified')` at its ONE origin site (`event_notify` line 354), never
against a raw possibly-`''` column; and `v_isp_support_mail IS NOT NULL` (line 1456)
reads `stop.contact.email` directly with no `NVL` wrapper, so no collapsing round-trip
exists there for Postgres to diverge on. `v_contact_list` (in
`get_message_for_isp_outage`) is explicitly initialized to a real empty-string
literal (`v_contact_list := '';`, line 1617) before any concatenation, which — unlike
the NULL-seeded accumulators above — behaves identically in both engines (`'' || 'x'
= 'x'` in both), so it is NOT a hazard despite the superficial resemblance to
S-NOTIFY-020.

### 2. SELECT INTO strictness

**All 30 sites from the Phase 1 inventory's `select_into_sites` array for
`TT.OSAG_NOTIFY` are enumerated below, one row each, none omitted.** Verdict legend:
`STRICT + handler` = Oracle had a handler at or immediately above this site and it
must be reproduced; `STRICT, unhandled` = Oracle had no handler anywhere reachable
before this specific call chain's boundary and the raise propagates, matching
Oracle's actual (possibly latent-bug-looking, but real) contract; `no STRICT` =
zero rows is structurally impossible (aggregate query).

### SELECT INTO strictness

| # | ddl/src/pkgb/tt_osag_notify.sql:LINE | target(s) | zero rows possible? | multi rows possible? | Oracle handler | PG translation | clause |
|---|---|---|---|---|---|---|---|
| 1 | `ddl/src/pkgb/tt_osag_notify.sql:345` | `v_ticket_id` (via `tt.event`) | yes (bad `p_event_id`) | no (`EVENT_PK`) | none local; `event_notify`'s outer `WHEN OTHERS` (line 754) | STRICT + handler | S-NOTIFY-002 |
| 2 | `ddl/src/pkgb/tt_osag_notify.sql:352` | `v_host_id` etc. (event/ticket/event_type/host/host2service join) | yes (join-integrity edge case) | **yes** (`mss.host2service` PK is `(host_id, service_id)`, not unique on `host_id`) | none local; outer `WHEN OTHERS` (line 754) | STRICT + handler | S-NOTIFY-003 |
| 3 | `ddl/src/pkgb/tt_osag_notify.sql:380` | `v_peer_contact_name` (only for event_type 50020) | yes (`peer_contact_id` null/unmapped) | no (`CONTACT_PK`) | local `WHEN NO_DATA_FOUND THEN NULL` (line 387) | STRICT + handler | S-NOTIFY-005 |
| 4 | `ddl/src/pkgb/tt_osag_notify.sql:397` | `v_company_id, v_ticket_type_id, v_ticket_worker_id` (`tt.ticket` by id) | yes (stale `v_ticket_id`) | no (`TICKET_PK`) | none local; outer `WHEN OTHERS` | STRICT + handler | S-NOTIFY-007 |
| 5 | `ddl/src/pkgb/tt_osag_notify.sql:402` | `v_ticket_type_name` (`tt.ticket_type` by id) | yes (`TT.TICKET.TYPE_ID` has no `NOT NULL` constraint) | no (`TICKETTYPE_PK`) | none local; outer `WHEN OTHERS` | STRICT + handler | S-NOTIFY-007 |
| 6 | `ddl/src/pkgb/tt_osag_notify.sql:408` | `v_company_unit_id, v_service_type_id` (`mss.service` by id) | yes (orphaned `v_service_id`) | no (`SERVICE_PK`) | none local; outer `WHEN OTHERS` | STRICT + handler | S-NOTIFY-007 |
| 7 | `ddl/src/pkgb/tt_osag_notify.sql:415` | `v_company_unit_id` (default unit via service→company join) | yes | no (both joins PK-keyed) | none local; outer `WHEN OTHERS` | STRICT + handler | S-NOTIFY-007 |
| 8 | `ddl/src/pkgb/tt_osag_notify.sql:425` | `v_company_unit_id` (default unit, company branch) | yes (orphaned `v_company_id`) | no (`COMPANY` PK) | none local; outer `WHEN OTHERS` | STRICT + handler | S-NOTIFY-007 |
| 9 | `ddl/src/pkgb/tt_osag_notify.sql:451` | `v_event_type_group_id` | yes | **yes** (`tt.event_type2event_type_group` PK is `(group_id, event_type_id)`, not unique on `event_type_id`) | local `WHEN NO_DATA_FOUND` only (lines 456-458); `TOO_MANY_ROWS` NOT caught locally, escalates to outer `WHEN OTHERS` | STRICT + handler (two-tier, see S-NOTIFY-009) | S-NOTIFY-009 |
| 10 | `ddl/src/pkgb/tt_osag_notify.sql:785` | `v_event_type_name` (`send_test_notification`) | yes | no (`EVENTTYPE_PK`) | **none anywhere in this routine** | STRICT, unhandled | S-NOTIFY-018 |
| 11 | `ddl/src/pkgb/tt_osag_notify.sql:987` | `v_entry_exists` (`is_notify_suppressor_active`, `COUNT(*)`) | no (aggregate) | no (aggregate) | n/a | no STRICT | S-NOTIFY-023 |
| 12 | `ddl/src/pkgb/tt_osag_notify.sql:1050` | `v_contact_id` etc. (SMS branch, `send_notification_by_type`) | yes | no (1:1 PK join) | none local; escalates to `event_notify`'s outer `WHEN OTHERS` via all 3 call sites | STRICT + handler (indirect) | S-NOTIFY-024 |
| 13 | `ddl/src/pkgb/tt_osag_notify.sql:1072` | `v_contact_id` etc. (email branch, `send_notification_by_type`) | yes | no (1:1 PK join) | none local; escalates as #12 | STRICT + handler (indirect) | S-NOTIFY-025 |
| 14 | `ddl/src/pkgb/tt_osag_notify.sql:1150` | `v_email_msg_template_id` (`compose_email_msg`) | yes | no (`EVENTTYPE_PK`) | none local; via `event_notify` → outer swallow; via `send_test_notification` → **unhandled** | mixed: STRICT + handler OR unhandled, by caller | S-NOTIFY-026 |
| 15 | `ddl/src/pkgb/tt_osag_notify.sql:1155` | `v_subject_template, v_message_template` (`compose_email_msg`) | yes (orphaned template id) | no (`EVENTTYPEMESSAGE_PK`) | same as #14 | mixed, by caller | S-NOTIFY-026 |
| 16 | `ddl/src/pkgb/tt_osag_notify.sql:1249` | `v_sms_msg_template_id` (`compose_sms_msg`) | yes | no (`EVENTTYPE_PK`) | none local; 3 callers, 3 different nets (swallow / unhandled / handled) | mixed, by caller | S-NOTIFY-028 |
| 17 | `ddl/src/pkgb/tt_osag_notify.sql:1254` | `v_message_template` (`compose_sms_msg`) | yes (orphaned template id) | no (`EVENTTYPEMESSAGE_PK`) | same as #16 | mixed, by caller | S-NOTIFY-028 |
| 18 | `ddl/src/pkgb/tt_osag_notify.sql:1336` | `v_service_name` (`notify_local_contacts`) | yes | no (PK joins) | routine-level `WHEN NO_DATA_FOUND` (lines 1378-1381) | STRICT + handler | S-NOTIFY-029 |
| 19 | `ddl/src/pkgb/tt_osag_notify.sql:1342` | `v_company_name` (`notify_local_contacts`) | yes | no (`COMPANY` PK) | same routine-level handler | STRICT + handler | S-NOTIFY-029 |
| 20 | `ddl/src/pkgb/tt_osag_notify.sql:1347` | `v_event_type_name` (`notify_local_contacts`) | yes | no (`EVENTTYPE_PK`) | same routine-level handler | STRICT + handler | S-NOTIFY-029 |
| 21 | `ddl/src/pkgb/tt_osag_notify.sql:1438` | `v_isp_notification` etc. (`notify_isp`) | yes | no (1:1 PK join) | local `WHEN NO_DATA_FOUND` + `WHEN OTHERS` (lines 1444-1449), both swallow to NULL | STRICT + handler | S-NOTIFY-030 |
| 22 | `ddl/src/pkgb/tt_osag_notify.sql:1496` | `v_isp_link_id` (`get_isp_link_id_for_host_id`) | yes | **yes** (`mss.interface` not unique on `host_id`; `mss.interface2isp_link` PK `(interface_id, isp_link_id)` not unique on `interface_id`) | local `WHEN NO_DATA_FOUND` + **`WHEN TOO_MANY_ROWS`** + `WHEN OTHERS` (lines 1505-1513) — **the pilot's only `TOO_MANY_ROWS` handler** | STRICT + handler (all 3 arms) | S-NOTIFY-031 |
| 23 | `ddl/src/pkgb/tt_osag_notify.sql:1556` | `v_acc_mgr_lastname` etc. (`get_message_for_isp_outage`) | yes | no (1:1 PK join) | local `WHEN OTHERS` (line 1563, sets `''`) | STRICT + handler | S-NOTIFY-032 |
| 24 | `ddl/src/pkgb/tt_osag_notify.sql:1571` | `v_isp_company_name` (`get_message_for_isp_outage`) | yes (orphaned company id) | no (`COMPANY` PK) | local `WHEN OTHERS THEN NULL` (line 1576) | STRICT + handler | S-NOTIFY-032 |
| 25 | `ddl/src/pkgb/tt_osag_notify.sql:1583` | `v_company_name, v_city_name, v_country_name` (`get_message_for_isp_outage`) | yes | no (PK-keyed joins) | local `WHEN OTHERS THEN NULL` (line 1592) | STRICT + handler | S-NOTIFY-032 |
| 26 | `ddl/src/pkgb/tt_osag_notify.sql:1601` | `v_connection_down_date` (`get_message_for_isp_outage`) | yes (comment: "assume there's one open outage" — an assumption, see Assumptions) | unverified/assumed-no (`mc.connection_interrupt_open` not unique on `host_id` per schema — see Assumptions) | local `WHEN OTHERS THEN NULL` (line 1606) — catches whichever exception fires regardless | STRICT + handler | S-NOTIFY-032 |
| 27 | `ddl/src/pkgb/tt_osag_notify.sql:1704` | `v_acc_mgr_lastname` etc. (`get_message_for_connection_up`) | yes | no (1:1 PK join) | local `WHEN OTHERS` (line 1711, sets `''`) | STRICT + handler | S-NOTIFY-033 |
| 28 | `ddl/src/pkgb/tt_osag_notify.sql:1719` | `v_isp_company_name` (`get_message_for_connection_up`) | yes | no (`COMPANY` PK) | local `WHEN OTHERS THEN NULL` (line 1724) | STRICT + handler | S-NOTIFY-033 |
| 29 | `ddl/src/pkgb/tt_osag_notify.sql:1731` | `v_company_name, v_city_name, v_country_name` (`get_message_for_connection_up`) | yes | no (PK-keyed joins) | local `WHEN OTHERS THEN NULL` (line 1740) | STRICT + handler | S-NOTIFY-033 |
| 30 | `ddl/src/pkgb/tt_osag_notify.sql:1810` | `v_event_notification_type_name` (`get_notification_type_name`) | yes | no (`EVENTNOTIFICATIONTYPE_PK`) | none local; escalates to `delete_ticket_notifications`'s outer `WHEN OTHERS` (both call sites are inside it) | STRICT + handler (indirect) | S-NOTIFY-036 |

### 3. Exception codes

**Zero `RAISE_APPLICATION_ERROR` calls and zero named-exception declarations or
raises exist anywhere in this 1844-line package body** (confirmed: `grep -c
RAISE_APPLICATION_ERROR` and `grep -c "^\s*RAISE\b"` both return 0 against
`ddl/src/pkgb/tt_osag_notify.sql`). The only exception surface this package presents
to the outside world is the fully-unhandled propagation from
`send_test_notification`/`add_notification_event` (S-NOTIFY-018, S-NOTIFY-022) — a
plain, un-numbered `NO_DATA_FOUND` (or, for `add_notification_event`, whatever
constraint-violation exception an `INSERT` triggers). There is nothing
package-specific for XCUT-01 to map here beyond the general, cross-package
requirement that PL/pgSQL's default `NO_DATA_FOUND` SQLSTATE (`P0002`) and
`TOO_MANY_ROWS` SQLSTATE (`P0003`) must propagate to these two routines' callers
exactly as Oracle's `ORA-01403` does today. Recorded here; mapping decision deferred
to Phase 3.

### 4. Package state

None. Verified by reading the full 1844-line package body: the body opens directly
with the private-routine FORWARD DECLARATIONS section (`ddl/src/pkgb/tt_osag_notify.sql:4-272`,
a block of `PROCEDURE`/`FUNCTION` signature-only declarations with no variable
declarations at all), immediately followed by `event_notify`'s own declaration at
line 278 — there is no package-level `DECLARE`-equivalent section between `IS`
(line 3) and the first routine body. The file ends at line 1843-1844
(`END OSAG_NOTIFY; /`) with no trailing unnamed initialization block. Matches the
Phase 1 inventory's `package_state: []` and `has_init_block: false` for this package
exactly.

### 5. FUNCTION vs PROCEDURE

**Zero `COMMIT`, zero `ROLLBACK`, zero `PRAGMA AUTONOMOUS_TRANSACTION` anywhere in
this package** (confirmed: `grep -ciE "COMMIT|ROLLBACK|PRAGMA"` against
`ddl/src/pkgb/tt_osag_notify.sql` returns 0; matches the Phase 1 inventory's
`has_commit: false, has_rollback: false, autonomous_transaction: false`). This
package has NONE of `TT.UTIL`'s FUNCTION/PROCEDURE-COMMIT collision (see
`migration/spec/tt.util.md` Checklist dimension 5) — a plain PostgreSQL `FUNCTION`
translation for `is_notify_suppressor_active` (the one `FUNCTION` among the six
public routines) and plain `PROCEDURE`s for the other five raise no transaction-
control concerns of their own. This package DOES, however, `CALL` into
`TT.TICKET_INTERFACE.change_notification` (S-NOTIFY-021) and is itself called FROM
`TT.UTIL.check_resolved_tickets`, which per `migration/spec/tt.util.md`'s
Checklist dimension 5 is a plain `PROCEDURE` today with no known `pg_kind`
collision — so no cross-package FUNCTION/PROCEDURE-COMMIT hazard is currently
reachable through this package's own call graph. `pg_kind` remains PROVISIONAL
(Phase 3 XCUT-04) for all six routines regardless, per `migration/README.md`'s
standing warning.

## Assumptions / Unresolved

- **`mc.connection_interrupt_open`'s cardinality per `host_id` is not schema-enforced,
  and the source code's own inline comment ("we can not use the event_id... therefore
  search via service_id and assume there's one open outage for that service",
  `ddl/src/pkgb/tt_osag_notify.sql:1598-1599`) EXPLICITLY ACKNOWLEDGES this as an
  assumption, not a guarantee.** `MC.CONNECTION_INTERRUPT_OPEN`'s primary key is
  `ID` alone (`ddl/generated/schema.oracle.sql:241`); `HOST_ID` is `NOT NULL` but not
  unique, so more than one open-interrupt row per host is not structurally
  forbidden. Whether this ever actually happens in production data cannot be
  determined from static source review alone — no live Oracle exists for this phase
  to check against. Harmless either way for THIS site specifically, since its
  `WHEN OTHERS` handler (S-NOTIFY-032) swallows `TOO_MANY_ROWS` identically to every
  other exception there, but flagged honestly rather than silently assumed safe.
- **Whether `format_customer_reference`'s `''`/`NULL` divergence (S-NOTIFY-035) is
  reachable in PRODUCTION data** (i.e. whether any real `tt.ticket.customer_reference`
  value is actually `''` rather than `NULL` or non-empty) cannot be determined from
  static source alone — the column permits it (no constraint forbids it), which is
  sufficient to make this a real spec-level hazard requiring a translation decision,
  independent of whether it has ever actually fired in practice.
- **The private-routine naming convention (`__` double-underscore prefix, see
  "Private routines — naming convention" above) is a NEW rule invented for this
  spec, outside `migration/mapping/name-map.csv`.** It is offered as the
  recommended corpus-wide default (Phase 4 will hit "public package interface,
  private implementation namespace" in essentially every remaining package), but
  this spec is not authorized to finalize it — flagged loudly again in this plan's
  SUMMARY as a decision that may need folding back into the name-map generator.
- **`pg_kind` (FUNCTION vs PROCEDURE) remains PROVISIONAL for all six public
  routines**, per `migration/README.md`'s standing warning — this spec confirms no
  COMMIT/ROLLBACK/autonomous-transaction hazard exists WITHIN this package (Checklist
  dimension 5), but the final call belongs to Phase 3's XCUT-04, same as every other
  pilot package.
- **The exact PostgreSQL sequence-call syntax for `event_sequence.NextVal`**
  (S-NOTIFY-015, `ddl/src/pkgb/tt_osag_notify.sql:710`) is a corpus-wide translation
  mechanic (Oracle `sequence.NEXTVAL` → PostgreSQL `nextval('schema.sequence')`),
  not something this package-specific spec can settle in isolation — noted here so
  whichever plan performs the actual translation does not have to re-derive it.
- Nothing else is unresolved: all 30 `SELECT ... INTO` sites (cross-checked
  programmatically against `migration/analyze/inventory.json`'s
  `select_into_sites` array — all 30 present), all 5 `NO_DATA_FOUND` handlers, the
  1 `TOO_MANY_ROWS` handler, all 11 `WHEN OTHERS` handlers (every single one
  confirmed to swallow, none re-raises), the full absence of package state, the
  full absence of `COMMIT`/`ROLLBACK`/`PRAGMA`, and all 51 `%TYPE`/`%ROWTYPE`
  references (46 `%TYPE` + 5 `%ROWTYPE`, matching the Phase 1 inventory's
  `type_refs` count of 51 exactly — every one resolves against a real project
  table/view column, `ticket`, `event_type`, `event_notification_type`, `host`,
  `ticket_type`, `event_type_group`, `contact`, `isp_link`, `service_type`,
  `company`, `city`, `country` — **none references an Oracle data-dictionary view
  (`all_*`/`user_*`/`dba_*`); verified by grep against the full text of both the
  package spec and body, zero matches**) were reviewed against the complete text of
  `ddl/src/pkg/tt_osag_notify.sql` and `ddl/src/pkgb/tt_osag_notify.sql`, plus the
  relevant `ddl/generated/schema.oracle.sql` table/constraint definitions cited
  throughout this spec (`tt.event`, `tt.ticket`, `tt.ticket_type`, `tt.event_type`,
  `tt.event_type2event_type_group`, `tt.event_notification_type`,
  `mss.host2service`, `mss.interface`, `mss.interface2isp_link`,
  `mc.connection_interrupt_open`) and `migration/analyze/depgraph.json`'s edges
  into `TT.OSAG_NOTIFY` (from `AUTH.OSAG_AUTH`, `TT.EVENT_INTERFACE`,
  `TT.TICKET_INTERFACE`, `TT.UTIL`).
