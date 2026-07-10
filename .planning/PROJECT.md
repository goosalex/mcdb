# MCDB Oracle → PostgreSQL Migration

## What This Is

Migration of the MCDB Oracle 19c database to PostgreSQL 17+, centered on translating all programmatic elements (48 Oracle packages, standalone procedures, triggers, types) into valid, tested PL/pgSQL. The approach is spec-first: derive behavioral specifications from the Oracle package code via static analysis, then write PostgreSQL tests that verify the translated code against those specs on a live local Postgres instance. The end deliverable is a runnable container database plus a regexp list for rectifying object names in client code.

## Core Value

Every translated PostgreSQL object behaves like its Oracle original, proven by tests derived from the Oracle code's specification — not just "compiles cleanly."

## Requirements

### Validated

<!-- Inferred from existing repo state — work already done before this project. -->

- ✓ Full Oracle DDL export exists (`ddl/export`, `ddl/generated`) — existing
- ✓ Schema batch-migrated with ora2pg (`ddl/migrated`) — existing, may contain errors
- ✓ Naive ora2pg conversion of programmatic elements (`pg_migration/output/`) — existing, known-incorrect raw material
- ✓ Naming prototype validated: `package_in_name` (package name prefixed to object names, schema layout unchanged) — existing
- ✓ Master data captured for prefilling new containers (`masterdata/`) — existing

### Active

- [ ] Behavioral specification derived per Oracle package (static analysis of `ddl/src/pkg` + `ddl/src/pkgb`): signatures, semantics, side effects, error behavior, transaction behavior
- [ ] Test harness selected and set up for PostgreSQL: pgTAP **and** plain SQL with expected-output comparison, runnable against the local Postgres 17 instance
- [ ] PostgreSQL tests written that verify the specs derived from the Oracle code
- [ ] All 48 packages translated to valid PL/pgSQL (orafce permitted), using `package_in_name` naming; all cross-references between objects refactored to the new names
- [ ] Standalone procedures (2) and triggers (8) translated and tested
- [ ] Types (2) translated as needed by dependent code
- [ ] All translated code verified green against the test suites on the local Postgres instance
- [ ] Runnable container database: DDL + masterdata + translated code stood up from scratch with tests passing
- [ ] Regexp list produced for client code (Perl/Java) to rectify package & object name references

### Out of Scope

- Scheduler jobs (`ddl/src/jobs`, 20 files) — need an architectural replacement (e.g. pg_cron); deferred to a later milestone
- AQ queues (`ddl/src/queues`) — need an architectural replacement (LISTEN/NOTIFY or queue tables); deferred to a later milestone
- Materialized view logs (`ddl/src/mlog`, `ddl/src/mviews`) — Oracle-specific refresh machinery; deferred to a later milestone
- Execution-based Oracle behavioral baseline — no live Oracle instance available now; specs come from static analysis. An Oracle 19c container is possible later to validate specs empirically
- Applying the client-code regexps to actual Perl/Java codebases — we deliver the regexp list; client teams apply it

## Context

- **Repo layout:** `ddl/export` (raw DDL dump), `ddl/generated` (split for recreation), `ddl/migrated` (ora2pg schema output), `ddl/src` (Oracle programmatic source: `pkg` 48 specs, `pkgb` 49 bodies, `proc` 2, `triggers` 8, `types` 2, plus deferred `jobs`/`queues`/`mviews`), `changes/` (Liquibase changelog on top of export), `masterdata/`, `pg_migration/` (ora2pg conversion attempts), `tests/` (existing ORM verification scripts).
- **Note:** CLAUDE.md refers to a top-level `src/` folder; the actual location is `ddl/src/`.
- **Naming prototype:** `pg_migration/output/package_in_name/` (~18k lines of ora2pg output) demonstrates the chosen convention, e.g. package `CALCULATOR` procedure `materialize_tickev` → `calculator_materialize_tickev`. An alternative `package_as_schema` prototype exists but was rejected.
- **ora2pg output is raw material only** — it is known to mistranslate program logic and must never be trusted without spec-driven verification.
- **Local Postgres:** PostgreSQL 17.10 on this machine, accessible via peer auth (`sudo -u postgres psql`). Dedicated test databases/roles will be created from there.
- **Codebase map:** `.planning/codebase/` contains 7 analysis documents from `/gsd-map-codebase`.

## Constraints

- **Tech stack**: PostgreSQL 17+, orafce extension explicitly allowed — reduces translation friction for Oracle built-ins
- **Naming/Compatibility**: Schema stays identical to Oracle; object names get package-name prefix (`package_in_name` convention) — keeps client migration mechanical (regexp-driven)
- **Verification**: Local Postgres 17.10 via sudo peer auth is the test target — no Oracle instance available for now
- **Methodology**: Spec-first — specs derived from Oracle source before translation; tests verify specs, not the translation's own assumptions

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Spec-first: derive specs from Oracle code, tests verify specs | ora2pg output is untrustworthy; need an Oracle-derived ground truth without a live Oracle instance | — Pending |
| Static analysis for specs (no live Oracle for now) | Oracle container is possible later but not now; do the best possible from source | — Pending |
| Dual PG test harness: pgTAP + plain SQL/expected-output | pgTAP for unit-level assertions; plain SQL diffs for regression-style checks with minimal dependencies | — Pending |
| Keep `package_in_name` naming from prototype | Schema stays Oracle-identical; package prefix on object names makes client-side rename regexp-able | — Pending |
| orafce allowed | Reduces friction translating Oracle built-ins | — Pending |
| Jobs/queues/mviews deferred to later milestone | Need architectural replacements (pg_cron, LISTEN/NOTIFY), separable from core code translation | — Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-07-10 after initialization*
