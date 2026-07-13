---
phase: 02-spec-method-test-harness-pilot
plan: 06
subsystem: database
tags: [oracle, postgresql, plsql, plpgsql, pgtap, dynamic-sql, spec-first]

# Dependency graph
requires:
  - phase: 02-spec-method-test-harness-pilot
    provides: "02-02 (SPEC-02/03 method, TEMPLATE.md/CHECKLIST.md, linters), 02-03 (dual test harness, mcdb_tmpl template DB, plog stub)"
provides:
  - "migration/spec/tt.event_interface.md -- full 8-routine, 34-SELECT-INTO-site spec for TT.EVENT_INTERFACE"
  - "migration/spec/DYNAMIC-SQL-TRACE.md -- reusable dynamic-SQL trace FORM, consumed not re-derived (already committed in a prior interrupted session)"
  - "migration/test/pgtap/tt__event_interface__spec.sql + migration/test/regress/{sql,expected}/tt__event_interface__errors.* -- RED test suite, 20 pgTAP assertions + 2 pinned expected-output errors"
affects: ["02-11 (TT.EVENT_INTERFACE translation)", "02-09/02-12 or wherever TT.TICKET_INTERFACE is specced", "phase-4 bulk translation (12 more dynamic-SQL sites, TT.ESCALATION_INTERFACE cycle)"]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Dynamic-SQL manual trace consumed by the package spec via restatement + citation, never re-derived -- the spec's Assumptions section carries the trace's own UNRESOLVED sub-item forward unchanged"
    - "SELECT INTO strictness table enumerates every inventory-listed site by exact line, decoupling the automated 34-site coverage check from clause-level narrative grouping"

key-files:
  created:
    - migration/spec/tt.event_interface.md
    - migration/test/pgtap/tt__event_interface__spec.sql
    - migration/test/regress/sql/tt__event_interface__errors.sql
    - migration/test/regress/expected/tt__event_interface__errors.out
  modified: []

key-decisions:
  - "Carried DYNAMIC-SQL-TRACE.md's EXECUTE format() verdict into the spec verbatim, including its own internal UNRESOLVED sub-item (allowlist scope) -- not silently resolved to make the spec look more complete"
  - "Documented a genuinely new, previously-unrecorded TOO_MANY_ROWS re-raise-then-unhandled hazard at newevent_new's mss.host2service join (S-EVENT-001) -- WHEN OTHERS THEN RAISE re-raises it, and newevent_new has no outer handler at all"
  - "Documented the ROWNUM=1 -> LIMIT 1 translation mechanic (S-EVENT-019) as corpus-wide, not package-specific -- first appearance in the pilot"
  - "Closed the plan's own flagged FUNCTION/PROCEDURE question: ticket_type_for_event_type has zero DB access and zero calls to anything, so it cannot transitively reach TT.UTIL's COMMIT"
  - "Flagged (not resolved) a second, previously-invisible mutual-recursion pair the trace surfaces: TT.EVENT_INTERFACE <-> TT.ESCALATION_INTERFACE, not yet in known_cycles.json"

requirements-completed: [SPEC-02, SPEC-03, HARN-05]

