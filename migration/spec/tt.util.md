---
oracle_schema: TT
oracle_package: UTIL
pg_schema: tt
pg_prefix: util
clause_prefix: UTIL
oracle_spec: ddl/src/pkg/tt_util.sql
oracle_body: ddl/src/pkgb/tt_util.sql
public_routines: 5
---

# TT.UTIL — PostgreSQL spec

Scheduled batch maintenance for the ticket system: closing long-resolved tickets,
escalating stale non-hot tickets to "hot", recomputing `status_valid_until_date`,
auto-resolving DNIDS-scanner tickets, and (dev-instance-only) closing abandoned tickets
and pruning duplicate spam events. Per the package header comment
(`ddl/src/pkg/tt_util.sql:5-11`), these procedures are meant to be scheduled via
`tt.submit_user_jobs`, not called ad hoc from application code — with one exception:
`update_status_valid_until` IS called directly by `TT.EVENT_INTERFACE` and
`TT.TICKET_INTERFACE` (see S-UTIL-015).

**This package is the pilot's deliberate first collision between Oracle's
`COMMIT`/`PRAGMA AUTONOMOUS_TRANSACTION` and PostgreSQL's FUNCTION/PROCEDURE rules.**
See Checklist dimension 5 and the Assumptions section below — the transaction-semantics
decision belongs to Phase 3 (XCUT-04, XCUT-05); this spec documents the finding and its
consequences without pre-empting that decision.

## Routines

### check_resolved_tickets

- **Oracle signature:** `PROCEDURE check_resolved_tickets`
- **PostgreSQL name:** `tt.util_check_resolved_tickets` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/tt_util.sql:20`
- **Defined:** `ddl/src/pkgb/tt_util.sql:7-34`
- Closes tickets that have been in "resolved" (status 101) for 14+ days: sets them to
  "closed" (102) via `TT.TICKET_INTERFACE.change_status`, stamps `close_date`, and
  deletes their notifications via `TT.OSAG_NOTIFY`.

### check_ticket_status

- **Oracle signature:** `PROCEDURE check_ticket_status`
- **PostgreSQL name:** `tt.util_check_ticket_status` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/tt_util.sql:30`
- **Defined:** `ddl/src/pkgb/tt_util.sql:39-67`
- Finds tickets whose `status_valid_until_date` has passed (statuses waiting/third-party/
  deferred/waiting-for-signoff) and delegates their status expiry to
  `TT.TICKET_INTERFACE.expire_status`.

### update_status_valid_until

- **Oracle signature:** `PROCEDURE update_status_valid_until(p_ticket_id NUMBER, p_valid_until_date DATE DEFAULT NULL)`
- **PostgreSQL name:** `tt.util_update_status_valid_until` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/tt_util.sql:39`
- **Defined:** `ddl/src/pkgb/tt_util.sql:72-147`
- Recomputes and writes `tt.ticket.status_valid_until_date` (and, for waiting-family
  statuses, `last_deferral_date`) based on the ticket's current status, type, and
  emergency flag. The ONLY routine in this package with a direct, non-scheduled caller
  (S-UTIL-015).

### check_dnids_tickets_to_resolve

- **Oracle signature:** `PROCEDURE check_dnids_tickets_to_resolve`
- **PostgreSQL name:** `tt.util_check_dnids_tickets_to_resolve` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/tt_util.sql:44`
- **Defined:** `ddl/src/pkgb/tt_util.sql:153-174`
- Auto-resolves customer-incident (type 5) tickets whose most recent public event
  indicates a DNIDS/DNIPS scan came back clean, via
  `TT.TICKET_INTERFACE.change_status(..., 101, ...)`.

### close_old_dev_tickets

