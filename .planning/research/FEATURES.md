# Feature Research

**Domain:** Oracle 19c → PostgreSQL 17+ database code migration (packages, procedures, triggers, types) — this milestone
**Researched:** 2026-07-10
**Confidence:** MEDIUM (web-sourced, cross-checked across multiple independent sources; no vendor/official-doc single-source claims presented as fact without corroboration)

Note on framing: this is not an end-user product. "Features" here are migration **work products and capabilities** — the artifacts and processes a competent Oracle→PostgreSQL code migration must produce to be trustworthy. Table stakes = the migration is unverified/unsafe without it. Differentiators = raises confidence and reduces post-migration surprises, but the migration is nominally usable without it. Anti-features = things this milestone should explicitly refuse to build.

## Feature Landscape

### Table Stakes (Migration Is Unsafe Without These)

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Per-package behavioral spec (signature, semantics, side effects, error behavior, transaction behavior) | Without a spec independent of the ora2pg output, there is no ground truth to test against — the translation would be validated against itself | MEDIUM | Already an Active requirement. Derived by static analysis of `ddl/src/pkg`+`pkgb` per PROJECT.md; must capture exceptions raised, DML performed, commit/rollback behavior, and OUT/return semantics per public routine. |
| Dependency-ordered translation (types → packages/specs → package bodies → procedures → triggers) | PL/pgSQL objects fail to compile/deploy if referenced objects don't exist yet; Oracle's forward-declaration tolerance doesn't carry over | LOW | Already encoded in `changes/plsql-changelog.xml` include order; must be preserved/re-derived for the 48 packages plus cross-package call graph (a package calling another package needs that other package's translated objects to exist first). |
| Exception/error-code mapping table (Oracle SQLCODE / RAISE_APPLICATION_ERROR ranges → PostgreSQL SQLSTATE / custom codes) | Oracle uses numeric SQLCODE and `-20000..-20999` app errors; PL/pgSQL requires 5-char SQLSTATE on RAISE EXCEPTION. Without an explicit, consistently-applied mapping, error-handling call sites silently diverge in behavior | MEDIUM | One documented mapping (a metadata table or a fixed convention, e.g. custom SQLSTATE class `P0xxx`/`OSxx`) applied uniformly across all 48 packages — not ad hoc per file. orafce can supply some Oracle-style error helpers but does not replace this mapping. |
| Transaction-semantics audit per routine (autonomous transactions, implicit commits, exception-triggered rollback points) | PostgreSQL has no native autonomous transactions; naive translation silently changes commit boundaries, which corrupts data integrity invisibly (no compile error) | HIGH | Must be an explicit checklist item per package: does this procedure rely on Oracle autonomous transaction (`PRAGMA AUTONOMOUS_TRANSACTION`)? If yes, decide per-case: refactor to avoid it (preferred) vs. dblink/pg_background emulation (only as last resort — adds connection overhead and operational complexity). |
| Test per public routine, both pgTAP (unit-style) and plain-SQL/expected-output (regression-style) | Already an Active requirement (dual harness). Without a test per public routine, "translated" and "compiles" are conflated with "behaves correctly" | HIGH (48 packages × ~avg routines) | pgTAP: use procedures+CALL over functions where reliability with pg_prove matters; ensure deterministic ORDER BY before `results_eq`; isolate/clean up PREPARE artifacts between runs. Plain-SQL/expected-output: good default for regression-style checks with minimal dependencies, useful where pgTAP's fixture machinery is overkill. |
| CI-runnable test suite (pg_prove + plain-SQL harness, scriptable, non-interactive) | A test suite nobody runs automatically decays; "verified green" (an Active requirement) needs a single repeatable command, not manual `psql` sessions | LOW-MEDIUM | pg_prove is the standard pgTAP runner; dockerize or script against the local Postgres 17.10 instance already available via peer auth. Must be re-runnable from a clean container state (see next row). |
| Idempotent, ordered deployment scripts (DDL + masterdata + translated code) | Already implied by "runnable container database" Active requirement; without idempotency, re-running a fix breaks on "already exists" errors, which is exactly what happened historically with ora2pg's raw batch scripts | MEDIUM | Liquibase already provides `runOnChange:true` idempotency pattern for PL/SQL in the existing repo — reuse that mechanism (or PostgreSQL-native equivalent: `CREATE OR REPLACE`, `DROP...IF EXISTS`) rather than inventing a new one. |
| Runnable container bootstrap (schema + masterdata + translated code, standing up from nothing, tests passing) | Already an Active requirement; this is the actual "done" signal for the milestone — a bag of translated .sql files with no proof they compose is not a deliverable | MEDIUM | Builds on existing `container/` patterns (currently Oracle-only); needs a PostgreSQL-target equivalent entrypoint sequence. |
| Cross-reference rewrite pass (every call site updated to the new `package_in_name` object names) | Already an Active requirement; a translated package is useless if other translated packages still call it by the old Oracle-qualified name | MEDIUM | This is internal (SQL-to-SQL) renaming — distinct from the external Perl/Java regexp deliverable below. Must be systematic (script-driven), not manual per-file editing, given 48 packages' worth of cross-calls. |
| Client-code rename regexp list (Perl/Java) | Already an Active requirement/deliverable; without it, the schema-identical-but-renamed-objects decision (`package_in_name`) is not actually consumable by client teams | LOW-MEDIUM | Deliver as literal regexp pairs (old qualified name → new flat name) per package/object, generated mechanically from the same mapping used for the internal cross-reference rewrite — not hand-derived a second time. |
| Package-local/global state translation decision per package (session variable vs. temp table vs. refactor away) | Oracle package-level variables (session-persistent state across calls in a session) have no direct PostgreSQL equivalent; silently dropping this state changes behavior for any package that uses it | MEDIUM | Needs a decision per package that has package-level state: custom GUC (`current_setting`/`set_config`, session-scoped) for simple scalars, or a temp table (Oracle GTT-like, via `pgtt` extension or a real temp table) for structured state. Must be flagged explicitly in the spec, not left implicit. |