coverage:
  - id: D1
    description: "TT.EVENT_INTERFACE spec covering all 8 public routines, all 34 SELECT INTO sites, derived only from ddl/src/**"
    requirement: SPEC-02
    verification:
      - kind: other
        ref: "python3 migration/spec/spec_lint.py migration/spec/tt.event_interface.md"
        status: pass
      - kind: other
        ref: "programmatic cross-check of migration/spec/tt.event_interface.md against migration/analyze/inventory.json's select_into_sites (all 34 present)"
        status: pass
    human_judgment: false
  - id: D2
    description: "The EXECUTE IMMEDIATE at tt_event_interface.sql:971 is manually traced (already done, consumed here) and its verdict + unresolved sub-item are carried into the spec's Assumptions section honestly"
    requirement: SPEC-02
    verification:
      - kind: other
        ref: "grep -qE 'tt_event_interface\\.sql:971' migration/spec/DYNAMIC-SQL-TRACE.md; grep '## Recommendation' migration/spec/DYNAMIC-SQL-TRACE.md"
        status: pass
      - kind: other
        ref: "awk '/## Assumptions/,0' migration/spec/tt.event_interface.md | grep -qiE 'dynamic|EXECUTE IMMEDIATE|971'"
        status: pass
    human_judgment: false
  - id: D3
    description: "RED pgTAP + expected-output test suite, every assertion citing a spec clause, demonstrably failing with no translation loaded"
    requirement: HARN-05
    verification:
      - kind: other
        ref: "python3 migration/spec/trace_lint.py migration/test/pgtap/tt__event_interface__spec.sql migration/test/regress/sql/tt__event_interface__errors.sql"
        status: pass
      - kind: integration
        ref: "bash migration/test/run-tests.sh --db mcdb_test_p06 --package tt.event_interface (both halves FAIL with 'does not exist', confirmed against a live mcdb_tmpl-cloned database)"
        status: pass
    human_judgment: false

