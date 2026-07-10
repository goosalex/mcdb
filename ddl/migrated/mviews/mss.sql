/*
 *
 * View mss.v_host_key_value
 *
 */
-- grant on commit refresh on vpn.vpn_member to mss;
-- grant on commit refresh on vpn.partition to mss;

-- grant select on vpn.mlog$_vpn_member to mss;
-- grant select on vpn.mlog$_partition to mss;

-- needed as we run this as sys
-- GRANT CREATE TABLE TO mss;
GRANT CREATE ON SCHEMA mss TO mss;

DROP MATERIALIZED VIEW IF EXISTS mss.mv_value_host;
-- first MV links values to host_id
create materialized view mss.mv_value_host
as
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


create index idx_mv_value_host1 on mss.mv_value_host (owner_host_id, key_id);
create index idx_mv_value_host2 on mss.mv_value_host (key_id, owner_host_id);

-- CREATE MATERIALIZED VIEW LOG ON mss.mv_value_host WITH ROWID (owner_host_id, key_id) INCLUDING NEW VALUES;


-- second MV adds default scope and ranks scopes
create materialized view mss.mv_value_host_default

as
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

create index idx_mv_value_host_default1 on mss.mv_value_host_default (host_id, key_name);
create index idx_mv_value_host_default2 on mss.mv_value_host_default (key_name, host_id);


-------------------------------------------------------------------------------------------
-- VIEW v_host_key_value
--      View of table mss.value containing the key values at the most significant scope
--      for every host
-------------------------------------------------------------------------------------------
/* in liquibase changelog only
create or replace force view mss.V_HOST_KEY_VALUE as
select distinct v.host_id,
                v.key_name as key_name,
                decode(v.n_scope,
                       1, 'host',
                       2, 'service',
                       3, 'group',
                       4, 'vpn',
                       5, 'company',
                       'default') as scope,
                v.object_id,
                v.string_value
from
    (select v.*,
            min(v.n_scope) over (partition by v.HOST_ID, v.key_name) as min_scope
     from mss.mv_value_host_default v) v
where v.min_scope = v.n_scope
;
*/