---
phase: 02-spec-method-test-harness-pilot
plan: 07
subsystem: database
tags: [oracle-to-postgres, spec-first, plpgsql, oracle-plsql, select-into, overload, mutual-recursion, function-vs-procedure]

# Dependency graph
requires:
  - phase: 02-spec-method-test-harness-pilot
    provides: "migration/spec/ TEMPLATE.md/CHECKLIST.md/README.md + spec_lint.py (02-02); TT.OSAG_NOTIFY's 30-site SELECT INTO table format as the reusable convention (02-05); TT.EVENT_INTERFACE's spec as the cycle-partner model, including its dynamic-SQL trace and cycle-group note (02-06)"
provides:
  - "migration/spec/tt.ticket_interface.md -- 38 public routines (both change_label overloads specced distinctly), 58 clauses, all 77 SELECT INTO sites individually enumerated with STRICT verdicts, 2 FUNCTION/PROCEDURE-COMMIT traces closed (no hazard), the merge_tickets and deleteTicket cascade enumerations, a genuine previously-undocumented add_status_change_event bug, mutual recursion with TT.EVENT_INTERFACE specced in both directions"
affects: ["02-08 (tests for this spec)", "02-12 (this package's translation)", "phase 3 XCUT-01 (exception mapping) / XCUT-04 (FUNCTION-vs-PROCEDURE)", "phase 4 bulk translation -- proves the spec method scales to the corpus's largest package"]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "SELECT INTO strictness table format reused unmodified from 02-05/02-06 at nearly 3x the site count (77 vs 30/dynamic) -- proves the format scales without adaptation"
    - "Front-matter public_routines vs name-map.csv row count divergence for a legitimately-overloaded package: spec_lint.py's cross-check compares against inventory.json's NAME-keyed set (37 unique names), not name-map.csv's ROW count (38) -- the front-matter field must match the former, with an explicit prose note preventing a reader from mistaking this for a scope reduction"
    - "Reusing a sibling spec's private-routine naming convention (double-underscore marker prefix) without re-litigating it, while still flagging it as unfinalized -- the correct behavior when a convention already exists from an earlier plan in the same phase"

key-files:
  created:
    - migration/spec/tt.ticket_interface.md

key-decisions:
  - "public_routines front-matter set to 37, not 38, to match spec_lint.py's inventory.json-based cross-check (which is a NAME-keyed set and collapses the change_label overload pair to one entry). This is bookkeeping only -- an explicit front-matter note and both change_label overloads' full, distinct treatment in ## Routines/## Clauses make clear the package's real scope (38 physical routine declarations) is untouched."
  - "expire_status's doc-comment/body disagreement (comment claims it calls change_label() AND change_status(); body only calls change_status(), p_label_id is accepted but never read) recorded faithfully as the body's real behavior, per the plan's own instruction that the body is authoritative over the doc comment -- not silently 'corrected' by inventing a change_label call Oracle doesn't make."
  - "add_status_change_event's cust_id-never-assigned bug (every audit event this private routine writes has company_id = NULL, unlike every other change_* routine that writes its own event directly) is recorded as a real Oracle behavior to PRESERVE in translation, not fixed -- fixing it would be a deliberate, separately-documented deviation for a later phase, not something a spec-derivation plan should silently paper over."
  - "remove_related_file's missing same-company guard (present in its mirror add_related_file, absent here) is recorded as an asymmetry, not silently harmonized -- no live Oracle exists to confirm whether this is intentional."

requirements-completed: [SPEC-02, SPEC-03]

