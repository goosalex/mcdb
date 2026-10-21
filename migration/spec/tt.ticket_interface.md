---
oracle_schema: TT
oracle_package: TICKET_INTERFACE
pg_schema: tt
pg_prefix: ticket_interface
clause_prefix: TICKET
oracle_spec: ddl/src/pkg/tt_ticket_interface.sql
oracle_body: ddl/src/pkgb/tt_ticket_interface.sql
public_routines: 37
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
TT.TICKET_INTERFACE|TT.UTIL` cycle group) — see S-TICKET-057 and
`migration/spec/tt.event_interface.md` for the reverse direction, already committed and
consistent with this spec. `static_resolution: complete` — no dynamic SQL anywhere in this
package (confirmed against `migration/analyze/inventory.json`'s
`static_resolution_reasons: []` for `TT.TICKET_INTERFACE`).

**Front-matter note on `public_routines`:** this package has **38 distinct public routine
declarations** in `migration/mapping/name-map.csv` (38 rows) — the front-matter
`public_routines: 37` above is NOT a scope reduction; it matches
`migration/analyze/inventory.json`'s routine list, which is a *name*-keyed set and
therefore counts the `change_label` overload PAIR once (both share the name
`change_label`, distinct signatures). `spec_lint.py`'s front-matter cross-check compares
against that same deduplicated inventory count, so `37` is the value that check expects.
Both `change_label` overloads are nonetheless specced as two fully distinct routines
below (see `## Routines` and S-TICKET-019/S-TICKET-020) — nothing about this package's
scope is reduced by this front-matter bookkeeping detail.

## Routines

### newticket_new (PUBLIC)

