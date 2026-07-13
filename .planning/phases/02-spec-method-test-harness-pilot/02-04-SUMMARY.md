---
phase: 02-spec-method-test-harness-pilot
plan: 04
subsystem: database
tags: [oracle-to-postgres, spec-first, pgtap, plpgsql, oracle-plsql, test-harness]

# Dependency graph
requires:
  - phase: 02-spec-method-test-harness-pilot
    provides: "migration/spec/ TEMPLATE.md/CHECKLIST.md/README.md + spec_lint.py/trace_lint.py (02-02); migration/test/ dual harness + mcdb_tmpl template + plog stub (02-01, 02-03)"
provides:
  - "migration/spec/mss.osag_dbprop.md — 9 clauses, all 5 checklist dimensions, empty-string/NULL boundary flagged"
  - "migration/spec/auth.osag_auth.md — 11 clauses, 6 SELECT INTO sites individually traced, unique-violation swallow documented as real business logic"
  - "migration/spec/tt.util.md — 15 clauses, the pilot's first COMMIT/PRAGMA AUTONOMOUS_TRANSACTION collision, explicitly deferred to XCUT-04/XCUT-05"
  - "5 RED test files (3 pgTAP + 2 expected-output) covering 26 distinct spec clauses, verified failing specifically because no translation exists yet"
affects: ["02-09 (or whichever later plan translates these 3 packages)", "phase 3 XCUT-01/04/05", "phase 4 bulk translation of the TT cycle group"]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "SET CONSTRAINTS ALL DEFERRED at the top of a pgTAP transaction lets fixture rows use fake FK targets (mss.host, stop.contact, stop.company have no masterdata) without ever tripping the FK, since the transaction always ROLLBACKs before the deferred check would fire"
    - "pgTAP assertions on genuinely-missing functions must use throws_ok/throws_like/lives_ok (pgTAP-protected via internal savepoints) rather than a bare is() wrapping a direct call — a bare call's error aborts the WHOLE wrapping transaction, silently skipping every later assertion in that file (observed first-hand in mss__osag_dbprop__spec.sql, documented below, not fixed since it still correctly fails)"
    - "a 'value must remain unchanged' assertion after a possibly-failed CALL is a structural tautology when the value's initial and expected-final states are the same (e.g. NULL stays NULL) — it passes whether the call ran correctly OR silently failed to run at all; removed one such case in tt__util__spec.sql (T-02-13)"
    - "regress/sql/*.sql files are NOT wrapped in BEGIN/ROLLBACK by convention (unlike pgtap/*.sql) — this is what lets them exercise a top-level CALL to a COMMIT-bearing procedure, which is the whole reason this harness half exists"

key-files:
  created:
    - migration/spec/mss.osag_dbprop.md
    - migration/spec/auth.osag_auth.md
    - migration/spec/tt.util.md
    - migration/test/pgtap/mss__osag_dbprop__spec.sql
    - migration/test/pgtap/auth__osag_auth__spec.sql
    - migration/test/pgtap/tt__util__spec.sql
    - migration/test/regress/sql/mss__osag_dbprop__errors.sql
    - migration/test/regress/expected/mss__osag_dbprop__errors.out
    - migration/test/regress/sql/tt__util__txn.sql
    - migration/test/regress/expected/tt__util__txn.out

key-decisions:
  - "TT.UTIL's autonomous-transaction decision is NOT made here — the spec records Oracle's actual behavior (COMMIT survives caller rollback), states 3 candidate PostgreSQL translations, and explicitly hands the final call to Phase 3's XCUT-05 (transaction semantics) and XCUT-04 (pg_kind finalization)"
  - "mss.v_host_key_value (the real ora2pg view, backed by a materialized view) is not loaded in mcdb_tmpl since ddl/migrated/mviews/ is out of scope per 02-03-SUMMARY.md — the DBPROP pgTAP suite creates a transaction-scoped substitute view with the same 5-column shape, explicitly flagged as a test fixture, not a translation claim"
  - "Oracle's V\$INSTANCE (used by close_old_dev_tickets' dev-instance check) has no PostgreSQL equivalent at all — the regress test for it sets a placeholder custom GUC (mcdb.force_dev_instance) purely as a TEST-ONLY convenience, explicitly documented as not a spec claim and likely to need rewriting once XCUT-04/05 pick a real mechanism"
  - "golden .out files were authored from the spec's expected SUBSTANCE (the correct future behavior), not from today's actual output — today's actual output ('function/procedure does not exist') legitimately mismatches, and that mismatch IS the RED proof; CONTEXT-line internal details in both golden files are acknowledged placeholders pending reconciliation once a real translation exists to observe"

