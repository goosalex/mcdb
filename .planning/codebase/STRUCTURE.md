# Codebase Structure

**Analysis Date:** 2026-07-10

## Directory Layout

```
mcdb/
├── .git/                          # Git repository metadata
├── .planning/                     # GSD planning and analysis docs
│   └── codebase/                  # Architecture and structure documents
├── BUILD                          # Bazel build configuration
├── README.md                      # Project overview
├── CLAUDE.md                      # Project-specific instructions
│
├── changes/                       # Liquibase change tracking (version control for schema)
│   ├── root-changelog.xml         # Master changelog orchestrator
│   ├── changelog-current.sql      # Current incremental DDL changes
│   ├── changelog-1.archive.sql    # Historical archived changes
│   ├── plsql-changelog.xml        # PL/SQL source code changelog
│   ├── audit-trail-mapping.xml    # Audit trail configuration
│   ├── tests-changelog.xml        # Test-specific changelog
│   ├── liquibase-*.properties     # Liquibase configuration (dev, prod, orm, container, sync)
│   └── scripts/                   # Utility scripts for export and migration
│       ├── export_prod_schema.sh  # Export Oracle schema via expdp
│       ├── exportddl.sh           # Export raw DDL
│       ├── regenerate-ddl.sh      # Split and organize DDL into ddl/generated/
│       ├── regenerate-csv.sh      # Regenerate masterdata CSV files
│       ├── migrate-ddl.sh         # Convert Oracle DDL to PostgreSQL via ora2pg
│       ├── ExportDDL.java         # Java utility to parse and organize Oracle DDL
│       └── ExportCsvMeta.java     # Java utility to export metadata as CSV+XML
│
├── ddl/                           # Database Definition Language (Schema)
│   ├── export/                    # Raw Oracle DDL dump (output of expdp)
│   ├── generated/                 # Snapshot of Oracle schema at baseline (organized)
│   │   ├── grants/                # Role and object grants
│   │   ├── sequences/             # Sequence definitions
│   │   └── users/                 # User/schema definitions
│   ├── migrated/                  # Batch-migrated Oracle DDL to PostgreSQL (via ora2pg)
│   │   ├── tables/                # Table definitions (tables.pg.sql, views.pg.sql, constraints.pg.sql)
│   │   ├── constraints/           # Constraint definitions
│   │   ├── mviews/                # Materialized view definitions
│   │   ├── grants/                # PostgreSQL grants
│   │   ├── users/                 # PostgreSQL user definitions
│   │   └── helpers/               # Helper procedures and functions
│   └── src/                       # Oracle PL/SQL source code (tracked in Liquibase)
│       ├── pkg/                   # Oracle packages (spec and body, e.g., AUTH.OSAG_AUTH)
│       ├── pkgb/                  # Package bodies (additional)
│       ├── proc/                  # Standalone procedures
│       ├── functions/             # Standalone functions (if organized separately)
│       ├── triggers/              # Database triggers
│       ├── types/                 # User-defined types (records, object types)
│       ├── jobs/                  # Oracle DBMS_SCHEDULER jobs
│       ├── queues/                # Advanced Queuing structures
│       ├── roles/                 # Role and privilege definitions
│       ├── users/                 # User/schema creation DDL
│       ├── global/                # Global DDL (tablespaces, directories, etc.)
│       ├── mlog/                  # Materialized view logs
│       ├── mviews/                # Materialized view definitions
│       └── tests/                 # Test procedures (PL/SQL unit tests)
│
├── masterdata/                    # Reference data snapshots (organized by module)
│   ├── APPID/                     # Application ID module
│   ├── AUTH/                      # Authentication & authorization
│   ├── CERTS/                     # Certificate management
│   ├── ESP/                       # Extended Services Platform
│   ├── FW/                        # Firewall module
│   ├── FYI/                       # FYI module
│   ├── GETNODES/                  # Node retrieval
│   ├── GUMA2/                     # GUMA module (v2)
│   ├── MAIL/                      # Mail service
│   ├── MC/                        # Mission Control (core)
│   ├── MCAUDIT/                   # Audit logging
│   ├── MCDB_CHECKS/               # Database consistency checks
│   ├── MCDB_MONITOR/              # Database monitoring
│   ├── MSS/                       # Managed Service Subscriptions
│   ├── NIDS/                      # Network IDS
│   ├── OSAG/                      # Open Systems AG domain
│   ├── OSIXINFO/                  # OS Information
│   ├── PRX/                       # Proxy services
│   ├── REPORT/                    # Reporting
│   ├── STOP/                      # Service management
│   ├── SVC_ZEROTRUST/             # Zero Trust services
│   ├── TIM/                       # Timezone/timing
│   ├── TT/                        # Ticketing
│   ├── UAI/                       # User API Interface
│   ├── UPOL/                      # User Policies
│   └── VPN/                       # VPN services
│       └── [table-name].csv       # CSV export of reference data (e.g., mc_file_type.csv)
│       └── [table-name].xml       # XML metadata for CSV (JDO properties, column types)
│
├── pg_migration/                  # PostgreSQL migration tooling and deployment
│   ├── README.md                  # Migration procedure and assumptions
│   ├── preparation/               # Pre-deployment schema and environment setup
│   │   ├── 100_database.sql       # Create PostgreSQL database
│   │   ├── 200_roles.sql          # Create roles/users
│   │   ├── 300_run_ora2pg.sh      # Execute ora2pg conversion tool
│   │   ├── 301_clean_tables.sh    # Clean/reset tables if needed
│   │   ├── 302_helper_procedures.sql  # Utility functions for migration
│   │   └── 303_package_procedure_fixes.sh # Apply manual fixes to PL/SQL
│   ├── apply/                     # Deploy schema to PostgreSQL (execute in order)
│   │   ├── 100_apply_users.sh     # Apply user/schema definitions
│   │   ├── 110_schema_users.sql   # Create PostgreSQL users
│   │   ├── 200_apply_tables.sh    # Apply table definitions
│   │   ├── 301_fixes.views.sql    # Fix view definitions
│   │   ├── 302_fix_constraint_syntax.sh # Fix constraint syntax
│   │   └── 400_deploy_k8s_dev_datatransfer.sh # Deploy data transfer to Kubernetes
│   ├── post_apply/                # Post-deployment validation and fixes
│   ├── output/                    # Ora2pg generated PostgreSQL code (three strategies)
│   │   ├── package_as_schema/     # Each package → PostgreSQL schema
│   │   │   ├── PACKAGE.pg.sql
│   │   │   ├── PROCEDURE.pg.sql
│   │   │   ├── FUNCTION.pg.sql
│   │   │   ├── TYPE.pg.sql
│   │   │   ├── TRIGGER.pg.sql
│   │   │   └── VIEW.pg.sql
│   │   ├── package_in_name/       # Package name as prefix to objects
│   │   │   └── [same file structure as above]
│   │   └── schema/                # Flat schema structure
│   │       └── [same file structure as above]
│   ├── config/                    # Ora2pg configuration files
│   ├── k8s/                       # Kubernetes manifests for data transfer
│   ├── load_sim/                  # Load simulation / stress test scripts post-migration
│   ├── manual_export/             # Manual export utilities
│   ├── run_local_example.sh       # Example migration run (local testing)
│   ├── run_local_pgsql.sh         # Run migration against local PostgreSQL
│   ├── run_oradata2pg.sh          # Execute ora2pg conversion
│   └── deploy.sh                  # Main deployment orchestration script
│
├── container/                     # Oracle XE container for testing
│   ├── container-entrypoint-initdb.d/  # Initialization scripts (numbered 010-999)
│   │   ├── 010_ora_directories.sql     # Create Oracle directories
│   │   ├── 011_tablespaces.sql         # Create tablespaces
│   │   ├── 021_flashback_setup.sh      # Enable Flashback Database
│   │   ├── 030_remote_sysdba_pw.sh     # Set SYSDBA password
│   │   ├── 040_extend-string-size.sh   # Extend string size limits
│   │   ├── 100_generate_initial_load.sh  # Generate baseline schema load
│   │   ├── 110_run_initial_load.sh     # Apply Liquibase changelog
│   │   └── 995_shutdown.sql            # Shutdown database
│   ├── container-entrypoint-startdb.d/ # Startup scripts
│   ├── docker_orafree_based/       # Dockerfile and container config
│   ├── osdp/                       # OSDP-specific container settings
│   └── README.md                   # Container setup instructions
│
├── config/                        # Application configuration
│   └── mc/                        # Mission Control configuration
│
├── mappingdata/                   # Auto-generated audit trail mapping (symlink)
│
├── tests/                         # Test suite (Java with Testcontainers)
│   ├── BUILD                      # Bazel build configuration for tests
│   ├── src/
│   │   ├── test/java/ch/open/osdb/build/changelog/
│   │   │   └── ApplyTest.java     # Main test: verifies Liquibase changelog applies cleanly
│   │   └── main/java/ch/open/osdb/build/changelog/
│   │       ├── WriteORM.java      # Generates ORM layer from database schema
│   │       └── ZipDirectory.java  # Utility to zip ORM output
│   ├── src/test/resources/
│   │   └── testcontainers.properties  # Testcontainers configuration
│   ├── ci-verify-orm.sh           # CI step to verify ORM layer consistency
│   └── update_dx_orm.sh           # Regenerate ORM layer after schema changes
```

