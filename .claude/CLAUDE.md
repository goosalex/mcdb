<!-- GSD:project-start source:PROJECT.md -->

## Project

**MCDB Oracle → PostgreSQL Migration**

Migration of the MCDB Oracle 19c database to PostgreSQL 17+, centered on translating all programmatic elements (48 Oracle packages, standalone procedures, triggers, types) into valid, tested PL/pgSQL. The approach is spec-first: derive behavioral specifications from the Oracle package code via static analysis, then write PostgreSQL tests that verify the translated code against those specs on a live local Postgres instance. The end deliverable is a runnable container database plus a regexp list for rectifying object names in client code.

**Core Value:** Every translated PostgreSQL object behaves like its Oracle original, proven by tests derived from the Oracle code's specification — not just "compiles cleanly."

### Constraints

- **Tech stack**: PostgreSQL 17+, orafce extension explicitly allowed — reduces translation friction for Oracle built-ins
- **Naming/Compatibility**: Schema stays identical to Oracle; object names get package-name prefix (`package_in_name` convention) — keeps client migration mechanical (regexp-driven)
- **Verification**: Local Postgres 17.10 via sudo peer auth is the test target — no Oracle instance available for now
- **Concurrency cap: at most 3 subagents at once.** This box has 4 cores / 8 GB. Each agent costs ~400 MB peak, so RAM is not the limit — CPU is. Four-plus agents oversubscribe 4 cores (agents also each clone a 549-table Postgres template DB), which slows everything and lengthens the window in which a session interruption can destroy uncommitted agent work. When a GSD wave has more than 3 plans, dispatch them in batches of 3, merging each batch before starting the next.
- **Methodology**: Spec-first — specs derived from Oracle source before translation; tests verify specs, not the translation's own assumptions

<!-- GSD:project-end -->

<!-- GSD:stack-start source:codebase/STACK.md -->

## Technology Stack

## Languages

- SQL (Oracle PL/SQL) - Database DDL and procedural objects in Oracle 19c
- SQL (PostgreSQL) - Database DDL and procedural objects for PostgreSQL 17+ migration target
- Java - Build automation, test infrastructure, and ORM code generation
- Bash - Migration and deployment scripts
- Perl - Data loading and simulation scripts (`pg_migration/load_sim/*.pl`)

## Runtime

- Java Runtime Environment (JVM) - For build automation and testing
- Docker - Container-based execution for Oracle XE and ora2pg migration tool
- Kubernetes - Deployment platform for data transfer jobs
- Bazel - Build system and dependency management
- Maven/Gradle dependencies managed through Bazel (transitive)

## Frameworks

- Bazel - Build automation and test orchestration (`BUILD` file at repository root)
- JUnit5 (Jupiter) - Test framework for Java-based schema validation tests
- Testcontainers - Docker-based test infrastructure for ephemeral database testing
- Liquibase 4.21.1 - Schema version control and change management (`changes/root-changelog.xml`, liquibase-*.properties)
- Oracle Database 19c Enterprise Edition - Primary database (production source)
- PostgreSQL 17+ - Migration target database
- DataNucleus ORM - Object-relational mapping for Java (`orm-codegen` tool referenced in BUILD)
- ora2pg - Oracle-to-PostgreSQL schema and data migration tool (Docker-based container)

## Key Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| Oracle JDBC Driver | ojdbc10 | Database connectivity to Oracle 19c |
| Liquibase Core | Latest (v4.21.1 required) | Schema changelog execution and tracking |
| JUnit Jupiter API | Latest | Test framework and annotations |
| JUnit Jupiter Params | Latest | Parameterized testing support |
| Package | Version | Purpose |
|---------|---------|---------|
| Testcontainers | Latest | Containerized database test fixtures |
| Testcontainers Oracle XE | Latest | Oracle XE test container image management |
| Testcontainers JUnit Jupiter | Latest | Integration between Testcontainers and JUnit5 |
| Apache Commons Collections | 4.x | Collection utilities for test data handling |
| Apache Log4j SLF4J Bridge | Latest | Logging infrastructure via SLF4J |
| Package | Version | Purpose |
|---------|---------|---------|
| ORM Codegen (ch.open.mss) | Internal | Generates Java ORM classes from database schema |