- **Oracle signature:** `PROCEDURE newticket_new(p_ticket_id OUT NUMBER, p_event_id OUT NUMBER, p_ticket_type_id NUMBER, p_subject VARCHAR2, p_event_type_id NUMBER, p_host_id NUMBER, p_details_public VARCHAR2, p_details_private VARCHAR2 DEFAULT NULL, p_contact_id NUMBER DEFAULT NULL, p_worker_id NUMBER DEFAULT NULL, p_public_event BOOLEAN DEFAULT TRUE, p_eventdate DATE DEFAULT sysdate, p_company_id NUMBER DEFAULT NULL, p_service_component_id NUMBER DEFAULT NULL, p_zitadel_contact_id NUMBER DEFAULT NULL)`
- **PostgreSQL name:** `tt.ticket_interface_newticket_new` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/tt_ticket_interface.sql:33`
- **Defined:** `ddl/src/pkgb/tt_ticket_interface.sql:35-303` (2026-10-20 export; was 35-272)
- Opens a brand-new ticket and its first event: resolves company/service context from the
  host and/or contact, decides whether the contact qualifies as a company-wide admin owner,
  decides whether the ticket is auto-confirmed (automatic event source or OSAG-worker-
  opened), pulls two sequences, replaces `##ticket_id##`/`##event_id##` placeholders
  (`replace_id_placeholders`), inserts the `ticket` and `event` rows, sets the UX timeout,
  notifies (`TT.OSAG_NOTIFY.event_notify`), records a history event
  (`tt.event_interface.add_history_event`), runs `exec_event_type_actions`, optionally opens
  a change-request (ServiceNow integration heuristic), and updates the ticket-flow queue.
  **2026-10-20 export:** the contact used for company resolution, owner check, change request
  and event contact is the *resolved sender* -- `p_contact_id`, or for a ServiceNow sign-off
  sender known only by Zitadel user ID the contact of the `auth.login` row carrying that ID
  (S-TICKET-061, S-TICKET-062); the ticket row also records the worker's Zitadel ID
  (S-TICKET-063).
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
- **Defined:** `ddl/src/pkgb/tt_ticket_interface.sql:684-788` (2026-10-20 export; was 653-756)
- Resolves the new and old worker names (each in its own local `BEGIN...EXCEPTION WHEN
  NO_DATA_FOUND` block, defaulting to a synthetic "MCC" label), updates `worker_id`,
  conditionally updates `handled_by_mcc` (and recomputes the UX timeout if it changed),
  since the 2026-10-20 export also writes `worker_zitadel_id` in the same UPDATE as
  `worker_id` (S-TICKET-063),
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
  "fixed" by inventing a `change_label` call that Oracle does not make. **Re-examined on
  branch `phoenix/migrate_tt_only` (Q11 (c)) and deliberately LEFT AS THE BODY DOES** —
  the evidence (S-TICKET-021, amended) shows the omitted call would be a no-op: the sole
  caller passes the ticket's own current label. No `SELECT INTO`, no
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
  S-TICKET-046 for the FUNCTION/PROCEDURE-COMMIT trace (this routine calls nothing, and
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
- Counts the existing relation row; only if `> 0`, resolves the file's display name (in
  Oracle a SEPARATE, un-guarded lookup — no same-company check, unlike
  `add_related_file`), deletes the relation, and records a history event. Oracle's
  handler is **`EXCEPTION WHEN OTHERS THEN plog.err(...); RETURN`** only — no
  `NO_DATA_FOUND` arm. **CORRECTED on branch `phoenix/migrate_tt_only`** (status report
  2026-10-13, Q11 (d)): the translation's display-name lookup carries the SAME
  same-company guard `add_related_file` applies (S-TICKET-044), and a mirrored
  `NO_DATA_FOUND` arm logs the mismatch; a caller can no longer detach a file relation
  across companies. See S-TICKET-045 (amended) and S-TICKET-060 (new).

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
- See S-TICKET-052 for the exact cascade/non-cascade enumeration (a strict sequence of
  31 `UPDATE .. SET x = NULL` / `DELETE` statements across 20+ tables, in the specific
  order Oracle executes them, ending with the `TT.TICKET` row itself). **No `SELECT INTO`
  anywhere** (only `UPDATE`/`DELETE`, several with `IN (SELECT ...)` subqueries that are
  NOT `SELECT INTO` and carry no `STRICT` concern). **No `EXCEPTION` block at all** — any
  constraint violation partway through propagates fully unhandled, leaving whatever
  statements already ran committed-pending in the CALLER's transaction (no `COMMIT`
  anywhere in this package, per Checklist dimension 5) (S-TICKET-052).

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
  S-TICKET-053 for **a genuine, previously-undocumented bug**: it declares `cust_id
  NUMBER;` and inserts it as the event's `company_id` — but NEVER assigns `cust_id`
  anywhere in its 40-line body. Every audit event this routine writes has `company_id =
  NULL`, regardless of the ticket's real company. Originally documented faithfully as a
  real Oracle behavior (not silently "fixed"). **CORRECTED on branch
  `phoenix/migrate_tt_only`** (status report 2026-10-13, Q11 (b); project-owner
  instruction "Don't mimic broken behaviour of oracle routines, but annotate/explain what
  changed with the correction"): the translation resolves `cust_id` from the ticket row
  exactly as the sibling audit-event writers do (`change_subject` line 873,
  `change_worker` line 715, `change_service_host` line 779: `SELECT company_id INTO
  cust_id FROM ticket WHERE id = p_ticket_id`) — see S-TICKET-053 (amended) and
  S-TICKET-059 (new).
- **`handleDeferredTransitions`** (`ddl/src/pkgb/tt_ticket_interface.sql:1859-1919`) —
  called only from `change_status_event_id_out` when the ticket transitions into or out of
  deferred (status 60); manages the escalation-status side effects of that transition. Has
  its own `EXCEPTION WHEN OTHERS THEN plog.err(...); RETURN` (S-TICKET-054).
- **`updateTicketTimeStats`** (`ddl/src/pkgb/tt_ticket_interface.sql:2313-2359`) — called
  only from `change_status_event_id_out`, accumulates per-status elapsed time into
  `tt.ticket_time_statistic`, using a `SELECT`-then-`MERGE`-then-re-`SELECT` pattern to
  avoid a race on first-row creation (S-TICKET-055). No `EXCEPTION` block of its own beyond
  the local `NO_DATA_FOUND` guarding the create-row path.

## Clauses

### S-TICKET-001

- **routines:** newticket_new
- **claim:** SELECT INTO sites #1-#2 (inventory lines 86, 89), reached only when
  `p_host_id IS NOT NULL`: `SELECT h.service_company_id INTO v_company_id FROM mss.host h
  WHERE h.id = p_host_id` (line 86, `HOST_PK` — `TOO_MANY_ROWS` impossible, zero rows
  reachable for a bad `p_host_id`) immediately followed by
  `SELECT h2s.service_id INTO v_mss_service_id FROM mss.host2service h2s WHERE h2s.host_id
  = p_host_id` (line 89). **Amended 2026-10-21: `TOO_MANY_ROWS` at site #2 is structurally
  IMPOSSIBLE.** The original text derived a multi-row hazard from `mss.host2service`'s
  primary key `(HOST_ID, SERVICE_ID)` alone (`ddl/generated/schema.oracle.sql:81`); the same
  export also carries `CREATE UNIQUE INDEX MSS.IDX_H2S_HOST_UN ON MSS.HOST2SERVICE(HOST_ID)`
  (`ddl/generated/schema.oracle.sql:3700`, created by `changes/changelog-2.archive.sql:1884`),
  so a host is mapped to AT MOST ONE service — confirmed live against the Oracle container
  (`ORA-00001: unique constraint (MSS.IDX_H2S_HOST_UN) violated` on a second row, scenario
  `tt__event_interface__newevent`). Zero rows (a host with no `host2service` row) remains
  reachable at site #2 and is the hazard that matters. The same correction applies to
  `migration/spec/tt.event_interface.md` S-EVENT-001 (amended the same day);
  `migration/spec/tt.osag_notify.md` S-NOTIFY-003 rests on the same assumption and should be
  re-read. The PostgreSQL template lacked the index (not in the ora2pg output) —
  `migration/test/schema-fixes/29_host2service_unique_fixes.sql` adds it. **`newticket_new`
  has NO procedure-level `EXCEPTION` block at all** (confirmed reading the full 238-line
  body, `ddl/src/pkgb/tt_ticket_interface.sql:35-272`), so a zero-row failure at either
  site propagates FULLY unhandled to whatever calls `newticket_new`.
- **source:** `ddl/src/pkgb/tt_ticket_interface.sql:35, 85-91, 272`, `ddl/generated/schema.oracle.sql:81, 3700`

### S-TICKET-002

- **routines:** newticket_new
- **claim:** SELECT INTO site #3 (inventory line 98), reached only when `p_contact_id IS
  NOT NULL`: `SELECT company_id INTO v_company_id FROM stop.contact WHERE contact.id =
  p_contact_id` — `CONTACT_PK`, `TOO_MANY_ROWS` structurally impossible; zero rows
  reachable for a bad `p_contact_id`. No handler anywhere in `newticket_new` — propagates
  fully unhandled, same as S-TICKET-001. This lookup deliberately OVERRIDES whatever
  `v_company_id` the host branch (S-TICKET-001) may have already set (the routine's own
  comment: "this overrides the company selection from the service id").
- **source:** `ddl/src/pkgb/tt_ticket_interface.sql:96-100`

### S-TICKET-003

- **routines:** newticket_new
- **claim:** SELECT INTO sites #4 and #8 (inventory lines 108, 125): site #4
  (`SELECT count(*) INTO v_count FROM auth.permission p, auth.login l WHERE ...`) is a
  `COUNT` aggregate — always exactly one row, no `STRICT` concern of any kind — used only
  to decide whether a NULL-host, non-NULL-contact ticket's contact qualifies as a
  company-wide admin owner. Site #8, `SELECT source INTO v_event_source_id FROM
  tt.event_type WHERE id = p_event_type_id` (`EVENTTYPE_PK`, `TOO_MANY_ROWS` impossible,
  zero rows reachable for a bad `p_event_type_id`), determines whether the new ticket is
  auto-confirmed. Neither has a local handler; both propagate to `newticket_new`'s total
  absence of an outer handler (S-TICKET-001).
- **source:** `ddl/src/pkgb/tt_ticket_interface.sql:106-115, 123-129`

### S-TICKET-004

- **routines:** newticket_new
- **claim:** SELECT INTO site #6 (inventory line 133), reached only when `p_worker_id IS
  NOT NULL`: `SELECT company_id INTO v_contact_company_id FROM stop.contact WHERE id =
  p_worker_id` — `CONTACT_PK`, `TOO_MANY_ROWS` impossible, zero rows reachable. Used only
  to auto-confirm tickets opened by an OSAG (company 6) worker. No handler; propagates
  unhandled.
- **source:** `ddl/src/pkgb/tt_ticket_interface.sql:132-137`

### S-TICKET-005

- **routines:** newticket_new
- **claim:** SELECT INTO sites #7 and #9 (inventory lines 141, 142, 254): `SELECT
  ticket_sequence.NEXTVAL INTO p_ticket_id FROM dual` and `SELECT event_sequence.NEXTVAL
  INTO p_event_id FROM dual` (lines 141-142, unconditional) and, ONLY when the
  ServiceNow-integration heuristic fires (`v_create_cr = 1`), `SELECT
  changerequest_seq.NEXTVAL INTO v_cr_id FROM dual` (line 254) — three ordinary
  sequence-pull-via-`DUAL` sites, no `STRICT` concern at any of them (a sequence
  `NEXTVAL` always returns exactly one value). The Oracle `sequence.NEXTVAL FROM DUAL`
  idiom has no direct PostgreSQL syntax and needs `nextval('tt.<sequence>')` or
  equivalent — a corpus-wide mechanic, not specific to this package (same note as
  `migration/spec/tt.event_interface.md`'s S-EVENT-011).
- **source:** `ddl/src/pkgb/tt_ticket_interface.sql:141-142, 252-268`

### S-TICKET-006

- **routines:** change_deferral_date
- **claim:** SELECT INTO site #10 (inventory line 289), unconditional:
  `SELECT status_id INTO v_ticket_status_id FROM tt.ticket t WHERE t.id = p_ticket_id` —
  `TICKET_PK`, `TOO_MANY_ROWS` impossible, zero rows reachable for a bad `p_ticket_id`.
  SELECT INTO site #11 (inventory line 295), reached ONLY when `v_ticket_status_id = 60`
  (deferred): `SELECT t.host_id INTO v_host_id FROM tt.ticket t WHERE t.id = p_ticket_id`
  — same PK, same structural profile. **`change_deferral_date` has no `EXCEPTION` block
  of its own** (confirmed reading the full 31-line body,
  `ddl/src/pkgb/tt_ticket_interface.sql:278-308`) — both sites' failures propagate fully
  unhandled. If the ticket is NOT deferred, the routine logs a warning and does nothing
  (a normal, non-exceptional branch, not related to either `SELECT INTO`).
- **source:** `ddl/src/pkgb/tt_ticket_interface.sql:278-308`

### S-TICKET-007

- **routines:** change_status
- **claim:** `change_status` is a pure delegator to `change_status_event_id_out`,
  discarding that routine's `event_id OUT` parameter into a local `ev_id` it never reads.
  No `SELECT INTO` and no `EXCEPTION` block of its own — every strictness/exception fact
  established for `change_status_event_id_out` (S-TICKET-008 onward) applies transitively
  and identically when reached via this delegator.
- **source:** `ddl/src/pkgb/tt_ticket_interface.sql:314-341`

### S-TICKET-008

- **routines:** change_status_event_id_out
- **claim:** SELECT INTO site #12 (inventory line 381), unconditional, the routine's main
  ticket-state read: `SELECT t.status_id, t.handled_by_mcc, t.last_public_event_id,
  t.escalation_status_id, t.status_valid_until_date, t.last_status_change_date,
  t.last_deferral_date, SYSDATE INTO ... FROM tt.ticket t WHERE t.id = p_ticket_id` —
  8-column single-row `TICKET_PK` lookup, `TOO_MANY_ROWS` structurally impossible, zero
  rows reachable for a bad `p_ticket_id`. SELECT INTO site #13 (inventory line 389),
  reached only when `v_last_public_event_id IS NOT NULL`: `SELECT event.type_id INTO
  v_last_public_event_type_id FROM tt.event WHERE event.id = v_last_public_event_id` —
  `EVENT_PK`, same profile. **`change_status_event_id_out` has NO procedure-level
  `EXCEPTION` block** (confirmed reading the full 212-line body,
  `ddl/src/pkgb/tt_ticket_interface.sql:346-557`) — both sites propagate fully unhandled.
  If the new status equals the current one, the routine `RETURN`s immediately (line 396,
  a normal no-op, not an exception).
- **source:** `ddl/src/pkgb/tt_ticket_interface.sql:381-391, 395-397`

### S-TICKET-009

- **routines:** change_status_event_id_out
- **claim:** SELECT INTO sites #14 and #15 (inventory lines 416, 417), unconditional,
  back-to-back: `SELECT name INTO status_name FROM status WHERE id = p_status_id` and
  `SELECT name INTO v_cur_status_name FROM status WHERE id = v_cur_status` — both
  `STATUS_PK` lookups (`TOO_MANY_ROWS` impossible), zero rows reachable if either status
  id is invalid. SELECT INTO site #16 (inventory line 435), unconditional: `SELECT
  type_id INTO l_ticket_type_id FROM tt.ticket WHERE id = p_ticket_id` — `TICKET_PK`,
  same profile, and notably its result (`l_ticket_type_id`) is READ NOWHERE ELSE IN THE
  ROUTINE (dead local variable — harmless, but the `SELECT INTO` itself still carries
  the same zero-row hazard as every other unguarded site here). None of the three has a
  local handler; all propagate to the total absence of an outer handler (S-TICKET-008).
- **source:** `ddl/src/pkgb/tt_ticket_interface.sql:416-417, 434-435`

### S-TICKET-010

- **routines:** change_status_event_id_out
- **claim:** SELECT INTO site #17 (inventory line 549), reached only when the new status
  is in (2,3,4) AND the OLD status was in (11,12,60,61,101): `SELECT
  from_tz(cast(eventdate as timestamp), 'EUROPE/ZURICH') INTO v_ux_timeout_start FROM
  tt.event WHERE id = event_id` — `event_id` here is the OUT parameter this same routine
  just populated via `tt.event_interface.add_history_event` moments earlier in the SAME
  transaction (line 459-469), so zero rows is structurally near-impossible but, per this
  checklist's own discipline, not assumed safe merely because it is unlikely — `EVENT_PK`
  makes `TOO_MANY_ROWS` impossible regardless. No local handler; propagates to
  S-TICKET-008's total absence of an outer handler.
- **source:** `ddl/src/pkgb/tt_ticket_interface.sql:548-551`

### S-TICKET-011

- **routines:** update_ux_timeout_for_ticket
- **claim:** SELECT INTO site #18 (inventory line 579), unconditional: `SELECT type_id,
  emergency, ux_timeout_start, handled_by_mcc, status_id INTO ... FROM tt.ticket WHERE id
  = p_ticket_id` — `TICKET_PK`, `TOO_MANY_ROWS` impossible, zero rows reachable for a bad
  `p_ticket_id`. **No `EXCEPTION` block anywhere in this 85-line routine** (confirmed
  reading the full body, `ddl/src/pkgb/tt_ticket_interface.sql:563-647`) — propagates
  fully unhandled. For excluded ticket types/statuses, the routine clears the timeout and
  `RETURN`s (lines 588-591, a normal early exit).
- **source:** `ddl/src/pkgb/tt_ticket_interface.sql:563-591`

### S-TICKET-012

- **routines:** update_ux_timeout_for_ticket
- **claim:** SELECT INTO site #19 (inventory line 619), reached only for maintenance
  tickets (type 12): `SELECT COUNT(*) INTO v_ticket_has_service_window FROM
  tt.service_window s WHERE p_ticket_id = s.ticket_id` — `COUNT` aggregate, no `STRICT`
  concern. SELECT INTO site #20 (inventory line 625), reached only when that count is
  `> 0`: `SELECT from_tz(cast(end_date as timestamp), 'EUROPE/ZURICH') INTO
  v_service_window_end FROM tt.service_window WHERE ticket_id = p_ticket_id AND ROWNUM =
  1`. **The trailing `ROWNUM = 1` is the identical translation hazard already documented
  in `migration/spec/tt.event_interface.md`'s S-EVENT-019**: Oracle's `ROWNUM` caps the
  row source at one candidate BEFORE `SELECT INTO` can see more than one, so
  `TOO_MANY_ROWS` is structurally impossible here ONLY because of that predicate — a
  PostgreSQL translation must replace `ROWNUM = 1` with a trailing `LIMIT 1`, not merely
  drop it, or its own `STRICT` could raise `TOO_MANY_ROWS` in a case Oracle never could
  (a ticket can legitimately have more than one `service_window` row). Zero rows is
  structurally near-impossible here (the count just confirmed `> 0` moments earlier in
  the same transaction) but not assumed safe merely for that reason. Neither site has a
  local handler.
- **source:** `ddl/src/pkgb/tt_ticket_interface.sql:618-628`

### S-TICKET-013

- **routines:** change_worker
- **claim:** SELECT INTO site #21 (inventory line 675): `SELECT short, id INTO new_shrt,
  v_worker_id FROM stop.contact WHERE id = p_worker_id` — `CONTACT_PK`, `TOO_MANY_ROWS`
  impossible, zero rows reachable for a bad `p_worker_id`. **Has its own local
  `EXCEPTION WHEN NO_DATA_FOUND`** (lines 679-684) that defaults `new_shrt := 'MCC'`,
  `v_worker_id := NULL` — a synthetic "unassigned / MCC" worker label, not an error path
  from the caller's perspective.
- **source:** `ddl/src/pkgb/tt_ticket_interface.sql:673-684`

### S-TICKET-014

- **routines:** change_worker
- **claim:** SELECT INTO site #22 (inventory line 688): `SELECT c.short,
  t.handled_by_mcc INTO old_shrt, v_handled_by_mcc FROM stop.contact c, tt.ticket t WHERE
  t.id = p_ticket_id AND t.worker_id = c.id` — an INNER join, so zero rows is reachable
  BOTH for a bad `p_ticket_id` AND for a ticket whose current `worker_id` doesn't resolve
  (e.g. an unassigned ticket, `worker_id IS NULL`); `TOO_MANY_ROWS` is structurally
  impossible (`TICKET_PK` pins at most one ticket row, `CONTACT_PK` pins at most one
  contact). **Has its own local `EXCEPTION WHEN NO_DATA_FOUND`** (lines 693-698)
  defaulting to the same synthetic "MCC" label plus `v_handled_by_mcc := 1`. SELECT INTO
  site #23 (inventory line 715), unconditional and AFTER both local-handler blocks have
  closed: `SELECT company_id into cust_id FROM ticket WHERE id = p_ticket_id` —
  `TICKET_PK`, `TOO_MANY_ROWS` impossible, zero rows reachable. **`change_worker` has no
  procedure-level `EXCEPTION` block** (confirmed reading the full 104-line body,
  `ddl/src/pkgb/tt_ticket_interface.sql:653-756`) — site #23's failure propagates fully
  unhandled, unlike sites #21/#22.
- **source:** `ddl/src/pkgb/tt_ticket_interface.sql:686-698, 714-716`

### S-TICKET-015

- **routines:** change_service_host
- **claim:** SELECT INTO site #24 (inventory line 779), unconditional, UN-guarded:
  `SELECT company_id into cust_id FROM tt.ticket WHERE id = p_ticket_id` — `TICKET_PK`,
  `TOO_MANY_ROWS` impossible, zero rows reachable for a bad `p_ticket_id`. **No
  procedure-level `EXCEPTION` block** (confirmed reading the full 94-line body,
  `ddl/src/pkgb/tt_ticket_interface.sql:762-855`) — this specific site's failure
  propagates fully unhandled, in contrast with the four FOLLOWING sites (S-TICKET-016),
  which are each individually guarded.
- **source:** `ddl/src/pkgb/tt_ticket_interface.sql:777-780`

### S-TICKET-016

- **routines:** change_service_host
- **claim:** SELECT INTO sites #25-#28 (inventory lines 784, 799, 813, 825), each in its
  OWN small `BEGIN...EXCEPTION WHEN NO_DATA_FOUND` block: old service name+id (784, join
  on `mss.service_type`/`mss.service`/`tt.ticket`, defaults `v_service_label_old :=
  NULL`), new service name (799, join on `mss.service_type`/`mss.service` by
  `p_service_id`, defaults `NULL`), old host name (813, join on `mss.host`/`tt.ticket`,
  defaults `'<empty>'`), new host name (825, `mss.host` by `p_host_id`, defaults
  `'<empty>'`). All four are effectively single-row lookups (`mss.service.id` and
  `mss.host.id` are each that table's PK; the `tt.ticket` join side is pinned by
  `TICKET_PK`), so `TOO_MANY_ROWS` is structurally impossible at all four; zero rows is
  reachable at each independently (orphaned/absent service or host references), and each
  is caught LOCALLY — none of the four can ever reach an outer handler because this
  routine has none (S-TICKET-015).
- **source:** `ddl/src/pkgb/tt_ticket_interface.sql:782-832`

### S-TICKET-017

- **routines:** change_subject
- **claim:** SELECT INTO site #29 (inventory line 873): `SELECT company_id into cust_id
  FROM ticket WHERE id = p_ticket_id`. SELECT INTO site #30 (inventory line 877):
  `SELECT t.subject INTO sub_old FROM tt.ticket t WHERE t.id = p_ticket_id`. Both are
  `TICKET_PK` lookups, `TOO_MANY_ROWS` impossible at either, zero rows reachable at both
  for a bad `p_ticket_id`. **`change_subject` has no `EXCEPTION` block of its own**
  (confirmed reading the full 37-line body,
  `ddl/src/pkgb/tt_ticket_interface.sql:860-896`) — both sites propagate fully unhandled.
- **source:** `ddl/src/pkgb/tt_ticket_interface.sql:868-878`

### S-TICKET-018

- **routines:** change_customer_reference
- **claim:** No `SELECT INTO` at this routine's own level (it delegates its audit write
  to the private `add_status_change_event`). The `IF (p_customer_reference IS NOT NULL)
  ... ELSE 'changed to <empty>'` pattern (lines 911-915) is Oracle's OWN
  `''`≡`NULL`-aware handling of its input, not a translation hazard to correct — both a
  caller-supplied `''` and a caller-supplied `NULL` take the `ELSE` branch under Oracle's
  native `''`≡`NULL` collapsing, and a PostgreSQL `IS NOT NULL` check on the SAME
  parameter would ALSO take the `ELSE` branch for `NULL` but NOT for `''` (a caller
  passing `''` explicitly would, in PostgreSQL, produce `'customer reference changed to
  '` with a trailing empty string rather than `'customer reference changed to <empty>'`)
  — a genuine, narrow divergence in the AUDIT TEXT ONLY (the `UPDATE ...
  customer_reference = p_customer_reference` itself is unaffected either way, since it
  writes whatever was passed verbatim). `tt.ticket.customer_reference` has no `NOT
  NULL`/check constraint forbidding `''` (`ddl/generated/schema.oracle.sql:203`), so `''`
  is a reachable caller input, not theoretical. Recorded as a real Checklist-dimension-1
  finding (see `## Checklist` §1), not silently assumed harmless because it "only"
  affects an audit string.
- **source:** `ddl/src/pkgb/tt_ticket_interface.sql:901-924`

### S-TICKET-019

- **routines:** change_label
- **claim:** The 2-arg overload (`change_label(p_ticket_id, p_label_id)`) is a single
  `UPDATE tt.ticket SET label_id = p_label_id WHERE id = p_ticket_id` with no `SELECT`
  of any kind and no `EXCEPTION` block — an `UPDATE` matching zero rows (bad
  `p_ticket_id`) is NOT an error in Oracle or PostgreSQL (no implicit row-count check),
  so a nonexistent ticket id silently no-ops rather than raising anything.
- **source:** `ddl/src/pkgb/tt_ticket_interface.sql:930-938`

### S-TICKET-020

- **routines:** change_label
- **claim:** The 3/4-arg overload's SELECT INTO sites #31-#33 (inventory lines 959, 965,
  972): site #31, unconditional, `SELECT company_id, label_id INTO v_company_id,
  v_old_label_id FROM ticket WHERE id=p_ticket_id` (`TICKET_PK`, `TOO_MANY_ROWS`
  impossible, zero rows reachable). Site #32, reached only when `v_old_label_id IS NOT
  NULL`: `SELECT name INTO v_old_label_name FROM label WHERE id=v_old_label_id` (`LABEL`
  PK, same profile). Site #33, reached only when `p_label_id IS NOT NULL` (the `ELSE`
  arm of the audit-text `IF`): `SELECT name INTO v_label_name FROM label WHERE
  id=p_label_id` (same profile). **None of the three has a local handler, and this
  overload has NO procedure-level `EXCEPTION` block either** (confirmed reading the full
  51-line body, `ddl/src/pkgb/tt_ticket_interface.sql:944-994`) — all three propagate
  fully unhandled. This overload CALLS the 2-arg overload (S-TICKET-019) to perform the
  actual `UPDATE`, then inserts its own audit event directly (not via
  `add_status_change_event`). The two overloads differ in argument COUNT (2 vs 3/4) —
  PostgreSQL's native overload resolution dispatches on this exactly as Oracle's does,
  no translation gap.
- **source:** `ddl/src/pkgb/tt_ticket_interface.sql:956-980`

### S-TICKET-021

- **routines:** expire_status
- **claim:** **A genuine doc/body disagreement, documented faithfully.** The package
  spec's doc comment for `expire_status`
  (`ddl/src/pkg/tt_ticket_interface.sql:191-202`) states it "sets private details text
  then calls change_label() and change_status()." **The body
  (`ddl/src/pkgb/tt_ticket_interface.sql:999-1017`) only calls `change_status`** —
  `p_label_id` is accepted as a parameter and never read anywhere in the 20-line body; no
  call to `change_label` exists in this routine at all. Per the plan's own instruction
  that the body is authoritative where doc comment and body disagree, this spec records
  the BODY's behavior (label is accepted but silently ignored) and flags the discrepancy
  here rather than inventing a `change_label` call Oracle does not make. No `SELECT INTO`
  at this routine's own level; no `EXCEPTION` block of its own — its call to
  `change_status` inherits that routine's full strictness profile (S-TICKET-007 onward).
  **Decision (branch `phoenix/migrate_tt_only`, status report 2026-10-13 Q11 (c)):
  behaviour KEPT — this is stale documentation, not a lost feature.** Evidence, all
  static: (1) the ONLY caller in the corpus is `TT.UTIL.check_ticket_status`
  (`ddl/src/pkgb/tt_util.sql:62-64`), whose cursor selects `t.label_id as label_id`
  from the ticket being expired (`ddl/src/pkgb/tt_util.sql:50`) and passes it as
  `p_label_id` — the doc comment itself names the parameter "current label id"
  (`ddl/src/pkg/tt_ticket_interface.sql:201`); a `change_label(p_ticket_id, p_label_id)`
  call (`ddl/src/pkgb/tt_ticket_interface.sql:930-938`, `UPDATE tt.ticket SET label_id =
  p_label_id`) with the ticket's own current label would therefore write the value
  already stored — a no-op; (2) the 4-argument `change_label` overload (lines 944-994),
  which would additionally write a "Ticket label ..." audit event, cannot be meant
  either: `expire_status` has no contact to pass and the generated text for an unchanged
  label ("changed to X (was: X)") would be nonsense; (3) nothing in `ddl/src/` reads
  `tt.ticket.label_id` in connection with status expiry or `status_valid_until_date`
  (`tt_util.sql:50` is the only reader outside `change_label` itself), and
  `masterdata/TT/label.csv` holds four routing labels (Dispatch, Routine, Process, SOC)
  with no "expired"/"hot" label a status expiry could plausibly apply; (4) the revision
  history of the body shows no removed `change_label` call (the routine is unchanged
  since the base import). The locked assertions (`tt__ticket_interface__lifecycle.sql`,
  S-TICKET-021: `label_id` untouched after `expire_status(..., p_label_id => 1)`) remain
  the pinned behaviour. Unlike Q11 (a)/(b)/(d) this item is NOT a `DEVIATION`.
- **source:** `ddl/src/pkg/tt_ticket_interface.sql:191-208`, `ddl/src/pkgb/tt_ticket_interface.sql:999-1017`

### S-TICKET-022

- **routines:** change_partner_reference
- **claim:** Structurally identical to `change_customer_reference`'s finding
  (S-TICKET-018): the `IF (p_partner_reference IS NOT NULL) ... ELSE 'changed to
  <empty>'` pattern (lines 1032-1036) has the same `''`-vs-`NULL` audit-text-only
  divergence, and `tt.ticket.partner_reference` likewise has no `NOT NULL`/check
  constraint forbidding `''`. No `SELECT INTO` at this routine's own level (delegates to
  `add_status_change_event`); no `EXCEPTION` block of its own.