## Directory Purposes

**`changes/`:**
- Purpose: Liquibase version control for the database schema
- Contains: XML and SQL changelogs that track schema evolution from baseline (`ddl/generated/`) to current state
- Key files: 
  - `root-changelog.xml` - Orchestrator that includes other changesets in order
  - `changelog-current.sql` - DDL changes (tables, views, etc.)
  - `plsql-changelog.xml` - PL/SQL objects (packages, procedures, triggers, types)
- Usage: Applied to both Oracle (for validation/testing) and PostgreSQL (during migration)

**`ddl/`:**
- Purpose: Database Definition Language storage (schemas, objects, source code)
- Subdivisions:
  - `generated/` - Snapshot of Oracle baseline (reference point)
  - `migrated/` - Batch-converted PostgreSQL DDL (ora2pg output)
  - `src/` - Current PL/SQL source (tracked in Liquibase)

**`masterdata/`:**
- Purpose: Store reference data snapshots organized by business module
- Contains: CSV files (data) + XML metadata (column types, JDO properties) for each reference table
- Modules: 25+ functional domains (AUTH, FW, MC, MSS, etc.)
- Usage: Loaded into new database instances during initialization

**`pg_migration/`:**
- Purpose: Complete tooling and orchestration for migrating schema and data to PostgreSQL
- Subdivisions:
  - `preparation/` - Database initialization and ora2pg conversion
  - `apply/` - Sequential schema application to PostgreSQL
  - `post_apply/` - Fixes and post-deployment validation
  - `output/` - Ora2pg-generated PostgreSQL code (three naming strategies)
  - `k8s/` - Kubernetes manifests for production data transfer

