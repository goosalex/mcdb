---
phase: 01-inventory-foundation
plan: 02
subsystem: database
tags: [python, oracle, plsql, static-analysis, migration-tooling, dependency-graph, name-mapping]

# Dependency graph
requires:
  - phase: 01-inventory-foundation plan 01
    provides: "migration/analyze/inventory.json (105 objects, calls_out_raw both call shapes, synonyms), plsql_lex.py's normalize() helper"
provides:
  - "migration/mapping/name-map.csv — THE PostgreSQL name-mapping SSOT (INV-03), 328 rows, zero unresolved collisions"
  - "migration/analyze/depgraph.json — THE dependency graph + wave list (INV-02), 105 nodes, 94 edges, 5 waves, 2 accepted cycle groups"
  - "migration/regenerate.sh — one command regenerating and validating the whole Phase 1 foundation, with a provably-failing staleness gate"
affects: ["phase 2 (spec derivation reads depgraph.json waves[] for translation order)", "phase 4 (wave-ordered translation, cross-reference rewriting, test naming all read these artifacts)", "phase 5 (client regexp kit generated from name-map.csv)"]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "SSOT enforcement: name-map.csv is the only place a PostgreSQL name is decided; depgraph.py derives its synonym table FROM name-map.csv's oracle_synonym column rather than re-deriving from raw inventory.synonyms, so there is never a second synonym-resolution implementation"
    - "Collision gate as a two-phase classify -> apply-overrides -> re-classify pipeline: mechanical names are classified first (to know what a hard collision actually is), overrides are applied only to rows genuinely in a hard-collision group, then a second classification pass on post-override names is authoritative"
    - "SCC condensation for cycle-safe topological sort: Tarjan's algorithm collapses every strongly-connected component of size > 1 into one condensed node before wave assignment, so mutual package recursion cannot infinite-loop or crash the sort"
    - "Staleness gate via normalized-diff: regenerate.sh regenerates into a temp dir and diffs against checked-in artifacts with only the volatile generated_at timestamp stripped (generator_version deliberately left in, so a version bump still forces a regenerate)"

key-files:
  created:
    - migration/mapping/name_map.py
    - migration/mapping/name-map.csv
    - migration/mapping/overrides.csv
    - migration/mapping/tests/test_name_map.py
    - migration/analyze/depgraph.py
    - migration/analyze/depgraph.json
    - migration/analyze/depgraph.dot
    - migration/analyze/known_cycles.json
    - migration/analyze/tests/test_depgraph.py
    - migration/regenerate.sh
  modified:
    - migration/README.md

key-decisions:
  - "The real corpus contains exactly ONE duplicate (pg_schema, pg_object_name) group, and it is the legitimate TT.TICKET_INTERFACE.change_label overload -- overrides.csv is seeded with a header row only, no data rows, because no real hard collision exists today. The plan's collision hazard (MC.MONITORING/MONITORING_STATE-shape prefix ambiguity) is real in schema layout but doesn't materialize in practice because every *_STATE package in this corpus (MONITORING_STATE, OSAG_AUTH_STATE excluded since it has one routine, OSAG_DBPROP_STATE, OSAG_GUMA_STATE, EVENT_INTERFACE_STATE, TICKET_INTERFACE_STATE) happens to declare zero or non-colliding public routines. The gate is fully implemented and proven capable of firing via synthetic fixtures (Tests 10-13), not weakened because the real data happens not to trigger it."
  - "Two genuine cycle groups exist in the real corpus and are seeded into known_cycles.json after individual verification against source, not just accepted because the algorithm found them: MC.MONITORING <-> MC.MONITORING_TICKET_PROCESSES, and the four core ticketing packages TT.EVENT_INTERFACE / TT.OSAG_NOTIFY / TT.TICKET_INTERFACE / TT.UTIL (a 4-member SCC). Both confirmed by reading the actual call sites, not assumed from the SCC computation alone."
  - "depgraph.py's synonym index is built FROM migration/mapping/name-map.csv's oracle_synonym column, not by re-parsing inventory.json's raw synonyms list. This means Task 1's malformed-synonym heuristic (the unqualified 'OSAG_NIDS' synonym, resolved to NIDS.OSAG_NIDS by unique package-name match) is inherited automatically instead of being re-implemented, keeping synonym resolution as a single source of truth."
  - "31 of 105 nodes end up static_resolution=incomplete -- 4 are the known dynamic-SQL bodies (SYS.OSAG_TABLE_REDEFINITION, REPORT.OSAG_CHANNEL, TT.EVENT_INTERFACE, MCDB_CHECKS.CONSISTENCY); the other 27 are objects whose calls_out_raw picked up INSERT/SELECT column-list noise (e.g. 'INSERT INTO auth.profile (id, name, ...)' misread by the lexer-based extractor as a call-shaped reference 'auth.profile'). This is a known, documented limitation of plan 01's calls_out_raw extraction (not something plan 02 was scoped to fix): every unresolved reference is recorded in unresolved_refs[] and forces the same 'incomplete' flag as genuine dynamic SQL, per the plan's explicit instruction that both classes of risk look identical to Phase 4. Documented in README.md's standing warning so Phase 2/4 know to expect false positives in that list, not just real dynamic-SQL risk."