- **source:** `ddl/src/pkgb/tt_ticket_interface.sql:1022-1045`

### S-TICKET-023

- **routines:** change_owner
- **claim:** SELECT INTO sites #34-#36 (inventory lines 1073, 1079, 1086), mutually
  exclusive branches: when Zitadel first/last name are BOTH supplied, NEITHER site runs
  (no DB lookup at all). When `p_owner_id IS NOT NULL` (and Zitadel names are not both
  present): site #34, `SELECT firstname, lastname into first_name, last_name FROM
  stop.contact WHERE id = p_owner_id` (`CONTACT_PK`, `TOO_MANY_ROWS` impossible, zero
  rows reachable for a bad `p_owner_id`), then site #35, `SELECT company_id INTO
  v_company_id FROM stop.contact WHERE id = p_owner_id` (re-query of the SAME row, same
  profile). Otherwise (the `ELSE` branch, `p_owner_id IS NULL`): site #36, `SELECT
  company_id into v_company_id FROM tt.ticket WHERE id = p_ticket_id` (`TICKET_PK`, same
  profile). **`change_owner` has no `EXCEPTION` block of its own** (confirmed reading the
  full 65-line body, `ddl/src/pkgb/tt_ticket_interface.sql:1050-1114`) — whichever branch
  fires, the failure propagates fully unhandled.
- **source:** `ddl/src/pkgb/tt_ticket_interface.sql:1068-1088`

### S-TICKET-024

- **routines:** change_company
- **claim:** SELECT INTO site #37 (inventory line 1135), unconditional: `SELECT
  t.company_id, t.host_id INTO v_old_company_id, v_old_host_id FROM tt.ticket t WHERE
  t.id = p_ticket_id` (`TICKET_PK`, `TOO_MANY_ROWS` impossible, zero rows reachable). Site
  #38 (line 1138), reached only if `v_old_host_id IS NOT NULL`: `SELECT h.name INTO
  v_old_host_name FROM mss.host h WHERE id = v_old_host_id` (`HOST_PK`, same profile;
  ELSE branch sets `'<none>'` — a normal default, not an exception). Site #39 (line
  1144), reached only if `v_old_company_id IS NOT NULL`: `SELECT c.short INTO
  v_old_company_short FROM stop.company c WHERE c.id = v_old_company_id` (`COMPANY` PK,
  same profile; ELSE branch sets `'<empty>'`). Site #40 (line 1157): `SELECT short INTO
  v_companyshort FROM stop.company WHERE id=p_company_id`, in its OWN local `BEGIN...
  EXCEPTION WHEN NO_DATA_FOUND THEN v_companyshort := '<empty>'` block (lines 1155-1163)
  — the only one of the four with a local handler. Sites #37-#39 have no local handler
  and no outer handler exists in this 78-line routine either (confirmed reading the full
  body, `ddl/src/pkgb/tt_ticket_interface.sql:1119-1196`) — they propagate fully
  unhandled.
- **source:** `ddl/src/pkgb/tt_ticket_interface.sql:1135-1163`

### S-TICKET-025

- **routines:** change_emergency
- **claim:** No `SELECT INTO` at this routine's own level — it delegates its audit write
  to `add_status_change_event` (inheriting that private routine's own findings,
  S-TICKET-053), then updates `emergency` and the ratchet `was_emergency :=
  GREATEST(p_emergency, was_emergency)` (a value that, once set to 1, this routine can
  never reset to 0 — by design, per the column name "was ever emergency"). No
  `EXCEPTION` block of its own.
- **source:** `ddl/src/pkgb/tt_ticket_interface.sql:1200-1230`

### S-TICKET-026

- **routines:** change_always_visible
- **claim:** No `SELECT INTO` at this routine's own level; delegates to
  `add_status_change_event`. No `EXCEPTION` block of its own. Structurally the simplest
  routine in the `change_*` family alongside `change_label`'s 2-arg overload.
- **source:** `ddl/src/pkgb/tt_ticket_interface.sql:1232-1254`

### S-TICKET-027

- **routines:** change_notification
- **claim:** **A genuine, narrow Pitfall-2-adjacent NULL-propagation fact, correctly
  handled by the Oracle source as written.** `v_event_details_public`/
  `v_event_details_private` are declared with no default (`NULL` on entry); each is
  assigned `EVENT_DETAILS_PREFIX || p_change_text_public` ONLY if that parameter `IS NOT
  NULL` (lines 1273-1279) — i.e. the variable is left at its declared `NULL` (not
  concatenated at all) if the input is `NULL`, so there is no `NULL || 'x'`
  collapsing-vs-not divergence to translate here (unlike
  `TT.OSAG_NOTIFY.delete_ticket_notifications`'s S-NOTIFY-020 accumulator, which DOES
  concatenate onto a NULL-seeded variable). If a caller passes `''` instead of `NULL` for
  either text parameter, the `IS NOT NULL` check is TRUE in both Oracle and PostgreSQL
  (an empty string is never NULL in either engine, so no `''`≡`NULL` collapsing is
  relevant to THIS specific check) — the prefix is prepended to `''`, producing a
  visible-but-otherwise-empty change line in both engines identically. No `EXCEPTION`
  block of its own; delegates to `add_status_change_event`.
- **source:** `ddl/src/pkgb/tt_ticket_interface.sql:1265-1281`

### S-TICKET-028

- **routines:** change_summary
- **claim:** SELECT INTO site #41 (inventory line 1302), unconditional: `SELECT
  summary_private, summary_public, summary_relevant_events_count into ... FROM ticket
  WHERE id = p_ticket_id` — `TICKET_PK`, `TOO_MANY_ROWS` impossible, zero rows reachable
  for a bad `p_ticket_id`. **No `EXCEPTION` block of its own** (confirmed reading the
  full 49-line body, `ddl/src/pkgb/tt_ticket_interface.sql:1288-1336`) — propagates fully
  unhandled.
- **source:** `ddl/src/pkgb/tt_ticket_interface.sql:1299-1303`

### S-TICKET-029

- **routines:** change_summary
- **claim:** The change-detection conditions for BOTH the private and public summary
  (`(old != new OR old IS NULL OR new IS NULL) AND NOT (old IS NULL AND new IS NULL)`,
  lines 1305-1308 and 1318-1321) are a careful, Oracle-correct `!=`-with-NULLs
  formulation that ALREADY accounts for the fact that `x != y` evaluates to `NULL` (never
  `TRUE`) whenever either side is `NULL` in standard three-valued SQL logic — identical
  in Oracle and PostgreSQL, so no translation divergence exists in this specific
  condition. `NVL(p_summary_private, '<empty>')`/`NVL(p_summary_public, '<empty>')`
  (lines 1311, 1324) ARE Oracle-`NVL`-specific but behave identically to PostgreSQL's
  `orafce` `NVL` or a native `COALESCE` for a NULL input — no divergence, since neither
  summary column is ever compared against `''` specifically anywhere in this routine
  (only against `NULL` and against each other). Resetting
  `summary_relevant_events_count := 0` happens ONLY on the public-summary-changed path
  (line 1325), never on the private-summary-changed path — a deliberate asymmetry, not an
  omission.
- **source:** `ddl/src/pkgb/tt_ticket_interface.sql:1305-1333`

### S-TICKET-030

- **routines:** change_type
- **claim:** SELECT INTO sites #42-#44 (inventory lines 1355, 1358, 1361), unconditional,
  back-to-back: company id (`TICKET_PK`), old type name (join `ticket_type`/`ticket`,
  `TICKETTYPE_PK` pins the type side, `TICKET_PK` pins the ticket side), new type name
  (`TICKETTYPE_PK` on `p_type_id`) — `TOO_MANY_ROWS` structurally impossible at all
  three, zero rows reachable at each independently (bad `p_ticket_id` for #42, a ticket
  whose CURRENT `type_id` doesn't resolve for #43 — structurally near-impossible for a
  live ticket but not schema-forbidden, a bad `p_type_id` for #44). **No `EXCEPTION`
  block of its own** (confirmed reading the full 36-line body,
  `ddl/src/pkgb/tt_ticket_interface.sql:1342-1377`) — all three propagate fully
  unhandled.
- **source:** `ddl/src/pkgb/tt_ticket_interface.sql:1354-1361`

### S-TICKET-031

- **routines:** change_type, change_service_component
- **claim:** **A shared, corpus-relevant sequence-`CurrVal`-after-`INSERT` pattern.**
  SELECT INTO site #45 (inventory line 1372, `change_type`) and site #51 (inventory line
  1428, `change_service_component`) both do `SELECT event_sequence.CurrVal INTO
  p_event_id FROM DUAL` immediately after their own `INSERT INTO event (...) VALUES
  (event_sequence.NextVal, ...)` in the SAME session/transaction — Oracle's `CurrVal`
  returns "the value most recently returned by `NextVal` for this sequence, in THIS
  session," which is guaranteed defined here since `NextVal` was just called moments
  earlier by the SAME session. **This relies on session-local sequence state that has no
  1:1 PostgreSQL equivalent syntax** (`CurrVal` maps to `currval('tt.event_sequence')`,
  which carries an IDENTICAL "must have called `nextval` in this session first"
  precondition — so the translation is mechanically sound here, not a hazard, but IS a
  corpus-wide mechanic worth flagging since bare `nextval()`/`currval()` calls must stay
  paired within the same translated routine, never split across a `CALL` boundary that
  crosses sessions). Neither site has a local handler, but a `CurrVal`-before-`NextVal`
  ordering bug is structurally impossible here since both call sites text-order `INSERT`
  (with `NextVal`) strictly before the `SELECT ... CurrVal`.
- **source:** `ddl/src/pkgb/tt_ticket_interface.sql:1367-1372, 1421-1428`

### S-TICKET-032

- **routines:** change_service_component
- **claim:** SELECT INTO site #46 (inventory line 1397), unconditional: company id
  (`TICKET_PK`, `TOO_MANY_ROWS` impossible, zero rows reachable). SELECT INTO sites #47-
  #48 (inventory lines 1401-1402), both inside ONE local `BEGIN...EXCEPTION WHEN
  NO_DATA_FOUND` block (lines 1400-1406): old service component internal_code and name
  (both joins on `mss.service_component`/`ticket`, `TOO_MANY_ROWS` impossible via
  `SERVICECOMPONENT_PK`, zero rows reachable if the ticket has no
  `service_component_id`), defaulting to `''`/`'<empty>'` on miss. SELECT INTO sites
  #49-#50 (inventory lines 1410-1411), both inside a SEPARATE local
  `BEGIN...EXCEPTION WHEN NO_DATA_FOUND` block (lines 1409-1415): new service component
  internal_code and name by `p_service_component_id`, same default pair. Site #46 has NO
  local handler and this routine has no procedure-level `EXCEPTION` block either
  (confirmed reading the full 51-line body,
  `ddl/src/pkgb/tt_ticket_interface.sql:1382-1432`) — site #46 propagates fully unhandled
  while sites #47-#50 are locally swallowed.
- **source:** `ddl/src/pkgb/tt_ticket_interface.sql:1396-1415`

### S-TICKET-033

- **routines:** get_next_recent_ticket
- **claim:** SELECT INTO site #52 (inventory line 1449): `SELECT MIN(t.id) INTO
  v_ticketid FROM tt.ticket t WHERE ...` — a `MIN` aggregate over a filtered ticket set
  (open, non-deferred, id greater than `p_last_ticket_id`, optional host/type/
  resolve-age filters), always exactly one row (`NULL` if no ticket matches), no
  `STRICT` concern of any kind. **Has its own `EXCEPTION WHEN OTHERS THEN
  plog.err(c_prefix||'unexpected error 99: '||sqlerrm); RETURN NULL`** (lines 1461-1465)
  — the ENTIRE function body is covered, so this `FUNCTION` never raises to its caller;
  any error (including a hypothetical one from the aggregate query itself) is logged and
  converted to a `NULL` return. Called from `TT.EVENT_INTERFACE.newevent_new`'s
  recent-ticket search loop (`migration/spec/tt.event_interface.md` S-EVENT-009) — one of
  the twelve call sites forming the `TT.EVENT_INTERFACE -> TT.TICKET_INTERFACE` depgraph
  edge (see S-TICKET-045, mutual recursion).
- **source:** `ddl/src/pkgb/tt_ticket_interface.sql:1445-1465`

### S-TICKET-034

- **routines:** merge_tickets
- **claim:** SELECT INTO sites #53-#56 (inventory lines 1498, 1504, 1508, 1514): site
  #53, unconditional, `SELECT partner_reference, fast_resolvable, last_public_event_id,
  ux_timeout_start, customer_ticket_rating_id, engineer_ticket_rating_id INTO ... FROM
  ticket WHERE id = p_ticket_id` (SOURCE ticket, `TICKET_PK`, `TOO_MANY_ROWS` impossible,
  zero rows reachable for a bad `p_ticket_id`). Site #54, reached only if
  `v_last_public_event_id IS NOT NULL`: `SELECT eventdate INTO v_last_public_event_date
  FROM tt.event WHERE id = v_last_public_event_id` (`EVENT_PK`, same profile). Site #55,
  unconditional, the mirror query for the TARGET ticket (`p_mticket_id`, two extra
  columns: `recoverable_status_id`, `status_id`). Site #56, reached only if
  `v_mlast_public_event_id IS NOT NULL`, mirrors site #54 for the target. **`merge_tickets`
  has no procedure-level `EXCEPTION` block** (confirmed reading the full 173-line body,
  `ddl/src/pkgb/tt_ticket_interface.sql:1470-1642`) — all four sites propagate fully
  unhandled; a bad `p_ticket_id` or `p_mticket_id` aborts the ENTIRE merge partway
  through, with no `COMMIT`/`ROLLBACK` anywhere in this package to define a transaction
  boundary (Checklist dimension 5) — whatever DML already ran before the failing
  `SELECT INTO` stays pending in the caller's transaction.
- **source:** `ddl/src/pkgb/tt_ticket_interface.sql:1495-1515`

### S-TICKET-035

- **routines:** merge_tickets
- **claim:** **The precise cascade/non-cascade enumeration for the SOURCE ticket
  (`p_ticket_id`) once merged into the TARGET (`p_mticket_id`).** CASCADES (rows moved or
  re-pointed to the target): all `tt.event` rows (`ticket_id` updated to `p_mticket_id`,
  original id preserved in `org_ticket_id` — lines 1530-1536); `event_notification` rows
  NOT already duplicated on the target (moved via `UPDATE ... SET ticket_id =
  p_mticket_id`, lines 1586-1588, AFTER first deleting exact-duplicate notifications
  already present on the target, lines 1573-1583); `change_request` rows (line
  1591-1593); `guma2.suppressed_signature` rows (line 1630-1632); the customer/engineer
  RATING id is merged onto the target via `NVL(GREATEST(source_rating,
  target_rating), source_rating)` — i.e. the MOST RECENT (highest id) rating wins,
  falling back to the source's if the target has none (lines 1519-1526); the source's
  `partner_reference` is adopted by the target ONLY if the target's is NULL (lines
  1596-1598); `fast_resolvable` is forced to 0 on the target if the SOURCE is 0 and the
  target is 1 (lines 1601-1603, i.e. merging in an unresolvable-fast ticket poisons the
  target); the target's `last_public_event_id`/`recoverable_status_id` are updated to the
  source's if the source's event is newer OR the target had none (lines 1607-1615); the
  target's `ux_timeout_start` is updated to the source's if newer (lines 1619-1621).
  DOES NOT CASCADE: the source ticket's own row is NOT deleted — it is marked
  `merged_into_ticket_id = p_mticket_id`, status 110 ("merged"), `close_date`/
  `last_resolved_date = sysdate`, `last_public_event_id = NULL` (lines 1564-1570); a NEW
  duplicate `event` row is inserted (via `INSERT ... SELECT ... FROM event WHERE id =
  v_event_id`, lines 1557-1561) connecting the SOURCE ticket to a COPY of the "merged"
  history event, rather than sharing the same event row across both tickets — the
  routine's own comment states this is deliberate preparation for a future release where
  events are no longer shared between tickets.
- **source:** `ddl/src/pkgb/tt_ticket_interface.sql:1517-1621`

### S-TICKET-036

- **routines:** merge_tickets
- **claim:** **Final state transitions, in exact order.** After all the above, the
  routine calls `ticket_interface.change_status(p_ticket_id, 110, p_contact_id, NULL,
  NULL, NULL, NULL, NULL, NULL, p_zitadel_contact_id)` (line 1567, marking the SOURCE
  ticket "merged" — inheriting `change_status_event_id_out`'s full strictness profile,
  S-TICKET-008 onward, including its own `updateTicketFlow` call), THEN a direct `UPDATE`
  sets `close_date`/`last_resolved_date`/`last_public_event_id=NULL` on the source (line
  1568-1570, i.e. these three columns are set OUTSIDE `change_status`'s own logic, not
  duplicated by it), THEN — as the routine's VERY LAST statement — calls
  `ticket_interface.change_status(p_mticket_id, 3, p_contact_id, NULL, NULL, NULL, NULL,
  NULL, 'ticket '||p_ticket_id||' merged into this ticket', p_zitadel_contact_id)` (line
  1640, forcing the TARGET to "hot" with a hot-reason string embedded in the private
  details via `change_status_event_id_out`'s own `p_hot_reason` handling, lines 427-432 —
  see S-TICKET-008). Both `change_status` calls are ordinary (non-dynamic) cross-routine
  calls within the SAME package, not calls into `TT.EVENT_INTERFACE`.
- **source:** `ddl/src/pkgb/tt_ticket_interface.sql:1566-1570, 1639-1641`

### S-TICKET-037

- **routines:** replace_id_placeholders
- **claim:** Pure string substitution — `REPLACE(p_text, '##ticket_id##', p_ticket_id)`
  then `REPLACE(..., '##event_id##', p_event_id)`, each `SUBSTRB`-truncated to 30000
  bytes. **No `SELECT` of any kind, no call to any other routine, no `EXCEPTION` block**
  — confirmed by reading the full 11-line body in its entirety
  (`ddl/src/pkgb/tt_ticket_interface.sql:1647-1657`). **This closes the FUNCTION/
  PROCEDURE-COMMIT question for this routine: it cannot transitively reach a `COMMIT`
  because it calls nothing at all** — no hazard exists for
  `get_next_recent_ticket`'s sibling `FUNCTION` either way (see S-TICKET-046 for the
  full trace of both `FUNCTION`s). Mirrors `TT.EVENT_INTERFACE.ticket_type_for_event_type`'s
  identical finding (S-EVENT-034 in the sibling spec).
- **source:** `ddl/src/pkgb/tt_ticket_interface.sql:1647-1657`

### S-TICKET-038

- **routines:** trigger_escalation
- **claim:** No `SELECT INTO` at this routine's own level. Writes a public history event
  (`tt.event_interface.add_history_event`, event type 100007) then runs
  `event_interface.exec_event_type_actions(v_event_id)` — a call INTO
  `TT.EVENT_INTERFACE`, one of the reverse-direction cycle edges (see S-TICKET-045).
  **Has its own `EXCEPTION WHEN OTHERS THEN plog.err(c_prefix||'unexpected error: '||
  sqlerrm)`** covering the entire body (lines 1732-1735) — logs and swallows, never
  propagates.
- **source:** `ddl/src/pkgb/tt_ticket_interface.sql:1715-1735`

### S-TICKET-039

- **routines:** rate_ticket
- **claim:** SELECT INTO site #58 (inventory line 1754): `SELECT ticketrating_seq.NextVal
  INTO p_rating_id FROM dual` — sequence pull, no `STRICT` concern (same mechanic as
  S-TICKET-005). **No `EXCEPTION` block of its own** (confirmed reading the full 34-line
  body, `ddl/src/pkgb/tt_ticket_interface.sql:1741-1774`) — any `INSERT`/`UPDATE`
  failure (e.g. an FK violation on `p_rating_event_id`) propagates fully unhandled. Only
  a BAD customer rating (`p_by_engineer = 0 AND p_rating_value < 3`) triggers the
  cascading `change_status(p_ticket_id, 3, ...)` call (hot); engineer ratings never
  trigger a status change regardless of value.
- **source:** `ddl/src/pkgb/tt_ticket_interface.sql:1753-1773`

### S-TICKET-040

- **routines:** add_docs_page
- **claim:** SELECT INTO site #59 (inventory line 1795): `SELECT ticketdocspage_seq.
  NextVal INTO p_ticket_docs_page_id FROM dual` — sequence pull, no `STRICT` concern.
  **Has its own `EXCEPTION WHEN OTHERS THEN plog.err(...)`** covering the entire body
  (lines 1808-1810) — logs and swallows, never propagates (including this sequence
  pull's own hypothetical failure, though a `DUAL` `SELECT` failing is not a realistic
  scenario in practice).
- **source:** `ddl/src/pkgb/tt_ticket_interface.sql:1793-1811`

### S-TICKET-041

- **routines:** remove_docs_page
- **claim:** SELECT INTO site #60 (inventory line 1830): `SELECT page_id, page_version,
  ticket_id INTO ... FROM ticket_docs_page WHERE id = p_ticket_docs_page_id` — that
  table's PK, `TOO_MANY_ROWS` impossible, zero rows reachable for a bad
  `p_ticket_docs_page_id`. **Has a 2-arm handler**: `WHEN NO_DATA_FOUND THEN NULL`
  (silently does nothing further — for a bad id, the `DELETE` and the history-event call
  never execute) and `WHEN OTHERS THEN plog.err(...)` (lines 1841-1846).
- **source:** `ddl/src/pkgb/tt_ticket_interface.sql:1828-1846`

### S-TICKET-042

- **routines:** add_related_ticket
- **claim:** SELECT INTO site #62 (inventory line 1936): `SELECT COUNT(*) INTO v_counter
  FROM tt.ticket t WHERE t.id IN (p_ticket_id, p_related_ticket_id)` — `COUNT`
  aggregate, no `STRICT` concern. `v_counter != 2` (covering BOTH "one or both tickets
  don't exist" AND "the two ids are equal, so the `IN`-list collapses to one distinct
  value") logs an error and `RETURN`s — a normal early exit, not an exception path.
  **Has its own `EXCEPTION WHEN OTHERS THEN plog.err(...); RETURN`** (lines 1951-1955)
  covering the whole body.
- **source:** `ddl/src/pkgb/tt_ticket_interface.sql:1933-1955`

### S-TICKET-043

- **routines:** remove_related_ticket
- **claim:** SELECT INTO site #63 (inventory line 1970): `SELECT COUNT(*) INTO v_counter
  FROM tt.ticket2related_ticket rt WHERE rt.ticket_id = p_ticket_id AND
  rt.related_ticket_id = p_related_ticket_id` — `COUNT` aggregate, no `STRICT` concern.
  Zero matches (`v_counter = 0`) is a normal silent no-op (neither the `DELETE` nor the
  history event runs). **Has its own `EXCEPTION WHEN OTHERS THEN plog.err(...); RETURN`**
  (lines 1984-1989).
- **source:** `ddl/src/pkgb/tt_ticket_interface.sql:1968-1989`

### S-TICKET-044

- **routines:** add_related_file
- **claim:** SELECT INTO site #64 (inventory line 2007): `SELECT f.display_name INTO
  v_file_display_name FROM mc.mc_file f, mc.mc_file_release r, tt.ticket t WHERE t.id =
  p_ticket_id AND f.id = p_related_file_id and r.mc_file_id = f.id AND t.company_id =
  r.company_id` — the routine's OWN inline comment states the `t.company_id =
  r.company_id` join predicate is a DELIBERATE same-company authorization guard, so a
  cross-company file/ticket pairing is EXPECTED to raise `NO_DATA_FOUND` here, not merely
  tolerated. `TOO_MANY_ROWS` is structurally bounded by `mc.mc_file.id`'s PK and
  `mc.mc_file_release`'s per-company uniqueness assumption (not independently re-verified
  against `ddl/generated/schema.oracle.sql` for this plan — see Assumptions). **Has a
  2-arm handler**: `WHEN NO_DATA_FOUND THEN plog.err(c_prefix||'MC File or ticket does
  not exits or they belong to different companies.'); RETURN` (an intentionally
  descriptive message reflecting the dual-purpose of this lookup) and
  `WHEN OTHERS THEN plog.err(...); RETURN` (lines 2019-2027).
