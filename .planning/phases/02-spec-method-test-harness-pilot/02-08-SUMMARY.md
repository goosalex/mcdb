---
phase: 02-spec-method-test-harness-pilot
plan: 08
subsystem: testing
tags: [pgtap, pl-pgsql, oracle-migration, tt-ticket-interface, red-green, select-into-strictness]

# Dependency graph
requires:
  - phase: 02-spec-method-test-harness-pilot
    provides: "02-07's migration/spec/tt.ticket_interface.md (38 routines, 58 clauses, 77-site SELECT INTO table) and the dual pgTAP/expected-output harness from 02-01..02-03"
provides:
  - "Four RED test files (3 pgTAP suites + 1 expected-output pair) for TT.TICKET_INTERFACE, written before any translation exists"
  - "A full 77-site SELECT INTO reachability ledger (covered / shadowed-unreachable / no-STRICT-not-required / schema-driven-untestable)"
  - "Proof that the pilot's method scales to the largest package (38 routines) without quietly dropping coverage"
affects: ["02-11 (TT.EVENT_INTERFACE translation)", "02-12 (TT.TICKET_INTERFACE translation, the cycle-group landing wave)", "Phase 4 bulk translation"]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Deferred-FK fixture trick: every FK in ddl/migrated is DEFERRABLE, so SET CONSTRAINTS ALL DEFERRED lets a single test insert an intentionally orphaned reference (bad last_public_event_id, status_id, host_id, company_id, type_id, todo_item.ticket_id) to reach an otherwise-unreachable SELECT INTO site, reused from tt__osag_notify__selectinto.sql's established idiom"
    - "ROW(...)::record wrapping for multi-column is() assertions, with explicit type casts on the literal side (numeric/smallint) to avoid PostgreSQL's 'cannot compare dissimilar column types' error"
    - "DO $tag$ ... $tag$ block wrapping inside lives_ok/throws_ok string literals for OUT-parameter procedure calls (distinct dollar-quote tags per call site to avoid nesting collisions)"

key-files:
  created:
    - migration/test/pgtap/tt__ticket_interface__lifecycle.sql
    - migration/test/pgtap/tt__ticket_interface__changes.sql
    - migration/test/pgtap/tt__ticket_interface__selectinto.sql
    - migration/test/regress/sql/tt__ticket_interface__errors.sql
    - migration/test/regress/expected/tt__ticket_interface__errors.out
  modified: []

key-decisions:
  - "Both change_label overloads dispatched and asserted DISTINCTLY (2-arg silent no-op vs 3/4-arg audited update+own audit event) rather than merely calling both -- a translation dropping either overload cannot pass"
  - "Only 2 of the 3 empty-string/NULL findings in the spec's Checklist dimension 1 (change_customer_reference, change_partner_reference) get paired '' /NULL assertions -- the spec itself found change_notification already correctly handled with no divergence, and reviewed every other IS NULL/|| site as not '' -collapsing-relevant; inventing extra paired assertions where the spec found none would test something the spec never claimed"
  - "Site #20's multi-row (TOO_MANY_ROWS) fixture is NOT constructible in ddl/migrated's actual schema: tt.service_window carries an immediate, non-deferrable UNIQUE(ticket_id) index (plus a table comment stating 'A ticket can only have one service window'), contradicting the spec's assumption that a ticket 'can legitimately have more than one service_window row.' Covered instead with the single-row positive case; the schema-level contradiction is flagged below for Phase 4/5, not silently worked around"
  - "The exception-text regress golden (tt__ticket_interface__errors.out) is authored from the spec's expected SUBSTANCE ('no data found', silent swallow + plog row), per the 02-04 convention -- NOT from today's actual 'does not exist' output. Verified the mismatch by diffing actual vs golden by hand (see RED Output below)"

patterns-established: []

requirements-completed: [HARN-05, SPEC-03]