requirements-completed: [SPEC-02, SPEC-03, HARN-05]

coverage:
  - id: D1
    description: "MSS.OSAG_DBPROP spec: 3 public routines, 9 clauses, all 5 checklist dimensions answered with real Oracle-source citations, non-empty Assumptions section"
    requirement: "SPEC-02"
    verification:
      - kind: unit
        ref: "python3 migration/spec/spec_lint.py migration/spec/mss.osag_dbprop.md -> OK"
        status: pass
    human_judgment: false
  - id: D2
    description: "AUTH.OSAG_AUTH spec: 3 public routines, 11 clauses, all 6 SELECT INTO sites individually traced against the package's exception-handler structure"
    requirement: "SPEC-02"
    verification:
      - kind: unit
        ref: "python3 migration/spec/spec_lint.py migration/spec/auth.osag_auth.md -> OK"
        status: pass
    human_judgment: false
  - id: D3
    description: "TT.UTIL spec: 5 public routines, 15 clauses, the COMMIT/PRAGMA AUTONOMOUS_TRANSACTION collision documented with both COMMIT sites cited by line and the decision explicitly deferred to XCUT-04/XCUT-05"
    requirement: "SPEC-02"
    verification:
      - kind: unit
        ref: "python3 migration/spec/spec_lint.py migration/spec/tt.util.md -> OK; grep for 'autonomous', 'XCUT-0[45]', and 'ddl/src/pkgb/tt_util.sql:(234|244)' all match"
        status: pass
    human_judgment: false
  - id: D4
    description: "5 test files (3 pgTAP + 2 expected-output) covering 26 distinct spec clause IDs, every assertion citing a resolvable clause ID"
    requirement: "HARN-05"
    verification:
      - kind: unit
        ref: "python3 migration/spec/trace_lint.py <all 5 files> -> 5 test file(s) OK"
        status: pass
    human_judgment: false
  - id: D5
    description: "The suites RUN and FAIL specifically because the translated functions/procedures do not exist yet (RED), proven against a freshly-bootstrapped mcdb_test_p04 clone with the plog stub loaded and no translation installed"
    requirement: "HARN-05"
    verification:
      - kind: integration
        ref: "bash migration/test/run-tests.sh --db mcdb_test_p04 (no --install) -> exit non-zero, TOTAL: 4 packages, 1 pass (_canary only), 3 fail; log contains 'does not exist'"
        status: pass
    human_judgment: false

duration: ~2h
completed: 2026-07-13
status: complete
---

# Phase 2 Plan 4: Spec + RED Tests for MSS.OSAG_DBPROP, AUTH.OSAG_AUTH, TT.UTIL Summary

**Derived Oracle-source specs (35 clauses total across 3 packages) and wrote 5 RED pgTAP/expected-output test files (26 distinct clause citations) proving the spec-first method on the pilot's control group — including TT.UTIL's COMMIT/PRAGMA AUTONOMOUS_TRANSACTION collision, explicitly handed to Phase 3 rather than silently resolved.**

## Performance

- **Duration:** ~2h (heavy static-analysis phase: reading Oracle source, tracing call graphs by hand, and iteratively verifying RED against a live local PostgreSQL instance)
- **Tasks:** 3/3
- **Files modified:** 10 created (3 specs, 3 pgTAP suites, 2 regress SQL scripts, 2 regress golden files)

## Accomplishments

