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

