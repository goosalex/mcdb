---
oracle_schema: TICKETEVOLUTION
oracle_package: CALCULATOR
pg_schema: ticketevolution
pg_prefix: calculator
clause_prefix: TICKEV
oracle_spec: ddl/src/pkg/ticketevolution_calculator.sql
oracle_body: ddl/src/pkgb/ticketevolution_calculator.sql
public_routines: 2
---

# TICKETEVOLUTION.CALCULATOR — PostgreSQL spec

Materializes a ticket's evolution — one `ticketevolution.tickev` row per observable change
of (status, emergency state, assigned engineer, MCC state, ticket type, label) — by
replaying the ticket's `tt.event` history in order (`ddl/src/pkg/ticketevolution_calculator.sql:4-13`).
`materialize_tickev` rebuilds a single ticket; `materialize_incremental` is the hourly
scheduled entry point (`ddl/src/jobs/ticketevolution_incremental_update.sql:7`) that
rebuilds every ticket touched since the previous run, bookkeeping its own watermark in
`ticketevolution.state` and **committing inside the procedure** (the package spec says so
explicitly, `ddl/src/pkg/ticketevolution_calculator.sql:11`). Unqualified `tickev` and
`state` in the body resolve to the package owner's schema, `TICKETEVOLUTION`.

Every date written to `tickev` comes from `tt.event.db_date` (the row's database insert
time), except the emergency-margin test, which reads `tt.event.eventdate`
(`ddl/src/pkgb/ticketevolution_calculator.sql:114`).

This spec contains two **corrected** clauses (S-TICKEV-009, S-TICKEV-011) where the Oracle
body contradicts its own stated intent; each states the corrected behaviour, cites the
Oracle line, and is marked so the translation's `-- DEVIATION(ORACLE-BUG):` annotations and
`calculator.FINDINGS.md` can be traced back here.

## Routines

### materialize_tickev

- **Oracle signature:** `PROCEDURE materialize_tickev(p_ticket_id tt.EVENT.ticket_id%TYPE)`
- **PostgreSQL name:** `ticketevolution.calculator_materialize_tickev` (from `name-map.csv`, `pg_kind=procedure`)
- **Declared:** `ddl/src/pkg/ticketevolution_calculator.sql:7`
- **Defined:** `ddl/src/pkgb/ticketevolution_calculator.sql:4-186`
- Soft-deletes the ticket's live `tickev` rows, then replays `tt.event` rows for the ticket
  (oldest first) through a state machine, inserting one `tickev` row per emitted state and
  closing the previous row's `date_to`. No COMMIT, no exception handler of its own; a
  nonexistent ticket propagates `NO_DATA_FOUND`.

### materialize_incremental

- **Oracle signature:** `PROCEDURE materialize_incremental`
- **PostgreSQL name:** `ticketevolution.calculator_materialize_incremental` (from `name-map.csv`, `pg_kind=procedure`)
- **Declared:** `ddl/src/pkg/ticketevolution_calculator.sql:13`
- **Defined:** `ddl/src/pkgb/ticketevolution_calculator.sql:188-211`
- Reads (or initialises) the `LAST_RUN` watermark in `ticketevolution.state`, calls
  `materialize_tickev` for every `tt.ticket` whose `update_timestamp` (second precision) is
  newer than the watermark, COMMITs after each ticket, then advances the watermark to the
  procedure's own start time and COMMITs again.

## Clauses

### S-TICKEV-001

- **routines:** materialize_tickev
- **claim:** `materialize_tickev` first resolves the ticket's CURRENT type name via
  `SELECT ty.name INTO v_ttype FROM tt.ticket_type ty, tt.ticket t WHERE t.id = p_ticket_id AND t.type_id = ty.id`.
  `tt.ticket.id` and `tt.ticket_type.id` are primary keys, so `TOO_MANY_ROWS` is
  structurally impossible; `NO_DATA_FOUND` IS reachable (ticket does not exist, or its
  `type_id` is NULL / matches no type) and propagates **unhandled** out of
  `materialize_tickev` — the routine has no `EXCEPTION` section at all (lines 17-186), and
  the package's only handler (lines 195-199) does not enclose the call at line 205. The
  resolved name seeds `ticket_type` for every row emitted before the first type-change
  event (S-TICKEV-015).
