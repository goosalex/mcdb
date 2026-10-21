-- migration/test/schema-fixes/28_dbprop_mviews_fixes.sql
--
-- MSS.OSAG_DBPROP's host-scoped property lookup reads the view MSS.V_HOST_KEY_VALUE
-- (ddl/src/pkgb/mss_osag_dbprop.sql, get_string_by_host_key_id: `from mss.V_HOST_KEY_VALUE hkv,
-- mss.KEY k`), which sits on two materialized views, MSS.MV_VALUE_HOST and
-- MSS.MV_VALUE_HOST_DEFAULT (Oracle: REFRESH FAST ON COMMIT, dba_mviews). The ora2pg output
-- carries them in ddl/migrated/mviews/mss.sql, but build-template.sh loads only
-- ddl/migrated/tables + constraints (SCHEMA-FIXES.md: "ddl/migrated/mviews/ are not loaded"),
-- so in mcdb_tmpl the function compiles (PL/pgSQL resolves tables at run time) and FAILS at its
-- first call with 42P01 `relation "mss.v_host_key_value" does not exist`.
--
-- Found by the differential scenario migration/test/diff/scenarios/tt__event_interface__exec_actions
-- (2026-10-21): tt.event_interface_exec_event_type_actions reaches the lookup for every
-- tt.event_action with a procedure_key_id (master-data actions 2, 3 and 4 -- connection-down,
-- ISP-outage and customer-id-notification escalations) whenever the event has a host. Oracle
-- returned NULL (no DBPROP value for the host) and fell through to "no procedure executed";
-- PostgreSQL raised 42P01 out of exec_event_type_actions (the lookup is outside its swallowing
-- block), which addevent_new's outer handler would swallow and newevent_new would propagate.
--
-- Additive, idempotent, applied AFTER the base ddl/migrated load (D-P7: ddl/ is read-only).
-- Ledger entry: migration/test/SCHEMA-FIXES.md, fix #12.
--
-- The two materialized views are ddl/migrated/mviews/mss.sql's text VERBATIM (only the
-- `GRANT CREATE ON SCHEMA` and the `DROP MATERIALIZED VIEW` preamble are left out, and
-- IF NOT EXISTS added); every base table they reference (mss.host2service, mss.service,
-- mss.value, mss.key, mss.interface, vpn.vpn_member, vpn.partition) exists in mcdb_tmpl. The
-- view itself is commented out in that file ("in liquibase changelog only") and is
-- translated here from ddl/generated/schema.oracle.sql (CREATE OR REPLACE FORCE VIEW
-- "MSS"."V_HOST_KEY_VALUE"): decode() -> CASE, otherwise identical.
--
-- Refresh semantics: Oracle refreshes both MVs ON COMMIT; PostgreSQL materialized views are
-- refreshed only by REFRESH MATERIALIZED VIEW. Nothing in the TT closure refreshes them, so
-- the lookup sees the snapshot taken at template build (empty: mss.value and mss.host2service
-- are empty in mcdb_tmpl). Inside a never-committed harness transaction the Oracle MVs are
-- equally blind to the fixtures, so both engines return NULL for a fixture host -- which is
-- what the differential scenario compares. A production migration must schedule the refresh
-- (pg_cron, see migration/pgsql/_support/30_pg_cron_jobs.sql) or replace the MVs by views;
-- that decision is Phase 5's, not this fix's.

CREATE MATERIALIZED VIEW IF NOT EXISTS mss.mv_value_host
AS
select h2s.HOST_ID owner_host_id,
       v.KEY_ID,
       v.HOST_ID,
       v.SERVICE_ID,
       v.VPN_ID,
       v.COMPANY_ID,
       v.CONFIGURATION_GROUP_ID,
       v.STRING_VALUE,
       1 marker,
       h2s.ctid rowid1,
       s.ctid rowid2,
       v.ctid rowid3,
       NULL::tid rowid4,
       NULL::tid rowid5,
       NULL::tid rowid6
from mss.host2service h2s,
     mss.service s,
     mss.value v
