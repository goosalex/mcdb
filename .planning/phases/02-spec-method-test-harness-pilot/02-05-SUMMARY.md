---
phase: 02-spec-method-test-harness-pilot
plan: 05
subsystem: database
tags: [oracle-to-postgres, spec-first, pgtap, plpgsql, oracle-plsql, test-harness, select-into, too-many-rows]

# Dependency graph
requires:
  - phase: 02-spec-method-test-harness-pilot
    provides: "migration/spec/ TEMPLATE.md/CHECKLIST.md/README.md + spec_lint.py/trace_lint.py (02-02); migration/test/ dual harness + mcdb_tmpl template + plog stub (02-01, 02-03); tt.util.md's spec shape as the sibling model (02-04)"
provides:
  - "migration/spec/tt.osag_notify.md -- 37 clauses, all 30 SELECT INTO sites individually enumerated with STRICT verdicts, the pilot's one TOO_MANY_ROWS handler found and specced, all 11 WHEN OTHERS handlers confirmed to swallow (none re-raises), 3 genuine Pitfall-2 ('' vs NULL) hazards found, private-routine naming convention declared"
  - "3 RED test files (2 pgTAP + 1 expected-output) covering 13 distinct spec clauses, verified failing specifically because no translation exists yet"
affects: ["02-09/02-10 (or whichever later plan translates this + the 4 pilot packages)", "phase 3 XCUT-01 (exception mapping)", "phase 4 bulk translation -- the SELECT INTO strictness table format is the reusable template for the remaining 44 packages", "phase 4 name-map generator (private-routine naming convention)"]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "SELECT INTO strictness table format (one row per site: line, target, zero/multi-row possibility grounded in actual PK/FK schema evidence, Oracle handler, PG translation verdict, clause ID) -- proposed as the corpus-wide template for Phase 4's remaining 44 packages"
    - "Private-routine naming convention: double-underscore marker prefix (tt.osag_notify__<name>), REVOKE ALL FROM PUBLIC -- a NEW rule living outside migration/mapping/name-map.csv, flagged for Phase 4/name-map-generator reconciliation"
    - "Testing a package's private routines directly by their own declared (REVOKE'd) name, bypassing the public entry point, when the public entry point's own top-level exception handler would otherwise swallow the very behavior under test -- see the TOO_MANY_ROWS triple test"
    - "Distinguishing a swallowed TOO_MANY_ROWS from a swallowed NO_DATA_FOUND via plog log CONTENT (not just a boolean 'it logged something'), when both arms return the same NULL to the caller -- the only way to prove a naive translation didn't drop the TOO_MANY_ROWS arm entirely"
    - "network_id left explicit NULL in mss.interface fixture rows: its DEFAULT of 1 does not resolve to a real mss.network row in mcdb_tmpl -- a genuine ora2pg/masterdata schema gap, worked around rather than papered over by inventing a network row"

key-files:
  created:
    - migration/spec/tt.osag_notify.md
    - migration/test/pgtap/tt__osag_notify__spec.sql
    - migration/test/pgtap/tt__osag_notify__selectinto.sql
    - migration/test/regress/sql/tt__osag_notify__errors.sql
    - migration/test/regress/expected/tt__osag_notify__errors.out

key-decisions:
  - "Private-routine naming convention: (a) double-underscore marker prefix (tt.osag_notify__send_notification_by_type, etc.) with REVOKE ALL ... FROM PUBLIC, per the plan's own recommendation. This is a NEW rule outside name-map.csv's SSOT -- flagged loudly in Assumptions/Unresolved and here for Phase 4 to fold back into the name-map generator, or explicitly reject in favor of an alternative."
  - "No test in this suite can observe TOO_MANY_ROWS (or, for that matter, most NO_DATA_FOUND sites) as a caller-visible raised exception, because BOTH structurally-reachable TOO_MANY_ROWS sites in this package (site #9's escalation to event_notify's outer WHEN OTHERS, and site #22's own local WHEN TOO_MANY_ROWS handler) are, per the Oracle source itself, swallowed one way or another. Tests therefore assert on return value / plog content / post-condition state rather than on a raised exception -- an honest reflection of the package's actual all-swallowing contract, not a coverage gap."
  - "Chose to test the private routines get_isp_link_id_for_host_id and send_notification_by_type DIRECTLY, by the double-underscore name the naming-convention decision assigns them, rather than only indirectly through the 6 public routines. This was necessary because event_notify's own top-level WHEN OTHERS would otherwise make it structurally impossible to observe the TOO_MANY_ROWS-vs-NO_DATA_FOUND distinction at site #22 at all (both arms are equally invisible to event_notify's caller)."