- **source:** `ddl/src/pkgb/ticketevolution_calculator.sql:32-35`, `ddl/src/pkgb/ticketevolution_calculator.sql:17-186`

### S-TICKEV-002

- **routines:** materialize_tickev
- **claim:** Before replaying, every live `tickev` row of the ticket (`deleted = 0`) is
  soft-deleted: `deleted = 1`, `update_dt = SYSDATE`. Rows are never physically removed, so
  re-running `materialize_tickev` on an unchanged ticket leaves the previous generation
  present with `deleted = 1` and produces a fresh, identical generation with `deleted = 0`.
- **source:** `ddl/src/pkgb/ticketevolution_calculator.sql:38`

### S-TICKEV-003

- **routines:** materialize_tickev
- **claim:** The replay considers exactly the `tt.event` rows with `ticket_id = p_ticket_id`
  AND `org_ticket_id IS NULL`, ordered by `(db_date, id)` ascending. Events carrying a
  non-NULL `org_ticket_id` (events copied in from a merged ticket) are ignored entirely —
  they neither emit rows nor advance the state machine. A ticket with zero qualifying
  events ends with zero live `tickev` rows (the soft-delete of S-TICKEV-002 and the type
  lookup of S-TICKEV-001 still run).
- **source:** `ddl/src/pkgb/ticketevolution_calculator.sql:40-44`

### S-TICKEV-004

- **routines:** materialize_tickev
- **claim:** The first qualifying event ALWAYS emits a row (`v_out := 1` before the loop,
  "always produce initial row"). The initial state is: status `'new'`, emergency state
  `'non-emergency'`, assigned engineer NULL, MCC state `'MCC'`, ticket type = the name
  resolved in S-TICKEV-001, label NULL. If the first event is not itself a state-changing
  event (e.g. an engineer change), the first emitted row carries status `'new'` and
  `ticket_status_id = (SELECT MIN(id) FROM tt.status WHERE name = 'new')`, and NO extra
  pseudo-row (S-TICKEV-009) is inserted then or later, because `v_last_status` is already
  `'new'` (non-NULL) from that point on.
- **source:** `ddl/src/pkgb/ticketevolution_calculator.sql:18-29`, `ddl/src/pkgb/ticketevolution_calculator.sql:160-182`

### S-TICKEV-005

- **routines:** materialize_tickev
- **claim:** Every emitted row is inserted with `date_from = date_to = e.db_date`,
  `update_dt = SYSDATE`, `deleted` at its column default (0), and
  `ticket_status_id = (SELECT MIN(id) FROM tt.status WHERE name = v_status)` — which is NULL
  when the status text extracted from the event matches no `tt.status.name`. After the
  insert, `v_last_event_id := e.id`, `v_last_status := v_status`, `v_out := 0`. The most
  recently emitted row of a ticket therefore always has `date_from = date_to`.
- **source:** `ddl/src/pkgb/ticketevolution_calculator.sql:177-181`

### S-TICKEV-006

- **routines:** materialize_tickev
- **claim:** Status change: an event whose `type_id` is in
  (101002, 101003, 101004, 101011, 101012, 101060, 101061, 101101, 101102, 101110, 101120)
  AND whose `details_public LIKE 'New status: %'` sets the status to the first
  capture group of `'^New status: (.+)$'` evaluated in Oracle multiline mode (`'m'`: `^`/`$`
  anchor at line boundaries, `.` does not cross a newline — i.e. the remainder of the FIRST
  line after `'New status: '`), e.g. `'open'`. A row is emitted only if the new status
  differs from the status of the last emitted row (`v_status != v_last_status`); a repeated
  status-change event to the SAME status emits nothing and changes nothing. The
  `!=` is NULL-unsafe in Oracle exactly as in PostgreSQL — it only matters when
  `v_last_status` is NULL, which is (a) before the first emitted row, where `v_out` is
  already 1 (S-TICKEV-004), or (b) after a row was emitted with a NULL status, which
  requires a degenerate `details_public` of exactly `'New status: '` (see Assumptions).
