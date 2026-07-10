# External Integrations

**Analysis Date:** 2026-07-10

## APIs & External Services

**Ticketing System:**
- Atlassian Jira (referenced in documentation)
  - Integration point: Issue tracking and documentation links in README
  - Docs: https://open-systems.atlassian.net/wiki/spaces/DOC

**Artifact Repository:**
- Artifactory (artifacts.open.ch)
  - Container images: `artifacts.open.ch/central-docker-prod-local/osdb/local_ora_mcdb`
  - Docker hub mirror: `artifacts.open.ch/public-docker-virtual/`
  - Base image source: `gvenzl/oracle-free:23.7` (mirrored through Artifactory)

## Data Storage

**Databases:**

| Database | Type | Purpose | Connection |
|----------|------|---------|-----------|
| Oracle 19c | Primary (Source) | Mission Control production database | JDBC via `jdbc:oracle:thin:@ORAPROD?TNS_ADMIN=/path/to/tnsnames` |
| Oracle XE/Free 23.7 | Test/Development | Ephemeral test database in containers | Docker container, exposed on port 1521 |
| PostgreSQL 17+ | Target (Migration) | PostgreSQL migration target database | Standard libpq connection |

**Configuration Files:**
- `config/mc/dev/tnsnames.ora` - TNS (Transparent Network Substrate) configuration for development
- `config/mc/prod/tnsnames.ora` - TNS configuration for production Oracle connectivity

**File Storage:**
- Local filesystem only - No cloud storage integration detected
- CSV exports: `masterdata/` directory contains master data snapshots as CSV files
- Script outputs: `pg_migration/output/` directories for migration artifacts

**Caching:**
- None detected - Schema is immutable via Liquibase versioning

## Authentication & Identity

**Oracle Database Authentication:**
- Method: Traditional Oracle username/password
- SYS account with SYSDBA privilege - Used for DDL export and administration
- Application schemas: Multiple schema accounts (APPID, AUTH, BIREADER, etc.) with schema-specific privileges
- Password management: Environment variables (`ORACLE_PASSWORD`, `SYSDBA_PASSWORD`, `ORA_PWD`)

**Kubernetes Access:**
- kubectl configuration - Cluster access for deployment jobs (`pg_migration/apply/400_deploy_k8s_dev_datatransfer.sh`)
- Current context detection at runtime

**API Keys/Credentials:**
- Stored in environment variables only (no files committed to repository)
- Testcontainers image pull policy: Uses repository mirror configuration in `testcontainers.properties`

## Monitoring & Observability

**Error Tracking:**
- Not detected - Schema validation errors handled via test assertions and Liquibase rollback

**Logs:**
- Log4j 2 with SLF4J bridge - Standard logging infrastructure
- SLF4J API - Abstraction layer for logging
- Liquibase changelog execution logs
- Docker container logs for Oracle and ora2pg

**Database Audit Trail:**
- Liquibase DATABASECHANGELOG table - Tracks all applied changesets
- Schema: `lqb` (Liquibase schema)
- Audit data export: `changes/audit-trail-mapping.xml` links database audit fields to application fields

## CI/CD & Deployment

**Build Orchestration:**
- Bazel - Local and CI build system
- Docker - Containerized dependency isolation

**CI Pipeline:**
- BuildKite - CI service (referenced in README for automated ORM rebuild checks)
- CI script: `tests/ci-verify-orm.sh` - Regenerates ORM layer for validation
- CI script: `tests/update_dx_orm.sh` - Updates generated ORM classes

**Deployment Platform:**
- Kubernetes - Orchestration platform for data transfer workloads
- Docker containers - Application delivery (Oracle, ora2pg, data transfer jobs)
- Container Registry: artifacts.open.ch (internal Docker repository)

**Deployment Targets:**

| Environment | Container | Registry |
|-------------|-----------|----------|
| Production | osdb/local_ora_mcdb:X.Y.Z | central-docker-prod-local |
| Development | osdb/local_ora_mcdb:snapshot | central-docker-dev-local |
| Testing | osdb/local_ora_mcdb_flashback | central-docker-prod-local (with ARCHIVELOG) |

**Release Management:**
- Kaeter - Automated release system
- Version strategy: SemVer (X.Y.Z) with major.minor tracking (e.g., `:2` tag for X.Y.* versions)
- ARM64 variant: Separate releases for Apple Silicon Macs via `container/docker_orafree_based/arm64/`

