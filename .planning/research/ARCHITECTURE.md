# Architecture Research

**Domain:** Oracle→PostgreSQL PL/SQL-to-PL/pgSQL code migration + verification pipeline (spec-first, dual test harness)
**Researched:** 2026-07-10
**Confidence:** MEDIUM — repo-grounded facts (read directly from `ddl/src`, `pg_migration/output`) are HIGH confidence; general pipeline/tooling practices below are cross-checked web findings at LOW/MEDIUM confidence (no case study matches this exact spec-first-without-a-live-Oracle-instance approach, so those parts are this agent's synthesis, flagged as such)

## Standard Architecture

### System Overview

```
┌───────────────────────────────────────────────────────────────────────────┐
│  STAGE 0 — Oracle Source (read-only input, already exists)                │
│  ddl/src/{pkg,pkgb,proc,triggers,types}   masterdata/{MODULE}/*.csv+xml   │
└───────────────────────────┬─────────────────────────────────────────────┘
                            │  (static analysis — no live Oracle needed)
┌───────────────────────────▼─────────────────────────────────────────────┐
│  STAGE 1 — Inventory & Dependency Graph                                   │
│  scripts/analyze/  →  inventory.json (every object, signature, calls-out) │
│                    →  depgraph.dot / .json (topological translation order)│
└──────────┬──────────────────────────────────────────┬────────────────────┘
          │                                            │
┌──────────▼───────────────┐            ┌───────────────▼───────────────────┐
│ STAGE 2a — Spec Docs      │            │ STAGE 2b — Name-Mapping Table      │
│ specs/<schema>/<pkg>.md    │            │ mapping/name-map.csv (SSOT)         │
│ (signatures, side effects, │            │ oracle_qualified → pg_name          │
│  exceptions, txn behavior) │            └──────┬───────────────┬────────────┘
└──────────┬─────────────────┘                    │               │
          │                          ┌────────────▼───┐   ┌───────▼─────────┐
          │                          │ STAGE 4 —       │   │ STAGE 6 —        │
          │                          │ Translation +    │   │ Client Regexp    │
          │                          │ Cross-ref rewrite│   │ Generator        │
          │                          │ pg_src/<schema>/ │   │ regexps/*.txt    │
          │                          └────────┬─────────┘   └──────────────────┘
┌──────────▼─────────────────────────────────▼─────────────────────────────┐
│ STAGE 3 — Test Harness (built ahead of/alongside translation)             │
│ tests/pgtap/<schema>/<pkg>/NNN_*.sql   tests/sql/<schema>/<pkg>/*.sql+.out │
│ tests/fixtures/ (masterdata-derived + package-specific seed data)          │
└──────────────────────────────────┬────────────────────────────────────────┘
                                   │  (spec-derived tests run against pg_src)
┌───────────────────────────────────▼────────────────────────────────────────┐
│ STAGE 5 — Bootstrap & Container Build                                      │
│ extensions → schema DDL (ddl/migrated, fixed) → masterdata → pg_src        │
│ (dependency order) → grants → run test suites → green container image     │
└──────────────────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Responsibility | Typical Implementation |
|-----------|----------------|------------------------|
| Package Inventory & Dependency Graph | Enumerate every programmatic object (48 packages + 2 procs + 8 trigger files + 2 types), its signature and every object it calls; compute a translation/test order | Static-analysis script (Python/Node) over `ddl/src/{pkg,pkgb,proc,triggers,types}`, output `inventory.json` + `depgraph.dot`/`.json` |
| Spec Documents | One behavioral spec per package: signatures, params, side effects (tables written), exceptions raised, transaction behavior (commits, autonomous transactions, cursors), calls made to other packages/DBMS_* | Markdown or YAML per package under `specs/<schema>/<package>.md`, generated from inventory + hand-verified |
| Name-Mapping Table | Single source of truth mapping every Oracle qualified name (`SCHEMA.PACKAGE.PROC`, synonym forms) to its PG `package_in_name` object name | `mapping/name-map.csv`: `oracle_schema, oracle_package, oracle_object, oracle_synonym, pg_schema, pg_object_name, kind` |
| Test Harness | Dual verification: pgTAP for structural/behavioral assertions, plain SQL + expected-output for regression-style diffs; both fed by shared masterdata-derived fixtures | `tests/pgtap/`, `tests/sql/`, `tests/fixtures/`, `pg_prove` + a thin SQL-diff runner |
| Translated Source Tree | Holds the verified PL/pgSQL translation, one file per Oracle package (not ora2pg's flat per-type dump), named per `package_in_name` | `pg_src/<schema_lower>/<package_prefix>.sql`, ordered internally to match dependency graph |
| Bootstrap / Container Build | Deterministic, replayable sequence: extensions → schema DDL → masterdata → code (dependency order) → tests | Numbered init scripts (mirrors existing `container/container-entrypoint-initdb.d/` pattern), Dockerfile for PG 17 |
| Client Regexp Generator | Mechanically derives Perl/Java rename regexps from the name-mapping table — never hand-authored | Script reading `mapping/name-map.csv`, emitting `regexps/client-rename.txt` |

## Recommended Project Structure

```
mcdb/
├── ddl/src/{pkg,pkgb,proc,triggers,types}   # existing Oracle source — read-only input
├── masterdata/{MODULE}/                     # existing seed data — read-only input
├── ddl/migrated/                            # existing ora2pg DDL — starting material, needs fixing
├── pg_migration/output/package_in_name/     # existing ora2pg naive code dump — starting material only
│
├── migration/                               # NEW — this milestone's pipeline
│   ├── analyze/
│   │   ├── inventory.json                   # every object: schema, package, name, kind, signature, calls-out[]
│   │   ├── depgraph.dot                     # graphviz dependency graph
│   │   ├── depgraph.json                    # same, machine-readable (topological order)
│   │   └── scripts/                         # static-analysis tooling (parses ddl/src/*)
│   ├── mapping/
│   │   └── name-map.csv                     # SSOT: oracle_qualified_name → pg_object_name
│   ├── specs/
│   │   └── <schema>/<package>.md            # one spec doc per package (or per standalone proc/trigger)
│   ├── pg_src/
│   │   └── <schema_lower>/<package_prefix>.sql   # one file per Oracle package, translated + cross-ref-rewritten
│   ├── tests/
│   │   ├── pgtap/<schema>/<package>/NNN_*.sql
│   │   ├── sql/<schema>/<package>/*.sql + *.expected
│   │   └── fixtures/                        # masterdata-derived + package-specific seed data
│   ├── bootstrap/
│   │   ├── 000_extensions.sql               # orafce, pgtap, pgcrypto, etc.
│   │   ├── 100_schema_ddl/                  # from ddl/migrated, corrected
│   │   ├── 200_masterdata_load.sh
│   │   ├── 300_pg_src_load.sh               # applies pg_src/ in depgraph order
│   │   └── 900_run_tests.sh
│   └── regexps/
│       └── client-rename.txt                # generated from name-map.csv — final deliverable
└── container/pg/                            # NEW — Postgres container mirroring existing container/ pattern
```

### Structure Rationale

- **`migration/analyze/` first and separate:** the dependency graph is the one artifact every other stage reads; keeping it as a standalone, regenerable output (not hand-maintained) prevents the "implicit ordering" anti-pattern already flagged in the existing Liquibase changelog (see Anti-Patterns).
- **`migration/mapping/name-map.csv` as a flat CSV, not scattered comments:** it is consumed by three independent downstream generators (translation cross-ref rewriter, test harness naming, client regexp generator) — a single flat table avoids drift between them.
- **`migration/pg_src/` one file per package, not per-type:** the existing `pg_migration/output/package_in_name/PACKAGE.pg.sql` prototype concatenates every package's procedures into one 15,964-line file — unreviewable and untestable at package granularity. Splitting one-file-per-package (mirroring `ddl/src/pkg/<name>.sql` naming) makes diffs, code review, and per-package CI gating tractable.
- **`migration/tests/` split pgtap/ vs sql/:** these are different tools with different runners (`pg_prove` vs a plain `psql -f ... | diff`); keeping them as sibling trees under a common `<schema>/<package>/` layout lets both be driven by the same package-level "done" signal.
- **`migration/bootstrap/` numbered scripts:** the repo already has a proven pattern for this (`container/container-entrypoint-initdb.d/010_...` through `995_...`); reusing numbered-script ordering for Postgres avoids introducing a second convention.

## Architectural Patterns

### Pattern 1: Static dependency graph as the translation-order oracle

**What:** Parse every `ddl/src/pkg/*.sql` and `ddl/src/pkgb/*.sql` file for (a) the package's own declared procedures/functions and (b) every `SCHEMA.PACKAGE.PROC` / `PACKAGE.PROC` call it makes to another package (e.g. `TT.OSAG_NOTIFY.delete_notifications_for_login` found inside `AUTH.OSAG_AUTH`). Build a directed graph; packages with no outbound edges (leaves) are translated and tested first; packages high in the graph (called by many, calling few) come next; packages that both call and are called by many others (hubs) come last, once their dependencies are proven.

**When to use:** Immediately, as the very first pipeline stage — every other artifact (specs, tests, translation batches) is ordered by this graph.

**Trade-offs:** Static text-based extraction misses dynamic SQL and can miscount calls hidden in string literals — cross-check against `ALL_DEPENDENCIES`-style Oracle metadata is not available here (no live Oracle instance per PROJECT.md constraints), so the graph must be manually spot-checked for the packages ora2pg flags as containing `EXECUTE IMMEDIATE`/dynamic SQL. Treat the graph as a strong prior, not ground truth.

**Example:**
```json
{
  "package": "AUTH.OSAG_AUTH",
  "kind": "package",
  "objects": ["delete_login", "..."],
  "calls_out": ["TT.OSAG_NOTIFY.delete_notifications_for_login", "PLOG.AUDITUSAGE"],
  "tables_written": ["auth.login2profile", "auth.user_permission", "stop.contact", "..."]
}
```

### Pattern 2: Name-mapping table as single source of truth (SSOT), never hand-duplicated

**What:** One CSV/table mapping every Oracle-qualified name (including public synonyms — the repo creates one per package, e.g. `create or replace public synonym OSAG_IMPLICATION for auth.osag_implication`) to its final PostgreSQL `package_in_name` object name. Every consumer (cross-reference rewriter inside translated code, test file/object naming, client regexp generator) reads this table; none of them invent naming independently.

**When to use:** Generate it directly after the inventory stage, before any translation begins, so translation and test-authoring never invent ad-hoc names that later have to be reconciled.

**Trade-offs:** Requires discipline — any manual renaming decision (e.g. resolving a collision between two packages that would produce the same prefixed name) must be written back into this table, not patched only in the SQL file.

**Example row set:**
```csv
oracle_schema,oracle_package,oracle_object,oracle_synonym,pg_schema,pg_object_name,kind
AUTH,OSAG_IMPLICATION,AUTH_UPDATE,OSAG_IMPLICATION,auth,auth_osag_implication_auth_update,procedure
TT,OSAG_NOTIFY,DELETE_NOTIFICATIONS_FOR_LOGIN,OSAG_NOTIFY,tt,tt_osag_notify_delete_notifications_for_login,procedure
```

### Pattern 3: Spec-first, dual-harness verification per package

**What:** For each package, derive a spec document (signature, side effects, exceptions, transaction semantics) purely from the Oracle source, independent of the ora2pg output. Author pgTAP tests (behavioral/structural assertions, e.g. "raises NO_DATA_FOUND-equivalent when login absent") and plain-SQL expected-output tests (regression-style: run the procedure, dump affected rows, diff against a golden file) from that spec — not from reading the ora2pg translation. Only then translate (using ora2pg output as raw material) and run both suites against the translation.

**When to use:** Per package, in dependency order from Pattern 1. This is the core discipline the milestone requires (spec-first — tests must not "verify the translation's own assumptions," per PROJECT.md).

**Trade-offs:** Slower up front than "translate then eyeball it," but is what prevents ora2pg's known silent mistranslation of procedural logic from surviving into the container DB.

**Example (pgTAP, package-scoped):**
```sql
-- tests/pgtap/auth/osag_auth/010_delete_login.sql
BEGIN;
SELECT plan(3);
SELECT lives_ok(
  $$ CALL auth.auth_osag_auth_delete_login(:login_id) $$,
  'delete_login completes without raising'
);
SELECT is(
  (SELECT count(*) FROM auth.login WHERE id = :login_id), 0,
  'login row removed'
);
SELECT is(
  (SELECT count(*) FROM auth.user_permission WHERE profile_id IN (...)), 0,
  'cascaded permission rows removed'
);
SELECT * FROM finish();
ROLLBACK;
```

## Data Flow

### Migration Pipeline Flow

```
Oracle source (ddl/src/pkg, pkgb, proc, triggers, types)
    ↓ (static analysis, no live Oracle needed)
Inventory (inventory.json) + Dependency Graph (depgraph.json/.dot)
    ↓                                  ↓
Spec docs (specs/<schema>/<pkg>.md)   Name-mapping table (mapping/name-map.csv)  ← SSOT
    ↓                                  ↓                    ↓                    ↓
Test authoring                  Translation +        Test harness         Client regexp
(pgTAP + expected-output,       cross-ref rewrite     naming (object       generator
 from specs)                    (pg_src/, using       names match          (regexps/
    ↓                            name-map for          name-map)            client-rename.txt)
    ↓                            intra-DB calls)             ↓
    └──────────── run tests against pg_src ─────────────────┘
                     ↓ (green)
        Bootstrap: extensions → schema DDL → masterdata → pg_src (dep order) → grants
                     ↓
              Runnable container DB, tests passing
```

### Key Data Flows

1. **Dependency graph → translation batches:** the graph is topologically sorted into waves (leaf packages first). Each wave's packages are translated, cross-ref-rewritten (using names already finalized for *earlier* waves, since those are the only ones a given package can legally call in a well-formed DAG), and tested together before the next wave starts.
2. **Name-mapping table → three independent consumers:** (a) the cross-reference rewriter substitutes every `SCHEMA.PACKAGE.PROC(...)` call found inside a package body being translated with its `pg_schema.pg_object_name(...)` equivalent; (b) the test harness uses the same names when calling the object under test; (c) the client regexp generator emits one regex rule per mapping row, entirely mechanically — this is what keeps the regexp list correct without hand-authoring.
3. **Masterdata → shared test fixtures:** `masterdata/<MODULE>/*.csv` already aligns 1:1 with Oracle schema names (`AUTH`, `FW`, `MC`, etc.). The bootstrap loads all masterdata once per fresh test database; package-specific tests add only incremental fixture rows on top (in `migration/tests/fixtures/<schema>/<package>/`) rather than re-seeding whole tables — keeps fixtures cheap and avoids masterdata drift between test files.
4. **Spec docs → both test types:** each spec's "side effects" section drives the plain-SQL expected-output assertions (row-level diffs), and its "error behavior"/"transaction behavior" sections drive pgTAP's `throws_ok`/`lives_ok`/`is` assertions — the two harnesses are not redundant, they check different facets of the same spec.

## Scaling Considerations

This is a one-time migration pipeline, not a runtime system, so "scale" here means number-of-packages, not concurrent users.

| Scale | Architecture Adjustments |
|-------|--------------------------|
| 1–5 packages (pilot) | Build and prove the full pipeline end-to-end manually on a handful of leaf packages (e.g. the `mss_osag_ip_test`-sized 7–14 line packages) to validate the inventory format, spec template, and both test harnesses before automating |
| 5–20 packages | Automate spec-doc scaffolding from `inventory.json` (generate a spec skeleton per package to be hand-filled, not hand-created from scratch); parallelize translation across independent subtrees of the dependency graph (packages in the same "wave" have no edges between them and can be translated concurrently) |
| All 48 packages + 2 procs + 8 trigger files + 2 types | Full graph-driven waves; per-package CI gate (a package's PR/commit must pass its own pgTAP + expected-output suite before merge); incremental container builds — the container should be buildable and green with only the currently-translated subset present, not require all 48 packages done at once |

### Scaling Priorities

1. **First bottleneck — dependency graph accuracy:** if the graph misses a dynamic-SQL-hidden call, a "leaf" package turns out not to be one, and its early translation breaks when a later package's cross-ref rewrite needs to reach into it. Mitigate by spot-checking each package's Oracle source for `EXECUTE IMMEDIATE`/string-built SQL during Stage 1, flagging those packages for manual dependency annotation rather than trusting the automated parse.
2. **Second bottleneck — spec-authoring throughput:** 48 packages of hand-verified behavioral specs is the largest manual-effort item in the whole pipeline. Mitigate by templating specs directly from the inventory (signature, tables touched, calls-out are all mechanically derivable; only exception/transaction semantics need a human read of the package body) and by batching similar packages (e.g. the several `*_state` packages likely share a shape) to reuse spec structure.

## Anti-Patterns

### Anti-Pattern 1: Translating in file-alphabetical (or Liquibase-include) order

**What people do:** Work through `ddl/src/pkg/*.sql` in the order Liquibase includes them (`--changeset` order / `plsql-changelog.xml` include order), which is not a dependency order.
**Why it's wrong:** The existing repo's own architecture notes flag this exact failure mode ("Missing Dependency Documentation in Changesets" — implicit ordering is brittle, silent failures on missing deps). For this milestone it also means cross-reference rewrites (Pattern 2) get applied to packages whose callees don't have PG names yet.
**Do this instead:** Always drive translation and test order from the computed dependency graph (Stage 1), not file order.

### Anti-Pattern 2: Trusting ora2pg output as the translation

**What people do:** Take `pg_migration/output/package_in_name/PACKAGE.pg.sql` (or the per-type files) as "the" PostgreSQL implementation and only lightly edit it to compile.
**Why it's wrong:** Per PROJECT.md, ora2pg output is confirmed to mistranslate program logic — it is raw material only. Package-local state, exception semantics (`WHEN OTHERS THEN RAISE;` patterns seen throughout `ddl/src/pkgb`), nested autonomous-transaction-like blocks, and Oracle format attributes (`$$PLSQL_UNIT_OWNER`, `%TYPE`) are exactly the constructs ora2pg is known to handle unreliably.
**Do this instead:** Use ora2pg output as a starting draft, but gate every package's acceptance on passing its spec-derived pgTAP + expected-output suite — never on "it compiles."

### Anti-Pattern 3: One giant per-type output file instead of one file per package

**What people do:** Keep the ora2pg-style layout where all procedures across all 48 packages live in one `PACKAGE.pg.sql` (currently ~16k lines) and all functions in another.
**Why it's wrong:** Impossible to code-review, diff, or gate in CI at the package granularity this milestone requires; a single-package fix touches a file shared by every other package's translation.
**Do this instead:** One file per Oracle package under `migration/pg_src/<schema>/<package_prefix>.sql`, named to mirror `ddl/src/pkg/<name>.sql` — makes "is package X done" a file-level, git-diffable, CI-gateable question.

### Anti-Pattern 4: Hand-authoring the client regexp list

**What people do:** Write the Perl/Java rename regexps by manually scanning translated packages for name changes.
**Why it's wrong:** Duplicates the name-mapping table in a second, unsynchronized place; guaranteed to drift as packages get re-translated or collisions get resolved.
**Do this instead:** Generate `regexps/client-rename.txt` purely mechanically from `mapping/name-map.csv` (Pattern 2) — one generator script, re-run any time the mapping changes, never edited by hand.

### Anti-Pattern 5: Building the full container before any package is proven

**What people do:** Try to stand up the complete DDL + masterdata + all-48-packages container in one pass at the end.
**Why it's wrong:** Defers discovery of bootstrap-ordering problems (extension load order, masterdata FK dependencies, cross-schema grants) until the very end, when 48 packages' worth of translation work is already sunk.
**Do this instead:** Make the bootstrap/container buildable incrementally from wave 1 (Stage 5 should tolerate a partially-translated `pg_src/` and simply run whichever package tests currently exist) — prove the container mechanism early on the pilot packages, then let it grow wave by wave.

## Integration Points

### External Services

| Service | Integration Pattern | Notes |
|---------|---------------------|-------|
| PostgreSQL 17.10 (local, peer auth) | Direct `psql`/`pg_prove` connections from bootstrap and test scripts | No live Oracle instance available (per PROJECT.md) — all Oracle-side "verification" is static-analysis-derived, not execution-derived, until/unless an Oracle 19c container is added later |
| orafce extension | Installed as Stage 0 of bootstrap (`CREATE EXTENSION orafce;`) before schema DDL | Reduces but does not eliminate translation work for Oracle built-ins (`DBMS_OUTPUT`-style, date/string functions); does not cover package-level constructs like `plog.AuditUsage` calls seen in package bodies — those still need bespoke PL/pgSQL equivalents |
| pgTAP extension | Installed alongside orafce in Stage 0; optionally scoped to its own schema via `CREATE EXTENSION pgtap SCHEMA tap;` to keep it out of the object namespace under test | `pg_prove` is the standard runner for bulk execution |
| ora2pg (existing tooling in `pg_migration/`) | Used only as an input generator for `migration/pg_src/` drafts, not as part of the verification pipeline itself | Existing `pg_migration/preparation/300_run_ora2pg.sh` remains the source of the raw draft; this milestone's pipeline consumes that output, it does not replace the ora2pg invocation step |

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| Inventory/depgraph ↔ Spec docs | File read (`inventory.json` → spec scaffold generator) | Specs are hand-verified after scaffolding; not fully automated |
| Inventory/depgraph ↔ Name-mapping table | File read (same inventory feeds both) | Both stages 2a/2b can run in parallel once Stage 1 is done |
| Name-mapping table ↔ Translation (cross-ref rewrite) | CSV read, search/replace by qualified-name pattern | Rewriter must handle both `SCHEMA.PACKAGE.PROC` and bare `PACKAGE.PROC` (via public synonym) call forms — both exist in the source, e.g. `TT.OSAG_NOTIFY.delete_notifications_for_login` |
| Name-mapping table ↔ Test harness | Test files reference PG object names directly; harness itself does no lookup at runtime | Keeps test execution free of a runtime dependency on the mapping table |
| Name-mapping table ↔ Client regexp generator | CSV read, one regex per row emitted | This is the only consumer that produces a deliverable outside the database itself |
| Translated pg_src ↔ Test harness | Bootstrap loads `pg_src/` then runs `tests/pgtap/` and `tests/sql/` against the live objects | Both harnesses run against the *same* bootstrapped database instance per test cycle, not against separate schemas |
| Masterdata ↔ Bootstrap/tests | CSV load scripts run once per fresh database, before code load; package-specific fixtures layer on top | Masterdata module directories (`AUTH/`, `FW/`, `MC/`, etc.) already map 1:1 to Oracle schema names, so no additional mapping layer is needed here |
| Existing `container/` (Oracle) pattern ↔ new Postgres container | Structural precedent only, not shared code | The numbered-init-script convention (`010_...` → `995_...`) is worth reusing for the Postgres container for consistency, but the Postgres container is a new tree (`container/pg/` or similar), not a modification of the Oracle one |

## Sources

- [pgTAP official site](https://pgtap.org/) — LOW confidence (web search digest, not independently verified against pgTAP docs in depth)
- [pgTAP documentation](https://pgtap.org/documentation.html) — LOW confidence
- [GitHub: theory/pgtap](https://github.com/theory/pgtap) — LOW confidence
- [Capital One: Unit Testing in Postgres Made Easy with pgTAP](https://www.capitalone.com/tech/software-engineering/automated-postgres-unit-testing/) — LOW confidence
- [Supabase Docs: Advanced pgTAP Testing](https://supabase.com/docs/guides/local-development/testing/pgtap-extended) — LOW confidence
- [Oracle docs: ALL_DEPENDENCIES](https://docs.oracle.com/cd/B19306_01/server.102/b14237/statviews_1041.htm) — LOW confidence (web digest; content is standard Oracle reference material)
- [dpriver.com: Analyzing Oracle PL/SQL Dependencies Before Your Snowflake Migration](https://www.dpriver.com/blog/2026/04/analyzing-oracle-plsql-dependencies-before-your-snowflake-migration/) — LOW confidence
- [ora2pg documentation](https://ora2pg.darold.net/documentation.html) — LOW confidence
- [ora2pg features](https://ora2pg.darold.net/docs/features) — LOW confidence
- [orafce GitHub](https://github.com/orafce/orafce) — LOW confidence
- [AWS Prescriptive Guidance: Migrate Oracle native functions to PostgreSQL using extensions](https://docs.aws.amazon.com/prescriptive-guidance/latest/patterns/migrate-oracle-native-functions-to-postgresql-using-extensions.html) — LOW confidence
- [convert-in.com: Practical Case Study of Oracle to PostgreSQL Database Migration](https://www.convert-in.com/docs/ora2pgs/case-study) — LOW confidence
- [DEEP: Case Study Migrating from Oracle to PostgreSQL with Ora2PG](https://www.deep.eu/en/ressources/articles-blog/data-ai/bases-de-donnees/migrer-oracle-vers-postgresql-avec-ora2pg) — LOW confidence
- [dev.to: Stored Procedures & Exception Handling when migrating from Oracle to PostgreSQL or YugabyteDB](https://dev.to/aws-heroes/stored-procedures-exception-handling-when-migrating-from-oracle-to-postgresql-or-yugabytedb-3i2e) — LOW confidence
- Direct repo inspection (HIGH confidence): `ddl/src/pkg/auth_osag_implication.sql`, `ddl/src/pkgb/auth_osag_auth.sql`, `pg_migration/output/package_in_name/PACKAGE.pg.sql`, `.planning/codebase/STRUCTURE.md`, `.planning/codebase/ARCHITECTURE.md`, `.planning/PROJECT.md`

---
*Architecture research for: Oracle→PostgreSQL code migration pipeline*
*Researched: 2026-07-10*
