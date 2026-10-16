# TT.ESCALATION_INTERFACE -- FINDINGS

**Source:** `ddl/src/pkg/tt_escalation_interface.sql` (spec, 94 lines),
`ddl/src/pkgb/tt_escalation_interface.sql` (body, 223 lines). **Spec:**
`migration/spec/tt.escalation_interface.md` (22 clauses, S-ESC-001..022). **Target:**
`migration/pgsql/tt/escalation_interface.sql`. **Tests:**
`migration/test/pgtap/tt__escalation_interface__spec.sql` (74 assertions),
`migration/test/regress/sql/tt__escalation_interface__errors.sql` (+ golden).

This is the dynamic-dispatch TARGET package: `tt.event_interface_exec_event_type_actions`'s
`EXECUTE format('CALL %I.%I($1)')` (behind its hard-coded TT.ESCALATION_INTERFACE allowlist)
can now, for the first time, actually reach something. S-ESC-022's end-to-end test proves it
(event of a type mapped to `tt.event_action` id 1 -> ticket `escalation_status_id = 10` +
a 60001 event).

## Deviations from Oracle (project-owner instruction: correct broken behaviour, annotate it)

Two, both marked `-- DEVIATION(ORACLE-BUG)` at the site in the translation and specified
as corrected behaviour in the spec (S-ESC-008, S-ESC-014), so the tests assert the
corrected contract, not Oracle's.

| # | routine | Oracle behaviour (lines) | why it is broken | corrected behaviour |
|---|---|---|---|---|
| 1 | `escalate_os` | ONE `WHEN NO_DATA_FOUND THEN v_host_id := NULL` (45-48) covers the event lookup (27), both ticket lookups (32, 35) AND the host lookup (41). For a nonexistent event, control continues with `v_ticket_id`/`v_escalation_status_id`/`v_host_active` all NULL: `IN (10,11)` is not true (55), `v_host_id IS NULL` is true (60), so Oracle runs `UPDATE tt.ticket ... WHERE id = NULL` (0 rows, 65) and `addevent_new(v_event_id, NULL, 60001, NULL, ...)` (68-73); `addevent_new`'s first `SELECT ... WHERE t.id = NULL` raises NO_DATA_FOUND, swallowed and logged as `"unknown error for ticket: : no data found"` by its outer `WHEN OTHERS` (`tt_event_interface.sql:825-827`). | It "escalates" nothing, silently, and the only trace is a misleading error attributed to `addevent_new`. The handler was clearly written for the host lookup (the comment on line 59 explains the no-host case); applying it to the event/ticket lookups is an accident of scope. | Event/ticket lookups (sites #1-#3) get their own handler: `plog.err('tt.escalation_interface.escalate_os(): event with id N or its ticket not found. This is needed for escalation. Aborting escalation.')` + `RETURN`. No UPDATE, no `addevent_new`, no exception. The host lookup (site #4) keeps Oracle's handler and semantics exactly (S-ESC-005: no host / missing host -> escalate with `host_id NULL`). |
| 2 | `escalate_customer` | Same shared handler (114-117) over sites 98/104/110. For a nonexistent event: `v_escalation_status_id <> 0` is `NULL <> 0` -> not true (121, NULL-unsafe), `v_host_id IS NULL` true (126), `UPDATE ... WHERE ticket.id = NULL` matches 0 rows (127), `SQL%ROWCOUNT = 0` skips `addevent_new` (130). | A COMPLETELY silent no-op (not even a log line) for a request to escalate an event that does not exist -- the `SQL%ROWCOUNT` guard accidentally hides the same defect as #1. | Same correction: `plog.err('tt.escalation_interface.escalate_customer(): event with id N or its ticket not found. ...')` + `RETURN`. Data effect unchanged (none); the failure becomes observable. The `<> 0` comparison is left as-is -- it can no longer see a NULL (column is `NOT NULL`, and the corrected handler returns first). |