requirements-completed: [INV-02, INV-03]

coverage:
  - id: D1
    description: "name-map.csv maps every callable Oracle object (package routines, standalone procedures, 53 triggers + 53 synthetic trigger functions, 2 types) to its package_in_name PostgreSQL name, with a collision gate that hard-fails on cross-package prefix ambiguity and identical-signature collisions, allows legitimate same-package overloads, and is resolvable only via a human-authored overrides.csv row"
    requirement: "INV-03"
    verification:
      - kind: unit
        ref: "migration/mapping/tests/test_name_map.py (15 tests: name derivation x5, coverage x3, collision gate x6 incl. two hard-fail classes + stale override, consumer contract x1)"
        status: pass
      - kind: integration
        ref: "python3 migration/mapping/name_map.py --check (exit 0 against real inventory: 328 rows, zero unresolved collisions)"
        status: pass
    human_judgment: false
  - id: D2
    description: "depgraph.json resolves call edges from BOTH schema-qualified (3-part) and public-synonym (2-part) call shapes plus same-schema bare references, drops DBMS_*/UTL_* external builtins and self-loops, flags every statically-unresolvable reference as static_resolution=incomplete (never silently dropped), and yields a topologically sorted waves[] with SCC-condensed cycle groups"
    requirement: "INV-02"
    verification:
      - kind: unit
        ref: "migration/analyze/tests/test_depgraph.py (16 tests: both call shapes pinned against real edges, dynamic-SQL + unresolved-ref flagging, synthetic chain/cycle wave assertions, tamper-and-fail reconciliation)"
        status: pass
      - kind: integration
        ref: "python3 migration/analyze/depgraph.py --check (exit 0: 105 nodes, 94 edges [25 qualified, 66 synonym, 3 same_schema], 5 waves, 2 accepted cycle groups, 31 incomplete nodes incl. all 4 known dynamic-SQL bodies)"
        status: pass
    human_judgment: false
  - id: D3
    description: "One command (migration/regenerate.sh) regenerates all three artifacts in dependency order, runs every --check gate and the full test suite, and its --check mode provably fails when a checked-in artifact is hand-edited or stale (proven by tampering one byte of name-map.csv), without ever mutating ddl/src"
    requirement: "INV-02, INV-03"
    verification:
      - kind: integration
        ref: "bash migration/regenerate.sh (exit 0); bash migration/regenerate.sh --check (exit 0 clean, exit 1 after one-byte name-map.csv tamper, exit 0 again after restore); git status --porcelain ddl/ (empty after every run)"
        status: pass
    human_judgment: false

duration: 16min
completed: 2026-07-11
status: complete
---

# Phase 01 Plan 02: Name-Mapping SSOT + Dependency Graph Summary

**Built the name-mapping SSOT (`name-map.csv`, 328 rows, `package_in_name` flattening with a hard-failing collision gate) and the dependency graph (`depgraph.json`, 105 nodes / 94 edges resolved from both call shapes / 5 waves / 2 accepted cycle groups), wired behind `regenerate.sh` with a staleness gate proven to fail on a hand-edited artifact.**