- **source:** `ddl/src/pkgb/tt_ticket_interface.sql:2003-2027`

### S-TICKET-045

- **routines:** remove_related_file
- **claim:** SELECT INTO site #65 (inventory line 2046): `SELECT COUNT(*) INTO v_counter
  FROM tt.ticket2mc_file t2f WHERE t2f.ticket_id = p_ticket_id AND t2f.mc_file_id =
  p_related_file_id` — `COUNT` aggregate, no `STRICT` concern. SELECT INTO site #66
  (inventory line 2051), reached only if `v_counter > 0`: `SELECT mcf.display_name INTO
  v_file_display_name FROM mc.mc_file mcf WHERE mcf.id = p_related_file_id` — `mc_file`'s
  PK, `TOO_MANY_ROWS` impossible; zero rows would be structurally surprising here (the
  relation just confirmed to exist implies the file id is real) but in Oracle is NOT
  re-verified against a same-company guard the way `add_related_file` (S-TICKET-044) is.
  Oracle **has only `WHEN OTHERS THEN plog.err(...); RETURN`** (lines 2064-2069) — no
  `NO_DATA_FOUND` arm; a bad `p_related_file_id` (orphaned `ticket2mc_file` row) is
  caught by `WHEN OTHERS`. **Amended (correction, branch `phoenix/migrate_tt_only`):**
  site #66 in the translation is the guarded form described by S-TICKET-060 — it also
  requires a `mc.mc_file_release` of that file to the ticket's company — and the handler
  gains a dedicated `NO_DATA_FOUND` arm mirroring `add_related_file`'s (log the specific
  "does not exist or they belong to different companies" message, `RETURN`). Observable
  consequences for the pre-existing assertions: the orphaned-file case still succeeds
  without raising (now via the `NO_DATA_FOUND` arm instead of `WHEN OTHERS`); a
  same-company relation is still deleted — provided the fixture actually releases the
  file to the ticket's company, which is what "same-company" means. Site #65 (the
  `COUNT`) and the `v_counter = 0` silent no-op are unchanged.
- **source:** `ddl/src/pkgb/tt_ticket_interface.sql:2044-2069`

### S-TICKET-046

- **routines:** get_next_recent_ticket, replace_id_placeholders
- **claim:** **The FUNCTION/PROCEDURE-COMMIT trace this plan's threat register (T-02-28)
  requires.** This package declares exactly TWO `FUNCTION`s
  (`ddl/src/pkg/tt_ticket_interface.sql:394, 423`). `get_next_recent_ticket`'s full body
  (S-TICKET-033) issues one aggregate `SELECT`, no `INSERT`/`UPDATE`/`DELETE`, and calls
  NOTHING else — it cannot transitively reach a `COMMIT`. `replace_id_placeholders`'s
  full body (S-TICKET-037) is pure string manipulation with no database access and no
  calls to anything — it likewise cannot transitively reach a `COMMIT`. **Neither
  `FUNCTION` has a FUNCTION/PROCEDURE-COMMIT hazard.** This matters because
  `migration/spec/tt.util.md`'s `TT.UTIL` (this package's cycle-mate) DOES `COMMIT`
  (S-UTIL, lines 234/244 per that spec) — but neither of THIS package's two `FUNCTION`s
  calls `TT.UTIL` at all (only `change_status_event_id_out`, itself a `PROCEDURE`, calls
  `tt.util.update_status_valid_until`, per S-TICKET-010's neighbor logic at lines
  519-523) — so no cross-package FUNCTION/PROCEDURE-COMMIT collision is currently
  reachable through either of this package's two `FUNCTION`s. `pg_kind` remains
  PROVISIONAL for all 38 routines regardless (Phase 3 XCUT-04), per
  `migration/README.md`'s standing warning — this clause confirms no COMMIT-reachability
  hazard exists WITHIN this package's own two `FUNCTION`s, it does not settle the final
  PostgreSQL FUNCTION-vs-PROCEDURE shape for any of the 38.
- **source:** `ddl/src/pkg/tt_ticket_interface.sql:394, 423`, `ddl/src/pkgb/tt_ticket_interface.sql:1437-1465, 1647-1657`

### S-TICKET-047

- **routines:** classify_request
- **claim:** SELECT INTO site #67 (inventory line 2105): `SELECT COUNT(*) INTO v_counter
  FROM tt.ticket_request_classification WHERE ticket_id = p_ticket_id` — `COUNT`
  aggregate, no `STRICT` concern, used to decide `UPDATE` vs `INSERT` (a hand-rolled
  upsert, not a native `MERGE`). **A classification value outside `{1,2,3}` (including
  `NULL`) silently defaults to `2` ("standard")** (lines 2093-2103) — no error is raised,
  contradicting the package spec's doc comment implying only 1/2/3 are valid inputs
  (`ddl/src/pkg/tt_ticket_interface.sql:547` "1 = very precise, 2 = standard, 3 =
  imprecise" does not mention a default-on-invalid behavior). **Has its own
  `EXCEPTION WHEN OTHERS THEN plog.err(...); RETURN`** (lines 2120-2124) covering the
  whole body.
- **source:** `ddl/src/pkgb/tt_ticket_interface.sql:2090-2124`

### S-TICKET-048

- **routines:** clear_todo_list
- **claim:** Deletes ALL `todo_item` rows for the ticket unconditionally (line 2143,
  regardless of whether any exist — zero matches is a normal silent no-op for a
  `DELETE`). SELECT INTO site #68 (inventory line 2149), reached ONLY if
  `p_add_history_event = 1` (the default): `SELECT t.host_id, t.company_id INTO
  v_host_id, v_company_id FROM tt.ticket t WHERE id = p_ticket_id` — `TICKET_PK`,
  `TOO_MANY_ROWS` impossible, zero rows reachable for a bad `p_ticket_id`. **No
  `EXCEPTION` block of its own** (confirmed reading the full 41-line body,
  `ddl/src/pkgb/tt_ticket_interface.sql:2132-2173`) — propagates fully unhandled. Note
  that if `p_add_history_event = 0`, this `SELECT INTO` never executes at all, so a bad
  `p_ticket_id` in that mode would still succeed in deleting zero todo items and
  resetting the step counters, without ever touching `tt.ticket` — a real, if narrow,
  path-dependent behavior worth naming.
- **source:** `ddl/src/pkgb/tt_ticket_interface.sql:2143-2171`

### S-TICKET-049

- **routines:** add_todo_item
- **claim:** SELECT INTO site #69 (inventory line 2193): `SELECT todoitem_seq.NextVal
  INTO p_todo_item_id FROM dual` — sequence pull, no `STRICT` concern. **No `EXCEPTION`
  block of its own** (confirmed reading the full 37-line body,
  `ddl/src/pkgb/tt_ticket_interface.sql:2181-2217`). Per its own doc comment, this
  routine deliberately does NOT write a history event — callers batch multiple
  `add_todo_item` calls under one shared history event written separately, a
  package-level convention this spec records but does not enforce (nothing in the body
  prevents a caller from omitting the follow-up history event entirely).
- **source:** `ddl/src/pkgb/tt_ticket_interface.sql:2192-2217`

### S-TICKET-050

- **routines:** update_todo_item_status
- **claim:** SELECT INTO site #70 (inventory line 2244): `SELECT tis.name, ti.details,
  ti.is_public, tis.id INTO ... FROM tt.todo_item ti LEFT JOIN tt.todo_item_status tis ON
  (ti.todo_item_status_id = tis.id) WHERE ti.ticket_id = p_ticket_id AND ti.seq_no =
  p_seq_no` — the `LEFT JOIN` means a todo item with an orphaned/NULL
  `todo_item_status_id` would still match (with `tis.*` columns NULL), so zero rows here
  specifically means "no todo item row at all for this `(ticket_id, seq_no)` pair," not
  "the item exists but its status doesn't resolve"; `TOO_MANY_ROWS` is structurally
  impossible if `(ticket_id, seq_no)` is that table's effective key (not independently
  re-verified against `ddl/generated/schema.oracle.sql` for this plan — flagged in
  Assumptions). SELECT INTO site #71 (line 2256), unconditional: ticket host/company
  (`TICKET_PK`). SELECT INTO site #72 (line 2261): NEW status name by
  `p_todo_item_status_id` (`TODO_ITEM_STATUS` PK, `TOO_MANY_ROWS` impossible, zero rows
  reachable for a bad status id). **No `EXCEPTION` block anywhere in this 87-line
  routine** (confirmed reading the full body,
  `ddl/src/pkgb/tt_ticket_interface.sql:2223-2309`) — all three sites propagate fully
  unhandled.
- **source:** `ddl/src/pkgb/tt_ticket_interface.sql:2244-2264`

### S-TICKET-051

- **routines:** updateTicketFlow
- **claim:** SELECT INTO site #76 (inventory line 2381), inside its OWN local
  `BEGIN...EXCEPTION WHEN NO_DATA_FOUND THEN v_flow_id := NULL` block (lines 2380-2386):
  `SELECT tf.id, tf.FLOW_IN_DATE INTO v_flow_id, v_flow_in_date FROM tt.ticket_flow tf
  where ticket_id = p_ticket_id AND flow_out_date IS NULL` — zero rows (no OPEN flow
  entry) is the EXPECTED common case for a ticket not currently in the MCC queue, not an
  error; `TOO_MANY_ROWS` would require two simultaneously-open flow entries for the same
  ticket, which the routine's own subsequent logic (insert-if-none-open,
  close-if-one-open) implies should not happen but is not independently schema-enforced
  (flagged in Assumptions). SELECT INTO site #77 (inventory line 2391), unconditional,
  AFTER that block closes: `SELECT t.handled_by_mcc, t.type_id, t.status_id,
  t.last_status_change_date INTO ... FROM tt.ticket t where t.id = p_ticket_id` —
  `TICKET_PK`, `TOO_MANY_ROWS` impossible, zero rows reachable for a bad `p_ticket_id`.
  **No procedure-level `EXCEPTION` block** (confirmed reading the full 74-line body,
  `ddl/src/pkgb/tt_ticket_interface.sql:2366-2439`) — site #77's failure propagates fully
  unhandled, unlike site #76.
- **source:** `ddl/src/pkgb/tt_ticket_interface.sql:2380-2393`

### S-TICKET-052

- **routines:** deleteTicket
- **claim:** **The precise cascade enumeration, in the exact statement order Oracle
  executes them (31 statements total).** NULLs out foreign-key references FIRST (7
  `UPDATE ... SET x = NULL` statements across `prx.prx_policy_item`, `tt.ticket`'s own
  self-references — `merged_into_ticket_id`, `last_public_event_id`,
  `customer_ticket_rating_id`, `engineer_ticket_rating_id` twice more via a different
  predicate each — `mcaudit.record`, `mc.isp_link_history`, `mss.
  installation_project_item`, `mc.isp_link_maintenance_history`,
  `mc.host_maintenance_history`), THEN deletes dependent rows in an order that respects
  FK dependency (docs pages, ticket_flow, both directions of ticket2related_ticket,
  attachments, ticket_time_statistic, guma2.suppressed_signature, nids.ticket2rule,
  fw.rule2ticket, fw.source_nat_rule2ticket, fw.destination_nat_rule2ticket,
  ticket2mc_file, ticket_rating rows keyed by the ticket's events AND by the ticket's own
  rating-id columns — three separate `DELETE`s for ratings alone, reflecting that a
  rating can be reachable via either path), THEN deletes `tt.event` rows for the ticket,
  THEN deletes maintenance/service-window-dependent rows (`maintenance_window`,
  `cust_maintenance_window`, `host2service_window`,
  `mss.deleted_host2service_window`, `service_window` itself — each keyed via a
  subquery on the ticket's own `service_window` ids), THEN `event_notification`,
  `todo_item`, `ticket_request_classification`, `change_request`, `fw.change`, and
  FINALLY `DELETE FROM TT.TICKET WHERE ID = p_ticket_id` as the LAST statement. **Does
  NOT cascade/clean**: any table not explicitly listed here (this spec does not claim
  the 31-statement list is exhaustive of every table with a logical FK to `tt.ticket` in
  the wider schema — only what THIS routine's body actually touches, verified by reading
  every line of the 42-line body,
  `ddl/src/pkgb/tt_ticket_interface.sql:2441-2482`, in full). **No `SELECT INTO`
  anywhere** (several `DELETE`/`UPDATE` statements use `IN (SELECT ...)` subqueries,
  which carry NO `STRICT` concern — that syntax is not `SELECT INTO`). **No `EXCEPTION`
  block at all** — a constraint violation partway through (e.g. an FK this routine
  doesn't know about, elsewhere in the schema, referencing `tt.ticket`) aborts with
  whatever statements already ran left pending in the caller's transaction, since this
  package never issues `COMMIT`/`ROLLBACK` (Checklist dimension 5).
- **source:** `ddl/src/pkgb/tt_ticket_interface.sql:2441-2482`

### S-TICKET-053

- **routines:** (none directly — private helper only)
- **claim:** **A genuine, previously-undocumented bug in the private
  `add_status_change_event`**, used by `change_customer_reference`,
  `change_partner_reference`, `change_emergency`, `change_always_visible`,
  `change_notification`, and `change_summary`. It declares `cust_id NUMBER;` (line 1670)
  and inserts it verbatim as the new event's `company_id` (line 1688) — but **`cust_id`
  is NEVER ASSIGNED anywhere in this 40-line body** (confirmed reading the full routine,
  `ddl/src/pkgb/tt_ticket_interface.sql:1663-1702`, in full — no `SELECT ... INTO
  cust_id` exists). Every "attribute change" audit event written through THIS private
  routine therefore has `company_id = NULL` in the `tt.event` row, regardless of the
  ticket's actual company — unlike every OTHER `change_*` routine in this package that
  writes its own audit event directly (e.g. `change_worker`, `change_subject`,
  `change_service_host`), which all correctly resolve and set a real `company_id`.
  Originally documented faithfully as a genuine Oracle behavior (a bug, not a feature).
  **Amended (correction, branch `phoenix/migrate_tt_only`):** the translation does NOT
  reproduce the NULL — it assigns `cust_id` from the ticket row before the `INSERT`,
  the way every sibling writer in this package does (see S-TICKET-059 for the corrected
  behaviour, including the one new failure mode this adds). The rest of this clause —
  the public/private hide rule, the `CurrVal` pull, the unconditional notify call, the
  absence of any `EXCEPTION` block — is unchanged. SELECT INTO site #57 (inventory
  line 1697), unconditional: `SELECT event_sequence.CurrVal INTO event_id FROM dual` —
  sequence pull (same `NextVal`-then-`CurrVal` pattern as S-TICKET-031), no `STRICT`
  concern. **No `EXCEPTION` block of its own** — any failure (including the `INSERT`
  itself, or the subsequent `TT.OSAG_NOTIFY.event_notify` call) propagates fully
  unhandled to whichever `change_*` routine called this one, each of which (per their own
  clauses above) has no `EXCEPTION` block of its own either — the failure ultimately
  reaches the ORIGINAL caller of the public `change_*` routine.
- **source:** `ddl/src/pkgb/tt_ticket_interface.sql:1663-1702`

### S-TICKET-054

- **routines:** (none directly — private helper only)
- **claim:** `handleDeferredTransitions`, called only from `change_status_event_id_out`
  when a ticket transitions into or out of "deferred" (status 60). SELECT INTO site #61
  (inventory line 1875), unconditional: `SELECT escalation_status_id INTO
  v_escalation_status FROM ticket WHERE id = p_ticket_id` — `TICKET_PK`, `TOO_MANY_ROWS`
  impossible, zero rows reachable for a bad `p_ticket_id` (structurally near-impossible
  here since its only caller already validated the ticket exists moments earlier, per
  S-TICKET-008, but not assumed safe merely for that reason). **Has its own
  `EXCEPTION WHEN OTHERS THEN plog.err(c_prefix||'unexpected error: '||sqlerrm); RETURN`**
  covering the entire 61-line body (lines 1915-1919) — logs and swallows, never
  propagates back to `change_status_event_id_out`.
- **source:** `ddl/src/pkgb/tt_ticket_interface.sql:1872-1919`

### S-TICKET-055

- **routines:** (none directly — private helper only)
- **claim:** `updateTicketTimeStats`, called only from `change_status_event_id_out` for a
  fixed set of statuses (2, 11, 12, 60, 61, 101). SELECT INTO sites #73-#75 (inventory
  lines 2330, 2335, 2343), all inside ONE local `BEGIN...EXCEPTION` block
  (lines 2328-2344): site #73, `SELECT ts.id INTO v_stats_id FROM
  tt.ticket_time_statistic ts WHERE ts.ticket_id = p_ticket_id` — zero rows is the
  EXPECTED case for a ticket's first-ever time-stat write, caught by
  `WHEN NO_DATA_FOUND`, which then (site #74) pulls a NEW id via `SELECT tt.
  tickettimestatistic_seq.nextval INTO v_stats_id FROM dual` (sequence, no `STRICT`
  concern), performs a `MERGE ... WHEN NOT MATCHED THEN INSERT` explicitly designed to
  avoid a race against a CONCURRENT session creating the same row, THEN (site #75)
  RE-does the SAME `SELECT ts.id INTO v_stats_id ...` query — because, per the routine's
  own inline comment, the `MERGE` "may not have inserted a new record" (a concurrent
  session may have won the race), so the re-`SELECT` picks up whichever row actually
  exists after the `MERGE`, own or the concurrent winner's. `tt.ticket_time_statistic.
  ticket_id` is presumed unique (not independently re-verified against
  `ddl/generated/schema.oracle.sql` for this plan — see Assumptions), which is what makes
  `TOO_MANY_ROWS` structurally impossible at sites #73/#75 either way.
- **source:** `ddl/src/pkgb/tt_ticket_interface.sql:2328-2344`

### S-TICKET-056

- **routines:** newticket_new, change_status_event_id_out, updateTicketFlow
- **claim:** All three of `newticket_new` (line 270), `change_status_event_id_out` (line
  555, passing the OLD status/date as `p_prev_status_id`/`p_prev_status_change_date`),
  and `merge_tickets` (transitively, via its two `change_status` calls, S-TICKET-036)
  eventually call `updateTicketFlow` — this is the corpus-wide "callers that change
  status/type/worker must also update the MCC queue" convention the package spec's doc
  comment for `updateTicketFlow` states explicitly
  (`ddl/src/pkg/tt_ticket_interface.sql:610-613`, "Should be called by state/type/worker
  changes that may influence if a ticket is in the MCC queue or not"). `change_worker`
  (S-TICKET-014, line 754) and `change_type` (S-TICKET-030, line 1375) ALSO call it. This
  spec records the convention as observed in the actual call sites, not as a rule this
  package enforces structurally (nothing prevents a NEW future `change_*` routine from
  omitting the call).
- **source:** `ddl/src/pkgb/tt_ticket_interface.sql:270, 555, 754, 1375`

### S-TICKET-057

- **routines:** newticket_new, change_status_event_id_out, change_deferral_date, add_docs_page, remove_docs_page, add_related_ticket, remove_related_ticket, add_related_file, remove_related_file, classify_request, clear_todo_list, update_todo_item_status, trigger_escalation, merge_tickets, change_summary
- **claim:** **The mutual recursion with `TT.EVENT_INTERFACE`, this package's OUTBOUND
  half (the reverse of `migration/spec/tt.event_interface.md`'s inbound calls TO this
  package, e.g. its S-EVENT-009 dozen call sites into `get_next_recent_ticket`,
  `change_status`, `change_type`).** This package calls `TT.EVENT_INTERFACE` from:
  `newticket_new` (line 237, `add_history_event`; line 250, `exec_event_type_actions`),
  `change_deferral_date` (line 303, `addevent_new`), `change_status_event_id_out` (lines
  459, 475, `add_history_event`; lines 509, 513, `addevent_new`), `add_docs_page`/
  `remove_docs_page`/`add_related_ticket`/`remove_related_ticket`/`add_related_file`/
  `remove_related_file`/`classify_request`/`update_todo_item_status` (each via
  `addevent_new` or `add_history_event`, one call site apiece), `clear_todo_list` (line
  2155, `add_history_event`), `trigger_escalation` (lines 1718, 1731, `add_history_event`
  then `exec_event_type_actions`), `merge_tickets` (line 1542, `addevent_new`). Per
  `migration/analyze/known_cycles.json`'s accepted `TT.EVENT_INTERFACE|TT.OSAG_NOTIFY|
  TT.TICKET_INTERFACE|TT.UTIL` cycle group, **this cycle does not fail Phase 1's
  topological sort — it is an accepted mutual-recursion group that must be translated as
  ONE batch**. PL/pgSQL does not resolve function/procedure bodies at `CREATE` time
  (only at CALL time), so the two packages' PostgreSQL translations CAN be `CREATE`d in
  either order — only EXECUTING a call across the cycle requires both sides to already
  exist. This is the identical conclusion `tt.event_interface.md`'s own cycle note
  reaches from the other direction, recorded here for consistency, not re-derived from
  scratch.
- **source:** `ddl/src/pkgb/tt_ticket_interface.sql:237, 250, 303, 459, 475, 509, 513, 1542, 1718, 1731, 2155`

### S-TICKET-058

- **routines:** newticket_new, change_status_event_id_out, addevent_new-reachable routines
- **claim:** This package also calls `TT.OSAG_NOTIFY.event_notify` directly (`newticket_new`
  line 234; `add_status_change_event` line 1700) and `TT.OSAG_NOTIFY.
  delete_ticket_notifications` (`change_status_event_id_out` line 497, on delete-status
  120), and `TT.UTIL.update_status_valid_until` (`change_status_event_id_out` lines 520,
  522) — the SAME two current call sites into `TT.UTIL` that `migration/spec/
  tt.event_interface.md`'s S-EVENT-029 already documents for `addevent_new`; both current
  callers of `TT.UTIL.update_status_valid_until` (this routine and `addevent_new`) are
  declared `PROCEDURE`, so no FUNCTION/PROCEDURE-COMMIT collision currently exists
  through EITHER path into `TT.UTIL`'s `COMMIT`-bearing code — consistent with
  S-TICKET-046's conclusion that neither of THIS package's own two `FUNCTION`s reaches a
  `COMMIT`.
- **source:** `ddl/src/pkgb/tt_ticket_interface.sql:234, 497, 520, 522, 1700`

### S-TICKET-059

- **routines:** change_customer_reference, change_partner_reference, change_emergency, change_always_visible, change_notification, change_summary
- **claim:** **CORRECTION of the `add_status_change_event` `cust_id` bug (S-TICKET-053;
  branch `phoenix/migrate_tt_only`).** Oracle declares `cust_id NUMBER;`
  (`ddl/src/pkgb/tt_ticket_interface.sql:1670`) and inserts it as `tt.event.company_id`
  (line 1688) without ever assigning it, so every audit event written through this
  private routine — i.e. by each of the six public routines listed above — carries
  `company_id = NULL`. Every OTHER audit-event writer in the same package resolves the
  company from the ticket first: `change_worker` (line 715), `change_service_host` (line
  779), `change_subject` (line 873), each `SELECT company_id INTO cust_id FROM ticket
  WHERE id = p_ticket_id`, and `change_label` (line 955) likewise — the NULL is an
  omission, not a design. The corrected behaviour: before the `INSERT`,
  `add_status_change_event` executes `SELECT company_id INTO cust_id FROM tt.ticket WHERE
  id = p_ticket_id` with the same strictness profile as the sibling sites (`STRICT`,
  unhandled — this private routine has no `EXCEPTION` block and neither do its six
  callers), so (i) the audit event's `company_id` equals the ticket's `company_id` at the
  time of the change, and (ii) a nonexistent `p_ticket_id` now surfaces as
  `NO_DATA_FOUND` from the company lookup (Oracle would have failed the same call on
  the `tt.event -> tt.ticket` foreign key instead — `ORA-02291` — so a nonexistent
  ticket was never a success path; only the error identity changes). Audit text,
  public/private hiding, the sequence pull and the notify call are unchanged.
- **source:** `ddl/src/pkgb/tt_ticket_interface.sql:1663-1702`, `ddl/src/pkgb/tt_ticket_interface.sql:715`, `ddl/src/pkgb/tt_ticket_interface.sql:779`, `ddl/src/pkgb/tt_ticket_interface.sql:873`

### S-TICKET-060

- **routines:** remove_related_file
- **claim:** **CORRECTION — the same-company guard made symmetric (branch
  `phoenix/migrate_tt_only`, Q11 (d)).** `add_related_file` refuses to ATTACH a file to
  a ticket of a different company: its lookup joins `mc.mc_file_release r` with
  `t.company_id = r.company_id` and its own inline comment (`ddl/src/pkgb/
  tt_ticket_interface.sql:2004-2006`, "make sure that ticket and mc file belong to the
  same company otherwise the NO_DATA_FOUND should be triggered") declares that
  predicate an authorization check (S-TICKET-044). `remove_related_file` (lines
  2046-2061) applies no such check, so any caller able to name a `(ticket, file)` pair
  could DETACH a relation belonging to another company — the authorization intent of the
  attach side is defeated by the detach side. The corrected behaviour: inside the
  `v_counter > 0` branch, the display-name lookup succeeds only if `mc.mc_file` row
  `p_related_file_id` exists AND a `mc.mc_file_release` row for that file exists whose
  `company_id` equals the ticket's `company_id` (expressed as an `EXISTS` sub-select
  rather than `add_related_file`'s plain join, so a file released more than once to the
  same company cannot produce `TOO_MANY_ROWS` here — `mc.mc_file_release` has no unique
  key on `(mc_file_id, company_id)`); on zero rows the routine logs
  `c_prefix || 'MC File or ticket does not exist or they belong to different companies.'`
  via `plog.err` and returns WITHOUT deleting the relation and WITHOUT writing the
  100019 history event. A same-company relation is deleted and its history event written
  exactly as before. Nothing is raised to the caller in either case (the swallow-all
  shape of the original handler is preserved).
- **source:** `ddl/src/pkgb/tt_ticket_interface.sql:2003-2006`, `ddl/src/pkgb/tt_ticket_interface.sql:2046-2069`

### S-TICKET-061

- **routines:** newticket_new
- **claim:** **2026-10-20 export — sign-off senders resolved by Zitadel user ID.** Before
  resolving company and owner, `v_sign_off_sender := 1` iff `p_event_type_id = 30002` AND
  `p_zitadel_contact_id` is one of the eight ServiceNow/partner sign-off Zitadel user IDs
  `260976466693466175, 260976421227212858, 260976444195221562, 249698997185305231,
  250130937734526554, 250130921494181466, 296895704029212305, 389858629131441574` (the
  `NUMBER` parameter is compared against string literals, i.e. implicitly converted; the
  translation compares `p_zitadel_contact_id::text`). `v_sender_contact_id := p_contact_id`;
  if that is NULL and `v_sign_off_sender = 1`, `v_sender_contact_id := (SELECT MAX(l.contact_id)
  FROM auth.login l WHERE l.oidc_zitadel_id = TO_CHAR(p_zitadel_contact_id))` — SELECT INTO
  site #78, an aggregate: never `NO_DATA_FOUND` or `TOO_MANY_ROWS`, NULL when no login
  carries that ID. From then on `v_sender_contact_id` replaces `p_contact_id` everywhere the
  old body read it: the company lookup (site #3, `stop.contact` by id — a mapped contact
  always exists because `auth.login.contact_id` references `stop.contact`), the
  company-wide-admin owner check (`p_host_id IS NULL AND v_sender_contact_id IS NOT NULL`),
  the ticket's `contact_id`, and the event-contact fallback (`p_worker_id`, else
  `v_sender_contact_id`, else NULL). An explicitly passed `p_contact_id` always wins over the
  Zitadel mapping. Any other `(p_event_type_id, p_zitadel_contact_id)` combination leaves the
  behaviour exactly as before the export.
- **source:** `ddl/src/pkgb/tt_ticket_interface.sql:97-146`, `ddl/src/pkgb/tt_ticket_interface.sql:227-233`

### S-TICKET-062

- **routines:** newticket_new
- **claim:** **2026-10-20 export — change-request rule widened.** The pre-approved
  change request (state 3, requester = approver = the resolved event contact, ticket type
  forced to 2) is created iff `p_event_type_id = 30002` AND (`v_sender_contact_id IN
  (224019, 1150408, 235692, 371508, 458818, 430183, 430181, 3598, 796216)` OR
  `v_sign_off_sender = 1`). The former `p_contact_id IS NOT NULL AND` guard is gone (an
  `IN` on NULL is simply false). Consequence: a sign-off Zitadel sender with no `auth.login`
  row still gets the change request — with `requester_id`/`approver_id` NULL (both nullable
  in `TT.CHANGE_REQUEST`) and a NULL ticket contact — and the legacy id list is matched
  against the *resolved* sender, so a Zitadel-mapped contact that is also a legacy id
  matches either way. `requester_zitadel_id`/`approver_zitadel_id` are still
  `p_zitadel_contact_id` (S-TICKET-005 unchanged).
- **source:** `ddl/src/pkgb/tt_ticket_interface.sql:180-200`

### S-TICKET-063

- **routines:** newticket_new, change_worker
- **claim:** **2026-10-20 export — `tt.ticket.worker_zitadel_id`.** Both routines write
  `worker_zitadel_id = (SELECT oidc_zitadel_id FROM auth.login WHERE contact_id = <worker>)`
  as a scalar subquery: `newticket_new` in its `INSERT INTO ticket` with `p_worker_id`,
  `change_worker` in the same `UPDATE` that sets `worker_id = v_worker_id` (so an
  unresolvable new worker — the local `NO_DATA_FOUND` default `v_worker_id := NULL`,
  S-TICKET-013 — clears both columns). NULL when the worker has no login row, no Zitadel
  ID, or is NULL itself. A contact owning more than one `auth.login` row raises
  `ORA-01427` (PostgreSQL `21000`, "more than one row returned by a subquery used as an
  expression") and propagates unhandled — neither routine has a procedure-level handler.
  The column is new in the 2026-10-20 export (`VARCHAR2(128 BYTE)`); on PostgreSQL it is
  added by `migration/test/schema-fixes/27_oct2026_export_fixes.sql`.
- **source:** `ddl/src/pkgb/tt_ticket_interface.sql:204-221`, `ddl/src/pkgb/tt_ticket_interface.sql:731-736`

### S-TICKET-064

- **routines:** change_status_event_id_out, change_status
- **claim:** **NULL-tolerant concatenation of the caller's texts into the status-change
  event (added 2026-10-21 from a live differential run; Pitfall 2, Checklist dimension 1
  missed it).** The status-change event's public text is built as `dets_pub := 'New
  status: ' || status_name || CHR(10) || 'Previous status: ' || v_cur_status_name;
  dets_pub := dets_pub || CHR(10) || p_details_public;` (lines 450-451) and, for a hot
  reason, the private text as `v_details_private := 'Hot because: ' || p_hot_reason ||
  CHR(10) || p_details_private` (line 457). `p_details_public` and `p_details_private`
  are frequently NULL: `TT.EVENT_INTERFACE.newevent_new` (line 326) and `addevent_new`
  (line 707) call `change_status(<ticket>, 3, <contact>, NULL, 'new event added', ...)`
  with a NULL public text. Oracle's `||` treats NULL as `''`, so the event's
  `details_public` is `'New status: hot' || CHR(10) || 'Previous status: open' || CHR(10)`
  (trailing line break, observed live for both routines on 2026-10-21) and the private
  text ends after the line break. PostgreSQL's `||` yields NULL for the whole expression,
  so a literal port writes `details_public = NULL` for every status change triggered by
  an incoming event — the "New status / Previous status" audit line disappears from the
  ticket history. The translation must concatenate with Oracle semantics at both sites
  (`concat()` or `COALESCE(p_x, '')`); the `IF (p_escalate_after_defer)` suffix (line 454)
  then appends to a non-NULL string as in Oracle.
- **source:** `ddl/src/pkgb/tt_ticket_interface.sql:450-461`, `ddl/src/pkgb/tt_event_interface.sql:326, 707`

## Checklist

### 1. Empty-string / NULL handling

**Three distinct findings from tracing every `VARCHAR2`/`CLOB` identifier through every
`IS NULL`/`IS NOT NULL`/`=`/`!=`/`||` site across the full 2,484-line body:**

1. **`change_customer_reference` and `change_partner_reference` (S-TICKET-018,
   S-TICKET-022) — a genuine, narrow AUDIT-TEXT-ONLY divergence.** Both routines'
   `IF (p_x IS NOT NULL) THEN '...' || p_x ELSE '...<empty>...'` pattern takes Oracle's
   `ELSE` branch for BOTH a caller-supplied `NULL` and a caller-supplied `''` (Oracle's
   universal `''`≡`NULL` collapsing for this comparison), producing `'... changed to
   <empty>'`. A literal PostgreSQL port of the SAME `IS NOT NULL` check would ALSO take
   the `ELSE` branch for `NULL` (no collapsing needed for that case) but would take the
   `THEN` branch for `''` (a real, distinct value in PostgreSQL), producing `'...
   changed to '` with a trailing empty string instead of `'... changed to <empty>'`.
   Both `tt.ticket.customer_reference` and `tt.ticket.partner_reference` permit `''` at
   the column level (no `NOT NULL`/check constraint forbidding it,
   `ddl/generated/schema.oracle.sql:203`), so this is reachable, not theoretical — though
   it affects ONLY the generated audit-event text, never the `UPDATE` that writes the
   actual column (which stores whatever was passed, verbatim, in both engines). Boundary
   normalization decision: `NULLIF(p_x, '')` before the `IS NOT NULL` check (or an
   explicit `p_x IS NOT NULL AND p_x != ''` test) closes the gap.
