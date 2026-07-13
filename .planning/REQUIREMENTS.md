# Requirements — MCDB Oracle → PostgreSQL Migration (v1)

## v1 Requirements

### Inventory & Foundation

- [x] **INV-01**: Complete inventory of all programmatic objects in `ddl/src` (48 package specs, 49 bodies, 2 procs, 8 triggers, 2 types) with per-object metadata (public routines, DBMS_*/UTL_* call sites, COMMIT/ROLLBACK presence, autonomous-transaction pragmas, package-level mutable state)
- [x] **INV-02**: Static dependency graph of cross-package/object calls driving a topological translation order (leaf packages first, waves)
- [x] **INV-03**: Single name-mapping table (Oracle `SCHEMA.PACKAGE.OBJECT` → PG `package_in_name` object name) as the sole source of truth for SQL refactoring, test naming, and client regexps

### Specifications

- [ ] **SPEC-01**: Behavioral specification derived per Oracle package by static analysis: routine signatures, semantics, side effects, error behavior, transaction behavior
- [x] **SPEC-02**: Every spec includes an explicit "assumptions/unresolved" section (no runtime Oracle baseline available)
- [x] **SPEC-03**: Per-package spec checklist applied uniformly: empty-string/NULL handling, SELECT INTO strictness, exception codes, package state, FUNCTION-vs-PROCEDURE determination

### Test Harness

