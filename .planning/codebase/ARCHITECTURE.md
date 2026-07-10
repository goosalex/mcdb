<!-- refreshed: 2026-07-10 -->
# Architecture

**Analysis Date:** 2026-07-10

## System Overview

```text
┌─────────────────────────────────────────────────────────────────┐
│                    Application Layer                             │
│              (Java ORM Layer / Application Code)                │
└────────────┬──────────────────────────────────────────────────┘
             │
┌────────────▼──────────────────────────────────────────────────┐
│              Database Schema Layer (DDL)                        │
│  Programmatic Elements: Packages, Procedures, Functions, Types │
│  `ddl/src/` (Oracle source)                                    │
│  `pg_migration/output/` (PostgreSQL migrated)                  │
└────────────┬──────────────────────────────────────────────────┘
             │
┌────────────▼──────────────────────────────────────────────────┐
│            Data & Metadata Layer                               │
│  Tables | Views | Materialized Views | Master Data             │
│  `ddl/generated/` (Oracle baseline)                            │
│  `ddl/migrated/` (PostgreSQL batch-migrated via ora2pg)        │
│  `masterdata/` (Reference data snapshots)                      │
└────────────┬──────────────────────────────────────────────────┘
             │
┌────────────▼──────────────────────────────────────────────────┐
│         Change Tracking & Orchestration (Liquibase)            │
│  `changes/` - Changelogs, scripts, configuration               │
│  Coordinates deployment across Oracle and PostgreSQL           │
└────────────┬──────────────────────────────────────────────────┘
             │
┌────────────▼──────────────────────────────────────────────────┐
│  Migration Tooling & Validation                                │
│  `pg_migration/` - ora2pg conversion and PG deployment         │
│  `tests/` - Java test harness with Testcontainers             │
│  `container/` - Docker container orchestration                │
└─────────────────────────────────────────────────────────────────┘
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

**Overall:** Liquibase-based database migration from Oracle to PostgreSQL using a staged approach: baseline snapshot → incremental changes → migration conversion → validation.

**Key Characteristics:**
- Snapshot-based schema tracking (baseline in `ddl/generated`, evolving via Liquibase in `changes`)
- Separation of DDL (schema) and procedural code (packages, functions)
- Multi-phase migration strategy: export Oracle → batch convert via ora2pg → manual fixes → deploy to PostgreSQL
- Three architectural options for package-to-PostgreSQL translation (package-as-schema, package-in-name, schema)
- Liquibase-driven deployment with dependency ordering and idempotency

## Layers

**Baseline Schema Layer:**
- Purpose: Captures a fixed point-in-time snapshot of the Oracle database schema
- Location: `ddl/generated/`
- Contains: Table definitions, constraints, sequences, users/grants (split into subdirectories)
- Depends on: None (baseline)
- Used by: Liquibase as the initial state for change calculation

**Change Tracking Layer:**
- Purpose: Manages incremental DDL and PL/SQL changes from baseline to current state
- Location: `changes/`
- Contains: 
  - `changelog-current.sql` - Current incremental SQL changes
  - `changelog-1.archive.sql` - Historical archived changes
  - `plsql-changelog.xml` - PL/SQL objects (packages, procedures, functions)
  - `root-changelog.xml` - Orchestration file that includes all others in dependency order
- Depends on: Baseline schema from `ddl/generated/`
- Used by: Liquibase to apply changes; Java ORM codegen to verify consistency

**Source Code Layer:**
- Purpose: Tracks original Oracle PL/SQL source code organized by object type
- Location: `ddl/src/`
- Contains: 147 SQL files organized by object type:
  - `pkg/` - Oracle packages (spec and body)
  - `proc/` - Standalone procedures
  - `pkgb/` - Package bodies
  - `triggers/` - Database triggers
  - `types/` - User-defined types
  - `functions/` - Standalone functions
  - `jobs/` - Oracle DBMS jobs
  - `queues/` - Advanced Queuing
  - `roles/` - Role definitions
  - `users/` - User/schema definitions
  - `global/` - Global DDL and constants
  - `mlog/` - Materialized view logs
  - `mviews/` - Materialized view definitions
  - `tests/` - Test procedures
- Depends on: Baseline schema
- Used by: Liquibase plsql-changelog; ora2pg for migration

**Master Data Layer:**
- Purpose: Stores reference data snapshots that populate new instances
- Location: `masterdata/`
- Contains: 25+ modules (AUTH, FW, ESP, MC, MSS, etc.), each with:
  - CSV files containing actual reference data
  - XML metadata (JDO properties)
- Depends on: Baseline schema for table structure
- Used by: Migration initialization; container bootstrapping

**Migration Output Layer:**
- Purpose: Transformed Oracle DDL and PL/SQL converted to PostgreSQL-compatible syntax
- Location: `ddl/migrated/` (DDL) and `pg_migration/output/` (PL/SQL)
- Contains:
  - `ddl/migrated/tables/` - PostgreSQL table definitions
  - `ddl/migrated/constraints/` - Constraint definitions
  - `ddl/migrated/mviews/` - View definitions
  - `pg_migration/output/package_as_schema/` - Packages as schemas approach
  - `pg_migration/output/package_in_name/` - Package name prefix approach
  - `pg_migration/output/schema/` - Pure schema approach
- Depends on: Liquibase changelogs (via ora2pg conversion)
- Used by: PostgreSQL deployment scripts

**Deployment Orchestration Layer:**
- Purpose: Sequences the application of schema, data, and fixes to PostgreSQL
- Location: `pg_migration/preparation/`, `pg_migration/apply/`, `pg_migration/post_apply/`
- Contains:
  - `preparation/` - Database initialization (100_database.sql, 200_roles.sql, ora2pg invocation)
  - `apply/` - Schema application in numbered sequence (users → tables → views → constraints)
  - `post_apply/` - Fix scripts for syntax issues that require manual adjustment
- Depends on: Migrated DDL from `ddl/migrated/` and PL/SQL from `pg_migration/output/`
- Used by: Migration scripts (`run_oradata2pg.sh`, `run_local_pgsql.sh`)

**Testing & Validation Layer:**
- Purpose: Validates schema consistency across Oracle and PostgreSQL
- Location: `tests/`
- Contains: Java Testcontainers-based JUnit5 tests
- Entry point: `tests/src/test/java/ch/open/osdb/build/changelog/ApplyTest.java`
- Depends on: Liquibase changelogs, container infrastructure
- Used by: CI pipeline to verify changelog validity

## Data Flow

### Primary Migration Path (Oracle → PostgreSQL)

1. **Snapshot Phase** (`ddl/generated/`, `masterdata/`)
   - Oracle MCDB exported via `changes/scripts/export_prod_schema.sh`
   - DDL split and stored in `ddl/generated/` (users, tables, sequences, grants, constraints)
   - Master data exported to `masterdata/` as CSV + XML metadata
   - Entry point: `changes/scripts/exportddl.sh` calls Java `ExportDDL.java`

2. **Change Accumulation** (`changes/`)
   - Liquibase tracks changes from baseline in `changelog-current.sql` (DDL) and `plsql-changelog.xml` (code)
   - PL/SQL source continuously updated in `ddl/src/`
   - Changes committed to repository and versioned

3. **Conversion Phase** (`ddl/migrated/`, `pg_migration/output/`)
   - `changes/scripts/migrate-ddl.sh` invokes ora2pg to convert DDL to PostgreSQL syntax
   - `pg_migration/preparation/300_run_ora2pg.sh` converts PL/SQL code
   - Three schema strategies generated in `pg_migration/output/`:
     - `package_as_schema/` - Each package becomes a PostgreSQL schema
     - `package_in_name/` - Package name used as prefix to all objects
     - `schema/` - Flat schema approach
   - Converted files stored in `ddl/migrated/` and `pg_migration/output/`

4. **Manual Fixes Phase** (`pg_migration/post_apply/`)
   - Ora2pg limitations identified; manual fixes created
   - `pg_migration/preparation/303_package_procedure_fixes.sh` applies corrections
   - Complex PL/SQL logic may require manual rewriting

5. **Deployment Phase** (`pg_migration/apply/`, `pg_migration/preparation/`)
   - Sequential SQL/shell script execution to PostgreSQL:
     1. `preparation/100_database.sql` - Create PostgreSQL database
     2. `preparation/200_roles.sql` - Create database roles/users
     3. `apply/100_apply_users.sh` - Apply user schema definitions
     4. `apply/110_schema_users.sql` - Create users/schemas
     5. `apply/200_apply_tables.sh` - Apply table definitions
     6. `apply/301_fixes.views.sql` - Fix view syntax
     7. `apply/302_fix_constraint_syntax.sh` - Fix constraint definitions
   - Data migration via Kubernetes jobs (see `apply/400_deploy_k8s_dev_datatransfer.sh`)

6. **Validation & Seeding**
   - `pg_migration/load_sim/` - Simple stress tests post-migration
   - Master data loaded from `masterdata/` CSV files
   - Schema consistency verified via test suite

### Secondary Path (Test Validation)

1. Container instantiation via `container/container-entrypoint-initdb.d/` scripts
2. Liquibase changelog application to Oracle XE container
3. Schema verification via Java test suite (`tests/src/test/java/.../ApplyTest.java`)
4. ORM codegen validation via `tests/update_dx_orm.sh`

**State Management:**
- Oracle MCDB is source of truth during migration (Flashback enabled to maintain consistency)
- Liquibase tracks changeset ID + author + MD5 checksum for idempotency and re-execution safety
- Each changeset marked with `runOnChange:true` for PL/SQL source to support code evolution

## Key Abstractions

**Liquibase Changeset:**
- Purpose: Represents an atomic, idempotent database change
- Examples: `changes/changelog-current.sql` (changesets), `ddl/src/pkg/auth_osag_auth.sql` (Liquibase-formatted SQL)
- Pattern: XML change log includes individual SQL files via `<includeAll>` or `<include>`; each SQL file is Liquibase-formatted with `--changeset` directive
- Example changeset format from `ddl/src/pkg/auth_osag_auth.sql`:
  ```sql
  --liquibase formatted sql logicalFilePath:pkg/auth_osag_auth.sql
  --changeset sys:1 runOnChange:true endDelimiter:/
  CREATE OR REPLACE PACKAGE AUTH.OSAG_AUTH IS ... END OSAG_AUTH;
  /
  ```

**Schema Object Naming (Packages → PostgreSQL):**
- Purpose: Translate Oracle package namespacing to PostgreSQL (which has no packages)
- Three strategies in `pg_migration/output/`:
  1. `package_as_schema/` - `AUTH.OSAG_AUTH` → schema `auth` + objects named `osag_auth`
  2. `package_in_name/` - `AUTH.OSAG_AUTH` → schema `public` + objects named `auth_osag_auth`
  3. `schema/` - All objects in single schema with flattened names

**Module Organization:**
- Purpose: Organize master data and functional domains by business module
- Examples: `masterdata/AUTH/`, `masterdata/FW/`, `masterdata/MC/`, etc.
- Pattern: Each module directory contains CSV + XML metadata for all its reference tables

**Ora2Pg Conversion:**
- Purpose: Batch-converts Oracle DDL and PL/SQL to PostgreSQL syntax
- Entry points: `pg_migration/preparation/300_run_ora2pg.sh`, `changes/scripts/migrate-ddl.sh`
- Output: Stored in `ddl/migrated/` (tables, views, constraints) and `pg_migration/output/` (packages, functions, types, triggers)
- Limitations: PL/SQL → PostgreSQL conversion requires manual fixes for complex logic

## Entry Points

**Oracle Export (One-time Baseline):**
- Location: `changes/scripts/export_prod_schema.sh`
- Triggers: Manual execution during snapshot phase
- Responsibilities: 
  - Exports current Oracle MCDB schema via `expdp` (Oracle Data Pump)
  - Captures baseline DDL snapshot

**DDL Regeneration:**
- Location: `changes/scripts/regenerate-ddl.sh`
- Triggers: After Oracle export; manual execution
- Responsibilities:
  - Splits raw Oracle DDL dump into organized structure in `ddl/generated/`
  - Invokes Java `ExportDDL.java` to parse and organize DDL by object type

**DDL Migration to PostgreSQL:**
- Location: `changes/scripts/migrate-ddl.sh`
- Triggers: During migration phase
- Responsibilities:
  - Converts Oracle DDL to PostgreSQL syntax via ora2pg
  - Outputs to `ddl/migrated/`

**Master Data Regeneration:**
- Location: `changes/scripts/regenerate-csv.sh`
- Triggers: When master data snapshots need updating
- Responsibilities:
  - Exports reference data from Oracle tables
  - Generates CSV + XML metadata in `masterdata/`

**PL/SQL Migration:**
- Location: `pg_migration/preparation/300_run_ora2pg.sh`
- Triggers: During migration preparation phase
- Responsibilities:
  - Converts Oracle packages, procedures, functions, triggers to PostgreSQL
  - Outputs to `pg_migration/output/` with three naming strategy options
  - Identifies areas requiring manual fixes

**Container Initialization:**
- Location: `container/container-entrypoint-initdb.d/`
- Triggers: When Oracle container starts
- Responsibilities:
  - Numbered scripts (010-999) initialize database, tablespaces, directories
  - Final script (`110_run_initial_load.sh`) applies Liquibase changelog
  - Creates baseline Oracle instance for testing

**Test Execution:**
- Location: `tests/src/test/java/ch/open/osdb/build/changelog/ApplyTest.java`
- Triggers: CI pipeline (`bazel test :tests`)
- Responsibilities:
  - Spins up Oracle XE container via Testcontainers
  - Applies Liquibase changelog to verify validity
  - Generates ORM layer from schema

**PostgreSQL Deployment:**
- Location: `pg_migration/apply/` and `pg_migration/preparation/`
- Triggers: Manual execution or CI pipeline
- Responsibilities:
  - `preparation/100_database.sql` - Create PostgreSQL database
  - `preparation/200_roles.sql` - Create roles
  - `apply/` - Apply schema in dependency order
  - `post_apply/` - Apply fixes

## Architectural Constraints

- **Threading:** Single-threaded sequential execution for Liquibase changelog application (Oracle and PostgreSQL). Parallel data migration via Kubernetes jobs (`pg_migration/k8s/`) for production scenarios.

- **Global state:** Liquibase maintains a `DATABASECHANGELOG` table on each database (Oracle and PostgreSQL) to track applied changesets by ID, author, and MD5 hash. This is the single source of truth for changeset state.

- **Circular imports:** PL/SQL packages may have dependencies encoded in include order in `changes/plsql-changelog.xml`:
  ```xml
  <includeAll path="src/types/" />      <!-- Type definitions first -->
  <includeAll path="src/pkg/" />        <!-- Package specs and bodies -->
  <includeAll path="src/proc" />        <!-- Standalone procedures -->
  <includeAll path="src/pkgb" />        <!-- Additional package bodies -->
  <includeAll path="src/triggers" />    <!-- Triggers last -->
  ```

- **DDL Application Order:** Strict ordering required (types → packages → procedures → triggers) to resolve dependencies. Views applied after tables; constraints applied after all base tables exist.

- **Migration Idempotency:** All Liquibase changesets marked `runOnChange:true` for PL/SQL to support code re-execution without change ID conflicts.

- **Source of Truth:** During migration, Oracle MCDB is source of truth. Changes must be completed in Oracle before PostgreSQL migration begins. Flashback capability required to ensure consistent snapshots.

## Anti-Patterns

### Incomplete Ora2Pg Conversion

**What happens:** Ora2pg batch-converts PL/SQL code but does not translate Oracle-specific procedural logic (exception handling, package-local variables, DBMS_* calls, custom data types) — output in `pg_migration/output/` and `ddl/migrated/` contains syntax errors and missing functionality.

**Why it's wrong:** PostgreSQL lacks Oracle packages, DBMS_* packages, and some PL/SQL constructs. Automated conversion leaves manual fixes for complex logic, creating a fragile migration path.

**Do this instead:** 
- Review `pg_migration/output/` output for errors early
- Create manual fix scripts in `pg_migration/post_apply/` for complex procedures
- Example: `pg_migration/preparation/303_package_procedure_fixes.sh` applies targeted corrections
- Plan 2-3 iteration cycles for PL/SQL translation; expect 20-30% of procedures to require manual rewriting

### Missing Dependency Documentation in Changesets

**What happens:** PL/SQL source files in `ddl/src/` may reference objects from other packages, but dependency order is implicit in the `plsql-changelog.xml` include order. Adding a new package without understanding the order can break existing procedures.

**Why it's wrong:** Implicit ordering makes maintenance brittle. Missing dependencies cause changelog application to fail silently or with circular errors.

**Do this instead:** 
- Document package dependencies as comments in `ddl/src/pkg/` files
- Verify include order in `changes/plsql-changelog.xml` matches dependency tree
- Use Liquibase `<precondition>` tags to verify prerequisite objects exist before applying a changeset
- Example: Add to package specs:
  ```sql
  -- Depends on: OSAG_AUTH_STATE (same package body)
  CREATE OR REPLACE PACKAGE AUTH.OSAG_AUTH IS ...
  ```

### Ignoring Liquibase Changeset Idempotency

**What happens:** Developers manually execute SQL scripts outside Liquibase, bypassing the `DATABASECHANGELOG` table. Later attempts to apply Liquibase changesets fail because Liquibase doesn't recognize the change as already applied.

**Why it's wrong:** Liquibase tracks state via changeset ID + author + MD5 hash. Manual execution breaks this tracking, causing dual applies or failed deployments.

**Do this instead:** 
- Always use Liquibase (`changes/liquibase-*.properties` configurations) to apply changes
- Use `runOnChange:true` for PL/SQL source files (e.g., `ddl/src/pkg/*.sql`) to force re-execution on code changes
- For one-off fixes, add them to `changes/changelog-current.sql` as numbered changesets, not to separate scripts

## Error Handling

**Strategy:** Liquibase fails fast on any changeset error; transaction rollback occurs. Test suite validates all changes before production deployment.

**Patterns:**
- Liquibase changelog application stops at first error; no partial state left
- `\set ON_ERROR_STOP OFF` in PostgreSQL migration scripts allows batch execution to continue (use cautiously)
- Oracle triggers with error logging (e.g., exception handlers in package bodies) log to `DBMS_OUTPUT` or custom tables
- Java test suite catches deployment errors via Testcontainers; reports via JUnit

## Cross-Cutting Concerns

**Logging:** 
- Oracle: `DBMS_OUTPUT` for PL/SQL runtime logging; SQL*Plus logs to stdout
- PostgreSQL: PostgreSQL logs via `pg_log`; migration scripts log via `set -x` in bash
- Java tests: SLF4J configured in `tests/src/test/resources/testcontainers.properties`

**Validation:** 
- Liquibase validates changeset syntax before application
- Java test suite verifies schema consistency via JUnit assertions
- ORM codegen regeneration via `tests/update_dx_orm.sh` ensures application layer matches database schema

**Authentication:** 
- Oracle: Username/password in Liquibase properties files (`changes/liquibase-*.properties`)
- PostgreSQL: Same approach; also supports `.pgpass` for password-less login
- Kubernetes data transfer jobs: Service account authentication with RBAC

---

*Architecture analysis: 2026-07-10*