2. **`change_notification`'s prefix-only-if-non-NULL pattern (S-TICKET-027) — CORRECTLY
   handled already, no divergence.** `v_event_details_public`/`_private` are assigned
   `EVENT_DETAILS_PREFIX || p_change_text_x` ONLY inside an `IF p_change_text_x IS NOT
   NULL` guard — the variable is left at its declared NULL (never concatenated) when the
   input is NULL, so there is no `NULL || 'x'`-collapsing-vs-not divergence to translate
   (unlike `TT.OSAG_NOTIFY.delete_ticket_notifications`'s S-NOTIFY-020 accumulator
   pattern, which DOES concatenate onto a NULL-seeded variable across multiple `||`
   calls). A caller-supplied `''` is never NULL in either engine, so the `IS NOT NULL`
   check behaves identically for that input too.
3. **`add_status_change_event`'s "hide the event" NULL check (its own inline comment,
   `ddl/src/pkgb/tt_ticket_interface.sql:1676-1678`) is EXPLICITLY flagged by Oracle's own
   author as fragile**: `IF (p_public_change_text IS NULL AND p_private_change_text IS
   NOT NULL) THEN v_public_event := 0` — the comment reads "if you ever decide to make
   this procedure public this has to be checked more carefully (whitespace-only
   strings...)". Since this routine stays PRIVATE in the translation (per this spec's
   naming convention), the check's known fragility (it does not treat `''` or
   whitespace-only public text as "hidden") is inherited as-is from all 6 current
   callers, none of which currently passes `''` for `p_public_change_text` (each passes
   either a real string or `NULL`) — recorded as a live caveat for Phase 4 if a future
   caller ever changes that.