### Differentiators (Raise Confidence / Reduce Post-Migration Surprise)

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Coverage metric per package (% of public routines with at least one spec-derived test) | Turns "we tested it" into a checkable number; surfaces which of the 48 packages are under-tested before declaring the milestone done | LOW | Simple to compute (count public routines in spec vs. count referenced in test files); high leverage for milestone-exit confidence. |
| Behavioral gotcha checklist applied per package (NULL vs. empty string, `SUBSTR`/string-function edge cases, implicit type coercion, date arithmetic) | Oracle/PostgreSQL diverge on well-known semantics (Oracle treats `''` as NULL; PostgreSQL does not) that syntax-only conversion never catches — these are exactly the bugs that show up in production, not in compilation | MEDIUM | Turn the known Oracle/PG semantic-gap list into a standing review checklist applied during spec derivation and again during test-writing, so it's caught twice. |
| Dependency graph artifact (which package calls which, machine-readable) | Makes the dependency-ordered translation defensible and re-checkable instead of tribal knowledge; also is exactly the input needed to generate the cross-reference and client regexp deliverables mechanically | LOW-MEDIUM | Can be derived once via static analysis of `ddl/src/pkg`/`pkgb` (grep/parse call sites) and reused for three purposes: translation ordering, internal cross-ref rewrite, and client regexp generation. |
| Named/documented Oracle→SQLSTATE mapping surfaced as a reusable table/reference (not just applied ad hoc) | Makes the exception-mapping table-stakes item auditable and reusable across all 48 packages instead of reinvented per file, and gives future maintainers a single place to look | LOW | Natural byproduct of doing the table-stakes exception mapping properly; promote it from "applied convention" to "documented artifact." |
| Golden-master / behavioral diff testing against a live Oracle instance | Strongest possible confidence — same inputs run against real Oracle and real PostgreSQL, outputs diffed | HIGH | Explicitly out of scope for now per PROJECT.md ("no live Oracle instance available"; static-analysis-derived specs are the interim ground truth). Flag as a strong candidate for a later milestone once an Oracle 19c container is available — do not attempt to fake this by hand-simulating Oracle behavior now (see anti-features). |
| Automated name-refactoring tooling (script that both rewrites internal cross-references AND emits the client regexp list from one source of truth) | Reduces manual-edit risk across 48 packages' worth of renamed objects; one bug in a hand-edited call site is a silent behavior change | MEDIUM | Builds directly on the dependency graph artifact above; turns two Active requirements (cross-ref rewrite, regexp deliverable) into one generated artifact instead of two independently-maintained ones. |
| Transaction-boundary test cases specifically targeting autonomous-transaction-derived code | Autonomous transactions are the single highest-risk transaction-semantics gap (silent data-integrity divergence); dedicated tests here catch what generic pgTAP coverage might miss | MEDIUM | Only relevant for the subset of packages actually using `PRAGMA AUTONOMOUS_TRANSACTION` — target effort there rather than spreading thin. |

