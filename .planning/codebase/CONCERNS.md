<!-- refreshed: 2026-07-10 -->
# Codebase Concerns

**Analysis Date:** 2026-07-10

## Tech Debt

### Oracle-Specific PL/SQL Functions in PostgreSQL Migration

**Issue:** The ora2pg-converted PL/SQL contains multiple Oracle database package calls that do not exist in PostgreSQL.

**Files:**
- `pg_migration/output/package_as_schema/PACKAGE.pg.sql` (16,140 lines)
- `pg_migration/output/package_in_name/PACKAGE.pg.sql` (15,639 lines)

**Critical Oracle packages not available:**
- `DBMS_UTILITY.format_error_backtrace()` - Lines 1950, 9043, 9044, 9082, 9083 (5 uses). PostgreSQL has no direct equivalent; needs custom error tracking.
- `DBMS_UTILITY.GET_TIME()` - Lines 9560, 9766, 9778, 9817, 9829, 9881, 9893, 9953 (8+ uses). PostgreSQL equivalent: `EXTRACT(EPOCH FROM clock_timestamp())`.
- `DBMS_RANDOM.varchar()` - Line 3440. Appears malformed: `DBMS_RANDOM.varchar(TEXTVALUE260?)`. PostgreSQL: use `random()` or UUID.
- `DBMS_CRYPTO` - Cryptographic hash functions. PostgreSQL: use `pgcrypto` extension (md5, sha1, sha256).
- `UTL_SMTP` package - Lines 8994-9046. Complete email sending framework. PostgreSQL has no built-in equivalent; needs external solution or `plpython3u` function.
- `UTL_I18N.STRING_TO_RAW()` - Line 6897 (at least 2 uses). PostgreSQL: use `encode()` and `decode()`.

**Impact:** Procedures using these functions will fail at runtime or during schema creation.

**Fix approach:** 
1. For `DBMS_UTILITY` functions, rewrite using PostgreSQL equivalents
2. For `UTL_SMTP`, migrate email logic to application layer or use `plpython3u`
3. For cryptographic functions, enable `pgcrypto` extension and rewrite calls
4. Test each converted function individually in PostgreSQL

---

### Incomplete Masterdata Transfer Process

**Issue:** The migration README documents masterdata transfer but the process is incomplete.

**Files:**
- `pg_migration/README.md` (lines 32-35)

**Problem:** Step 5 in migration process is marked incomplete with `[TODO: specify the scripts here]`. No documented process for:
- Regenerating masterdata CSV from Oracle in migration context
- Loading masterdata CSV into PostgreSQL
- Validating masterdata consistency post-migration

**Impact:** Critical reference data may not be properly transferred, causing data integrity issues in PostgreSQL.

**Fix approach:** Complete and test masterdata transfer scripts with validation checks.

---

### Malformed SQL Syntax in GET DIAGNOSTICS

**Issue:** Incorrect PostgreSQL syntax in converted procedures.

**Files:**
- `pg_migration/output/package_as_schema/PACKAGE.pg.sql` line 11117
- `pg_migration/output/package_in_name/PACKAGE.pg.sql` line 15017

**Problem:** `GET DIAGNOSTICS v_return = ROW_COUNT > 0;` is syntactically invalid. Should be either:
- `GET DIAGNOSTICS v_rowcount := ROW_COUNT;` followed by comparison, OR
- Direct comparison: `IF (SELECT COUNT(*) FROM ...) > 0 THEN`

**Impact:** These procedures will not compile in PostgreSQL.

**Fix approach:** Replace with correct PostgreSQL `GET DIAGNOSTICS` syntax.

---

### Missing Materialized Views and Views

**Issue:** Known missing views in migration.

**Files:**
- `pg_migration/apply/301_fixes.views.sql` (lines 51-72)

**Missing components:**
1. Line 51: `bireader.v_tt_service_window` - marked with TODO, contains ghost columns `sys_nc00008$`, `sys_nc00009$` from Oracle's internal column naming
2. Line 56: `mss.mv_value_host_default` - materialized view completely missing