Reachability note (recorded in the spec too): `tt.event.ticket_id` is `NOT NULL` in both
the Oracle export (`ddl/export/schema.oracle.sql:130`) and the migrated schema, so "event
exists but has no ticket id" is structurally impossible; the real defect path is "event
missing", plus "ticket row missing" under deferred FK checking.

**NOT treated as defects, deliberately:**

- `escalate_customer`'s name and comments vs. its body (S-ESC-012): the pkg comment
  (`pkg:22-32`) and body header (`pkgb:82-84`) describe a customer escalation (60101 /
  status 20 / Securitas wizard); the body writes status **10** and event **60001**. The body
  is authoritative; translated and tested as 10/60001. Whether the comments are stale or the
  body was changed on purpose is unknowable from source.
- The "missing host -> treat as no host -> escalate anyway" semantics (S-ESC-005): intended
  per the inline comment on line 59, preserved.
- `escalate_isp_outage_to_os`'s second `SELECT eventdate` (line 182) outside the handler
  (S-ESC-017): unreachable NO_DATA_FOUND in practice (the row was just proven to exist by
  the six-table join); translated `STRICT`, unhandled, no shim -- not an externally
  reachable error site.

## AuditUsage deletion count

**5 of 5** `plog.AuditUsage(...)` call sites deleted outright, one per public routine
(`escalate_os` line 22, `escalate_customer` line 95, `escalate_isp_outage_to_os` line 159,
`nop` line 210, `clear_customer_escalation` line 217) -- confirmed by
`grep -c AuditUsage ddl/src/pkgb/tt_escalation_interface.sql` -> 5. Per XCUT-06, deleted,
not stubbed. `nop` is therefore literally empty (`NULL;`), exactly its Oracle intent.

## `pg_kind` verdict: correct for all 5, and the ONLY kind that can work

All five are Oracle `PROCEDURE`s, `name-map.csv` says `pg_kind=procedure` for all five,
all five are created as PostgreSQL `PROCEDURE`s (`prokind='p'` verified by the five
S-ESC-001 assertions). This is not merely consistent but forced: the package is reached
exclusively by `CALL` -- dynamically (`EXECUTE format('CALL %I.%I($1)') USING p_event_id`
in `exec_event_type_actions`, whose allowlist names exactly `escalation_interface_escalate_os`,
`_escalate_customer`, `_escalate_isp_outage_to_os`, `_nop`) and statically
(`MC.MONITORING_TICKET_PROCESSES.new_event_up` -> `clear_customer_escalation`). No
COMMIT/ROLLBACK/autonomous transaction anywhere (inventory and full read agree), so no
XCUT-04/05 collision.

## Transaction-scope delta on the S-ESC-009 path (recorded, not asserted)

`escalate_os`/`escalate_customer` have no handler around `addevent_new`; the one error
`addevent_new` re-raises (`ticket_closed`, Oracle -20980, translated as SQLSTATE `OS980`
in `event_interface.sql`, PROVISIONAL) propagates out AFTER the line-65/127 UPDATE ran.
In Oracle, when the dispatching `exec_event_type_actions` swallows it, the UPDATE
(status := 10) STAYS. In PL/pgSQL the dispatcher's `BEGIN ... EXCEPTION` block is a
subtransaction, so the UPDATE is rolled back with the failed CALL: a closed ticket ends
at status 10 in Oracle, 0 in PostgreSQL. Reachable only for a ticket that is simultaneously
closed (`status_id > 101`) and receiving an escalation-triggering event; arguably the
PostgreSQL outcome is saner, but it is a behavioural delta owned by XCUT-05. The pgTAP
S-ESC-009 assertions only pin that the error propagates (`throws_like '%closed%'`).

## SELECT INTO strictness (9 sites, matching the spec's table and the inventory)

- Sites #1-#3 (`escalate_os` event/ticket lookups) and #5-#6 (`escalate_customer`):
  `STRICT` + the CORRECTED local `NO_DATA_FOUND` handler (log + return) -- deviation #1/#2.