# Metrics
duration: ~45min (this session; Task 1's trace was completed in an earlier interrupted session and consumed here, not redone)
completed: 2026-07-13
status: complete
---

# Phase 02 Plan 06: TT.EVENT_INTERFACE spec + RED tests, including the dynamic-SQL site Summary

**Full 8-routine/34-site spec for TT.EVENT_INTERFACE that consumes the already-completed dynamic-SQL trace (verdict: `EXECUTE format()` with an allowlist-scope sub-item left honestly `UNRESOLVED`) plus a 20-assertion RED pgTAP suite proving the harness fails correctly against zero translation.**

## Performance

- **Duration:** ~45 min this session (Task 1's `DYNAMIC-SQL-TRACE.md` was completed and committed in a prior session interrupted mid-plan; this session read it, did not redo it)
- **Completed:** 2026-07-13
- **Tasks:** 3/3 (Task 1 pre-existing/consumed, Tasks 2-3 executed this session)
- **Files modified:** 4 (1 spec, 1 pgTAP file, 1 regress SQL, 1 regress golden output) + 1 SUMMARY

## Accomplishments

- Wrote `migration/spec/tt.event_interface.md`: 8 public routines, 45 numbered clauses, a 34-row `SELECT INTO strictness` table (every inventory-listed site present, cross-checked programmatically), all five `CHECKLIST.md` dimensions, and an `## Assumptions / Unresolved` section that restates the trace's verdict, carries its `UNRESOLVED` sub-item forward unchanged, and adds two genuinely new findings of my own (below).
- Consumed `migration/spec/DYNAMIC-SQL-TRACE.md` (already complete from a prior interrupted session) rather than re-deriving it — its `EXECUTE format()` verdict, the allowlist-before-execution requirement, and the explicitly-flagged `UNRESOLVED — DO NOT GUESS` allowlist-scope question are all restated with citation, not settled.
- Found and documented two hazards the trace itself did not cover, because they live in `TT.EVENT_INTERFACE`'s own body, not the dynamic-SQL site:
  - **S-EVENT-001**: `newevent_new`'s `mss.host` × `mss.host2service` join can return more than one row (the join table's PK is `(host_id, service_id)`, not unique on `host_id`); Oracle's `WHEN OTHERS THEN RAISE` re-raises a `TOO_MANY_ROWS` here, and `newevent_new` has no procedure-level exception block at all — so it propagates fully unhandled to the caller today.
  - **S-EVENT-019**: `addevent_new`'s merged-ticket lookup uses `ROWNUM=1` in the `WHERE` clause, which caps the Oracle row source at one row *before* `SELECT INTO` could ever see more than one — a translation that drops `ROWNUM=1` without adding `LIMIT 1` would let its own `STRICT` raise `TOO_MANY_ROWS` in a case Oracle structurally never could.
- Wrote a 20-assertion pgTAP suite (`tt__event_interface__spec.sql`) plus a 2-error expected-output pair (`tt__event_interface__errors.sql`/`.out`), covering all 8 routines' happy paths, the fully-unhandled sites (`demote_event`, `promote_event`, `exec_event_type_actions` called directly), the swallowed sites (`moveevent`'s 3-arm handler), the two hazards above, and a dynamic-SQL allowlist-rejection test (a resolved-but-real, off-allowlist procedure name must be rejected, not silently executed).
- Ran the suite against a live `mcdb_test_p06` database cloned from `mcdb_tmpl` (plog stub installed) via `migration/test/run-tests.sh --package tt.event_interface` — **both halves FAIL**, confirmed for the right reason (`grep -qiE "does not exist|undefined"` matches the captured log). RED banked.
- `spec_lint.py` and `trace_lint.py` both run clean across the whole `migration/spec/` and `migration/test/` trees (not just this plan's own files).

## Task Commits

1. **Task 1: Manually trace the EXECUTE IMMEDIATE at line 971** - `00fadb0` (docs) — completed and committed in an earlier, interrupted session; consumed as-is this session, not redone or modified.
2. **Task 2: Spec TT.EVENT_INTERFACE** - `9c1d804` (docs)
3. **Task 3: Tests for TT.EVENT_INTERFACE, cited and RED** - `1f3a36a` (test)

**Plan metadata:** (this commit)

## Files Created/Modified

- `migration/spec/tt.event_interface.md` - Full spec: 8 routines, 45 clauses, 34-row SELECT INTO strictness table, 5 checklist dimensions, honest Assumptions/Unresolved section
- `migration/test/pgtap/tt__event_interface__spec.sql` - 20 pgTAP assertions, every description citing its spec clause
- `migration/test/regress/sql/tt__event_interface__errors.sql` - 2 pinned unhandled-propagation error cases (demote_event, promote_event)
- `migration/test/regress/expected/tt__event_interface__errors.out` - golden output authored from the spec's expected substance ("no data found"), per the 02-04 golden-file convention

## Decisions Made

- Carried the dynamic-SQL trace's verdict (`EXECUTE format()`) and its own flagged `UNRESOLVED` sub-item (allowlist scope: narrow to `TT.ESCALATION_INTERFACE.*` vs. broad "any single-`NUMBER`-arg procedure") into the spec's Assumptions section unchanged — this plan does not have standing to settle a decision the trace itself declared a Phase-4 translation-time policy call.
- Documented, but did not attempt to resolve, a genuinely new finding: the trace's dynamic-SQL edge closes a depgraph gap that reveals `TT.EVENT_INTERFACE` and `TT.ESCALATION_INTERFACE` form a SECOND, previously-invisible mutual-recursion pair, on top of the already-accepted 4-member cycle group. Flagged for whoever owns `known_cycles.json` maintenance — not edited here (out of this plan's scope).
- Closed the plan's own explicitly-flagged checklist question (whether the one `FUNCTION`, `ticket_type_for_event_type`, transitively reaches `TT.UTIL`'s `COMMIT`) with a documented "no": the routine does zero database access and calls zero other routines, confirmed by reading its full 29-line body.
- Recorded `moveevent`'s own acknowledged "FIXME / BROKEN" bug (from the Oracle source's own header comment) as Oracle's actual current behavior, explicitly declining to silently "fix" it in the spec or tests — that decision belongs to whoever plans `moveevent`'s translation.
- Used `mcdb_test_p06` (not `mcdb_p06`) for the live RED-proof database, per `bootstrap.sh`'s safe-name regex (`^mcdb_(test|tmpl|harness)[a-z0-9_]*$`) — the plan's own verify-block literal (`--db mcdb_p06`) does not match that regex; this is a naming-convention correction, not a behavioral deviation, and the verify command's actual assertions (exit code, log content) were run and passed unchanged.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Corrected the RED-proof database name to match bootstrap.sh's safe-name gate**
- **Found during:** Task 3's live verification step
- **Issue:** The plan's own verify command literal (`bash migration/test/bootstrap.sh --db mcdb_p06 --template mcdb_tmpl`) uses a name that does not match `bootstrap.sh`'s enforced `^mcdb_(test|tmpl|harness)[a-z0-9_]*$` safe-name gate (T-02-01) and is refused outright.
- **Fix:** Used `mcdb_test_p06` instead, exactly as this plan's own `<environment>` section instructs ("use the `mcdb_test_*` form"). All other verify-command assertions (exit code, `does not exist` grep) were run unmodified and passed.
- **Files modified:** none (command-line invocation only, no file changed)
- **Verification:** `bash migration/test/run-tests.sh --db mcdb_test_p06 --package tt.event_interface` produced the expected non-zero exit with "does not exist" in both halves' output.
- **Committed in:** n/a (no file change)