- [ ] **HARN-01**: pgTAP test harness installed and runnable against the local PostgreSQL 17.10 instance (pg_prove runner, dedicated test database)
- [ ] **HARN-02**: Plain-SQL expected-output harness (pg_regress-style: sql/*.sql vs expected/*.out diffing) runnable alongside pgTAP
- [x] **HARN-03**: Shared test fixtures/seed data derived from `masterdata/` so tests run against realistic reference data
- [x] **HARN-04**: One-command test runner executing both harnesses and reporting per-package pass/fail
- [x] **HARN-05**: Every test traceable to the Oracle-derived spec (not to the PL/pgSQL implementation) to avoid circular verification

### Cross-cutting Semantics

- [ ] **XCUT-01**: Exception mapping table (Oracle error codes / -20NNN RAISE_APPLICATION_ERROR → PostgreSQL SQLSTATE convention) applied uniformly across all translations
- [ ] **XCUT-02**: `plog` re-implemented the PostgreSQL-idiomatic way — a non-transactional **UDP log shipper** to the telemetry stack (syslog-shaped payload; plog's existing levels 0–7 already match). No Oracle AQ queue, no autonomous-transaction emulation, no dblink/pg_background: a fire-and-forget datagram survives rollback inherently. OTel is the eventual destination; adapters can be added later if needed
- [ ] **XCUT-05**: The two remaining *table-writing* autonomous-transaction sites — `mcdb_checks_consistency.insert_result` and `tt_util.close_old_dev_tickets` — each get an explicit recorded decision: re-emit as a UDP telemetry event, accept transactional semantics, or (last resort) dblink
- [ ] **XCUT-06**: `plog.AuditUsage` and its ~177 call sites are **dropped, not translated** — the feature is unused (nothing reads `osag.plsql_audit`; `plog` is its only writer), and its arguments are Oracle inquiry directives (`$$PLSQL_UNIT_OWNER`/`$$PLSQL_UNIT_TYPE`/`$$PLSQL_UNIT`) with no PostgreSQL equivalent. Delete the call sites during translation rather than stubbing them; drop `plsql_audit` from the migrated DDL (`ddl/migrated/tables/tables.pg.sql`)
- [ ] **XCUT-03**: DBMS_*/UTL_* replacement reference table (orafce coverage vs native rewrite) decided once and applied consistently
- [ ] **XCUT-04**: Transaction-semantics audit: every Oracle routine that COMMITs/ROLLBACKs identified and mapped to PG PROCEDURE (not FUNCTION) with call-chain implications documented

### Translation

- [ ] **TRAN-01**: All 48 packages translated to valid PL/pgSQL (orafce permitted) in dependency-graph wave order, one file per package
- [ ] **TRAN-02**: `package_in_name` naming convention applied (package prefix on object names; schema layout unchanged from Oracle)
- [ ] **TRAN-03**: All cross-references between translated objects refactored to the new names via the name-mapping table
- [ ] **TRAN-04**: Standalone procedures (2) and triggers (8) translated and tested
- [ ] **TRAN-05**: Types (2) translated as needed by dependent code
- [ ] **TRAN-06**: ora2pg output (`pg_migration/output/package_in_name/`) used as raw material/checklist only — never shipped unverified

### Verification

- [ ] **VER-01**: Every translated package passes its pgTAP and expected-output test suites derived from its spec on the local Postgres instance
- [ ] **VER-02**: Test coverage: every public routine of every package has at least one spec-derived test

### Container

- [ ] **CONT-01**: Runnable container database built from scratch: extensions (orafce, pgTAP) → schema DDL → masterdata → translated code, in dependency order
- [ ] **CONT-02**: Full test suites pass inside the freshly built container (systematic catch-all for dangling references and DDL-ordering issues)

### Client Migration Aids

- [ ] **CLI-01**: Regexp list generated from the name-mapping table for rectifying package & object name references in client code (Perl/Java), with application notes

## v2 Requirements

Deferred to a later milestone:

- **JOBS-01**: Scheduler jobs (`ddl/src/jobs`, 20 files) replaced with pg_cron or equivalent
- **QUEUE-01**: AQ queues (`ddl/src/queues`) replaced with LISTEN/NOTIFY or queue tables
- **MVIEW-01**: Materialized view logs / mviews (`ddl/src/mlog`, `ddl/src/mviews`) re-architected for PostgreSQL
- **ORA-01**: Oracle 19c container stood up from `ddl/` + `masterdata/` for empirical golden-master validation of the static-analysis specs

## Out of Scope

- Applying the client-code regexps to actual Perl/Java codebases — we deliver the regexp list; client teams apply it
- Full PL/SQL emulation layers or generic translation frameworks — they hide the per-package decisions (exception mapping, transaction semantics, state) that must be explicit
- Hand-simulating "what Oracle would return" as a substitute for behavioral diffing — specs are static-analysis-derived and marked with assumptions instead
- Data migration tooling/ETL — this milestone is code + schema + masterdata bootstrap, not production data movement

## Traceability

<!-- Filled by roadmap creation: REQ-ID → Phase mapping -->

| REQ-ID | Phase | Status |
|--------|-------|--------|
| INV-01 | Phase 1 — Inventory & Foundation | Complete |
| INV-02 | Phase 1 — Inventory & Foundation | Complete |
| INV-03 | Phase 1 — Inventory & Foundation | Complete |
| SPEC-02 | Phase 2 — Spec Method, Test Harness & Pilot | Complete |
| SPEC-03 | Phase 2 — Spec Method, Test Harness & Pilot | Complete |
| HARN-01 | Phase 2 — Spec Method, Test Harness & Pilot | Pending |
| HARN-02 | Phase 2 — Spec Method, Test Harness & Pilot | Pending |
| HARN-03 | Phase 2 — Spec Method, Test Harness & Pilot | Complete |
| HARN-04 | Phase 2 — Spec Method, Test Harness & Pilot | Complete |
| HARN-05 | Phase 2 — Spec Method, Test Harness & Pilot | Complete |
| XCUT-01 | Phase 3 — Cross-cutting Semantics | Pending |
| XCUT-02 | Phase 3 — Cross-cutting Semantics | Pending |
| XCUT-03 | Phase 3 — Cross-cutting Semantics | Pending |
| XCUT-04 | Phase 3 — Cross-cutting Semantics | Pending |
| XCUT-05 | Phase 3 — Cross-cutting Semantics | Pending |
| XCUT-06 | Phase 3 — Cross-cutting Semantics | Pending |
| SPEC-01 | Phase 4 — Wave-Ordered Translation & Verification | Pending |
| TRAN-01 | Phase 4 — Wave-Ordered Translation & Verification | Pending |
| TRAN-02 | Phase 4 — Wave-Ordered Translation & Verification | Pending |
| TRAN-03 | Phase 4 — Wave-Ordered Translation & Verification | Pending |
| TRAN-04 | Phase 4 — Wave-Ordered Translation & Verification | Pending |
| TRAN-05 | Phase 4 — Wave-Ordered Translation & Verification | Pending |
| TRAN-06 | Phase 4 — Wave-Ordered Translation & Verification | Pending |
| VER-01 | Phase 4 — Wave-Ordered Translation & Verification | Pending |
| VER-02 | Phase 4 — Wave-Ordered Translation & Verification | Pending |
| CONT-01 | Phase 5 — Container Build & Client Migration Aids | Pending |
| CONT-02 | Phase 5 — Container Build & Client Migration Aids | Pending |
| CLI-01 | Phase 5 — Container Build & Client Migration Aids | Pending |

**Coverage:** 28/28 v1 requirements mapped to exactly one phase. No orphans, no duplicates.

**Mapping notes:**

- **SPEC-01** (behavioral spec per Oracle package) is assigned to Phase 4, where it completes across all 48 packages. Phase 2 produces pilot specs as instances of the format defined by SPEC-02/SPEC-03.
- **TRAN-01** completes in Phase 4. Pilot translations in Phase 2 exist to prove the harness and spec method, not to claim translation coverage.