**`container/`:**
- Purpose: Docker container for Oracle XE used in testing and CI
- Contains: Initialization scripts (numbered 010-999) that set up database, enable Flashback, apply Liquibase changelog
- Usage: Testcontainers spins up for `bazel test :tests`

**`tests/`:**
- Purpose: Test suite that validates schema consistency
- Contains: Java JUnit5 tests using Testcontainers
- Key test: `ApplyTest.java` - spins up Oracle container, applies Liquibase changelog, verifies success
- Usage: CI pipeline validation; ORM layer regeneration

## Key File Locations

**Entry Points:**

- **Oracle Export:** `changes/scripts/export_prod_schema.sh` - Exports Oracle MCDB baseline via Oracle Data Pump (expdp)
- **DDL Reorganization:** `changes/scripts/regenerate-ddl.sh` - Splits raw DDL into `ddl/generated/`
- **DDL Migration:** `changes/scripts/migrate-ddl.sh` - Converts DDL to PostgreSQL via ora2pg
- **Container Initialization:** `container/container-entrypoint-initdb.d/110_run_initial_load.sh` - Applies Liquibase to Oracle container
- **Test Execution:** `tests/src/test/java/ch/open/osdb/build/changelog/ApplyTest.java` - Main test entry point
- **PostgreSQL Migration:** `pg_migration/preparation/300_run_ora2pg.sh` - Converts PL/SQL code to PostgreSQL