## Configuration

- `ORACLE_PASSWORD` - Oracle instance admin password
- `ORACLE_DATABASE` - Target Oracle database/PDB name (e.g., XEPDB1)
- `ORA_PWD` - Oracle user password for ora2pg connectivity
- `SYSDBA_PASSWORD` - SYS account password for DDL export
- `PANTA_HOME` - Base path for project workspace
- `TESTCONTAINERS_RYUK_DISABLED` - Disable container cleanup (used in build automation)

| File | Purpose |
|------|---------|
| `changes/liquibase-prod.properties` | Production Oracle instance connection (`jdbc:oracle:thin:@ORAPROD`) |
| `changes/liquibase-dev.properties` | Development instance configuration |
| `changes/liquibase-container.properties` | Container-based instance configuration |
| `changes/liquibase-orm.properties` | ORM layer generation configuration |
| `tests/src/test/resources/testcontainers.properties` | Docker Hub image prefix override for artifact repository |
| `config/mc/versions.yaml` | Version tracking for configuration releases |
| `container/docker_orafree_based/Dockerfile` | Container image build specification |
| Property | Example Value | Purpose |
|----------|---------------|---------|
| driver | oracle.jdbc.OracleDriver | Oracle JDBC driver class |
| url | jdbc:oracle:thin:@ORAPROD?TNS_ADMIN=... | Oracle connection URL with TNS admin path |
| liquibase.searchPath | ../ddl,.,../mappingdata | Paths for changelog file lookup |
| changelogFile | root-changelog.xml | Root changelog entry point |
| schemas | APPID,AUTH,BIREADER,...,VPN | List of database schemas to manage (24 schemas) |
| liquibase.ddlLockTimeout | 60 | Lock acquisition timeout in seconds |

## Build System

| Target | Location | Purpose |
|--------|----------|---------|
| `:testlib` | `BUILD` | Java library containing test classes and data |
| `:tests_dependencies` | `BUILD` | Test framework dependency aggregation |
| `:current_ddl` | `BUILD` | Filegroup of DDL and configuration sources |
| `:changelog2java` | `BUILD` | Binary for generating ORM layer from schema |
| `:gen_sql2orm` | `BUILD` | Genrule that generates orm_layer.zip artifact |
| `:tests` | `BUILD` | JUnit5 test runner for schema validation |

## Platform Requirements

- Java Development Kit (JDK 11+)
- Docker Engine (for Testcontainers)
- Bazel build tool
- GNU sed (or gsed on macOS)
- Liquibase CLI v4.21.1
- Bash shell
- Docker-compatible container runtime (Docker, Podman, etc.)
- Kubernetes cluster (for data transfer workloads)
- Oracle 19c database (source/primary)
- PostgreSQL 17+ database (migration target)
- kubectl CLI for Kubernetes deployments
- Oracle Wallet for TLS/SSL connections (optional, for TCPS port 2484)

## Database Configuration