- **Oracle signature:** `PROCEDURE close_old_dev_tickets`
- **PostgreSQL name:** `tt.util_close_old_dev_tickets` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/tt_util.sql:56`
- **Defined:** `ddl/src/pkgb/tt_util.sql:208-246`
- Dev-instance-only (self-checking): closes abandoned MCC tickets with no activity in 30
  days, and prunes ("despams") tickets with more than 5000 events. Runs as
  `PRAGMA AUTONOMOUS_TRANSACTION` and `COMMIT`s per-iteration — see S-UTIL-010/012/013/014
  and Checklist dimension 5.

## Clauses

### S-UTIL-001

- **routines:** check_resolved_tickets
- **claim:** `check_resolved_tickets` uses cursor `cur_resolved` (status 101, resolved
  14+ days ago) in a `FOR` loop — not `SELECT ... INTO`. Zero matching tickets is a
  normal, non-exceptional outcome (empty loop body); no exception of any kind is raised
  for "nothing to close".
- **source:** `ddl/src/pkgb/tt_util.sql:9-13, 20-31`

### S-UTIL-002

- **routines:** check_ticket_status
- **claim:** `check_ticket_status` uses cursor `t_cur_valid_date_not_null` (statuses
  11/12/60/61 with `status_valid_until_date < SYSDATE`) in a `FOR` loop, delegating each
  match to `ticket_interface.expire_status`. Same "empty loop, no exception" pattern as
  S-UTIL-001.
- **source:** `ddl/src/pkgb/tt_util.sql:44-52, 60-65`

### S-UTIL-003

- **routines:** update_status_valid_until
- **claim:** `update_status_valid_until` resolves the ticket's `type_id`, `status_id`,
  `emergency`, `handled_by_mcc` via
  `SELECT ... INTO ... FROM tt.ticket WHERE id = p_ticket_id`. `tt.ticket.id` is the
  primary key, so `TOO_MANY_ROWS` is structurally impossible. **This package has ZERO
  exception handlers anywhere** (0 `EXCEPTION` blocks in the whole 248-line body,
  confirmed against the Phase 1 inventory's handler counts of 0/0/0) — so if
  `p_ticket_id` does not exist, `NO_DATA_FOUND` propagates FULLY UNHANDLED out of
  `update_status_valid_until` to WHATEVER called it. See S-UTIL-015 for exactly which two
  routines that is today.
- **source:** `ddl/src/pkgb/tt_util.sql:96-98`

### S-UTIL-004

- **routines:** update_status_valid_until
- **claim:** If the ticket's status is "deferred" (60), `update_status_valid_until`
  `RETURN`s immediately with no writes at all — deferred tickets are explicitly excluded
  from this routine's logic (handled elsewhere, per the inline comment).
- **source:** `ddl/src/pkgb/tt_util.sql:100-103`

### S-UTIL-005

- **routines:** update_status_valid_until
- **claim:** For statuses waiting/third-party/waiting-for-signoff (11, 12, 61), the
  computed offset depends on the `emergency` flag: emergency tickets default to +4h,
  capped at +1d if the caller supplied an explicit `p_valid_until_date` within that
  window; non-emergency tickets default to +20d, capped at +60d under the same condition.
- **source:** `ddl/src/pkgb/tt_util.sql:106-128`

### S-UTIL-006

- **routines:** update_status_valid_until
- **claim:** `update_status_valid_until` ALWAYS writes `tt.ticket.status_valid_until_date`
  — either to `SYSDATE + v_period_to_add` (S-UTIL-005's computed offset), or to the
  caller-supplied `p_valid_until_date` verbatim, or — for every status NOT in
  (11,12,60,61), since neither `v_period_to_add` nor `v_valid_until_date` gets set —
  it resets the field to `NULL`. This means calling `update_status_valid_until` on a
  ticket in any "other" status (e.g. open, hot, resolved) silently CLEARS
  `status_valid_until_date`, which is deliberate per the inline comment (line 136-137:
  "if it changed to a state not using the valid_until -> reset this field to NULL!").
- **source:** `ddl/src/pkgb/tt_util.sql:131-139`

### S-UTIL-007

- **routines:** update_status_valid_until
- **claim:** For statuses waiting/third-party/waiting-for-signoff (11, 12, 61),
  `update_status_valid_until` ALSO unconditionally overwrites
  `tt.ticket.last_deferral_date` with `p_valid_until_date` — which is `NULL` when the
  caller uses the 1-argument form (the parameter's `DEFAULT null`). Calling the 1-arg
  form on such a ticket therefore always nulls out `last_deferral_date` too, not just
  `status_valid_until_date`.
- **source:** `ddl/src/pkgb/tt_util.sql:142-145`

### S-UTIL-008

- **routines:** check_dnids_tickets_to_resolve
- **claim:** `check_dnids_tickets_to_resolve` uses cursor `cur_to_resolve` (customer-
  incident tickets, type 5, status < 101, whose last public event is a DNIDS/DNIPS scan
  event older than 7 days OR matching an "ALLCLEAN" regex) in a `FOR` loop, resolving
  each match via `ticket_interface.change_status(..., 101, ...)`. Same "empty loop, no
  exception" pattern as S-UTIL-001/002.
- **source:** `ddl/src/pkgb/tt_util.sql:155-161, 167-171`

### S-UTIL-009

- **routines:** close_old_dev_tickets
- **claim:** `close_old_dev_tickets` calls the PRIVATE helper `despam_ticket` (not part of
  the package's public spec — no `name-map.csv` row of its own), which deletes
  duplicate/excess `tt.event` rows for any `(ticket_id, type_id)` pair exceeding
  `p_limit` occurrences, always preserving the min event id, the max event id, the
  ticket's `last_public_event_id`, and any event still referenced by
  `mc.isp_link_history`. Its own `SELECT MIN(e.id), MAX(e.id) INTO v_min, v_max ...` (line
  187) is an aggregate query — always exactly one row, structurally safe from
  `NO_DATA_FOUND`/`TOO_MANY_ROWS`, same guarantee as S-DBPROP-001/S-AUTH-009's `DUAL`/
  aggregate sites. Documented here only because `close_old_dev_tickets` (public) invokes
  it directly and Phase 4 must still translate it correctly.
- **source:** `ddl/src/pkgb/tt_util.sql:176-202`

### S-UTIL-010

- **routines:** close_old_dev_tickets
- **claim:** `close_old_dev_tickets` is declared with `PRAGMA AUTONOMOUS_TRANSACTION`
  (`ddl/src/pkgb/tt_util.sql:209`) — Oracle runs its entire body in a transaction
  independent of its caller's. PostgreSQL has **no autonomous-transaction equivalent**.
  This is one of exactly two table-writing autonomous-transaction sites in the whole
  corpus (`.planning/research/PITFALLS.md`). See Checklist dimension 5 and Assumptions
  for the full write-up; this clause records only the mechanical fact.
- **source:** `ddl/src/pkgb/tt_util.sql:209`

### S-UTIL-011

- **routines:** close_old_dev_tickets
- **claim:** `close_old_dev_tickets` determines whether it is allowed to run at all via
  `SELECT COUNT(*) INTO v_is_dev FROM V$INSTANCE WHERE HOST_NAME LIKE '%-dev-%'` — a
  `COUNT` aggregate (always exactly one row, same structural guarantee as S-UTIL-009), so
  this is not a `NO_DATA_FOUND` concern. It IS a hard translation gap: `V$INSTANCE` is an
  Oracle dynamic performance view with **no PostgreSQL equivalent whatsoever**. How the
  translated procedure will determine "is this a dev instance" is unresolved by static
  analysis alone (see Assumptions).
- **source:** `ddl/src/pkgb/tt_util.sql:223`

### S-UTIL-012

- **routines:** close_old_dev_tickets
- **claim:** If `v_is_dev = 0` (not a dev instance), `close_old_dev_tickets` explicitly
  issues `ROLLBACK` and `RETURN`s (`ddl/src/pkgb/tt_util.sql:226-227`). Because this
  happens inside the `PRAGMA AUTONOMOUS_TRANSACTION` body, that `ROLLBACK` only undoes
  the autonomous transaction's own (so-far-empty, since nothing was written yet) work —
  it has no effect on the caller's transaction at all. The net observable effect for any
  caller is simply "nothing happened."
- **source:** `ddl/src/pkgb/tt_util.sql:224-228`

### S-UTIL-013

- **routines:** close_old_dev_tickets
- **claim:** For each old, abandoned ticket found by cursor `c` (`HANDLED_BY_MCC = 1`,
  status not in (2, 102), status < 100, `OPEN_DATE` older than 30 days),
  `close_old_dev_tickets` calls `ticket_interface.change_status(..., 102, ...)` and then
  **`COMMIT`s immediately, inside the loop** (`ddl/src/pkgb/tt_util.sql:234`) — one
  `COMMIT` per ticket closed, not a single `COMMIT` at the end of the loop.
- **source:** `ddl/src/pkgb/tt_util.sql:210-216, 231-235`

### S-UTIL-014

- **routines:** close_old_dev_tickets
- **claim:** For each `(ticket_id)` group with more than 5000 `tt.event` rows,
  `close_old_dev_tickets` calls the private `despam_ticket(ticket_id, 100)` and then
  **`COMMIT`s immediately, inside the loop** (`ddl/src/pkgb/tt_util.sql:244`) — again one
  `COMMIT` per iteration, matching the per-ticket-closure pattern of S-UTIL-013.
- **source:** `ddl/src/pkgb/tt_util.sql:238-245`

### S-UTIL-015

- **routines:** update_status_valid_until
- **claim:** `update_status_valid_until` is called from exactly two sites in the whole
  corpus, per `migration/analyze/depgraph.json`'s edges into `TT.UTIL`
  (`TT.EVENT_INTERFACE` call_site 761; `TT.TICKET_INTERFACE` call_sites 520, 522) — both
  traced by hand: `ddl/src/pkgb/tt_event_interface.sql:761` is inside
  `PROCEDURE addevent_new` (declared `ddl/src/pkgb/tt_event_interface.sql:519`), and
  `ddl/src/pkgb/tt_ticket_interface.sql:520,522` is inside
  `PROCEDURE change_status_event_id_out` (declared
  `ddl/src/pkgb/tt_ticket_interface.sql:346`). **Both current callers are themselves
  declared `PROCEDURE` in Oracle, not `FUNCTION`** — as of today's call graph, no
  `FUNCTION` caller of `TT.UTIL` exists, so the classic "a PostgreSQL PROCEDURE that
  COMMITs cannot be CALLed from inside a FUNCTION body" hazard does not currently bite
  `update_status_valid_until` specifically. This finding is an input to XCUT-04, not a
  substitute for it: if either caller is later reclassified as a PostgreSQL `FUNCTION`
  during Phase 3's `pg_kind` finalization, this constraint would immediately re-apply.
  `check_resolved_tickets`, `check_ticket_status`, `check_dnids_tickets_to_resolve`, and
  `close_old_dev_tickets` have NO callers at all in the static call graph — they are
  scheduled entry points (per the package header, invoked via `tt.submit_user_jobs`), so
  no caller-side FUNCTION/PROCEDURE constraint applies to them, though the constraint on
  how THEY THEMSELVES must be invoked (top-level `CALL`, never nested inside a `FUNCTION`
  body) still holds.
- **source:** `ddl/src/pkgb/tt_event_interface.sql:519, 761`, `ddl/src/pkgb/tt_ticket_interface.sql:346, 520, 522`

## Checklist

### 1. Empty-string / NULL handling

N/A — verified by reading all five public routine signatures
(`ddl/src/pkg/tt_util.sql:20,30,39,44,56`): the only parameters anywhere in the package
are `p_ticket_id NUMBER` and `p_valid_until_date DATE` (`update_status_valid_until`); no
routine declares a `VARCHAR2`/`CLOB` parameter. The only `VARCHAR2`-typed identifiers in
the whole package are hardcoded log/status-change message string literals (e.g.
`'ticket resolved for more than 2 weeks, closing it automatically'`) and the
`c_prefix CONSTANT VARCHAR2(64)` declared in `check_ticket_status`
(`ddl/src/pkgb/tt_util.sql:54`), which is declared but never referenced anywhere in that
routine's body (dead code, confirmed by reading lines 39-67 in full) — none of these
takes part in an `IS NULL`/`IS NOT NULL` check, a comparison, or a `||` concatenation
against caller-supplied data.

### 2. SELECT INTO strictness

Three `SELECT ... INTO` sites, matching the Phase 1 inventory count exactly, against a
package with **zero exception handlers anywhere** (0/0/0, confirmed by reading the full
248-line body):

- `ddl/src/pkgb/tt_util.sql:96` (`update_status_valid_until`) — plain (non-aggregate)
  select keyed on `tt.ticket.id` (PK); `TOO_MANY_ROWS` structurally impossible;
  `NO_DATA_FOUND` IS reachable if `p_ticket_id` doesn't exist and is completely unhandled
  — it propagates all the way out of the routine to whichever of its two current callers
  invoked it (S-UTIL-003/015).
- `ddl/src/pkgb/tt_util.sql:187` (private `despam_ticket`) — `MIN`/`MAX` aggregate,
  always exactly one row; structurally safe (S-UTIL-009).
- `ddl/src/pkgb/tt_util.sql:223` (`close_old_dev_tickets`) — `COUNT` aggregate, always
  exactly one row; structurally safe from a strictness perspective, but the underlying
  data source (`V$INSTANCE`) has no PostgreSQL equivalent at all (S-UTIL-011).

Translation: all three become `SELECT ... INTO STRICT` with **no local handler at any of
the three sites**, deliberately matching Oracle's "unhandled propagates" contract — this
package has no exception-handling infrastructure to preserve, so none should be invented.

### 3. Exception codes

No `RAISE_APPLICATION_ERROR` call and no named exception declaration or raise exists
anywhere in this package (confirmed by reading the full 248-line body). The only
"exception" surface is the fully-unhandled, propagated `NO_DATA_FOUND` from
`ddl/src/pkgb/tt_util.sql:96` (S-UTIL-003). There is nothing package-specific for XCUT-01
to map here beyond the general, cross-package requirement that PL/pgSQL `STRICT`'s
default `NO_DATA_FOUND` SQLSTATE (`P0002`) must propagate to `update_status_valid_until`'s
callers exactly as Oracle's unhandled `ORA-01403` does today — recorded here, mapping
decision deferred to Phase 3.

### 4. Package state

None. Verified by reading the full 248-line package body (`ddl/src/pkgb/tt_util.sql`):
the body opens directly with `PROCEDURE check_resolved_tickets` immediately after `IS`
(line 3-7), with no package-level declare section, and the file ends at line 247-248
(`END util; /`) with no trailing unnamed initialization block. Matches the Phase 1
inventory's `package_state: []` for this package.

### 5. FUNCTION vs PROCEDURE

**This is the point of this spec.** All five public routines are declared `PROCEDURE` in
Oracle (`ddl/src/pkg/tt_util.sql:20,30,39,44,56`), and `migration/mapping/name-map.csv`
carries `pg_kind=procedure` for all five. That looks settled. **It is not** — `pg_kind`
is explicitly PROVISIONAL (`migration/README.md`, "Standing warnings"), and the real
question is not "what kind is `TT.UTIL`" but **what kind is every caller of `TT.UTIL`,
transitively** (S-UTIL-015): a PostgreSQL PROCEDURE that issues `COMMIT` cannot be
`CALL`ed from inside a `FUNCTION` body.

- `update_status_valid_until` has exactly 2 current callers (S-UTIL-015), both
  `PROCEDURE`s today. No collision exists in the CURRENT static call graph, but this must
  be re-verified whenever XCUT-04 finalizes `pg_kind` for `TT.EVENT_INTERFACE.addevent_new`
  and `TT.TICKET_INTERFACE.change_status_event_id_out` themselves.
- `close_old_dev_tickets` carries `PRAGMA AUTONOMOUS_TRANSACTION` (S-UTIL-010) and two
  per-iteration `COMMIT`s (S-UTIL-013, S-UTIL-014). PostgreSQL has no autonomous-
  transaction equivalent at all. The write survives the CALLER's own later `ROLLBACK` in
  Oracle (that is the entire point of an autonomous transaction) — three candidate
  PostgreSQL behaviours exist, and this spec does not choose between them (that decision
  belongs to Phase 3's XCUT-05):
  1. **Plain PROCEDURE + real COMMIT** (accepting the delta): the `COMMIT` now commits
     the CALLER's own transaction too, since PostgreSQL has only one transaction per
     session — this is NOT symmetric with Oracle's true isolation (Oracle's autonomous
     transaction cannot see the caller's own uncommitted writes at all; a plain
     PostgreSQL `COMMIT` inside a `CALL`ed procedure commits everything the session has
     done so far, caller's work included).
  2. **True isolation via a background worker / `dblink`/`postgres_fdw` loopback
     connection**: preserves Oracle's isolation semantics but is heavyweight machinery
     for what is, per the package header, a nightly scheduled batch job.
  3. **Drop the per-iteration `COMMIT`/`ROLLBACK` entirely**, running the whole procedure
     in one caller-managed transaction: simplest, loses the "partial progress survives a
     later failure" property, but may be an acceptable match for how a top-level `CALL`
     from a cron-like scheduler actually behaves in practice.
- The `COMMIT`s at lines 234/244: `change_status` (line 233) and `despam_ticket` (line
  243) each commit their own writes IMMEDIATELY, one iteration at a time. After each
  `COMMIT`, execution continues in a NEW transaction — any locks or snapshot-visibility
  assumptions the rest of the loop held from before that point are gone. A caller of
  `close_old_dev_tickets` sees each closed ticket/despammed group become durably visible
  to OTHER sessions as soon as its own iteration's `COMMIT` executes, not only when the
  whole procedure finishes.

This checklist item RECORDS the finding and its consequences; it does not settle
XCUT-04/XCUT-05.

## Assumptions / Unresolved

- **`V$INSTANCE` has no PostgreSQL equivalent (S-UTIL-011).** How the translated
  `close_old_dev_tickets` will determine "is this a dev instance" is unresolved by static
  analysis of `ddl/src/**` alone — candidate replacements (a session/database GUC, a
  small config table, a naming convention on the connection string or database name) are
  Phase 3/4's call, not decided here.
- **Phase 2 will translate `close_old_dev_tickets` (and `TT.UTIL` generally) as a plain
  PostgreSQL PROCEDURE with a real `COMMIT`** — accepting the semantic delta from
  Oracle's `PRAGMA AUTONOMOUS_TRANSACTION` isolation described in Checklist dimension 5,
  option 1 — **and this pilot's tests therefore do NOT assert rollback-survival for it.**
  XCUT-05 owns the final autonomous-transaction decision; XCUT-04 owns the final
  FUNCTION-vs-PROCEDURE decision for `pg_kind` generally, including whether
  `update_status_valid_until`'s current callers stay `PROCEDURE`.
- Whether `TT.EVENT_INTERFACE.addevent_new` / `TT.TICKET_INTERFACE.change_status_event_id_out`
  (S-UTIL-015's only two current static callers of `TT.UTIL`) will still be declared
  `PROCEDURE` once XCUT-04 finalizes `pg_kind` for THEM is unresolved here — this spec
  only records their CURRENT Oracle declaration (both `PROCEDURE`) and flags that a
  future reclassification of either as `FUNCTION` would immediately collide with
  `TT.UTIL`'s own transaction control.
- `despam_ticket` is PRIVATE (no entry in `ddl/src/pkg/tt_util.sql`, and therefore no
  `name-map.csv` row of its own); it is documented here (S-UTIL-009) only because
  `close_old_dev_tickets` calls it directly and its `SELECT ... INTO` site matters for
  translation — not because it is itself in scope as a public routine of this package.
- Whether `mc.isp_link_history` (referenced in `despam_ticket`'s `NOT EXISTS` subquery,
  `ddl/src/pkgb/tt_util.sql:199`) ever has orphaned or mismatched rows in production that
  would change `despam_ticket`'s deletion set cannot be determined from static source
  review alone — no live Oracle exists for this phase to check against.
- Nothing else is unresolved: every `SELECT ... INTO` site (3, including the private
  helper's), the confirmed absence of any exception handler anywhere in the package, the
  full declare section (none), both `COMMIT` sites and the `PRAGMA
  AUTONOMOUS_TRANSACTION` pragma, and both current call sites into `TT.UTIL` (traced by
  hand into their enclosing routines) were reviewed against the full text of
  `ddl/src/pkg/tt_util.sql`, `ddl/src/pkgb/tt_util.sql`, and the relevant sections of
  `ddl/src/pkgb/tt_event_interface.sql` and `ddl/src/pkgb/tt_ticket_interface.sql`.