- **source:** `ddl/src/pkgb/ticketevolution_calculator.sql:63-64`, `ddl/src/pkgb/ticketevolution_calculator.sql:70-72`, `ddl/src/pkgb/ticketevolution_calculator.sql:79-82`

### S-TICKEV-007

- **routines:** materialize_tickev
- **claim:** Merge: an event of `type_id` 100004 ("ticket merged") sets the status to the
  literal `'merged'` regardless of its details, and is subject to the same
  differs-from-last gate as S-TICKEV-006. Consequently the two merge workflows documented
  inline — (1) a `101110` `'New status: merged'` event plus a `100004` event, (2) a lone
  `100004` event — both yield exactly ONE `'merged'` row (`ticket_status_id` = the id of
  `tt.status` `'merged'`), never two.
- **source:** `ddl/src/pkgb/ticketevolution_calculator.sql:66`, `ddl/src/pkgb/ticketevolution_calculator.sql:68-77`, `ddl/src/pkgb/ticketevolution_calculator.sql:79-82`

### S-TICKEV-008

- **routines:** materialize_tickev
- **claim:** Date chaining: when a row is emitted and a previous row was emitted for this
  replay (`v_last_event_id IS NOT NULL`), the previous row — live (`deleted = 0`), same
  ticket, `event_id = v_last_event_id` — gets `date_to = e.db_date` (the new row's
  `date_from`) and `update_dt = SYSDATE`. Live rows of one generation therefore form a
  contiguous chain: each row's `date_to` equals the next row's `date_from`. Events that
  emit nothing (S-TICKEV-006 repeats, S-TICKEV-011 in-place update, S-TICKEV-013 "other
  emergency text", ignored events of S-TICKEV-003) do not touch any `date_to`.
- **source:** `ddl/src/pkgb/ticketevolution_calculator.sql:168-175`

### S-TICKEV-009

- **routines:** materialize_tickev
- **claim:** Pseudo "new" row **(CORRECTED — see FINDINGS "Deviations from Oracle")**: when
  the first emitted row's status is not `'new'` (the first qualifying event is a status
  change or merge, so `v_last_status IS NULL AND v_status != 'new'`), an extra row is
  inserted immediately before it, carrying the SAME `event_id`, status `'new'`,
  `ticket_status_id = MIN(id) of tt.status 'new'`, assigned engineer NULL (Oracle `''`),
  the current emergency/MCC/type/label state, `date_from = v_first_event_date` and
  `date_to = e.db_date` — both the first event's `db_date`, so the pseudo-row is a
  zero-length `'new'` interval at the first event's timestamp. **Corrected behaviour:** the
  pseudo-row's `date_to` is NEVER extended afterwards; S-TICKEV-008's chaining update
  applies only to the real row emitted for that event. (Oracle keys the chaining update on
  `event_id` alone — lines 170-174 — so, because the pseudo-row shares the first event's
  id, Oracle ALSO stretches the pseudo-row's `date_to` to the second emitted event's
  `db_date`, producing two overlapping live intervals `'new'` [T1,T2] and e.g. `'open'`
  [T1,T2] for one ticket. That contradicts the explicit `date_to = e.DB_DATE` the same code
  assigns to the pseudo-row at line 165 and the contiguous-chain invariant of S-TICKEV-008;
  it is an unintended side effect of a non-unique `event_id`, not a design.)
- **source:** `ddl/src/pkgb/ticketevolution_calculator.sql:162-166`, `ddl/src/pkgb/ticketevolution_calculator.sql:170-174`, `ddl/src/pkgb/ticketevolution_calculator.sql:45-48`