- Sites #4 and #7 (host `active` lookups): `STRICT` + Oracle's own `v_host_id := NULL`.
- Site #8 (`escalate_isp_outage_to_os` six-table join): `STRICT` + Oracle's two-arm
  `NO_DATA_FOUND`/`OTHERS` log-and-return handler, texts verbatim.
- Site #9 (`eventdate`): `STRICT`, unhandled, no shim (S-ESC-017).
- No `TOO_MANY_ROWS` handling needed anywhere: every site is PK-keyed.

The "no data found" message-parity shim is NOT used in this package: there is no
externally reachable unhandled NO_DATA_FOUND site left (the two that existed in Oracle are
exactly the corrected ones, which now never raise).

## Translation mechanics worth knowing

- **`(+)` -> `LEFT JOIN`** for `ec`/`tc` (event/ticket company); `sc` (host service
  company), `t`, `h` stay inner joins; `NVL(e.host_id, t.host_id)` -> `COALESCE`.
- **NULL concatenation (Pitfall 2):** Oracle's `||` treats NULL as `''`, PostgreSQL's
  `||` nulls the whole string. `concat()` (Oracle semantics) is used wherever an operand
  can be NULL: `p_event_id` in the error/debug lines, `v_ticket_id`/`v_host_id` in the
  debug lines (a host-less ticket logs `host id is ` rather than NULL), and
  `v_company_short` in the ISP-outage public text -- S-ESC-018's "NULL company short ->
  `Company: ` line survives" assertion (a company with `short IS NULL` is a legal row: the
  `lower(short) = short` CHECK passes NULL) proves this live. `||` is kept where every
  operand is provably NOT NULL.
- **`SQL%ROWCOUNT` -> `GET DIAGNOSTICS v_rows = ROW_COUNT`** immediately after the
  race-guarded UPDATE in `escalate_customer`.