## Database Migration Tools

**Ora2pg:**
- Docker container: `ora2pg` - Oracle-to-PostgreSQL conversion tool
- Invocation: `pg_migration/run_oradata2pg.sh`
- Configuration: `pg_migration/config/data_export.conf` (TNS admin files required)
- Output: SQL migration scripts in `pg_migration/output/`
- Scope: Schema DDL, code objects, and data extraction

**Migration Workflow:**
```
Oracle 19c (Source)
    ↓
ora2pg (Docker container)
    ↓
PostgreSQL migration scripts (ddl/migrated/)
    ↓
PostgreSQL 17+ (Target)
```

## Webhooks & Callbacks

**Incoming:**
- Not detected - No webhook endpoints configured

**Outgoing:**
- Liquibase Hub integration: Disabled (`liquibase.hub.mode=off` in properties)
- Kaeter hooks: Autorelease triggers on version file changes (`open.ch/kaeter-hook/autorelease-version` in versions.yaml)

## Environment Configuration

**Required for Development:**
- `ORACLE_PASSWORD` - Oracle database password
- `ORACLE_DATABASE` - Target PDB name (e.g., XEPDB1)
- `ORA_PWD` - Oracle user password for data export
- `SYSDBA_PASSWORD` - SYS account password
- `PANTA_HOME` - Workspace root path
- `TNS_ADMIN` - Path to tnsnames.ora for Oracle client

**Required for Kubernetes Deployment:**
- kubectl configured and connected to cluster
- Current namespace and context properly set
- RBAC permissions for deployment operations

**Secrets Location:**
- Environment variables only (NEVER committed to git)
- `.gitignore` entries prevent accidental secret commits
- testcontainers.properties references artifact repository mirror (no secrets)

## Docker Integration

**Base Images:**

| Image | Version | Arch | Purpose | SHA256 |
|-------|---------|------|---------|--------|
| gvenzl/oracle-free | 23.7 | AMD64 | Oracle 19c-like test/runtime environment | 091eb0... (SHA prefix) |
| gvenzl/oracle-free | 23.7 | ARM64 | Oracle for Apple Silicon | 90fda7... (SHA prefix) |

**Custom Images:**
- `osdb/local_ora_mcdb` - Mission Control database with DDL and masterdata preloaded
- Built with multi-stage Dockerfile: base → test → final

**Initialization Scripts:**
- `container/container-entrypoint-initdb.d/` - Executed on first startup
  - Schema user setup and permissions
  - Flashback archive configuration
  - FRA (Fast Recovery Area) setup
  - Remote SYSDBA password configuration
  - Initial load execution
  - ARCHIVELOG and Flashback enablement
- `container/container-entrypoint-startdb.d/` - Executed on container restart
  - Archive log cleanup

**Container Exposure:**
- Port 1521 - Oracle JDBC listener
- Port 2484 - TCPS (Secure Oracle Protocol) with Oracle Wallet
- Port 5500 - Oracle EM Express GUI (optional)

## Data Transfer & Migration

**Orchestration:**
- Kubernetes Job manifests: `pg_migration/k8s/dev/` - Parallelized data transfer workloads
- Data transfer phases:
  1. Master data transfer (parallelized)
  2. Normal table data (parallelized)
  3. Large CLOB tables (initial recent entries)
  4. Bulk transfer of older CLOB entries

**Data Consistency:**
- Oracle SCN (System Change Number) - Baseline snapshot point for consistent transfer
- Flashback Database - Enables consistent read-only snapshots
- No CDC (Change Data Capture) - Single-pass migration approach

**CSV Export:**
- `changes/scripts/regenerate-csv.sh` - Exports master data from Oracle to CSV
- Master data files: `masterdata/` with naming pattern `*.jdo_properties.csv`
- Used to pre-populate PostgreSQL test instances

## Supporting Tools & Frameworks

**ORM Generation:**
- DataNucleus ORM - Java ORM framework
- ch.open.mss.orm.codegen - Custom code generator
- Targets: `applications/customer-portal/libs/java/core/`

**Configuration Management:**
- Kaeter module: `config/mc/mc-files-module.yaml` - Versioned configuration artifact
- CHANGELOG.md - Configuration release notes
- Semantic versioning: `versions.yaml` tracks all releases with timestamps

---

*Integration audit: 2026-07-10*
