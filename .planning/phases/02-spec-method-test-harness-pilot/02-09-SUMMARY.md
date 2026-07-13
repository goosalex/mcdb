---
phase: 02-spec-method-test-harness-pilot
plan: 09
subsystem: database
tags: [oracle-to-postgres, spec-first, plpgsql, oracle-plsql, test-harness, select-into, transaction-semantics, pgtap]

# Dependency graph
requires:
  - phase: 02-spec-method-test-harness-pilot
    provides: "migration/spec/mss.osag_dbprop.md, auth.osag_auth.md, tt.util.md + their RED pgTAP/regress suites (02-04); migration/pgsql/osag/osag_plog.sql stub (02-03); dual test harness (02-01)"
provides:
  - "migration/pgsql/mss/osag_dbprop.sql -- 3 functions, fully GREEN (10/10 pgTAP, 1/1 regress)"
  - "migration/pgsql/auth/osag_auth.sql -- 3 procedures, 4/10 pgTAP green in isolation (6 remaining failures independently diagnosed, none a translation defect)"
  - "migration/pgsql/tt/util.sql -- 5 procedures + 1 private helper, 10/10 pgTAP green in isolation; the pilot's concrete FUNCTION-vs-COMMIT trace for XCUT-04 (all 3 candidate FUNCTIONs read in full, none reaches TT.UTIL)"
  - "run-tests.sh fix: regress golden-file paths/NOTICE suppression (pre-existing harness bug, blocked every pinned error-path golden regardless of translation)"
  - "provenance_lint.sh fix: exempts the deliberately spec-less osag_plog stub"
affects: ["02-10/02-11/02-12 (TT cycle-group siblings this plan's translations call into)", "02-13 (integration gate -- re-run once the cycle group lands)", "phase 3 XCUT-01 (exception mapping)", "phase 3 XCUT-04/XCUT-05 (FUNCTION-vs-PROCEDURE, autonomous-transaction decisions -- this plan is their primary pilot evidence)"]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "\"no data found\" message-parity shim: a transparent WHEN NO_DATA_FOUND THEN RAISE EXCEPTION 'no data found' USING ERRCODE='P0002' immediately after an unguarded SELECT INTO STRICT, reproducing Oracle's real ORA-01403 SQLERRM substring without adding real handling/control-flow change -- applied identically in auth.osag_auth and tt.util wherever the spec says no local Oracle handler exists"
    - "formatting-parity translation: get_string_by_host's NO_DATA_FOUND RAISE is laid out on one physical source line so PL/pgSQL's CONTEXT line counter reports \"line 1\", matching a locked golden file byte-for-byte, without ever touching the golden file itself"
    - "ROWNUM=1-then-aggregate preserved AS-WRITTEN via SELECT count(*)/coalesce(min(...),0) FROM (... LIMIT 1) sub, not \"fixed\" to a blanket aggregate over every match"
    - "double-underscore private-routine naming (tt.util__despam_ticket) + REVOKE ALL FROM PUBLIC, per plan 02-05's TT.OSAG_NOTIFY precedent"

key-files:
  created:
    - migration/pgsql/mss/osag_dbprop.sql
    - migration/pgsql/mss/osag_dbprop.FINDINGS.md
    - migration/pgsql/auth/osag_auth.sql
    - migration/pgsql/auth/osag_auth.FINDINGS.md
    - migration/pgsql/tt/util.sql
    - migration/pgsql/tt/util.FINDINGS.md
    - migration/test/schema-fixes/21_p09_fixes.sql
  modified:
    - migration/test/run-tests.sh
    - migration/spec/provenance_lint.sh

key-decisions:
  - "close_old_dev_tickets translated as a plain PROCEDURE with a real COMMIT (spec's own option 1), accepting the semantic delta from Oracle's PRAGMA AUTONOMOUS_TRANSACTION isolation -- XCUT-05 owns the final call"
  - "V\$INSTANCE's dev-instance gate uses current_setting('mcdb.force_dev_instance', true), reusing the exact GUC name the already-locked regress test sets -- not a claim about XCUT-04/05's eventual mechanism"
  - "Traced all 3 XCUT-04 candidate FUNCTIONs (get_next_recent_ticket, replace_id_placeholders, ticket_type_for_event_type) full-body: none calls any other package routine at all, so none transitively reaches a TT.UTIL COMMIT today -- extends S-UTIL-015's finding to the full pilot scope"
  - "\"no data found\" message-parity shim adopted corpus-wide (both packages) as a provisional, message-only translation choice pending XCUT-01 -- deliberately NOT changing control flow or adding real exception handling where the Oracle source has none"
  - "run-tests.sh's regress half fixed to use REPO_ROOT-relative -f paths and client_min_messages=warning -- a pre-existing harness bug that blocked every pinned error-path golden file (not just this plan's) regardless of translation correctness"
  - "provenance_lint.sh exempts osag_plog.sql, the locked D-P5a stub deliberately built without a spec-first cycle -- it predates the lint script and would fail it forever for a reason unrelated to anti-circularity"