- Edition: Enterprise Edition
- Container: Oracle XE or Oracle Free 23.7 (for testing)
- PDB: XEPDB1 (Pluggable Database)
- Flashback enabled: Required for consistent data transfer
- ARCHIVELOG mode: Optional, enabled in flashback variant
- TCPS port: 2484 with self-signed Oracle Wallet at `/opt/oracle/oradata/dbconfig/EE/.tls-wallet`
- EM Express GUI: port 5500 (https://localhost:5500/em/)
- Version: 17 or higher
- Connection method: Standard libpq connection
- Schema structure: Derived from Oracle schema via ora2pg conversion

<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->

## Conventions

## Naming Patterns

- SQL files follow semantic names: `<prefix>_<package_name>.sql` for packages, `changelog-*.sql` for change logs
- Package specs: `<prefix>_<name>.sql` in `ddl/src/pkg/`
- Package bodies: `<prefix>_<name>.sql` in `ddl/src/pkgb/`
- Test packages: `<prefix>_<name>_test.sql` marked with `contextFilter:unit-tests`
- Migration output organized by pattern: `ddl/src/pkg/mss_osag_ip.sql` → `pg_migration/output/package_in_name/FUNCTION.pg.sql`
- Mixed case with descriptive names: `getbcast()`, `getnet()`, `ip2num()`, `num2ip()`, `runOsCmdGetResult()`
- Action-verb prefix pattern: `delete_*`, `grant_*`, `test_*`
- Deprecated procedures noted: e.g., "runOsCmd: Procedure is deprecated, use runOsCmdGetResult instead!" (`ddl/src/pkg/osag_osag_ext.sql`)
- Prefix convention strictly enforced:
- Record types use descriptive naming: `test_case_record`, `test_case_table`
- Index BY PLS_INTEGER for array-like collections (e.g., `TYPE test_case_table IS TABLE OF test_case_record INDEX BY PLS_INTEGER`)
- Schema-qualified names: `MSS.OSAG_IP`, `AUTH.OSAG_AUTH`, `FW.DELETE_AUTO_IP_GROUPS_TEST`, `ASERTO_TEST.E2ETEST`
- Public synonyms created for every package: `CREATE OR REPLACE PUBLIC SYNONYM osag_auth FOR auth.osag_auth` (`ddl/src/pkg/auth_osag_auth.sql`)
- Naming convention: `<SCHEMA>.<PREFIX>_<DOMAIN>_<FUNCTION>`

## Code Style

- No formal linter detected (no .eslintrc, .prettierrc, or eslint.config files found)
- Custom formatting guidelines evident from source:
- No explicit linting configuration found
- SQL adheres to Oracle PL/SQL syntax standards
- Manual code review likely (CLAUDE.md indicates this is a conversion task)

## Import Organization

- Liquibase formatted SQL uses `logicalFilePath` attribute:
- Explicit schema qualification for cross-schema access: `OSAG.OSAG_EXT`, `MSS.OSAG_IP`, `AUTH.OSAG_AUTH`
- Public synonyms provide unqualified access
- Declared in package specs with comments noting state packages:

## Error Handling

- Unified logging via `plog` package (custom logging framework):
- Oracle-specific exceptions:
- PostgreSQL equivalent (migration):

## Logging

- `plog.debug(message)` - debug level
- `plog.err(message)` - error level
- `plog.AuditUsage(unit_owner, unit_type, unit)` - audit trail
- Syslog-style levels in PostgreSQL migration: 0=Emerg, 1=Alert, 2=Crit, 3=Err, 4=Warning, 5=Notice, 6=Info, 7=Debug
- Log messages prefixed with procedure name: `c_prefix := 'OSAG_IP.ip2num(): '` then logged as `plog.debug(c_prefix||'not enough dots in ip address')` (`ddl/src/pkgb/mss_osag_ip.sql`)
- Output truncation for long values: truncate to 35 characters with ellipsis (`ddl/src/pkgb/osag_osag_ext.sql:102-103`)

## Comments

- Mandatory header block per file with Liquibase metadata:
- Copyright/author attribution where applicable:
- Section headers with alignment dashes (minimum 80 dashes):
- Parameter documentation blocks for procedures/functions with input/output descriptions:
- Not applicable (PL/SQL uses block comments)
- Extensive block documentation standard for all functions
- Deprecation notices included inline: "Procedure is deprecated, use runOsCmdGetResult instead!"

## Function Design

- Functions typically 30-150 lines
- Package bodies split by function (labeled sections with dashes)
- Longer procedures use FOR loops for clarity (e.g., IPv6 address parsing: `FOR v_byte_no IN 1..4 LOOP`)
- Strongly typed to table columns using `%TYPE` anchor: `p_login_id login.id%TYPE` (`ddl/src/pkg/auth_osag_auth.sql`)
- Deterministic functions marked explicitly: `FUNCTION num2ip(p_number NUMBER) RETURN VARCHAR2 DETERMINISTIC`
- IN/OUT/IN OUT keywords required
- Explicit RETURN statements with type
- NULL returns documented when applicable: "if p_string is null then return null; end if;"
- Success indicated by return type match (no void-like procedures in functional style)

## Module Design

- Package specs (`ddl/src/pkg/`) declare public interface
- Package bodies (`ddl/src/pkgb/`) provide implementation
- Public synonyms expose packages without schema prefix
- Not used (database packages are monolithic)
- State packages pattern: separate package for constants/exceptions (e.g., `OSAG_AUTH` main logic, `OSAG_AUTH_STATE` for state)
- Liquibase changesets control deployment:

<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->

## Architecture

## System Overview

```text

```

## Component Responsibilities

| Component | Responsibility | File/Directory |
|-----------|----------------|---|
| DDL Baseline | Captures the Oracle schema snapshot at a point in time | `ddl/generated/` |
| Source Code | Tracks current PL/SQL source (packages, procedures, functions, triggers, types, etc.) | `ddl/src/` |
| Liquibase Changelogs | Manages incremental schema changes from baseline | `changes/*.xml` and `changes/*.sql` |
| Master Data | Stores reference data snapshots organized by module | `masterdata/` |
| Migration Layer | Converts Oracle DDL and PL/SQL to PostgreSQL using ora2pg | `ddl/migrated/`, `pg_migration/` |
| Test Suite | Validates schema consistency via Java test harness | `tests/` |
| Container | Provides isolated Oracle XE instance for testing | `container/` |

## Pattern Overview

- Snapshot-based schema tracking (baseline in `ddl/generated`, evolving via Liquibase in `changes`)
- Separation of DDL (schema) and procedural code (packages, functions)
- Multi-phase migration strategy: export Oracle → batch convert via ora2pg → manual fixes → deploy to PostgreSQL
- Three architectural options for package-to-PostgreSQL translation (package-as-schema, package-in-name, schema)
- Liquibase-driven deployment with dependency ordering and idempotency

## Layers

- Purpose: Captures a fixed point-in-time snapshot of the Oracle database schema
- Location: `ddl/generated/`
- Contains: Table definitions, constraints, sequences, users/grants (split into subdirectories)
- Depends on: None (baseline)
- Used by: Liquibase as the initial state for change calculation
- Purpose: Manages incremental DDL and PL/SQL changes from baseline to current state
- Location: `changes/`
- Contains: 
- Depends on: Baseline schema from `ddl/generated/`
- Used by: Liquibase to apply changes; Java ORM codegen to verify consistency
- Purpose: Tracks original Oracle PL/SQL source code organized by object type
- Location: `ddl/src/`
- Contains: 147 SQL files organized by object type:
- Depends on: Baseline schema
- Used by: Liquibase plsql-changelog; ora2pg for migration
- Purpose: Stores reference data snapshots that populate new instances
- Location: `masterdata/`
- Contains: 25+ modules (AUTH, FW, ESP, MC, MSS, etc.), each with:
- Depends on: Baseline schema for table structure
- Used by: Migration initialization; container bootstrapping
- Purpose: Transformed Oracle DDL and PL/SQL converted to PostgreSQL-compatible syntax
- Location: `ddl/migrated/` (DDL) and `pg_migration/output/` (PL/SQL)
- Contains:
- Depends on: Liquibase changelogs (via ora2pg conversion)
- Used by: PostgreSQL deployment scripts
- Purpose: Sequences the application of schema, data, and fixes to PostgreSQL
- Location: `pg_migration/preparation/`, `pg_migration/apply/`, `pg_migration/post_apply/`
- Contains:
- Depends on: Migrated DDL from `ddl/migrated/` and PL/SQL from `pg_migration/output/`
- Used by: Migration scripts (`run_oradata2pg.sh`, `run_local_pgsql.sh`)
- Purpose: Validates schema consistency across Oracle and PostgreSQL
- Location: `tests/`
- Contains: Java Testcontainers-based JUnit5 tests
- Entry point: `tests/src/test/java/ch/open/osdb/build/changelog/ApplyTest.java`
- Depends on: Liquibase changelogs, container infrastructure
- Used by: CI pipeline to verify changelog validity

## Data Flow

### Primary Migration Path (Oracle → PostgreSQL)

### Secondary Path (Test Validation)

- Oracle MCDB is source of truth during migration (Flashback enabled to maintain consistency)
- Liquibase tracks changeset ID + author + MD5 checksum for idempotency and re-execution safety
- Each changeset marked with `runOnChange:true` for PL/SQL source to support code evolution

## Key Abstractions

- Purpose: Represents an atomic, idempotent database change
- Examples: `changes/changelog-current.sql` (changesets), `ddl/src/pkg/auth_osag_auth.sql` (Liquibase-formatted SQL)
- Pattern: XML change log includes individual SQL files via `<includeAll>` or `<include>`; each SQL file is Liquibase-formatted with `--changeset` directive
- Example changeset format from `ddl/src/pkg/auth_osag_auth.sql`:
- Purpose: Translate Oracle package namespacing to PostgreSQL (which has no packages)
- Three strategies in `pg_migration/output/`:
- Purpose: Organize master data and functional domains by business module
- Examples: `masterdata/AUTH/`, `masterdata/FW/`, `masterdata/MC/`, etc.
- Pattern: Each module directory contains CSV + XML metadata for all its reference tables
- Purpose: Batch-converts Oracle DDL and PL/SQL to PostgreSQL syntax
- Entry points: `pg_migration/preparation/300_run_ora2pg.sh`, `changes/scripts/migrate-ddl.sh`
- Output: Stored in `ddl/migrated/` (tables, views, constraints) and `pg_migration/output/` (packages, functions, types, triggers)
- Limitations: PL/SQL → PostgreSQL conversion requires manual fixes for complex logic

## Entry Points

- Location: `changes/scripts/export_prod_schema.sh`
- Triggers: Manual execution during snapshot phase
- Responsibilities: 
- Location: `changes/scripts/regenerate-ddl.sh`
- Triggers: After Oracle export; manual execution
- Responsibilities:
- Location: `changes/scripts/migrate-ddl.sh`
- Triggers: During migration phase
- Responsibilities:
- Location: `changes/scripts/regenerate-csv.sh`
- Triggers: When master data snapshots need updating
- Responsibilities:
- Location: `pg_migration/preparation/300_run_ora2pg.sh`
- Triggers: During migration preparation phase
- Responsibilities:
- Location: `container/container-entrypoint-initdb.d/`
- Triggers: When Oracle container starts
- Responsibilities:
- Location: `tests/src/test/java/ch/open/osdb/build/changelog/ApplyTest.java`
- Triggers: CI pipeline (`bazel test :tests`)
- Responsibilities:
- Location: `pg_migration/apply/` and `pg_migration/preparation/`
- Triggers: Manual execution or CI pipeline
- Responsibilities:

## Architectural Constraints

- **Threading:** Single-threaded sequential execution for Liquibase changelog application (Oracle and PostgreSQL). Parallel data migration via Kubernetes jobs (`pg_migration/k8s/`) for production scenarios.
- **Global state:** Liquibase maintains a `DATABASECHANGELOG` table on each database (Oracle and PostgreSQL) to track applied changesets by ID, author, and MD5 hash. This is the single source of truth for changeset state.
- **Circular imports:** PL/SQL packages may have dependencies encoded in include order in `changes/plsql-changelog.xml`:
- **DDL Application Order:** Strict ordering required (types → packages → procedures → triggers) to resolve dependencies. Views applied after tables; constraints applied after all base tables exist.
- **Migration Idempotency:** All Liquibase changesets marked `runOnChange:true` for PL/SQL to support code re-execution without change ID conflicts.
- **Source of Truth:** During migration, Oracle MCDB is source of truth. Changes must be completed in Oracle before PostgreSQL migration begins. Flashback capability required to ensure consistent snapshots.

## Anti-Patterns

### Incomplete Ora2Pg Conversion

- Review `pg_migration/output/` output for errors early
- Create manual fix scripts in `pg_migration/post_apply/` for complex procedures
- Example: `pg_migration/preparation/303_package_procedure_fixes.sh` applies targeted corrections
- Plan 2-3 iteration cycles for PL/SQL translation; expect 20-30% of procedures to require manual rewriting

### Missing Dependency Documentation in Changesets

- Document package dependencies as comments in `ddl/src/pkg/` files
- Verify include order in `changes/plsql-changelog.xml` matches dependency tree
- Use Liquibase `<precondition>` tags to verify prerequisite objects exist before applying a changeset
- Example: Add to package specs:

### Ignoring Liquibase Changeset Idempotency

- Always use Liquibase (`changes/liquibase-*.properties` configurations) to apply changes
- Use `runOnChange:true` for PL/SQL source files (e.g., `ddl/src/pkg/*.sql`) to force re-execution on code changes
- For one-off fixes, add them to `changes/changelog-current.sql` as numbered changesets, not to separate scripts

## Error Handling

- Liquibase changelog application stops at first error; no partial state left
- `\set ON_ERROR_STOP OFF` in PostgreSQL migration scripts allows batch execution to continue (use cautiously)
- Oracle triggers with error logging (e.g., exception handlers in package bodies) log to `DBMS_OUTPUT` or custom tables
- Java test suite catches deployment errors via Testcontainers; reports via JUnit

## Cross-Cutting Concerns

- Oracle: `DBMS_OUTPUT` for PL/SQL runtime logging; SQL*Plus logs to stdout
- PostgreSQL: PostgreSQL logs via `pg_log`; migration scripts log via `set -x` in bash
- Java tests: SLF4J configured in `tests/src/test/resources/testcontainers.properties`
- Liquibase validates changeset syntax before application
- Java test suite verifies schema consistency via JUnit assertions
- ORM codegen regeneration via `tests/update_dx_orm.sh` ensures application layer matches database schema
- Oracle: Username/password in Liquibase properties files (`changes/liquibase-*.properties`)
- PostgreSQL: Same approach; also supports `.pgpass` for password-less login
- Kubernetes data transfer jobs: Service account authentication with RBAC

<!-- GSD:architecture-end -->

<!-- GSD:skills-start source:skills/ -->

## Project Skills

No project skills found. Add skills to any of: `.claude/skills/`, `.agents/skills/`, `.cursor/skills/`, `.github/skills/`, or `.codex/skills/` with a `SKILL.md` index file.
<!-- GSD:skills-end -->

<!-- GSD:workflow-start source:GSD defaults -->

## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through a GSD command so planning artifacts and execution context stay in sync.

Use these entry points:

- `/gsd-quick` for small fixes, doc updates, and ad-hoc tasks
- `/gsd-debug` for investigation and bug fixing
- `/gsd-execute-phase` for planned phase work

Do not make direct repo edits outside a GSD workflow unless the user explicitly asks to bypass it.
<!-- GSD:workflow-end -->

<!-- GSD:profile-start -->

## Developer Profile

> Profile not yet configured. Run `/gsd-profile-user` to generate your developer profile.
> This section is managed by `generate-claude-profile` -- do not edit manually.
<!-- GSD:profile-end -->