**Impact:** Applications relying on these views will fail; BI reader functionality may be broken.

**Fix approach:** 
1. For ghost columns: recreate view without Oracle system-generated column references
2. For missing MV: determine underlying query logic and recreate in PostgreSQL

---

## Known Bugs

### Container Build Failure in v2.0.0

**Issue:** Docker container version 2.0.0 is non-functional.

**Files:**
- `container/docker_orafree_based/CHANGELOG.md` line 73

**Symptoms:** "Does not work! breaks ORM Layer in OSIXINFO"

**Trigger:** Introduced when switching to Oracle 23-Free from Oracle EE 19c and pure Docker base.

**Workaround:** Use container version 2.1.0 or later.

**Status:** Fixed in v2.1.0.

---

## Security Considerations

### Hardcoded SSH Jump Host Placeholder

**Issue:** SSH host contains hardcoded placeholder in production code.

**Files:**
- `pg_migration/output/package_as_schema/PACKAGE.pg.sql` line 6385

**Code:**
```sql
C_OSAG_AUTHSYNC_SSH_CALL CONSTANT varchar(64) := '/usr/bin/ssh -q -t -t -x radiator@XXXXXX "stty hup; ';
```

**Risk:** Jump host hostname is replaced at runtime using `REPLACE()`. This pattern is error-prone; if replacement fails silently, SSH calls go to wrong host.

**Current mitigation:** Runtime replacement logic (line 6397)

**Recommendations:** 
1. Store SSH host in configuration table, not hardcoded constant
2. Add validation that replacement succeeded
3. Audit all SSH connection logic for proper host verification

---

## Performance Bottlenecks

### Large Table Migration with CLOB-to-VARCHAR2 Conversion

**Issue:** Tables containing CLOBs are being converted to VARCHAR2(32K), but migration strategy serializes large CLOB tables.

**Files:**
- `pg_migration/README.md` (lines 39-41)
- `container/docker_orafree_based/CHANGELOG.md` line 10

**Current approach:** K8s jobs run:
1. Parallelized normal data transfer
2. Parallelized masterdata transfer
3. **Sequential** bulk transfer of older entries with CLOBs

**Problem:** Large historical CLOB data transferred sequentially, which may take hours for multi-GB tables.

**Improvement path:** 
1. Parallelize CLOB table transfers by date range or ID range
2. Use PostgreSQL COPY for bulk load instead of row-by-row inserts
3. Consider compression/archival of old CLOB data pre-migration

---

### GET DIAGNOSTICS Usage with String Concatenation

**Issue:** Multiple procedures check row counts with verbosity overhead.

**Files:**
- `pg_migration/output/package_as_schema/PACKAGE.pg.sql` (lines 137-138, 1054-1055, 2401-2404, 7380-7383, 15182-15183)

**Current pattern:**
```sql
GET DIAGNOSTICS ora2pg_rowcount = ROW_COUNT;
IF ora2pg_rowcount = 0 THEN
```

**Impact:** For procedures that check row counts hundreds of times, this creates 2 statements per check instead of 1 conditional.

**Improvement path:** Use PostgreSQL's `FOUND` variable after INSERT/UPDATE/DELETE instead of GET DIAGNOSTICS for simple existence checks.

---

## Fragile Areas

### Complex Email Sending Procedure with UTL_SMTP

**Files:**
- `pg_migration/output/package_as_schema/PACKAGE.pg.sql` (lines 8994-9046)

**Why fragile:** 
- UTL_SMTP package does not exist in PostgreSQL
- Email logic contains SMTP protocol handling (HELO, MAIL, RCPT, DATA, QUIT)
- Multiple error handling branches with connection cleanup
- Nested exception handlers with plog.err() calls

**Safe modification:**
1. Extract email-sending logic to application layer (Node.js/Java)
2. Create PostgreSQL function stub that calls external email service via HTTP
3. Test with mock SMTP server before production deployment
4. Maintain backward compatibility by keeping same function signature

**Test coverage:** Currently none for this procedure in PostgreSQL context

---

### Aserto Integration in Triggers