### S-TICKEV-010

- **routines:** materialize_tickev
- **claim:** Engineer change: an event with `type_id = 100003` AND
  `details_private LIKE 'Engineer changed to:%'` sets the assigned engineer to the first
  capture group of `'^Engineer changed to: ([^ .]+)'` (the first token, e.g. `'jho'`) and
  the MCC state to the first capture group of
  `'^Engineer changed to: [^ ]+ \(((non-)?MCC)\)'` (`'MCC'` or `'non-MCC'`; NULL if the
  text carries no parenthesised MCC marker). If the engineer token is literally `'MCC'`,
  the engineer becomes NULL (Oracle `''`) and the MCC state `'MCC'`. A row is ALWAYS
  emitted. This branch is tested BEFORE the emergency and label branches, so a 100003 event
  whose `details_private` starts with `'Engineer changed to:'` is never treated as an
  emergency or label change.
- **source:** `ddl/src/pkgb/ticketevolution_calculator.sql:86-99`

### S-TICKEV-011

- **routines:** materialize_tickev
- **claim:** Emergency flag on a still-new ticket **(CORRECTED — see FINDINGS "Deviations
  from Oracle")**: an event with `type_id = 100003` AND `details_public` exactly
  `'ticket changed to emergency'`, arriving while the replay status is `'new'` AND the
  emergency state is `'non-emergency'`, does NOT emit a row if it can be folded into the
  ticket's creation: every live, `'non-emergency'` `tickev` row of the ticket whose
  `date_from` lies less than **60 seconds** before the event's `eventdate`
  (`e.eventdate < date_from + 60 seconds`) is updated in place to
  `emergency_state = 'emergency'`, `update_dt = SYSDATE`. Only if that update touches zero
  rows (`SQL%ROWCOUNT = 0`, i.e. the flag was set more than 60 s after the row started) is
  a new row emitted. Either way the replay's emergency state becomes `'emergency'`. (Oracle
  line 114 reads `date_from + 60`, which in Oracle DATE arithmetic is 60 DAYS — the inline
  comment at line 109, "60s margin for setting emergency flag on a new ticket", states the
  intent; 60 days would fold virtually every flag-after-creation into the creation row and
  make the `SQL%ROWCOUNT = 0` branch dead in practice. The stated intent, 60 seconds, is
  the specified behaviour.)
- **source:** `ddl/src/pkgb/ticketevolution_calculator.sql:103-119`, `ddl/src/pkgb/ticketevolution_calculator.sql:123`

### S-TICKEV-012

- **routines:** materialize_tickev
- **claim:** An event with `type_id = 100003` AND `details_public` exactly
  `'ticket changed to emergency'` arriving when the replay status is NOT `'new'` OR the
  emergency state is already `'emergency'` always emits a row with
  `emergency_state = 'emergency'` (no in-place update is attempted).
- **source:** `ddl/src/pkgb/ticketevolution_calculator.sql:105-107`, `ddl/src/pkgb/ticketevolution_calculator.sql:120-123`

### S-TICKEV-013

- **routines:** materialize_tickev
- **claim:** An event with `type_id = 100003` AND `details_public` exactly
  `'ticket changed to non-emergency'` sets the emergency state to `'non-emergency'` and
  always emits a row. A 100003 event whose `details_public` merely CONTAINS `'emergency'`
  but equals neither exact phrase (`LIKE` without wildcards is equality) enters this
  branch and then does nothing: no state change, no row — and, because the `ELSIF` chain
  has already matched, it is NOT re-examined as a label or type change.
- **source:** `ddl/src/pkgb/ticketevolution_calculator.sql:103-105`, `ddl/src/pkgb/ticketevolution_calculator.sql:124-128`

### S-TICKEV-014