where h2s.service_id = s.id
  and (v.HOST_ID = h2s.HOST_ID
    or v.SERVICE_ID = h2s.SERVICE_ID
    or v.CONFIGURATION_GROUP_ID = s.CONFIGURATION_GROUP_ID
    or v.COMPANY_ID = s.COMPANY_ID)

union all

select h2s.HOST_ID owner_host_id,
       v.KEY_ID,
       null HOST_ID,
       null SERVICE_ID,
       v.VPN_ID,
       null COMPANY_ID,
       null CONFIGURATION_GROUP_ID,
       v.STRING_VALUE,
       2 marker,
       h2s.ctid rowid1,
       NULL::tid rowid2,
       v.ctid rowid3,
       i.ctid rowid4,
       vm.ctid rowid5,
       vp.ctid rowid6
from mss.host2service h2s,
     mss.value v,
     mss.interface i,
     vpn.vpn_member vm,
     vpn.partition vp
where h2s.HOST_ID = i.HOST_ID
  and i.id = vm.interface_id
  and vm.partition_id = vp.id
  and v.VPN_ID = vp.vpn_id
;

CREATE INDEX IF NOT EXISTS idx_mv_value_host1 ON mss.mv_value_host (owner_host_id, key_id);
CREATE INDEX IF NOT EXISTS idx_mv_value_host2 ON mss.mv_value_host (key_id, owner_host_id);

-- second MV adds default scope and ranks scopes
CREATE MATERIALIZED VIEW IF NOT EXISTS mss.mv_value_host_default
AS
SELECT v.owner_host_id as host_id,
       k.name as key_name,
       CASE
           WHEN v.host_id IS NOT NULL THEN 1
           WHEN v.service_id IS NOT NULL THEN 2
           WHEN v.configuration_group_id IS NOT NULL THEN 3
           WHEN v.vpn_id IS NOT NULL THEN 4
           WHEN v.company_id IS NOT NULL THEN 5
           ELSE 9
           END  as n_scope,
       COALESCE(v.host_id, v.service_id, v.configuration_group_id, v.vpn_id,
                v.company_id)    AS object_id,
       v.string_value  AS string_value,
       1 marker,
       NULL::tid rowid1,
       k.ctid rowid2,
       v.ctid rowid3
FROM mss.mv_value_host v,
     mss.key k
where v.key_id = k.id

union all

-- default scope
select h2s.host_id,
       k.name as key_name,
       9 as n_scope,
       null as object_id,
       k.string_default as string_value,
       2 marker,
       h2s.ctid rowid1,
       k.ctid rowid2,
       NULL::tid rowid3
from mss.host2service h2s,
     mss.key k
-- yes, cartesian product
;

CREATE INDEX IF NOT EXISTS idx_mv_value_host_default1 ON mss.mv_value_host_default (host_id, key_name);
CREATE INDEX IF NOT EXISTS idx_mv_value_host_default2 ON mss.mv_value_host_default (key_name, host_id);

-- VIEW v_host_key_value: the key values at the most significant scope for every host
-- (ddl/generated/schema.oracle.sql, "MSS"."V_HOST_KEY_VALUE"; decode -> CASE).
CREATE OR REPLACE VIEW mss.v_host_key_value (host_id, key_name, scope, object_id, string_value) AS
select distinct v.host_id,
       v.key_name as key_name,
       CASE v.n_scope
           WHEN 1 THEN 'host'
           WHEN 2 THEN 'service'
           WHEN 3 THEN 'group'
           WHEN 4 THEN 'vpn'
           WHEN 5 THEN 'company'
           ELSE 'default'
       END as scope,
       v.object_id,
       v.string_value
from
  (select v.*,
      min(v.n_scope) over (partition by v.host_id, v.key_name) as min_scope
    from mss.mv_value_host_default v) v
where v.min_scope = v.n_scope;

COMMENT ON VIEW mss.v_host_key_value IS
    'View of table mss.value containing the key values at the most significant scope for every host (Oracle MSS.V_HOST_KEY_VALUE); read by mss.osag_dbprop_get_string_by_host_key_id. Sits on two materialized views that PostgreSQL does not refresh on commit -- see migration/test/schema-fixes/28_dbprop_mviews_fixes.sql';