coverage:
  - id: D1
    description: "TT.TICKET_INTERFACE spec: all 38 public routines documented (both change_label overloads as distinct entries) + 3 private routines, 58 clauses, all 5 checklist dimensions answered with real Oracle-source citations"
    requirement: "SPEC-02"
    verification:
      - kind: unit
        ref: "python3 migration/spec/spec_lint.py migration/spec/tt.ticket_interface.md -> OK"
        status: pass
    human_judgment: false
  - id: D2
    description: "All 38 routines present via programmatic diff against inventory.json's routine name list (incl. the change_label overload pair); all 77 SELECT INTO sites individually cited and verdicted"
    requirement: "SPEC-02"
    verification:
      - kind: unit
        ref: "python3 one-off script diffing spec citations against inventory.json's routines[]/select_into_sites[] for TT.TICKET_INTERFACE -> ALL_38_ROUTINES_SPECCED / ALL_77_SELECT_INTO_SITES_SPECCED; grep -c 'STRICT, unhandled|STRICT + handler|no STRICT' -> 83 (>=77 required)"
        status: pass
    human_judgment: false
  - id: D3
    description: "Both FUNCTIONs' (get_next_recent_ticket, replace_id_placeholders) transitive COMMIT-reachability traced and handed to Phase 3's XCUT-04 as an input, not silently resolved"
    requirement: "SPEC-03"
    verification:
      - kind: unit
        ref: "grep -qiE get_next_recent_ticket && grep -qiE replace_id_placeholders && grep -qE XCUT-04 migration/spec/tt.ticket_interface.md -> FUNCTION_FINDING_RECORDED"
        status: pass
    human_judgment: false

duration: ~2.5h
completed: 2026-07-13
status: complete
---

# Phase 2 Plan 7: Spec for TT.TICKET_INTERFACE (all 38 routines) Summary

**Derived a 58-clause Oracle-source spec for the pilot's largest and most consequential package -- all 38 public routines (both `change_label` overloads specced as fully distinct entries), all 77 `SELECT ... INTO` sites individually enumerated with schema-grounded STRICT verdicts, the `merge_tickets`/`deleteTicket` cascade semantics traced exactly, a genuine previously-undocumented bug found in a shared private helper, both `FUNCTION`s' COMMIT-reachability closed with no hazard, and the mutual recursion with `TT.EVENT_INTERFACE` specced in both directions.**

## Performance

- **Duration:** ~2.5h (2,484-line body read and traced in full, cross-referenced against `migration/analyze/inventory.json`'s `select_into_sites`/`exception_handlers` counts and `migration/mapping/name-map.csv`'s 38 rows)
- **Tasks:** 3/3
- **Files modified:** 1 created (`migration/spec/tt.ticket_interface.md`, ~1,800 lines)

## Accomplishments