- **routines:** materialize_tickev
- **claim:** Label ("queue") change: an event with `type_id = 100003` AND
  `details_private LIKE 'Ticket label %'` (and not matching S-TICKEV-010/011-013 first)
  sets the label to: the first capture group of `'^Ticket label ([^ ]+) added'` for
  `'Ticket label % added'`; the first capture group of
  `'^Ticket label changed to ([^ ]+)'` (first space-delimited token only) for
  `'Ticket label changed to %'`; NULL for `'Ticket label removed %'`; unchanged for any
  other `'Ticket label %'` text. A row is ALWAYS emitted, even in the unchanged case.
- **source:** `ddl/src/pkgb/ticketevolution_calculator.sql:132-144`

### S-TICKEV-015

- **routines:** materialize_tickev
- **claim:** Ticket type change: an event with `type_id = 100005` AND
  `details_public LIKE 'type changed from %'` is parsed with
  `'^type changed from ([a-z ]+) to ([a-z ]+)$'` (lower-case letters and spaces only; a
  non-matching text yields NULL for both groups). On the FIRST such event of the replay,
  group 1 (the "from" type) is written back as `ticket_type` of EVERY live `tickev` row of
  the ticket emitted so far — these rows were seeded with the ticket's CURRENT type
  (S-TICKEV-001), and the event is the first evidence of what the type actually was before.
  This rewrite is intended per the inline comment ("update existing tickev records") and
  happens exactly once per replay (`v_ttype_initial` flag); a second type-change event
  does not rewrite earlier rows. In every case the replay's type becomes group 2 (the "to"
  type) and a row is emitted.
- **source:** `ddl/src/pkgb/ticketevolution_calculator.sql:147-157`

### S-TICKEV-016

- **routines:** materialize_tickev
- **claim:** Oracle `''` is NULL: the initial engineer and label (`v_eng := ''`,
  `v_label := ''`), the engineer after an `'MCC'` token (`v_eng := ''`), and the pseudo-row's
  `ASSIGNED_ENGINEER` literal `''` are all NULL in Oracle. The corresponding `tickev`
  columns (`assigned_engineer`, `ticket_label`) MUST be SQL NULL in the emitted rows, never
  the empty string. `v_ttype := ''` is dead (overwritten by S-TICKEV-001 before any use).
- **source:** `ddl/src/pkgb/ticketevolution_calculator.sql:24-28`, `ddl/src/pkgb/ticketevolution_calculator.sql:96`, `ddl/src/pkgb/ticketevolution_calculator.sql:165`

### S-TICKEV-017

- **routines:** materialize_tickev
- **claim:** Events of any other `type_id`, or of a listed `type_id` whose details fail the
  branch's `LIKE` gate (e.g. a 101002 event whose `details_public` does not start with
  `'New status: '`, or a 100003 event with no recognised `details_private`/`details_public`
  text), fall through the whole `IF ... ELSIF` chain: no state change and — unless `v_out`
  is still 1 from initialisation (first event, S-TICKEV-004) — no row.
- **source:** `ddl/src/pkgb/ticketevolution_calculator.sql:63-158`, `ddl/src/pkgb/ticketevolution_calculator.sql:160`

### S-TICKEV-018

- **routines:** materialize_incremental
- **claim:** `materialize_incremental` records its own start time (`v_this_run := SYSDATE`,
  second precision) FIRST, then reads the watermark via
  `SELECT value_dt INTO v_last_run FROM state WHERE key = 'LAST_RUN'`. On `NO_DATA_FOUND`
  (first ever run) it initialises `v_last_run := SYSDATE - 365` (days), inserts the row
  `('LAST_RUN', v_last_run)` into `ticketevolution.state`, and COMMITs immediately. `state`
  has no key constraint; a second `LAST_RUN` row would raise `TOO_MANY_ROWS`, which is NOT
  handled and propagates.
- **source:** `ddl/src/pkgb/ticketevolution_calculator.sql:192-200`

### S-TICKEV-019