---

**Total deviations:** 1 auto-fixed (Rule 3 - blocking, database-name gate)
**Impact on plan:** Cosmetic only — the plan's own environment section already anticipated this exact naming requirement; no test content, spec content, or verification logic was changed.

## Issues Encountered

- Two `trace_lint.py` false-positive hits during first-draft authoring: prose comments containing the literal substrings `` `is()` `` and `PK is (host_id,service_id)` were mistaken by the linter's regex-based assertion scanner for actual `is(...)` calls (the scanner is not comment-aware). Reworded both comments to avoid the pattern; no assertion logic changed. This is a known sharp edge of `trace_lint.py`'s implementation (regex over raw text, not a SQL-comment-aware parser) worth flagging for whoever next touches that linter, but not a bug this plan is scoped to fix.
- The pgTAP suite's very first assertion (`ticket_type_for_event_type`, a bare `is()` call with no `lives_ok`/`throws_ok` wrapper) aborts the whole file's wrapping transaction on "function does not exist," causing pgTAP to report "Bad plan. You planned 20 tests but ran 0" rather than a per-assertion pass/fail breakdown. This matches the same pattern already present in the sibling `tt__osag_notify__spec.sql` (its `is_notify_suppressor_active` check) — an accepted harness characteristic for the RED phase, not a defect: once the translation exists, `is()` will succeed and the transaction will not abort. Confirmed the plan's own RED-proof criteria (non-zero exit, "does not exist" in the log) are satisfied regardless.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- `TT.EVENT_INTERFACE`'s spec and RED test suite are complete and banked; both linters (`spec_lint.py`, `trace_lint.py`) run clean across the whole `migration/spec/`/`migration/test/` trees, not just this plan's files.
- Plan 02-11 (or wherever `TT.EVENT_INTERFACE`'s translation lands) has, in hand: the exact `EXECUTE format()` recommendation with its allowlist-validation requirement and remaining `UNRESOLVED` scope question; the `TOO_MANY_ROWS` re-raise hazard at the host2service join; and the `ROWNUM=1` → `LIMIT 1` mechanic.
- Two things flagged for attention BEFORE Phase 4 batches translation order, not resolved here: (1) the newly-surfaced `TT.EVENT_INTERFACE` ↔ `TT.ESCALATION_INTERFACE` mutual-recursion pair is not yet in `migration/analyze/known_cycles.json`; (2) the dynamic-SQL allowlist's exact scope (narrow vs. broad) is a translation-time policy decision, not settled by this spec or its trace.
- `TT.TICKET_INTERFACE`'s own spec (this package's mutual-recursion partner, 38 routines) is a separate, not-yet-written plan in this phase — its internal behavior was deliberately kept out of scope here; only its call-graph edges into/out of `TT.EVENT_INTERFACE` were cited.

---
*Phase: 02-spec-method-test-harness-pilot*
*Completed: 2026-07-13*

## Self-Check: PASSED

All created files verified present on disk (`migration/spec/tt.event_interface.md`,
`migration/test/pgtap/tt__event_interface__spec.sql`,
`migration/test/regress/sql/tt__event_interface__errors.sql`,
`migration/test/regress/expected/tt__event_interface__errors.out`). All three task
commits verified present in `git log` (`00fadb0`, `9c1d804`, `1f3a36a`).