- **All 38 public routines specced**, verified programmatically against `inventory.json`'s routine list, including both `change_label` overloads as two fully distinct routine entries (2-arg bare form vs. 3/4-arg audited form that calls the bare form and writes its own audit event) — the corpus's one legitimate name collision, and the one place the linter's coverage check alone would NOT have caught a silent collapse.
- **All 77 `SELECT ... INTO` sites individually enumerated** in a dedicated strictness table (`# | line | target | zero rows? | multi rows? | Oracle handler | PG translation | clause`), matching the exact format `TT.OSAG_NOTIFY`'s 30-site table (02-05) established — proving that format scales to more than double the site count without adaptation. 13 `NO_DATA_FOUND` handlers, 0 `TOO_MANY_ROWS` handlers, 10 `WHEN OTHERS` handlers, matching `inventory.json`'s counts exactly. The large majority of sites (well over half) are `STRICT, unhandled` — this package propagates far more unhandled exceptions to its callers than either `TT.OSAG_NOTIFY` or `TT.EVENT_INTERFACE`, a genuinely different swallow/propagate profile worth flagging for Phase 3/4.
- **The `ROWNUM=1` translation hazard recurs a second time** (`update_ux_timeout_for_ticket`'s service-window-end lookup, site #20) — the identical structural trap already found in `TT.EVENT_INTERFACE`'s `addevent_new` (S-EVENT-019): Oracle's `ROWNUM=1` caps the row source before `SELECT INTO` can see more than one row, so a translation must add `LIMIT 1`, not merely drop the predicate, or its own `STRICT` could raise `TOO_MANY_ROWS` where Oracle structurally could not.
- **A shared sequence `NEXTVAL`-then-`CURRVAL` pattern found and documented once** (`change_type`, `change_service_component`, and the private `add_status_change_event` all resolve an `OUT` event id via `event_sequence.CurrVal` immediately after their own `INSERT ... event_sequence.NextVal` in the same session) — flagged as a corpus-wide mechanic requiring `nextval()`/`currval()` to stay paired within one translated routine, not split across a `CALL` boundary.
- **A genuine, previously-undocumented bug found**: the private `add_status_change_event` (shared by `change_customer_reference`, `change_partner_reference`, `change_emergency`, `change_always_visible`, `change_notification`, `change_summary`) declares `cust_id NUMBER;` and inserts it as the new event's `company_id` — but never assigns `cust_id` anywhere in its 40-line body. Every audit event these six routines write through it has `company_id = NULL`, unlike every other `change_*` routine that writes its own event directly and correctly resolves a real company id. Documented faithfully as a real Oracle behavior to preserve, not silently fixed, following the precedent `TT.EVENT_INTERFACE.moveevent`'s self-acknowledged bug set in 02-06.
- **A genuine doc/body disagreement found in `expire_status`**: its doc comment claims it "calls change_label() and change_status()"; the body only calls `change_status` — `p_label_id` is accepted but never read. Recorded as the body's actual (authoritative) behavior, not "corrected."
- **`merge_tickets` and `deleteTicket`'s cascade/non-cascade semantics specced exactly**, per the plan's own explicit instruction that these are "where a subtly wrong translation destroys data rather than throwing an error": `merge_tickets`' precise rules for ratings (most-recent-id wins), events (moved + original preserved via `org_ticket_id`, a NEW duplicate event inserted for the source rather than a shared row), notifications (de-duplicated then moved), partner reference/fast-resolvable/recoverable-status/UX-timeout merge rules, and the exact final-state ordering (source → status 110 "merged", target → status 3 "hot," as the routine's LAST statement); `deleteTicket`'s full 31-statement cascade enumerated in Oracle's exact execution order across 20+ tables, ending with the `tt.ticket` row itself.
- **Both `FUNCTION`s' COMMIT-reachability traced and closed with no hazard**: `get_next_recent_ticket` (one aggregate `SELECT`, calls nothing else) and `replace_id_placeholders` (pure string manipulation, zero database access, zero calls) — neither can transitively reach `TT.UTIL`'s `COMMIT`. This package's only two current call sites into `TT.UTIL` are both from `change_status_event_id_out`, a `PROCEDURE`, so no cross-package FUNCTION/PROCEDURE collision currently exists. Recorded as an XCUT-04 input, not silently settled — `pg_kind` remains PROVISIONAL for all 38 routines.
- **The mutual recursion with `TT.EVENT_INTERFACE` specced in both directions**: this package's 11 outbound call sites into `TT.EVENT_INTERFACE` (`add_history_event`/`addevent_new`/`exec_event_type_actions` from 12 different routines) are enumerated here, consistent with `tt.event_interface.md`'s already-committed inbound-direction accounting (its 12 call sites into `get_next_recent_ticket`/`change_status`/`change_type`). Both specs independently reach the identical conclusion that PL/pgSQL's CREATE-time (not call-time) function resolution means the two translations can load in either order.

## Task Commits

Work was committed in small increments throughout, per the plan's `commit_or_lose_it` protocol (this plan's own briefing noted the identical plan had already been lost twice to session interruptions with nothing committed):

1. `b345329` (docs) — spec skeleton + front-matter + package intro + routines 1-13 (`newticket_new`..`change_service_host`, incl. both `change_label` overloads)
2. `ee765c8` (docs) — remaining 25 routine entries (14-38) + 3 private routines
3. `f46df7a` (docs) — Clauses S-TICKET-001 through 058, covering all 38 routines' behavior/exceptions
4. `3383185` (docs) — Checklist (5 dimensions) + full 77-site SELECT INTO strictness table + Assumptions/Unresolved
5. `0784368` (fix) — corrected `public_routines` front-matter 38→37 to match `spec_lint.py`'s deduplicated inventory cross-check, fixed a stale clause-ID reference
6. `8a6425a` (docs) — fixed 5 remaining stale inline clause-ID cross-references left over from an earlier numbering draft

**Plan metadata:** (this commit, made after this SUMMARY)

## Files Created/Modified

- `migration/spec/tt.ticket_interface.md` — spec, 58 clauses (`S-TICKET-001..058`), 38 routines (37 unique names + the `change_label` overload pair), 77 SELECT INTO sites, all 5 checklist dimensions, non-empty Assumptions section

## Decisions Made