requirements-completed: [SPEC-02, SPEC-03, HARN-05]

coverage:
  - id: D1
    description: "TT.OSAG_NOTIFY spec: 6 public + 13 private routines documented, 37 clauses, all 5 checklist dimensions answered with real Oracle-source citations grounded in ddl/generated/schema.oracle.sql PK/FK evidence, non-empty Assumptions section"
    requirement: "SPEC-02"
    verification:
      - kind: unit
        ref: "python3 migration/spec/spec_lint.py migration/spec/tt.osag_notify.md -> OK"
        status: pass
    human_judgment: false
  - id: D2
    description: "All 30 SELECT INTO sites from inventory.json's select_into_sites array for TT.OSAG_NOTIFY are individually cited and verdicted in the spec's SELECT INTO strictness table; the pilot's one TOO_MANY_ROWS handler (site #22) is found and specced"
    requirement: "SPEC-02"
    verification:
      - kind: unit
        ref: "programmatic diff of migration/spec/tt.osag_notify.md's cited lines against inventory.json's select_into_sites for TT.OSAG_NOTIFY -> ALL_30_SELECT_INTO_SITES_SPECCED; grep -qiE TOO_MANY_ROWS -> TMR_SPECCED"
        status: pass
    human_judgment: false
  - id: D3
    description: "3 test files (2 pgTAP + 1 expected-output) covering 13 distinct spec clause IDs, every assertion citing a resolvable clause ID, including >=5 throws_ok zero-row/exception assertions across 5 distinct SELECT INTO sites and a zero/one/many-row triple on the TOO_MANY_ROWS site"
    requirement: "HARN-05"
    verification:
      - kind: unit
        ref: "python3 migration/spec/trace_lint.py <all 3 files> -> 3 test file(s) OK; grep -cE throws_ok tt__osag_notify__selectinto.sql -> 6"
        status: pass
    human_judgment: false
  - id: D4
    description: "The suites RUN and FAIL specifically because the translated functions/procedures do not exist yet (RED), proven against a freshly-bootstrapped mcdb_test_p05 clone with the plog stub loaded and no translation installed, and the fixture rows themselves execute cleanly (no schema/constraint errors masking the intended RED signal)"
    requirement: "HARN-05"
    verification:
      - kind: integration
        ref: "bash migration/test/run-tests.sh --db mcdb_test_p05 -> exit non-zero; TOTAL: 5 packages, 1 pass (_canary only), 4 fail; tt.osag_notify's own failures are all SQLSTATE 42883 (does not exist), matching the auth/dbprop/util baseline"
        status: pass
    human_judgment: false

duration: ~2h
completed: 2026-07-13
status: complete
---

# Phase 2 Plan 5: Spec + RED Tests for TT.OSAG_NOTIFY Summary

**Derived a 37-clause Oracle-source spec for TT.OSAG_NOTIFY -- the pilot's SELECT INTO proving ground, all 30 sites individually enumerated and verdicted against real PK/FK schema evidence, the pilot's one TOO_MANY_ROWS handler found and specced, all 11 WHEN OTHERS handlers confirmed to swallow -- and wrote 3 RED pgTAP/expected-output test files (13 clause citations, 6 throws_ok zero-row assertions across 5 distinct sites, and a zero/one/many-row triple proving the TOO_MANY_ROWS arm specifically) verified failing for the right reason against a live PostgreSQL 17.10 instance.**

## Performance

