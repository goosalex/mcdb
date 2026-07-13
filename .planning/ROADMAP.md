# Roadmap: MCDB Oracle → PostgreSQL Migration

## Overview

This milestone moves MCDB's programmatic layer (48 packages, 2 standalone procedures, 8 triggers, 2 types) from Oracle 19c PL/SQL to PostgreSQL 17 PL/pgSQL, spec-first. The journey starts by turning `ddl/src` into machine-readable ground truth — an object inventory, a dependency graph that dictates translation order, and a single name-mapping table. That foundation feeds a proving run: the dual test harness (pgTAP + expected-output) plus the spec format, validated end-to-end on a small pilot batch. Decisions that span every package — exception codes, logging (`plog` becomes a non-transactional UDP shipper to the telemetry stack, dropping Oracle's AQ queue and autonomous transaction entirely), DBMS_*/UTL_* replacements, COMMIT/ROLLBACK semantics — are then settled once so translation never re-litigates them. Only then does bulk translation run, wave by wave in dependency order, each package specified from Oracle source and verified green against tests derived from that spec (never from ora2pg output). The milestone closes when a container built from scratch — extensions, DDL, masterdata, translated code — passes the full suite, and the name-mapping table has been turned into a regexp kit for client teams.

## Phases

**Phase Numbering:**

- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: Inventory & Foundation** - Object inventory, dependency graph with wave order, name-mapping SSOT (completed 2026-07-11)
- [ ] **Phase 2: Spec Method, Test Harness & Pilot** - Dual harness running and the spec-first method proven on a pilot batch
- [ ] **Phase 3: Cross-cutting Semantics** - Exceptions, plog as a UDP log shipper, DBMS_* replacements, transaction audit — decided once
- [ ] **Phase 4: Wave-Ordered Translation & Verification** - All packages, procs, triggers, types specified, translated, and green
- [ ] **Phase 5: Container Build & Client Migration Aids** - From-scratch runnable container, green suite inside it, client rename regexps

## Phase Details

### Phase 1: Inventory & Foundation

**Goal**: The migration has machine-readable ground truth — every programmatic object inventoried, a dependency graph that dictates translation wave order, and one name-mapping table every downstream consumer reads from
**Depends on**: Nothing (first phase)
**Requirements**: INV-01, INV-02, INV-03
**Success Criteria** (what must be TRUE):

  1. An inventory artifact covers all programmatic objects in `ddl/src` (48 package specs, 49 bodies, 2 procs, 8 triggers, 2 types), each with its public routines, DBMS_*/UTL_* call sites, COMMIT/ROLLBACK presence, autonomous-transaction pragmas, and package-level mutable state
  2. A dependency graph artifact exists and yields a topologically sorted wave list (leaf packages first) — later phases consume this as their batch order, never file-alphabetical order
  3. A name-mapping table (Oracle `SCHEMA.PACKAGE.OBJECT` → PG `package_in_name` name) covers every object with zero collisions, and is the single artifact that SQL refactoring, test naming, and client regexps all read from
  4. Objects whose call edges cannot be resolved statically (EXECUTE IMMEDIATE, DBMS_SQL) are explicitly flagged in the graph rather than silently omitted

**Plans**: 2/2 plans complete

- [x] 01-01-PLAN.md — Oracle source lexer + object inventory (`migration/analyze/inventory.json`), reconciled against files on disk (INV-01)
- [x] 01-02-PLAN.md — Name-mapping SSOT with collision gate + dependency graph with wave order, behind one regeneration command (INV-02, INV-03)

**Research**: Standard pattern (DAG extraction + topological sort) — no deeper research needed. Gap to close during the phase: verify graph completeness for dynamic-SQL packages; validate name map for zero collisions.

### Phase 2: Spec Method, Test Harness & Pilot