Every other `IS NULL`/`IS NOT NULL`/`||` site in the package body (the `change_*` family's
audit-string builders, `merge_tickets`' partner-reference/rating/event merge logic,
`change_summary`'s `NVL(..., '<empty>')` calls) was reviewed and found to be either (a) a
numeric/id comparison with no `''`-collapsing relevance (`v_company_id IS NULL`,
`v_old_label_id IS NULL`, etc.), or (b) a `VARCHAR2` comparison against a value never
assigned `''` anywhere in this package's own code (e.g. `change_service_host`'s
`'<empty>'`/`NULL` defaults are Oracle string LITERALS chosen by this package, not
caller input subject to collapsing), or (c) `change_summary`'s `!=`-with-NULLs pattern
(S-TICKET-029), which is standard three-valued SQL logic identical in both engines.

### 2. SELECT INTO strictness

**All 77 sites from the Phase 1 inventory's `select_into_sites` array for
`TT.TICKET_INTERFACE` are enumerated in the dedicated table below, one row each, none
omitted.** Verdict legend (same as `migration/spec/tt.osag_notify.md` and
`migration/spec/tt.event_interface.md`, reused for consistency, not reinvented):
`STRICT + handler` = Oracle had a handler at or immediately above this site and it must
be reproduced; `STRICT, unhandled` = Oracle had no handler anywhere reachable before this
specific call chain's boundary and the raise propagates, matching Oracle's actual
contract (13 `NO_DATA_FOUND` handlers against 77 sites means the large majority of sites
in this package are `STRICT, unhandled` — that is Oracle's real, if occasionally
latent-bug-looking, contract, not something this spec "improves"); `no STRICT` = zero
rows is structurally impossible (an aggregate query: `COUNT`, `MIN`, `MAX`, or a
`sequence.NEXTVAL`/`CURRVAL` pull via `DUAL`).

### SELECT INTO strictness