## Performance

- **Duration:** ~16 min
- **Started:** 2026-07-11T21:37:51Z
- **Completed:** 2026-07-11T21:53:07Z
- **Tasks:** 3
- **Files modified:** 11 (10 new, 1 modified: README.md)

## Accomplishments

- `name_map.py`: builds one row per callable Oracle object from `inventory.json` alone (never re-parses `ddl/src`), applying the naming-rules table exactly (package routines get the package prefix; standalone procedures, triggers, and types do not; every trigger emits both a `trigger` row and a synthetic `trigger_function` row with a `_fn` suffix). Every row carries the owning package's public synonym (empty string, never a missing column, when none exists).
- Collision gate: classifies every duplicate `(pg_schema, pg_object_name)` group as a legitimate same-package overload (allowed, `is_overload=true`) or a hard collision (identical signature, or cross-package prefix ambiguity — hard-fails even when arg lists differ). Overrides are the only sanctioned resolution path; a stale override (matching no real collision) fails the gate exactly like an unresolved one. Proven capable of failing via 4 synthetic-fixture tests, not just asserted.
- `depgraph.py`: resolves `calls_out_raw` in precedence order (3-part against the package index → 2-part against the synonym index sourced from `name-map.csv` → 2-part against a same-schema package → `DBMS_`/`UTL_` external builtin, dropped → otherwise unresolved, recorded with text+line, never dropped). Self-loops are dropped. Every dynamic-SQL object from `inventory.json` plus every node with an unresolved reference is flagged `static_resolution: "incomplete"` with structured reasons, printed in full on every run.
- Tarjan SCC + condensation-based wave assignment: two genuine cycles were found and individually verified against source (not just trusted from the algorithm) — `MC.MONITORING ↔ MC.MONITORING_TICKET_PROCESSES` and the four core ticketing packages `TT.EVENT_INTERFACE`/`TT.OSAG_NOTIFY`/`TT.TICKET_INTERFACE`/`TT.UTIL` — both seeded into `known_cycles.json`; an unlisted cycle fails `--check`.
- `regenerate.sh`: one command regenerates the full chain (inventory → name-map → depgraph) and runs every gate plus both test suites; `--check` mode regenerates into a temp dir and diffs against the checked-in copies with `generated_at` normalized out (so a no-op re-run never fires) while `generator_version` is left in (so a version bump still forces a regenerate). Proved the gate can actually fail by tampering one byte of `name-map.csv`, confirming non-zero exit with the diff printed, then restoring it.
- `migration/README.md` extended with the full consumer contract (who reads which artifact for what), the naming-rules and collision-semantics tables verbatim, the cycle policy, and both standing warnings (`pg_kind` provisional pending Phase 3's XCUT-04; `static_resolution: "incomplete"` nodes need manual tracing, including known false positives from INSERT/SELECT column-list noise).
- 69 new unit tests total (15 name_map, 16 depgraph, on top of the 38 from plan 01 — full suite is 54 in `analyze/tests` + 15 in `mapping/tests` = 69 passing).

## Task Commits

1. **Task 1: Name-mapping SSOT — generator, overrides, and the collision gate** - `ea14c9e` (feat)
2. **Task 2: Dependency graph — resolve both call shapes, flag the unresolvable, sort into waves** - `c0680ca` (feat)
3. **Task 3: One-command regeneration with a staleness gate, and the consumer contract** - `57a8733` (feat)

_Both Task 1 and Task 2 were TDD: tests written first, confirmed failing (ModuleNotFoundError) before the corresponding module existed, then implementation added until green. Task 3 is a wiring/documentation task per the plan (no `tdd="true"` flag) and was verified via the plan's own regenerate/tamper/restore sequence._

## Files Created/Modified

- `migration/mapping/name_map.py` - name-map generator (default mode writes CSV; `--check` runs the collision gate)
- `migration/mapping/name-map.csv` - THE name-mapping SSOT (INV-03), 328 rows
- `migration/mapping/overrides.csv` - human-authored collision-resolution input; header only (no real collision needs one today)
- `migration/mapping/tests/test_name_map.py` - 15 unit tests
- `migration/analyze/depgraph.py` - dependency graph generator (default mode writes JSON+DOT; `--check` runs every graph gate)
- `migration/analyze/depgraph.json` - THE dependency graph + wave list (INV-02), 105 nodes / 94 edges / 5 waves
- `migration/analyze/depgraph.dot` - Graphviz rendering for human review (incomplete nodes styled distinctly)
- `migration/analyze/known_cycles.json` - human-authored input; the 2 accepted cycle groups, each with a verification note
- `migration/analyze/tests/test_depgraph.py` - 16 unit tests
- `migration/regenerate.sh` - one-command regenerate + validate + staleness gate
- `migration/README.md` - extended with the consumer contract, naming rules, collision semantics, cycle policy, and standing warnings

## Decisions Made

See `key-decisions` in frontmatter for full detail. Summary:

- Real corpus has exactly one name collision (the legitimate `change_label` overload) — `overrides.csv` ships empty (header only) rather than manufacturing a synthetic collision to exercise, since the gate's ability to hard-fail is already proven via synthetic in-memory fixtures per the plan's own instruction.
- Two genuine cycle groups exist and were individually verified against source before being accepted into `known_cycles.json`, not accepted merely because Tarjan's algorithm reported them.
- `depgraph.py` builds its synonym index from `name-map.csv` (not from raw `inventory.json` synonyms) so the malformed-synonym heuristic resolved in Task 1 is inherited rather than re-implemented — one source of truth for synonym attribution, per the SSOT rule.
- 31/105 nodes end up `static_resolution: "incomplete"` — 4 genuine dynamic-SQL objects plus 27 objects whose `calls_out_raw` includes lexer false positives (`INSERT INTO schema.table (...)` misread as a call). This is inherent to plan 01's calls_out_raw extraction and is explicitly documented in the README as a standing warning, not silently smoothed over.

## Deviations from Plan

None - plan executed exactly as written. The one place reality diverged from the plan's stated hazard (the MC.MONITORING/MONITORING_STATE-shape prefix collision not actually occurring in the real corpus, since the `*_STATE` packages happen to have no colliding public routines) was investigated and confirmed via direct inspection of `inventory.json`, then documented as a decision rather than treated as a plan defect — the collision gate itself is implemented in full per spec and proven to fail via synthetic fixtures.

## Issues Encountered

- The plan's own literal verify command for Task 1 (`python3 -m unittest discover ... 2>&1 | tail -3 | grep -q '^OK$'`) initially failed because two tests (14, 15) call `name_map.main()` directly, and `main()`'s informational `print()` output to stdout was interleaving after unittest's own stderr-buffered `OK` summary line when piped through `2>&1`. Fixed by wrapping those two `main()` calls in `contextlib.redirect_stdout` within the tests only — `main()`'s normal CLI behavior (printing to stdout when run directly by a human or by `regenerate.sh`) is unchanged. This is a test-harness fix, not a change to the generator's behavior or any gate's strictness.

## User Setup Required

None - no external service configuration required. Python 3.12 stdlib only, `jq` already present. `graphviz`/`dot` is not installed on this box; `depgraph.dot`'s validity was confirmed via a syntax check (balanced braces, correct `digraph`/closing-brace structure) rather than an actual render, per the plan's own fallback instruction.

## Next Phase Readiness

- `name-map.csv` and `depgraph.json` are both ready to be consumed by Phase 4 (wave-ordered translation) and Phase 5 (client regexp kit) exactly as specified in the README's consumer contract.
- Phase 2 (spec derivation) and Phase 4 inherit the 31-node `static_resolution: "incomplete"` list as their manual-tracing backlog — this is printed in full on every `depgraph.py` run and documented in the README so it is never silently lost.
- `regenerate.sh` is ready as the standing "is Phase 1 still valid" command for any later phase that touches `ddl/src`.
- No blockers.

---
*Phase: 01-inventory-foundation*
*Completed: 2026-07-11*

## Self-Check: PASSED

All 11 created/modified artifacts verified present on disk; all 4 commit hashes (ea14c9e, c0680ca, 57a8733, e24ef82) verified present in git log.