- `migration/spec/mss.osag_dbprop.md` — 3 routines, 9 clauses. Traced both `SELECT ... INTO` sites (one structurally safe via `DUAL`, one with an explicit `NO_DATA_FOUND` handler protected by a unique index), the two distinct exception paths (`-20801` vs. the un-pragma'd `e_abort`), and the Oracle `''`/`NULL` collapsing hazard for `get_string_by_host`'s property-name lookup (S-DBPROP-009) — the translation must add an explicit boundary normalization since PostgreSQL never collapses `''` into `NULL` the way Oracle does.
- `migration/spec/auth.osag_auth.md` — 3 routines, 11 clauses. All 6 `SELECT ... INTO` sites traced individually against the package's actual exception-handler structure, including one genuinely dead-code `WHEN NO_DATA_FOUND THEN NULL` handler (a cursor `FOR` loop can never raise it) and one deliberate exception-swallow (contact cleanup, S-AUTH-006) that must survive translation unchanged. `grant_user_role`'s `SQLCODE != -00001` unique-violation swallow is documented as real business logic (idempotent re-grant), not incidental error suppression.
- `migration/spec/tt.util.md` — 5 routines (+1 private helper documented for translation completeness), 15 clauses. This is the pilot's deliberate first FUNCTION-vs-PROCEDURE/COMMIT collision: `close_old_dev_tickets` carries `PRAGMA AUTONOMOUS_TRANSACTION` plus two per-iteration `COMMIT`s (cited by exact line, 234 and 244), and its dev-instance gate (`V$INSTANCE`) has zero PostgreSQL equivalent. Both current callers of `update_status_valid_until` were traced by hand into their enclosing routines and confirmed `PROCEDURE`, not `FUNCTION` — so no collision exists in today's static call graph, but the spec flags that this must be re-checked once XCUT-04 finalizes `pg_kind` for those callers too. The autonomous-transaction decision itself is explicitly deferred to XCUT-05, with three candidate PostgreSQL behaviors laid out and none chosen.
- 5 RED test files, 26 distinct spec clause IDs cited (well above the 15-clause density floor): `mss__osag_dbprop__spec.sql` (10 assertions, 6 clauses), `auth__osag_auth__spec.sql` (10 assertions, 7 clauses), `tt__util__spec.sql` (10 assertions, 9 clauses), `mss__osag_dbprop__errors.sql` (3 error-path statements, 2 clauses), `tt__util__txn.sql` (the top-level-CALL transaction-semantics test, 3 clauses).
- Verified RED end-to-end: `bash migration/test/run-tests.sh --db mcdb_test_p04` (fresh template clone, plog stub loaded, no translation installed) exits non-zero; only `_canary.canary` (the harness self-test) passes; all three pilot packages report `FAIL`, and the log is full of `does not exist`/`undefined` errors — proving these tests genuinely exercise the (absent) translation rather than asserting tautologies.
- Caught and fixed a real vacuous-pass tautology while writing `tt__util__spec.sql`: a "value stays NULL" check after a `CALL` that (today) silently dies would pass regardless of whether the call ran correctly — removed it in favor of the already-honest `lives_ok` assertion (documented inline in the test file, per T-02-13's own concern).

## Task Commits

Each task was committed atomically, with additional intra-task commits per the "commit-or-lose-it" instruction (this environment drops connections roughly every 15 minutes):

1. **Task 1: Specs for MSS.OSAG_DBPROP and AUTH.OSAG_AUTH**
   - `79ca321` (docs) — MSS.OSAG_DBPROP spec
   - `522b54f` (docs) — AUTH.OSAG_AUTH spec, completes Task 1
2. **Task 2: Spec for TT.UTIL — the first COMMIT/autonomous-transaction collision**
   - `e27e11a` (docs) — TT.UTIL spec, completes Task 2
3. **Task 3: Tests for all three — cited to clauses, and RED**
   - `f29a000` (test) — pgTAP suite for MSS.OSAG_DBPROP
   - `cb36fa5` (test) — pgTAP suite for AUTH.OSAG_AUTH
   - `85a60a3` (test) — pgTAP suite for TT.UTIL (includes the tautology fix)
   - `668cc35` (test) — expected-output suite for MSS.OSAG_DBPROP error paths
   - `d602230` (test) — expected-output suite for TT.UTIL transaction semantics

**Plan metadata:** (this commit, made after this SUMMARY)

## Files Created/Modified
- `migration/spec/mss.osag_dbprop.md` — spec, 9 clauses (`S-DBPROP-001..009`)
- `migration/spec/auth.osag_auth.md` — spec, 11 clauses (`S-AUTH-001..011`)
- `migration/spec/tt.util.md` — spec, 15 clauses (`S-UTIL-001..015`)
- `migration/test/pgtap/mss__osag_dbprop__spec.sql` — 10 assertions, transaction-scoped `mss.v_host_key_value` substitute view
- `migration/test/pgtap/auth__osag_auth__spec.sql` — 10 assertions, login/profile/user_permission fixture
- `migration/test/pgtap/tt__util__spec.sql` — 10 assertions, `pg_proc.prokind` existence checks + ticket-status business logic
- `migration/test/regress/sql/mss__osag_dbprop__errors.sql` + `expected/mss__osag_dbprop__errors.out` — pinned error-text golden for the unknown-property raise path
- `migration/test/regress/sql/tt__util__txn.sql` + `expected/tt__util__txn.out` — top-level `CALL` transaction-semantics test

## Decisions Made

- **`SET CONSTRAINTS ALL DEFERRED` as the fixture strategy for tables with no masterdata FK targets.** `mss.host`, `stop.contact`, and `stop.company` have zero masterdata rows (they're operational data, not reference data), but the FKs pointing at them from `mss.value`, `auth.login`, and `tt.ticket` are all `DEFERRABLE`. Since every pgTAP file always `ROLLBACK`s, deferring the FK check past that rollback means it is never actually enforced — this let fixtures use fake IDs without fabricating unrelated entity rows. Verified working via a standalone manual test before relying on it (see commit history).
- **A transaction-scoped substitute `mss.v_host_key_value` view, clearly flagged as a test fixture.** The real ora2pg view is backed by `mss.mv_value_host_default`, and per `02-03-SUMMARY.md`, `ddl/migrated/mviews/` is explicitly out of scope for `mcdb_tmpl`. Rather than silently skip testing `get_string_by_host_key_id` (the routine that most needs this checklist dimension's coverage), the pgTAP file creates a `CREATE OR REPLACE VIEW` with the identical 5-column contract, sourced directly from `mss.value`/`mss.key`. This is explicitly commented as NOT a claim about how the real view/materialized view should be translated — it's flagged as a schema-completeness gap for Phase 4/5, in the same spirit as `migration/test/SCHEMA-FIXES.md`.
- **A placeholder GUC (`mcdb.force_dev_instance`) for the `V$INSTANCE`-dependent regress test.** `close_old_dev_tickets`' dev-instance gate has no PostgreSQL equivalent (S-UTIL-011, explicitly unresolved in the spec). Rather than skip testing the COMMIT-survival behavior entirely, the regress test sets a custom session GUC as a test-only convenience, loudly commented as NOT a spec claim and NOT a prediction of what XCUT-04/05 will actually decide.
- **Golden `.out` files encode the spec's expected SUBSTANCE, not today's actual output.** Per the plan's own instruction, the exact PL/pgSQL error/CONTEXT formatting cannot be known before a translation exists to observe. Both golden files were authored from the spec (message text derived directly from Oracle's `RAISE_APPLICATION_ERROR` string concatenation, decoded character-by-character from the doubled-quote literal), and the CONTEXT-line internal function line numbers are acknowledged, explicit placeholders — the mismatch against today's actual "does not exist" output is the RED proof itself, and reconciliation (formatting only, never substance) is deferred to whichever plan lands the real translation.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Plan's verify-command database name violates the harness's own safety gate**
- **Found during:** Task 3, first attempt to bootstrap a verification database
- **Issue:** The plan's own verify commands use `--db mcdb_p04`, but `migration/test/bootstrap.sh`'s safety gate (T-02-01, from plan 02-01) only accepts names matching `^mcdb_(test|tmpl|harness)[a-z0-9_]*$` — `mcdb_p04` does not match (`p04` isn't `test`/`tmpl`/`harness`), so `bootstrap.sh` refuses to run with a `FATAL` before any test could even start.
- **Fix:** Substituted `mcdb_test_p04` (matches the safety regex) everywhere the plan's verify commands specified `mcdb_p04`, for both `bootstrap.sh` and `run-tests.sh` invocations. Did not modify `bootstrap.sh` itself (out of this plan's `files_modified` scope, and the safety gate is working exactly as designed — T-02-01's whole point is that it should refuse an unrecognized name).
- **Files modified:** none (verification-command-only substitution, no repo files changed by this fix)
- **Verification:** `bash migration/test/bootstrap.sh --db mcdb_test_p04 --template mcdb_tmpl` succeeds; all subsequent RED verification runs against this database.
- **Committed in:** n/a (verification-only; no commit needed)

**2. [Rule 1 - Bug] `--package` flag in `migration/test/run-tests.sh` is not repeatable**
- **Found during:** Task 3, running the plan's exact verify command (`run-tests.sh --db mcdb_p04 --package mss.osag_dbprop --package auth.osag_auth --package tt.util`)
- **Issue:** `run-tests.sh`'s argument parser stores `--package` into a single scalar (`PKG_FILTER="$2"`), so passing it three times silently keeps only the last value (`tt.util`) — the other two packages were never actually exercised by that invocation, even though the command appeared to succeed at proving RED.
- **Fix:** Did not modify `run-tests.sh` (shared harness infrastructure from plan 02-01, out of this plan's scope, and a one-invocation workaround was available). Instead ran `run-tests.sh --db mcdb_test_p04` with NO `--package` filter, which discovers and runs every test file for every package (including `_canary`) in one pass — a strictly more thorough proof than the plan's original three-package-filtered command would have given even if it had worked as intended.
- **Files modified:** none
- **Verification:** Full unfiltered run shows all 3 pilot packages (`mss.osag_dbprop`, `auth.osag_auth`, `tt.util`) individually reported as `FAIL`, plus `_canary.canary` as the sole `PASS` — confirms all three packages were genuinely exercised and all three genuinely fail, not just whichever the flag happened to keep.
- **Committed in:** n/a (verification-only; flagging `run-tests.sh`'s `--package` non-repeatability here for whichever future plan next touches that script)

---

**Total deviations:** 2 auto-fixed (2 Rule 3/Rule 1, both verification-environment issues, zero repo-file changes required)
**Impact on plan:** Both deviations were pre-existing harness/plan-text inconsistencies unrelated to this plan's actual deliverables (specs and tests). Neither required touching shared harness files (`bootstrap.sh`, `run-tests.sh`), which are out of this plan's scope. No scope creep; both are flagged here for whichever future plan next maintains those scripts.

## Issues Encountered

- **`mss.osag_dbprop_get_number_by_host`'s pgTAP suite aborts its whole wrapping transaction on the first assertion, rather than failing all 10 individually.** Unlike the AUTH/UTIL suites (which wrap every function-calling assertion in `throws_ok`/`throws_like`/`lives_ok`, all of which pgTAP protects internally via savepoints), the DBPROP suite's first assertion is a bare `is()` around a direct call to the still-nonexistent function. That bare call's `ERROR: function ... does not exist` aborts the entire `BEGIN...ROLLBACK` transaction, so every later statement in that file also errors (`current transaction is aborted`), and `pg_prove` reports `Tests=0`/`Parse errors: Bad plan` instead of "10 failed." This still correctly proves RED (the log clearly shows the `does not exist` error) and the overall `run-tests.sh` exit code is unaffected, but it is a less informative failure mode than the other two suites'. Documented here rather than silently reworked, since fixing it would mean rewriting several assertions to use a defensive pattern purely for cosmetic reporting quality with no effect on the plan's actual pass/fail criteria — left as an honest observation for whichever later plan revisits this suite once a translation exists to test against (at which point, if the translation is correct, this whole failure mode disappears on its own).

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- All three pilot packages (MSS.OSAG_DBPROP, AUTH.OSAG_AUTH, TT.UTIL) have complete, `spec_lint`-clean specs with non-empty Assumptions sections and full checklist coverage — ready to be consumed as the authoritative input for whichever plan performs their PL/pgSQL translation.
- The TT.UTIL spec is a load-bearing input to Phase 3: XCUT-04 (pg_kind finalization, specifically re-checking `TT.EVENT_INTERFACE.addevent_new` and `TT.TICKET_INTERFACE.change_status_event_id_out`'s own eventual classification) and XCUT-05 (the autonomous-transaction/COMMIT-semantics decision for `close_old_dev_tickets`, with three candidate behaviors already laid out in the spec's Checklist dimension 5).
- Known, explicitly-flagged gaps for the translation plan to inherit: (1) `mss.v_host_key_value`/`mss.mv_value_host_default` are not loaded in `mcdb_tmpl` (mviews/ out of scope per 02-03) — the DBPROP test's substitute view is a stopgap, not a schema fix; (2) `V$INSTANCE` has no PostgreSQL equivalent — `close_old_dev_tickets`' dev-instance gate mechanism is genuinely undecided; (3) both regress golden files' CONTEXT-line internals are acknowledged placeholders pending reconciliation against a real translation's actual output.
- `run-tests.sh --package`'s non-repeatable-flag bug (documented above) should be fixed by whichever plan next touches the shared harness, so future multi-package verify commands behave as their authors intend.

---
*Phase: 02-spec-method-test-harness-pilot*
*Completed: 2026-07-13*
