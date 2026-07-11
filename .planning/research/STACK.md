# Stack Research

**Domain:** Oracle 19c → PostgreSQL 17+ PL/SQL migration and in-database testing tooling
**Researched:** 2026-07-10
**Confidence:** MEDIUM (versions/release dates cross-verified directly against GitHub API release tags; behavioral/coverage claims from vendor docs and web search, not independently executed against PG 17.10 by this research pass)

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| PostgreSQL | 17.10 (already installed locally) | Migration target / test target | Fixed by project constraint. All tooling choices below are pinned to what's verified compatible with PG 17. |
| pgTAP | 1.3.4 (released 2025-10-04) | In-database unit-test assertions (`ok`, `is`, `throws_ok`, `results_eq`, function/table-shape assertions) | The de facto standard xUnit-style framework for PostgreSQL; tests are themselves SQL/PL/pgSQL, so they run inside the same transactional sandbox as the code under test — ideal for asserting package-level behavior (return values, raised exceptions, side effects) derived from the Oracle specs. 1.3.3+ explicitly tested against PG 17.0. |
| pg_prove | via `TAP::Parser::SourceHandler::pgTAP` (CPAN, current ~3.37) | Test runner / CI harness for pgTAP scripts | Turns pgTAP's raw TAP output into readable pass/fail reports and JUnit-style exit codes; this is the standard companion to pgTAP, not an alternative — nearly every pgTAP guide assumes pg_prove as the runner. |
| orafce | 4.16.7 (released 2026-06-04) | Oracle built-in function/type compatibility shim (date arithmetic, `dbms_output`, `utl_file`, string/number helpers) | Explicitly allowed by project constraints. Reduces the amount of hand-written PL/pgSQL needed to replicate Oracle built-ins that have no 1:1 PostgreSQL equivalent (see coverage breakdown below). Actively maintained (releases roughly monthly), packaged for PG17 by both PGDG apt and dnf repos. |
| Plain-SQL / `pg_regress`-style diff harness | Hand-rolled (pattern borrowed from PostgreSQL's own `pg_regress`/PGXS convention) | Regression-style "run script, diff against golden output" tests | Complements pgTAP for scenarios that are naturally expressed as "run this SQL, the resulting rows/output must match exactly" (e.g., full package-body integration flows, cursor result sets) rather than as discrete assertions. This is exactly the second harness the project's spec-first methodology calls for. |
| ora2pg | 25.0 (released 2025-04-20) | Raw material generator + offline PL/SQL-snippet translator + complexity/assessment reporting | Already used for the existing `ddl/migrated` and `pg_migration/output` artifacts. Its `-i`/`--input_file` mode lets it translate a single package body file **without any live Oracle connection**, which fits this project's static-analysis-only constraint. Its assessment-report mode is useful for triage (ranking the 48 packages by translation complexity) even though its actual code translation is never trusted as final output. |
| ZPA (felipebz/zpa) | Latest (rolling releases, active as of research date) | PL/SQL static-analysis parser / AST extraction for spec derivation | An independent, ANTLR-based PL/SQL + Oracle SQL parser (not ora2pg's regex/heuristic engine). Ships a standalone `zpa-toolkit` jar to dump a parse tree/AST from a `.sql`/`.pkb` file — gives a second, more rigorous lens for extracting signatures, cursor definitions, exception handlers, and control flow when deriving behavioral specs from `ddl/src/pkg` and `ddl/src/pkgb`, independent of ora2pg's own (known-buggy) interpretation. |
| Docker + Compose | Docker Engine (any recent), `postgres:17` official image as base | Reproducible local + CI test environment | Needed to pin an exact PG17.10-equivalent image, exact orafce/pgTAP versions, and automate seed/masterdata loading identically in dev and CI, decoupled from whatever happens to be installed on the researcher's machine via `sudo -u postgres`. |

### Supporting Libraries

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `orafce_sql` (okbob/orafce_sql or orafce/orafce_sql) | Latest on GitHub (unversioned/rolling; not yet merged into core orafce) | Closer approximation of Oracle's `dbms_sql` dynamic-SQL API | Only if static analysis of the 48 packages turns up real `dbms_sql`-style dynamic SQL usage — core orafce's `dbms_sql` is an intentionally partial subset. Evaluate need before adding; likely most dynamic SQL in the packages can be rewritten directly with PL/pgSQL's native `EXECUTE`/`format()` instead of emulating the Oracle API. |
| `pg_cron` | Latest stable for PG17 | Out-of-scope placeholder for `ddl/src/jobs` | Not part of this milestone (jobs are deferred), but note it now since it's the natural target when that milestone starts — avoids a second stack-research pass later. |
| PostgreSQL native `LISTEN/NOTIFY` + queue tables | N/A (built-in) | Out-of-scope placeholder for `ddl/src/queues` (AQ replacement) | Same as above — deferred, noted for continuity. |
| `pgxnclient` (PyPI) | Latest | Alternative installer for PGXN-hosted extensions (pgTAP, orafce) when not using apt/dnf packages | Only needed if the CI/container base image isn't Debian/RHEL-family (e.g., Alpine) where PGDG apt/dnf packages aren't available; otherwise apt/dnf packages are simpler and pin cleanly in a Dockerfile. |

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| `pg_prove` CLI | Run `.sql` pgTAP test files, produce TAP/JUnit-style summaries | Requires Perl + `TAP::Parser::SourceHandler::pgTAP` (`cpan TAP::Parser::SourceHandler::pgTAP`), plus `pg_config` on PATH so pgTAP's `make install` targets the right PG17 install. Bake into the test-container image, not the developer's host, to avoid Perl/CPAN drift. |
| `psql` scripted diffing (`diff -u expected/*.out results/*.out`) | Golden-file regression testing for plain-SQL harness | Mirrors PostgreSQL core's own `pg_regress` convention: `sql/*.sql` input, `expected/*.out` golden output, `results/*.out` actual output, diff on mismatch. Full PGXS/`pg_regress` binary is not required — a thin bash/Make wrapper around `psql -f` + `diff` gets 90% of the value without needing to package this project as a C extension. |
| `zpa-toolkit` jar | Dump PL/SQL AST for a given file for spec extraction | Requires JDK 11+; run once per package during spec derivation, not part of the runtime test loop. |
| Docker Compose | Orchestrate PG17 + seed-data init + test runner as one reproducible stack | Use `/docker-entrypoint-initdb.d/NN-*.sql` numbered scripts for `CREATE EXTENSION orafce; CREATE EXTENSION pgtap;` then masterdata load, then translated-DDL load — deterministic ordering matters since init scripts only run once against an empty data directory. |

## Installation

```bash
# On the target Postgres 17 host (Debian/Ubuntu, PGDG apt repo already configured)
sudo apt-get install -y postgresql-17-pgtap postgresql-17-orafce

# Enable extensions in each database that needs them
psql -d mcdb_test -c "CREATE EXTENSION IF NOT EXISTS orafce;"
psql -d mcdb_test -c "CREATE EXTENSION IF NOT EXISTS pgtap;"

# pg_prove (Perl test runner) — install once per CI/dev image
cpan TAP::Parser::SourceHandler::pgTAP
# or: apt-get install libtap-parser-sourcehandler-pgtap-perl (Debian package name may vary by distro)

# ora2pg (already used for prior conversion passes; reconfirm pinned version)
cpanm DBD::Oracle   # only if connecting live; not needed for -i/--input_file mode
git clone --branch v25.0 https://github.com/darold/ora2pg.git

# ZPA static analysis (optional, for independent spec-derivation pass)
# Requires JDK 11+; download zpa-toolkit-<version>.jar from
# https://github.com/felipebz/zpa/releases
```

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|--------------------------|
| pgTAP + pg_prove | pg_regress (raw PGXS harness) | If the project ever needs to ship this test suite as an installable PostgreSQL extension itself (unlikely here) — pg_regress is heavier to set up for a one-off migration project than a hand-rolled diff script, but is the "real" mechanism pgTAP itself borrows its philosophy from. |
| pgTAP + pg_prove | pgxUnit / dbunit-style JVM test frameworks | If the team wants tests authored in Java against the existing Testcontainers/JUnit5 harness already in the repo (`tests/`) instead of in SQL. Rejected as primary choice because it pushes spec verification outside the database and duplicates the existing ORM test layer's purpose; pgTAP keeps tests co-located with the SQL they verify, which matches the spec-first methodology better. Could still be a secondary layer for end-to-end/ORM-facing checks. |
| orafce | Hand-written PL/pgSQL shims for every Oracle built-in | If a specific orafce function's semantics don't match the Oracle behavior found during spec derivation (this will happen for edge cases, especially date arithmetic across format strings and `dbms_sql`). In that case, write a package-local wrapper function that corrects orafce's behavior rather than avoiding orafce wholesale — cheaper than reimplementing everything. |
| ora2pg (`-i` file mode + assessment report) | SQLines, SQL Tran (commercial), AWS SCT | Commercial/managed tools (SQL Tran claims 95-99% auto-translation, AWS Schema Conversion Tool is free but AWS-account-gated) could be evaluated if the 48-package hand-translation proves too slow, but they don't fit "static analysis only, no external service dependency" as cleanly, and none avoid the need for spec-driven verification of translated logic. Not recommended as the primary path for this milestone. |
| ZPA for spec-extraction AST | Trivadis `plsql-analyzer` | `plsql-analyzer`'s primary workflow analyzes PL/SQL live inside an Oracle instance and stores parse trees in Oracle tables — not usable here since there is no live Oracle instance for this milestone. Revisit if/when an Oracle 19c container is stood up later for empirical baseline validation. |

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|--------------|
| Trusting ora2pg's PL/SQL→PL/pgSQL *code* output as final translation | Explicitly known-incorrect per project context (`pg_migration/output` is "naive," "for sure contains errors" — ora2pg cannot reliably translate program logic, only schema/DDL and simple mappings) | Use ora2pg only for (a) raw material/starting scaffolding, (b) offline single-file translation as a first draft to edit, and (c) its assessment/complexity report for triage. All actual logic must be verified against pgTAP/plain-SQL specs derived independently. |
| Assuming orafce gives full Oracle package compatibility | orafce's own stated goal is to "reduce migration work," not achieve full compatibility; `dbms_sql` is an intentionally partial subset, `dbms_alert` is missing on some platforms, and there's no built-in `dbms_lob`/`dbms_crypto`/`utl_smtp` equivalent | Treat orafce as a base layer only. For any package in `ddl/src/pkg`/`pkgb` that uses `dbms_sql`, `dbms_alert`, `dbms_lob`, or similar, plan a dedicated native PL/pgSQL rewrite rather than assuming orafce covers it — confirm per-package during spec derivation. |
| Building the plain-SQL harness on top of full PGXS (`pg_regress` binary + Makefile, extension packaging) | Overkill for a migration-verification project that isn't shipping a redistributable extension; adds a C toolchain/build dependency for no functional gain over a shell/Make wrapper | A thin script: `psql -f sql/<test>.sql > results/<test>.out; diff -u expected/<test>.out results/<test>.out` — same golden-file philosophy, none of the packaging overhead. |
| Installing pgTAP/orafce by compiling from source in developer containers ad hoc | Source builds drift version-to-version across machines/CI and this project needs exact-version reproducibility for the "runnable container database" deliverable | Pin exact versions via PGDG apt packages (`postgresql-17-pgtap=1.3.4*`, `postgresql-17-orafce=4.16.7*` or nearest available packaged version) in a single Dockerfile, rebuilt in CI. |
| Relying on `dblink`/background-worker tricks to emulate Oracle "autonomous transaction" semantics as a default pattern | Adds operational complexity (extra connections, commit visibility subtleties) and is easy to misuse outside the narrow cases where Oracle code actually needs autonomous commit-on-error logging | Reserve for the few packages whose spec genuinely requires autonomous-transaction logging (e.g., audit/error-log inserts that must survive a caller rollback); default assumption should be that PostgreSQL's procedure-level `COMMIT`/`ROLLBACK` (available since PG11, unlike Oracle's function/procedure autonomous pragma) covers most cases directly. Flag per-package during spec derivation rather than adopting site-wide. |

## Stack Patterns by Variant

**If a package's behavior spec includes error/exception semantics (`RAISE`, `EXCEPTION WHEN OTHERS`, custom Oracle exception codes):**
- Use pgTAP's `throws_ok()` / `throws_matching()` assertions to pin exact SQLSTATE/message expectations.
- Because Oracle's numbered user exceptions (`RAISE_APPLICATION_ERROR(-20xxx, ...)`) need an explicit mapping decision to PostgreSQL SQLSTATEs/custom conditions — this mapping itself belongs in the per-package spec, not left implicit in the ora2pg output.

**If a package's behavior is best characterized as "given these inputs, the resulting row set/output must exactly equal X" (e.g., cursor-returning procedures, report-style output):**
- Use the plain-SQL/expected-output harness instead of pgTAP.
- Because pgTAP assertions are verbose for large result-set comparisons; a straight `SELECT ... ORDER BY` diffed against a golden `.out` file is both easier to author from the derived spec and easier for a reviewer to eyeball against the Oracle source.

**If a package uses Oracle built-ins not covered by orafce at all (`dbms_lob`, `dbms_crypto`, `utl_smtp`, full `dbms_sql`):**
- Write a small native PL/pgSQL (or, if unavoidable, PL/Python/pgcrypto-backed) replacement scoped to just the calls actually used in `ddl/src`.
- Because pulling in another compatibility extension for one or two call sites adds a dependency for marginal benefit; PostgreSQL's `pgcrypto` (built-in-adjacent, ships with most distros) already covers most `dbms_crypto` use cases directly.

## Version Compatibility

| Package A | Compatible With | Notes |
|-----------|------------------|-------|
| pgTAP 1.3.3+ | PostgreSQL 17.0+ | 1.3.3 release notes explicitly call out PG17 testing and a `to_regtypemod()`-based fix for `col_type_is` correctness/performance on PG17; use 1.3.4 (current) which is a superset. |
| orafce 4.16.x | PostgreSQL 17 | Packaged builds exist for PG17 (`postgresql-17-orafce` apt, `orafce_17` dnf); verify the exact packaged point-release available in your distro's PGDG repo matches (or is newer than) 4.16.7 — some distros lag upstream by a few point releases, which is fine since the SQL migration file chain (`orafce--4.15--4.16.sql`, etc.) is additive. |
| ora2pg 25.0 | Oracle 19c source, PostgreSQL 17 target | No live Oracle connection required for `-i`/file-mode translation, which is what this project needs; live-connection features (data movement, `oracle_fdw` COPY modes) are irrelevant here since there's no Oracle instance available. |
| ZPA (rolling) | Oracle SQL/PL-SQL grammar including 23ai syntax | Grammar is a superset that comfortably covers 19c syntax; no compatibility risk in the down-version direction. |

## Sources

- [pgTAP GitHub Releases](https://github.com/theory/pgtap/releases) — verified directly via GitHub API: latest v1.3.4, 2025-10-04. Confidence: MEDIUM-HIGH (primary source, cross-checked via API not just search snippet).
- [pgTAP documentation](https://pgtap.org/documentation.html) — installation and pg_prove relationship. Confidence: MEDIUM.
- [orafce/orafce GitHub Releases](https://github.com/orafce/orafce/releases) — verified directly via GitHub API: latest VERSION_4_16_7, 2026-06-04. Confidence: MEDIUM-HIGH.
- [orafce README.asciidoc](https://github.com/orafce/orafce) (raw file fetched) — function/package coverage detail. Confidence: MEDIUM.
- [ora2pg GitHub Releases](https://github.com/darold/ora2pg/releases) — verified directly via GitHub API: latest v25.0, 2025-04-20. Confidence: MEDIUM-HIGH.
- [ora2pg documentation](https://ora2pg.darold.net/documentation.html) — CLI flags (`-p`, `-i`, `-t`, `-o`, `-N`). Confidence: MEDIUM.
- [PostgreSQL core Test Evaluation docs](https://www.postgresql.org/docs/current/regress-evaluation.html) — `pg_regress`/PGXS sql/expected/results convention. Confidence: MEDIUM (official docs via web search, not fetched raw).
- [ZPA (felipebz/zpa)](https://github.com/felipebz/zpa) — active-maintenance and AST-toolkit capability. Confidence: LOW-MEDIUM (web search summary only, not independently verified by running the tool).
- [orafce_sql (okbob/orafce_sql)](https://github.com/okbob/orafce_sql) — noted as a separate, not-yet-merged `dbms_sql` implementation. Confidence: LOW (mentioned only in passing in search results; verify directly before depending on it).
- Web search results (general orafce/ora2pg/pgTAP ecosystem context) — Confidence: LOW-MEDIUM per individual claim; treated as directional, not authoritative, wherever not corroborated by a primary source above.

---
*Stack research for: Oracle→PostgreSQL PL/SQL migration & testing tooling*
*Researched: 2026-07-10*