- **routines:** materialize_incremental, materialize_tickev
- **claim:** `materialize_incremental` calls `materialize_tickev(t.id)` for every
  `tt.ticket` whose `update_timestamp`, reduced to DATE precision
  (`CAST(update_timestamp AS DATE)` — Oracle DATE has whole-second precision; the cast drops
  fractional seconds, it keeps time-of-day), is STRICTLY GREATER than `v_last_run`, and
  COMMITs after each ticket. Tickets with `update_timestamp` at or before the watermark are
  not touched. Because `materialize_tickev`'s `NO_DATA_FOUND` is unhandled (S-TICKEV-001),
  one broken ticket aborts the loop; tickets already processed stay committed.
- **source:** `ddl/src/pkgb/ticketevolution_calculator.sql:202-207`

### S-TICKEV-020

- **routines:** materialize_incremental
- **claim:** After the loop, the `LAST_RUN` watermark is set to `v_this_run` — the time the
  procedure STARTED, not finished — and committed. Tickets updated after `v_this_run` while
  the run was in progress are therefore picked up by the NEXT run even if this run already
  processed them; a ticket updated in the same whole second as `v_this_run` after the
  loop's query ran is NOT picked up next time (its truncated `update_timestamp` equals, and
  is not greater than, the watermark). The whole procedure is a top-level scheduled job
  (`ddl/src/jobs/ticketevolution_incremental_update.sql:7`, hourly); it has no callers in
  the static call graph.
- **source:** `ddl/src/pkgb/ticketevolution_calculator.sql:192`, `ddl/src/pkgb/ticketevolution_calculator.sql:209-210`

## Checklist

### 1. Empty-string / NULL handling

No routine has a `VARCHAR2` parameter (`materialize_tickev(p_ticket_id NUMBER)` via
`tt.event.ticket_id%TYPE`; `materialize_incremental()` has none). The `VARCHAR2` surface is
entirely local variables and `tt.event` columns:

- `v_eng := ''` (line 24), `v_label := ''` (line 28), `v_ttype := ''` (line 26), `v_eng := ''`
  (line 96), literal `''` in the pseudo-row insert (line 165): all NULL in Oracle. A naive
  port writing `''` would store empty strings in `assigned_engineer`/`ticket_label` where
  Oracle stores NULL. Decision: write `NULL` explicitly at all five sites (S-TICKEV-016).
  `v_ttype := ''` is dead (overwritten at line 32).
- `v_eng = 'MCC'` (line 94): `v_eng` is NULL only if the engineer regexp did not match,
  which cannot happen inside the `LIKE 'Engineer changed to:%'` gate unless the text is
  exactly `'Engineer changed to:'` (regexp needs one more char); either way NULL = 'MCC' is
  not true in both engines. Leave as-is.
- `v_status != v_last_status` (line 79) and `v_status != 'new'` (line 162): NULL-unsafe in
  both engines, identically. Reachable only via a degenerate `details_public` of exactly
  `'New status: '` (passes `LIKE 'New status: %'`, fails `(.+)`). Leave as-is; recorded in
  Assumptions.
- `e.details_public LIKE ...` / `e.details_private LIKE ...` (lines 64, 86, 103, 105, 124,
  132, 134, 137, 140, 147): a NULL details column makes every `LIKE` NULL (not true) in both
  engines — the event falls through (S-TICKEV-017). `tt.event.details_*` are nullable
  (`ddl/migrated/tables/tables.pg.sql`), and a PostgreSQL `''` details value would simply
  fail all these gates just as Oracle NULL does. Leave as-is.
- `REGEXP_SUBSTR(...)` returning NULL on no match (lines 72, 89, 91, 136, 139, 152, 156):
  `(regexp_match(...))[n]` returns NULL on no match too. Leave as-is.
- `WHERE name = v_status` (line 178) with NULL `v_status`: `MIN(id)` over zero rows is NULL
  in both engines — `ticket_status_id` NULL (S-TICKEV-005).

### 2. SELECT INTO strictness

