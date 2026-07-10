# Technology Stack

**Analysis Date:** 2026-07-10

## Languages

**Primary:**
- SQL (Oracle PL/SQL) - Database DDL and procedural objects in Oracle 19c
- SQL (PostgreSQL) - Database DDL and procedural objects for PostgreSQL 17+ migration target
- Java - Build automation, test infrastructure, and ORM code generation
- Bash - Migration and deployment scripts

**Secondary:**
- Perl - Data loading and simulation scripts (`pg_migration/load_sim/*.pl`)

## Runtime

**Environment:**
- Java Runtime Environment (JVM) - For build automation and testing
- Docker - Container-based execution for Oracle XE and ora2pg migration tool
- Kubernetes - Deployment platform for data transfer jobs

**Package Manager:**
- Bazel - Build system and dependency management
- Maven/Gradle dependencies managed through Bazel (transitive)

## Frameworks

**Build/Test:**
- Bazel - Build automation and test orchestration (`BUILD` file at repository root)
- JUnit5 (Jupiter) - Test framework for Java-based schema validation tests
- Testcontainers - Docker-based test infrastructure for ephemeral database testing

**Database Management:**
- Liquibase 4.21.1 - Schema version control and change management (`changes/root-changelog.xml`, liquibase-*.properties)
- Oracle Database 19c Enterprise Edition - Primary database (production source)
- PostgreSQL 17+ - Migration target database

**ORM:**
- DataNucleus ORM - Object-relational mapping for Java (`orm-codegen` tool referenced in BUILD)

**Migration:**
- ora2pg - Oracle-to-PostgreSQL schema and data migration tool (Docker-based container)

## Key Dependencies

**Critical:**

| Package | Version | Purpose |
|---------|---------|---------|
| Oracle JDBC Driver | ojdbc10 | Database connectivity to Oracle 19c |
| Liquibase Core | Latest (v4.21.1 required) | Schema changelog execution and tracking |
| JUnit Jupiter API | Latest | Test framework and annotations |
| JUnit Jupiter Params | Latest | Parameterized testing support |

**Testing Infrastructure:**

| Package | Version | Purpose |
|---------|---------|---------|
| Testcontainers | Latest | Containerized database test fixtures |
| Testcontainers Oracle XE | Latest | Oracle XE test container image management |
| Testcontainers JUnit Jupiter | Latest | Integration between Testcontainers and JUnit5 |
| Apache Commons Collections | 4.x | Collection utilities for test data handling |
| Apache Log4j SLF4J Bridge | Latest | Logging infrastructure via SLF4J |

**ORM & Code Generation:**

| Package | Version | Purpose |
|---------|---------|---------|
| ORM Codegen (ch.open.mss) | Internal | Generates Java ORM classes from database schema |

## Configuration

**Environment Variables:**
- `ORACLE_PASSWORD` - Oracle instance admin password
- `ORACLE_DATABASE` - Target Oracle database/PDB name (e.g., XEPDB1)
- `ORA_PWD` - Oracle user password for ora2pg connectivity
- `SYSDBA_PASSWORD` - SYS account password for DDL export
- `PANTA_HOME` - Base path for project workspace
- `TESTCONTAINERS_RYUK_DISABLED` - Disable container cleanup (used in build automation)

**Configuration Files:**

| File | Purpose |
|------|---------|
| `changes/liquibase-prod.properties` | Production Oracle instance connection (`jdbc:oracle:thin:@ORAPROD`) |
| `changes/liquibase-dev.properties` | Development instance configuration |
| `changes/liquibase-container.properties` | Container-based instance configuration |
| `changes/liquibase-orm.properties` | ORM layer generation configuration |
| `tests/src/test/resources/testcontainers.properties` | Docker Hub image prefix override for artifact repository |
| `config/mc/versions.yaml` | Version tracking for configuration releases |
| `container/docker_orafree_based/Dockerfile` | Container image build specification |

**Properties Configuration:**

| Property | Example Value | Purpose |
|----------|---------------|---------|
| driver | oracle.jdbc.OracleDriver | Oracle JDBC driver class |
| url | jdbc:oracle:thin:@ORAPROD?TNS_ADMIN=... | Oracle connection URL with TNS admin path |
| liquibase.searchPath | ../ddl,.,../mappingdata | Paths for changelog file lookup |
| changelogFile | root-changelog.xml | Root changelog entry point |
| schemas | APPID,AUTH,BIREADER,...,VPN | List of database schemas to manage (24 schemas) |
| liquibase.ddlLockTimeout | 60 | Lock acquisition timeout in seconds |

## Build System

**Bazel Configuration:**

| Target | Location | Purpose |
|--------|----------|---------|
| `:testlib` | `BUILD` | Java library containing test classes and data |
| `:tests_dependencies` | `BUILD` | Test framework dependency aggregation |
| `:current_ddl` | `BUILD` | Filegroup of DDL and configuration sources |
| `:changelog2java` | `BUILD` | Binary for generating ORM layer from schema |
| `:gen_sql2orm` | `BUILD` | Genrule that generates orm_layer.zip artifact |
| `:tests` | `BUILD` | JUnit5 test runner for schema validation |

**Test Execution:**
```bash
bazel test :tests
```
This runs:
1. Testcontainers to spin up ephemeral Oracle XE container
2. Liquibase changelog execution against test instance
3. Schema validation assertions
4. ORM layer regeneration checks

## Platform Requirements

**Development:**
- Java Development Kit (JDK 11+)
- Docker Engine (for Testcontainers)
- Bazel build tool
- GNU sed (or gsed on macOS)
- Liquibase CLI v4.21.1
- Bash shell

**Production/Deployment:**
- Docker-compatible container runtime (Docker, Podman, etc.)
- Kubernetes cluster (for data transfer workloads)
- Oracle 19c database (source/primary)
- PostgreSQL 17+ database (migration target)
- kubectl CLI for Kubernetes deployments
- Oracle Wallet for TLS/SSL connections (optional, for TCPS port 2484)

## Database Configuration

**Oracle 19c (Source):**
- Edition: Enterprise Edition
- Container: Oracle XE or Oracle Free 23.7 (for testing)
- PDB: XEPDB1 (Pluggable Database)
- Flashback enabled: Required for consistent data transfer
- ARCHIVELOG mode: Optional, enabled in flashback variant
- TCPS port: 2484 with self-signed Oracle Wallet at `/opt/oracle/oradata/dbconfig/EE/.tls-wallet`
- EM Express GUI: port 5500 (https://localhost:5500/em/)

**PostgreSQL 17+ (Migration Target):**
- Version: 17 or higher
- Connection method: Standard libpq connection
- Schema structure: Derived from Oracle schema via ora2pg conversion

---

*Stack analysis: 2026-07-10*