**Files:**
- `pg_migration/output/package_as_schema/TRIGGER.pg.sql` (multiple lines)
  - Lines 468-476: `aserto.PublishAsertoUpdate()` in trigger
  - Lines 549-557, 575-583: More aserto calls
  - Lines 781-796, 809-817: aserto.PublishAsertoAction()
  
**Why fragile:**
- Triggers call external `aserto.*` procedures with complex parameters
- Must execute within trigger context (before/after insert/update/delete)
- No error handling documented; trigger failure cascades to application
- 30+ aserto calls in triggers alone

**Safe modification:**
1. Verify aserto schema/functions exist in PostgreSQL migration
2. Add error handling to trigger logic (catch and log, don't cascade)
3. Document aserto API contract
4. Test trigger + aserto integration end-to-end
5. Consider asynchronous notification model instead of synchronous calls

**Test coverage:** No PostgreSQL tests for aserto integration

---

### plog Logging Package Dependency

**Files:**
- All converted procedures reference `plog.notice()`, `plog.debug()`, `plog.err()`
- Example: `pg_migration/output/package_as_schema/PACKAGE.pg.sql` lines 7383, 9044, 9082, etc.

**Why fragile:**
- plog package must exist and be accessible in all schemas
- If plog is not available, all logging calls fail
- Logging is mixed with business logic (not separated)

**Safe modification:**
1. Ensure plog extension/schema is created first in PostgreSQL migration
2. Test that plog functions accept same parameter signatures as current code
3. If plog differs between Oracle and PostgreSQL, create compatibility wrapper
4. Consider extracting to application logging instead of database logging

---

## Scaling Limits

### Liquibase Changelog Synchronization

**Issue:** Changelog management relies on Liquibase version tracking, but container rebuild strategy requires manual tag management.

**Files:**
- `container/README.md` (lines 23-38)
- `container/docker_orafree_based/CHANGELOG.md` line 5 (v2.5.0: "use changelog-sync-to-tag")

**Current capacity:** Container successfully applies ~2500 changesets (per v2.5.0 comment).

**Limit:** 
- As changelog grows beyond 3000+ changesets, container build time increases substantially
- Truncating changelog for new baseline requires manual coordination with deployed systems
- PostgreSQL migration has not yet established sustainable changelog strategy

**Scaling path:**
1. Establish clear changelog archive/truncation policy (e.g., truncate every 2 years)
2. Test PostgreSQL changelog replay from scratch with 3000+ changesets
3. Implement automated changelog validation in CI
4. Plan for separate PostgreSQL-specific changelog once migration complete

---

## Dependencies at Risk

### ora2pg Tool Dependency

**Issue:** Migration relies entirely on ora2pg (version 25.0) for PL/SQL conversion.

**Files:**
- `pg_migration/run_oradata2pg.sh`
- `pg_migration/preparation/300_run_ora2pg.sh`
- `changes/scripts/migrate-ddl.sh`

**Risk:**
- ora2pg is open-source but development may stall
- Tool known to have limitations with complex PL/SQL (per its own output comments)
- No alternative tool identified for fallback

**Current state:** ora2pg output for 16K+ lines of packages confirmed to have errors (DBMS_*, UTL_* calls, malformed syntax).

**Migration plan:** Acknowledge ora2pg output as "first pass only" and require 100% manual review/fix of converted procedures.

---

### Liquibase Compatibility Across Oracle and PostgreSQL

**Issue:** Changelog uses Oracle-specific SQL (RAISE_APPLICATION_ERROR, NUMBER types, etc.) that may not replay identically in PostgreSQL.

**Files:**
- `changes/changelog-current.sql` (contains live Oracle SQL)
- `ddl/export/schema.oracle.sql` (Oracle DDL export)

**Risk:** Liquibase treats both databases identically; SQL written for Oracle may fail in PostgreSQL.

**Mitigation strategy needed:** 
1. Split changelog into Oracle-specific and cross-platform sections
2. Use Liquibase's `<includeAll path="...">` with separate directories per database
3. Validate changelog applies cleanly to PostgreSQL before production cutover

---

## Missing Critical Features

### PostgreSQL Testing Infrastructure

**Issue:** All current tests target Oracle container only.

**Files:**
- `tests/src/test/java/ch/open/osdb/build/changelog/ApplyTest.java`
- `tests/ci-verify-orm.sh`
- BUILD file

**Missing:**
- PostgreSQL container test setup
- PostgreSQL-specific schema validation tests
- Procedure/function execution tests in PostgreSQL
- Aserto, plog, and other package compatibility tests
- Data migration validation tests (Oracle → PostgreSQL comparison)

**Blocks:** Cannot validate migration correctness until PostgreSQL tests are created.

**Priority:** High - should be done before full production migration

---

### PostgreSQL-Specific Performance Tuning

**Issue:** No indexes, VACUUM/ANALYZE strategies, or partitioning designed for PostgreSQL.

**Files:**
- Migration documents don't mention PostgreSQL-specific optimizations

**Missing:**
- Index strategy (multi-column, partial, BRIN for large tables)
- Autovacuum configuration tuning
- Table partitioning for large historical tables (e.g., TICKET, EVENT)
- Connection pooling configuration (pgBouncer)

**Blocks:** Production PostgreSQL will perform significantly worse than Oracle until tuning applied.

**Priority:** Medium - can be addressed post-migration as performance testing reveals bottlenecks

---

## Test Coverage Gaps

### Procedures with Oracle-Specific Functions

**What's not tested:** All 16K+ lines of converted package code using DBMS_*, UTL_* functions.

**Files:**
- `pg_migration/output/package_as_schema/PACKAGE.pg.sql` lines with DBMS_UTILITY, DBMS_RANDOM, UTL_SMTP, DBMS_CRYPTO

**Risk:** Functions will fail at runtime in PostgreSQL; failures only discovered in production or UAT.

**Priority:** High

---

### Email Sending Logic (UTL_SMTP)

**What's not tested:** Procedure handling SMTP connections and email transmission.

**Files:**
- `pg_migration/output/package_as_schema/PACKAGE.pg.sql` lines 8994-9046

**Risk:** Email functionality broken post-migration; no warning until application attempts to send mail.

**Priority:** High - email critical for notifications

---

### Trigger + Aserto Integration

**What's not tested:** 30+ aserto calls within database triggers during insert/update/delete operations.

**Files:**
- `pg_migration/output/package_as_schema/TRIGGER.pg.sql` (multiple aserto.PublishAsertoUpdate/Action calls)

**Risk:** Authorization system out-of-sync if aserto calls fail silently; security data inconsistency.

**Priority:** High - security-critical

---

### Masterdata Consistency Post-Migration

**What's not tested:** 28+ masterdata CSV files transferred from Oracle.

**Files:**
- `masterdata/` (28 CSV files, ~4.0 MB total)
- `pg_migration/load_sim/prod_data.sql`

**Risk:** Data may be partially or incorrectly transferred; referential integrity broken if specific rows missing.

**Priority:** High - masterdata required for application function

---

## Migration Readiness

### Known Issues Documented in Code

- `pg_migration/apply/301_fixes.views.sql` line 51: TODO for bireader.v_tt_service_window (ghost columns)
- `pg_migration/apply/301_fixes.views.sql` line 56: TODO for mss.mv_value_host_default (missing)
- `pg_migration/README.md` line 34: TODO for masterdata transfer scripts

### Pre-Production Checklist Gaps

- [ ] All 31 Oracle-specific function calls identified and rewritten
- [ ] Email (UTL_SMTP) logic migrated to application layer
- [ ] plog package verified compatible with PostgreSQL
- [ ] aserto integration tested end-to-end
- [ ] Masterdata transfer process completed and validated
- [ ] Missing views (bireader.v_tt_service_window, mss.mv_value_host_default) recreated
- [ ] PostgreSQL-specific performance tuning applied
- [ ] Full end-to-end UAT in PostgreSQL environment
- [ ] Rollback/recovery plan documented and tested

---

*Technical debt audit: 2026-07-10*