Two sites, matching the Phase 1 inventory's `select_into_sites: [32, 194]`:

- `ddl/src/pkgb/ticketevolution_calculator.sql:32-35` (`materialize_tickev`, ticket type
  name): zero rows reachable (nonexistent ticket, NULL/unmatched `type_id`); multi-row
  impossible (PK joins). No handler at any enclosing scope within `materialize_tickev`
  (lines 17-186 contain no `EXCEPTION`); when called from `materialize_incremental` (line
  205) the only handler in that routine (lines 195-199) is a closed block that does not
  enclose line 205. Translation: `SELECT ... INTO STRICT`, no handler — unhandled
  `NO_DATA_FOUND` (PL/pgSQL `P0002`) propagates exactly as Oracle's `ORA-01403` does
  (S-TICKEV-001).
- `ddl/src/pkgb/ticketevolution_calculator.sql:194` (`materialize_incremental`, watermark):
  zero rows expected on the first ever run and handled by `WHEN NO_DATA_FOUND` (lines
  195-199); multi-row reachable in principle (`state` has no PK/unique constraint in
  `ddl/migrated/tables/tables.pg.sql:3611-3614`) and NOT handled — `TOO_MANY_ROWS` would
  propagate. Translation: `INTO STRICT` with a `NO_DATA_FOUND` handler mirroring Oracle's,
  no `TOO_MANY_ROWS` handler (S-TICKEV-018). Note the Oracle handler body COMMITs (line
  199); PL/pgSQL forbids `COMMIT` inside a block that has an `EXCEPTION` clause, so the
  translation must set a flag in the handler and perform the insert+COMMIT after the block
  — same observable behaviour, different block shape.

### 3. Exception codes

No `RAISE_APPLICATION_ERROR`, no named exception, no `WHEN OTHERS` anywhere in the package
(inventory: `raise_application_error: []`, handlers `NO_DATA_FOUND: 1, TOO_MANY_ROWS: 0,
OTHERS: 0`; confirmed by reading all 214 lines). The exception surface is: unhandled
`NO_DATA_FOUND` from line 32 (S-TICKEV-001) → PL/pgSQL `P0002` `no_data_found` from
`STRICT`; and an unhandled `TOO_MANY_ROWS` from line 194 → `P0003` `too_many_rows`.
Mapping PROVISIONAL per XCUT-01; nothing package-specific to add.

### 4. Package state

None. The body opens with `PROCEDURE materialize_tickev` immediately after `AS` (lines
3-4) — no package-level declare section — and ends with `END CALCULATOR;` (line 213) with
no trailing initialisation block. Matches the inventory's `package_state: []`,
`has_init_block: false`. The persistent watermark lives in the `ticketevolution.state`
TABLE, not in package state, so it survives flattening unchanged.

### 5. FUNCTION vs PROCEDURE