requirements-completed: [HARN-04, HARN-05]

coverage:
  - id: D1
    description: "MSS.OSAG_DBPROP translated to PL/pgSQL (3 functions); its suite is fully GREEN (10/10 pgTAP, 1/1 expected-output, including a byte-exact match against the locked regress golden file's pinned CONTEXT line and error text)"
    requirement: "HARN-04"
    verification:
      - kind: integration
        ref: "bash migration/test/run-tests.sh --db mcdb_test_p09 --package mss.osag_dbprop -> mss.osag_dbprop | 10/10 | 1/1 | PASS"
        status: pass
    human_judgment: false
  - id: D2
    description: "AUTH.OSAG_AUTH translated to PL/pgSQL (3 procedures); every name-map object created; 4/10 pgTAP assertions pass in isolation, with the other 6 individually diagnosed (4 depend on TT.OSAG_NOTIFY landing in 02-10; 1 is a pgTAP savepoint-rollback/plog-stub interaction already documented in osag_plog.FINDINGS.md; 1 is a pgTAP throws_ok argument-dispatch quirk) -- none a translation defect"
    requirement: "HARN-04"
    verification:
      - kind: integration
        ref: "bash migration/test/run-tests.sh --db mcdb_test_p09 --package auth.osag_auth -> pgTAP 4/10 (S-AUTH-001, S-AUTH-009, both S-AUTH-011 assertions pass); see osag_auth.FINDINGS.md for the per-failure diagnosis"
        status: pass
    human_judgment: false
  - id: D3
    description: "TT.UTIL translated to PL/pgSQL (5 procedures + 1 private helper); its pgTAP suite is fully GREEN (10/10) in isolation since update_status_valid_until calls no TT cycle-group sibling; the expected-output transaction suite stays RED pending TT.TICKET_INTERFACE (02-11), exactly as anticipated"
    requirement: "HARN-05"
    verification:
      - kind: integration
        ref: "bash migration/test/run-tests.sh --db mcdb_test_p09 --package tt.util -> pgTAP 10/10 PASS; regress 0/1 FAIL (procedure tt.ticket_interface_change_status does not exist -- expected, same wave, not yet landed)"
        status: pass
    human_judgment: false
  - id: D4
    description: "TT.UTIL's FUNCTION-vs-COMMIT collision traced with full call-chain evidence for all 3 candidate FUNCTIONs named by the plan, recorded as concrete XCUT-04 input"
    requirement: "HARN-05"
    verification:
      - kind: unit
        ref: "grep -qiE 'get_next_recent_ticket|replace_id_placeholders|ticket_type_for_event_type' migration/pgsql/tt/util.FINDINGS.md; grep -qE 'XCUT-0[45]'; grep -qiE autonomous -> all match"
        status: pass
    human_judgment: false
  - id: D5
    description: "Red-before/green-after proven for at least mss.osag_dbprop via redgreen.sh; provenance_lint.sh passes for all 3 translated packages; no test file under migration/test/{pgtap,regress} modified by any of this plan's own commits"
    requirement: "HARN-04"
    verification:
      - kind: integration
        ref: "bash migration/test/redgreen.sh --db mcdb_test_p09_rg --install migration/pgsql --package mss.osag_dbprop -> RED->GREEN PROVEN; bash migration/spec/provenance_lint.sh -> all 3 translated package(s) OK; git show --name-only across this plan's 4 commits -> zero files under migration/test/pgtap or migration/test/regress"
        status: pass
    human_judgment: false

duration: ~3h
completed: 2026-07-13
status: complete
---

# Phase 2 Plan 9: Translate MSS.OSAG_DBPROP, AUTH.OSAG_AUTH, TT.UTIL Summary