### Anti-Features (Deliberately Do Not Build)

| Feature | Why It Seems Appealing | Why Problematic | Alternative |
|---------|------------------------|------------------|-------------|
| Full PL/SQL emulation/compatibility layer (a generic runtime that reinterprets Oracle PL/SQL semantics inside PostgreSQL) | Feels like it would make every package "just work" without manual translation | Massive, open-ended scope; duplicates what orafce already covers for built-ins; produces code that still "behaves like PL/SQL" (line-by-line translated) rather than idiomatic PL/pgSQL — hard to maintain, and defers rather than resolves the semantic-gap problems (NULL handling, autonomous transactions, package state) that need real per-package decisions anyway | Translate each package's *intent* to native PL/pgSQL, using orafce only for genuine Oracle built-in gaps (already an approved Constraint), and make an explicit per-package decision for state/transactions/exceptions as described above. |
| Over-generic, package-agnostic translation framework/DSL for future migrations | Looks efficient — "build it once, translate all 48 packages through it" | This milestone has a fixed, known, finite set of 48 packages + 2 procs + 8 triggers + 2 types; building a general framework is speculative generalization that inflates scope and delays the actual verified deliverable (a runnable, tested container DB) | Do direct, spec-verified translation per package. If genuine repeated patterns emerge (e.g., a recurring exception-mapping idiom), extract a small shared helper/convention after the fact, not a framework up front. |
| Simulating a full Oracle execution baseline by hand (manually working out "what Oracle would return") to substitute for real behavioral diffing | Tempting since no live Oracle instance is available now, and it looks like it closes the golden-master gap | Manually reasoned "Oracle behavior" is exactly the kind of unverified assumption spec-first methodology is meant to avoid — it's trusting a guess dressed up as ground truth, worse than clearly labeling the gap | Rely on static-analysis-derived specs (current approach, honestly labeled as such) and flag live-Oracle behavioral diffing as explicit future work once an Oracle 19c container is available (already anticipated in PROJECT.md Out of Scope). |
| Migrating/translating jobs, AQ queues, materialized view logs/mviews in this milestone | They're part of `ddl/src` and touching them "while we're in there" looks efficient | These require architectural replacements (pg_cron, LISTEN/NOTIFY, refresh strategy), not code translation — mixing them into the code-translation milestone conflates two different kinds of risk and blocks the code-translation deliverable on unrelated architecture decisions | Already correctly scoped out in PROJECT.md; keep them deferred to a dedicated later milestone. |
| Applying the client-code regexps to actual Perl/Java codebases | Feels like "finishing the job" since the migration isn't truly done until clients are updated | Out of this team's control/scope per PROJECT.md; client codebases have their own release cycles, review processes, and ownership — bundling this in creates a dependency this milestone can't control | Deliver the regexp list as the complete artifact (already correctly scoped); client teams own applying it. |
| One-off/manual SQL fixes applied outside the Liquibase-tracked (or equivalent) pipeline | Fast when a single script is broken and "just needs a tweak" | Breaks changeset idempotency tracking (documented anti-pattern already observed in this codebase's own architecture doc — `DATABASECHANGELOG` desyncs), causing dual-applies or silently stale deployments later | Every fix goes through the same tracked, idempotent deployment mechanism used for everything else — no exceptions, even for "quick" corrections. |

## Feature Dependencies

```
Per-package behavioral spec
    └──requires──> (static analysis of ddl/src/pkg + pkgb, already available)

Dependency graph artifact
    └──enables──> Dependency-ordered translation
    └──enables──> Cross-reference rewrite pass
    └──enables──> Client-code rename regexp list
    └──enables──> Automated name-refactoring tooling (differentiator)

Exception/error-code mapping table
    └──requires──> Per-package behavioral spec (must capture what each routine raises)
    └──enables──> Tests per public routine (error-path assertions need the mapping to assert against)

Transaction-semantics audit
    └──requires──> Per-package behavioral spec
    └──enables──> Transaction-boundary test cases (differentiator)
    └──conflicts-with──> Full PL/SQL emulation layer (anti-feature: audit forces explicit per-case decisions instead of blanket emulation)

Package-local/global state translation decision
    └──requires──> Per-package behavioral spec
    └──enables──> Tests per public routine (state-dependent routines need the decision made first to be testable)

Tests per public routine (pgTAP + plain-SQL)
    └──requires──> Exception/error-code mapping table
    └──requires──> Transaction-semantics audit
    └──requires──> Package-local/global state translation decision
    └──enables──> CI-runnable test suite
    └──enables──> Coverage metric per package (differentiator)

CI-runnable test suite
    └──enables──> Runnable container bootstrap (tests must run against it to prove "green")

Idempotent, ordered deployment scripts
    └──requires──> Dependency-ordered translation
    └──enables──> Runnable container bootstrap

Runnable container bootstrap
    └──requires──> Idempotent, ordered deployment scripts
    └──requires──> CI-runnable test suite
    (this is the milestone's terminal "done" artifact)

Golden-master live-Oracle diffing (differentiator, future milestone)
    └──enhances──> Per-package behavioral spec (would validate/correct the static-analysis-derived spec)
```

### Dependency Notes

- **Dependency graph artifact enables three other deliverables:** building it once (from static analysis of call sites in `ddl/src/pkg`/`pkgb`) pays for itself by feeding translation ordering, the internal cross-reference rewrite, and the external client regexp list from a single source of truth — build this early, not per-package ad hoc.
- **Tests per public routine requires three prior decisions:** exception mapping, transaction-semantics audit, and state-translation decision must each be made before a routine's tests can be written correctly — writing tests first and "discovering" these decisions mid-test risks inconsistent per-package conventions. Sequence spec-derivation work to surface these three items explicitly, per package, before test-writing starts.
- **Transaction-semantics audit conflicts with the full-emulation-layer anti-feature:** the audit's entire value is forcing an explicit per-routine decision (refactor vs. dblink/pg_background vs. accept-the-difference); a generic emulation layer would paper over exactly the cases that need a human decision, defeating the audit's purpose.
- **Golden-master diffing enhances but does not gate this milestone:** it would strengthen confidence in the static-analysis-derived specs, but PROJECT.md already correctly defers it (no live Oracle instance now) — do not let its absence block the milestone; do flag it as the top follow-up research item for later.

## MVP Definition

Framed against this milestone's actual Active requirements (this is a migration milestone, not a product — "MVP" here means "minimum for the milestone to be truthfully called done").

### Launch With (this milestone)

- [ ] Per-package behavioral spec for all 48 packages — the ground truth everything else checks against
- [ ] Dependency graph / ordering across packages, procedures, triggers, types
- [ ] Exception/error-code mapping table, applied consistently
- [ ] Transaction-semantics audit per package (flag autonomous-transaction usage explicitly)
- [ ] Package-state translation decision per package that needs it
- [ ] Dual test harness (pgTAP + plain-SQL/expected-output) set up and runnable
- [ ] Test coverage for every public routine in all 48 packages, 2 procedures, 8 triggers
- [ ] All translated PL/pgSQL objects (package_in_name naming), cross-references rewritten
- [ ] CI-runnable test suite, all green against local Postgres 17
- [ ] Idempotent deployment scripts, dependency-ordered
- [ ] Runnable container: DDL + masterdata + translated code + tests passing from scratch
- [ ] Client-code rename regexp list (Perl/Java)

### Add After Validation (next milestone or later in this one if time allows)

- [ ] Coverage metric report per package (% public routines tested) — cheap, high-value, add once the base test suite exists
- [ ] Documented/reusable Oracle→SQLSTATE mapping reference (promote from applied convention to standalone artifact)
- [ ] Automated tooling that generates both the internal cross-reference rewrite and the client regexp list from the same dependency-graph source of truth (reduces risk of the two drifting apart)

### Future Consideration (later milestones, explicitly out of scope now)

- [ ] Golden-master/behavioral diffing against a live Oracle 19c container — do this once an Oracle container is available, to validate/correct the static-analysis-derived specs
- [ ] Jobs (pg_cron replacement), AQ queues (LISTEN/NOTIFY or queue tables), materialized view logs/mviews — architectural replacement work, separate milestone
- [ ] Applying the regexp list to real Perl/Java client codebases — owned by client teams, not this milestone

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Per-package behavioral spec | HIGH | MEDIUM | P1 |
| Dependency graph artifact | HIGH | LOW-MEDIUM | P1 |
| Exception/SQLSTATE mapping table | HIGH | MEDIUM | P1 |
| Transaction-semantics audit | HIGH | HIGH | P1 |
| Package-state translation decision | MEDIUM-HIGH | MEDIUM | P1 |
| Dual test harness setup | HIGH | MEDIUM | P1 |
| Test per public routine | HIGH | HIGH | P1 |
| CI-runnable test suite | HIGH | LOW-MEDIUM | P1 |
| Idempotent deployment scripts | HIGH | MEDIUM | P1 |
| Runnable container bootstrap | HIGH | MEDIUM | P1 |
| Cross-reference rewrite pass | HIGH | MEDIUM | P1 |
| Client regexp list | HIGH | LOW-MEDIUM | P1 |
| Coverage metric per package | MEDIUM | LOW | P2 |
| Documented SQLSTATE mapping reference | MEDIUM | LOW | P2 |
| Automated name-refactor tooling (unified generator) | MEDIUM | MEDIUM | P2 |
| Golden-master diffing vs. live Oracle | HIGH (confidence) | HIGH | P3 (future milestone) |
| Full PL/SQL emulation layer | LOW (illusory) | VERY HIGH | Do not build |
| Generic translation framework/DSL | LOW (illusory) | HIGH | Do not build |

**Priority key:**
- P1: Must have — this milestone is not truthfully "done" without it (matches PROJECT.md Active requirements)
- P2: Should have — meaningfully raises confidence, add if time allows within this milestone
- P3: Future milestone — correctly deferred, don't let it block P1

## Competitor / Reference-Approach Analysis

Not a market-competitor domain; instead, comparing known industry approaches to the same migration problem:

| Concern | ora2pg-only approach (raw/naive) | AWS DMS / cloud-vendor tooling | This project's spec-first approach |
|---------|-----------------------------------|-------------------------------|--------------------------------|
| Ground truth for correctness | None — trusts the tool's own output | Vendor migration playbooks + manual testing guidance, still recommends manual validation | Static-analysis-derived spec per package, independent of the translation tool's output |
| Package naming collisions | Not handled by default (lowercase-only rename) | Explicit rename directives (e.g. `RENAME_PACKAGES`) mapping old→new names | `package_in_name` convention already chosen; needs the same explicit, mechanical mapping applied to all 48 packages |
| Exception handling | Left to manual post-fix | Documented but manual metadata-table mapping approach recommended | Formalized as a P1 deliverable (mapping table), not left ad hoc |
| Autonomous transactions | Not converted correctly (known ora2pg limitation) | dblink/pg_background workarounds documented, refactor recommended first | Explicit per-package audit that forces a refactor-vs-workaround decision, rather than blanket-applying a workaround |
| Testing | "20-30% of procedures typically need manual rewriting"; testing often an afterthought | Unit test each converted routine + regression test + data-level diff recommended as best practice | Dual harness with per-routine coverage as a P1 requirement — stronger than typical practice, matches the "vendor best practice" tier |

## Sources

- [Ora2Pg documentation](https://ora2pg.darold.net/documentation.html)
- [PL/SQL to PostgreSQL Migration Guide: Challenges, Tools & Best Practices — Newt Global](https://newtglobal.com/blogs/oracle-to-postgresql-migration-plsql-conversion/)
- [Standard Operating Procedure: Oracle to PostgreSQL Migration using Ora2Pg — Medium](https://medium.com/@jramcloud1/01-standard-operating-procedure-sop-oracle-to-postgresql-migration-using-ora2pg-7a5d5a36dd8b)
- [pgTAP documentation](https://pgtap.org/documentation.html)
- [Testing user-defined functions with pgTAP — End Point Dev](https://www.endpointdev.com/blog/2023/09/testing-user-defined-functions-with-pgtap/)
- [Create a unit testing framework for PostgreSQL using the pgTAP extension — AWS Database Blog](https://aws.amazon.com/blogs/database/create-a-unit-testing-framework-for-postgresql-using-the-pgtap-extension/)
- [How to test PROCEDURES (NOT functions) in PostgreSQL with pgTAP — pgtap-users group](https://groups.google.com/g/pgtap-users/c/5H__ySXcG5M)
- [Migrating Exception Handling from Oracle to YugabyteDB — YugabyteDB Tips](https://yugabytedb.tips/migrating-exception-handling-from-oracle-to-yugabytedb/)
- [SQLCODE Variable — Oracle to PostgreSQL Migration — SQLines Tools](https://www.sqlines.com/oracle-to-postgresql/sqlcode)
- [Migrate Oracle Database error codes to Aurora PostgreSQL — AWS Prescriptive Guidance](https://docs.aws.amazon.com/prescriptive-guidance/latest/patterns/migrate-oracle-database-error-codes-to-an-amazon-aurora-postgresql-compatible-database.html)
- [Your Schema, Your Rules: Control Database Migrations with New Directives — Google Cloud Medium](https://medium.com/google-cloud/your-schema-your-rules-control-database-migrations-with-new-directives-c257613e9699)
- [Migrating Oracle Autonomous Transactions to PostgreSQL — AWS Database Blog](https://aws.amazon.com/blogs/database/migrating-oracle-autonomous-transactions-to-postgresql/)
- [Handling Autonomous Transactions in Oracle and PostgreSQL — convert-in.com](https://www.convert-in.com/docs/ora2pgs/autonomous-transactions)
- [Autonomous transaction support in PostgreSQL — Dalibo blog](https://blog.dalibo.com/2016/08/19/Autonoumous_transactions_support_in_PostgreSQL.html)
- [Implementing Autonomous Transactions in Postgres — CYBERTEC](https://www.cybertec-postgresql.com/en/implementing-autonomous-transactions-in-postgres/)
- [Same SQL, Different Results: A Subtle Oracle vs PostgreSQL Migration Bug](https://databaserookies.wordpress.com/2026/01/30/same-sql-different-results-a-subtle-oracle-vs-postgresql-migration-bug/)
- [Gold Master Testing — Hashrocket](https://hashrocket.com/blog/posts/gold-master-testing)
- [Oracle database migration testing and bug fixing — AWS DMS Sample Guide](https://docs.aws.amazon.com/dms/latest/sbs/chap-oracle-postgresql.migration-process.testing.html)
- [pgtt — GitHub (Darold), Oracle-style Global Temporary Tables extension](https://github.com/darold/pgtt)
- [Using custom variables as per-session global variables](https://fluca1978.github.io/2023/08/24/PostgreSQLSETCustomVariables.html)
- [Oracle package Global variables migration to PostgreSQL — ora2pg issue #970](https://github.com/darold/ora2pg/issues/970)
- [The Anti-Corruption Pattern and Legacy Migration Strategies](https://www.atelier-solutions.com/the-anti-corruption-pattern-and-legacy-migration-strategies/)
- Project-internal: `.planning/PROJECT.md`, `.planning/codebase/ARCHITECTURE.md`

---
*Feature research for: Oracle 19c → PostgreSQL 17+ code migration (packages/procedures/triggers/types)*
*Researched: 2026-07-10*