**Configuration:**

- **Liquibase Properties:** 
  - `changes/liquibase-dev.properties` - Development environment
  - `changes/liquibase-prod.properties` - Production environment
  - `changes/liquibase-orm.properties` - ORM layer generation
  - `changes/liquibase-container.properties` - Container testing

- **Build Configuration:**
  - `BUILD` - Bazel build for tests and ORM generation
  - `tests/BUILD` - Test-specific build rules

**Core Logic:**

- **Schema Changelog:** `changes/root-changelog.xml` - Master orchestrator
- **DDL Changes:** `changes/changelog-current.sql` - Incremental DDL from baseline
- **PL/SQL Source:** `ddl/src/` - 147 SQL files organized by object type
- **PL/SQL Changelog:** `changes/plsql-changelog.xml` - Includes source files in dependency order

**Testing:**

- **Main Test:** `tests/src/test/java/ch/open/osdb/build/changelog/ApplyTest.java` - Validates changelog applies cleanly to Oracle container
- **ORM Codegen:** `tests/src/main/java/ch/open/osdb/build/changelog/WriteORM.java` - Generates Java ORM layer from database schema
- **ORM Update Script:** `tests/update_dx_orm.sh` - Regenerates ORM after schema changes

## Naming Conventions

**Files:**

- **Liquibase XML:** `root-changelog.xml`, `*-changelog.xml` (e.g., `plsql-changelog.xml`, `tests-changelog.xml`)
- **Liquibase SQL:** `changelog-*.sql` (e.g., `changelog-current.sql`, `changelog-1.archive.sql`)
- **Oracle PL/SQL source:** `[prefix]_[object_name].sql` (e.g., `auth_osag_auth.sql` for package `AUTH.OSAG_AUTH`)
- **Migration scripts:** Numbered `[100-900]_[description].{sh,sql}` for execution order (e.g., `100_apply_users.sh`, `200_apply_tables.sh`)
- **PostgreSQL generated:** `*.pg.sql` (e.g., `tables.pg.sql`, `functions.pg.sql`) from ora2pg
- **Master data:** `[table_name].csv` + `[table_name].xml` (e.g., `mc_file_type.csv`, `mc_file_type.xml`)
- **Liquibase properties:** `liquibase-[environment].properties` (e.g., `liquibase-dev.properties`, `liquibase-prod.properties`)

**Directories:**

- **Module (functional domain):** UPPERCASE (e.g., `AUTH`, `FW`, `MC`, `MSS`)
- **Object type in `ddl/src/`:** lowercase plural or descriptive (e.g., `pkg`, `proc`, `triggers`, `types`)
- **Migration stage:** descriptive name (e.g., `preparation`, `apply`, `post_apply`, `output`)
- **Ora2pg strategy:** `package_as_schema`, `package_in_name`, `schema`

## Where to Add New Code

**New Table or View:**
- DDL: Add `CREATE TABLE/VIEW` to `changes/changelog-current.sql` as a numbered changeset
- Master data: If reference data, add CSV + XML files to `masterdata/[MODULE]/`
- PostgreSQL migration: Oracle DDL auto-converts via ora2pg; output appears in `ddl/migrated/tables/tables.pg.sql`

**New Package or Procedure:**
- Source: Create new `.sql` file in `ddl/src/pkg/` or `ddl/src/proc/` with Liquibase-formatted header:
  ```sql
  --liquibase formatted sql logicalFilePath:pkg/[schema]_[package_name].sql
  --changeset sys:1 runOnChange:true endDelimiter:/
  CREATE OR REPLACE PACKAGE [SCHEMA].[PACKAGE_NAME] IS
  ...
  END [PACKAGE_NAME];
  /
  ```
- Changelog: Automatically included by `changes/plsql-changelog.xml` via `<includeAll path="src/pkg/" />`
- PostgreSQL migration: Code converts via ora2pg; output appears in `pg_migration/output/[strategy]/PACKAGE.pg.sql`