Both routines are `PROCEDURE` in Oracle (`ddl/src/pkg/ticketevolution_calculator.sql:7,13`)
and `pg_kind=procedure` in `name-map.csv`. `materialize_incremental` issues three
`COMMIT`s (`ddl/src/pkgb/ticketevolution_calculator.sql:199,206,210`, matching the
inventory's `has_commit_sites`), one of them inside a cursor `FOR` loop; no `ROLLBACK`, no
`PRAGMA AUTONOMOUS_TRANSACTION`. Decision (same as `tt.util_close_old_dev_tickets`,
option 1): a plain PostgreSQL PROCEDURE with REAL `COMMIT`s. Consequences: it can only be
`CALL`ed at the top level of a transaction chain (never from a FUNCTION, never inside an
explicit `BEGIN` block that the caller intends to roll back) — which matches its only
usage, a scheduler job running `BEGIN ticketevolution.CALCULATOR.materialize_incremental; END;`
(`ddl/src/jobs/ticketevolution_incremental_update.sql:7`). The per-ticket `COMMIT` inside
the `FOR` loop makes PL/pgSQL convert the loop cursor to a holdable cursor on the first
commit — the set of tickets is fixed when the loop's query starts, as in Oracle.
`materialize_tickev` never commits and is callable from anywhere, including inside pgTAP's
wrapping transaction.

## Assumptions / Unresolved

- **Exact status text in `details_public`.** The replay copies whatever follows
  `'New status: '` into `tickev.ticket_status` and resolves `ticket_status_id` by exact
  match on `tt.status.name` (S-TICKEV-005). Whether the application writes
  e.g. `'waiting for signoff'` (the masterdata `tt.status.name`) or `'waiting for sign-off'`
  (the `tt.event_type.name` wording) cannot be known from `ddl/src/**`; a mismatch yields a
  NULL `ticket_status_id` in both engines. The translation preserves the lookup verbatim;
  tests use statuses whose spelling is unambiguous (`open`, `hot`, `merged`).
- **Degenerate `'New status: '` events** (S-TICKEV-006 (b)): an event whose
  `details_public` is exactly `'New status: '` emits a row with NULL status, after which
  the next status change is swallowed by the NULL-unsafe `!=` until some other branch
  emits a row. Both engines behave identically; this spec does not correct it because no
  intent statement in the source contradicts it and real data is unavailable to show it
  occurs. Not tested.
- **S-TICKEV-011's 60-second margin is a correction**, chosen from the inline comment at
  line 109 over the arithmetic at line 114. If the production author actually relied on
  the 60-day behaviour (every flag-after-creation folded into the creation row), live
  Oracle `tickev` data would show almost no `'new'`→`'emergency'` row pairs; that cannot be
  checked without an Oracle instance. Decision recorded in FINDINGS "Deviations from
  Oracle".
- **S-TICKEV-009's non-extension of the pseudo-row is a correction**, derived from the
  explicit `date_to = e.DB_DATE` at line 165 and the chain invariant; Oracle data would
  show overlapping `'new'`/`<first status>` live rows for tickets whose first qualifying
  event is a status change. Same caveat as above.
- **Timestamp precision.** Oracle `DATE`/`SYSDATE` are whole seconds; `tickev.date_*`,
  `state.value_dt` are `timestamp(0)` in the migrated DDL, and `tt.ticket.update_timestamp`
  is `timestamp` (microseconds, set from `SYSTIMESTAMP` by `tt.ticket_update_trg`).
  PostgreSQL ROUNDS on assignment to `timestamp(0)` where Oracle's cast TRUNCATES; the
  translation must truncate explicitly (`date_trunc('second', ...)`) for `v_this_run`,
  `v_last_run` and the `update_timestamp` comparison (S-TICKEV-019/020) so a watermark can
  never be rounded into the future. `SYSDATE` → `statement_timestamp()` per project
  convention.
- **`e.eventdate` vs `e.db_date`** (S-TICKEV-011): the emergency margin compares the
  event's `eventdate` with `date_from` values that came from `db_date`. Whether the two
  ever differ materially for 100003 events (they are both defaulted to the insert time in
  the migrated DDL) is unknown; the translation keeps the exact column choice.
- `tickev` has no primary key; the translation's corrected chaining update (S-TICKEV-009)
  must therefore identify the real row by `(ticket_id, event_id, deleted = 0)` plus its
  status (`ticket_status IS NOT DISTINCT FROM v_last_status`), which distinguishes it from
  the pseudo-row (whose status is `'new'` while the real row's is guaranteed `!= 'new'` by
  the insert condition at line 162).
- Nothing else is unresolved: both `SELECT INTO` sites, the single handler, all three
  `COMMIT` sites, the (empty) declare section, every `REGEXP_SUBSTR`/`LIKE` gate, and the
  job definition were reviewed against the full text of
  `ddl/src/pkg/ticketevolution_calculator.sql`, `ddl/src/pkgb/ticketevolution_calculator.sql`
  and `ddl/src/jobs/ticketevolution_incremental_update.sql`.