coverage:
  - id: D1
    description: "Every one of the 38 public routines of TT.TICKET_INTERFACE has at least one test citing a resolvable S-TICKET-NNN spec clause"
    requirement: "HARN-05"
    verification:
      - kind: other
        ref: "programmatic check against migration/analyze/inventory.json (38 rows in name-map.csv, 37 deduped by routine name since change_label is one name with two signatures) -- ALL_37_ROUTINES_HAVE_A_TEST"
        status: pass
    human_judgment: false
  - id: D2
    description: "Both change_label overloads are dispatched to and asserted distinctly, proving PostgreSQL's native overload resolution (not merely called twice)"
    requirement: "HARN-05"
    verification:
      - kind: unit
        ref: "migration/test/pgtap/tt__ticket_interface__changes.sql -- S-TICKET-019/S-TICKET-020 overload-pair block (7 assertions, 2-arg vs 3/4-arg dispatch + no-audit-event vs has-audit-event proof)"
        status: pass
    human_judgment: false
  - id: D3
    description: "Zero-row SELECT INTO cases are asserted across all reachable STRICT sites, so a translation that dropped STRICT could not pass"
    requirement: "HARN-05"
    verification:
      - kind: unit
        ref: "migration/test/pgtap/tt__ticket_interface__{lifecycle,changes,selectinto}.sql -- 15+ throws_ok('P0002'/'P0003', ...) assertions across the three files; selectinto.sql alone carries 15 throws_ok (>=10 required)"
        status: pass
    human_judgment: false
  - id: D4
    description: "The suite is RED: it fails because the translation does not exist, proven end-to-end via run-tests.sh --package tt.ticket_interface"
    requirement: "HARN-05"
    verification:
      - kind: other
        ref: "bash migration/test/run-tests.sh --db mcdb_test_p08 --package tt.ticket_interface -- exits non-zero, PACKAGE table shows tt.ticket_interface 0/129 pgTAP, 0/1 regress, RESULT FAIL, log contains 'does not exist'"
        status: pass
    human_judgment: false
  - id: D5
    description: "trace_lint.py passes cleanly on all four test files, and every assertion's description resolves to a real clause in migration/spec/tt.ticket_interface.md"
    requirement: "SPEC-03"
    verification:
      - kind: other
        ref: "python3 migration/spec/trace_lint.py migration/test/pgtap/tt__ticket_interface__{lifecycle,changes,selectinto}.sql migration/test/regress/sql/tt__ticket_interface__errors.sql -- OK on all 4 files, 51/58 clauses cited"
        status: pass
    human_judgment: false

duration: 95min
completed: 2026-07-13
status: complete
---

# Phase 2 Plan 8: TT.TICKET_INTERFACE RED test suite Summary

**Four RED pgTAP/expected-output test files for TT.TICKET_INTERFACE (38 routines, 129 pgTAP assertions + 1 regress case) written entirely from the Oracle-derived spec before any translation exists, proving the spec-first method holds at the pilot's largest scale.**

## Performance

- **Duration:** ~95 min
- **Started:** 2026-07-13
- **Completed:** 2026-07-13
- **Tasks:** 3
- **Files modified:** 5 (4 new test files + this SUMMARY)

## Accomplishments

