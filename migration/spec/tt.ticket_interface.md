---
oracle_schema: TT
oracle_package: TICKET_INTERFACE
pg_schema: tt
pg_prefix: ticket_interface
clause_prefix: TICKET
oracle_spec: ddl/src/pkg/tt_ticket_interface.sql
oracle_body: ddl/src/pkgb/tt_ticket_interface.sql
public_routines: 38
---

# TT.TICKET_INTERFACE — PostgreSQL spec

The primary mutation interface for `tt.ticket`: opens new tickets, changes every mutable
ticket attribute (status, worker, subject, customer/partner reference, label, service/host,
owner, company, emergency flag, always-visible flag, notification/summary text, type,
service component), merges tickets, manages docs pages / related tickets / related files /
todo items, drives the MCC ticket-flow queue, and deletes a ticket outright. Per its header
comment (`ddl/src/pkg/tt_ticket_interface.sql:5-10`) it "offers procedures to deal with
mission control tickets... to open a ticket or modify ticket attributes and merge two
tickets together." This is the pilot's largest package (2,484 body lines), **all 38 public
routines in scope** (user-confirmed, LOCKED), with **77 `SELECT ... INTO` sites** (more than
twice `TT.OSAG_NOTIFY`'s 30), 13 `NO_DATA_FOUND` handlers, 0 `TOO_MANY_ROWS` handlers, 10
`WHEN OTHERS` handlers, and the corpus's only genuine routine overload
(`change_label`/`change_label`). It is **mutually recursive with `TT.EVENT_INTERFACE`**
(`migration/analyze/known_cycles.json`'s `TT.EVENT_INTERFACE|TT.OSAG_NOTIFY|
TT.TICKET_INTERFACE|TT.UTIL` cycle group) — see S-TICKET-090 and
`migration/spec/tt.event_interface.md` for the reverse direction, already committed and
consistent with this spec. `static_resolution: complete` — no dynamic SQL anywhere in this
package (confirmed against `migration/analyze/inventory.json`'s
`static_resolution_reasons: []` for `TT.TICKET_INTERFACE`).

## Routines

### newticket_new (PUBLIC)

- **Oracle signature:** `PROCEDURE newticket_new(p_ticket_id OUT NUMBER, p_event_id OUT NUMBER, p_ticket_type_id NUMBER, p_subject VARCHAR2, p_event_type_id NUMBER, p_host_id NUMBER, p_details_public VARCHAR2, p_details_private VARCHAR2 DEFAULT NULL, p_contact_id NUMBER DEFAULT NULL, p_worker_id NUMBER DEFAULT NULL, p_public_event BOOLEAN DEFAULT TRUE, p_eventdate DATE DEFAULT sysdate, p_company_id NUMBER DEFAULT NULL, p_service_component_id NUMBER DEFAULT NULL, p_zitadel_contact_id NUMBER DEFAULT NULL)`
- **PostgreSQL name:** `tt.ticket_interface_newticket_new` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/tt_ticket_interface.sql:33`
- **Defined:** `ddl/src/pkgb/tt_ticket_interface.sql:35-272`
- Opens a brand-new ticket and its first event: resolves company/service context from the
  host and/or contact, decides whether the contact qualifies as a company-wide admin owner,
  decides whether the ticket is auto-confirmed (automatic event source or OSAG-worker-
  opened), pulls two sequences, replaces `##ticket_id##`/`##event_id##` placeholders
  (`replace_id_placeholders`), inserts the `ticket` and `event` rows, sets the UX timeout,
  notifies (`TT.OSAG_NOTIFY.event_notify`), records a history event
  (`tt.event_interface.add_history_event`), runs `exec_event_type_actions`, optionally opens
  a change-request (ServiceNow integration heuristic), and updates the ticket-flow queue.
  **No procedure-level `EXCEPTION` block at all** — any unhandled error propagates fully to
  the caller (S-TICKET-001).

### change_deferral_date (PUBLIC)

- **Oracle signature:** `PROCEDURE change_deferral_date(p_ticket_id NUMBER, p_contact_id NUMBER, p_defer_date DATE, p_details_public tt.event.details_public%TYPE, p_zitadel_contact_id NUMBER DEFAULT NULL)`
- **PostgreSQL name:** `tt.ticket_interface_change_deferral_date` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/tt_ticket_interface.sql:57`
- **Defined:** `ddl/src/pkgb/tt_ticket_interface.sql:278-308`
- Changes the deferral date of a ticket only if it is currently in status 60 (deferred);
  otherwise logs a warning and does nothing. On the deferred path, updates
  `status_valid_until_date`/`last_deferral_date` and appends a new event via
  `tt.event_interface.addevent_new`. **No `EXCEPTION` block of its own** (S-TICKET-002).

### change_status_event_id_out (PUBLIC)

- **Oracle signature:** `PROCEDURE change_status_event_id_out(event_id OUT NUMBER, p_ticket_id NUMBER, p_status_id NUMBER, p_contact_id NUMBER, p_details_public VARCHAR2, p_details_private VARCHAR2 DEFAULT NULL, p_valid_until_date DATE DEFAULT null, p_defer_event NUMBER DEFAULT null, p_escalate_after_defer BOOLEAN DEFAULT NULL, p_hot_reason VARCHAR2 DEFAULT NULL, p_zitadel_contact_id NUMBER DEFAULT NULL)`
- **PostgreSQL name:** `tt.ticket_interface_change_status_event_id_out` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/tt_ticket_interface.sql:72`
- **Defined:** `ddl/src/pkgb/tt_ticket_interface.sql:346-557`
- The real status-change engine (`change_status` below is a thin delegator to this one, its
  `event_id` OUT discarded). Resolves current ticket state, no-ops if the new status equals
  the current one, updates time statistics (`updateTicketTimeStats`), writes the new status,
  clears a stale deferral date, builds the audit text, handles deferred-status transitions
  (`handleDeferredTransitions`), writes the status-change history event
  (`tt.event_interface.add_history_event`), optionally writes a "hot non-MCC ticket" event,
  updates `last_resolved_date`, deletes ticket notifications on delete-status, stops pending
  escalations, updates `status_valid_until_date` via `tt.util.update_status_valid_until`,
  recomputes `recoverable_status_id`, updates the UX timeout, and updates the ticket-flow
  queue. **No procedure-level `EXCEPTION` block** (S-TICKET-004 onward).

### change_status (PUBLIC)

- **Oracle signature:** `PROCEDURE change_status(p_ticket_id NUMBER, p_status_id NUMBER, p_contact_id NUMBER, p_details_public VARCHAR2, p_details_private VARCHAR2 DEFAULT NULL, p_valid_until_date DATE DEFAULT null, p_defer_event NUMBER DEFAULT null, p_escalate_after_defer BOOLEAN DEFAULT NULL, p_hot_reason VARCHAR2 DEFAULT NULL, p_zitadel_contact_id NUMBER DEFAULT NULL)`
- **PostgreSQL name:** `tt.ticket_interface_change_status` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/tt_ticket_interface.sql:85`
- **Defined:** `ddl/src/pkgb/tt_ticket_interface.sql:314-341`
- Pure delegator: calls `change_status_event_id_out` with a local `ev_id` that it discards.
  No `SELECT INTO` and no `EXCEPTION` block of its own — every strictness/exception fact
  from `change_status_event_id_out` applies transitively (S-TICKET-003).

### update_ux_timeout_for_ticket (PUBLIC)

- **Oracle signature:** `PROCEDURE update_ux_timeout_for_ticket(p_ticket_id tt.ticket.id%TYPE, p_is_initial BOOLEAN)`
- **PostgreSQL name:** `tt.ticket_interface_update_ux_timeout_for_ticket` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/tt_ticket_interface.sql:106`
- **Defined:** `ddl/src/pkgb/tt_ticket_interface.sql:563-647`
- Computes and writes the ticket's UX-timeout deadline from its type, emergency flag,
  handled-by-MCC flag, and status; clears the timeout entirely for excluded types/statuses;
  for maintenance tickets (type 12) may extend the window to 60 minutes after an associated
  service window's end. **No `EXCEPTION` block** (S-TICKET-006/007).

### change_worker (PUBLIC)

- **Oracle signature:** `PROCEDURE change_worker(p_ticket_id NUMBER, p_worker_id NUMBER, p_contact_id NUMBER, p_handled_by_mcc NUMBER DEFAULT 0, p_is_emergency NUMBER DEFAULT 0, p_reason VARCHAR2 DEFAULT NULL, p_zitadel_contact_id NUMBER DEFAULT NULL)`
- **PostgreSQL name:** `tt.ticket_interface_change_worker` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/tt_ticket_interface.sql:123`
- **Defined:** `ddl/src/pkgb/tt_ticket_interface.sql:653-756`
- Resolves the new and old worker names (each in its own local `BEGIN...EXCEPTION WHEN
  NO_DATA_FOUND` block, defaulting to a synthetic "MCC" label), updates `worker_id`,
  conditionally updates `handled_by_mcc` (and recomputes the UX timeout if it changed),
  builds a private "engineer changed to..." audit event, inserts it directly (not via
  `add_status_change_event`), and updates the ticket-flow queue. **No procedure-level
  `EXCEPTION` block** — everything outside the two local blocks propagates unhandled
  (S-TICKET-008 onward).

### change_subject (PUBLIC)

- **Oracle signature:** `PROCEDURE change_subject(p_ticket_id NUMBER, p_subject VARCHAR2, p_contact_id NUMBER, p_zitadel_contact_id NUMBER DEFAULT NULL)`
- **PostgreSQL name:** `tt.ticket_interface_change_subject` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/tt_ticket_interface.sql:137`
- **Defined:** `ddl/src/pkgb/tt_ticket_interface.sql:860-896`
- Looks up the customer id and old subject, inserts a public "ticket subject changed"
  audit event, and updates `ticket.subject`. **No `EXCEPTION` block** (S-TICKET-013/014).

### change_customer_reference (PUBLIC)

- **Oracle signature:** `PROCEDURE change_customer_reference(p_ticket_id NUMBER, p_customer_reference tt.ticket.customer_reference%TYPE, p_contact_id NUMBER, p_zitadel_contact_id NUMBER DEFAULT NULL)`
- **PostgreSQL name:** `tt.ticket_interface_change_customer_reference` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/tt_ticket_interface.sql:153`
- **Defined:** `ddl/src/pkgb/tt_ticket_interface.sql:901-924`
- **A Pitfall-2 hazard, handled CORRECTLY by the Oracle source itself, not a translation
  hazard.** `IF (p_customer_reference IS NOT NULL) THEN ... ELSE 'changed to <empty>'`
  (lines 911-915) — the source ALREADY treats `''` the same as `NULL` semantically for its
  own audit-text purposes (both produce a real value either way: the reference itself, or
  the literal string `'<empty>'`), so there is no divergence to translate here; noted for
  completeness (S-TICKET-015) since `p_customer_reference` is exactly the kind of parameter
  Checklist dimension 1 asks to be checked. Updates `ticket.customer_reference`
  unconditionally (even to `''` or `NULL` alike) and writes an audit event via the private
  `add_status_change_event`. No `SELECT INTO` at this routine's own level.

### change_label (PUBLIC, overload A — 2 args)

- **Oracle signature:** `PROCEDURE change_label(p_ticket_id NUMBER, p_label_id NUMBER)`
- **PostgreSQL name:** `tt.ticket_interface_change_label` (from `name-map.csv`, `is_overload=true`)
- **Declared:** `ddl/src/pkg/tt_ticket_interface.sql:168`
- **Defined:** `ddl/src/pkgb/tt_ticket_interface.sql:930-938`
- The bare form: a single `UPDATE tt.ticket SET label_id = p_label_id WHERE id = p_ticket_id`
  and nothing else — no audit event, no `SELECT`, no `EXCEPTION` block. This overload is
  itself called BY the 4-arg overload below (S-TICKET-016).

### change_label (PUBLIC, overload B — 3-4 args)

- **Oracle signature:** `PROCEDURE change_label(p_ticket_id NUMBER, p_label_id NUMBER, p_contact_id NUMBER, p_zitadel_contact_id NUMBER DEFAULT NULL)`
- **PostgreSQL name:** `tt.ticket_interface_change_label` (from `name-map.csv`, `is_overload=true`,
  distinct signature — PostgreSQL dispatches on argument COUNT/type exactly as Oracle does)
- **Declared:** `ddl/src/pkg/tt_ticket_interface.sql:183`
- **Defined:** `ddl/src/pkgb/tt_ticket_interface.sql:944-994`
- The audited form: resolves company id and old label id/name, resolves the new label name
  (if non-NULL), builds a private change-text describing the old→new transition, CALLS the
  2-arg overload above to perform the actual update, then inserts a private "attribute
  change event" directly (not via `add_status_change_event`). **No `EXCEPTION` block of its
  own** (S-TICKET-016 onward). The two overloads differ in argument COUNT (2 vs 3/4), not
  merely type — PostgreSQL's native overload resolution dispatches on this the same way
  Oracle's does.

### expire_status (PUBLIC)

- **Oracle signature:** `PROCEDURE expire_status(p_ticket_id NUMBER, p_valid_until DATE, p_last_change DATE, p_status_id NUMBER, p_status_name VARCHAR2, p_label_id NUMBER)`
- **PostgreSQL name:** `tt.ticket_interface_expire_status` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/tt_ticket_interface.sql:203`
- **Defined:** `ddl/src/pkgb/tt_ticket_interface.sql:999-1017`
- Computes an hours-elapsed figure from `p_valid_until - p_last_change`, builds a private
  "Status changed to: hot..." message, and calls `change_status(p_ticket_id, 3, NULL, NULL,
  v_private_details)` — i.e. forces the ticket to "hot" (status 3) with NULL contact and
  NULL public details. **Despite its doc-comment claiming it "calls change_label() and
  change_status()"** (`ddl/src/pkg/tt_ticket_interface.sql:191-202`), **the body only calls
  `change_status`** — `p_label_id` is accepted as a parameter but never read anywhere in the
  20-line body. This is a genuine doc/body disagreement (per the plan's own instruction that
  the body, not the doc comment, is authoritative) — recorded in Assumptions, not silently
  "fixed" by inventing a `change_label` call that Oracle does not make. No `SELECT INTO`, no
  `EXCEPTION` block of its own (S-TICKET-017).

### change_partner_reference (PUBLIC)

- **Oracle signature:** `PROCEDURE change_partner_reference(p_ticket_id NUMBER, p_partner_reference tt.ticket.partner_reference%TYPE, p_contact_id NUMBER, p_zitadel_contact_id NUMBER DEFAULT NULL)`
- **PostgreSQL name:** `tt.ticket_interface_change_partner_reference` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/tt_ticket_interface.sql:221`
- **Defined:** `ddl/src/pkgb/tt_ticket_interface.sql:1022-1045`
- Structurally identical to `change_customer_reference` (S-TICKET-015): the same
  Oracle-side `IS NOT NULL`/`'<empty>'` pattern, no divergence to translate. Updates
  `ticket.partner_reference` and writes via `add_status_change_event`. No `SELECT INTO`,
  no `EXCEPTION` block (S-TICKET-018).

### change_service_host (PUBLIC)

- **Oracle signature:** `PROCEDURE change_service_host(p_ticket_id NUMBER, p_service_id NUMBER, p_host_id NUMBER, p_contact_id NUMBER, p_zitadel_contact_id NUMBER DEFAULT NULL)`
- **PostgreSQL name:** `tt.ticket_interface_change_service_host` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/tt_ticket_interface.sql:234`
- **Defined:** `ddl/src/pkgb/tt_ticket_interface.sql:762-855`
- Builds a public "service changed from X to Y" audit string from FOUR independent
  local-handler-guarded lookups (old service, new service, old host, new host — each its
  own `BEGIN...EXCEPTION WHEN NO_DATA_FOUND`, each defaulting to `NULL`/`'<empty>'` on miss),
  inserts the audit event directly, then updates `mss_service_id`/`host_id` on the ticket.
  One un-guarded lookup (customer id) precedes all four. **No procedure-level `EXCEPTION`
  block** (S-TICKET-009 onward).

### change_owner (PUBLIC)

- **Oracle signature:** `PROCEDURE change_owner(p_ticket_id NUMBER, p_owner_id NUMBER, p_contact_id NUMBER, p_zitadel_owner_id NUMBER DEFAULT NULL, p_zitadel_contact_id NUMBER DEFAULT NULL, p_company_id NUMBER DEFAULT NULL, p_owner_zitadel_first_name VARCHAR2 DEFAULT NULL, p_owner_zitadel_last_name VARCHAR2 DEFAULT NULL)`
- **PostgreSQL name:** `tt.ticket_interface_change_owner` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/tt_ticket_interface.sql:252`
- **Defined:** `ddl/src/pkgb/tt_ticket_interface.sql:1050-1114`
- Three mutually exclusive branches resolve the audit text and company id: Zitadel names
  supplied directly (no DB lookup), an Oracle `p_owner_id` (looks up name + company),
  or neither (uses the ticket's own current company). Updates either
  `contact_zitadel_id`/`company_id` (Zitadel path) or `contact_id`/`company_id` (Oracle
  path) depending on whether `p_zitadel_owner_id`/`p_company_id` are both present, then
  inserts a public audit event directly. **No `EXCEPTION` block** (S-TICKET-019 onward).

### change_company (PUBLIC)

- **Oracle signature:** `PROCEDURE change_company(p_ticket_id NUMBER, p_company_id NUMBER, p_contact_id NUMBER, p_zitadel_contact_id NUMBER DEFAULT NULL)`
- **PostgreSQL name:** `tt.ticket_interface_change_company` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/tt_ticket_interface.sql:274`
- **Defined:** `ddl/src/pkgb/tt_ticket_interface.sql:1119-1196`
- Collects old company/host names for the audit text (host lookup only if
  `v_old_host_id IS NOT NULL`; company lookup only if `v_old_company_id IS NOT NULL`),
  resets `contact_id`/`contact_zitadel_id`/`mss_service_id`/`host_id` to NULL on the
  ticket (company change invalidates all of them), resolves the NEW company's short name
  in a locally-guarded block, inserts the audit event, then deletes/reassigns
  `event_notification` rows depending on whether the notified login belongs to OSAG
  (company 6). **No procedure-level `EXCEPTION` block** (S-TICKET-022 onward).

### change_emergency (PUBLIC)

- **Oracle signature:** `PROCEDURE change_emergency(p_ticket_id NUMBER, p_emergency NUMBER, p_contact_id NUMBER, p_is_new_ticket NUMBER DEFAULT 0, p_zitadel_contact_id NUMBER DEFAULT NULL)`
- **PostgreSQL name:** `tt.ticket_interface_change_emergency` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/tt_ticket_interface.sql:290`
- **Defined:** `ddl/src/pkgb/tt_ticket_interface.sql:1200-1230`
- Writes an audit event via the private `add_status_change_event`, updates `emergency` and
  the ratchet `was_emergency := GREATEST(p_emergency, was_emergency)`, and recomputes the
  UX timeout (treating `p_is_new_ticket` to choose the "initial" vs "not initial" timeout
  variant). No `SELECT INTO` at this routine's own level; no `EXCEPTION` block
  (S-TICKET-025).

### change_always_visible (PUBLIC)

- **Oracle signature:** `PROCEDURE change_always_visible(p_ticket_id NUMBER, p_always_visible NUMBER, p_contact_id NUMBER, p_zitadel_contact_id NUMBER DEFAULT NULL)`
- **PostgreSQL name:** `tt.ticket_interface_change_always_visible` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/tt_ticket_interface.sql:306`
- **Defined:** `ddl/src/pkgb/tt_ticket_interface.sql:1232-1254`
- Writes an audit event via `add_status_change_event`, updates `always_visible`. No
  `SELECT INTO`, no `EXCEPTION` block (S-TICKET-026).

### change_notification (PUBLIC)

- **Oracle signature:** `PROCEDURE change_notification(p_ticket_id NUMBER, p_change_text_public VARCHAR2, p_change_text_private VARCHAR2, p_contact_id NUMBER, p_zitadel_contact_id NUMBER DEFAULT NULL)`
- **PostgreSQL name:** `tt.ticket_interface_change_notification` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/tt_ticket_interface.sql:322`
- **Defined:** `ddl/src/pkgb/tt_ticket_interface.sql:1259-1283`
- Prefixes each of `p_change_text_public`/`p_change_text_private` with a fixed
  `'Notification settings changed\n'` constant ONLY if that parameter `IS NOT NULL`
  (leaving the corresponding local variable at its uninitialized `NULL` if the input is
  `NULL`), then delegates to `add_status_change_event`. This is the call site
  `TT.OSAG_NOTIFY.delete_ticket_notifications` (S-NOTIFY-021 in the sibling spec) uses to
  record its own notification-deletion audit trail. No `SELECT INTO`, no `EXCEPTION` block
  (S-TICKET-027).

### change_summary (PUBLIC)

- **Oracle signature:** `PROCEDURE change_summary(p_ticket_id NUMBER, p_summary_private VARCHAR2, p_summary_public VARCHAR2, p_contact_id NUMBER, p_zitadel_contact_id NUMBER DEFAULT NULL)`
- **PostgreSQL name:** `tt.ticket_interface_change_summary` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/tt_ticket_interface.sql:339`
- **Defined:** `ddl/src/pkgb/tt_ticket_interface.sql:1288-1336`
- Independently updates the private and public summary, each guarded by a
  change-detection condition that explicitly treats "old is NULL" / "new is NULL" /
  "old != new" as change-worthy (but "both NULL" as no-op) — this is itself a careful,
  Oracle-correct `!=`-with-NULLs formulation (S-TICKET-028). Resetting
  `summary_relevant_events_count` to 0 happens only on the PUBLIC summary path. No
  `EXCEPTION` block of its own (S-TICKET-029).

### change_type (PUBLIC)

- **Oracle signature:** `PROCEDURE change_type(p_event_id OUT NUMBER, p_ticket_id NUMBER, p_type_id NUMBER, p_contact_id NUMBER, p_zitadel_contact_id NUMBER DEFAULT NULL)`
- **PostgreSQL name:** `tt.ticket_interface_change_type` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/tt_ticket_interface.sql:357`
- **Defined:** `ddl/src/pkgb/tt_ticket_interface.sql:1342-1377`
- Resolves company id, old and new type names, updates `ticket.type_id`, inserts a public
  "type changed" audit event directly (NOT via `add_status_change_event`), then resolves
  `p_event_id` via `event_sequence.CurrVal` (relies on the immediately-preceding `INSERT`
  in the SAME session having just advanced the sequence — see S-TICKET-031), recomputes the
  UX timeout and the ticket-flow queue. **No `EXCEPTION` block** (S-TICKET-030 onward).

### change_service_component (PUBLIC)

- **Oracle signature:** `PROCEDURE change_service_component(p_event_id OUT NUMBER, p_ticket_id NUMBER, p_service_component_id NUMBER, p_contact_id NUMBER, p_zitadel_contact_id NUMBER DEFAULT NULL)`
- **PostgreSQL name:** `tt.ticket_interface_change_service_component` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/tt_ticket_interface.sql:375`
- **Defined:** `ddl/src/pkgb/tt_ticket_interface.sql:1382-1432`
- Same `CurrVal`-after-`INSERT` pattern as `change_type` (S-TICKET-031). Old/new service
  component code+name are each resolved in their OWN locally-guarded 2-statement block
  (both statements share one handler), defaulting to `''`/`'<empty>'` on miss. Updates
  `service_component_id`, inserts a public+private audit event, resolves `p_event_id`,
  recomputes the UX timeout. **No procedure-level `EXCEPTION` block** (S-TICKET-032
  onward).

### get_next_recent_ticket (PUBLIC, FUNCTION)

- **Oracle signature:** `FUNCTION get_next_recent_ticket(p_last_ticket_id NUMBER, p_host_id NUMBER, p_ticket_type_id NUMBER, p_resolve_age NUMBER) RETURN NUMBER`
- **PostgreSQL name:** `tt.ticket_interface_get_next_recent_ticket` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/tt_ticket_interface.sql:394`
- **Defined:** `ddl/src/pkgb/tt_ticket_interface.sql:1437-1465`
- One of the corpus's two `FUNCTION`s in this package. Finds the smallest open, non-deferred
  ticket id greater than `p_last_ticket_id` matching optional host/type/resolve-age filters
  — used by `TT.EVENT_INTERFACE.newevent_new`'s recent-ticket search loop (per
  `migration/spec/tt.event_interface.md` S-EVENT-009). **Has its own `EXCEPTION WHEN OTHERS`
  that logs and returns `NULL`** rather than propagating (S-TICKET-034) — see
  S-TICKET-091 for the FUNCTION/PROCEDURE-COMMIT trace (this routine calls nothing, and
  commits nothing).

### merge_tickets (PUBLIC)

- **Oracle signature:** `PROCEDURE merge_tickets(p_ticket_id NUMBER, p_mticket_id NUMBER, p_contact_id NUMBER, p_zitadel_contact_id NUMBER DEFAULT NULL)`
- **PostgreSQL name:** `tt.ticket_interface_merge_tickets` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/tt_ticket_interface.sql:408`
- **Defined:** `ddl/src/pkgb/tt_ticket_interface.sql:1470-1642`
- Merges the SOURCE ticket (`p_ticket_id`) into the TARGET ticket (`p_mticket_id`) — see
  S-TICKET-035 through S-TICKET-040 for the precise cascade/non-cascade semantics (ratings,
  events, notifications, change requests, suppressed signatures, partner reference,
  fast-resolvable flag, last-public-event/recoverable-status, UX timeout), the source
  ticket's own final state (`merged_into_ticket_id`, status 110 "merged", close/resolve
  dates), and the target's final state (status forced to 3 "hot"). **No procedure-level
  `EXCEPTION` block of its own** — every unhandled `SELECT INTO` here propagates fully
  (S-TICKET-035).

### replace_id_placeholders (PUBLIC, FUNCTION)

- **Oracle signature:** `FUNCTION replace_id_placeholders(p_text VARCHAR2, p_ticket_id NUMBER, p_event_id NUMBER) RETURN VARCHAR2`
- **PostgreSQL name:** `tt.ticket_interface_replace_id_placeholders` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/tt_ticket_interface.sql:423`
- **Defined:** `ddl/src/pkgb/tt_ticket_interface.sql:1647-1657`
- The package's OTHER `FUNCTION`. Pure string substitution (`REPLACE` of
  `##ticket_id##`/`##event_id##`, `SUBSTRB`-truncated to 30000 bytes each step) — **no
  `SELECT` of any kind, no call to any other routine, no `EXCEPTION` block**. Confirmed by
  reading the full 11-line body. **There is no FUNCTION/PROCEDURE-COMMIT hazard for this
  routine** — it cannot transitively reach a `COMMIT` because it calls nothing at all
  (S-TICKET-041, closes this plan's own flagged question for this routine — mirrors
  `TT.EVENT_INTERFACE.ticket_type_for_event_type`'s S-EVENT-034 finding).

### trigger_escalation (PUBLIC)

- **Oracle signature:** `PROCEDURE trigger_escalation(p_ticket_id NUMBER, p_contact_id NUMBER, p_triggering_event_id NUMBER, p_zitadel_contact_id NUMBER DEFAULT NULL)`
- **PostgreSQL name:** `tt.ticket_interface_trigger_escalation` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/tt_ticket_interface.sql:436`
- **Defined:** `ddl/src/pkgb/tt_ticket_interface.sql:1708-1735`
- Writes a public "escalation triggered" history event
  (`tt.event_interface.add_history_event`) then runs `exec_event_type_actions`. **Has its
  own `EXCEPTION WHEN OTHERS THEN plog.err(...)`** that logs and swallows — never
  propagates (S-TICKET-042). No `SELECT INTO` at this routine's own level.

### rate_ticket (PUBLIC)

- **Oracle signature:** `PROCEDURE rate_ticket(p_rating_id OUT NUMBER, p_ticket_id NUMBER, p_rating_event_id NUMBER, p_contact_id NUMBER, p_by_engineer NUMBER, p_rating_value NUMBER, p_zitadel_contact_id NUMBER DEFAULT NULL)`
- **PostgreSQL name:** `tt.ticket_interface_rate_ticket` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/tt_ticket_interface.sql:451`
- **Defined:** `ddl/src/pkgb/tt_ticket_interface.sql:1741-1774`
- Pulls a sequence for the new rating id, inserts `ticket_rating`, sets EITHER
  `engineer_ticket_rating_id` OR `customer_ticket_rating_id` on the ticket depending on
  `p_by_engineer`, and — only for a bad CUSTOMER rating (`< 3`) — forces the ticket to
  "hot" (status 3) via `change_status`. **No `EXCEPTION` block of its own**
  (S-TICKET-043).

### add_docs_page (PUBLIC)

- **Oracle signature:** `PROCEDURE add_docs_page(p_ticket_docs_page_id OUT NUMBER, p_ticket_id NUMBER, p_page_id NUMBER, p_page_version NUMBER, p_page_title VARCHAR2, p_hot_issue NUMBER, p_contact_id NUMBER, p_zitadel_contact_id NUMBER DEFAULT NULL)`
- **PostgreSQL name:** `tt.ticket_interface_add_docs_page` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/tt_ticket_interface.sql:467`
- **Defined:** `ddl/src/pkgb/tt_ticket_interface.sql:1780-1811`
- Pulls a sequence, inserts `ticket_docs_page`, builds a private "Docs Page added" text
  (prefixed "Hot issue" if `p_hot_issue > 0`), and calls
  `event_interface.addevent_new`. **Has its own `EXCEPTION WHEN OTHERS THEN plog.err(...)`**
  that logs and swallows (S-TICKET-044).

### remove_docs_page (PUBLIC)

- **Oracle signature:** `PROCEDURE remove_docs_page(p_ticket_docs_page_id NUMBER, p_page_title VARCHAR2, p_contact_id NUMBER, p_zitadel_contact_id NUMBER DEFAULT NULL)`
- **PostgreSQL name:** `tt.ticket_interface_remove_docs_page` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/tt_ticket_interface.sql:485`
- **Defined:** `ddl/src/pkgb/tt_ticket_interface.sql:1817-1846`
- Looks up the docs-page row (page id/version/ticket id), deletes it, then calls
  `event_interface.addevent_new` to record the removal. **Has a 2-arm handler**:
  `WHEN NO_DATA_FOUND THEN NULL` (silently does nothing further — the DELETE and
  addevent_new never run for a bad `p_ticket_docs_page_id`) and
  `WHEN OTHERS THEN plog.err(...)` (S-TICKET-045).

### add_related_ticket (PUBLIC)

- **Oracle signature:** `PROCEDURE add_related_ticket(p_ticket_id tt.ticket.id%TYPE, p_related_ticket_id tt.ticket.id%TYPE, p_contact_id stop.contact.id%TYPE, p_zitadel_contact_id NUMBER DEFAULT NULL)`
- **PostgreSQL name:** `tt.ticket_interface_add_related_ticket` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/tt_ticket_interface.sql:499`
- **Defined:** `ddl/src/pkgb/tt_ticket_interface.sql:1925-1955`
- Verifies BOTH tickets exist via a `COUNT(*) ... IN (p_ticket_id, p_related_ticket_id)`
  check (`v_counter != 2` covers both "one doesn't exist" AND "both ids are equal" in one
  test — logs and `RETURN`s early, not an exception path), inserts the relation, records a
  history event. **Has its own `EXCEPTION WHEN OTHERS THEN plog.err(...); RETURN`**
  (S-TICKET-046).

### remove_related_ticket (PUBLIC)

- **Oracle signature:** `PROCEDURE remove_related_ticket(p_ticket_id tt.ticket.id%TYPE, p_related_ticket_id tt.ticket.id%TYPE, p_contact_id stop.contact.id%TYPE, p_zitadel_contact_id NUMBER DEFAULT NULL)`
- **PostgreSQL name:** `tt.ticket_interface_remove_related_ticket` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/tt_ticket_interface.sql:512`
- **Defined:** `ddl/src/pkgb/tt_ticket_interface.sql:1960-1989`
- Mirror of `add_related_ticket`: counts the existing relation row, and only if `> 0`
  deletes it and records a history event — zero matches is a normal silent no-op, not an
  error path. Same `EXCEPTION WHEN OTHERS THEN plog.err(...); RETURN` shape
  (S-TICKET-047).

### add_related_file (PUBLIC)

- **Oracle signature:** `PROCEDURE add_related_file(p_ticket_id tt.ticket.id%TYPE, p_related_file_id mc.mc_file.id%TYPE, p_contact_id stop.contact.id%TYPE, p_zitadel_contact_id NUMBER DEFAULT NULL)`
- **PostgreSQL name:** `tt.ticket_interface_add_related_file` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/tt_ticket_interface.sql:524`
- **Defined:** `ddl/src/pkgb/tt_ticket_interface.sql:1995-2028`
- Resolves the MC file's display name via a THREE-way join that DELIBERATELY doubles as a
  same-company guard (`t.company_id = r.company_id`) — the routine's own inline comment
  states the `NO_DATA_FOUND` this triggers on a cross-company mismatch IS the intended
  authorization check, not incidental (S-TICKET-048). **2-arm handler**:
  `WHEN NO_DATA_FOUND THEN plog.err(...); RETURN` (logs the specific
  "does not exist or different companies" message) and `WHEN OTHERS THEN plog.err(...);
  RETURN`.

### remove_related_file (PUBLIC)

- **Oracle signature:** `PROCEDURE remove_related_file(p_ticket_id tt.ticket.id%TYPE, p_related_file_id mc.mc_file.id%TYPE, p_contact_id stop.contact.id%TYPE, p_zitadel_contact_id NUMBER DEFAULT NULL)`
- **PostgreSQL name:** `tt.ticket_interface_remove_related_file` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/tt_ticket_interface.sql:537`
- **Defined:** `ddl/src/pkgb/tt_ticket_interface.sql:2035-2069`
- Counts the existing relation row; only if `> 0`, resolves the file's display name (a
  SEPARATE, un-guarded lookup — no same-company check here unlike `add_related_file`),
  deletes the relation, and records a history event. **`EXCEPTION WHEN OTHERS THEN
  plog.err(...); RETURN`** (S-TICKET-049) — no `NO_DATA_FOUND` arm; a bad
  `p_related_file_id` inside the `IF v_counter > 0` branch would hit `WHEN OTHERS`
  instead.

### classify_request (PUBLIC)

- **Oracle signature:** `PROCEDURE classify_request(p_ticket_id tt.ticket.id%TYPE, p_classification tt.ticket_request_classification.classification%TYPE, p_contact_id stop.contact.id%TYPE, p_zitadel_contact_id NUMBER DEFAULT NULL)`
- **PostgreSQL name:** `tt.ticket_interface_classify_request` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/tt_ticket_interface.sql:552`
- **Defined:** `ddl/src/pkgb/tt_ticket_interface.sql:2078-2125`
- Maps `p_classification` (1/2/3) to a text label, defaulting silently to "standard" (2)
  for any OTHER input value including NULL (S-TICKET-050 — no error is raised for an
  invalid classification, contradicting the doc comment's implication that only 1/2/3 are
  valid). Upserts (via a `COUNT`-then-`UPDATE`-or-`INSERT`, not a native `MERGE`) the
  ticket's single classification row, then records a history event. **`EXCEPTION WHEN
  OTHERS THEN plog.err(...); RETURN`** (S-TICKET-051).

### clear_todo_list (PUBLIC)

- **Oracle signature:** `PROCEDURE clear_todo_list(p_ticket_id NUMBER, p_contact_id NUMBER, p_add_history_event NUMBER DEFAULT 1, p_zitadel_contact_id NUMBER DEFAULT NULL)`
- **PostgreSQL name:** `tt.ticket_interface_clear_todo_list` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/tt_ticket_interface.sql:565`
- **Defined:** `ddl/src/pkgb/tt_ticket_interface.sql:2132-2173`
- Deletes ALL `todo_item` rows for the ticket unconditionally, optionally (if
  `p_add_history_event = 1`) records a private "todo list cleared" history event via
  `tt.event_interface.add_history_event`, and resets `steps_total`/`steps_completed` to 0.
  **No `EXCEPTION` block of its own** (S-TICKET-052).

### add_todo_item (PUBLIC)

- **Oracle signature:** `PROCEDURE add_todo_item(p_todo_item_id OUT NUMBER, p_ticket_id NUMBER, p_seq_no NUMBER, p_details VARCHAR2, p_todo_item_status_id NUMBER, p_contact_id NUMBER, p_todo_item_is_public NUMBER DEFAULT 0, p_zitadel_contact_id NUMBER DEFAULT NULL)`
- **PostgreSQL name:** `tt.ticket_interface_add_todo_item` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/tt_ticket_interface.sql:580`
- **Defined:** `ddl/src/pkgb/tt_ticket_interface.sql:2181-2217`
- Pulls a sequence, inserts the `todo_item` row, and — only for PUBLIC todo items —
  increments `steps_total`, conditionally increments `steps_completed` (statuses 2/4 =
  done/skipped), and resets `todo_relevant_events_count` to 0. **Per its own doc comment,
  deliberately does NOT write a history event itself** — callers are expected to batch
  multiple `add_todo_item` calls and write ONE shared history event (S-TICKET-053). No
  `EXCEPTION` block.

### update_todo_item_status (PUBLIC)

- **Oracle signature:** `PROCEDURE update_todo_item_status(p_ticket_id NUMBER, p_seq_no NUMBER, p_todo_item_status_id NUMBER, p_contact_id NUMBER, p_zitadel_contact_id NUMBER DEFAULT NULL)`
- **PostgreSQL name:** `tt.ticket_interface_update_todo_item_status` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/tt_ticket_interface.sql:600`
- **Defined:** `ddl/src/pkgb/tt_ticket_interface.sql:2223-2309`
- Resolves the current todo item (old status name/details/public flag) via a `LEFT JOIN`
  to `todo_item_status`, updates its status, resolves ticket host/company and the NEW
  status name, builds public-or-private history text depending on `is_public`, adjusts
  `steps_completed` on specific status transitions (public items only), resets
  `todo_relevant_events_count`, and records the history event via
  `tt.event_interface.add_history_event`. **No `EXCEPTION` block of its own**
  (S-TICKET-054 onward).

### updateTicketFlow (PUBLIC)

- **Oracle signature:** `PROCEDURE updateTicketFlow(p_ticket_id NUMBER, p_prev_status_id NUMBER DEFAULT NULL, p_prev_status_change_date DATE DEFAULT NULL)`
- **PostgreSQL name:** `tt.ticket_interface_updateticketflow` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/tt_ticket_interface.sql:615`
- **Defined:** `ddl/src/pkgb/tt_ticket_interface.sql:2366-2439`
- Checks whether the ticket currently has an open (`flow_out_date IS NULL`) MCC-queue
  entry, then decides — from status/type/`handled_by_mcc` — whether to insert a new queue
  entry, close an existing one (accumulating `open_time`), or leave it alone. Called by
  every routine that changes status/type/worker (per the plan's own note). **No
  `EXCEPTION` block of its own** (S-TICKET-057 onward).

### deleteTicket (PUBLIC)

- **Oracle signature:** `PROCEDURE deleteTicket(p_ticket_id NUMBER)`
- **PostgreSQL name:** `tt.ticket_interface_deleteticket` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/tt_ticket_interface.sql:624`
- **Defined:** `ddl/src/pkgb/tt_ticket_interface.sql:2441-2482`
- See S-TICKET-059/060 for the exact cascade/non-cascade enumeration (a strict sequence of
  31 `UPDATE .. SET x = NULL` / `DELETE` statements across 20+ tables, in the specific
  order Oracle executes them, ending with the `TT.TICKET` row itself). **No `SELECT INTO`
  anywhere** (only `UPDATE`/`DELETE`, several with `IN (SELECT ...)` subqueries that are
  NOT `SELECT INTO` and carry no `STRICT` concern). **No `EXCEPTION` block at all** — any
  constraint violation partway through propagates fully unhandled, leaving whatever
  statements already ran committed-pending in the CALLER's transaction (no `COMMIT`
  anywhere in this package, per Checklist dimension 5) (S-TICKET-059).