**Goal**: The spec-first methodology is proven end-to-end at small scale — the dual harness runs against local Postgres, specs follow a uniform checklist, and tests trace to Oracle-derived specs rather than to the translation
**Depends on**: Phase 1 (pilot batch is drawn from wave 1 of the dependency graph; test names come from the name map)
**Requirements**: SPEC-02, SPEC-03, HARN-01, HARN-02, HARN-03, HARN-04, HARN-05
**Success Criteria** (what must be TRUE):

  1. A pgTAP suite runs via pg_prove against a dedicated test database on the local PostgreSQL 17.10 instance, and a plain-SQL expected-output suite (sql/*.sql vs expected/*.out diffing) runs alongside it
  2. One command runs both harnesses and reports per-package pass/fail
  3. Shared fixtures seeded from `masterdata/` let tests execute against realistic reference data
  4. Pilot packages (3-5, drawn from wave 1) each have a spec that applies the uniform checklist — empty-string/NULL handling, SELECT INTO strictness, exception codes, package state, FUNCTION-vs-PROCEDURE — and carries an explicit "assumptions / unresolved" section
  5. Every pilot test cites the spec clause it verifies, and the harness demonstrably goes red-before / green-after on the pilot batch — proving the method before it is applied at scale

**Plans**: 6/13 plans executed

- [x] 02-01-PLAN.md — Dual harness foundation: pgTAP+pg_prove, expected-output diffing, one-command runner, disposable test DBs, and the `redgreen.sh` gate — proven falsifiable (HARN-01, HARN-02, HARN-04)
- [x] 02-02-PLAN.md — Spec template + uniform 5-dimension checklist + the three anti-circularity linters (spec_lint, trace_lint, provenance_lint) (SPEC-02, SPEC-03, HARN-05)
- [x] 02-03-PLAN.md — Test schema from `ddl/migrated/` with ora2pg errors surfaced and fixed, sequences ported, masterdata fixtures, plog stub (HARN-03)
- [x] 02-04-PLAN.md — Spec + tests (RED): MSS.OSAG_DBPROP, AUTH.OSAG_AUTH, TT.UTIL (SPEC-02, SPEC-03, HARN-05)
- [x] 02-05-PLAN.md — Spec + tests (RED): TT.OSAG_NOTIFY — all 30 SELECT INTO sites (SPEC-02, SPEC-03, HARN-05)
- [x] 02-06-PLAN.md — Spec + tests (RED): TT.EVENT_INTERFACE + the dynamic-SQL manual trace (SPEC-02, SPEC-03, HARN-05)
- [ ] 02-07-PLAN.md — Spec: TT.TICKET_INTERFACE — all 38 routines, all 77 SELECT INTO sites (SPEC-02, SPEC-03)
- [ ] 02-08-PLAN.md — Tests (RED): TT.TICKET_INTERFACE — every routine cited to a clause (HARN-05, SPEC-03)
- [ ] 02-09-PLAN.md — Translate: MSS.OSAG_DBPROP, AUTH.OSAG_AUTH, TT.UTIL → green (HARN-04, HARN-05)
- [ ] 02-10-PLAN.md — Translate: TT.OSAG_NOTIFY → green (HARN-04, HARN-05)
- [ ] 02-11-PLAN.md — Translate: TT.EVENT_INTERFACE incl. the dynamic-SQL site → green (HARN-04, HARN-05)
- [ ] 02-12-PLAN.md — Translate: TT.TICKET_INTERFACE — all 38 routines → green (HARN-04, HARN-05)
- [ ] 02-13-PLAN.md — Integration: one command, whole-pilot red→green + mutation check, PHASE2-FINDINGS + METHOD-REVIEW (all 7)

**Research**: Needs deeper research — dynamic SQL (DBMS_SQL, EXECUTE IMMEDIATE) in pilot packages may resist static spec derivation and require manual tracing; no live-Oracle baseline is available to fall back on. *Skipped by user decision; handled instead by plan 02-06's mandatory manual trace, which may return an explicit `UNRESOLVED — DO NOT GUESS` verdict.*

**Scope note (planning, 2026-07-12):** The roadmap assumed "3-5 small packages drawn from wave 1". The user overrode that: wave 1 is dominated by 0-routine `*_STATE` constants packages that would prove nothing. The locked pilot is 4 real packages (`MSS.OSAG_DBPROP`, `TT.EVENT_INTERFACE`, `TT.TICKET_INTERFACE` with **all 38 routines**, `AUTH.OSAG_AUTH`) plus 3 transitive dependencies they cannot run without (`OSAG.OSAG_PLOG` — stubbed; `TT.OSAG_NOTIFY`; `TT.UTIL`). That is **7 packages, ~76 public routines, ~6,000 lines of Oracle** — roughly 4x the assumed size, hence 13 plans rather than 3.

### Phase 3: Cross-cutting Semantics

**Goal**: Every decision that spans packages is made once, written down, and applied uniformly — so per-package translation never re-decides exception codes, logging, Oracle built-ins, or transaction shape
**Depends on**: Phase 2 (decisions are exercised against the pilot batch and its tests)
**Requirements**: XCUT-01, XCUT-02, XCUT-03, XCUT-04, XCUT-05, XCUT-06
**Success Criteria** (what must be TRUE):

  1. An exception mapping table maps every Oracle error code and `-20NNN` RAISE_APPLICATION_ERROR found in the Phase 1 inventory to a PostgreSQL SQLSTATE, and the pilot translations already use it
  2. `plog` is re-implemented as a **UDP log shipper** — the Oracle AQ queue (`MCDB_MONITOR.plog_messages`) and the autonomous transaction are both gone, replaced by a fire-and-forget datagram to the telemetry sink. Proven by a rollback-survival test: a message logged on an error path is observed at the collector *after* the calling transaction rolls back. The translated logging path contains no `dblink`, no `pg_background`, and no queue table
  3. The two remaining *table-writing* autonomous-transaction sites (`mcdb_checks_consistency.insert_result`, `tt_util.close_old_dev_tickets`) each have an explicit recorded decision — UDP telemetry event, accept transactional semantics, or dblink as a last resort — and a test for the chosen behavior
  4. `plog.AuditUsage` is dropped: zero `AuditUsage` call sites remain in the translated code (~177 deleted, not stubbed), and `plsql_audit` is gone from the migrated DDL. The feature is unused — nothing reads the table — so it is removed rather than ported
  5. A DBMS_*/UTL_* replacement reference records one decision per family (orafce coverage vs native rewrite), covering every call site the inventory found — no family is left to per-package improvisation
  6. A transaction-semantics audit lists every Oracle routine that COMMITs or ROLLBACKs, maps each to a PG PROCEDURE (not FUNCTION), and documents the call-chain implications for its callers

**Plans**: 2 plans
**Research**: Needs deeper research — decide *how* the database emits UDP (untrusted PL such as `plperlu`/`plpython3u`, needing no C build, vs a small C extension) and confirm the payload shape; syslog RFC 5424 maps 1:1 onto plog's existing 0–7 levels, and the sink should be able to front an OTel collector later without changing the in-database emitter. Do NOT benchmark dblink vs pg_background — that path is dropped for logging. Each DBMS_*/UTL_* replacement must be validated against a real call site, not assumed from orafce docs.

### Phase 4: Wave-Ordered Translation & Verification

**Goal**: Every package, standalone procedure, trigger, and type is specified from Oracle source, translated to PL/pgSQL, and green against tests derived from that spec — worked through in dependency-wave order
**Depends on**: Phase 3 (exception map, plog, DBMS_* decisions, and transaction rules are prerequisites for every package translated here)
**Requirements**: SPEC-01, TRAN-01, TRAN-02, TRAN-03, TRAN-04, TRAN-05, TRAN-06, VER-01, VER-02
**Success Criteria** (what must be TRUE):

  1. Each of the 48 packages has a behavioral spec derived by static analysis of `ddl/src/pkg` + `ddl/src/pkgb` — routine signatures, semantics, side effects, error behavior, transaction behavior — and a PL/pgSQL translation (one file per package) using the `package_in_name` convention
  2. Translation proceeds in the wave order from the Phase 1 dependency graph (leaves first): when a wave is translated, every object it calls already exists under its new name, so cross-reference rewrites resolve and "object not found" cannot mask a real error
  3. The 2 standalone procedures, 8 triggers, and 2 types are translated and covered by tests alongside the packages that depend on them
  4. Every public routine of every package has at least one spec-derived test, and all pgTAP + expected-output suites pass on the local Postgres instance
  5. No ora2pg output ships unverified — `pg_migration/output/package_in_name/` is used as raw material and a completeness checklist, with each translation reviewed against its spec before it counts as done

**Plans**: 4 plans
**Research**: Escalation trigger — if any package is found where a FUNCTION issues COMMIT/ROLLBACK, re-scope it as a PROCEDURE with OUT parameters and propagate the change to its callers. Specs with unresolved dynamic SQL in performance-sensitive paths get flagged for manual review rather than guessed.

### Phase 5: Container Build & Client Migration Aids

**Goal**: The whole database stands up from scratch in a container and passes everything, and client teams receive a mechanical rename kit rather than a migration narrative
**Depends on**: Phase 4
**Requirements**: CONT-01, CONT-02, CLI-01
**Success Criteria** (what must be TRUE):

  1. One command builds a PostgreSQL 17 container database from scratch in dependency order: extensions (orafce, pgTAP) → schema DDL → masterdata → translated code
  2. The full dual test suite runs inside the freshly built container and is green — this from-scratch build is the systematic catch-all that surfaces dangling references and DDL-ordering issues
  3. A regexp list, generated mechanically from the name-mapping table (not hand-authored), rewrites package and object name references in client code (Perl/Java), and ships with application notes plus an explicit list of non-mechanical renames that need manual client review

**Plans**: 2 plans
**Research**: Standard patterns (container bootstrap, mechanical regexp generation) — no deeper research needed.

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Inventory & Foundation | 2/2 | Complete   | 2026-07-11 |
| 2. Spec Method, Test Harness & Pilot | 6/13 | In Progress|  |
| 3. Cross-cutting Semantics | 0/2 | Not started | - |
| 4. Wave-Ordered Translation & Verification | 0/4 | Not started | - |
| 5. Container Build & Client Migration Aids | 0/2 | Not started | - |

## Requirement Coverage

All 28 v1 requirements mapped to exactly one phase.

| Phase | Requirements | Count |
|-------|--------------|-------|
| 1 | INV-01, INV-02, INV-03 | 3 |
| 2 | SPEC-02, SPEC-03, HARN-01, HARN-02, HARN-03, HARN-04, HARN-05 | 7 |
| 3 | XCUT-01, XCUT-02, XCUT-03, XCUT-04, XCUT-05, XCUT-06 | 6 |
| 4 | SPEC-01, TRAN-01, TRAN-02, TRAN-03, TRAN-04, TRAN-05, TRAN-06, VER-01, VER-02 | 9 |
| 5 | CONT-01, CONT-02, CLI-01 | 3 |
| **Total** | | **28/28** |

**Mapping notes:**

- **SPEC-01** (behavioral spec per Oracle package) is assigned to Phase 4, where it completes for all 48 packages. Phase 2 produces pilot specs as instances of the format established by SPEC-02/SPEC-03; Phase 4 finishes the set wave by wave.
- **TRAN-01** likewise completes in Phase 4. The pilot translations in Phase 2 exist to prove the harness and spec method, not to claim translation coverage.