- **Duration:** ~2h (1844-line body read and traced in full, cross-referenced against `ddl/generated/schema.oracle.sql`'s actual PK/FK constraints to ground every zero-row/multi-row verdict in real schema evidence rather than assumption)
- **Tasks:** 3/3
- **Files modified:** 5 created (1 spec, 2 pgTAP suites, 1 regress SQL script, 1 regress golden file)

## Accomplishments

- `migration/spec/tt.osag_notify.md` -- 6 public + 13 private routines documented, 37 clauses (`S-NOTIFY-001..037`). Every one of the 30 `SELECT ... INTO` sites in the Phase 1 inventory is individually enumerated in a `### SELECT INTO strictness` table with line, target, zero/multi-row possibility, Oracle handler, and PG translation verdict -- and every possibility/impossibility claim is grounded in the ACTUAL primary/foreign key constraints from `ddl/generated/schema.oracle.sql`, not assumed. This surfaced two non-obvious `TOO_MANY_ROWS` reachability findings the source code itself doesn't call out explicitly: (1) `mss.host2service`'s primary key `(host_id, service_id)` means the package's very first big join (site #2) can return more than one row; (2) `tt.event_type2event_type_group`'s primary key `(group_id, event_type_id)` means site #9's event-type-group lookup can too -- and its local handler catches `NO_DATA_FOUND` only, NOT `TOO_MANY_ROWS`, so that specific exception silently escalates one level further to `event_notify`'s own outer handler.
- **The pilot's one and only `TOO_MANY_ROWS` handler, found and specced (S-NOTIFY-031, `get_isp_link_id_for_host_id`, line 1507).** Traced to two independent structural causes in the schema: `mss.interface` has no uniqueness constraint on `host_id` (a host can have >1 mgmt-access interface), and `mss.interface2isp_link`'s primary key `(interface_id, isp_link_id)` means one interface can map to >1 ISP link. Oracle's handler swallows all three arms (`NO_DATA_FOUND`, `TOO_MANY_ROWS`, `OTHERS`) to `NULL` -- it never raises.
- **All 11 `WHEN OTHERS` handlers in this 1844-line package confirmed to swallow -- zero re-raises, zero `RAISE_APPLICATION_ERROR` calls anywhere.** This is a genuinely different profile from `AUTH.OSAG_AUTH`'s handler (which re-raises after logging, per `02-04-SUMMARY.md`) -- `TT.OSAG_NOTIFY`'s whole design contract is "a notification failure must never break the caller's ticket-update transaction," and `event_notify`'s own top-level handler means NO internal `SELECT INTO` failure, however deep, is ever caller-visible from the package's flagship public routine.
- **3 genuine Pitfall-2 (`''` vs `NULL` collapsing) hazards found**, none previously flagged: `format_customer_reference`'s `IS NULL` check on a caller-supplied string (the clearest case -- `tt.ticket.customer_reference` has no constraint forbidding `''`); `delete_ticket_notifications`' NULL-seeded string accumulator, where Oracle's `NULL || 'x' = 'x'` masks a bug that PL/pgSQL's `NULL || 'x' = NULL` would expose (both the accumulation itself AND the suffix-append site); and the `NVL(contact.lastname, '') ... IS NULL` round-trip in both ISP-message composers, where `orafce`'s `NVL` returns a real non-NULL `''` that a later `IS NULL` check would then miss.
- **Private-routine naming convention declared**: double-underscore marker prefix (`tt.osag_notify__<name>`, e.g. `tt.osag_notify__get_isp_link_id_for_host_id`), `REVOKE ALL ... FROM PUBLIC`, per the plan's own recommendation -- flagged in the spec's Assumptions section and here as a NEW rule living outside `name-map.csv`'s SSOT, to be folded back into the name-map generator (or explicitly rejected) in Phase 4.
- 3 RED test files, 13 distinct spec clause IDs cited: `tt__osag_notify__spec.sql` (9 assertions, 6 clauses -- public contract: `event_notify`'s swallow-all handler + plog observability, `add_notification_event`'s public/private routing, `is_notify_suppressor_active`'s aggregate-site safety, `delete_notifications_for_login`'s empty-loop no-op, `delete_ticket_notifications`' own swallow of an internal unhandled `NO_DATA_FOUND`), `tt__osag_notify__selectinto.sql` (14 planned assertions, 7 clauses -- 6 `throws_ok` zero-row propagation assertions across 5 distinct sites #10/#12/#13/#14-15/#16-17, a zero/one/many-row triple on the `TOO_MANY_ROWS` site #22 distinguished by return value AND plog log content, and the site #9 escalation-to-outer-handler behavior proven via a post-condition check that the rest of `event_notify` never ran), `tt__osag_notify__errors.sql`+`.out` (2 pinned SQLSTATE/text golden cases).
- Verified RED end-to-end against a freshly-bootstrapped `mcdb_test_p05` (template clone, plog stub loaded, no translation installed): `run-tests.sh` exits non-zero; only `_canary.canary` passes; all 4 pilot/dependency packages (`auth.osag_auth`, `mss.osag_dbprop`, `tt.osag_notify`, `tt.util`) report `FAIL`, and every one of `tt.osag_notify`'s own failures is specifically `SQLSTATE 42883` ("does not exist") -- proving the suite genuinely exercises the absent translation rather than failing for an unrelated (e.g. fixture/schema) reason.
- Caught and fixed a real fixture bug while first running the suite: two `tt.event_type` fixture rows omitted `sms_message_template_id`/`email_message_template_id`, which ARE `NOT NULL` in the migrated PG schema (ora2pg carried Oracle's `NOT NULL` through correctly) -- the INSERT itself aborted before the test could ever reach its intended RED signal. Fixed by supplying real existing template ids (1, 2) from `tt.event_type_message`; re-verified both files now fail for the intended reason.

## Task Commits

Each task was committed atomically, with an additional fixture-bugfix commit per the "commit-or-lose-it" instruction:

1. **Task 1 + Task 2: Spec TT.OSAG_NOTIFY, including the full SELECT INTO strictness table**
   - `dad32b4` (docs) -- TT.OSAG_NOTIFY spec: 37 clauses, all 30 SELECT INTO sites, the pilot's one TOO_MANY_ROWS handler, all 11 WHEN OTHERS handlers characterized, 3 Pitfall-2 hazards, private-routine naming convention
2. **Task 3: Tests -- cited to clauses, and RED**
   - `f4fe690` (test) -- pgTAP spec + selectinto suites, expected-output errors suite + golden
   - `6a63a75` (fix) -- corrected NOT NULL fixture bug in two `tt.event_type` inserts, re-verified RED for the right reason

**Plan metadata:** (this commit, made after this SUMMARY)

## Files Created/Modified
- `migration/spec/tt.osag_notify.md` -- spec, 37 clauses (`S-NOTIFY-001..037`)
- `migration/test/pgtap/tt__osag_notify__spec.sql` -- 9 assertions, public-contract fixture (ticket/event/login/event_notification)
- `migration/test/pgtap/tt__osag_notify__selectinto.sql` -- 14 planned assertions, the SELECT INTO strictness suite including the ISP-link zero/one/many-row fixture chain (stop.company/mss.host/mss.interface/mss.isp_link/mss.interface2isp_link)
- `migration/test/regress/sql/tt__osag_notify__errors.sql` + `expected/tt__osag_notify__errors.out` -- pinned error-text golden for `send_test_notification`'s unhandled NO_DATA_FOUND and `add_notification_event`'s bare NOT NULL violation

## Decisions Made

- **Private-routine naming convention: double-underscore marker prefix, option (a) from the plan.** Thirteen private routines is too many to inline into their six callers without destroying readability, and this exact "public package interface hiding a private implementation namespace" situation recurs in essentially every one of the remaining 44 packages Phase 4 will translate. This is offered as the corpus-wide default but is explicitly NOT authorized to be final by this spec alone -- it lives outside `migration/mapping/name-map.csv`, exactly the kind of invented-name drift `migration/README.md`'s consumer contract warns against. **Flagged here loudly, again, as a Phase 4 (and possibly name-map-generator) decision.**
- **Testing private routines directly, by their declared (soon-to-be-`REVOKE`d) name, when the public entry point's own exception handling would make the behavior otherwise unobservable.** `event_notify`'s top-level `WHEN OTHERS` swallows everything reachable through it, including both `TOO_MANY_ROWS` sites (#9 indirectly, #22 directly). Testing `get_isp_link_id_for_host_id` and `send_notification_by_type` directly by their own convention-assigned names was the only way to distinguish "zero rows, silently NULL" from "too many rows, NULL + a specific log message" from "exactly one row, real value" -- proving all three arms exist and none was collapsed into a bare STRICT. As superuser (or the eventual functions' owner), `REVOKE ALL ... FROM PUBLIC` does not block a test suite that calls the function directly by name; it only blocks unprivileged application roles, which is the whole point of marking it private.
- **No test in this suite asserts `TOO_MANY_ROWS` (or most `NO_DATA_FOUND` sites) as a raised, caller-visible exception**, because the Oracle source itself never lets that happen at the two sites where `TOO_MANY_ROWS` is structurally reachable. This is recorded as a decision, not a gap: a test asserting `throws_ok` for `TOO_MANY_ROWS` anywhere in this package would be asserting behavior Oracle itself never exhibited, which would poison Phase 4's translation exactly the way a guessed spec clause would.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixture `tt.event_type` inserts omitted NOT NULL columns**
- **Found during:** Task 3, first live-database run of the RED verification
- **Issue:** Both `tt__osag_notify__spec.sql` and `tt__osag_notify__selectinto.sql` inserted `tt.event_type` fixture rows with only `(id, name, source)`, omitting `sms_message_template_id`/`email_message_template_id` -- both `NOT NULL` in the migrated PG schema (`ddl/migrated/tables/tables.pg.sql`, matching Oracle's own `NOT NULL` on those columns). The INSERT itself raised `23502 not_null_violation`, aborting the fixture setup before the intended "function does not exist" signal could ever be reached -- a RED-for-the-wrong-reason failure mode.
- **Fix:** Supplied real, existing `tt.event_type_message` ids (1, 2, already present via masterdata) for both fixture rows.
- **Files modified:** `migration/test/pgtap/tt__osag_notify__spec.sql`, `migration/test/pgtap/tt__osag_notify__selectinto.sql`
- **Verification:** Full `bootstrap.sh` + `osag_plog.sql` + `run-tests.sh --db mcdb_test_p05` cycle re-run; every remaining failure in both files is `SQLSTATE 42883` (does not exist), matching the established RED baseline.
- **Committed in:** `6a63a75`

---

**Total deviations:** 1 auto-fixed (Rule 1, test-fixture-only, zero spec-file changes required)
**Impact on plan:** The deviation was caught and fixed within this plan's own verification loop before any commit claimed RED was proven; no scope creep, no changes to shared harness files.

## Issues Encountered

- **A handful of bare `is()`/`SELECT` assertions in `tt__osag_notify__selectinto.sql` (the zero/one/many-row triple on `get_isp_link_id_for_host_id`, and `tt__osag_notify__spec.sql`'s `is_notify_suppressor_active`/`event_notify` calls) abort their WHOLE wrapping transaction on the first "function does not exist" error today, rather than failing all planned assertions individually** -- the exact same pattern `02-04-SUMMARY.md` already documented for `mss__osag_dbprop__spec.sql`'s bare `is()`. This is a RED-phase-only cosmetic limitation: `pg_prove` reports fewer "Tests=N" than planned and a "Bad plan" parse warning, but the log clearly shows the underlying `42883 does not exist` error, `run-tests.sh`'s overall non-zero exit is unaffected, and once a real translation exists (making these functions callable), each `is()`/comparison will simply evaluate normally without aborting anything. Left as an honest, documented observation rather than reworked, per the same reasoning 02-04 gave.
- **`mss.interface.network_id`'s schema `DEFAULT 1` does not resolve to a real `mss.network` row anywhere in `mcdb_tmpl`** (0 rows in `mss.network` for id 1, confirmed live). This is a genuine ora2pg/masterdata completeness gap (the FK is `DEFERRABLE`, so it would only bite at `COMMIT`, which this pgTAP transaction never reaches) -- worked around by leaving `network_id` explicit `NULL` in the fixture (the column is nullable despite the unusable default), rather than fabricating a `mss.network` row that isn't this plan's concern. Flagged here for whichever later plan builds out `mss.network` masterdata/schema-fix coverage (in the spirit of `migration/test/SCHEMA-FIXES.md`).

## User Setup Required

None -- no external service configuration required.

## Next Phase Readiness

- `migration/spec/tt.osag_notify.md` is `spec_lint`-clean, all 30 SELECT INTO sites individually verdicted with real schema-grounded evidence, and ready to be consumed as the authoritative input for whichever plan performs `TT.OSAG_NOTIFY`'s PL/pgSQL translation. It is a load-bearing input to that translation AND to Phase 3/4 for two reasons beyond its own package: (1) the SELECT INTO strictness table format is proposed as the reusable template for the remaining 44 packages; (2) the private-routine naming convention needs an explicit Phase 4 (or name-map-generator) decision before the corpus-wide translation begins, since every package with private helpers will hit this same question.
- Known, explicitly-flagged gaps for the translation plan to inherit: (1) the private-routine naming convention is NOT finalized, only proposed; (2) `mss.network`'s masterdata is empty in `mcdb_tmpl`, a real completeness gap unrelated to this package but discovered while fixturing it; (3) the exact PostgreSQL sequence-call syntax for `event_sequence.NextVal` (S-NOTIFY-015) is a corpus-wide mechanic this package-specific spec flags but does not settle.
- Every one of the 3 Pitfall-2 (`''`/NULL) hazards found here (`format_customer_reference`, `delete_ticket_notifications`' accumulator, the `NVL(...,'') -> IS NULL` round-trip) is a concrete, load-bearing correctness requirement for whichever plan translates this package -- a bare 1:1 port of any of the three lines identified will silently misbehave.

---
*Phase: 02-spec-method-test-harness-pilot*
*Completed: 2026-07-13*

## Self-Check: PASSED

All 5 created files confirmed present on disk; all 3 task/fix commit hashes (`dad32b4`, `f4fe690`, `6a63a75`) confirmed present in git history.
