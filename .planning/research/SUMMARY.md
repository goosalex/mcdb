# Project Research Summary

**Project:** Oracle 19c → PostgreSQL 17+ PL/SQL Code Migration  
**Domain:** Database code migration, static-analysis-first methodology  
**Researched:** 2026-07-10  
**Confidence:** MEDIUM (technology stack verified via primary sources; migration methodology cross-checked against industry practices; spec-first approach grounded in project's own requirements and repo state)

## Executive Summary

This milestone translates 48 Oracle packages, 2 procedures, 8 triggers, and 2 types from PL/SQL to PL/pgSQL, targeting PostgreSQL 17.10, without a live Oracle instance for baseline comparison. The core approach is **spec-first**: derive behavioral specs independently from the Oracle source (using static analysis + ora2pg as raw material), write dual-harness tests (pgTAP + expected-output regression) from those specs, then translate and verify against those tests—not the other way around. This methodology is critical because ora2pg's known limitation is mistranslation of procedural logic; trusting its output as a starting point inverts the verification burden and is explicitly anti-recommended by this project's own architecture notes.

The technology stack is largely determined: PostgreSQL 17.10 (already installed), pgTAP 1.3.4 + pg_prove for in-database testing, orafce 4.16.7 for Oracle built-in compatibility (allowed by project constraints), ora2pg 25.0 as a draft-generation tool (not a final translator), and Docker + Compose for reproducible environment management. The roadmap should be driven by a **dependency graph** computed during Stage 1 (leaf packages first, high-dependency hubs last) rather than file alphabetical or Liquibase include order, to surface implicit dependencies early and structure translation in independent waves.

The top four risks are: (1) **Autonomous transactions — substantially defused by project decision.** The original research called for emulating `PRAGMA AUTONOMOUS_TRANSACTION` via dblink/pg_background so `plog` writes survive rollback. **Rejected.** `plog` is re-implemented as a non-transactional **UDP log shipper** to the telemetry stack (OTel-bound; adapters later if needed) — rollback-survival is inherent to a fire-and-forget datagram, so no emulation, no queue, no dblink. What remains is much smaller: `plog.AuditUsage` (a table `UPDATE` despite its package, ~177 call sites) is **deleted, not ported** — the feature is unused, nothing reads `osag.plsql_audit` — leaving just two *table-writing* autonomous sites (`mcdb_checks_consistency.insert_result`, `tt_util.close_old_dev_tickets`) that each need an explicit recorded decision, not a blanket workaround; (2) **Exception handling** (Oracle's numeric `-20NNN` codes don't map 1:1 to PostgreSQL SQLSTATE; requires an explicit, consistently-applied mapping table); (3) **SELECT INTO STRICT semantics** (Oracle raises `NO_DATA_FOUND` by default; PostgreSQL doesn't without explicit `STRICT`—must be decided per statement, not blanket-applied); (4) **Package-level session state** (Oracle packages are scoped to a session; PostgreSQL's `package_in_name` flattening loses this unless explicitly replaced with GUCs/temp tables—must be audited per package).

## Key Findings

### Recommended Stack

The technology stack is well-established and version-pinned for PostgreSQL 17:

**Core technologies:**
- **PostgreSQL 17.10** (target database, already installed locally) — fixed by project constraint
- **pgTAP 1.3.4** (in-database unit testing) — de facto standard for PostgreSQL, explicitly tested against PG 17.0+; provides xUnit-style assertions that run inside the same transactional context as code under test
- **pg_prove** (pgTAP test runner) — produces TAP/JUnit-style reports and CI-ready exit codes; standard companion to pgTAP
- **orafce 4.16.7** (Oracle built-in compatibility shim) — provides NVL, dbms_output, partial dbms_sql, string/date functions; explicitly allowed and reduces translation friction, but is a bridge only (not full compatibility)
- **ora2pg 25.0** (raw material generator) — already used for existing artifacts; CLI mode supports offline single-file translation without live Oracle connection; does NOT produce final code
- **Docker + Compose** (environment reproducibility) — pins exact versions; automates seed/masterdata loading

**What NOT to use:**
- Trusting ora2pg's PL/SQL→PL/pgSQL output as final code (confirmed mistranslations exist)
- Blanket "add STRICT to all SELECT INTO" without per-statement review
- Assuming orafce gives full Oracle compatibility (dbms_sql is intentionally partial; version upgrades can change function volatility)

### Expected Features

This is a **migration milestone**; "features" are the work products and assurances a trustworthy migration must produce.

**Must have (table stakes):**
- Per-package behavioral spec (signatures, side effects, exceptions, transaction semantics) — ground truth independent of ora2pg
- Dependency-ordered translation (derived from static analysis, never file-alphabetical)
- Exception/error-code mapping table (Oracle RAISE_APPLICATION_ERROR → PostgreSQL SQLSTATE; single source of truth, applied uniformly)
- Transaction-semantics audit per package (explicit per-case decision for PRAGMA AUTONOMOUS_TRANSACTION; note `plog` logging is settled — UDP emitter, no emulation)
- PL/pgSQL-idiomatic logging: `plog` re-implemented as a UDP shipper to the telemetry stack, replacing the Oracle AQ queue + autonomous transaction entirely
- Test per public routine (dual harness: pgTAP + expected-output regression)
- CI-runnable test suite (pg_prove + plain-SQL harness, scriptable, repeatable)
- Idempotent, ordered deployment scripts (preserving Liquibase `runOnChange:true` pattern)
- Runnable container bootstrap (DDL + masterdata + translated code, tests passing, built from scratch) — this is the "done" signal
- Cross-reference rewrite pass (every package call updated to new `package_in_name` object names)
- Client-code rename regexp list (Perl/Java, generated mechanically, not hand-authored)

**Should have (raise confidence):**
- Coverage metric per package (% public routines with at least one test)
- Dependency graph artifact (machine-readable: which package calls which)
- Documented Oracle→SQLSTATE mapping reference

**Defer to later milestones:**
- Jobs (pg_cron), AQ queues (LISTEN/NOTIFY), materialized view logs — architectural replacement work
- Live-Oracle behavioral diffing (top-priority follow-up once Oracle container available)

### Architecture Approach

The migration follows a **5-stage pipeline**:

1. **Inventory & Dependency Graph** (Stage 1) — parse ddl/src to extract objects, signatures, call-outs; compute topological sort
2. **Spec derivation + Name mapping** (Stages 2a/2b, parallel) — hand-verify specs from inventory; build name-mapping SSOT
3. **Test harness** (Stage 3, alongside translation) — write pgTAP + plain-SQL tests from specs (not from ora2pg)
4. **Translation + cross-reference rewrite** (Stage 4) — dependency-ordered waves (leaves first)
5. **Bootstrap & container build** (Stage 5) — numbered init scripts; deliverable is green runnable Docker image

**Major components:**
- **Dependency graph** (oracle for translation/test ordering, feeds three consumers: translation batches, cross-ref rewriting, client regexps)
- **Name-mapping table** (CSV SSOT, consumed by cross-reference rewriter, test harness, regexp generator)
- **Dual test harness** (pgTAP for discrete assertions; expected-output for regression-style diffs)
- **Idempotent deployment scripts** (bootstrap numbered scripts, dependency order enforced by Stage 1)

### Critical Pitfalls

Top 5 by risk/likelihood:

1. **SELECT INTO STRICT semantics** — Oracle raises `NO_DATA_FOUND` by default; PostgreSQL silently returns NULL. **Prevention:** Per-statement spec review, add `STRICT` + exception handlers only when Oracle had a handler. Verify with tests exercising zero-row and multi-row cases.

2. **Autonomous transactions** — 3 packages use `PRAGMA AUTONOMOUS_TRANSACTION`; PostgreSQL has no equivalent. **Prevention — corrected:** For `plog` (the log levels 0–7, by far the most call sites), do NOT emulate: emit a fire-and-forget **UDP datagram** to the telemetry sink, which is non-transactional by construction and therefore survives rollback inherently. dblink/pg_background are explicitly rejected for the logging path. `plog.AuditUsage` is deleted outright (unused feature). For the two genuine table-writing autonomous sites (`insert_result`, `close_old_dev_tickets`), record an explicit per-case decision — UDP telemetry event, accept transactional semantics, or dblink as a last resort. Resolve before the first package batch.

3. **Exception/error-code mapping** — Oracle uses numeric codes; PostgreSQL uses 5-char SQLSTATE. **Prevention:** Standardize exception format with `USING ERRCODE = '<P0001-P9999>'`; maintain explicit mapping table; apply consistently.

4. **Package-level session state** — Oracle packages have session-scoped variables; `package_in_name` flattening has no equivalent. **Prevention:** Audit all 48 packages for non-CONSTANT package-body-level variables. Decide per case: GUC, temp table, or re-derivation. Flag in spec before translation.

5. **Empty string vs NULL divergence** — Oracle treats `''` and `NULL` identically; PostgreSQL distinguishes them. **Prevention:** Flag every VARCHAR2 participating in `IS NULL` checks or concatenation. Normalize or add CHECK constraints. Verify with explicit `''` test cases.

## Implications for Roadmap

The roadmap should follow a **dependency-graph-driven phase structure**. Packages are grouped into **waves**: independent packages in the same wave are translated/tested in parallel; no wave starts until all packages in the prior wave are complete.

### Suggested Phases

**Phase 0: Inventory & Foundation (1-2 weeks)**
- Dependency graph (topologically sorted, wave boundaries)
- Name-mapping table (SSOT, zero collisions)
- Test harness scaffolding (pgTAP + plain-SQL runner)
Addresses: Foundational features; Avoids: Pitfall 7 (ora2pg blind spots)

**Phase 1: Spec Derivation & Early Pilots (2-3 weeks)**
- Behavioral specs for pilot packages (3-5 smallest)
- Exception/error-code mapping table (reference, applied to pilots first)
- Transaction-semantics audit (per-pilot-package: COMMIT/ROLLBACK and PRAGMA AUTONOMOUS_TRANSACTION decisions)
- Package-state audit (per pilot: mutable globals, initialization blocks)
- pgTAP + plain-SQL tests (100% coverage per public routine)
- Translated pilot packages, cross-references rewritten
- Local container bootstrap (green tests)
Addresses: Pitfalls 2, 4, 5; Avoids: Pitfalls 1, 3, 6

**Phase 2: Cross-cutting Dependency Resolution (1-2 weeks)**
- `plog` re-implemented as a UDP log shipper (syslog-shaped payload; levels 0–7 already match). No autonomous-transaction emulation, no AQ queue, no dblink. Test asserts the datagram reaches the collector after the caller rolls back
- `plog.AuditUsage` + its ~177 call sites + the `plsql_audit` table deleted (unused feature, not ported)
- Per-case decisions for the 2 remaining table-writing autonomous sites (`insert_result`, `close_old_dev_tickets`)
- DBMS_*/UTL_* replacement strategies (reference table: one decision per family, applied consistently)
- SELECT INTO STRICT pattern (approved document: when to add STRICT, when to add exception handlers)
Addresses: Pitfalls 2, 4, 8, 9; Stack: UDP emitter (untrusted PL or extension — decide in phase), pgcrypto, native PostgreSQL equivalents

**Phase 3: Wave 1 Translation & Test (3-4 weeks)**
- Complete specs for all Wave 1 packages (leaf packages: no other packages call them)
- pgTAP + plain-SQL tests (100% coverage)
- Translated packages (ora2pg as raw material, specs as ground truth)
- Wave 1 deployed to container, all tests green
- Coverage metrics per Wave 1 package
Addresses: All table-stakes; Avoids: Pitfalls 1, 3, 6, 7, 10

**Phase 4: Wave 2-N Translation & Test (4-6 weeks, paced)**
- Complete specs for remaining packages
- Full dual test suites
- All 48 packages + 2 procs + 8 triggers + 2 types translated, cross-references rewritten
- Incremental container builds proving each wave integrates
- 100% coverage metrics achieved
Addresses: All table-stakes; Avoids: All 11 critical pitfalls through consistent pattern application

**Phase 5: Container Finalization & Client Regexps (1-2 weeks)**
- Runnable PostgreSQL 17 container (from-scratch build catching %TYPE dangling refs)
- Client-code rename regexp list (generated mechanically from name-map.csv, not hand-authored)
- Documentation of Oracle→SQLSTATE mapping
- List of non-mechanical renames requiring manual client review
Addresses: Table-stakes; Avoids: Pitfall 10 (from-scratch build surfaces any dangling references)

### Phase Ordering Rationale

Dependency order is critical: the dependency graph (Phase 0) determines wave boundaries (Phases 3-4). Packages translated in topological order (leaves first) so cross-reference rewrites assume called package's objects already exist. This prevents spurious "object not found" failures masking real errors.

Cross-cutting work first (Phases 1-2) resolves exceptions, logging (the `plog` UDP emitter), the residual table-writing autonomous transactions, and DBMS_* families spanning multiple packages — preventing per-package re-decisions.

Pilot before full scale (Phase 1) de-risks the methodology on low-remediation-cost packages.

### Research Flags

**Phases needing deeper research:**
- **Phase 1** — Complex dynamic SQL (DBMS_SQL, EXECUTE IMMEDIATE) may need manual trace or live-Oracle baseline. ZPA toolkit may help but isn't a complete substitute.
- **Phase 2** — Decide *how* the database emits UDP: untrusted PL (`plperlu`/`plpython3u`, no C build) vs a small C extension. Confirm the payload shape (syslog RFC 5424 maps 1:1 onto plog's existing 0–7 levels) and that the sink can front an OTel collector later. No dblink/pg_background benchmarking — that path is dropped.
- **Phase 4** — If any package found to have FUNCTION issuing COMMIT/ROLLBACK, escalate for re-scoping as PROCEDURE + OUT parameter.

**Standard patterns (skip research-phase):**
- **Phase 0** — Dependency graph is standard DAG traversal; well-documented.
- **Phase 3** — Patterns proven in Phase 1; execution-focused.
- **Phase 5** — Standard container build and regexp generation; patterns established.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | MEDIUM-HIGH | Versions verified via GitHub releases; behavioral claims cross-checked against vendor docs. No empirical testing of this stack combination, but components individually verified. PG17 compatibility confirmed by PGDG packaging. |
| Features | MEDIUM | Table-stakes align with project's Active requirements and industry best-practices. MVP definition is project-aware synthesis (high confidence). Differentiators grounded in repo state and industry patterns (medium-high). |
| Architecture | MEDIUM | 5-stage pipeline derived from project constraints and best-practices. No case study exactly matches "spec-first without live Oracle baseline." Patterns grounded in PostgreSQL official docs (HIGH) and repo context (HIGH); data-flow synthesis (MEDIUM). |
| Pitfalls | MEDIUM-HIGH | Top 11 derived from PostgreSQL official porting docs (HIGH), AWS/Dalibo/EDB guides (MEDIUM), ora2pg/orafce docs (MEDIUM), and direct repo inspection (HIGH). Each cross-checked against 2+ sources except those purely repo-grounded (HIGH confidence). Recovery strategies estimated, not empirically validated. |

**Overall confidence:** MEDIUM

Research has strong foundations in technology verification (stack) and project-specific analysis (grounded in PROJECT.md and CONCERNS.md). Medium reflects: (1) no independent empirical testing of full pipeline; (2) no live-Oracle baseline to validate specs; (3) industry guidance is best-practices, but no exact case-study match. Solid enough to proceed to roadmap; gaps flagged for resolution during execution.

### Gaps to Address

**During Phase 0:** Verify dependency graph for packages with dynamic SQL (EXECUTE IMMEDIATE, DBMS_SQL). Validate name-mapping table for zero collisions.

**During Phase 1:** Each spec must include "Assumptions / Unresolved" section for dynamic SQL, implicit coercions, or NLS behavior that static analysis couldn't resolve. The plog rollback-survival test (datagram reaches the collector after the caller rolls back) must pass before other packages' tests.

**During Phase 2:** Choose the UDP emission mechanism and prove it end-to-end (datagram observed at a collector, including after a caller rollback). Validate each DBMS_*/UTL_* replacement against a real usage.

**During Phase 4:** If spec includes unresolved dynamic SQL and call-time SQL is complex/performance-sensitive, escalate for manual review or live-Oracle trace.

**Post-delivery:** Set up live Oracle 19c container (if possible) and run behavioral diffs against sample of translated packages to refine spec template and validate edge cases.

## Sources

### Primary (HIGH confidence)
- STACK.md research — PostgreSQL official docs, GitHub API verification of pgTAP/orafce/ora2pg releases (2026-07-10)
- FEATURES.md research — PROJECT.md, ARCHITECTURE.md, AWS/Dalibo/EDB guides, ora2pg docs
- ARCHITECTURE.md research — Direct repo inspection: ddl/src, pg_migration/output, .planning/codebase/
- PITFALLS.md research — PostgreSQL 18 porting docs, Oracle-to-PostgreSQL transition guides, ora2pg/orafce docs, repo grepping

### Secondary (MEDIUM confidence)
- AWS Database Blog (error codes, autonomous transactions, empty strings, pgTAP testing)
- Dalibo blog (PL/SQL porting, autonomous transactions)
- EDB tutorials (NULL vs. empty string)
- Capital One tech blog (pgTAP)
- ora2pg/orafce documentation and GitHub issues

### Tertiary (LOW-MEDIUM confidence)
- General web search on pgTAP, orafce, migration patterns (directional guidance)
- ZPA toolkit (mentioned as alternative, not independently tested)

---

*Research completed: 2026-07-10*  
*Ready for roadmap: yes*