## Private routines (used internally, no `name-map.csv` row)

**3 private routines**, matching the Phase 1 inventory exactly (confirmed by reading the
full 2,484-line body and counting every declaration below the three forward declarations
at the top, `ddl/src/pkgb/tt_ticket_interface.sql:7-29`): `add_status_change_event`,
`handleDeferredTransitions`, `updateTicketTimeStats`. Per plan 02-05's convention (reused
here, not reinvented — see `migration/spec/tt.osag_notify.md`, "Private routines — naming
convention"), the recommended PostgreSQL names are `tt.ticket_interface__add_status_change_event`,
`tt.ticket_interface__handledeferredtransitions`, `tt.ticket_interface__updateticketimestats`
(schema-level function, `__` double-underscore marker prefix, `REVOKE ALL ... FROM
PUBLIC`). Same standing caveat as the sibling specs: this convention lives outside
`migration/mapping/name-map.csv` and is not finalized by this spec — flagged again in this
plan's SUMMARY.

- **`add_status_change_event`** (`ddl/src/pkgb/tt_ticket_interface.sql:1663-1702`) — the
  shared audit-event writer used by `change_customer_reference`, `change_partner_reference`,
  `change_emergency`, `change_always_visible`, `change_notification`, `change_summary`. See
  S-TICKET-060a for **a genuine, previously-undocumented bug**: it declares `cust_id
  NUMBER;` and inserts it as the event's `company_id` — but NEVER assigns `cust_id`
  anywhere in its 40-line body. Every audit event this routine writes has `company_id =
  NULL`, regardless of the ticket's real company. Documented faithfully as a real Oracle
  behavior (not silently "fixed"), per the plan's own instruction and the precedent set by
  `TT.EVENT_INTERFACE.moveevent`'s acknowledged bug (S-EVENT-033 in the sibling spec).
- **`handleDeferredTransitions`** (`ddl/src/pkgb/tt_ticket_interface.sql:1859-1919`) —
  called only from `change_status_event_id_out` when the ticket transitions into or out of
  deferred (status 60); manages the escalation-status side effects of that transition. Has
  its own `EXCEPTION WHEN OTHERS THEN plog.err(...); RETURN` (S-TICKET-061).
- **`updateTicketTimeStats`** (`ddl/src/pkgb/tt_ticket_interface.sql:2313-2359`) — called
  only from `change_status_event_id_out`, accumulates per-status elapsed time into
  `tt.ticket_time_statistic`, using a `SELECT`-then-`MERGE`-then-re-`SELECT` pattern to
  avoid a race on first-row creation (S-TICKET-062). No `EXCEPTION` block of its own beyond
  the local `NO_DATA_FOUND` guarding the create-row path.