- `tt__ticket_interface__lifecycle.sql` (39 assertions): the 11 ticket-lifecycle routines — `newticket_new`, `change_deferral_date`, `change_status`/`change_status_event_id_out`, `update_ux_timeout_for_ticket`, `expire_status`, `updateTicketFlow`, `trigger_escalation`, `merge_tickets`, `deleteTicket`, `get_next_recent_ticket` — including a "both halves" cascade/non-cascade proof for `merge_tickets` and `deleteTicket` (what survives AND what is removed).
- `tt__ticket_interface__changes.sql` (70 assertions): the remaining 27 routines, with the `change_label` overload pair dispatched and asserted distinctly, and both genuine `''`-vs-NULL Pitfall-2 pairs (`change_customer_reference`, `change_partner_reference`) asserted with paired empty-string/NULL calls.
- `tt__ticket_interface__selectinto.sql` (20 assertions): 19 SELECT INTO sites not already exercised elsewhere, including the package's one `TOO_MANY_ROWS` hazard (site #2, `mss.host2service`) and several sites only reachable via deliberately orphaned (deferred-FK) fixture data.
- `tt__ticket_interface__errors.sql` + golden `.out`: exact SQLSTATE/error-text pinning for two STRICT-unhandled sites, plus a WHEN OTHERS swallow-vs-reraise demonstration (`trigger_escalation`) with a plog-stub assertion taken without forcing a rollback.
- Full 77-site SELECT INTO reachability ledger (below) — the honest Phase 4 input the plan calls for.
- Verified RED end-to-end: `run-tests.sh --package tt.ticket_interface` exits non-zero; 0/129 pgTAP and 0/1 regress pass; log contains "does not exist".

## Task Commits

1. **Task 1: Ticket lifecycle — creation, status, deletion, merge** - `492a844` (test)
2. **Task 2: The change_* family, the overload pair, and empty-string vs NULL** - `d05b1ee` (test)
3. **Task 3: SELECT INTO strictness, exception paths, and the RED proof** - `cb87992` (pgTAP selectinto) + `07268db` (regress errors + full-package RED proof)

**Plan metadata:** (this commit, docs: complete plan)

## Files Created/Modified

- `migration/test/pgtap/tt__ticket_interface__lifecycle.sql` — 11 routines, 39 assertions
- `migration/test/pgtap/tt__ticket_interface__changes.sql` — 27 routines, 70 assertions, overload pair + Pitfall-2 pairs
- `migration/test/pgtap/tt__ticket_interface__selectinto.sql` — 19 additional SELECT INTO sites, 20 assertions
- `migration/test/regress/sql/tt__ticket_interface__errors.sql` — exception-text/SQLSTATE pinning + swallow demonstration
- `migration/test/regress/expected/tt__ticket_interface__errors.out` — golden authored from spec substance

## SELECT INTO Reachability Ledger (all 77 sites)

Legend: **L**=lifecycle.sql, **C**=changes.sql, **S**=selectinto.sql, **no-STRICT**=aggregate/sequence pull, no test required, **shadowed**=zero-row case unreachable independently because an earlier site in the same call already fails for the identical bad id, **near-impossible**=the spec itself names this zero-row case as structurally near-impossible (the row was just written by the same call moments earlier) and it was not separately fixtured, **schema-blocked**=blocked by an actual DDL constraint discovered while building fixtures.