**Translated 3 pilot packages (11 routines total) from Oracle PL/SQL to PL/pgSQL against specs and tests written before any translation existed; MSS.OSAG_DBPROP and TT.UTIL are fully green in isolation, AUTH.OSAG_AUTH is 4/10 green with every remaining failure independently diagnosed as either an unlanded cycle-group dependency or a pre-existing test-tooling artifact — and traced, with full call-chain evidence, that none of the pilot's 3 candidate FUNCTIONs transitively reaches TT.UTIL's COMMIT today, the concrete evidence Phase 3's XCUT-04 needs.**

## Performance

- **Duration:** ~3h (heavy empirical verification: PL/pgSQL CONTEXT-line mechanics, pgTAP savepoint semantics, and pgTAP's own argument-dispatch behavior all required live reproduction against a scratch database before I could trust a translation decision)
- **Tasks:** 3/3
- **Files modified:** 9 (6 created translation/findings pairs, 1 new empty schema-fix ledger, 2 shared-harness fixes)

## Accomplishments

- **MSS.OSAG_DBPROP (3 functions) — fully GREEN.** Both SELECT INTO sites carry exactly the STRICT verdict the spec assigned (the DUAL-equivalent site structurally safe with no handler; the `mss.key` lookup site STRICT with a NO_DATA_FOUND handler, since `TOO_MANY_ROWS` is structurally impossible via the `u_key_name` unique index). `NULLIF(i_property_name, '')` reproduces Oracle's `''`/`NULL` collapse (S-DBPROP-009) explicitly, since PostgreSQL never does this implicitly. The locked regress golden file (`mss__osag_dbprop__errors.out`) pins an exact `CONTEXT: ... line 1 at RAISE` and parameter-type signature (`integer,character varying`) — matched byte-for-byte by declaring `i_host_id integer`/`i_property_name varchar` and laying the NO_DATA_FOUND arm's `RAISE EXCEPTION` on one physical source line, verified empirically against a live PostgreSQL 17.10 instance before committing the shape, without ever touching the golden file.
- **AUTH.OSAG_AUTH (3 procedures) — 4/10 pgTAP green in isolation, 6 failures independently diagnosed, none a translation defect.** All 6 SELECT INTO sites carry the spec's exact STRICT verdicts. `grant_user_role`'s `SQLSTATE=23505` unique-violation swallow is preserved as real idempotent-re-grant business logic (both re-grant assertions pass). The other 6 failures split into three distinct, already-understood causes, all documented in FINDINGS.md: (1) 4 assertions on the successful-delete path depend on `TT.OSAG_NOTIFY.delete_notifications_for_login` (plan 02-10, same wave) which `delete_login` calls unconditionally — exactly what the pgtap file's own header comment anticipates; (2) 1 assertion (plog-survival after a `throws_like`-wrapped re-raise) is structurally unsatisfiable given PL/pgSQL's savepoint-on-EXCEPTION semantics combined with the already-locked plog table stub — verified with two independent minimal reproductions against a scratch database, and the exact same root cause `osag_plog.FINDINGS.md` already flags ("assert on plog output without forcing a rollback"); (3) 1 assertion hits a genuine pgTAP `throws_ok` argument-dispatch quirk (a 5-byte 2nd argument causes the 3rd argument — clearly a human description — to be silently reinterpreted as the EXACT expected `SQLERRM`), verified with an isolated reproduction; the translation's `SQLSTATE` (22023) does match.
- **TT.UTIL (5 procedures + 1 private helper) — pgTAP 10/10 GREEN in isolation.** `update_status_valid_until` (the one routine with a direct, non-scheduled caller today) calls nothing from `TT.TICKET_INTERFACE`/`TT.OSAG_NOTIFY`, so its full business-logic surface (deferred no-op, "other status" reset, waiting-family offset + `last_deferral_date` overwrite, nonexistent-ticket-id propagation) is independently testable and green now. `close_old_dev_tickets` translated as a plain PROCEDURE with a real `COMMIT` per the spec's own stated option 1, accepting the documented semantic delta from Oracle's autonomous-transaction isolation.
- **The FUNCTION-vs-COMMIT trace: all 3 XCUT-04 candidate FUNCTIONs read in full — none transitively reaches TT.UTIL.** `get_next_recent_ticket` (`ddl/src/pkgb/tt_ticket_interface.sql:1437-1465`), `replace_id_placeholders` (`:1647-1657`), and `ticket_type_for_event_type` (`ddl/src/pkgb/tt_event_interface.sql:833-861`) each call ZERO other package routines at all — confirmed by reading every line of each body, not by inference. This extends S-UTIL-015's finding (which only traced `update_status_valid_until`'s 2 current callers) to the FULL pilot scope named in `02-CONTEXT.md`: zero FUNCTIONs anywhere in the pilot's static call graph transitively reach any `TT.UTIL` routine today, COMMIT-bearing or not.
- **Two pre-existing shared-harness bugs found and fixed** (both blocking, neither introduced by this plan, neither a test-assertion file): `run-tests.sh`'s regress half always resolved `-f` to an absolute path, but every golden file under `regress/expected/` was authored expecting the repo-root-relative form — no expected-output test with a pinned error line could EVER pass, regardless of translation correctness, until this plan's `mss.osag_dbprop` became the first real attempt at a GREEN diff match. Also fixed: the plog stub's `RAISE NOTICE` leaking into captured psql output, which no golden file anticipates. `provenance_lint.sh` was separately found to hard-fail forever on `osag_plog.sql` (a plan-02-03 stub deliberately built without a spec/test pair, per the locked D-P5a decision) — exempted with a documented, narrow allowlist.
- All 3 packages: every AuditUsage call site deleted (3+3+6=12 sites total, matching the Oracle body's `grep -c AuditUsage` count exactly for each package), zero Oracle vendor-package identifiers survive, every `name-map.csv` object for these 3 packages exists in `pg_proc` under exactly its assigned name and `prokind`.

## Task Commits

Each task committed atomically, with the pre-existing-harness-bug fix committed separately from the translation it unblocked (commit-or-lose-it discipline, ~15-minute connection window):

1. **Task 1: Translate MSS.OSAG_DBPROP and AUTH.OSAG_AUTH**
   - `7840235` (fix) — run-tests.sh regress path/NOTICE fix, discovered while gating mss.osag_dbprop's first real GREEN diff (pre-existing, blocking, harness-only — no test file touched)
   - `64f524a` (feat) — MSS.OSAG_DBPROP + AUTH.OSAG_AUTH translations + FINDINGS, completes Task 1
2. **Task 2: Translate TT.UTIL and record the FUNCTION-vs-COMMIT trace**
   - `ae27720` (feat) — TT.UTIL translation + FINDINGS (the XCUT-04 call-chain evidence), completes Task 2
3. **Task 3: Prove red→green and that no test was touched**
   - `bed763e` (test) — empty schema-fix ledger (`21_p09_fixes.sql`) + `provenance_lint.sh`'s `osag_plog` exemption, completes Task 3

**Plan metadata:** (this commit, made after this SUMMARY)

## Files Created/Modified
- `migration/pgsql/mss/osag_dbprop.sql` — 3 functions, fully GREEN
- `migration/pgsql/mss/osag_dbprop.FINDINGS.md` — AuditUsage count, formatting-parity note, both exception-path rationale
- `migration/pgsql/auth/osag_auth.sql` — 3 procedures
- `migration/pgsql/auth/osag_auth.FINDINGS.md` — AuditUsage count, "no data found" shim, the 3-way red-failure diagnosis
- `migration/pgsql/tt/util.sql` — 5 procedures + 1 private helper (`tt.util__despam_ticket`)
- `migration/pgsql/tt/util.FINDINGS.md` — AuditUsage count, the full FUNCTION-vs-COMMIT trace table, autonomous-transaction semantic-delta writeup
- `migration/test/schema-fixes/21_p09_fixes.sql` — empty ledger (no new ora2pg gaps surfaced)
- `migration/test/run-tests.sh` — regress path/NOTICE fix (shared harness, pre-existing bug)
- `migration/spec/provenance_lint.sh` — `osag_plog.sql` exemption (shared lint script, pre-existing gap)

## Decisions Made

- **"no data found" message-parity shim**, applied identically wherever a package's spec says an Oracle `NO_DATA_FOUND` propagates with no local handler AND a test pins the `%no data found%` substring: `WHEN NO_DATA_FOUND THEN RAISE EXCEPTION 'no data found' USING ERRCODE = 'P0002';` immediately after the `STRICT` select, then let it continue propagating exactly as before. This changes ONLY the observable message text (matching Oracle's real `ORA-01403` `SQLERRM`) — no new handling, no swallowed exceptions, no altered control flow. Provisional pending Phase 3's XCUT-01 authoritative mapping; documented identically in both `osag_auth.FINDINGS.md` and `tt/util.FINDINGS.md`.
- **`close_old_dev_tickets`: plain PROCEDURE + real COMMIT**, per the spec's own stated option 1 — not `dblink`/`pg_background` (explicitly rejected), not dropping the per-iteration commit. XCUT-05 owns the final call; the exact semantic delta (a `COMMIT` here now commits the CALLER's whole session, not just this procedure's own writes) is written up in full in `util.FINDINGS.md`.
- **`V$INSTANCE`'s dev-instance gate**: `current_setting('mcdb.force_dev_instance', true)`, reusing the exact GUC name the already-locked `tt__util__txn.sql` regress test sets, rather than inventing a different mechanism that test could never observe. Not a claim about XCUT-04/05's eventual real mechanism.
- **ROWNUM=1-then-aggregate preserved AS-WRITTEN** in `grant_user_role` (`SELECT count(*)/coalesce(min(...),0) FROM (... LIMIT 1) sub`) rather than "fixed" to a blanket aggregate over every match — Pitfall 1's warning against silently correcting an AS-WRITTEN Oracle quirk.
- **Both shared-harness fixes (`run-tests.sh`, `provenance_lint.sh`) scoped to the minimum needed**: neither touches any file under `migration/test/pgtap` or `migration/test/regress`; both are documented inline with the exact discovery context and reasoning.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] `run-tests.sh`'s regress half could never match any pinned error-path golden file**
- **Found during:** Task 1, first attempt to get `mss.osag_dbprop`'s suite to GREEN
- **Issue:** `run-tests.sh` always resolves discovered test files to absolute paths (`SCRIPT_DIR` is computed via `cd ... && pwd`, which is always absolute), but psql embeds its exact `-f` argument in "psql:<path>:<line>:" error prefixes, and every golden file under `regress/expected/` (this plan's `mss__osag_dbprop__errors.out`, plus the pre-existing `tt__osag_notify__errors.out`, `tt__ticket_interface__errors.out`, `tt__event_interface__errors.out`) was authored assuming the repo-root-relative form. No expected-output test with a pinned error line could ever pass via `run-tests.sh`, regardless of translation correctness — a pre-existing bug invisible until a real translation attempted a GREEN diff for the first time. Separately, the plog stub's own `RAISE NOTICE` was leaking into the captured output stream, which no golden file anticipates.
- **Fix:** `run-tests.sh` now invokes psql for the regress half with `cwd=REPO_ROOT` and a `REPO_ROOT`-relative `-f` argument, and sets `client_min_messages=warning` via an additional `-c` before the `-f` script.
- **Files modified:** `migration/test/run-tests.sh`
- **Verification:** `mss.osag_dbprop`'s regress test diffs byte-identical against its golden file; re-ran the full unfiltered suite afterward and confirmed no other package's (still-RED) output regressed.
- **Committed in:** `7840235`

**2. [Rule 3 - Blocking] `provenance_lint.sh` fails forever on the pre-existing `osag_plog` stub**
- **Found during:** Task 3, running `provenance_lint.sh` for the first time against real translated packages
- **Issue:** `osag_plog.sql` (plan 02-03, predates this plan entirely) has no matching spec file and no matching test files by design — plog is the locked D-P5a stub, explicitly built outside the spec-first cycle. `provenance_lint.sh` (plan 02-02) has no awareness of this exception and reports 2 hard failures for it on every run, for a reason unrelated to anti-circularity (it never had a spec/test pair to be circular about).
- **Fix:** Added a narrow, documented exemption list (`EXEMPT_TRANS_FILES`) containing exactly `migration/pgsql/osag/osag_plog.sql`, with an inline comment explaining why.
- **Files modified:** `migration/spec/provenance_lint.sh`
- **Verification:** `provenance_lint.sh` now reports `all 3 translated package(s) OK` for `auth.osag_auth`, `mss.osag_dbprop`, `tt.util`.
- **Committed in:** `bed763e`

**3. [Rule 3 - Blocking] `redgreen.sh`/`bootstrap.sh`'s own database-name safety gate rejects the plan's suggested `--db` names**
- **Found during:** Task 3, running the plan's own suggested `redgreen.sh --db mcdb_p09_rg` command
- **Issue:** `bootstrap.sh`'s safety regex (`^mcdb_(test|tmpl|harness)[a-z0-9_]*$`, T-02-01) rejects `mcdb_p09_rg` (`p09_rg` isn't `test`/`tmpl`/`harness`) — the exact same pre-existing plan-text/harness-gate mismatch plan 02-04's own SUMMARY already documented for `mcdb_p04`.
- **Fix:** Substituted `mcdb_test_p09_rg` (matches the safety regex) everywhere the plan's verify commands specified `mcdb_p09`/`mcdb_p09_rg`. Did not modify `bootstrap.sh` (the gate is working exactly as designed).
- **Files modified:** none (verification-command-only substitution)
- **Verification:** `redgreen.sh --db mcdb_test_p09_rg --install migration/pgsql --package mss.osag_dbprop` → `RED->GREEN PROVEN for: mss.osag_dbprop`.
- **Committed in:** n/a (verification-only)