- **`public_routines: 37` in front-matter, not 38.** `spec_lint.py`'s cross-check compares the declared count against `inventory.json`'s routine list, which is keyed by NAME and therefore deduplicates the `change_label` overload pair to one set entry. Setting front-matter to 38 fails the linter; setting it to 37 passes AND is what the linter's own documented semantics actually check. This is not a scope reduction — an explicit front-matter note states the package has 38 physical routine declarations, and both `change_label` overloads are fully specced as distinct routines throughout `## Routines` and `## Clauses` (S-TICKET-019 for the 2-arg overload, S-TICKET-020 for the 3/4-arg overload). Flagged here in case Phase 4's spec tooling wants a cleaner convention (e.g. a separate `public_routine_declarations` field) for the corpus's other overload-bearing packages, if any exist beyond this one.
- **Bugs and doc/body disagreements found in the Oracle source are recorded, not fixed** (the `add_status_change_event` `cust_id` bug; the `expire_status` doc/body mismatch; `remove_related_file`'s missing same-company guard relative to its mirror `add_related_file`). Per this phase's spec-first methodology, "fixing" any of these would silently diverge the PostgreSQL translation from what Oracle actually does today, which is exactly the kind of unverifiable assumption this method exists to prevent. Each is flagged for a LATER, explicit deviation decision if Phase 4/5 wants to actually change the behavior.
- **The `TT.OSAG_NOTIFY`/`TT.EVENT_INTERFACE` private-routine naming convention (double-underscore marker prefix) is reused unmodified**, not re-derived, for this package's 3 private routines — consistent with the standing caveat from both prior specs that this convention is not yet finalized outside `migration/mapping/name-map.csv`.

## Known Stubs

None — this is a spec document with no runtime code; the "stub" concept does not apply.

## Threat Flags

None — this plan's own `<threat_model>` (T-02-25 through T-02-28) is the threat register being satisfied here, not a source of new surface. No new network endpoints, auth paths, or schema changes are introduced by a spec document.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking issue] Task 1's clause-count verify check used an incorrect grep pattern**
- **Found during:** Task 1 verification
- **Issue:** The plan's own verify command for Task 1 was `grep -cE "^\| *S-TICKET-[0-9]{3}"` (expecting clause IDs to appear as the FIRST column of a markdown table row). `TEMPLATE.md` and both sibling specs (`tt.osag_notify.md`, `tt.event_interface.md`) — and this spec — use `### S-<PREFIX>-NNN` heading-style clauses, per `TEMPLATE.md`'s own mandated skeleton. The pipe-table regex would fail identically against BOTH already-successful sibling specs (confirmed: `grep -cE "^\| *S-EVENT-[0-9]{3}" migration/spec/tt.event_interface.md` and the `S-NOTIFY-` equivalent both return 0), proving this is a bug in the verify command's regex, not a defect in any spec's structure.
- **Fix:** Did not weaken or edit the check. Confirmed the TRUE clause count independently (`grep -cE "^### S-TICKET-[0-9]{3}"` → 58, far exceeding the 19-clause threshold the check intended for routines 1-19), and confirmed full routine/clause coverage via `spec_lint.py` (which parses the real `### S-<PREFIX>-NNN` heading format correctly) and the plan's own Task 2/Task 3 Python-based verify scripts, all of which passed cleanly.
- **Files modified:** None (verification-only finding; no PLAN.md edit made).
- **Verification:** `spec_lint.py` OK; Task 2/3's programmatic routine and SELECT-INTO coverage checks both pass; 58 real clauses confirmed present.

**2. [Rule 1 - Bug] Front-matter `public_routines` count mismatch against `spec_lint.py`'s dedup semantics**
- **Found during:** First `spec_lint.py` run after completing all four mandatory sections
- **Issue:** `public_routines: 38` (the plan's own stated routine count) failed `spec_lint.py`'s cross-check, which compares against `inventory.json`'s NAME-keyed routine set (37 unique names, since `change_label` appears twice under the same name).
- **Fix:** Set front-matter to `37` (matching the linter's actual, documented semantics) and added an explicit prose note immediately after the front-matter clarifying that this is a bookkeeping detail, not a scope reduction — the package's real 38 physical routine declarations, and both `change_label` overloads as distinct entries, remain fully intact and cited throughout.
- **Files modified:** `migration/spec/tt.ticket_interface.md`
- **Verification:** `spec_lint.py` → OK.
- **Commit:** `0784368`

**3. [Rule 1 - Bug] Stale inline clause-ID cross-references**
- **Found during:** Final consistency pass after the Clauses section was complete
- **Issue:** Six inline `(S-TICKET-NNN)` mentions in the `## Routines` and private-routines prose referenced clause IDs assigned during an earlier draft numbering plan (059, 060 [invalid — letter-suffixed `060a` would also have failed `spec_lint.py`'s `S-[A-Z0-9]+-\d{3}` heading regex had it been used as an actual heading], 061, 062, 090, 091) that didn't survive into the final `## Clauses` section, which used a different (denser, gap-free) numbering scheme.
- **Fix:** Repointed all six references to the clause IDs that actually exist (052, 053, 054, 055, 046, 057). Verified via a diff of every referenced `S-TICKET-NNN` against every defined `### S-TICKET-NNN` heading — zero dangling references remain.
- **Files modified:** `migration/spec/tt.ticket_interface.md`
- **Verification:** `comm -23` diff of referenced vs. defined clause IDs → empty; `spec_lint.py` → OK.
- **Commit:** `8a6425a`

---

**Total deviations:** 3 auto-fixed (2x Rule 1 bug, 1x Rule 3 blocking-issue investigation with no code change required — the plan's own verify script, not the spec, was at fault)
**Impact on plan:** All auto-fixed within this plan's own verification loop; no scope change, no weakening of `spec_lint.py` itself, no silent trimming of the 38-routine/77-site requirement.

## Issues Encountered

- **The Task 1 verify-command bug (Deviation 1 above) would silently recur for any future plan that copy-pastes this exact grep pattern.** Not fixed here (out of this plan's scope to edit `02-07-PLAN.md`), but worth surfacing to whoever plans 02-08/Phase 4's remaining specs: the correct clause-count check is `grep -cE "^### S-<PREFIX>-[0-9]{3}"`, not a pipe-table pattern.

## User Setup Required

None — no external service configuration required. This is a documentation-only artifact; no database interaction occurs in this plan.

## Next Phase Readiness

- `migration/spec/tt.ticket_interface.md` is `spec_lint`-clean and ready to be consumed as the authoritative input for plan 02-08 (tests) and 02-12 (translation, alongside `TT.EVENT_INTERFACE` as one cycle-group batch per `migration/analyze/known_cycles.json`).
- Known, explicitly-flagged gaps for later plans to inherit: (1) the private-routine naming convention (3 routines: `add_status_change_event`, `handleDeferredTransitions`, `updateTicketTimeStats`) is proposed, reused from 02-05/02-06, but not finalized outside `migration/mapping/name-map.csv`; (2) three structural-uniqueness assumptions (`tt.ticket_time_statistic.ticket_id`, `tt.ticket_flow`'s single-open-entry invariant, `(tt.todo_item.ticket_id, seq_no)`) are inferred from routine behavior, not independently confirmed against named schema constraints; (3) the `add_status_change_event` `cust_id` bug and the `expire_status` doc/body mismatch are real Oracle behaviors this spec preserves — Phase 4/5 must decide explicitly whether to carry them forward or fix them as a documented deviation; (4) `remove_related_file`'s missing same-company guard (present in `add_related_file`) is flagged as an unconfirmed asymmetry.
- This plan proves the spec method scales: 38 routines, 77 SELECT INTO sites, 58 clauses derived from a 2,484-line body — more than double `TT.OSAG_NOTIFY`'s site count and nearly 5x `TT.EVENT_INTERFACE`'s routine count — using the identical conventions (SELECT INTO strictness table shape, private-routine naming, checklist structure) established by the two prior pilot specs, with no format changes required. This is the strongest available evidence for whether the method survives Phase 4's remaining 44 packages.

---
*Phase: 02-spec-method-test-harness-pilot*
*Completed: 2026-07-13*

## Self-Check: PASSED

`migration/spec/tt.ticket_interface.md` confirmed present on disk; all 6 task/fix commit
hashes (`b345329`, `ee765c8`, `f46df7a`, `3383185`, `0784368`, `8a6425a`) confirmed present
in git history via `git log --oneline --all`.