**New PL/SQL Fix After Ora2pg Conversion:**
- Add fix script to `pg_migration/post_apply/` with numbering `[100-999]_[description].sh` or `.sql`
- Wrap manual fixes with comments explaining the ora2pg limitation:
  ```sql
  -- FIX: Ora2pg did not translate Oracle DBMS_ALERT.SIGNAL() 
  -- Manual replacement with PostgreSQL NOTIFY/LISTEN pattern
  CREATE OR REPLACE FUNCTION...
  ```

**New Container Initialization Step:**
- Add script to `container/container-entrypoint-initdb.d/` with numbering `[010-999]_[description].{sh,sql}`
- Scripts execute in alphanumeric order; use lower numbers for prerequisites (e.g., directories before tablespaces)

**New Integration Test:**
- Add Java test class to `tests/src/test/java/ch/open/osdb/build/changelog/`
- Inherit from test base that provisions Testcontainers and Liquibase
- Test should verify schema consistency, data integrity, or ORM layer

**New Master Data Module:**
- Create directory in `masterdata/[NEW_MODULE]/`
- Export CSV + XML metadata for all reference tables in the module
- Use `changes/scripts/regenerate-csv.sh` to standardize export format

**New Database Configuration:**
- Add `.properties` file to `changes/` with pattern `liquibase-[environment].properties`
- Include: database URL, username (password from env var or secure store), schema name

## Special Directories

**`ddl/generated/`:**
- Purpose: Snapshot of Oracle baseline schema (reference point for Liquibase changes)
- Generated: Yes (by `changes/scripts/regenerate-ddl.sh`)
- Committed: Yes (snapshot is checked in to track baseline)
- Content: Split and organized Oracle DDL (tables, sequences, users, grants)
- Modification: Read-only; update only via regenerate-ddl.sh when Oracle baseline changes

**`ddl/migrated/`:**
- Purpose: Batch-migrated Oracle DDL to PostgreSQL (ora2pg output)
- Generated: Yes (by `changes/scripts/migrate-ddl.sh` or `pg_migration/preparation/300_run_ora2pg.sh`)
- Committed: Yes (batch-migrated DDL checked in for review and further fixes)
- Content: PostgreSQL-compatible table/view/constraint definitions
- Modification: Can be manually edited to fix ora2pg issues (e.g., correct syntax errors, adjust data types)

**`pg_migration/output/`:**
- Purpose: Ora2pg-generated PL/SQL code in PostgreSQL dialect (three naming strategies)
- Generated: Yes (by `pg_migration/preparation/300_run_ora2pg.sh`)
- Committed: Optional (output is intermediate; manual fixes take precedence)
- Content: Three subdirectories representing different package-to-PostgreSQL translation approaches
- Modification: Review for errors; copy corrected versions to `pg_migration/post_apply/`

**`masterdata/`:**
- Purpose: Snapshots of reference data (seed data for new instances)
- Generated: Yes (by `changes/scripts/regenerate-csv.sh`)
- Committed: Yes (reference data snapshots checked in)
- Content: CSV files (data) + XML metadata (column types) organized by functional module
- Modification: Can be manually edited to update reference values; regenerate from Oracle to sync

**`container/container-entrypoint-initdb.d/`:**
- Purpose: Initialization scripts for Oracle XE container
- Generated: No (hand-written; may be updated for new setup requirements)
- Committed: Yes
- Content: Shell scripts and SQL files that execute in order (010-999)
- Modification: Add new scripts for additional setup steps; maintain alphanumeric ordering

**`.planning/codebase/`:**
- Purpose: GSD codebase analysis and architecture documentation
- Generated: Yes (by GSD mapper agents)
- Committed: Yes (documentation checked in)
- Content: ARCHITECTURE.md, STRUCTURE.md, CONVENTIONS.md, TESTING.md, CONCERNS.md, STACK.md, INTEGRATIONS.md
- Modification: Read-only; regenerate via `/gsd-map-codebase` when architecture changes

---

*Structure analysis: 2026-07-10*