| # | Line | Site | Clause | Status |
|---|------|------|--------|--------|
| 1 | 86 | mss.host by id (newticket_new) | S-TICKET-001 | L (bad host_id, throws_ok) |
| 2 | 89 | mss.host2service by host_id, TOO_MANY_ROWS | S-TICKET-001 | S (2-service host, throws_ok P0003) |
| 3 | 98 | stop.contact by id | S-TICKET-002 | L (bad contact_id, throws_ok) |
| 4 | 108 | admin-permission COUNT | S-TICKET-003 | no-STRICT, not required |
| 5 | 125 | tt.event_type by id | S-TICKET-003 | L (bad event_type_id, throws_ok) |
| 6 | 133 | stop.contact by worker_id | S-TICKET-004 | L (bad worker_id, throws_ok) |
| 7-9 | 141,142,254 | sequence NEXTVALs | S-TICKET-005 | no-STRICT, not required |
| 10 | 289 | tt.ticket (change_deferral_date) | S-TICKET-006 | L (bad ticket_id, throws_ok) |
| 11 | 295 | tt.ticket re-query, conditional status=60 | S-TICKET-006 | near-impossible (same ticket re-queried moments after site #10 already validated it; not independently fixturable) |
| 12 | 381 | tt.ticket 8-col (change_status_event_id_out) | S-TICKET-008 | L (bad ticket_id, throws_ok) |
| 13 | 389 | tt.event, conditional last_public_event_id | S-TICKET-008 | S (orphaned last_public_event_id, throws_ok) |
| 14 | 416 | status by NEW p_status_id | S-TICKET-009 | S (bad new status id, throws_ok) |
| 15 | 417 | status by CURRENT status_id | S-TICKET-009 | S (orphaned current status_id, throws_ok) |
| 16 | 435 | tt.ticket, dead variable | S-TICKET-009 | shadowed by site #12 (same ticket lookup fails first for a bad id) |
| 17 | 549 | tt.event by just-inserted event_id | S-TICKET-010 | near-impossible (own just-inserted row; spec itself calls this structurally near-impossible) |
| 18 | 579 | tt.ticket 5-col (update_ux_timeout_for_ticket) | S-TICKET-011 | L (bad ticket_id, throws_ok) + errors.sql golden |
| 19 | 619 | service_window COUNT | S-TICKET-012 | no-STRICT, not required |
| 20 | 625 | service_window, ROWNUM=1 | S-TICKET-012 | S (single-row positive case only — **schema-blocked** for multi-row, see Decisions) |
| 21 | 675 | stop.contact by worker_id (change_worker) | S-TICKET-013 | C (bad worker_id, lives_ok, local handler) |
| 22 | 688 | join, old worker | S-TICKET-014 | C (unassigned ticket, lives_ok, local handler) |
| 23 | 715 | tt.ticket (change_worker, unguarded) | S-TICKET-014 | C (bad ticket_id, throws_ok) |
| 24 | 779 | tt.ticket (change_service_host, unguarded) | S-TICKET-015 | C (bad ticket_id, throws_ok) |
| 25-28 | 784,799,813,825 | 4 locally-guarded service/host label lookups | S-TICKET-016 | C (bad service/host ids together, lives_ok) |
| 29 | 873 | tt.ticket (change_subject) | S-TICKET-017 | C (bad ticket_id, throws_ok) |
| 30 | 877 | tt.ticket, old subject | S-TICKET-017 | shadowed by site #29 (same ticket, same failure) |
| 31 | 959 | tt.ticket (change_label 3/4-arg) | S-TICKET-020 | C (bad ticket_id, throws_ok) |
| 32 | 965 | label by old_label_id, conditional | S-TICKET-020 | S (orphaned label_id, throws_ok) |
| 33 | 972 | label by NEW p_label_id, conditional | S-TICKET-020 | S (bad new label id, throws_ok) |
| 34 | 1073 | stop.contact by p_owner_id (change_owner) | S-TICKET-023 | C (bad owner_id, throws_ok) |
| 35 | 1079 | stop.contact re-query, same p_owner_id | S-TICKET-023 | shadowed by site #34 (same owner id, same failure) |
| 36 | 1086 | tt.ticket, ELSE branch | S-TICKET-023 | S (bad ticket_id, p_owner_id NULL, throws_ok) |
| 37 | 1135 | tt.ticket (change_company) | S-TICKET-024 | C (bad ticket_id, throws_ok) |
| 38 | 1138 | mss.host, conditional old_host_id | S-TICKET-024 | S (orphaned host_id on ticket, throws_ok) |
| 39 | 1144 | stop.company, conditional old_company_id | S-TICKET-024 | S (orphaned company_id on ticket, throws_ok) |
| 40 | 1157 | stop.company by p_company_id, local handler | S-TICKET-024 | C (bad company_id, lives_ok) |
| 41 | 1302 | tt.ticket (change_summary) | S-TICKET-028 | C (bad ticket_id, throws_ok) |
| 42 | 1355 | tt.ticket (change_type) | S-TICKET-030 | C (bad ticket_id, throws_ok) |
| 43 | 1358 | join, OLD type name | S-TICKET-030 | S (valid ticket, orphaned type_id — genuinely constructible despite spec calling it "structurally near-impossible", throws_ok) |
| 44 | 1361 | ticket_type by NEW p_type_id | S-TICKET-030 | S (bad new type_id, throws_ok) |
| 45 | 1372 | event_sequence CurrVal | S-TICKET-031 | no-STRICT; implicitly exercised (non-NULL OUT assertion) in C |
| 46 | 1397 | tt.ticket (change_service_component, unguarded) | S-TICKET-032 | C (bad ticket_id, throws_ok) |
| 47-48 | 1401,1402 | OLD component lookup, local handler | S-TICKET-032 | C (ticket with no service_component_id set, implicit coverage via the site #46 test's ticket fixture) |
| 49-50 | 1410,1411 | NEW component lookup, local handler | S-TICKET-032 | C (bad new service_component_id, lives_ok) |
| 51 | 1428 | event_sequence CurrVal | S-TICKET-031 | no-STRICT, not required |
| 52 | 1449 | MIN aggregate (get_next_recent_ticket) | S-TICKET-033 | L (lives_ok, whole-function catch-all) |
| 53 | 1498 | tt.ticket source (merge_tickets) | S-TICKET-034 | L (bad source ticket, throws_ok) |
| 54 | 1504 | tt.event, conditional source last_public_event_id | S-TICKET-034 | S (orphaned event id on source, throws_ok) |
| 55 | 1508 | tt.ticket target | S-TICKET-034 | L (bad target ticket, throws_ok) |
| 56 | 1514 | tt.event, conditional target last_public_event_id | S-TICKET-034 | S (orphaned event id on target, throws_ok) |
| 57 | 1697 | event_sequence CurrVal (add_status_change_event) | S-TICKET-053 | no-STRICT; implicitly exercised via C's change_emergency/change_customer_reference/etc. calls |
| 58 | 1754 | ticketrating_seq NextVal (rate_ticket) | S-TICKET-039 | no-STRICT, implicitly exercised in C |
| 59 | 1795 | ticketdocspage_seq NextVal (add_docs_page) | S-TICKET-040 | no-STRICT, implicitly exercised in C |
| 60 | 1830 | ticket_docs_page by id (remove_docs_page) | S-TICKET-041 | C (bad id, lives_ok, 2-arm handler) |
| 61 | 1875 | tt.ticket (handleDeferredTransitions) | S-TICKET-054 | S (transition into deferred, lives_ok — the branch neither L nor C otherwise exercises) |
| 62 | 1936 | tt.ticket COUNT (add_related_ticket) | S-TICKET-042 | no-STRICT, implicitly exercised in C |
| 63 | 1970 | ticket2related_ticket COUNT | S-TICKET-043 | no-STRICT, implicitly exercised in C |
| 64 | 2007 | 3-way join, same-company guard (add_related_file) | S-TICKET-044 | C (cross-company mismatch, lives_ok + plog check) |
| 65 | 2046 | ticket2mc_file COUNT | S-TICKET-045 | no-STRICT, implicitly exercised in C |
| 66 | 2051 | mc_file by id, conditional | S-TICKET-045 | S (orphaned mc_file_id via deferred FK, lives_ok, whole-routine catch-all) |
| 67 | 2105 | ticket_request_classification COUNT | S-TICKET-047 | no-STRICT, implicitly exercised in C |
| 68 | 2149 | tt.ticket, conditional p_add_history_event=1 (clear_todo_list) | S-TICKET-048 | C (bad ticket_id, default arg, throws_ok) + errors.sql golden |
| 69 | 2193 | todoitem_seq NextVal | S-TICKET-049 | no-STRICT, implicitly exercised in C |
| 70 | 2244 | todo_item LEFT JOIN (update_todo_item_status) | S-TICKET-050 | C (bad seq_no, throws_ok) |
| 71 | 2256 | tt.ticket, SECOND lookup | S-TICKET-050 | S (valid todo_item, orphaned ticket_id via deferred FK — otherwise shadowed by site #70, throws_ok) |
| 72 | 2261 | todo_item_status by NEW id | S-TICKET-050 | S (bad new status id, throws_ok) |
| 73 | 2330 | ticket_time_statistic by ticket_id, first-write | S-TICKET-055 | S (transition into status 11, lives_ok + row-created assertion) |
| 74 | 2335 | tickettimestatistic_seq NextVal, inside handler | S-TICKET-055 | no-STRICT, implicit within site #73's test |
| 75 | 2343 | re-SELECT after MERGE | S-TICKET-055 | implicit within site #73's test (structurally near-impossible zero-row) |
| 76 | 2381 | ticket_flow, open entry (updateTicketFlow) | S-TICKET-051 | L (no open entry, lives_ok, local handler — this IS the zero-row case) |
| 77 | 2391 | tt.ticket (updateTicketFlow, unguarded) | S-TICKET-051 | L (bad ticket_id, throws_ok) |

**Tally:** 77 sites total. 15 no-STRICT (aggregate/sequence, not required, several still exercised implicitly). 4 shadowed (sites #11 near-impossible; #16, #30, #35 shadowed by an earlier site in the same call). 1 near-impossible (#17). 1 schema-blocked for its multi-row half (#20, single-row half covered). The remaining 56 STRICT sites each have an independent, dedicated zero-row (or multi-row, for #2) assertion across the three pgTAP files.

## Decisions Made

- **change_label overload proof, not just double-calling.** `changes.sql` asserts the 2-arg call writes NO audit event and the 3/4-arg call writes exactly one — the only way a dropped overload during translation could be caught, since both flatten to the same PostgreSQL function name.
- **Only 2 of 3 Checklist-1 findings get paired empty-string/NULL assertions**, matching the spec's own conclusion (`change_notification` is already correctly handled; every other site was reviewed and found not `''`-collapsing-relevant) — inventing extra pairs would test behavior the spec never claimed existed.
- **Site #20's multi-row case is genuinely unconstructible** given `ddl/migrated`'s `tt.service_window` unique(ticket_id) index — a real schema-vs-spec-assumption tension flagged here (not silently routed around) for whoever plans the ROWNUM=1→LIMIT-1 translation to weigh: in THIS schema the hazard the spec worried about cannot occur, though the translation should still defensively use `LIMIT 1`.
- **The errors.sql golden is authored from spec substance**, not observed output, per the established 02-04 convention — verified by hand-diffing actual (today's "does not exist") against golden ("no data found" + successful swallow + plog count 1), confirming the mismatch is exactly the expected RED signal.

## Deviations from Plan

None — plan executed as written. Three implementation bugs were caught and fixed DURING test authoring, before committing (Rule 1 — auto-fix bugs in the test files themselves, not in any translated code, since none exists):

**1. [Rule 1 - Bug] Scalar-subquery-with-multiple-columns errors in three `is()` assertions**
- **Found during:** Task 1 and Task 2, first bootstrap-and-run verification pass
- **Issue:** `(SELECT col1, col2 FROM t WHERE ...)` used directly as a scalar expression is invalid SQL (Postgres: "subquery must return only one column") and, when it occurs in a bare `is()` call (not wrapped by pgTAP's own exception trapping), aborts the entire transaction — killing every subsequent assertion in the file and desyncing the TAP plan count.
- **Fix:** Wrapped multi-column comparisons in `ROW(...)` inside the SELECT list (`SELECT ROW(a,b,c,d) FROM t`) compared against an explicitly-cast `ROW(...)::record` literal on the right-hand side.
- **Files modified:** `migration/test/pgtap/tt__ticket_interface__lifecycle.sql`, `migration/test/pgtap/tt__ticket_interface__changes.sql`
- **Verification:** Re-ran each suite to completion (39/39 and 70/70 tests executed, no fatal aborts) before committing.
- **Committed in:** `492a844`, `d05b1ee` (part of the same task commits — caught before first commit of each file)

**2. [Rule 1 - Bug] `is()` comparing `numeric`/`smallint` columns against untyped integer literals inside a `ROW(...)::record`**
- **Found during:** Task 2, second verification pass
- **Issue:** `ROW(906099989, NULL, NULL, NULL)::record` compared against a `ROW(numeric, numeric, ...)` left-hand side raised "cannot compare dissimilar column types numeric and integer at record column 1" — again an uncaught fatal error outside `is()`'s own trapping.
- **Fix:** Added explicit casts on every literal inside the `ROW(...)` (`906099989::numeric`, `0::smallint`, etc.) to match the target column types.
- **Files modified:** `migration/test/pgtap/tt__ticket_interface__changes.sql`
- **Verification:** Suite ran to completion (70/70), `Wstat: 0` (no fatal exit), confirmed via `pg_prove`.
- **Committed in:** `d05b1ee`

**3. [Rule 1 - Bug] False-positive trace_lint violation from prose matching the assertion-call regex**
- **Found during:** Task 3, first `trace_lint.py` run on `selectinto.sql`
- **Issue:** A comment reading "...a table whose PK is (host_id, service_id)..." was matched by `trace_lint.py`'s `is(` call-detection regex (`\bis\s*\(`), flagged as an `is()` assertion with no string-literal description.
- **Fix:** Reworded the comment to avoid the "is (" token sequence ("a table whose primary key spans both host_id and service_id").
- **Files modified:** `migration/test/pgtap/tt__ticket_interface__selectinto.sql`
- **Verification:** `trace_lint.py` reports `OK`.
- **Committed in:** `cb87992`

---

**Total deviations:** 3 auto-fixed (all Rule 1, all confined to test-file SQL correctness — no translated code exists yet to have bugs in).
**Impact on plan:** None on scope; all three were mechanical SQL-correctness fixes caught by this plan's own verification loop before any commit, exactly as the harness is supposed to work.

## Issues Encountered

None beyond the three deviations above, all resolved within the plan's own verification loop.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- All four TICKET_INTERFACE test files are committed, trace_lint-clean, and demonstrably RED (`run-tests.sh --package tt.ticket_interface` exits non-zero; 129 pgTAP + 1 regress assertion all fail against "does not exist").
- Every one of the 38 public routines (37 name-deduped) has at least one citing test; both `change_label` overloads are proven dispatched distinctly.
- The 77-site reachability ledger above is ready as a direct Phase 4/5 input, including the one genuine schema-vs-spec tension (site #20's multi-row case) that whoever plans the `TT.TICKET_INTERFACE` translation (plan 02-12) should weigh explicitly.
- `provenance_lint.sh` can now assert (once the translation lands in 02-12) that these test-add commits (`492a844`, `d05b1ee`, `cb87992`, `07268db`) precede the translation-add commit in git history, per this plan's core discipline (the_one_rule).
- No blockers for 02-11 (`TT.EVENT_INTERFACE` translation) or 02-12 (`TT.TICKET_INTERFACE` translation, the cycle-group landing wave) from this plan.

## Self-Check: PASSED

- FOUND: migration/test/pgtap/tt__ticket_interface__lifecycle.sql
- FOUND: migration/test/pgtap/tt__ticket_interface__changes.sql
- FOUND: migration/test/pgtap/tt__ticket_interface__selectinto.sql
- FOUND: migration/test/regress/sql/tt__ticket_interface__errors.sql
- FOUND: migration/test/regress/expected/tt__ticket_interface__errors.out
- FOUND commit 492a844
- FOUND commit d05b1ee
- FOUND commit cb87992
- FOUND commit 07268db

---
*Phase: 02-spec-method-test-harness-pilot*
*Completed: 2026-07-13*
