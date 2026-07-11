---
phase: 01-inventory-foundation
verified: 2026-07-11T00:00:00Z
status: passed
score: 4/4 must-haves verified
behavior_unverified: 0
overrides_applied: 0
---

# Phase 1: Inventory & Foundation Verification Report

**Phase Goal:** The migration has machine-readable ground truth — every programmatic object inventoried, a dependency graph that dictates translation wave order, and one name-mapping table every downstream consumer reads from
**Verified:** 2026-07-11
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths (ROADMAP Success Criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Inventory covers ALL programmatic objects in `ddl/src` with per-object metadata | ✓ VERIFIED | `inventory.json`: 105 objects (48 packages + 2 procedures + 53 triggers + 2 types), independently reconciled by orchestrator. `--check` proven to fail on removed object. |
| 2 | Dependency graph yields a topologically sorted wave list (leaf packages first) | ✓ VERIFIED | Independently re-derived from `depgraph.json`: 5 waves, sizes [44,32,18,8,3]=105. `OSAG.OSAG_PLOG` (called by 48 inbound edges, a true leaf — calls nothing itself) sits in wave 1; its heaviest caller `AUTH.OSAG_AUTH` sits in wave 4. Programmatic sweep of all 94 edges found **zero** edges violating `wave(callee) < wave(caller)` outside declared cycle groups. |
| 3 | Name-mapping table covers every object, ZERO collisions, single SSOT for 3 consumers | ✓ VERIFIED | 328 rows = 218 package routines + 53 triggers + 53 trigger_functions + 2 procedures + 2 types (exact arithmetic reconciliation, independently computed). `oracle_synonym` column populated for 87/328 rows spanning all 12 packages that declare a public synonym — including `OSAG_PLOG` (13 rows, synonym=`plog`), confirming the SSOT genuinely carries what client Perl/Java code actually calls (`plog.Err(...)`), not just the schema-qualified form. `--check` exits 0, zero unresolved collisions. |
| 4 | Statically-unresolvable call edges (EXECUTE IMMEDIATE, DBMS_SQL) are explicitly FLAGGED, not omitted | ✓ VERIFIED | All 4 known dynamic-SQL objects independently confirmed flagged with concrete line-numbered `reasons[]` matching real EXECUTE IMMEDIATE/DBMS_SQL sites in source (spot-checked against `ddl/src/pkgb/mcdb_checks_consistency.sql` etc.). 31/105 nodes total flagged incomplete; the extra 27 (lexer false positives from INSERT/SELECT column lists) are explicitly documented in `migration/README.md`'s standing warning rather than hidden. |

**Score:** 4/4 truths verified (0 present, behavior-unverified)

### Focused Adversarial Checks (beyond orchestrator's pre-verification)

| # | Check | Result |
|---|-------|--------|
| 1 | Is `name-map.csv` genuinely usable as SSOT for SQL rewriting + test naming + client regexps? | **Yes.** `oracle_synonym` is populated wherever a public synonym exists (12 packages, 87 rows) — e.g. the `OSAG_PLOG.Err` row carries `oracle_synonym=plog`, giving Phase 5 everything needed to build a regexp matching the real client call shape `plog.Err(...)`, not just the schema-qualified `OSAG.OSAG_PLOG.Err`. Packages without a synonym correctly show an empty (not missing) column. |
| 2 | Are BOTH call shapes (schema-qualified AND public-synonym) really resolved into graph edges? | **Yes, verified with real data.** `OSAG.OSAG_PLOG` — the package called via public synonym from nearly every error handler in the codebase — has **48 inbound edges**, all `via=synonym`. Corpus-wide edge breakdown: 66 synonym, 25 qualified, 3 same_schema (94 total). If synonym resolution had silently produced zero edges, this would have been the single most damaging undetected defect in the phase; it did not. |
| 3 | Is the wave order actually correct (leaves first, no backward edges)? | **Yes.** `OSAG.OSAG_PLOG` (zero outgoing in-scope edges — a true leaf) lands in wave 1; its caller `AUTH.OSAG_AUTH` lands in wave 4. A full programmatic scan of all 94 edges against node wave numbers found zero edges where `wave(callee) >= wave(caller)`, except within declared cycle groups (where this is expected and correct). |
| 4 | Are the 2 "accepted" cycle groups in `known_cycles.json` real mutual recursion, not parser artifacts? | **Yes, confirmed by direct source inspection (not just trusting the JSON note).** `mc_monitoring.sql:536/585/597` calls `monitoring_ticket_processes.new_event`; `mc_monitoring_ticket_processes.sql:222-223` calls back `mc.monitoring.get_sang_status_from_state`/`get_mode_from_state` — genuine 2-way cycle. The 4-member TT cycle (`EVENT_INTERFACE`/`OSAG_NOTIFY`/`TICKET_INTERFACE`/`UTIL`) was independently traced via grep across all four source bodies: `ticket_interface`↔`event_interface` bidirectional calls, both →`util`, all three →`osag_notify`, and `osag_notify`→`ticket_interface` closing the loop. Both cycle groups are real. |
| 5 | Coverage arithmetic: 105 objects but 328 name-map rows — is every object represented? | **Yes, exact reconciliation performed independently.** 218 package public routines (from 48 packages) + 53 triggers + 53 synthetic trigger_function rows (one per trigger, PG needs a function backing every trigger) + 2 procedures + 2 types = 328. Verified bidirectionally: every package with ≥1 public routine appears in the name map (zero missing); the 6 packages with zero public routines (`*_STATE` packages, `OSIXINFO.OSAG_EXCEPTIONS`) are explicitly printed by `--check` as `packages with zero public routines`, not silently dropped. |

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `migration/analyze/inventory.json` | 105-object inventory with per-object metadata | ✓ VERIFIED | 105 objects confirmed; all required keys present (routines, has_commit, calls_out_raw, static_resolution, etc.) |
| `migration/analyze/depgraph.json` | 105-node graph, wave list, cycle groups | ✓ VERIFIED | 105 nodes, 94 edges, 5 waves partition exactly, 2 cycle groups both confirmed genuine |
| `migration/mapping/name-map.csv` | 328-row SSOT, zero collisions | ✓ VERIFIED | 328 rows, exact arithmetic reconciliation, `--check` exits 0 |
| `migration/known_cycles.json` / `overrides.csv` | Human-authored gate inputs | ✓ VERIFIED | Present, correctly seeded (2 cycle groups; empty overrides since no real collision exists) |
| `migration/regenerate.sh` | One-command regen + staleness gate | ✓ VERIFIED | Re-ran independently: `regenerate.sh --check` exits 0, all 69 unit tests pass, no drift |
| `migration/README.md` | Consumer contract for all 3 artifacts | ✓ VERIFIED | Documents who-reads-what, naming rules, collision semantics, cycle policy, standing warnings (pg_kind provisional; incomplete nodes need manual tracing) |

### Key Link Verification

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| `inventory.json.calls_out_raw` | `depgraph.json` edges | resolution precedence (qualified→synonym→same_schema→external→unresolved) | ✓ WIRED | 94 edges resolved; both `via=qualified` (25) and `via=synonym` (66) present and non-trivial |
| `name-map.csv.oracle_synonym` | `depgraph.py` synonym index | depgraph.py builds its synonym table FROM name-map.csv, not raw inventory | ✓ WIRED | Confirmed: 48 inbound edges to OSAG_PLOG all resolve via this exact path |
| `depgraph.json.waves[]` | Phase 4 (future consumer) | documented contract in README | ✓ WIRED (contract only — Phase 4 not yet built) | README explicitly states Phase 4 reads waves[] for batch order |
| `name-map.csv` | Phase 5 client regexp kit (future consumer) | documented contract in README | ✓ WIRED (contract only) | `oracle_synonym` + `oracle_object` columns are sufficient to mechanically generate a synonym-form regexp; `oracle_schema`+`oracle_package`+`oracle_object` sufficient for the qualified-form regexp |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Full regeneration + staleness gate | `bash migration/regenerate.sh --check` | 69/69 unit tests OK; "the whole Phase 1 foundation is valid and not stale" | ✓ PASS |
| Name-map collision gate | `python3 migration/mapping/name_map.py --check` | "328 rows, zero unresolved collisions" | ✓ PASS |
| OSAG_PLOG inbound edges (synonym resolution) | ad-hoc Python against `depgraph.json` | 48 inbound edges, all `via=synonym` | ✓ PASS |
| Wave-ordering invariant (no backward edges) | ad-hoc Python scan of all 94 edges vs. node waves | 0 violations outside cycle groups | ✓ PASS |
| Cycle-group genuineness | `grep` against real `ddl/src/pkgb/*.sql` source | Both cycle groups confirmed as real mutual calls | ✓ PASS |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|--------------|--------|----------|
| INV-01 | 01-01-PLAN.md | Complete inventory with per-object metadata | ✓ SATISFIED | 105 objects, all metadata fields present, `--check` provably fails on omission |
| INV-02 | 01-02-PLAN.md | Static dependency graph → topological wave order | ✓ SATISFIED | 105 nodes, 94 edges (both shapes), 5 waves, verified wave-ordering invariant holds corpus-wide |
| INV-03 | 01-02-PLAN.md | Single name-mapping SSOT, zero collisions, 3-consumer contract | ✓ SATISFIED | 328 rows, exact bidirectional coverage, synonym column populated and load-bearing, zero collisions |

No orphaned requirements found for Phase 1 in REQUIREMENTS.md.

### Anti-Patterns Found

None. Scanned all generator scripts (`inventory.py`, `plsql_lex.py`, `depgraph.py`, `name_map.py`, `regenerate.sh`) for `TBD`/`FIXME`/`XXX`/`TODO`/`HACK`/`PLACEHOLDER` markers — zero matches.

### Human Verification Required

None. All four success criteria and all five focused adversarial checks were verified programmatically against real artifact data and real Oracle source, not by re-reading SUMMARY.md claims.

### Gaps Summary

No gaps. All 4 ROADMAP success criteria are substantively met, not merely met in letter:

- The name map's `oracle_synonym` column is genuinely populated and load-bearing — it is not a hollow column that technically exists but can't drive Phase 5's client regexps.
- Synonym-shaped call resolution is proven with real data (48 inbound edges to the most-called package in the codebase), not just asserted by the generator's own unit tests.
- The wave order is verified correct end-to-end: leaf packages are in wave 1, callers are strictly later, and zero edges violate this outside declared cycles.
- Both accepted cycle groups were independently confirmed as genuine mutual recursion by reading the actual Oracle source, not accepted on the SUMMARY's word.
- The 105-vs-328 count discrepancy is fully explained and reconciles exactly (218 routines + 53 triggers + 53 trigger-functions + 2 procs + 2 types = 328), with no object silently dropped.

---

_Verified: 2026-07-11_
_Verifier: Claude (gsd-verifier)_