| # | ddl/src/pkgb/tt_ticket_interface.sql:LINE | target(s) | zero rows possible? | multi rows possible? | Oracle handler | PG translation | clause |
|---|---|---|---|---|---|---|---|
| 1 | `ddl/src/pkgb/tt_ticket_interface.sql:86` | `v_company_id` (`mss.host` by id) | yes (bad `p_host_id`) | no (`HOST_PK`) | none; `newticket_new` has no `EXCEPTION` block at all | STRICT, unhandled | S-TICKET-001 |
| 2 | `ddl/src/pkgb/tt_ticket_interface.sql:89` | `v_mss_service_id` (`mss.host2service` by host id) | yes | **yes** (`mss.host2service` PK is `(host_id, service_id)`, not unique on `host_id`) | none | STRICT, unhandled | S-TICKET-001 |
| 3 | `ddl/src/pkgb/tt_ticket_interface.sql:98` | `v_company_id` (`stop.contact` by id) | yes (bad `p_contact_id`) | no (`CONTACT_PK`) | none | STRICT, unhandled | S-TICKET-002 |
| 4 | `ddl/src/pkgb/tt_ticket_interface.sql:108` | `v_count` (admin-permission `COUNT(*)`) | no (aggregate) | no (aggregate) | n/a | no STRICT | S-TICKET-003 |
| 5 | `ddl/src/pkgb/tt_ticket_interface.sql:125` | `v_event_source_id` (`tt.event_type` by id) | yes (bad `p_event_type_id`) | no (`EVENTTYPE_PK`) | none | STRICT, unhandled | S-TICKET-003 |
| 6 | `ddl/src/pkgb/tt_ticket_interface.sql:133` | `v_contact_company_id` (`stop.contact` by id) | yes (bad `p_worker_id`) | no (`CONTACT_PK`) | none | STRICT, unhandled | S-TICKET-004 |
| 7 | `ddl/src/pkgb/tt_ticket_interface.sql:141` | `p_ticket_id` (`ticket_sequence.NEXTVAL`) | no (sequence) | no (sequence) | n/a | no STRICT | S-TICKET-005 |
| 8 | `ddl/src/pkgb/tt_ticket_interface.sql:142` | `p_event_id` (`event_sequence.NEXTVAL`) | no (sequence) | no (sequence) | n/a | no STRICT | S-TICKET-005 |
| 9 | `ddl/src/pkgb/tt_ticket_interface.sql:254` | `v_cr_id` (`changerequest_seq.NEXTVAL`, only if `v_create_cr=1`) | no (sequence) | no (sequence) | n/a | no STRICT | S-TICKET-005 |
| 10 | `ddl/src/pkgb/tt_ticket_interface.sql:289` | `v_ticket_status_id` (`tt.ticket` by id) | yes (bad `p_ticket_id`) | no (`TICKET_PK`) | none; `change_deferral_date` has no `EXCEPTION` block | STRICT, unhandled | S-TICKET-006 |
| 11 | `ddl/src/pkgb/tt_ticket_interface.sql:295` | `v_host_id` (`tt.ticket` by id, only if status=60) | yes | no (`TICKET_PK`) | none | STRICT, unhandled | S-TICKET-006 |
| 12 | `ddl/src/pkgb/tt_ticket_interface.sql:381` | `v_cur_status` etc. (8-col `tt.ticket` by id) | yes (bad `p_ticket_id`) | no (`TICKET_PK`) | none; `change_status_event_id_out` has no `EXCEPTION` block | STRICT, unhandled | S-TICKET-008 |
| 13 | `ddl/src/pkgb/tt_ticket_interface.sql:389` | `v_last_public_event_type_id` (`tt.event` by id, only if not null) | yes | no (`EVENT_PK`) | none | STRICT, unhandled | S-TICKET-008 |
| 14 | `ddl/src/pkgb/tt_ticket_interface.sql:416` | `status_name` (`status` by id) | yes (bad `p_status_id`) | no (`STATUS_PK`) | none | STRICT, unhandled | S-TICKET-009 |
| 15 | `ddl/src/pkgb/tt_ticket_interface.sql:417` | `v_cur_status_name` (`status` by id) | yes | no (`STATUS_PK`) | none | STRICT, unhandled | S-TICKET-009 |
| 16 | `ddl/src/pkgb/tt_ticket_interface.sql:435` | `l_ticket_type_id` (`tt.ticket` by id — dead variable) | yes | no (`TICKET_PK`) | none | STRICT, unhandled | S-TICKET-009 |
| 17 | `ddl/src/pkgb/tt_ticket_interface.sql:549` | `v_ux_timeout_start` (`tt.event` by `event_id`, conditional) | structurally near-impossible (own just-inserted event) | no (`EVENT_PK`) | none | STRICT, unhandled | S-TICKET-010 |
| 18 | `ddl/src/pkgb/tt_ticket_interface.sql:579` | `v_type_id` etc. (`tt.ticket` by id) | yes (bad `p_ticket_id`) | no (`TICKET_PK`) | none; `update_ux_timeout_for_ticket` has no `EXCEPTION` block | STRICT, unhandled | S-TICKET-011 |
| 19 | `ddl/src/pkgb/tt_ticket_interface.sql:619` | `v_ticket_has_service_window` (`tt.service_window` `COUNT(*)`) | no (aggregate) | no (aggregate) | n/a | no STRICT | S-TICKET-012 |
| 20 | `ddl/src/pkgb/tt_ticket_interface.sql:625` | `v_service_window_end` (`tt.service_window`, `ROWNUM=1`) | structurally near-impossible (count just confirmed >0) | no (capped by `ROWNUM=1` — must become `LIMIT 1`, not merely dropped) | none | STRICT, unhandled (translate `ROWNUM=1` as `LIMIT 1`) | S-TICKET-012 |
| 21 | `ddl/src/pkgb/tt_ticket_interface.sql:675` | `new_shrt, v_worker_id` (`stop.contact` by id) | yes (bad `p_worker_id`) | no (`CONTACT_PK`) | local `WHEN NO_DATA_FOUND` (lines 679-684), defaults to synthetic "MCC" | STRICT + handler | S-TICKET-013 |
| 22 | `ddl/src/pkgb/tt_ticket_interface.sql:688` | `old_shrt, v_handled_by_mcc` (join `stop.contact`/`tt.ticket`) | yes (unassigned worker or bad ticket) | no (both PK-keyed) | local `WHEN NO_DATA_FOUND` (lines 693-698) | STRICT + handler | S-TICKET-014 |
| 23 | `ddl/src/pkgb/tt_ticket_interface.sql:715` | `cust_id` (`ticket` by id) | yes (bad `p_ticket_id`) | no (`TICKET_PK`) | none; `change_worker` has no procedure-level `EXCEPTION` block | STRICT, unhandled | S-TICKET-014 |
| 24 | `ddl/src/pkgb/tt_ticket_interface.sql:779` | `cust_id` (`tt.ticket` by id) | yes (bad `p_ticket_id`) | no (`TICKET_PK`) | none; `change_service_host` has no procedure-level `EXCEPTION` block | STRICT, unhandled | S-TICKET-015 |
| 25 | `ddl/src/pkgb/tt_ticket_interface.sql:784` | `v_service_id_old, v_service_label_old` (join `mss.service_type`/`mss.service`/`tt.ticket`) | yes | no (PK-keyed joins) | local `WHEN NO_DATA_FOUND` (lines 792-795) | STRICT + handler | S-TICKET-016 |
| 26 | `ddl/src/pkgb/tt_ticket_interface.sql:799` | `v_service_label_new` (join `mss.service_type`/`mss.service` by `p_service_id`) | yes | no (PK-keyed) | local `WHEN NO_DATA_FOUND` (lines 806-809) | STRICT + handler | S-TICKET-016 |
| 27 | `ddl/src/pkgb/tt_ticket_interface.sql:813` | `v_host_label_old` (join `mss.host`/`tt.ticket`) | yes | no (PK-keyed) | local `WHEN NO_DATA_FOUND` (lines 818-821) | STRICT + handler | S-TICKET-016 |
| 28 | `ddl/src/pkgb/tt_ticket_interface.sql:825` | `v_host_label_new` (`mss.host` by `p_host_id`) | yes | no (`HOST_PK`) | local `WHEN NO_DATA_FOUND` (lines 829-832) | STRICT + handler | S-TICKET-016 |
| 29 | `ddl/src/pkgb/tt_ticket_interface.sql:873` | `cust_id` (`ticket` by id) | yes (bad `p_ticket_id`) | no (`TICKET_PK`) | none; `change_subject` has no `EXCEPTION` block | STRICT, unhandled | S-TICKET-017 |
| 30 | `ddl/src/pkgb/tt_ticket_interface.sql:877` | `sub_old` (`tt.ticket` by id) | yes | no (`TICKET_PK`) | none | STRICT, unhandled | S-TICKET-017 |
| 31 | `ddl/src/pkgb/tt_ticket_interface.sql:959` | `v_company_id, v_old_label_id` (`ticket` by id, `change_label` 3/4-arg overload) | yes (bad `p_ticket_id`) | no (`TICKET_PK`) | none; this overload has no `EXCEPTION` block | STRICT, unhandled | S-TICKET-020 |
| 32 | `ddl/src/pkgb/tt_ticket_interface.sql:965` | `v_old_label_name` (`label` by id, conditional) | yes (orphaned `v_old_label_id`) | no (`LABEL` PK) | none | STRICT, unhandled | S-TICKET-020 |
| 33 | `ddl/src/pkgb/tt_ticket_interface.sql:972` | `v_label_name` (`label` by `p_label_id`, conditional) | yes (bad `p_label_id`) | no (`LABEL` PK) | none | STRICT, unhandled | S-TICKET-020 |
| 34 | `ddl/src/pkgb/tt_ticket_interface.sql:1073` | `first_name, last_name` (`stop.contact` by `p_owner_id`) | yes (bad `p_owner_id`) | no (`CONTACT_PK`) | none; `change_owner` has no `EXCEPTION` block | STRICT, unhandled | S-TICKET-023 |
| 35 | `ddl/src/pkgb/tt_ticket_interface.sql:1079` | `v_company_id` (`stop.contact` by `p_owner_id`, re-query) | yes | no (`CONTACT_PK`) | none | STRICT, unhandled | S-TICKET-023 |
| 36 | `ddl/src/pkgb/tt_ticket_interface.sql:1086` | `v_company_id` (`tt.ticket` by id, ELSE branch) | yes (bad `p_ticket_id`) | no (`TICKET_PK`) | none | STRICT, unhandled | S-TICKET-023 |
| 37 | `ddl/src/pkgb/tt_ticket_interface.sql:1135` | `v_old_company_id, v_old_host_id` (`tt.ticket` by id) | yes (bad `p_ticket_id`) | no (`TICKET_PK`) | none; `change_company` has no `EXCEPTION` block | STRICT, unhandled | S-TICKET-024 |
| 38 | `ddl/src/pkgb/tt_ticket_interface.sql:1138` | `v_old_host_name` (`mss.host` by id, conditional) | yes | no (`HOST_PK`) | none | STRICT, unhandled | S-TICKET-024 |
| 39 | `ddl/src/pkgb/tt_ticket_interface.sql:1144` | `v_old_company_short` (`stop.company` by id, conditional) | yes | no (`COMPANY` PK) | none | STRICT, unhandled | S-TICKET-024 |
| 40 | `ddl/src/pkgb/tt_ticket_interface.sql:1157` | `v_companyshort` (`stop.company` by `p_company_id`) | yes (bad `p_company_id`) | no (`COMPANY` PK) | local `WHEN NO_DATA_FOUND THEN v_companyshort := '<empty>'` (lines 1160-1163) | STRICT + handler | S-TICKET-024 |
| 41 | `ddl/src/pkgb/tt_ticket_interface.sql:1302` | `old_summary_private` etc. (`ticket` by id) | yes (bad `p_ticket_id`) | no (`TICKET_PK`) | none; `change_summary` has no `EXCEPTION` block | STRICT, unhandled | S-TICKET-028 |
| 42 | `ddl/src/pkgb/tt_ticket_interface.sql:1355` | `v_company_id` (`ticket` by id) | yes (bad `p_ticket_id`) | no (`TICKET_PK`) | none; `change_type` has no `EXCEPTION` block | STRICT, unhandled | S-TICKET-030 |
| 43 | `ddl/src/pkgb/tt_ticket_interface.sql:1358` | `v_old_type_name` (join `ticket_type`/`ticket`) | yes (structurally near-impossible for a live ticket) | no (PK-keyed) | none | STRICT, unhandled | S-TICKET-030 |
| 44 | `ddl/src/pkgb/tt_ticket_interface.sql:1361` | `v_type_name` (`ticket_type` by `p_type_id`) | yes (bad `p_type_id`) | no (`TICKETTYPE_PK`) | none | STRICT, unhandled | S-TICKET-030 |
| 45 | `ddl/src/pkgb/tt_ticket_interface.sql:1372` | `p_event_id` (`event_sequence.CurrVal`) | no (session-local sequence state) | no | n/a | no STRICT (needs `currval()` paired with preceding `nextval()` in same routine) | S-TICKET-031 |
| 46 | `ddl/src/pkgb/tt_ticket_interface.sql:1397` | `v_company_id` (`ticket` by id) | yes (bad `p_ticket_id`) | no (`TICKET_PK`) | none; site has no local handler and routine has no procedure-level `EXCEPTION` block | STRICT, unhandled | S-TICKET-032 |
| 47 | `ddl/src/pkgb/tt_ticket_interface.sql:1401` | `v_old_service_component_code` (join `mss.service_component`/`ticket`) | yes (no service component set) | no (`SERVICECOMPONENT_PK`) | local `WHEN NO_DATA_FOUND` (lines 1403-1406, covers both 1401 and 1402) | STRICT + handler | S-TICKET-032 |
| 48 | `ddl/src/pkgb/tt_ticket_interface.sql:1402` | `v_old_service_component_name` (same join) | yes | no | same local handler as #47 | STRICT + handler | S-TICKET-032 |
| 49 | `ddl/src/pkgb/tt_ticket_interface.sql:1410` | `v_service_component_code` (`mss.service_component` by `p_service_component_id`) | yes (bad id) | no (`SERVICECOMPONENT_PK`) | local `WHEN NO_DATA_FOUND` (lines 1412-1415, covers both 1410 and 1411) | STRICT + handler | S-TICKET-032 |
| 50 | `ddl/src/pkgb/tt_ticket_interface.sql:1411` | `v_service_component_name` (same lookup) | yes | no | same local handler as #49 | STRICT + handler | S-TICKET-032 |
| 51 | `ddl/src/pkgb/tt_ticket_interface.sql:1428` | `p_event_id` (`event_sequence.CurrVal`) | no (session-local sequence state) | no | n/a | no STRICT | S-TICKET-031 |
| 52 | `ddl/src/pkgb/tt_ticket_interface.sql:1449` | `v_ticketid` (`tt.ticket` filtered `MIN(id)`) | no (aggregate, NULL on no match) | no (aggregate) | whole-function `WHEN OTHERS THEN ...RETURN NULL` (lines 1461-1465) | no STRICT (function-level catch-all regardless) | S-TICKET-033 |
| 53 | `ddl/src/pkgb/tt_ticket_interface.sql:1498` | `v_partner_ref` etc. (source `ticket` by id) | yes (bad `p_ticket_id`) | no (`TICKET_PK`) | none; `merge_tickets` has no `EXCEPTION` block | STRICT, unhandled | S-TICKET-034 |
| 54 | `ddl/src/pkgb/tt_ticket_interface.sql:1504` | `v_last_public_event_date` (`tt.event`, conditional) | yes (orphaned event id) | no (`EVENT_PK`) | none | STRICT, unhandled | S-TICKET-034 |
| 55 | `ddl/src/pkgb/tt_ticket_interface.sql:1508` | `v_mpartner_ref` etc. (target `ticket` by `p_mticket_id`) | yes (bad `p_mticket_id`) | no (`TICKET_PK`) | none | STRICT, unhandled | S-TICKET-034 |
| 56 | `ddl/src/pkgb/tt_ticket_interface.sql:1514` | `v_mlast_public_event_date` (`tt.event`, conditional) | yes | no (`EVENT_PK`) | none | STRICT, unhandled | S-TICKET-034 |
| 57 | `ddl/src/pkgb/tt_ticket_interface.sql:1697` | `event_id` (`add_status_change_event`, `event_sequence.CurrVal`) | no (session-local sequence state) | no | n/a | no STRICT | S-TICKET-053 |
| 58 | `ddl/src/pkgb/tt_ticket_interface.sql:1754` | `p_rating_id` (`ticketrating_seq.NextVal`) | no (sequence) | no (sequence) | n/a | no STRICT | S-TICKET-039 |
| 59 | `ddl/src/pkgb/tt_ticket_interface.sql:1795` | `p_ticket_docs_page_id` (`ticketdocspage_seq.NextVal`) | no (sequence) | no (sequence) | whole-routine `WHEN OTHERS` (lines 1808-1810) | no STRICT (routine-level catch-all regardless) | S-TICKET-040 |
| 60 | `ddl/src/pkgb/tt_ticket_interface.sql:1830` | `v_page_id` etc. (`ticket_docs_page` by id) | yes (bad `p_ticket_docs_page_id`) | no (that table's PK) | `WHEN NO_DATA_FOUND THEN NULL` + `WHEN OTHERS` (lines 1841-1846) | STRICT + handler | S-TICKET-041 |
| 61 | `ddl/src/pkgb/tt_ticket_interface.sql:1875` | `v_escalation_status` (`ticket` by id, `handleDeferredTransitions`) | yes (structurally near-impossible, ticket pre-validated by caller) | no (`TICKET_PK`) | whole-routine `WHEN OTHERS` (lines 1915-1919) | STRICT + handler (routine-level) | S-TICKET-054 |
| 62 | `ddl/src/pkgb/tt_ticket_interface.sql:1936` | `v_counter` (`tt.ticket` `COUNT(*) ... IN (...)`) | no (aggregate) | no (aggregate) | whole-routine `WHEN OTHERS` (lines 1951-1955) | no STRICT | S-TICKET-042 |
| 63 | `ddl/src/pkgb/tt_ticket_interface.sql:1970` | `v_counter` (`tt.ticket2related_ticket` `COUNT(*)`) | no (aggregate) | no (aggregate) | whole-routine `WHEN OTHERS` (lines 1984-1989) | no STRICT | S-TICKET-043 |
| 64 | `ddl/src/pkgb/tt_ticket_interface.sql:2007` | `v_file_display_name` (3-way join, same-company guard) | yes (bad id OR cross-company mismatch, by design) | no (PK/guard-bounded) | `WHEN NO_DATA_FOUND` (descriptive message) + `WHEN OTHERS` (lines 2019-2027) | STRICT + handler | S-TICKET-044 |
| 65 | `ddl/src/pkgb/tt_ticket_interface.sql:2046` | `v_counter` (`tt.ticket2mc_file` `COUNT(*)`) | no (aggregate) | no (aggregate) | whole-routine `WHEN OTHERS` (lines 2064-2069) | no STRICT | S-TICKET-045 |
| 66 | `ddl/src/pkgb/tt_ticket_interface.sql:2051` | `v_file_display_name` (`mc.mc_file` by id, conditional) | structurally surprising but not re-verified (see Assumptions) | no (`mc_file` PK) | whole-routine `WHEN OTHERS` (same as #65) | STRICT + handler (routine-level) | S-TICKET-045 |
| 67 | `ddl/src/pkgb/tt_ticket_interface.sql:2105` | `v_counter` (`tt.ticket_request_classification` `COUNT(*)`) | no (aggregate) | no (aggregate) | whole-routine `WHEN OTHERS` (lines 2120-2124) | no STRICT | S-TICKET-047 |
| 68 | `ddl/src/pkgb/tt_ticket_interface.sql:2149` | `v_host_id, v_company_id` (`tt.ticket` by id, conditional) | yes (bad `p_ticket_id`) | no (`TICKET_PK`) | none; `clear_todo_list` has no `EXCEPTION` block | STRICT, unhandled | S-TICKET-048 |
| 69 | `ddl/src/pkgb/tt_ticket_interface.sql:2193` | `p_todo_item_id` (`todoitem_seq.NextVal`) | no (sequence) | no (sequence) | n/a; `add_todo_item` has no `EXCEPTION` block | no STRICT | S-TICKET-049 |
| 70 | `ddl/src/pkgb/tt_ticket_interface.sql:2244` | `v_old_status_name` etc. (`tt.todo_item` LEFT JOIN `tt.todo_item_status`) | yes (no todo item for `(ticket_id, seq_no)`) | no (assumed key, see Assumptions) | none; `update_todo_item_status` has no `EXCEPTION` block | STRICT, unhandled | S-TICKET-050 |
| 71 | `ddl/src/pkgb/tt_ticket_interface.sql:2256` | `v_host_id, v_company_id` (`tt.ticket` by id) | yes (bad `p_ticket_id`) | no (`TICKET_PK`) | none | STRICT, unhandled | S-TICKET-050 |
| 72 | `ddl/src/pkgb/tt_ticket_interface.sql:2261` | `v_status_name` (`tt.todo_item_status` by id) | yes (bad status id) | no (`TODO_ITEM_STATUS` PK) | none | STRICT, unhandled | S-TICKET-050 |
| 73 | `ddl/src/pkgb/tt_ticket_interface.sql:2330` | `v_stats_id` (`tt.ticket_time_statistic` by ticket id) | yes (first-ever stats write) | no (assumed unique on `ticket_id`, see Assumptions) | local `WHEN NO_DATA_FOUND` (lines 2332-2344) | STRICT + handler | S-TICKET-055 |
| 74 | `ddl/src/pkgb/tt_ticket_interface.sql:2335` | `v_stats_id` (`tt.tickettimestatistic_seq.nextval`, inside handler) | no (sequence) | no (sequence) | (inside handler above) | no STRICT | S-TICKET-055 |
| 75 | `ddl/src/pkgb/tt_ticket_interface.sql:2343` | `v_stats_id` (re-`SELECT` after `MERGE`, inside handler) | structurally near-impossible (row now guaranteed to exist) | no | (inside handler above) | STRICT + handler | S-TICKET-055 |
| 76 | `ddl/src/pkgb/tt_ticket_interface.sql:2381` | `v_flow_id, v_flow_in_date` (`tt.ticket_flow`, open entry) | yes (expected common case — no open entry) | unverified/assumed-no (see Assumptions) | local `WHEN NO_DATA_FOUND THEN v_flow_id := NULL` (lines 2383-2386) | STRICT + handler | S-TICKET-051 |
| 77 | `ddl/src/pkgb/tt_ticket_interface.sql:2391` | `v_mcc_flag` etc. (`tt.ticket` by id) | yes (bad `p_ticket_id`) | no (`TICKET_PK`) | none; `updateTicketFlow` has no procedure-level `EXCEPTION` block | STRICT, unhandled | S-TICKET-051 |
| 78 | `ddl/src/pkgb/tt_ticket_interface.sql:116` | `v_sender_contact_id` (`MAX(contact_id)` over `auth.login` by `oidc_zitadel_id`) | no (an aggregate always returns one row; NULL when no login matches) | no (aggregate) | none; reached only for a sign-off Zitadel sender without `p_contact_id` | plain `INTO` (an aggregate; `STRICT` would be satisfied too) | S-TICKET-061 |

### 3. Exception codes

**Zero `RAISE_APPLICATION_ERROR` calls and zero named-exception declarations or raises
exist anywhere in this 2,484-line package body** (confirmed: `grep -c
RAISE_APPLICATION_ERROR` and `grep -c "^\s*RAISE\b"` both return 0 against
`ddl/src/pkgb/tt_ticket_interface.sql`; matches `migration/analyze/inventory.json`'s
`raise_application_error: []` for `TT.TICKET_INTERFACE`). This is a real, structural
contrast with its cycle-mate `TT.EVENT_INTERFACE`, which DOES raise one named exception
through a companion `*_STATE` package
(`EVENT_INTERFACE_STATE.S_ERRNO_TICKET_CLOSED`, `migration/spec/tt.event_interface.md`
S-EVENT-021) — nothing here required the same by-hand trace this plan's sibling had to
do for that constant. The only exception surface this package presents to callers is the
large set of `STRICT, unhandled` sites in the table above (13 `NO_DATA_FOUND` handlers
against 77 sites, 0 `TOO_MANY_ROWS` handlers, 10 `WHEN OTHERS` handlers — all matching
`migration/analyze/inventory.json`'s `exception_handlers` counts exactly) — a plain,
un-numbered `NO_DATA_FOUND`/`TOO_MANY_ROWS`, or whatever constraint-violation exception
an `INSERT`/`UPDATE`/`DELETE` triggers (e.g. `deleteTicket`'s FK-dependent cascade,
S-TICKET-052). There is nothing package-specific for XCUT-01 to map here beyond the
general, cross-package requirement (already stated identically in both sibling specs)
that PL/pgSQL's default `NO_DATA_FOUND` SQLSTATE (`P0002`) and `TOO_MANY_ROWS` SQLSTATE
(`P0003`) must propagate to these routines' callers exactly as Oracle's `ORA-01403`/
`ORA-01422` do today. Mapping decision deferred to Phase 3.

### 4. Package state

None. Verified two ways: (1) `migration/analyze/inventory.json` lists `package_state: []`
and `has_init_block: false` for `TT.TICKET_INTERFACE`; (2) confirmed independently by
reading the full 2,484-line package body — it opens directly with three private-routine
FORWARD DECLARATIONS (`ddl/src/pkgb/tt_ticket_interface.sql:7-29`, signature-only, no
variable declarations), immediately followed by `newticket_new`'s own declaration section
at line 35 — there is no package-level `DECLARE`-equivalent section between `IS`
(line 3) and the first routine body. The file ends at line 2484
(`END ticket_interface;`) with no trailing unnamed initialization block.

### 5. FUNCTION vs PROCEDURE

**Zero `COMMIT`, zero `ROLLBACK`, zero `PRAGMA AUTONOMOUS_TRANSACTION` anywhere in this
package** (confirmed: `grep -ciE "COMMIT|ROLLBACK|PRAGMA"` against
`ddl/src/pkgb/tt_ticket_interface.sql` returns 0; matches
`migration/analyze/inventory.json`'s `has_commit: false, has_rollback: false,
autonomous_transaction: false`). This package declares exactly TWO `FUNCTION`s —
`get_next_recent_ticket` and `replace_id_placeholders` — both fully traced in
S-TICKET-046: neither calls anything that could reach a `COMMIT`
(`get_next_recent_ticket` issues one aggregate `SELECT` and calls nothing else;
`replace_id_placeholders` is pure string manipulation with zero database access and zero
calls to anything). **Neither `FUNCTION` has a FUNCTION/PROCEDURE-COMMIT hazard.** This
package's own two current call sites into `TT.UTIL` (which DOES `COMMIT`, per
`migration/spec/tt.util.md`) are both from `change_status_event_id_out`
(S-TICKET-058), a `PROCEDURE` — not from either `FUNCTION` — so no cross-package
collision is currently reachable through this package's `FUNCTION`s either. `pg_kind`
remains PROVISIONAL for all 38 routines (Phase 3 XCUT-04), per `migration/README.md`'s
standing warning — this dimension confirms no COMMIT-reachability hazard exists WITHIN
this package, it does not settle the final PostgreSQL FUNCTION-vs-PROCEDURE shape for any
of the 38 routines, including the two `FUNCTION`s themselves (a Phase 3 decision could
still choose to make either a `PROCEDURE` with an OUT parameter for consistency with the
rest of the package, independent of whether a COMMIT-reachability hazard exists).

## Assumptions / Unresolved

- **Line references predate the 2026-10-20 export except where marked.** That export
  (commit 0e5c990) inserted 32 lines into `newticket_new` after former line 94 and 1 line
  in its `INSERT` column list, and 1 line into `change_worker`'s `UPDATE`; every
  `ddl/src/pkgb/tt_ticket_interface.sql:NNN` citation below site #3 in the SELECT INTO table
  is therefore offset by +32 (sites #3-#8) or +33 (#9 onward) against the current file.
  S-TICKET-061..063 and site #78 cite current line numbers.

- **The doc/body disagreement in `expire_status`** (S-TICKET-021): the package spec's
  comment claims it "calls change_label() and change_status()"; the body only calls
  `change_status`. This spec records the body's actual behavior as authoritative (per
  this plan's own instruction). **Resolved on branch `phoenix/migrate_tt_only` (Q11
  (c)): stale documentation, behaviour kept** — the only caller passes the ticket's own
  current label, so the documented `change_label` call would be a no-op (evidence listed
  in S-TICKET-021). What remains unknowable statically is whether an Oracle-side client
  outside `ddl/src/` ever calls `expire_status` directly with a DIFFERENT label; none is
  known, and the parameter's own doc ("current label id") argues against it.
- **The `add_status_change_event` `cust_id`-never-assigned bug** (S-TICKET-053): every
  audit event written through this private routine has `company_id = NULL`. Whether this
  is a LATENT bug nobody has noticed (because `company_id` on these specific audit
  events is never read by any UI/report), or a bug that IS visible somewhere downstream,
  cannot be determined from static source alone. Originally recorded as a faithful
  behavior to preserve, with the fix deferred to an explicit, documented deviation
  decision. **That decision was taken on branch `phoenix/migrate_tt_only`** (status
  report 2026-10-13, Q11 (b)): corrected — S-TICKET-059 states the behaviour, the
  translation carries a `DEVIATION(ORACLE-BUG)` annotation and
  `migration/pgsql/tt/ticket_interface.FINDINGS.md` ("Deviations from Oracle") records
  it. Still open: any downstream consumer that filtered these events on `company_id IS
  NULL` (unlikely, but not statically excludable) would see them disappear from that
  filter.
- **Three structural-uniqueness assumptions this spec relies on but did not independently
  re-verify against every relevant constraint in `ddl/generated/schema.oracle.sql` for
  this plan** (each is used to justify a "no STRICT concern beyond zero-row" verdict in
  the table above): (a) `tt.ticket_time_statistic.ticket_id` is unique (site #73/#75,
  S-TICKET-055) — the routine's own `MERGE ... WHEN NOT MATCHED` race-avoidance logic
  strongly implies this is intended to be enforced, but this spec did not locate and cite
  the specific unique constraint/index by name; (b) `tt.ticket_flow` cannot have two
  simultaneously-open (`flow_out_date IS NULL`) rows for the same ticket (site #76,
  S-TICKET-051) — implied by the routine's own insert-if-none-open logic, not
  independently confirmed via a partial unique index; (c) `(tt.todo_item.ticket_id,
  tt.todo_item.seq_no)` is unique (site #70, S-TICKET-050) — implied by the routine
  addressing "the" todo item by that pair, not independently confirmed. None of these
  affects the STRICT-vs-unhandled verdict in the table (each site would need `STRICT`
  regardless of whether the assumption holds, to correctly surface `TOO_MANY_ROWS` if it
  ever turns out to be wrong) — flagged so Phase 4/5 knows these three are inferred from
  routine behavior, not independently schema-confirmed.
- **`add_related_file` vs `remove_related_file`'s asymmetric same-company guard**
  (S-TICKET-044 vs S-TICKET-045): `add_related_file`'s file-name lookup deliberately
  joins through `mc.mc_file_release` to enforce `t.company_id = r.company_id`;
  `remove_related_file`'s mirror lookup does not. Whether this asymmetry is intentional
  (removal doesn't need the same authorization check because the relation's existence was
  already checked) or an oversight cannot be determined from static source alone.
  Originally recorded faithfully as written. **Harmonized on branch
  `phoenix/migrate_tt_only`** (status report 2026-10-13, Q11 (d)): a caller must not be
  able to detach a relation across companies — S-TICKET-060 states the guard, the
  translation carries a `DEVIATION(ORACLE-BUG)` annotation and
  `migration/pgsql/tt/ticket_interface.FINDINGS.md` records it. Still open: a relation
  whose file has NO `mc.mc_file_release` row at all (release withdrawn after attachment)
  can no longer be detached through this routine; Oracle allowed that. If that is a
  real operational case it needs its own decision.
- **The private-routine naming convention** (`__` double-underscore prefix, see "Private
  routines" above) is REUSED from `migration/spec/tt.osag_notify.md`/
  `migration/spec/tt.event_interface.md`, not reinvented — but, per those specs' own
  standing caveat, it remains outside `migration/mapping/name-map.csv` and is not
  finalized by this spec. Flagged again in this plan's SUMMARY.
- **`pg_kind` (FUNCTION vs PROCEDURE) remains PROVISIONAL for all 38 routines**, per
  `migration/README.md`'s standing warning — Checklist dimension 5 confirms no
  COMMIT/ROLLBACK/autonomous-transaction hazard exists WITHIN this package for either of
  its two current `FUNCTION`s, but the final call belongs to Phase 3's XCUT-04.
- **The exact PostgreSQL syntax for `sequence.NEXTVAL`/`sequence.CurrVal` FROM DUAL**
  (used at 9 sites across this package, e.g. S-TICKET-005, S-TICKET-031, S-TICKET-053,
  S-TICKET-055) is a corpus-wide translation mechanic (`nextval('tt.<sequence>')`/
  `currval('tt.<sequence>')`), not something this package-specific spec can settle in
  isolation — noted here so whichever plan performs the actual translation does not have
  to re-derive it, consistent with `migration/spec/tt.event_interface.md`'s S-EVENT-011
  and `migration/spec/tt.osag_notify.md`'s S-NOTIFY-015.
- **The mutual recursion with `TT.EVENT_INTERFACE`** (S-TICKET-057) is an ACCEPTED cycle
  group per `migration/analyze/known_cycles.json` — both packages must be translated as
  one batch. This spec and `migration/spec/tt.event_interface.md` independently reach the
  identical conclusion about `CREATE`-time vs call-time resolution in PL/pgSQL; recorded
  here for consistency, not re-derived from scratch.
- Nothing else is unresolved: all 38 public routines (both `change_label` overloads
  specced as distinct routines, cross-checked programmatically against
  `migration/analyze/inventory.json`), all 77 `SELECT ... INTO` sites (cross-checked
  programmatically — all 77 present with an explicit STRICT verdict), all 13
  `NO_DATA_FOUND` handlers, all 10 `WHEN OTHERS` handlers, the confirmed absence of any
  `TOO_MANY_ROWS` handler, the full absence of package state, the full absence of
  `COMMIT`/`ROLLBACK`/`PRAGMA AUTONOMOUS_TRANSACTION`, and the `static_resolution:
  "complete"` status (no dynamic SQL anywhere in this package) were reviewed against the
  complete text of `ddl/src/pkg/tt_ticket_interface.sql` and
  `ddl/src/pkgb/tt_ticket_interface.sql`, cross-referenced against
  `migration/analyze/inventory.json`, `migration/mapping/name-map.csv`'s 38
  `TT.TICKET_INTERFACE` rows, and `migration/analyze/known_cycles.json`'s cycle-group
  entry for this package.