- **`newticket_new` call shape:** OUT parameters first (`v_ticket_id, v_event_id`), then
  the 13 positional arguments exactly as Oracle; `SYSDATE` passed explicitly as
  `statement_timestamp()::timestamp` -- the parameter is a naive `timestamp` and CALL
  resolution has no implicit `timestamptz -> timestamp` cast (found by probing the call
  before writing the translation: `statement_timestamp()` alone fails with "no procedure
  matches the given name and argument types"). `addevent_new`'s `eventdate` is
  `timestamptz` with a default, left at its default as Oracle does.
- **`%TYPE` parameter:** `clear_customer_escalation(p_ticket_id tt.ticket.id%TYPE)` is
  kept as `%TYPE` (resolves to `numeric`), following `osag_notify.sql`'s established
  convention for `%TYPE` parameters.
- **`TYPE ref_cursor IS REF CURSOR`** in the package spec: unused by every routine, not
  ported.
- **Unqualified `ticket` / `event`** in the Oracle body (`FROM ticket`, `FROM event`,
  `WHERE ticket.id = ...`) resolve to `tt.ticket` / `tt.event` (package owner schema);
  the `UPDATE tt.ticket ... WHERE ticket.id = v_ticket_id` form is valid PostgreSQL.

## Schema / masterdata facts the tests depend on

- `tt.event_type_action` is EMPTY in the template's masterdata, so in a fresh container
  nothing is dispatched to this package until event types are mapped to action 1. The
  S-ESC-022 test maps a pilot-owned event type (908020) to action 1 itself.
- `tt.event_action` id 1 = `tt.escalation_interface.escalate_os` (no `procedure_key_id`),
  `tt.event_type` 60001/30005/10001/10003, `tt.escalation_status` 0/10/11/20,
  `mss.service_component` 27, `mss.operating_system` 2 are all present in masterdata.
  `mss.host` / `stop.company` are not -- pilot-owned rows (908xxx) in the fixtures.
- `mss.host.active` defaults to 0: every "active host" fixture sets it explicitly.

## Red/green status (verified live against `mcdb_test_esc`, cloned from `mcdb_tmpl`)

**RED (before the translation existed, `--install migration/pgsql` without this file):**

```
PACKAGE                                  | PGTAP (pass/total) | REGRESS (pass/total) | RESULT
tt.escalation_interface                  | 17/74              | 0/1                | FAIL
TOTAL: 1 packages, 0 pass, 1 fail   (exit 1)
```

The 17 pre-passing assertions are exactly the "did NOT happen"/unchanged checks that sit
beside a failing `lives_ok` (an absent procedure trivially changes nothing) plus the
S-ESC-022 `lives_ok` on `exec_event_type_actions` -- which swallowed `procedure
tt.escalation_interface_escalate_os(numeric) does not exist` exactly as Oracle's own
`WHEN OTHERS` would; its two data assertions (status 10, 60001 event) failed, which is why
the dispatch proof rests on those and not on the `lives_ok`. The regress half failed on
`procedure ... does not exist` / `current transaction is aborted` against the golden.

**GREEN (translation installed), this package:**

```
tt.escalation_interface                  | 74/74              | 1/1                | PASS
```

**GREEN, whole harness (`run-tests.sh --db mcdb_test_esc --install migration/pgsql`):**

```
PACKAGE                                  | PGTAP (pass/total) | REGRESS (pass/total) | RESULT
_canary.canary                           | 2/2                | 1/1                | PASS
auth.osag_auth                           | 9/10               | 0/0                | FAIL
mss.osag_dbprop                          | 10/10              | 1/1                | PASS
tt.escalation_interface                  | 74/74              | 1/1                | PASS
tt.event_interface                       | 20/20              | 0/1                | FAIL
tt.osag_notify                           | 23/23              | 0/1                | FAIL
tt.ticket_interface                      | 125/129            | 0/1                | FAIL
tt.util                                  | 10/10              | 0/1                | FAIL
TOTAL: 8 packages, 3 pass, 5 fail
```

Every FAIL above is pre-existing and documented as known before this package was touched:
auth S-AUTH-007 (1), the ticket_interface selectinto assertions (tests 3, 10, 15, 20) and
the four stale regress goldens (event_interface / osag_notify / ticket_interface / util --
all CONTEXT-line / header-whitespace / redacted-DETAIL drift, verified by reading the
four diffs). No sibling pgTAP count
changed relative to the pre-existing state; none of those files were touched here.

## Verification performed

- `python3 migration/spec/spec_lint.py` (OK), `python3 migration/spec/trace_lint.py`
  (OK, 19/22 clauses cited -- uncited: S-ESC-002/010, structural lookup-shape clauses
  whose observable consequences are covered by 003..008 / 011..014, and S-ESC-017, the
  practically unreachable site), `bash migration/spec/provenance_lint.sh` (OK for this
  package once the translation commit landed: spec commit and first-test commit are both
  ancestors; no commit touches translation and test files together).
- `grep -nEi "dbms_|utl_|auditusage|dblink|pg_background"` over the translation: zero
  matches outside comments.
- `pg_proc.prokind = 'p'` for all five routines (S-ESC-001 assertions).
- Commit order: spec (`1dc047f`), spec amendment pinning the corrected log texts
  (`51e1dfd`), RED suite (`dd4fd33`), then this translation + FINDINGS.

## Open questions (could not be settled from the Oracle source)

- Whether `escalate_customer` was MEANT to become an OS escalation (body) or the comments
  are the intent (customer escalation, 60101/20). Translated per the body.
- Whether production maps event type 30005 (the incident report
  `escalate_isp_outage_to_os` creates, "which is then automatically escalated" per the
  pkg comment) to action 1 -- `tt.event_type_action` is empty in the repo's masterdata.
- The S-ESC-009 transaction-scope delta for closed tickets (above) -- XCUT-05's call.
