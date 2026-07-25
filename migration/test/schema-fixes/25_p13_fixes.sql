-- migration/test/schema-fixes/25_p13_fixes.sql
--
-- Plan 02-13 (phase-closing integration) CORRECTS a finding from plan 02-11
-- (migration/test/schema-fixes/23_p11_fixes.sql's own trailing note, and
-- migration/pgsql/tt/event_interface.FINDINGS.md's "Deliberately NOT fixed" section):
-- both claimed "auth.permission has no Oracle-side definition anywhere in
-- ddl/export/schema.oracle.sql" and that fabricating a replacement query "would be an
-- uninformed architectural guess". THAT VERDICT WAS WRONG. Both objects have real,
-- complete Oracle-side definitions:
--
--   - ddl/src/mviews/auth.sql:114  CREATE MATERIALIZED VIEW AUTH.PERMISSION
--   - ddl/src/mviews/auth.sql:15   CREATE MATERIALIZED VIEW AUTH.MV_SERVICE_ACCESS
--
-- ...and ora2pg had ALREADY converted both to PostgreSQL syntax, sitting unused at
-- ddl/migrated/mviews/auth.sql. build-template.sh never loaded ddl/migrated/mviews/ at
-- all (SCHEMA-FIXES.md's own "Also out of scope for this plan" section says so
-- explicitly, from plan 02-09 forward) -- so nobody had ever tried loading this file
-- until this plan did, and discovered it fails on three ora2pg-emitted schema-qualified
-- index names:
--
--   CREATE INDEX AUTH.IDX_MV_SERVICE_R_ROLE_LOGINCMP ON AUTH.MV_SERVICE_ACCESS (...)
--   CREATE INDEX AUTH.IDX_MV_SERVICE_ACCESS_R_LOGIN   ON AUTH.MV_SERVICE_ACCESS (...)
--   CREATE INDEX AUTH.IDX_MV_PERMISSION_ROLE_LOGIN    ON AUTH.PERMISSION (...)
--
-- `ERROR: syntax error at or near "."` -- PostgreSQL's CREATE INDEX takes an
-- (optionally schema-qualified) TABLE name, never a schema-qualified INDEX name (an
-- index always lives in its table's own schema; there is no CREATE INDEX
-- schema.name ON ... syntax at all). Confirmed this is the ONLY defect: ora2pg's fourth
-- index in the same file (line 103, `CREATE INDEX IDX_MV_USER_UNIT_R_ROLE_LOGIN ON
-- AUTH.MV_USER_UNIT_ACCESS (...)`) is NOT schema-qualified and loads fine as-is. This is
-- a mechanical ora2pg emission bug (three of its four index statements wrongly qualify
-- the index name), not an architectural unknown -- exactly the class of thing D-P7's
-- additive-fix convention exists for.
--
-- FIX: recreate all three materialized views verbatim from
-- ddl/migrated/mviews/auth.sql (D-P7: that file itself is never edited), with only the
-- three offending index names' schema-qualification stripped (index moves into its
-- table's own schema automatically -- no behavioral change, this is purely what
-- PostgreSQL's grammar requires). The view bodies, column lists, CASE mappings, and
-- join conditions are copied byte-for-byte from the ora2pg output. Oracle's own
-- `REFRESH FAST ON COMMIT` clause was already dropped by ora2pg (materialized-view-log
-- incremental refresh has no PostgreSQL equivalent); these become ordinary
-- point-in-time-snapshot materialized views, refreshed only by an explicit REFRESH
-- MATERIALIZED VIEW -- a known, accepted simplification (same shape as every other
-- "ora2pg already dropped an Oracle-only clause" case this project has seen), not a new
-- one introduced here.
--
-- SCOPE NOTE: this build order (schema-fixes step 4, BEFORE fixtures step 5) means these
-- three MVs are populated from whatever base-table data exists at CREATE time -- i.e.
-- empty at template-build time, since masterdata/ loads afterward, and never
-- auto-refreshed thereafter (PostgreSQL materialized views do not auto-refresh on
-- underlying-table writes, unlike Oracle's ON COMMIT REFRESH). This is sufficient for
-- what this plan needed: newticket_new's/newevent_new's admin-permission check does a
-- plain COUNT(*)/EXISTS against auth.permission -- with the relation now EXISTING (the
-- actual defect that previously raised "relation does not exist" and killed
-- S-TICKET-005's `lives_ok` assertion outright), the count legitimately evaluates to 0
-- for any login the fixture or the pilot's masterdata seeded (none of it was present
-- when the MV was snapshotted), taking the same "not an admin" branch Oracle's own
-- REFRESH FAST ON COMMIT view would take for the exact same missing-permission-row case.
-- A live-refresh strategy (a trigger-based refresh, or REFRESH MATERIALIZED VIEW after
-- fixtures/40_fixtures.sh) is explicitly NOT attempted here -- that is a real design
-- decision (materialized view vs. plain view vs. trigger-maintained table) that
-- Phase 3/5 should make deliberately, not inherit silently from a test-template
-- ordering accident. Flagged in PHASE2-FINDINGS.md.
--
-- Verified live (plan 02-13): loads cleanly against a bootstrap.sh --template mcdb_tmpl
-- clone with the base schema already present; with migration/pgsql installed on top,
-- tt.ticket_interface's S-TICKET-005 `lives_ok` assertion (previously "not ok ... died:
-- relation auth.permission does not exist") passes.

CREATE MATERIALIZED VIEW auth.mv_service_access
    AS (
-- company scope
SELECT 'CS' mv_marker, s.ctid::tid s_rowid, p.ctid::tid p_rowid, NULL::tid c_rowid, cs.ctid::tid cs_rowid, NULL::tid cus_rowid, NULL::tid uss_rowid, f.ctid::tid f_rowid, l2f.ctid::tid l2f_rowid,
       l2f.login_id login_id,
       CASE
           WHEN p.user_role_id = 1001 then 2
           WHEN p.user_role_id = 1002 then 15
           WHEN p.user_role_id = 1003 then 1
           ELSE -1
           END role_id, s.id service_id, s.company_id service_company_id
FROM auth.user_permission p, auth.profile f, auth.login2profile l2f, mss.service s,
     auth.user_company_scope cs
WHERE p.user_role_id IN (1001,1002,1003) AND p.profile_id = f.id AND f.id = l2f.profile_id
  AND p.id = cs.permission_id
  AND cs.company_id = s.company_id
UNION ALL
-- company unit scope
SELECT 'CUS' mv_marker, s.ctid::tid s_rowid, p.ctid::tid p_rowid, c.ctid::tid c_rowid, NULL::tid cs_rowid, cus.ctid::tid cus_rowid, NULL::tid uss_rowid, f.ctid::tid f_rowid, l2f.ctid::tid l2f_rowid,
       l2f.login_id login_id,
       CASE
           WHEN p.user_role_id = 1001 then 2
           WHEN p.user_role_id = 1002 then 15
           WHEN p.user_role_id = 1003 then 1
           ELSE -1
           END role_id, s.id service_id, s.company_id service_company_id
FROM auth.user_permission p, auth.profile f, auth.login2profile l2f, mss.service s, stop.company c, auth.user_company_unit_scope cus
WHERE p.user_role_id IN (1001,1002,1003) AND p.profile_id = f.id AND f.id = l2f.profile_id AND c.id = s.company_id
  AND p.id = cus.permission_id
  AND (
        (cus.company_unit_id = s.company_unit_id)
        OR (s.company_unit_id IS NULL AND cus.company_unit_id = c.default_company_unit_id)
    )
UNION ALL
-- service scope
SELECT 'USS' mv_marker, s.ctid::tid s_rowid, p.ctid::tid p_rowid, NULL::tid c_rowid, NULL::tid cs_rowid, NULL::tid cus_rowid, uss.ctid::tid uss_rowid, f.ctid::tid f_rowid, l2f.ctid::tid l2f_rowid,
       l2f.login_id login_id,
       CASE
           WHEN p.user_role_id = 1001 then 2
           WHEN p.user_role_id = 1002 then 15
           WHEN p.user_role_id = 1003 then 1
           ELSE -1
           END role_id, s.id service_id, s.company_id service_company_id
FROM auth.user_permission p, auth.profile f, auth.login2profile l2f, mss.service s,
     auth.user_service_scope uss
WHERE p.user_role_id IN (1001,1002,1003) AND p.profile_id = f.id AND f.id = l2f.profile_id
  AND p.id = uss.permission_id
  AND uss.service_id = s.id
    );

-- FIX applied here: index names de-schema-qualified (AUTH.IDX_... -> idx_...). Table
-- reference (ON AUTH.MV_SERVICE_ACCESS) is unaffected -- only the index's OWN name was
-- ever invalid.
CREATE INDEX idx_mv_service_r_role_logincmp ON auth.mv_service_access (service_id, login_id, role_id, service_company_id);
CREATE INDEX idx_mv_service_access_r_login ON auth.mv_service_access (login_id);

CREATE MATERIALIZED VIEW auth.mv_user_unit_access
    AS (
-- company scope
SELECT 'CS' mv_marker, p.ctid::tid p_rowid, u.ctid::tid u_rowid, cs.ctid::tid cs_rowid, NULL::tid uus_rowid, f.ctid::tid f_rowid, l2f.ctid::tid l2f_rowid,
       l2f.login_id login_id,
       CASE
           WHEN p.user_role_id = 3002 then 11
           WHEN p.user_role_id = 3005 then 12
           ELSE -1
           END
           role_id, u.id user_unit_id, u.company_id company_id
FROM auth.user_permission p, auth.profile f, auth.login2profile l2f, auth.user_unit u, auth.user_company_scope cs
WHERE p.user_role_id IN (3002,3005) AND p.profile_id = f.id AND f.id = l2f.profile_id
  AND p.id = cs.permission_id
  AND cs.company_id = u.company_id
UNION ALL
-- user unit
SELECT 'UUS' mv_marker, p.ctid::tid p_rowid, u.ctid::tid u_rowid, NULL::tid cs_rowid, uus.ctid::tid uus_rowid, f.ctid::tid f_rowid, l2f.ctid::tid l2f_rowid,
       l2f.login_id login_id,
       CASE
           WHEN p.user_role_id = 3002 then 11
           WHEN p.user_role_id = 3005 then 12
           ELSE -1
           END
           role_id, u.id user_unit_id, u.company_id company_id
FROM auth.user_permission p, auth.profile f, auth.login2profile l2f, auth.user_unit u, auth.user_unit_scope uus
WHERE p.user_role_id IN (3002,3005) AND p.profile_id = f.id AND f.id = l2f.profile_id
  AND p.id = uus.permission_id
  AND uus.user_unit_id = u.id
);

-- Unaffected by the fix: ora2pg's OWN output already emits this one unqualified
-- (matches ddl/migrated/mviews/auth.sql:103 verbatim -- included here only because this
-- fix file recreates the whole MV, not because this specific line needed correcting).
CREATE INDEX idx_mv_user_unit_r_role_login ON auth.mv_user_unit_access (user_unit_id, login_id, role_id);

CREATE MATERIALIZED VIEW auth.permission
AS
(
-- Company part
SELECT 'CS'                                                                                     mv_marker,
       p.ctid                                                                                   p_rowid,
       cs.ctid                                                                                  cs_rowid,
       NULL::tid                                                                                cus_rowid,
       NULL::tid                                                                                uus_rowid,
       NULL::tid                                                                                uss_rowid,
       r.ctid                                                                                   r_rowid,
       f.ctid                                                                                   f_rowid,
       l2f.ctid                                                                                 l2f_rowid,
       TO_NUMBER('9' || cast(cs.company_id as varchar) || cast(p.id as varchar), '99999999999') id,
       l2f.login_id                                                                             login_id,
       CASE
           WHEN r.id = 200 then 6
           WHEN r.id = 201 then 5
           WHEN r.id = 1003 then 1
           WHEN r.id = 1000 then 3
           WHEN r.id = 1001 then 2
           WHEN r.id = 1002 then 15
           WHEN r.id = 3005 then 12
           WHEN r.id = 3002 then 11
           WHEN r.id = 3003 then 16
           WHEN r.id = 5002 then 21
           WHEN r.id = 5003 then 26
           WHEN r.id = 5005 then 22
           ELSE -1
           END                                                                                  role_id,
       cs.company_id                                                                            company_id,
       NULL::bigint                                                                             company_unit_id,
       NULL::bigint                                                                             user_unit_id,
       NULL::bigint                                                                             service_id
FROM auth.user_permission p,
     auth.user_company_scope cs,
     auth.user_role r,
     auth.profile f,
     auth.login2profile l2f
WHERE p.user_role_id = r.id
  AND p.profile_id = f.id
  AND l2f.profile_id = f.id
  AND p.id = cs.permission_id
  AND r.id IN (200, 201, 1000, 1001, 1002, 1003, 3005, 3002, 3003, 5002, 5003, 5005)
UNION ALL
-- Company unit part
SELECT 'CUS'                                                                                          mv_marker,
       p.ctid                                                                                         p_rowid,
       NULL::tid                                                                                      cs_rowid,
       cus.ctid                                                                                       cus_rowid,
       NULL::tid                                                                                      uus_rowid,
       NULL::tid                                                                                      uss_rowid,
       r.ctid                                                                                         r_rowid,
       f.ctid                                                                                         f_rowid,
       l2f.ctid                                                                                       l2f_rowid,
       TO_NUMBER('8' || cast(cus.company_unit_id as varchar) || cast(p.id as varchar), '99999999999') id,
       l2f.login_id                                                                                   login_id,
       CASE
           WHEN r.id = 200 then 6
           WHEN r.id = 201 then 5
           WHEN r.id = 1003 then 1
           WHEN r.id = 1000 then 3
           WHEN r.id = 1001 then 2
           WHEN r.id = 1002 then 15
           WHEN r.id = 3005 then 12
           WHEN r.id = 3002 then 11
           WHEN r.id = 3003 then 16
           WHEN r.id = 5002 then 21
           WHEN r.id = 5003 then 26
           WHEN r.id = 5005 then 22
           ELSE -1
           END                                                                                        role_id,
       NULL::bigint                                                                                   company_id,
       cus.company_unit_id                                                                            company_unit_id,
       NULL::bigint                                                                                   user_unit_id,
       NULL::bigint                                                                                   service_id
FROM auth.user_permission p,
     auth.user_company_unit_scope cus,
     auth.user_role r,
     auth.profile f,
     auth.login2profile l2f
WHERE p.user_role_id = r.id
  AND p.profile_id = f.id
  AND l2f.profile_id = f.id
  AND p.id = cus.permission_id
  AND r.id IN (200, 201, 1000, 1001, 1002, 1003, 3005, 3002, 3003, 5002, 5003, 5005)
UNION ALL
-- User unit part
SELECT 'UUS'                                                                                       mv_marker,
       p.ctid                                                                                      p_rowid,
       NULL::tid                                                                                   cs_rowid,
       NULL::tid                                                                                   cus_rowid,
       uus.ctid                                                                                    uus_rowid,
       NULL::tid                                                                                   uss_rowid,
       r.ctid                                                                                      r_rowid,
       f.ctid                                                                                      f_rowid,
       l2f.ctid                                                                                    l2f_rowid,
       TO_NUMBER('7' || cast(uus.user_unit_id as varchar) || cast(p.id as varchar), '99999999999') id,
       l2f.login_id                                                                                login_id,
       CASE
           WHEN r.id = 200 then 6
           WHEN r.id = 201 then 5
           WHEN r.id = 1003 then 1
           WHEN r.id = 1000 then 3
           WHEN r.id = 1001 then 2
           WHEN r.id = 1002 then 15
           WHEN r.id = 3005 then 12
           WHEN r.id = 3002 then 11
           WHEN r.id = 3003 then 16
           WHEN r.id = 5002 then 21
           WHEN r.id = 5003 then 26
           WHEN r.id = 5005 then 22
           ELSE -1
           END                                                                                     role_id,
       NULL::bigint                                                                                company_id,
       NULL::bigint                                                                                company_unit_id,
       uus.user_unit_id                                                                            user_unit_id,
       NULL::bigint                                                                                service_id
FROM auth.user_permission p,
     auth.user_unit_scope uus,
     auth.user_role r,
     auth.profile f,
     auth.login2profile l2f
WHERE p.user_role_id = r.id
  AND p.profile_id = f.id
  AND l2f.profile_id = f.id
  AND p.id = uus.permission_id
  AND r.id IN (200, 201, 1000, 1001, 1002, 1003, 3005, 3002, 3003, 5002, 5003, 5005)
UNION ALL
-- Service part
SELECT 'USS'                                                   mv_marker,
       p.ctid                                                  p_rowid,
       NULL::tid                                               cs_rowid,
       NULL::tid                                               cus_rowid,
       NULL::tid                                               uus_rowid,
       uss.ctid                                                uss_rowid,
       r.ctid                                                  r_rowid,
       f.ctid                                                  f_rowid,
       l2f.ctid                                                l2f_rowid,
       TO_NUMBER('6' || uss.service_id || p.id, '99999999999') id,
       l2f.login_id                                            login_id,
       CASE
           WHEN r.id = 200 then 6
           WHEN r.id = 201 then 5
           WHEN r.id = 1003 then 1
           WHEN r.id = 1000 then 3
           WHEN r.id = 1001 then 2
           WHEN r.id = 1002 then 15
           WHEN r.id = 3005 then 12
           WHEN r.id = 3002 then 11
           WHEN r.id = 3003 then 16
           WHEN r.id = 5002 then 21
           WHEN r.id = 5003 then 26
           WHEN r.id = 5005 then 22
           ELSE -1
           END                                                 role_id,
       NULL::bigint                                            company_id,
       NULL::bigint                                            company_unit_id,
       NULL::bigint                                            user_unit_id,
       uss.service_id                                          service_id
FROM auth.user_permission p,
     auth.user_service_scope uss,
     auth.user_role r,
     auth.profile f,
     auth.login2profile l2f
WHERE p.user_role_id = r.id
  AND p.profile_id = f.id
  AND l2f.profile_id = f.id
  AND p.id = uss.permission_id
  AND r.id IN (200, 201, 1000, 1001, 1002, 1003, 3005, 3002, 3003, 5002, 5003, 5005)
);

-- FIX applied here: index name de-schema-qualified (AUTH.IDX_MV_PERMISSION_ROLE_LOGIN ->
-- idx_mv_permission_role_login).
CREATE INDEX idx_mv_permission_role_login ON auth.permission (login_id, role_id);

-- PHASE 3/5 ACTION: (1) file the schema-qualified-index-name defect upstream against the
-- ora2pg export configuration for materialized-view indexes specifically (every OTHER
-- CREATE INDEX this project has seen from ora2pg is correctly unqualified; this appears
-- confined to the mviews/ output path) and regenerate, dropping this file's index
-- statements once fixed; (2) decide, deliberately, whether these three MVs should be
-- kept as plain snapshot materialized views (requiring an explicit refresh strategy --
-- cron, trigger-driven, or a REFRESH MATERIALIZED VIEW CONCURRENTLY call wired into
-- whatever replaces the deleted ON COMMIT semantics) or converted to plain views (always
-- current, no refresh needed, at the cost of the read-performance Oracle's own header
-- comment says NOPARALLEL materialized views exist to provide). Both mv_service_access
-- and permission gate real authorization checks (newevent_new's/newticket_new's
-- company-wide-admin branch, and -- per their own header comments -- broader RLS-style
-- service-access checks not yet reached by any translated pilot routine); a stale
-- snapshot silently under- or over-granting access is a real security-relevant
-- consequence Phase 3/5 must resolve, not inherit from this test-template default.