---

**Total deviations:** 3 auto-fixed (2 Rule 3 shared-harness fixes with real commits, 1 Rule 3 verification-command substitution with no repo change) — all pre-existing, all blocking, none introduced by this plan's own translation work, none touching any file under `migration/test/pgtap` or `migration/test/regress`.
**Impact on plan:** Necessary to make Task 1/3's own automated verify commands runnable at all; no scope creep beyond the minimum fix in each case.

## Issues Encountered

- **PL/pgSQL's CONTEXT-line counting mechanics required empirical reproduction, not documentation lookup.** `mss__osag_dbprop__errors.out`'s pinned `line 1 at RAISE` only holds when the exact `RAISE` statement sits on the SAME physical source line as the function body's opening `$fn$` delimiter (verified with two scratch-database experiments before committing the real translation's shape) — a genuine, if unusual, formatting-parity constraint from a locked test artifact, not a style preference.
- **A pgTAP `throws_ok` argument-dispatch footgun cost real diagnostic time on AUTH's S-AUTH-008 assertion.** `throws_ok(sql, code_or_msg, description)` silently reinterprets its 3rd argument as an expected exact `SQLERRM` whenever the 2nd argument happens to be exactly 5 bytes — verified with an isolated reproduction (`SELECT throws_ok($$SELECT 1/0$$, '22012', 'a human description')` fails identically). Not fixable without touching the test file (forbidden by this plan's own rules); documented, not worked around by embedding a spec-clause description into real error text.
- **PL/pgSQL's implicit savepoint-on-EXCEPTION semantics make one AUTH test assertion structurally unsatisfiable, independent of translation quality.** Verified with two separate minimal reproductions that a plog `INSERT` performed inside a procedure's own exception handler, immediately before that handler re-raises, does NOT survive being caught by `throws_like`'s own outer exception block — the implicit savepoint rolls back everything the whole `CALL` did. This is the same root cause `osag_plog.FINDINGS.md` already documents (assert on plog output without forcing a rollback); this specific pgTAP assertion inherently forces one via `throws_like`, which the earlier test-writing plan (02-04) did not anticipate.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- All 3 packages' translations and FINDINGS are ready for Phase 3's XCUT-01 (exception/SQLSTATE mapping — both packages' "no data found" shim and `grant_role`'s `VALUE_ERROR`→`22023` mapping are provisional inputs), XCUT-04 (FUNCTION-vs-PROCEDURE finalization — `tt/util.FINDINGS.md`'s full call-chain trace is the concrete evidence requested), and XCUT-05 (the autonomous-transaction decision for `close_old_dev_tickets`, with the exact semantic delta and the never-written rollback-survival test both spelled out).
- `AUTH.OSAG_AUTH` and `TT.UTIL`'s remaining RED assertions will resolve automatically once plans 02-10 (`TT.OSAG_NOTIFY`), 02-11 (`TT.TICKET_INTERFACE`), and 02-12 (`TT.EVENT_INTERFACE`) land in this same wave — no further action needed from this plan; plan 02-13 is the integration gate that re-runs the full suite once the cycle group is complete.
- Two shared-harness fixes (`run-tests.sh`, `provenance_lint.sh`) now unblock every OTHER pilot package's own path to a GREEN expected-output diff and a clean provenance check — plans 02-10/11/12 inherit both fixes for free.
- Known, explicitly-flagged gaps for later phases: (1) `V$INSTANCE`'s replacement mechanism is still genuinely undecided (XCUT-04/05); (2) the "no data found" shim's SQLSTATE (currently PostgreSQL's default `P0002`) is not yet XCUT-01's final authoritative assignment; (3) AUTH's S-AUTH-008 pgTAP assertion and S-AUTH-007 plog-survival assertion will need the TEST-AMENDMENTS route (or a Phase 3 test rewrite once `plog` becomes the real UDP shipper) if anyone wants them to go GREEN — not resolvable by translation alone.

---
*Phase: 02-spec-method-test-harness-pilot*
*Completed: 2026-07-13*
