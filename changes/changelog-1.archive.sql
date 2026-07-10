--liquibase formatted sql logicalFilePath:changelog-1.sql
-- CAUTION:
--  Always append at the end only!
-- If you modify a changeset, then specify runOnChange:true if you want it to be executed again

--changeset ogl:1000
--comment: This initial changeset servers as a placeholder
SELECT 1 FROM DUAL;

--changeset alg:1001
--comment: DB-1669, ignore decommissioned hosts in consistency check

update MCDB_CHECKS.CONSISTENCY_CHECKS SET STATEMENT =
                                              'SELECT h.name host, i1.name interface_1, mss.osag_ip.num2ip(i1.ip_address) ip1, i2.name interface_2, mss.osag_ip.num2ip(i2.ip_address) ip2
                                              FROM mss.host h INNER JOIN mss.interface i1 ON h.ID = i1.HOST_ID INNER JOIN mss.interface i2 ON h.ID = i2.HOST_ID AND i1.ip_address = i2.ip_address
                                              WHERE i1.id > i2.id AND i1.ip_address > 0
                                                AND i2.name NOT LIKE ''reth\%'' AND i1.name NOT LIKE ''reth\%''
                                                AND h.id not in (22429, 22430, 25928, 25929)
                                                and not exists (select 1 from mss.decomm_host dh where dh.host_id = h.id and dh.status_id not in (2,4))
                                              '
WHERE ID = 6 AND CHECK_KEY = 'SEL_unique_ip_per_host';


update MCDB_CHECKS.CONSISTENCY_CHECKS SET STATEMENT = 'select h.id, h.name, OSAG_IP.num2ip(tn.IP_ADDRESS) target_net, tn.NETMASK, OSAG_IP.num2ip(nh.IP_ADDRESS) gw, OSAG_IP.num2ip(gwn.IP_ADDRESS) gw_net, gwn.NETMASK
from mss.STATIC_ROUTE sr, mss.HOST h, mss.INTERFACE nh, mss.NETWORK tn, mss.NETWORK gwn
where sr.ROUTE_OWNER_HOST_ID = h.id
  and sr.NEXTHOP_INTERFACE_ID = nh.id
  and sr.NETWORK_ID = tn.id
  and nh.NETWORK_ID = gwn.id
  and not exists (
        select 1
        from mss.INTERFACE i
        where i.HOST_ID = sr.ROUTE_OWNER_HOST_ID
          and i.NETWORK_ID = nh.NETWORK_ID
    )
  and not exists (select 1 from mss.decomm_host dh where dh.host_id = h.id and dh.status_id not in (2,4))
'
WHERE ID = 53 AND CHECK_KEY = 'SEL_wrong_nexthop';

--changeset ogl:1002
--comment: MC-24832: new field auth.login.OIDC_ZITADEL_ID
ALTER TABLE AUTH.LOGIN ADD (OIDC_ZITADEL_ID VARCHAR2(128) NULL);

--changeset ogl:1003
--comment: DB-1674: required by package
GRANT SELECT ON V_$INSTANCE TO OSAG;

--changeset ogl:1004
--comment: DB-1674: add config table
CREATE TABLE AUTH.JUMPHOST (
  DB_HOST   VARCHAR2(64) NOT NULL,
  JUMP_HOST VARCHAR2(64) NOT NULL,
  CONSTRAINT U_JUMPHOST UNIQUE (DB_HOST, JUMP_HOST)
);

INSERT INTO AUTH.JUMPHOST(db_host, jump_host) values ('ora19-a13-prod-1.open.ch', 'jump2');
INSERT INTO AUTH.JUMPHOST(db_host, jump_host) values ('ora19-i33-prod-2.open.ch', 'jump1');
INSERT INTO AUTH.JUMPHOST(db_host, jump_host) values ('ora19-r29-dev-1.open.ch', 'zuse');
INSERT INTO AUTH.JUMPHOST(db_host, jump_host) values ('ora19-r29-dev-2.open.ch', 'zuse');

--changeset ogl:1005
--comment: DB-1674: required by package
GRANT SELECT ON V_$INSTANCE TO AUTH;

--changeset nbo:1007
--comment: MC-24832: unique index auth.login.OIDC_ZITADEL_ID
CREATE UNIQUE INDEX AUTH.IDX_OIDC_ZITADEL_ID ON AUTH.LOGIN (OIDC_ZITADEL_ID);

--changeset ogl:1008
--comment: MC-24833: Create 'zitadel.migration' dbprop
INSERT INTO MSS.KEY (DESCRIPTION,ID,KEY_TYPE_ID,NAME,OPERATING_SYSTEM_ID,REGEXP,SERVICE_OPTION_TYPE_ID,STRING_DEFAULT) VALUES ('Specifies if company was migrated to Zitadel',56701,1,'zitadel.migration',NULL,'^[01]$',NULL,0);

--changeset ogl:1009
--comment: DB-1678: New DB User for Buildcloud
CREATE USER "SVC_BUILDCLOUD_PARAMGEN" IDENTIFIED BY "xxxxxx" ACCOUNT LOCK
  DEFAULT TABLESPACE "USERS"
  TEMPORARY TABLESPACE "TEMP";

GRANT "MSS_LOGIN_USER" TO "SVC_BUILDCLOUD_PARAMGEN";

ALTER USER "SVC_BUILDCLOUD_PARAMGEN" DEFAULT ROLE "MSS_LOGIN_USER";

GRANT EXEMPT ACCESS POLICY TO "SVC_BUILDCLOUD_PARAMGEN";

--changeset ogl:1010 contextFilter:dummyPasswords
alter user SVC_BUILDCLOUD_PARAMGEN identified by "password" account unlock;

--changeset ogl:1011
--comment: DB-1678 grants
GRANT SELECT ON MSS.HOST TO SVC_BUILDCLOUD_PARAMGEN;
GRANT SELECT ON MSS.INTERFACE TO SVC_BUILDCLOUD_PARAMGEN;
GRANT SELECT ON MSS.NETWORK TO SVC_BUILDCLOUD_PARAMGEN;
GRANT SELECT ON MSS.HOST2SERVICE TO SVC_BUILDCLOUD_PARAMGEN;
GRANT SELECT ON MSS.SERVICE TO SVC_BUILDCLOUD_PARAMGEN;

--changeset ogl:1012
--comment: MC-24833: Rename 'zitadel.migration' dbprop to 'migrate.zitadel'
update mss.key k
set k.NAME='migrate.zitadel'
where k.id=56701
  and k.name='zitadel.migration';

--changeset ogl:1013
--comment: fix wrong boolean ORM type mapping
alter table vpn.tunnel modify tunnelmode number(2);

--changeset ogl:1014
--comment: FW-5398: grant read company table for svc_firewall_api
grant references on stop.COMPANY to svc_firewall_api;

--changeset ogl:1015
--comment: DB1687: New DB User for feature flags service
CREATE USER "SVC_FEATURE_FLAG" IDENTIFIED BY "xxxxxx" ACCOUNT LOCK
  DEFAULT TABLESPACE "USERS"
  TEMPORARY TABLESPACE "TEMP";

GRANT "MSS_LOGIN_USER" TO "SVC_FEATURE_FLAG";

ALTER USER "SVC_FEATURE_FLAG" DEFAULT ROLE "MSS_LOGIN_USER";

GRANT EXEMPT ACCESS POLICY TO "SVC_FEATURE_FLAG";
--changeset ogl:1016 contextFilter:dummyPasswords
alter user SVC_FEATURE_FLAG identified by "password" account unlock;
--changeset ogl:1017
grant select on mss.V_HOST_KEY_VALUE to SVC_FEATURE_FLAG;
grant select on mss.SERVICE to SVC_FEATURE_FLAG;
grant select on mss.HOST to SVC_FEATURE_FLAG;
grant select on mss.HOST2SERVICE to SVC_FEATURE_FLAG;
grant select on mss.CONFIGURATION_GROUP to SVC_FEATURE_FLAG;
grant select on stop.COMPANY to SVC_FEATURE_FLAG;
grant select on stop.COMPANY_UNIT to SVC_FEATURE_FLAG;
grant select on stop.CONTACT to SVC_FEATURE_FLAG;
grant select on auth.LOGIN to SVC_FEATURE_FLAG;
grant select on auth.user_permission to SVC_FEATURE_FLAG;
grant select on auth.user_service_scope to SVC_FEATURE_FLAG;
grant select on auth.user_unit_scope to SVC_FEATURE_FLAG;
grant select on auth.user_company_unit_scope to SVC_FEATURE_FLAG;
grant select on auth.user_company_scope to SVC_FEATURE_FLAG;
grant select on auth.user_role to SVC_FEATURE_FLAG;
grant select on auth.profile to SVC_FEATURE_FLAG;
grant select on auth.login2profile to SVC_FEATURE_FLAG;
grant select on vpn.VPN to SVC_FEATURE_FLAG;
grant select on vpn.PARTITION to SVC_FEATURE_FLAG;
grant select on vpn.VPN_MEMBER to SVC_FEATURE_FLAG;
--changeset ogl:1018
grant select on mss.KEY to SVC_FEATURE_FLAG;
grant select on mss.VALUE to SVC_FEATURE_FLAG;
--changeset sev:1019
--comment: ZTNA-570: Create 'ztna.upstream' dbprop
INSERT INTO MSS.KEY (DESCRIPTION,ID,KEY_TYPE_ID,NAME,OPERATING_SYSTEM_ID,REGEXP,SERVICE_OPTION_TYPE_ID,STRING_DEFAULT) VALUES ('Specify upstream for IDAC',24506,4,'ztna.upstream',NULL,'^[A-Za-z0-9-_\.]+$',NULL,'cyolo.io');

--changeset nbo:1020
--comment: MC-25018: making login.HOMEAUTHHOST_ID nullable
alter table auth.LOGIN modify (HOMEAUTHHOST_ID NULL);

--changeset ogl:1020
--comment: DB-1688: New DB user SVC_OIDC_MIGRATION
CREATE USER "SVC_OIDC_MIGRATION" IDENTIFIED BY "xxxxxx" ACCOUNT LOCK
  DEFAULT TABLESPACE "USERS"
  TEMPORARY TABLESPACE "TEMP";

GRANT "MSS_LOGIN_USER" TO "SVC_OIDC_MIGRATION";

ALTER USER "SVC_OIDC_MIGRATION" DEFAULT ROLE "MSS_LOGIN_USER";

GRANT EXEMPT ACCESS POLICY TO "SVC_OIDC_MIGRATION";

GRANT SELECT on auth.login to SVC_OIDC_MIGRATION;
GRANT UPDATE on auth.login to SVC_OIDC_MIGRATION;
GRANT INSERT on auth.login to SVC_OIDC_MIGRATION;
GRANT SELECT on auth.tunnelgroup to SVC_OIDC_MIGRATION;
GRANT SELECT on auth.login2tunnelgroup to SVC_OIDC_MIGRATION;
GRANT INSERT on auth.login2tunnelgroup to SVC_OIDC_MIGRATION;
GRANT SELECT on auth.profile to SVC_OIDC_MIGRATION;
GRANT INSERT on auth.profile to SVC_OIDC_MIGRATION;
GRANT SELECT on auth.login2profile to SVC_OIDC_MIGRATION;
GRANT INSERT on auth.login2profile to SVC_OIDC_MIGRATION;
GRANT SELECT on auth.user_permission to SVC_OIDC_MIGRATION;
GRANT INSERT on auth.user_permission to SVC_OIDC_MIGRATION;
GRANT SELECT on auth.user_role to SVC_OIDC_MIGRATION;
GRANT SELECT on auth.groups to SVC_OIDC_MIGRATION;
GRANT SELECT on AUTH.login2groups to SVC_OIDC_MIGRATION;
GRANT INSERT on AUTH.login2groups to SVC_OIDC_MIGRATION;
GRANT SELECT on auth.alias to SVC_OIDC_MIGRATION;
GRANT SELECT on auth.temp_access_key to SVC_OIDC_MIGRATION;
GRANT SELECT on auth.token to SVC_OIDC_MIGRATION;
GRANT SELECT on auth.tokenreplacementstate to SVC_OIDC_MIGRATION;
GRANT SELECT on auth.user_unit to SVC_OIDC_MIGRATION;
GRANT SELECT on auth.authhost to SVC_OIDC_MIGRATION;
GRANT SELECT on auth.mc_settings to SVC_OIDC_MIGRATION;
GRANT SELECT on auth.passwordtype to SVC_OIDC_MIGRATION;
GRANT SELECT on stop.contact to SVC_OIDC_MIGRATION;
GRANT UPDATE on stop.contact to SVC_OIDC_MIGRATION;
GRANT INSERT on stop.contact to SVC_OIDC_MIGRATION;
GRANT SELECT on stop.company to SVC_OIDC_MIGRATION;
GRANT SELECT on stop.contact_sync to SVC_OIDC_MIGRATION;
GRANT SELECT on mss.cost_center to SVC_OIDC_MIGRATION;
--changeset ogl:1021 contextFilter:dummyPasswords
alter user SVC_OIDC_MIGRATION identified by "password" account unlock;

--changeset isa:1022
--comment: WAN-2286: Add new DB Prop migrate.frrouting
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (56702, 'migrate.frrouting', 1, '0', '^[01]$', NULL, 'Replace Quagga with FRRouting');

--changeset nkj:1023
--comment: MC-24877: Grant interface permission for feature flags service user
GRANT SELECT on mss.INTERFACE to SVC_FEATURE_FLAG;

--changeset mlo:1024
--comment: MC-25070: Add VPN.PARTITION permission to webcache to be able to prefetch vpn connections
GRANT SELECT ON VPN.PARTITION TO WEBCACHE;

--changeset nbo:1025
--comment: MC-24840: new audit trail target
INSERT INTO mcaudit.RECORD_TYPE (ID,NAME,SHORT,DESCRIPTION,SYSTEM_ID) values (7, 'Login OIDC Migrated', 'login_oidc_migrated', 'Login was migrated to OIDC', 2);

--changeset ssk:1026
--comment: CLOUD-86: Cleanup the 'cloudexpress' service type
UPDATE MSS.SERVICE_TYPE SET DEPRECATED = 1 WHERE ID = 561;
UPDATE MSS.SERVICE_COMPONENT SET DEPRECATED = 1 WHERE ID = 14;

--changeset mlo:1027
--comment: TRIVIAL: Change 'migrate.zitadel' dbprop to be 0/1/2 instead of 0/1 and create migrate.zitadel.earlyaccess
update mss.key k
set k.REGEXP='^[012]$', k.KEY_TYPE_ID=2
where k.id=56701
  and k.name='migrate.zitadel';
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (56703, 'migrate.zitadel.earlyaccess', 4, '', '^[a-zA-Z0-9\-\@\._,]*$', NULL, 'Early access users for zitadel migration for company, comma-separated list of logins');

--changeset alg:1028
--comment DB-1697 Create new DB user SVC_TERRAFORM_EXECUTOR
CREATE USER "SVC_TERRAFORM_EXECUTOR" IDENTIFIED BY "xxxxxx" ACCOUNT LOCK
    DEFAULT TABLESPACE "USERS"
    TEMPORARY TABLESPACE "TEMP";
GRANT "MSS_LOGIN_USER" TO "SVC_TERRAFORM_EXECUTOR";

ALTER USER "SVC_TERRAFORM_EXECUTOR" DEFAULT ROLE "MSS_LOGIN_USER";

GRANT EXEMPT ACCESS POLICY TO "SVC_TERRAFORM_EXECUTOR";

--changeset alg:1029 contextFilter:dummyPasswords
--comment DB-1697 Create new DB user SVC_TERRAFORM_EXECUTOR
alter user SVC_TERRAFORM_EXECUTOR identified by "password" account unlock;

--changeset alg:1030
--comment DB-1697 Create new DB user SVC_TERRAFORM_EXECUTOR
GRANT SELECT ON MSS.VALUE TO SVC_TERRAFORM_EXECUTOR;
-- not yet sure if both of these are strictly needed, may depend on implementation:
GRANT SELECT ON MSS.KEY TO SVC_TERRAFORM_EXECUTOR;
GRANT SELECT ON MSS.MV_VALUE_HOST TO SVC_TERRAFORM_EXECUTOR;

--changeset mlo:1028
--comment: MC-24837: Add LoginType grant to SVC_OIDC_MIGRATION
GRANT SELECT on AUTH.LOGINTYPE to SVC_OIDC_MIGRATION;

--changeset mlo:1031
--comment: MC-24837: Add LoginType grant to SVC_OIDC_MIGRATION
GRANT SELECT on AUTH.SEQ_LOGIN_ID to SVC_OIDC_MIGRATION;
GRANT SELECT on STOP.CONTACT_SEQ to SVC_OIDC_MIGRATION;
GRANT SELECT on AUTH.SEQ_PROFILE to SVC_OIDC_MIGRATION;
GRANT SELECT on AUTH.SEQ_USER_PERMISSION to SVC_OIDC_MIGRATION;

--changeset mlo:1032
--comment: MC-24837: Add LoginType grant to SVC_OIDC_MIGRATION
GRANT SELECT ON MCAUDIT.RECORD_SEQ TO SVC_OIDC_MIGRATION;
GRANT SELECT ON MCAUDIT.TRANSACTION_SEQ TO SVC_OIDC_MIGRATION;
GRANT SELECT ON MCAUDIT.APPLICATION TO SVC_OIDC_MIGRATION;
GRANT SELECT ON MCAUDIT.COMPONENT TO SVC_OIDC_MIGRATION;
GRANT INSERT ON MCAUDIT.RECORD TO SVC_OIDC_MIGRATION;
GRANT SELECT ON MCAUDIT.RECORD_TYPE TO SVC_OIDC_MIGRATION;
GRANT SELECT ON MCAUDIT.SEVERITY TO SVC_OIDC_MIGRATION;
GRANT SELECT ON MCAUDIT.SYSTEM TO SVC_OIDC_MIGRATION;

--changeset mlo:1033
--comment: MC-24837: Add LoginType grant to SVC_OIDC_MIGRATION
GRANT SELECT ON MSS.OBJECT_TYPE TO SVC_OIDC_MIGRATION;

--changeset mlo:1034
--comment: MC-24837: Add LoginType grant to SVC_OIDC_MIGRATION
GRANT SELECT ON MSS.FIELD_MAPPING TO SVC_OIDC_MIGRATION;

--changeset mlo:1035
--comment: MC-24837: Add LoginType grant to SVC_OIDC_MIGRATION
GRANT SELECT ON MSS.FIELD_MAPPING_TYPE TO SVC_OIDC_MIGRATION;

--changeset mlo:1036
--comment: MC-24837: Add LOGIN2TUNNELGROUP DELETE grant to SVC_OIDC_MIGRATION
GRANT DELETE on AUTH.LOGIN2TUNNELGROUP to SVC_OIDC_MIGRATION;

--changeset nbo:1037
--comment: MC-25116: new audit trail type
INSERT INTO mcaudit.RECORD_TYPE (ID,NAME,SHORT,DESCRIPTION,SYSTEM_ID) values (8, 'Login OIDC Updated', 'login_oidc_updated', 'OIDC Login was updated after login', 2);

--changeset aba:1038
--comment: MON-3422: decommission mgmtserver.balu_broker.rabbitmq dbprop
delete from mss.key where id = 24527;

--changeset nbo:1039
--comment: MC-25120:
alter table auth.login add (oidc_federated NUMBER(1) default 0 not null);

--changeset tbo:1040
--comment: HEL-335: decommission mgmtserver.lake.ingestion dbprop
DELETE FROM mss.key WHERE id = 21478;

--changeset adu:1041
--comment: PRX-7086: Add new dbprop migrate.2023.squid.urlfilter
INSERT INTO MSS.KEY (DESCRIPTION,ID,KEY_TYPE_ID,NAME,OPERATING_SYSTEM_ID,REGEXP,SERVICE_OPTION_TYPE_ID,STRING_DEFAULT) VALUES ('Activates the new URLF engine on a host for migrating customers',56704,1,'migrate.2023.squid.urlfilter',22,'^[01]$',NULL,0);

--changeset isa:1042
--comment: FW-5527: Add new DB Prop iptables.vrrp_redirect.disable.interfaces
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (56705, 'iptables.vrrp_redirect.disable.interfaces', 4, '', '^((eth|lacp)[\d]+((\.[\d+]+)?\s+)*)+$', NULL, 'Disable VRRP redirect on interfaces (space-separated list)');

--changeset phm:1043
--comment: MON-3471: add scope resolver for alert-handler mc ticket output
GRANT SELECT ON MSS.HOST TO SVC_ALERTHANDLER;
GRANT SELECT ON MSS.HOST2SERVICE TO SVC_ALERTHANDLER;
GRANT SELECT ON MSS.SERVICE TO SVC_ALERTHANDLER;
GRANT SELECT ON MSS.INTERFACE TO SVC_ALERTHANDLER;
GRANT SELECT ON MSS.INTERFACE2ISP_LINK TO SVC_ALERTHANDLER;
GRANT SELECT ON MSS.ISP_LINK TO SVC_ALERTHANDLER;

--changeset dmg:1044
--comment: DB-1697: Grant Terraform executor rights to query company short
GRANT SELECT on stop.company to SVC_TERRAFORM_EXECUTOR;

--changeset ogl:1045 tag:v1.0.1
--comment: Base of new container
SELECT 1 FROM DUAL;

--changeset nbo:1046
--comment: MC-25146: new field auth.login.OIDC_ZITADEL_USERNAME
ALTER TABLE AUTH.LOGIN ADD (OIDC_ZITADEL_USERNAME VARCHAR2(250) NULL);
ALTER TABLE AUTH.LOGIN ADD CONSTRAINT IDX_OIDC_ZITADEL_USERNAME UNIQUE(OIDC_ZITADEL_USERNAME);
CREATE UNIQUE INDEX AUTH.IDX_OIDC_ZITADEL_USERNAME2 ON AUTH.LOGIN (LOWER(OIDC_ZITADEL_USERNAME));

--changeset alg:1047
--comment: DB-1703: unique constraint on auth.login is wrong
CREATE UNIQUE INDEX AUTH.U_IDX_LOGIN_LOWER_LOGIN_HOMEAUTHHOST ON AUTH.LOGIN(lower(LOGIN), HOMEAUTHHOST_ID);
ALTER TABLE AUTH.LOGIN DROP CONSTRAINT U_LOGIN_LOGIN_HOMEAUTHHOST;
DROP INDEX AUTH.U_LOGIN_LOGIN_HOMEAUTHHOST;
ALTER TABLE AUTH.LOGIN ADD CONSTRAINT U_CONST_LOGIN_LOWER_LOGIN_HOMEAUTHHOST UNIQUE (LOGIN, HOMEAUTHHOST_ID) ;

--changeset nbo:1047
--comment: MC-25145: additional grants used for audit trail
GRANT SELECT ON MCAUDIT.RECORD TO SVC_OIDC_MIGRATION;
GRANT UPDATE ON MCAUDIT.RECORD TO SVC_OIDC_MIGRATION;

--changeset nbo:1048
--comment: MC-25174: revert obsolete grants for SVC_OIDC_MIGRATION user
REVOKE SELECT ON auth.alias FROM SVC_OIDC_MIGRATION;
REVOKE SELECT ON auth.temp_access_key FROM SVC_OIDC_MIGRATION;
REVOKE SELECT ON auth.token FROM SVC_OIDC_MIGRATION;
REVOKE SELECT ON auth.tokenreplacementstate FROM SVC_OIDC_MIGRATION;
REVOKE SELECT ON auth.user_unit FROM SVC_OIDC_MIGRATION;
REVOKE SELECT ON auth.authhost FROM SVC_OIDC_MIGRATION;
REVOKE SELECT ON auth.mc_settings FROM SVC_OIDC_MIGRATION;
REVOKE SELECT ON auth.passwordtype FROM SVC_OIDC_MIGRATION;
REVOKE SELECT ON auth.tunnelgroup FROM SVC_OIDC_MIGRATION;
REVOKE SELECT ON auth.login2tunnelgroup FROM SVC_OIDC_MIGRATION;
REVOKE INSERT ON auth.login2tunnelgroup FROM SVC_OIDC_MIGRATION;
REVOKE SELECT ON auth.profile FROM SVC_OIDC_MIGRATION;
REVOKE INSERT ON auth.profile FROM SVC_OIDC_MIGRATION;
REVOKE SELECT ON auth.login2profile FROM SVC_OIDC_MIGRATION;
REVOKE INSERT ON auth.login2profile FROM SVC_OIDC_MIGRATION;
REVOKE SELECT ON auth.user_permission FROM SVC_OIDC_MIGRATION;
REVOKE INSERT ON auth.user_permission FROM SVC_OIDC_MIGRATION;
REVOKE SELECT ON auth.user_role FROM SVC_OIDC_MIGRATION;
REVOKE SELECT ON auth.groups FROM SVC_OIDC_MIGRATION;
REVOKE SELECT ON AUTH.login2groups FROM SVC_OIDC_MIGRATION;
REVOKE INSERT ON AUTH.login2groups FROM SVC_OIDC_MIGRATION;
REVOKE INSERT ON auth.login FROM SVC_OIDC_MIGRATION;
REVOKE UPDATE ON stop.contact FROM SVC_OIDC_MIGRATION;
REVOKE INSERT ON stop.contact FROM SVC_OIDC_MIGRATION;
REVOKE SELECT ON stop.contact_sync FROM SVC_OIDC_MIGRATION;
REVOKE SELECT ON mss.cost_center FROM SVC_OIDC_MIGRATION;
REVOKE DELETE ON AUTH.LOGIN2TUNNELGROUP FROM SVC_OIDC_MIGRATION;
REVOKE SELECT ON AUTH.LOGINTYPE FROM SVC_OIDC_MIGRATION;
REVOKE SELECT ON AUTH.SEQ_LOGIN_ID FROM SVC_OIDC_MIGRATION;
REVOKE SELECT ON STOP.CONTACT_SEQ FROM SVC_OIDC_MIGRATION;
REVOKE SELECT ON AUTH.SEQ_PROFILE FROM SVC_OIDC_MIGRATION;
REVOKE SELECT ON AUTH.SEQ_USER_PERMISSION FROM SVC_OIDC_MIGRATION;

--changeset alg:1049
--comment DB-1660: introduce local PLOG log table to be used in containers only
CREATE TABLE MCDB_MONITOR.PLOG_OUTPUT(
                 message VARCHAR2(4000),
                 severity VARCHAR2(20),
                 loglevel NUMBER,
                 sender_user VARCHAR(128),
                 sender_session NUMBER,
                 sender_proc VARCHAR(260),
                 log_ts TIMESTAMP DEFAULT SYSDATE
);

--changeset ogl:1050
--comment DB-1718: create db user for mss-service tool
CREATE USER "SVC_MSS_SERVICE" IDENTIFIED BY "xxxxxx" ACCOUNT LOCK
  DEFAULT TABLESPACE "USERS"
  TEMPORARY TABLESPACE "TEMP";

GRANT "MSS_LOGIN_USER" TO "SVC_MSS_SERVICE";

ALTER USER "SVC_MSS_SERVICE" DEFAULT ROLE "MSS_LOGIN_USER";

GRANT EXEMPT ACCESS POLICY TO "SVC_MSS_SERVICE";

GRANT UPDATE ON MSS.SERVICE TO SVC_MSS_SERVICE;

--changeset ogl:1051 contextFilter:dummyPasswords
alter user SVC_MSS_SERVICE identified by "password" account unlock;

--changeset alg:1052
--comment DB-1660: migrate mapping information about cacheablity of value tables to database governed JDOP_PROPERTIES
INSERT INTO APPID."#JDO_PROPERTIES" VALUES ('APP_OPTIMIZATION_PROTOCOL.cacheable','true');
INSERT INTO APPID."#JDO_PROPERTIES" VALUES ('APP_TYPE.cacheable','true');
INSERT INTO APPID."#JDO_PROPERTIES" VALUES ('BANDWIDTH_CONTROL_CLASS.cacheable','true');
INSERT INTO APPID."#JDO_PROPERTIES" VALUES ('OPTIMIZATION_POOL.cacheable','true');
INSERT INTO APPID."#JDO_PROPERTIES" VALUES ('PATH_SELECTION_FAILOVER_TYPE.cacheable','true');
INSERT INTO APPID."#JDO_PROPERTIES" VALUES ('PATH_SELECTION_STICKINESS.cacheable','true');
INSERT INTO AUTH."#JDO_PROPERTIES" VALUES ('AUTHTYPE.cacheable','true');
INSERT INTO AUTH."#JDO_PROPERTIES" VALUES ('CONSENTED_TERM_TYPE.cacheable','true');
INSERT INTO AUTH."#JDO_PROPERTIES" VALUES ('HTML_MAIL_PART_TYPE.cacheable','true');
INSERT INTO AUTH."#JDO_PROPERTIES" VALUES ('LOGINTYPE.cacheable','true');
INSERT INTO AUTH."#JDO_PROPERTIES" VALUES ('PASSWORDTYPE.cacheable','true');
INSERT INTO AUTH."#JDO_PROPERTIES" VALUES ('ROLE.cacheable','true');
INSERT INTO AUTH."#JDO_PROPERTIES" VALUES ('SYNCTYPE.cacheable','true');
INSERT INTO AUTH."#JDO_PROPERTIES" VALUES ('TEMP_ACCESS_TYPE.cacheable','true');
INSERT INTO AUTH."#JDO_PROPERTIES" VALUES ('TOKENFORM.cacheable','true');
INSERT INTO AUTH."#JDO_PROPERTIES" VALUES ('TOKENREPLACEMENTSTATE.cacheable','true');
INSERT INTO AUTH."#JDO_PROPERTIES" VALUES ('TOKENTYPE.cacheable','true');
INSERT INTO AUTH."#JDO_PROPERTIES" VALUES ('USER_ROLE_SCOPE_TYPE.cacheable','true');
INSERT INTO CERTS."#JDO_PROPERTIES" VALUES ('CERTIFICATE_SCOPE_TYPE.cacheable','true');
INSERT INTO CHECKLIST."#JDO_PROPERTIES" VALUES ('CHECKLIST_STATE.cacheable','true');
INSERT INTO FW."#JDO_PROPERTIES" VALUES ('ACTION.cacheable','true');
INSERT INTO FW."#JDO_PROPERTIES" VALUES ('ICMP_TYPE.cacheable','true');
INSERT INTO FW."#JDO_PROPERTIES" VALUES ('ICMPV6_TYPE.cacheable','true');
INSERT INTO FW."#JDO_PROPERTIES" VALUES ('IP_PROTOCOL.cacheable','true');
INSERT INTO FW."#JDO_PROPERTIES" VALUES ('LOG_TARGET.cacheable','true');
INSERT INTO FW."#JDO_PROPERTIES" VALUES ('MEMBER_TYPE.cacheable','true');
INSERT INTO FW."#JDO_PROPERTIES" VALUES ('MEMBER_USAGE.cacheable','true');
INSERT INTO FW."#JDO_PROPERTIES" VALUES ('NAT_ACTION.cacheable','true');
INSERT INTO FW."#JDO_PROPERTIES" VALUES ('NAT_SECTION_TYPE.cacheable','true');
INSERT INTO FW."#JDO_PROPERTIES" VALUES ('SCOPED_IP_GROUP_MEMBER_TYPE.cacheable','true');
INSERT INTO FW."#JDO_PROPERTIES" VALUES ('SUB_SECTION_TYPE.cacheable','true');
INSERT INTO FW."#JDO_PROPERTIES" VALUES ('TCP_FLAG.cacheable','true');
INSERT INTO FYI."#JDO_PROPERTIES" VALUES ('NOTIFICATION_TYPE.cacheable','true');
INSERT INTO FYI."#JDO_PROPERTIES" VALUES ('TOPIC_GROUP.cacheable','true');
INSERT INTO GUMA2."#JDO_PROPERTIES" VALUES ('SENSOR_TYPE.cacheable','true');
INSERT INTO GUMA2."#JDO_PROPERTIES" VALUES ('SYSLOG_FACILITY.cacheable','true');
INSERT INTO GUMA2."#JDO_PROPERTIES" VALUES ('SYSLOG_MESSAGE_TYPE.cacheable','true');
INSERT INTO GUMA2."#JDO_PROPERTIES" VALUES ('SYSLOG_SEVERITY.cacheable','true');
INSERT INTO MAIL."#JDO_PROPERTIES" VALUES ('DMARC_DISPOSITION.cacheable','true');
INSERT INTO MAIL."#JDO_PROPERTIES" VALUES ('DMARC_DKIM_RESULT.cacheable','true');
INSERT INTO MAIL."#JDO_PROPERTIES" VALUES ('DMARC_SPF_RESULT.cacheable','true');
INSERT INTO MAIL."#JDO_PROPERTIES" VALUES ('POLICY_LIST_TAG.cacheable','true');
INSERT INTO MAIL."#JDO_PROPERTIES" VALUES ('POLICY_LIST_TYPE.cacheable','true');
INSERT INTO MAIL."#JDO_PROPERTIES" VALUES ('POLICY_LIST_VALUE_TYPE.cacheable','true');
INSERT INTO MC."#JDO_PROPERTIES" VALUES ('AVAILABILITY_REPORT_STATUS.cacheable','true');
INSERT INTO MC."#JDO_PROPERTIES" VALUES ('CON_INT_TYPE.cacheable','true');
INSERT INTO MC."#JDO_PROPERTIES" VALUES ('CONN_SLA_TARGET.cacheable','true');
INSERT INTO MC."#JDO_PROPERTIES" VALUES ('INTERRUPT_REVIEW_STATUS.cacheable','true');
INSERT INTO MC."#JDO_PROPERTIES" VALUES ('ISP_LINK_STATUS_TYPE.cacheable','true');
INSERT INTO MC."#JDO_PROPERTIES" VALUES ('MAINTENANCE_STATUS.cacheable','true');
INSERT INTO MC."#JDO_PROPERTIES" VALUES ('MC_FILE_TYPE.cacheable','true');
INSERT INTO MCAUDIT."#JDO_PROPERTIES" VALUES ('APPLICATION.cacheable','true');
INSERT INTO MCAUDIT."#JDO_PROPERTIES" VALUES ('COMPONENT.cacheable','true');
INSERT INTO MCAUDIT."#JDO_PROPERTIES" VALUES ('RECORD_TYPE.cacheable','true');
INSERT INTO MCAUDIT."#JDO_PROPERTIES" VALUES ('SEVERITY.cacheable','true');
INSERT INTO MCAUDIT."#JDO_PROPERTIES" VALUES ('SYSTEM.cacheable','true');
INSERT INTO MSS."#JDO_PROPERTIES" VALUES ('CLIENT_PROFILE_TYPE.cacheable','true');
INSERT INTO MSS."#JDO_PROPERTIES" VALUES ('CONFIG_DEPLOYMENT_ERROR.cacheable','true');
INSERT INTO MSS."#JDO_PROPERTIES" VALUES ('CONFIG_DEPLOYMENT_STATUS.cacheable','true');
INSERT INTO MSS."#JDO_PROPERTIES" VALUES ('CONFIG_DEPLOYMENT_USE_CASE.cacheable','true');
INSERT INTO MSS."#JDO_PROPERTIES" VALUES ('CONFIG_LIST_VALUE_TYPE.cacheable','true');
INSERT INTO MSS."#JDO_PROPERTIES" VALUES ('CONTINENT.cacheable','true');
INSERT INTO MSS."#JDO_PROPERTIES" VALUES ('COUNTRY.cacheable','true');
INSERT INTO MSS."#JDO_PROPERTIES" VALUES ('CURRENCY.cacheable','true');
INSERT INTO MSS."#JDO_PROPERTIES" VALUES ('CVPN_GROUP_DNS_TYPE.cacheable','true');
INSERT INTO MSS."#JDO_PROPERTIES" VALUES ('CVPN_GROUP_PROXY_TYPE.cacheable','true');
INSERT INTO MSS."#JDO_PROPERTIES" VALUES ('CVPN_SERVICE_DNS_TYPE.cacheable','true');
INSERT INTO MSS."#JDO_PROPERTIES" VALUES ('CVPN_SERVICE_PROXY_TYPE.cacheable','true');
INSERT INTO MSS."#JDO_PROPERTIES" VALUES ('DECOMM_STATUS.cacheable','true');
INSERT INTO MSS."#JDO_PROPERTIES" VALUES ('DNS_SEARCH_DOMAIN_TYPE.cacheable','true');
INSERT INTO MSS."#JDO_PROPERTIES" VALUES ('DNSSEC_ALGORITHM.cacheable','true');
INSERT INTO MSS."#JDO_PROPERTIES" VALUES ('DNSSEC_KEY_DIGEST_TYPE.cacheable','true');
INSERT INTO MSS."#JDO_PROPERTIES" VALUES ('DNSSEC_KEY_STATE.cacheable','true');
INSERT INTO MSS."#JDO_PROPERTIES" VALUES ('DNSSEC_KEY_TYPE.cacheable','true');
INSERT INTO MSS."#JDO_PROPERTIES" VALUES ('FIELD_MAPPING_TYPE.cacheable','true');
INSERT INTO MSS."#JDO_PROPERTIES" VALUES ('HARDWARE_DEPLOY_REASON.cacheable','true');
INSERT INTO MSS."#JDO_PROPERTIES" VALUES ('HARDWARE_DISPOSAL_REASON.cacheable','true');
INSERT INTO MSS."#JDO_PROPERTIES" VALUES ('HARDWARE_LICENSE_TYPE.cacheable','true');
INSERT INTO MSS."#JDO_PROPERTIES" VALUES ('HARDWARE_LC_LOCATION.cacheable','true');
INSERT INTO MSS."#JDO_PROPERTIES" VALUES ('HARDWARE_LC_STATE.cacheable','true');
INSERT INTO MSS."#JDO_PROPERTIES" VALUES ('HARDWARE_LC_TRANSIT_STATE.cacheable','true');
INSERT INTO MSS."#JDO_PROPERTIES" VALUES ('INTERFACE_RIP_MODE.cacheable','true');
INSERT INTO MSS."#JDO_PROPERTIES" VALUES ('INTERFACE_SPEED.cacheable','true');
INSERT INTO MSS."#JDO_PROPERTIES" VALUES ('ISP_LINK_SOURCING_TYPE.cacheable','true');
INSERT INTO MSS."#JDO_PROPERTIES" VALUES ('ISP_LINK_TRANSPORT_MEDIA.cacheable','true');
INSERT INTO MSS."#JDO_PROPERTIES" VALUES ('KEY.cacheable','true');
INSERT INTO MSS."#JDO_PROPERTIES" VALUES ('KEY_TYPE.cacheable','true');
INSERT INTO MSS."#JDO_PROPERTIES" VALUES ('LOCAL_CONTACT_TYPE.cacheable','true');
INSERT INTO MSS."#JDO_PROPERTIES" VALUES ('NEWS_ENTRY_CATEGORY.cacheable','true');
INSERT INTO MSS."#JDO_PROPERTIES" VALUES ('NEWS_ENTRY_STATUS.cacheable','true');
INSERT INTO MSS."#JDO_PROPERTIES" VALUES ('OPERATING_SYSTEM.cacheable','true');
INSERT INTO MSS."#JDO_PROPERTIES" VALUES ('PERMISSION_GROUP.cacheable','true');
INSERT INTO MSS."#JDO_PROPERTIES" VALUES ('PLATFORM_TYPE.cacheable','true');
INSERT INTO MSS."#JDO_PROPERTIES" VALUES ('PROJECT_ITEM_STATUS.cacheable','true');
INSERT INTO MSS."#JDO_PROPERTIES" VALUES ('NEWS_ENTRY_2_LOGIN_TYPE.cacheable','true');
INSERT INTO MSS."#JDO_PROPERTIES" VALUES ('REPORT_SCHEDULE.cacheable','true');
INSERT INTO MSS."#JDO_PROPERTIES" VALUES ('REPORT_STATE.cacheable','true');
INSERT INTO MSS."#JDO_PROPERTIES" VALUES ('REPORT_TYPE.cacheable','true');
INSERT INTO MSS."#JDO_PROPERTIES" VALUES ('SERVICE_COMPONENT.cacheable','true');
INSERT INTO MSS."#JDO_PROPERTIES" VALUES ('SERVICE_FEATURE_STATE.cacheable','true');
INSERT INTO MSS."#JDO_PROPERTIES" VALUES ('SERVICE_LEVEL.cacheable','true');
INSERT INTO MSS."#JDO_PROPERTIES" VALUES ('SERVICE_OPTION_TYPE.cacheable','true');
INSERT INTO MSS."#JDO_PROPERTIES" VALUES ('SERVICE_TYPE.cacheable','true');
INSERT INTO MSS."#JDO_PROPERTIES" VALUES ('SPLIT_TUNNELING_TYPE.cacheable','true');
INSERT INTO MSS."#JDO_PROPERTIES" VALUES ('TAXCODE.cacheable','true');
INSERT INTO MSS."#JDO_PROPERTIES" VALUES ('UPLOAD_TYPE.cacheable','true');
INSERT INTO NIDS."#JDO_PROPERTIES" VALUES ('DIRECTION.cacheable','true');
INSERT INTO NIDS."#JDO_PROPERTIES" VALUES ('ENTITY_TYPE.cacheable','true');
INSERT INTO NIDS."#JDO_PROPERTIES" VALUES ('FILTER_ACTION.cacheable','true');
INSERT INTO NIDS."#JDO_PROPERTIES" VALUES ('INVESTIGATION_FINDING.cacheable','true');
INSERT INTO NIDS."#JDO_PROPERTIES" VALUES ('INVESTIGATION_STATUS.cacheable','true');
INSERT INTO NIDS."#JDO_PROPERTIES" VALUES ('KS_SCOPE_TYPE.cacheable','true');
INSERT INTO NIDS."#JDO_PROPERTIES" VALUES ('MDR_FILTER_ACTION.cacheable','true');
INSERT INTO NIDS."#JDO_PROPERTIES" VALUES ('MDR_SIG_GROUP_MEMBER_TYPE.cacheable','true');
INSERT INTO NIDS."#JDO_PROPERTIES" VALUES ('NIDS_ENTITY_TYPE.cacheable','true');
INSERT INTO NIDS."#JDO_PROPERTIES" VALUES ('SCOPE_TYPE.cacheable','true');
INSERT INTO NIDS."#JDO_PROPERTIES" VALUES ('SIGNATURE_GROUP_MEMBER_TYPE.cacheable','true');
INSERT INTO NIDS."#JDO_PROPERTIES" VALUES ('SIGNATURE_REFERENCE_TYPE.cacheable','true');
INSERT INTO NIDS."#JDO_PROPERTIES" VALUES ('XDR_TYPE.cacheable','true');
INSERT INTO PRX."#JDO_PROPERTIES" VALUES ('PRX_POLICY_ITEM_TYPE.cacheable','true');
INSERT INTO PRX."#JDO_PROPERTIES" VALUES ('PRX_POLICY_TYPE.cacheable','true');
INSERT INTO REPORT."#JDO_PROPERTIES" VALUES ('CHANNELKEY.cacheable','true');
INSERT INTO RLSDEF."#JDO_PROPERTIES" VALUES ('AREA.cacheable','true');
INSERT INTO RLSDEF."#JDO_PROPERTIES" VALUES ('PREDICATE.cacheable','true');
INSERT INTO STOP."#JDO_PROPERTIES" VALUES ('COMPANY_SECTOR.cacheable','true');
INSERT INTO STOP."#JDO_PROPERTIES" VALUES ('COMPTYPE.cacheable','true');
INSERT INTO STOP."#JDO_PROPERTIES" VALUES ('PARTNER_DOMAIN.cacheable','true');
INSERT INTO STOP."#JDO_PROPERTIES" VALUES ('REACH_ON_TYPE.cacheable','true');
INSERT INTO TIM."#JDO_PROPERTIES" VALUES ('BLACKLIST_VALUE_CATEGORY.cacheable','true');
INSERT INTO TIM."#JDO_PROPERTIES" VALUES ('BLACKLIST_VALUE_TYPE.cacheable','true');
INSERT INTO TIM."#JDO_PROPERTIES" VALUES ('EXCLUSION_LIST_VALUE_TYPE.cacheable','true');
INSERT INTO TT."#JDO_PROPERTIES" VALUES ('CHANGE_REQUEST_STATE.cacheable','true');
INSERT INTO TT."#JDO_PROPERTIES" VALUES ('ESCALATION_STATUS.cacheable','true');
INSERT INTO TT."#JDO_PROPERTIES" VALUES ('EVENT_ACTION.cacheable','true');
INSERT INTO TT."#JDO_PROPERTIES" VALUES ('EVENT_NOTIFICATION_TYPE.cacheable','true');
INSERT INTO TT."#JDO_PROPERTIES" VALUES ('EVENT_SOURCE.cacheable','true');
INSERT INTO TT."#JDO_PROPERTIES" VALUES ('EVENT_TYPE.cacheable','true');
INSERT INTO TT."#JDO_PROPERTIES" VALUES ('EVENT_TYPE_GROUP.cacheable','true');
INSERT INTO TT."#JDO_PROPERTIES" VALUES ('EVENT_TYPE_MESSAGE.cacheable','true');
INSERT INTO TT."#JDO_PROPERTIES" VALUES ('LABEL.cacheable','true');
INSERT INTO TT."#JDO_PROPERTIES" VALUES ('STATUS.cacheable','true');
INSERT INTO TT."#JDO_PROPERTIES" VALUES ('TICKET_TYPE.cacheable','true');
INSERT INTO TT."#JDO_PROPERTIES" VALUES ('TODO_ITEM_STATUS.cacheable','true');
INSERT INTO VPN."#JDO_PROPERTIES" VALUES ('TUNNEL_RATING_INTERVAL.cacheable','true');

--changeset ogl:1053
--comment: container fixup
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM dba_users where USERNAME='SVC_VPN_CONNECTIONS'
delete from lqb.DATABASECHANGELOG where id='1053' and author='mlo' and filename='changelog-1.sql';

--changeset mlo:1053
--comment: MC-25170: New DB user SVC_VPN_CONNECTIONS
CREATE USER "SVC_VPN_CONNECTIONS" IDENTIFIED BY "xxxxxx" ACCOUNT LOCK
    DEFAULT TABLESPACE "USERS"
    TEMPORARY TABLESPACE "TEMP";

GRANT "MSS_LOGIN_USER" TO "SVC_VPN_CONNECTIONS";

ALTER USER "SVC_VPN_CONNECTIONS" DEFAULT ROLE "MSS_LOGIN_USER";

GRANT EXEMPT ACCESS POLICY TO "SVC_VPN_CONNECTIONS";

GRANT SELECT on STOP.COMPANY to SVC_VPN_CONNECTIONS;
GRANT SELECT on MSS.HOST to SVC_VPN_CONNECTIONS;
GRANT SELECT on MSS.HOST2SERVICE to SVC_VPN_CONNECTIONS;
GRANT SELECT on MSS.SERVICE to SVC_VPN_CONNECTIONS;
GRANT SELECT on MSS.INTERFACE to SVC_VPN_CONNECTIONS;
GRANT SELECT on VPN.TUNNEL to SVC_VPN_CONNECTIONS;
GRANT SELECT on VPN.PARTITION to SVC_VPN_CONNECTIONS;
GRANT SELECT on VPN.VPN to SVC_VPN_CONNECTIONS;
GRANT SELECT on VPN.VPN_MEMBER to SVC_VPN_CONNECTIONS;

--changeset alg:1054
--comment DB-1639: fix masterdata containing state too
create table MCDB_CHECKS.CONSISTENCY_CHECK_RUN (
                                                   ID               NUMBER not null
                                                       constraint CONSISTENCY_CHECK_RUN_FK1
                                                           references MCDB_CHECKS.CONSISTENCY_CHECKS
                                                               deferrable initially deferred
                                                       constraint CONSISTENCY_CHECK_RUN_PK primary key,
                                                   CHECK_KEY        VARCHAR2(100),
                                                   LAST_RUN         TIMESTAMP(6)  default SYSDATE,
                                                   LAST_RESULT_HASH RAW(20)
);

merge into MCDB_CHECKS.CONSISTENCY_CHECK_RUN chkrun using
    ( select ID, CHECK_KEY, LAST_RUN, LAST_RESULT_HASH FROM MCDB_CHECKS.CONSISTENCY_CHECKS ) chkdef
on (chkdef.ID = chkrun.ID)
when not matched then insert (id, check_key, last_run, last_result_hash)
                      VALUES (chkdef.ID, chkdef.CHECK_KEY, chkdef.LAST_RUN, chkdef.LAST_RESULT_HASH);


--changeset alg:1055
--comment DB-1639: fix masterdata containing state too - cleanup part
alter table MCDB_CHECKS.CONSISTENCY_CHECKS DROP ( LAST_RUN, LAST_RESULT_HASH);

--changeset phm:1056
--validCheckSum: 8:0cd7f3c9d4f751dd0ab08de3f09cf43d
--comment CONF-3326: add mss.service.platform-deployment-enabled, all existing should be true
alter table mss.service add (platform_deployment_enabled NUMBER(1) null);
update mss.service set platform_deployment_enabled=1 where platform_type_id=2;

--changeset phm:1057
--comment CONF-3326: make platform_deployment_enabled NOT NULL
update mss.service set platform_deployment_enabled=1 where platform_type_id in (1,2,3);
alter table mss.service modify platform_deployment_enabled NUMBER(1) default 0 not null;

--changeset lag:1058
--comment: DNS-374: Add new DB Prop 'migrate.forwarderzones'
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (56710, 'migrate.forwarderzones', 1, '0', '^[01]$', NULL, 'Enable migration of named.caching.forwarderzones and named.caching.forward_insecure from dbprop to vault');

--changeset gip:1059
--comment MX-3902: Create new dbprops for Admin Quarantine Tag and Relay
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (56711, 'mail.admin_quarantine_tag', 1, '0', '^[01]$', NULL, 'Enable Admin Quarantine tag and relay feature');

insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (56712, 'mail.admin_quarantine_tag.header_match', 4, 'X-MC-Admin-Quarantine', '^[A-Za-z0-9_-]+$', NULL, 'Admin Quarantine tag and relay header to indicate match');

insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (56713, 'mail.admin_quarantine_tag.header_reason', 4, 'X-MC-Admin-Quarantine-Reason', '^[A-Za-z0-9_-]+$', NULL, 'Admin Quarantine tag and relay header for match reason');

insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (56714, 'mail.admin_quarantine_tag.next_hop', 4, NULL, '^([0-9]|[1-9]\d|1\d\d|2[0-4]\d|25[0-5])\.([0-9]|[1-9]\d|1\d\d|2[0-4]\d|25[0-5])\.([0-9]|[1-9]\d|1\d\d|2[0-4]\d|25[0-5])\.([0-9]|[1-9]\d|1\d\d|2[0-4]\d|25[0-5])(\:[0-9]+)?$', NULL, 'Next hop IP address for Admin Quarantine tag and relay');

insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (56715, 'migrate.mail.quarantine.tag_relay', 2, '0', '^[012]$', NULL, 'Migration to new Admin Quarantine tag and relay feature');

insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (56716, 'migrate.mail.quarantine.tag_relay.date', 4, '0', '^[0-9]{10}$', NULL, 'Migration to new Admin Quarantine tag and relay feature - migration date timestamp');

--changeset ogl:1060
--comment: DB-1747 Slow delete from GUMA2.SIGNATURE
create index PATTERN_FK1 on guma2.pattern(signature_id) compute statistics;

--changeset nop:1061
--comment: SRE-364: New DB user SVC_SRE_METRICS_CFG
CREATE USER "SVC_SRE_METRICS_CFG" IDENTIFIED BY "xxxxxx" ACCOUNT LOCK
    DEFAULT TABLESPACE "USERS"
    TEMPORARY TABLESPACE "TEMP";

GRANT "MSS_LOGIN_USER" TO "SVC_SRE_METRICS_CFG";

ALTER USER "SVC_SRE_METRICS_CFG" DEFAULT ROLE "MSS_LOGIN_USER";

GRANT EXEMPT ACCESS POLICY TO "SVC_SRE_METRICS_CFG";

GRANT SELECT on MSS.HOST to SVC_SRE_METRICS_CFG;
GRANT SELECT on MSS.HOST2SERVICE to SVC_SRE_METRICS_CFG;
GRANT SELECT on MSS.INTERFACE to SVC_SRE_METRICS_CFG;
GRANT SELECT on MSS.SERVICE to SVC_SRE_METRICS_CFG;
GRANT SELECT on STOP.COMPANY to SVC_SRE_METRICS_CFG;
GRANT SELECT on VPN.PARTITION to SVC_SRE_METRICS_CFG;
GRANT SELECT on VPN.TUNNEL to SVC_SRE_METRICS_CFG;
GRANT SELECT on VPN.VPN to SVC_SRE_METRICS_CFG;
GRANT SELECT on VPN.VPN_MEMBER to SVC_SRE_METRICS_CFG;

--changeset ogl:1062 contextFilter:dummyPasswords
ALTER USER SVC_VPN_CONNECTIONS identified by "password" account unlock;
ALTER USER SVC_SRE_METRICS_CFG identified by "password" account unlock;

--changeset nop:1063
--comment: SRE-364: Add missing grants
GRANT SELECT on MSS.HARDWARE to SVC_SRE_METRICS_CFG;
GRANT SELECT on MSS.HARDWARE_TYPE to SVC_SRE_METRICS_CFG;
GRANT SELECT on MSS.SERVICE_TYPE to SVC_SRE_METRICS_CFG;

--changeset phm:1064
--comment: CONF-3250: rename db user from SVC_MSS_SERVICE to SVC_SERVICE_CONFIG
CREATE USER "SVC_SERVICE_CONFIG" IDENTIFIED BY "xxxxxx" ACCOUNT LOCK
    DEFAULT TABLESPACE "USERS"
    TEMPORARY TABLESPACE "TEMP";

GRANT "MSS_LOGIN_USER" TO "SVC_SERVICE_CONFIG";

ALTER USER "SVC_SERVICE_CONFIG" DEFAULT ROLE "MSS_LOGIN_USER";

GRANT EXEMPT ACCESS POLICY TO "SVC_SERVICE_CONFIG";

GRANT UPDATE ON MSS.SERVICE TO SVC_SERVICE_CONFIG;

--changeset phm:1065
--comment: CONF-3250: rename db user from SVC_MSS_SERVICE to SVC_SERVICE_CONFIG
DROP USER SVC_MSS_SERVICE;

--changeset ogl:1066 contextFilter:dummyPasswords
alter user SVC_SERVICE_CONFIG identified by "password" account unlock;

--changeset nop:1067
--comment: SRE-364: Add missing grants
GRANT SELECT ON MSS.VALUE to SVC_SRE_METRICS_CFG;

--changeset phm:1068
--comment: MON-3508: more permissions for alert-hander as ticketing api does not provide everything required yet
GRANT SELECT ON TT.HOST2SERVICE_WINDOW TO SVC_ALERTHANDLER;
GRANT SELECT ON TT.SERVICE_WINDOW TO SVC_ALERTHANDLER;
GRANT SELECT ON TT.MAINTENANCE_WINDOW TO SVC_ALERTHANDLER;
GRANT SELECT ON TT.TICKET TO SVC_ALERTHANDLER;

--changeset nom:1069
--comment: OSDP-1190: Create two new OSSE dbprops
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (56720, 'osse.baseversion', 4, NULL, '^[A-Za-z0-9-.]+$', NULL, 'Set the base helm chart version of the OSSE service.');

insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (56721, 'osse.serviceversion', 4, NULL, '^[A-Za-z0-9-.]+$', NULL, 'Set the service helm chart version of the OSSE service.');

--changeset nkj:1070
--comment: MC-25460: Change 'migrate.zitadel' dbprop to be 0/1/2/3 instead of 0/1/2
update mss.key k
set k.REGEXP='^[0123]$'
where k.id=56701
  and k.name='migrate.zitadel';

--changeset gip:1071
--comment: MX-3997: change the default of mail.antispam.action.quarantine
update MSS.key k
set k.STRING_DEFAULT='0'
where k.id=22341 and k.name='mail.antispam.action.quarantine';

--changeset rse:1072
--comment: Additional GRANTS for user "mcmgw" to determine host by ISP line number
GRANT SELECT ON MSS.ISP_LINK TO MCMGW;
GRANT SELECT ON MSS.INTERFACE2ISP_LINK TO MCMGW;
GRANT SELECT ON MSS.INTERFACE TO MCMGW;
GRANT SELECT ON MSS.HOST TO MCMGW;

--changeset rse:1073
--comment: Introduce new dbprops for NTP and chrony
INSERT INTO MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
VALUES (56730, 'ntp.chrony', 1, '0', '^[01]$', NULL, 'Enable chrony instead of ntpd as NTP client and server');

INSERT INTO MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
VALUES (56731, 'ntp.nts', 1, '0', '^[01]$', NULL, 'Enable Network Time Security (RFC 8915)');

INSERT INTO MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
VALUES (56732, 'mgmtserver.ntp', 1, '0', '^[01]$', NULL, 'management host with NTP server functionality');

--changeset nbo:1074 endDelimiter:/
--comment: MC-25456: remove obsolete auth.mc_settings table
BEGIN
    DBMS_RLS.DROP_POLICY('AUTH', 'MC_SETTINGS', 'MC_SETTINGS_RF');
    DBMS_RLS.DROP_POLICY('AUTH', 'MC_SETTINGS', 'MC_SETTINGS_WF');
END;
/

--changeset nbo:1075
--comment: MC-25456: remove obsolete auth.mc_settings table
REVOKE ALL ON AUTH.MCSETTINGS_SEQ FROM AUTHSYNC;
REVOKE ALL ON AUTH.MCSETTINGS_SEQ FROM MCA;
REVOKE ALL ON AUTH.MCSETTINGS_SEQ FROM WEBRLS;

DELETE FROM RLSDEF.PREDICATE WHERE TABLE_NAME = 'MC_SETTINGS';

DELETE FROM AUTH."#JDO_PROPERTIES" WHERE KEY = 'LOGIN.naming.inverse.AUTH.FK_MC_SETTINGS_LOGIN_ID';
DELETE FROM AUTH."#JDO_PROPERTIES" WHERE KEY = 'MC_SETTINGS.seq.for.pk.ID';

REVOKE ALL ON AUTH.MC_SETTINGS FROM SVC_OIDC_MIGRATION;
REVOKE ALL ON AUTH.MC_SETTINGS FROM MCA;
REVOKE ALL ON AUTH.MC_SETTINGS FROM BIREADER;
REVOKE ALL ON AUTH.MC_SETTINGS FROM AUTHSYNC;
REVOKE ALL ON AUTH.MC_SETTINGS FROM WEBRLS;

DROP TABLE auth.mc_settings CASCADE CONSTRAINTS;

DROP SEQUENCE AUTH.MCSETTINGS_SEQ;

--changeset nop:1076
--comment: SRE-394: Add grants to look for interface address and firewall zone
GRANT SELECT on MSS.ADDRESS to SVC_SRE_METRICS_CFG;
GRANT SELECT on MSS.CITY to SVC_SRE_METRICS_CFG;
GRANT SELECT on MSS.COUNTRY to SVC_SRE_METRICS_CFG;
GRANT SELECT on FW.ZONE to SVC_SRE_METRICS_CFG;
GRANT SELECT on FW.ZONE_MEMBER to SVC_SRE_METRICS_CFG;


--changeset mlo:1077
--comment: MC-25482: Add OIDC_UPN field
ALTER TABLE AUTH.LOGIN ADD (OIDC_UPN VARCHAR2(250) NULL);
ALTER TABLE AUTH.LOGIN ADD CONSTRAINT IDX_OIDC_UPN UNIQUE(OIDC_UPN);
CREATE UNIQUE INDEX AUTH.IDX_OIDC_UPN2 ON AUTH.LOGIN (LOWER(OIDC_UPN));


--changeset ogl:1078
--comment: DB-1759 new user for XDR rule export
CREATE USER "SVC_XDRCONVERT" IDENTIFIED BY "xxxxxx" ACCOUNT LOCK
  DEFAULT TABLESPACE "USERS"
  TEMPORARY TABLESPACE "TEMP";

GRANT "MSS_LOGIN_USER" TO "SVC_XDRCONVERT";

ALTER USER "SVC_XDRCONVERT" DEFAULT ROLE "MSS_LOGIN_USER";

GRANT EXEMPT ACCESS POLICY TO "SVC_XDRCONVERT";

--changeset ogl:1079 contextFilter:dummyPasswords
alter user SVC_XDRCONVERT identified by "password" account unlock;

--changeset ogl:1080
--comment: DB-1759 new user for XDR rule export
GRANT SELECT ON NIDS.NIDS_ENTITY TO SVC_XDRCONVERT;
GRANT SELECT ON NIDS.NIDS_IP_ADDRESS TO SVC_XDRCONVERT;
GRANT SELECT ON NIDS.NIDS_IP_NETWORK TO SVC_XDRCONVERT;
GRANT SELECT ON NIDS.NIDS_DEVICE TO SVC_XDRCONVERT;
GRANT SELECT ON NIDS.NIDS_USER TO SVC_XDRCONVERT;
GRANT SELECT ON NIDS.NIDS_IPV6_ADDRESS TO SVC_XDRCONVERT;
GRANT SELECT ON NIDS.NIDS_IPV6_PREFIX TO SVC_XDRCONVERT;
GRANT SELECT ON NIDS.NIDS_FILE TO SVC_XDRCONVERT;
GRANT SELECT ON NIDS.MDR_FILTER_RULE TO SVC_XDRCONVERT;
GRANT SELECT ON NIDS.MDR_SIGNATURE_GROUP TO SVC_XDRCONVERT;
GRANT SELECT ON NIDS.MDR_SIGNATURE_GROUP_MEMBER TO SVC_XDRCONVERT;
GRANT SELECT ON NIDS.MDR_SIGNATURE TO SVC_XDRCONVERT;
GRANT SELECT ON MCAUDIT.RECORD TO SVC_XDRCONVERT;
GRANT SELECT ON STOP.COMPANY TO SVC_XDRCONVERT;

--changeset nom:1081
--comment: OSDP-1206: Create two new OSSE dbprops
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (56740, 'osse.proxy.chartversion', 4, NULL, '^[A-Za-z0-9-.]+$', NULL, 'Set the proxy helm chart version of the OSSE service.');

insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (56741, 'osse.ztna.chartversion', 4, NULL, '^[A-Za-z0-9-.]+$', NULL, 'Set the ztna helm chart version of the OSSE service.');

--changeset phm:1082
--comment: DB-1763: Permission changes for svc_alerthandler opening tickets via DB procedures API
GRANT EXECUTE ON TT.EVENT_INTERFACE TO SVC_ALERTHANDLER;
GRANT EXECUTE ON TT.TICKET_INTERFACE TO SVC_ALERTHANDLER;

--changeset phm:1083
--comment: CONF-3354: dbprop regexp update osse.baseversion to accept branch names feature/CONF-XXXX
UPDATE MSS.KEY SET MSS.KEY.REGEXP='^[A-Za-z0-9-.\/]+$' WHERE MSS.KEY.ID = 56720;

--changeset nop:1084
--comment: Migration dbprop to enable linkmon -> thanos metrics
INSERT INTO MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
VALUES (56742, 'migrate.custom_exporter.linkmon', 1, '0', '^[01]$', NULL, 'Enable linkmon metric scaping by custom exporter');

--changeset sym:1085
--comment: OSDP-1214: Allow the osse version dbprops to have branch names with slashes
UPDATE MSS.KEY SET MSS.KEY.REGEXP='^[A-Za-z0-9-.\/]+$' WHERE MSS.KEY.ID = 56740;
UPDATE MSS.KEY SET MSS.KEY.REGEXP='^[A-Za-z0-9-.\/]+$' WHERE MSS.KEY.ID = 56741;

--changeset nop:1086
--comment: Emergency turn-off for custom prometheus exporter
INSERT INTO MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
VALUES (56743, 'migrate.custom_exporter.emergency_turnoff', 1, '0', '^[01]$', NULL, 'Set to 1 for an emergency turn-off of the custom exporter if it leads to trouble');

--changeset nop:1069
--comment: SRE-346: SANG to ticket decomissioning
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (56744, 'migrate.sang.turnoff_ticket_events', '1', '0', '^[01]$', NULL, 'Decommission SANG alerts to MC, in favor of the alert-handler');

--changeset nis:1087
--comment: Allows ticketing service user to access MSS.HOST2SERVICE
GRANT SELECT ON MSS.HOST2SERVICE TO SVC_API_TICKETING;

--changeset ysh:1089
--comment: SRE-366: Create node-exporter CBLX module
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
VALUES (56745, 'migrate.node_exporter.emergency_turnoff', '1', '0', '^[01]$', NULL, 'Set to 1 for an emergency turn-off of the node exporter if it leads to trouble');

--changeset nop:1090
--comment: SRE-410 Allows metrics cfg service account to access ISP, FW tables and DBProp view
GRANT SELECT on MSS.INTERFACE2ISP_LINK to SVC_SRE_METRICS_CFG;
GRANT SELECT on MSS.ISP_LINK to SVC_SRE_METRICS_CFG;
GRANT SELECT on FW.SECTION to SVC_SRE_METRICS_CFG;
GRANT SELECT on FW.POLICY to SVC_SRE_METRICS_CFG;
GRANT SELECT on MSS.V_HOST_KEY_VALUE to SVC_SRE_METRICS_CFG;

--changeset nop:1091
--comment: SRE-410 Add a dbprop for the progressive rollout of connectivity alerts
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (56746, 'migrate.progressive_rollout.connectivity_alerts_1', '1', '0', '^[01]$', NULL, 'Decommission SANG alerts to MC, in favor of the alert-handler');

--changeset sym:1092
--comment: OSDP-1216 Delete deprecated dbprop
delete from mss.VALUE v where v.key_id = 56721;
delete from mss.key where id = 56721;

--changeset nop:1093
--comment: SRE-346: Decomission SANG (allow linkmon to fetch dbprops for silencing)
GRANT SELECT ON MSS.V_HOST_KEY_VALUE TO LINKMON;

--changeset mgr:1094
--comment: MX-4071: Make markexternal subject tag string configurable
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (56747, 'mail.markexternal.tag_subject.value', 4, '[EXTERNAL]', '^[A-Za-z0-9_\[\]{}()|: -]+$', NULL, 'Tag the subject of external emails');

--changeset alg:1095
--comment: DB-1754 add retry to timeout prone external commands in domainsync
alter table AUTH.SYNCDOMAIN
    add (
        MAX_ATTEMPT   INTEGER DEFAULT 3,
        RUN_ATTEMPT   INTEGER DEFAULT 0,
        LAST_RESULTCODE    INTEGER default 0,
        LAST_RESULTMSG     VARCHAR2(4000)
        );

comment on column AUTH.SYNCDOMAIN.MAX_ATTEMPT is 'Max number of automatic retries after failure';
comment on column AUTH.SYNCDOMAIN.RUN_ATTEMPT is 'Number of retries done after failure';
comment on column AUTH.SYNCDOMAIN.LAST_RESULTCODE is 'SQLCODE of last failure';
comment on column AUTH.SYNCDOMAIN.LAST_RESULTMSG is 'SQLERRM of last failure';

--changeset rse:1095
--comment: MON-3665: Add boolean dbprops fw.log.loki and fw.log.debug.loki for fw log forwarding to Loki
INSERT INTO MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
VALUES (56750, 'fw.log.loki', 1, '0', '^[01]$', NULL, 'Enable firewall log forwarding to Loki');
INSERT INTO MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
VALUES (56752, 'fw.log.input.loki', 1, '0', '^[01]$', NULL, 'Enable firewall input log forwarding to Loki');
INSERT INTO MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
VALUES (56751, 'fw.log.debug.loki', 1, '0', '^[01]$', NULL, 'Enable firewall debug log forwarding to Loki');

--changeset alg:1100 tag:v1.0.3
--comment: Base of new container
SELECT 1 FROM DUAL;

--changeset aba:1101
--comment: OSDP-1257: decommission osse.baseversion, osse.proxy.chartversion and osse.ztna.chartversion dbprops
delete from mss.VALUE v where v.key_id in (56720,56740,56741);
delete from mss.key where id in (56720,56740,56741);

--changeset jwj:1102
--comment: WAF-2556: Delete WAF/IAM related dbprops
delete from mss.value v
where v.KEY_ID in (select ID from mss.KEY
                   where NAME in ('airlock','airlock.antimalware','airlock.cloud.listener.interface','airlock.clustersync.interface','airlock.loghost','airlock.loghost.logtypes','airlock.self-provisioning','airlock.soapfilter','airlock.soapfilter.version','airlock.sslvpn','airlock.sslvpn.version','airlock.sst','airlock.sst.version','airlock.version','airlock.xmlfilter','airlock.xmlfilter.version','beats.waf.requestlog','medusa','medusa.adminapp','medusa.instance.version','medusa.loghost','medusa.loginapp','medusa.servicecontainerapp','medusa.webserver.http','medusa.webserver.https','medusa.webserver.keystore.password','medusa.webserver.listeninterface','medusa.webserver.version','mgmtserver.airlock','mgmtserver.airlock.company'));
delete from mss.key
where NAME in ('airlock','airlock.antimalware','airlock.cloud.listener.interface','airlock.clustersync.interface','airlock.loghost','airlock.loghost.logtypes','airlock.self-provisioning','airlock.soapfilter','airlock.soapfilter.version','airlock.sslvpn','airlock.sslvpn.version','airlock.sst','airlock.sst.version','airlock.version','airlock.xmlfilter','airlock.xmlfilter.version','beats.waf.requestlog','medusa','medusa.adminapp','medusa.instance.version','medusa.loghost','medusa.loginapp','medusa.servicecontainerapp','medusa.webserver.http','medusa.webserver.https','medusa.webserver.keystore.password','medusa.webserver.listeninterface','medusa.webserver.version','mgmtserver.airlock','mgmtserver.airlock.company');

--changeset fis:1103
--comment: MX-4114: Add new DB Prop mail.admin_email to replace pmx.admin_email
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (56753, 'mail.admin_email', 4, 'postmaster@open.ch', '.*', null, 'Email address used for SEG notifications / digests');

--changeset jmj:1104
--comment: OSIX-5854: add new dbprop relmgmt.alpha for hosts to access not-yet-in-patch packages
INSERT INTO MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
VALUES (21705, 'relmgmt.alpha', 1, '0', '^[01]$', 22, 'host can use alpha package repositories');

--changeset alg:1105 tag:v1.0.4
--comment: Base of new container
SELECT 1 FROM DUAL;



--changeset ogl:1106
--comment: check for UNUSABLE indexes
insert into MCDB_CHECKS.CONSISTENCY_CHECKS
(ID, CHECK_KEY, CHECK_GROUP, STATEMENT, MESSAGE, PLOGLEVEL, SLOGLEVEL)
values
  (76, 'SEL_invalid_idx', 'critical', 'select owner, index_name from DBA_INDEXES where status != ''VALID'' and owner not in (''SYS'', ''SYSTEM'', ''AUDSYS'')',
   'There are unusable indexes in the database. They need to be rebuilt.', 4, 'WARNING');

--changeset ogl:1107
--comment: drop unused sequence. Masterdata IDs are managed manually.
drop sequence MCDB_CHECKS.CONSISTENCY_CHECKS_SEQ;

--changeset phm:1108
--comment: CONF-3390: add cloud_region_instance access to mssquery/gethosts
GRANT SELECT ON MSS.CLOUD_REGION_INSTANCE TO GETNODES;

--changeset ogl:1109
--comment DB-1783: add service user for Conifer
CREATE USER "SVC_CONIFER" IDENTIFIED BY "xxxxxx" ACCOUNT LOCK
  DEFAULT TABLESPACE "USERS"
  TEMPORARY TABLESPACE "TEMP";

--changeset ogl:1110 contextFilter:dummyPasswords
ALTER USER "SVC_CONIFER" IDENTIFIED BY "password" ACCOUNT UNLOCK;

--changeset ogl:1111
--comment DB-1783: add service user for Conifer
GRANT "MSS_LOGIN_USER" TO "SVC_CONIFER";
ALTER USER "SVC_CONIFER" DEFAULT ROLE "MSS_LOGIN_USER";
GRANT EXEMPT ACCESS POLICY TO "SVC_CONIFER";
GRANT SELECT ON stop.COMPANY TO "SVC_CONIFER";
GRANT SELECT ON stop.COMP_COMPTYPE_REF TO "SVC_CONIFER";
GRANT EXECUTE ON mss.OSAG_IP TO "SVC_CONIFER";
GRANT SELECT ON mss.HARDWARE TO "SVC_CONIFER";
GRANT SELECT ON mss.HOST TO "SVC_CONIFER";
GRANT SELECT ON mss.HOST2SERVICE TO "SVC_CONIFER";
GRANT SELECT ON mss.SERVICE TO "SVC_CONIFER";
GRANT SELECT ON mss.SERVICE_COMPONENT TO "SVC_CONIFER";
GRANT SELECT ON mss.SERVICE_COMPONENT2SERVICE TO "SVC_CONIFER";
GRANT SELECT ON mss.SERVICE_TYPE TO "SVC_CONIFER";
GRANT SELECT ON mss.SERVICE_OPTION_TYPE TO "SVC_CONIFER";
GRANT SELECT ON mss.STATIC_ROUTE TO "SVC_CONIFER";
GRANT SELECT ON mss.INTERFACE TO "SVC_CONIFER";
GRANT SELECT ON mss.NETWORK TO "SVC_CONIFER";
GRANT SELECT ON mss.ISP_LINK TO "SVC_CONIFER";
GRANT SELECT ON mss.INTERFACE2ISP_LINK TO "SVC_CONIFER";

--changeset nop:1112
--comment: SRE-421: Add CONNECTION_INTERRUPT_CLOSED_SRE table

-- MC.CONNECTION_INTERRUPT_CLOSED definition
CREATE TABLE "MC"."CONNECTION_INTERRUPT_CLOSED_SRE" 
   (	"ID" NUMBER(22,0) NOT NULL ENABLE, 
	"HOST_ID" NUMBER(10,0) NOT NULL ENABLE, 
	"TYPE_ID" NUMBER(22,0), 
	"DOWN_DATE" DATE, 
	"UP_DATE" DATE, 
	"MINUTES" NUMBER(22,0), 
	"ACTIVE" NUMBER(1,0) DEFAULT 1 NOT NULL ENABLE, 
	"EVENT_ID" NUMBER(22,0), 
	"DETAILS" VARCHAR2(2000), 
	"INTERRUPT_REVIEW_STATUS_ID" NUMBER(10,0), 
	 CONSTRAINT "CONNECTIONINTERRUPTCLOSEDSRE_PK" PRIMARY KEY ("ID"),
   CONSTRAINT "FK_CI_CLOSED_SRE_HOST_ID" FOREIGN KEY ("HOST_ID") REFERENCES "MSS"."HOST" ("ID"),
   CONSTRAINT "FK_CI_CLOSED_SRE_REVIEW_STATUS_ID" FOREIGN KEY ("INTERRUPT_REVIEW_STATUS_ID")
	  REFERENCES "MC"."INTERRUPT_REVIEW_STATUS" ("ID"),
    CONSTRAINT "FK_CI_CLOSED_SRE_TYPE_ID" FOREIGN KEY ("TYPE_ID")
	  REFERENCES "MC"."CON_INT_TYPE" ("ID")
  );

CREATE INDEX "MC"."IDX_CI_CLOSED_SRE_HOST_ID" ON "MC"."CONNECTION_INTERRUPT_CLOSED_SRE" ("HOST_ID");


--changeset nop:1113
--comment: SRE-421: Add CONNECTION_INTERRUPT_OPEN_SRE table

-- MC.CONNECTION_INTERRUPT_OPEN definition
CREATE TABLE "MC"."CONNECTION_INTERRUPT_OPEN_SRE" 
   (	"ID" NUMBER(22,0) NOT NULL ENABLE, 
	"HOST_ID" NUMBER(10,0) NOT NULL ENABLE, 
	"TYPE_ID" NUMBER(22,0), 
	"DOWN_DATE" DATE, 
	"UP_DATE" DATE, 
	"MINUTES" NUMBER(22,0), 
	"ACTIVE" NUMBER(1,0) DEFAULT 1 NOT NULL ENABLE, 
	"EVENT_ID" NUMBER(22,0), 
	"ISP_ESCALATED" NUMBER(1,0) DEFAULT 0 NOT NULL ENABLE, 
	"DETAILS" VARCHAR2(2000), 
	"INTERRUPT_REVIEW_STATUS_ID" NUMBER(10,0), 
	 CONSTRAINT "CONNECTIONINTERRUPTOPENSRE_PK" PRIMARY KEY ("ID"),
   CONSTRAINT "FK_CI_OPEN_SRE_EVENT_ID" FOREIGN KEY ("EVENT_ID") REFERENCES "TT"."EVENT" ("ID"),
   CONSTRAINT "FK_CI_OPEN_SRE_HOST_ID" FOREIGN KEY ("HOST_ID") REFERENCES "MSS"."HOST" ("ID"),
   CONSTRAINT "FK_CI_OPEN_SRE_TYPE_ID" FOREIGN KEY ("TYPE_ID") REFERENCES "MC"."CON_INT_TYPE" ("ID")
  ) ;

CREATE INDEX "MC"."IDX_CI_OPEN_SRE_HOST_ID" ON "MC"."CONNECTION_INTERRUPT_OPEN_SRE" ("HOST_ID") ;
ALTER TABLE "MC"."CONNECTION_INTERRUPT_OPEN_SRE" ADD CONSTRAINT "U_CI_OPEN_SRE_HOST_ID" UNIQUE ("HOST_ID") USING INDEX "MC"."IDX_CI_OPEN_SRE_HOST_ID" ;


COMMENT ON TABLE MC.CONNECTION_INTERRUPT_OPEN_SRE IS 'If there is some outage, ISP outage or connection down, there will be an entry in this table.
The entry is removed when the outage is over, and replaced when the type of the outage changes.
I.e. this table reflects the current connection status of a host.';


--changeset nop:1114
--comment: SRE-421: Add ISP_LINK_HISTORY_SRE table

-- MC.ISP_LINK_HISTORY definition
CREATE TABLE "MC"."ISP_LINK_HISTORY_SRE" 
   (	"ID" NUMBER(22,0) NOT NULL ENABLE, 
	"ISP_LINK_ID" NUMBER(10,0) NOT NULL ENABLE, 
	"REPORTING_HOST_ID" NUMBER(10,0), 
	"OLD_ISP_LINK_STATUS_TYPE_ID" NUMBER(10,0) NOT NULL ENABLE, 
	"NEW_ISP_LINK_STATUS_TYPE_ID" NUMBER(10,0) NOT NULL ENABLE, 
	"CHANGE_DATE" DATE NOT NULL ENABLE, 
	"EVENT_ID" NUMBER(22,0), 
	 CONSTRAINT "ISPLINKHISTORYSRE_PK" PRIMARY KEY ("ID"),
   CONSTRAINT "FK_ISP_LINK_SRE_EVENT_ID" FOREIGN KEY ("EVENT_ID")
	  REFERENCES "TT"."EVENT" ("ID"),
    CONSTRAINT "FK_ISP_LINK_SRE_HISTORY_HOST_ID" FOREIGN KEY ("REPORTING_HOST_ID")
	  REFERENCES "MSS"."HOST" ("ID"),
    CONSTRAINT "FK_ISP_LINK_SRE_HISTORY_LINK_ID" FOREIGN KEY ("ISP_LINK_ID")
	  REFERENCES "MSS"."ISP_LINK" ("ID") ON DELETE CASCADE,
    CONSTRAINT "FK_ISP_LINK_SRE_STATUS_TYPE_ID_NEW" FOREIGN KEY ("NEW_ISP_LINK_STATUS_TYPE_ID")
	  REFERENCES "MC"."ISP_LINK_STATUS_TYPE" ("ID") ,
    CONSTRAINT "FK_ISP_LINK_SRE_STATUS_TYPE_ID_OLD" FOREIGN KEY ("OLD_ISP_LINK_STATUS_TYPE_ID")
	  REFERENCES "MC"."ISP_LINK_STATUS_TYPE" ("ID")
   );

CREATE INDEX "MC"."IDX_ISP_LINK_SRE_EVENT_ID" ON "MC"."ISP_LINK_HISTORY_SRE" ("EVENT_ID");
CREATE INDEX "MC"."IDX_ISP_LINK_SRE_HISTORY_DATE" ON "MC"."ISP_LINK_HISTORY_SRE" ("CHANGE_DATE");
CREATE INDEX "MC"."IDX_ISP_LINK_SRE_HISTORY_ID" ON "MC"."ISP_LINK_HISTORY_SRE" ("ISP_LINK_ID");



--changeset nop:1115
--comment: SRE-421: Add MON_SERVER_CONNECTION_SRE table

-- MC.MON_SERVER_CONNECTION definition
CREATE TABLE "MC"."MON_SERVER_CONNECTION_SRE" 
   (	"HOST_ID" NUMBER(10,0) NOT NULL ENABLE, 
	"MON_SERVER_ID" NUMBER(10,0) NOT NULL ENABLE, 
	"CON_TIMESTAMP" NUMBER(10,0), 
	"DELAY" NUMBER(9,0), 
	"DETAILS" VARCHAR2(2024), 
	"ENTRY_DATE" TIMESTAMP (6) WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL ENABLE, 
	"STATUS" NUMBER(22,0), 
	"IPV4_ADDRESS" NUMBER(10,0), 
	"IPV6_ADDRESS_1" NUMBER(20,0), 
	"IPV6_ADDRESS_2" NUMBER(20,0), 
	 CONSTRAINT "MONSERVERCONNECTIONSRE_PK" PRIMARY KEY ("HOST_ID", "MON_SERVER_ID"),
   CONSTRAINT "FK_MSC_SRE_HOST_ID" FOREIGN KEY ("HOST_ID")
	  REFERENCES "MSS"."HOST" ("ID") ON DELETE CASCADE,
    CONSTRAINT "FK_MSC_SRE_MON_SERVER_ID" FOREIGN KEY ("MON_SERVER_ID")
	  REFERENCES "MSS"."HOST" ("ID") ON DELETE CASCADE,
    CONSTRAINT "FK_MSC_SRE_STATUS" FOREIGN KEY ("STATUS")
	  REFERENCES "MC"."CON_INT_TYPE" ("ID")
 
   )  ;

COMMENT ON COLUMN MC.MON_SERVER_CONNECTION_SRE.IPV6_ADDRESS_1 IS 'The most significant 64 bits of the IPv6 address.';
COMMENT ON COLUMN MC.MON_SERVER_CONNECTION_SRE.IPV6_ADDRESS_2 IS 'The least significant 64 bits of the IPv6 address.';


--changeset nop:1116
--comment: SRE-421: Add HOST_CONNECTION_STATUS_SRE table

-- MC.HOST_CONNECTION_STATUS definition
CREATE TABLE "MC"."HOST_CONNECTION_STATUS_SRE" 
   (	"HOST_ID" NUMBER(10,0) NOT NULL ENABLE, 
	"CON_TIMESTAMP" NUMBER(10,0) NOT NULL ENABLE, 
	"DETAILS" VARCHAR2(2024), 
	"CON_INT_TYPE_ID" NUMBER(10,0), 
	 CONSTRAINT "HOSTCONNECTIONSTATUSSRE_PK" PRIMARY KEY ("HOST_ID"),
   CONSTRAINT "FK_HCS_SRE_HOST_ID" FOREIGN KEY ("HOST_ID")
	  REFERENCES "MSS"."HOST" ("ID") ON DELETE CASCADE,
    CONSTRAINT "FK_HCS_SRE_INT_TYPE" FOREIGN KEY ("CON_INT_TYPE_ID")
	  REFERENCES "MC"."CON_INT_TYPE" ("ID") 
  
   )  ;

--changeset nop:1117
--comment: SRE-421: Adjust ISP_LINK table

-- MSS.ISP_LINK additional column
ALTER TABLE MSS.ISP_LINK ADD ISP_LINK_STATUS_TYPE_ID_SRE NUMBER(10,0) NULL;

-- MSS.ISP_LINK foreign keys
ALTER TABLE "MSS"."ISP_LINK" ADD CONSTRAINT "ISPLINK_FK16" FOREIGN KEY ("ISP_LINK_STATUS_TYPE_ID_SRE") REFERENCES "MC"."ISP_LINK_STATUS_TYPE" ("ID") DEFERRABLE INITIALLY DEFERRED ENABLE;


--changeset nop:1118
--comment: SRE-421: Add user SVC_CONNECTIVITY_COORDINATOR

CREATE USER "SVC_CONNECTIVITY_COORDINATOR" IDENTIFIED BY "xxxxxx" ACCOUNT LOCK
    DEFAULT TABLESPACE "USERS"
    TEMPORARY TABLESPACE "TEMP";

GRANT "MSS_LOGIN_USER" TO "SVC_CONNECTIVITY_COORDINATOR";
ALTER USER "SVC_CONNECTIVITY_COORDINATOR" DEFAULT ROLE "MSS_LOGIN_USER";
GRANT EXEMPT ACCESS POLICY TO "SVC_CONNECTIVITY_COORDINATOR";

GRANT UPDATE on MSS.ISP_LINK to SVC_CONNECTIVITY_COORDINATOR;

GRANT INSERT on MC.HOST_CONNECTION_STATUS_SRE to SVC_CONNECTIVITY_COORDINATOR;
GRANT SELECT on MC.HOST_CONNECTION_STATUS_SRE to SVC_CONNECTIVITY_COORDINATOR;
GRANT UPDATE on MC.HOST_CONNECTION_STATUS_SRE to SVC_CONNECTIVITY_COORDINATOR;
GRANT DELETE on MC.HOST_CONNECTION_STATUS_SRE to SVC_CONNECTIVITY_COORDINATOR;

GRANT INSERT on MC.MON_SERVER_CONNECTION_SRE to SVC_CONNECTIVITY_COORDINATOR;
GRANT SELECT on MC.MON_SERVER_CONNECTION_SRE to SVC_CONNECTIVITY_COORDINATOR;
GRANT UPDATE on MC.MON_SERVER_CONNECTION_SRE to SVC_CONNECTIVITY_COORDINATOR;
GRANT DELETE on MC.MON_SERVER_CONNECTION_SRE to SVC_CONNECTIVITY_COORDINATOR;

GRANT INSERT on MC.ISP_LINK_HISTORY_SRE to SVC_CONNECTIVITY_COORDINATOR;
GRANT SELECT on MC.ISP_LINK_HISTORY_SRE to SVC_CONNECTIVITY_COORDINATOR;
GRANT UPDATE on MC.ISP_LINK_HISTORY_SRE to SVC_CONNECTIVITY_COORDINATOR;
GRANT DELETE on MC.ISP_LINK_HISTORY_SRE to SVC_CONNECTIVITY_COORDINATOR;

GRANT INSERT on MC.CONNECTION_INTERRUPT_CLOSED_SRE to SVC_CONNECTIVITY_COORDINATOR;
GRANT SELECT on MC.CONNECTION_INTERRUPT_CLOSED_SRE to SVC_CONNECTIVITY_COORDINATOR;
GRANT UPDATE on MC.CONNECTION_INTERRUPT_CLOSED_SRE to SVC_CONNECTIVITY_COORDINATOR;
GRANT DELETE on MC.CONNECTION_INTERRUPT_CLOSED_SRE to SVC_CONNECTIVITY_COORDINATOR;

GRANT INSERT on MC.CONNECTION_INTERRUPT_OPEN_SRE to SVC_CONNECTIVITY_COORDINATOR;
GRANT SELECT on MC.CONNECTION_INTERRUPT_OPEN_SRE to SVC_CONNECTIVITY_COORDINATOR;
GRANT UPDATE on MC.CONNECTION_INTERRUPT_OPEN_SRE to SVC_CONNECTIVITY_COORDINATOR;
GRANT DELETE on MC.CONNECTION_INTERRUPT_OPEN_SRE to SVC_CONNECTIVITY_COORDINATOR;

GRANT SELECT on TT.TICKET to SVC_CONNECTIVITY_COORDINATOR;
GRANT SELECT on TT.SERVICE_WINDOW to SVC_CONNECTIVITY_COORDINATOR;
GRANT SELECT on MSS.ISP_LINK to SVC_CONNECTIVITY_COORDINATOR;
GRANT SELECT on MSS.HOST to SVC_CONNECTIVITY_COORDINATOR;
GRANT SELECT on MC.HOST_CONNECTION_STATUS_SRE to SVC_CONNECTIVITY_COORDINATOR;
GRANT SELECT on MSS.OPENVPN_INTERFACE to SVC_CONNECTIVITY_COORDINATOR;
GRANT SELECT on MSS.INTERFACE to SVC_CONNECTIVITY_COORDINATOR;
GRANT SELECT on MSS.ISP_LINK to SVC_CONNECTIVITY_COORDINATOR;
GRANT SELECT on MSS.INTERFACE2ISP_LINK to SVC_CONNECTIVITY_COORDINATOR;

--changeset nop:1119 endDelimiter:/
--comment: SRE-421: Create stub package

CREATE OR REPLACE PACKAGE MC.CONNECTIVITY_COORDINATOR IS
END CONNECTIVITY_COORDINATOR;
/

--changeset nop:1120
--comment: SRE-421: Grant execute to SVC_CONNECTIVITY_COORDINATOR on MC.CONNECTIVITY_COORDINATOR

GRANT EXECUTE ON MC.CONNECTIVITY_COORDINATOR TO SVC_CONNECTIVITY_COORDINATOR;

--changeset fpi:1121
--comment: FW-5728: Grant additional access rights for FW objects validation

GRANT SELECT on MSS.ISP_LINK TO SVC_FIREWALL_API;
GRANT SELECT on MSS.IPV6_STATIC_ROUTE TO SVC_FIREWALL_API;
GRANT SELECT on MSS.OPENVPN_INTERFACE TO SVC_FIREWALL_API;
GRANT SELECT on VPN.VPN TO SVC_FIREWALL_API;

--changeset ogl:1122
--comment: DB-1783: permissions on ISP data
GRANT SELECT ON mss.ISP_LINK_TRANSPORT_MEDIA TO "SVC_CONIFER";
GRANT SELECT ON mss.IPV6_ADDRESS TO "SVC_CONIFER";
GRANT SELECT ON mss.CURRENCY TO "SVC_CONIFER";
GRANT SELECT ON stop.CONTACT TO "SVC_CONIFER";

--changeset alg:1123
--comment: DB-1783: permissions on Props data
GRANT SELECT ON MSS.mv_value_host_default TO SVC_CONIFER;
GRANT SELECT ON MSS.KEY TO SVC_CONIFER;
GRANT SELECT ON MSS.VALUE TO SVC_CONIFER;

--changeset rse:1124
--comment: CONF-3380: Support full buildall in worker.scheduler (job scheduling system via MC portal)
ALTER TABLE MSS.CONFIG_ROLLOUT MODIFY CONFIG_DEPLOYMENT_USE_CASE_ID NUMBER(10,0) NULL;

--changeset fpi:1125
--comment: FW-5797: Permissions to edit simple objects in FW-API
GRANT SELECT ON FW.IPADDRESS_SEQ TO SVC_FIREWALL_API;
GRANT SELECT ON MSS.NETWORK_SEQUENCE TO SVC_FIREWALL_API;
GRANT SELECT ON MSS.IPV6ADDRESS_SEQ TO SVC_FIREWALL_API;
GRANT SELECT ON MSS.IPV6PREFIX_SEQ TO SVC_FIREWALL_API;

GRANT INSERT,UPDATE,DELETE ON FW.IP_ADDRESS TO SVC_FIREWALL_API;
GRANT INSERT,UPDATE,DELETE ON MSS.NETWORK TO SVC_FIREWALL_API;
GRANT INSERT,UPDATE,DELETE ON MSS.IPV6_ADDRESS TO SVC_FIREWALL_API;
GRANT INSERT,UPDATE,DELETE ON MSS.IPV6_PREFIX TO SVC_FIREWALL_API;

--changeset ogl:1126
--comment: DB-1780: complete interface datamodel
GRANT SELECT ON FW.ZONE TO SVC_CONIFER;
GRANT SELECT ON FW.ZONE_MEMBER TO SVC_CONIFER;
GRANT SELECT ON FW.IP_ADDRESS TO SVC_CONIFER;
GRANT SELECT ON MSS.INTERFACE_SPEED TO SVC_CONIFER;
GRANT SELECT ON APPID.PATH_SELECTION_LINK_CLASS TO SVC_CONIFER;
GRANT SELECT ON APPID.BANDWIDTH_CONTROL_PROFILE TO SVC_CONIFER;

--changeset nop:1127
--comment: SRE-421: Allow service user to access ipv6 related tables
GRANT SELECT ON MSS.IPV6_ADDRESS TO SVC_CONNECTIVITY_COORDINATOR;
GRANT SELECT ON MSS.INTERFACE_ADDRESS TO SVC_CONNECTIVITY_COORDINATOR;

--changeset ogl:1128
GRANT SELECT ON MSS.INTERFACE_SEQUENCE TO SVC_CONIFER;
GRANT INSERT,UPDATE ON MSS.INTERFACE TO SVC_CONIFER;
GRANT INSERT ON MSS.NETWORK TO SVC_CONIFER;
GRANT SELECT ON FW.ZONE_MEMBER_SEQ TO SVC_CONIFER;
GRANT INSERT ON FW.ZONE_MEMBER TO SVC_CONIFER;

--changeset mlo:1129
--comment: MC-25796: Add OIDC setup record in audit trail
INSERT INTO mcaudit.RECORD_TYPE (ID,NAME,SHORT,DESCRIPTION,SYSTEM_ID) values (9, 'Login OIDC Setup', 'login_oidc_setup', 'OIDC Login was setup after first login', 2);

--changeset lga:1130
--comment: MC-25656: ISP Line new fields
ALTER TABLE MSS.ISP_LINK
    ADD SITE_ID VARCHAR2(256);
COMMENT ON COLUMN MSS.ISP_LINK.SITE_ID is 'Contains the Customer Site ID Registry + Location ID';

ALTER TABLE MSS.ISP_LINK
    ADD OSAM_ID VARCHAR2(256);
COMMENT ON COLUMN MSS.ISP_LINK.OSAM_ID is 'Contains the Site ID, Location ID, first or second line and version of line offer';

ALTER TABLE MSS.ISP_LINK
    ADD HANDOFF_PORT VARCHAR2(256);
COMMENT ON COLUMN MSS.ISP_LINK.HANDOFF_PORT is 'Provided by the ISP, lists the ports that are still available to use';

--changeset fpi:1131
--comment: FW-5757: Implement Audit Log for Simple Objects
GRANT EXECUTE ON MCAUDIT.OSAG_AUDIT TO SVC_FIREWALL_API;

--changeset nop:1132
--comment: SRE-454: Add turn-off dbprop for blackbox-exporter
INSERT INTO MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
VALUES (56754, 'migrate.blackbox_exporter.disable', 1, '1', '^[01]$', NULL, 'Disable blackbox exporter configuration');

--changeset fis:1133
--comment: MX-4296 Grant select permissions to mail_dkim user
GRANT SELECT ON MSS.SERVICE TO MAIL_DKIM;
GRANT SELECT ON STOP.COMPANY TO MAIL_DKIM;

--changeset ogl:1134
--comment: monitor FRA free space
insert into MCDB_CHECKS.CONSISTENCY_CHECKS(ID, CHECK_KEY, CHECK_GROUP, STATEMENT, MESSAGE, PLOGLEVEL, SLOGLEVEL)
values (77, 'SEL_fra_full', 'critical',
        'select 100-round(100*(SPACE_USED-SPACE_RECLAIMABLE)/SPACE_LIMIT, 2) pct_free from V$RECOVERY_FILE_DEST d where 100-round(100*(SPACE_USED-SPACE_RECLAIMABLE)/SPACE_LIMIT, 2) < 30',
        'DB FRA is running out of space. Start DB Backup to free up space NOW or DB will stop soon!',
        '4', 'WARNING');

--changeset fpi:1135
--comment: FW-5757: Add app, component and record types for FWAPI
INSERT INTO MCAUDIT.APPLICATION (ID, NAME, SHORT, DESCRIPTION)
VALUES (15, 'Firewall API', 'fwapi', 'Firewall API');

INSERT INTO MCAUDIT.COMPONENT (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID)
VALUES (79, 'Firewall Self-Service', 'fwapi', 'Firewall API', 1);

INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID)
VALUES (364, 'Firewall object created', 'fw_object_created', 'A new firewall object has been created', 1);

INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID)
VALUES (365, 'Firewall object modified', 'fw_object_modified', 'A firewall object has been updated', 1);

INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID)
VALUES (366, 'Firewall object deleted', 'fw_object_deleted', 'A firewall object has been deleted', 1);

--changeset ogl:1136
--comment: DB-1784: add permissions for VPN tunnels
grant select on vpn.VPN to SVC_CONIFER;
grant select on vpn.PARTITION to SVC_CONIFER;
grant select on vpn.VPN_MEMBER to SVC_CONIFER;
grant select,insert,update,delete on vpn.TUNNEL to SVC_CONIFER;
grant select on mss.HOST_SEQUENCE to SVC_CONIFER;
grant insert on mss.HOST to SVC_CONIFER;
grant select on mss.NETWORK_SEQUENCE to SVC_CONIFER;
grant select on  mss.STATIC_ROUTE_SEQUENCE to SVC_CONIFER;

--changeset ogl:1137
--comment: DB-1784: add missing permissions for tunnels
grant insert,update,delete on vpn.VPN_MEMBER to SVC_CONIFER;
grant select on vpn.VPN_MEMBER_SEQUENCE to SVC_CONIFER;
grant select on vpn.TUNNEL_SEQUENCE to SVC_CONIFER;

--changeset ogl:1138
--comment: DB-1820: create user SVC_CHECKHOSTS
CREATE USER "SVC_CHECKHOSTS" IDENTIFIED BY "xxxxxx" ACCOUNT LOCK
  DEFAULT TABLESPACE "USERS"
  TEMPORARY TABLESPACE "TEMP";

--changeset ogl:1139 contextFilter:dummyPasswords
ALTER USER "SVC_CHECKHOSTS" IDENTIFIED BY "password" ACCOUNT UNLOCK;

--changeset ogl:1140
--comment: DB-1820: roles and permissons for SVC_CHECKHOSTS
GRANT "MSS_LOGIN_USER" TO "SVC_CHECKHOSTS";
ALTER USER "SVC_CHECKHOSTS" DEFAULT ROLE "MSS_LOGIN_USER";
GRANT EXEMPT ACCESS POLICY TO "SVC_CHECKHOSTS";

grant select on MSS.HARDWARE to SVC_CHECKHOSTS;
grant select on MSS.HARDWARE_TYPE to SVC_CHECKHOSTS;
grant select on MSS.HOST to SVC_CHECKHOSTS;
grant select on MSS.HOST2SERVICE to SVC_CHECKHOSTS;
grant select on MSS.INTERFACE to SVC_CHECKHOSTS;
grant select on MSS.NETWORK to SVC_CHECKHOSTS;
grant select on MSS.SERVICE to SVC_CHECKHOSTS;
grant select on MSS.SERVICE_TYPE to SVC_CHECKHOSTS;
grant select on MSS.STATIC_ROUTE to SVC_CHECKHOSTS;
grant select on MSS.V_HOST_KEY_VALUE to SVC_CHECKHOSTS;
grant select on STOP.COMPANY to SVC_CHECKHOSTS;
grant select on VPN.VPN_MEMBER to SVC_CHECKHOSTS;

--changeset nop:1141
--comment: SRE-421: Additional grants to SVC_CONNECTIVITY_COORDINATOR for monitoring purposes
GRANT SELECT on MC.MON_SERVER_CONNECTION to SVC_CONNECTIVITY_COORDINATOR;

--changeset ogl:1142
--comment: DB-1787: missing grant
grant select on MSS.V_HOST_KEY_VALUE to SVC_CONIFER;

--changeset ogl:1143
--comment: DB-1786: add grants on local contacts
grant select on mss.local_contact  to SVC_CONIFER;
grant select on stop.contact to SVC_CONIFER;
grant select on mss.address to SVC_CONIFER;
grant select on stop.company to SVC_CONIFER;
grant select on mss.city to SVC_CONIFER;
grant select on mss.country to SVC_CONIFER;
grant select on mss.continent to SVC_CONIFER;

--changeset yab:1144
--comment: MC-25881: Add new self-service permission for fw-editor
INSERT INTO AUTH.USER_ROLE (ID, NAME, DESCRIPTION, IS_INTERNAL, USER_ROLE_SCOPE_TYPE_ID)
    VALUES (2011, 'mc-cust-fw-config-mgmt', 'Firewall Policy Management', 0, 1);
INSERT INTO AUTH.user_role2required_role (USER_ROLE_ID, REQUIRED_USER_ROLE_ID)
    VALUES (2011, 1003);

--changeset nop:1145
--comment: SRE-421: drop constraint for monitoring server for thanos data
ALTER TABLE MC.MON_SERVER_CONNECTION_SRE DROP CONSTRAINT FK_MSC_SRE_MON_SERVER_ID;
INSERT INTO MC."#JDO_PROPERTIES" ("KEY","VALUE") VALUES ('MON_SERVER_CONNECTION_SRE.naming','none');

--changeset thw:1146
--comment: SRE-457: allow alert-handler user to access isp company name
grant select on stop.company to SVC_ALERTHANDLER;

--changeset thw:1147
--comment: SRE-458: allow alert-handler user to access address data of hosts
grant select on MSS.ADDRESS to SVC_ALERTHANDLER;
grant select on MSS.CITY to SVC_ALERTHANDLER;
grant select on MSS.COUNTRY to SVC_ALERTHANDLER;

--changeset ogl:1148
--comment: DB-1780: grants for creating static NAT
GRANT SELECT ON FW.IPADDRESS_SEQ TO SVC_CONIFER;
GRANT INSERT ON FW.IP_ADDRESS TO SVC_CONIFER;

--changeset nop:1149
--comment: SRE-421: grants for dbdns to query sre tables
GRANT SELECT ON MC.MON_SERVER_CONNECTION_SRE TO DBDNS;

--changeset baj:11450
--comment: IDS-2447: remove dbprop snort.goalertd
delete from mss.VALUE where KEY_ID=21346;
delete from mss.key where id = 21346;

--changeset jho:1151
--comment: MX-4353: Create SASI dbprops
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (56755, 'mail.antispam.sasi', 1, '0', '^[01]$', NULL, 'Include SASI results for spam checks');

insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (56756, 'mail.antispam.sasi.log_only', 1, '0', '^[01]$', NULL, 'Include SASI results for spam checks in log-only mode');

--changeset ogl:1152
--comment: DB-1838: grants to check authorization
grant select on auth.LOGIN to SVC_CONIFER;
grant select on auth.LOGIN2PROFILE to SVC_CONIFER;
grant select on auth.USER_PERMISSION to SVC_CONIFER;
grant select on auth.USER_ROLE to SVC_CONIFER;

--changeset ogl:1153
--comment: DB-1844: auditing
grant execute on MCAUDIT.OSAG_AUDIT to SVC_CONIFER;
insert into MCAUDIT.APPLICATION(id, name, short, description)
values (16, 'Config API', 'mc-config-api', 'MC Configuration API');
insert into MCAUDIT.COMPONENT(id, system_id, name, short, description)
values (80, 1, 'Config API', 'mc-config-api', 'MC Configuration API');

--changeset diw:1154
--comment: IDS-2533: Add new DB Prop migrate.2023.swanctl
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (56757, 'migrate.2023.swanctl', 1, '0', '^[01]$', NULL, 'migrate form ipsec.conf to swanctl.conf');

--changeset ogl:1155
--comment: DB-1844: audit references tickets
grant select on TT.TICKET to SVC_CONIFER;

--changeset rse:1156
--comment: Add missing grant for DBDNS to filter for hosts attached to a service
GRANT SELECT ON MSS.HOST2SERVICE TO DBDNS;

--changeset ogl:1157
--comment: DB-1862: expose CompanyUnit
grant select on stop.COMPANY_UNIT to SVC_CONIFER;
grant select on stop.CONTACT_HANDLING to SVC_CONIFER;
grant select on stop.CONTACT_LIST to SVC_CONIFER;

--changeset mta:1158
--comment: FW-5905: Grant on FW sequences to svc_firewall_api
GRANT SELECT ON FW.APPGROUP_SEQ TO SVC_FIREWALL_API;
GRANT SELECT ON FW.CONFIGLOCK_SEQ TO SVC_FIREWALL_API;
GRANT SELECT ON FW.DNS_OBJECT_SEQ TO SVC_FIREWALL_API;
GRANT SELECT ON FW.EXTERNALIPLIST_SEQ TO SVC_FIREWALL_API;
GRANT SELECT ON FW.FILTERRULE_SEQ TO SVC_FIREWALL_API;
GRANT SELECT ON FW.IPADDRESS_SEQ TO SVC_FIREWALL_API;
GRANT SELECT ON FW.IPGROUPMEMBER_SEQ TO SVC_FIREWALL_API;
GRANT SELECT ON FW.IPGROUP_SEQ TO SVC_FIREWALL_API;
GRANT SELECT ON FW.IPSERVICE_SEQ TO SVC_FIREWALL_API;
GRANT SELECT ON FW.NAT_SECTION_SEQ TO SVC_FIREWALL_API;
GRANT SELECT ON FW.POLICY_SEQ TO SVC_FIREWALL_API;
GRANT SELECT ON FW.RECENT_POLICY_SEQ TO SVC_FIREWALL_API;
GRANT SELECT ON FW.SCOPED_IP_GROUP_MEMBER_SEQ TO SVC_FIREWALL_API;
GRANT SELECT ON FW.SCOPED_IP_GROUP_SCOPE_SEQ TO SVC_FIREWALL_API;
GRANT SELECT ON FW.SCOPED_IP_GROUP_SEQ TO SVC_FIREWALL_API;
GRANT SELECT ON FW.SECTION_SEQ TO SVC_FIREWALL_API;
GRANT SELECT ON FW.SERVICEGROUP_SEQ TO SVC_FIREWALL_API;
GRANT SELECT ON FW.SUB_SECTION_SEQ TO SVC_FIREWALL_API;
GRANT SELECT ON MSS.IPV6PREFIX_SEQ TO SVC_FIREWALL_API;
GRANT SELECT ON MSS.IPV6ADDRESS_SEQ TO SVC_FIREWALL_API;
GRANT SELECT ON MSS.NETWORK_SEQUENCE TO SVC_FIREWALL_API;

--changeset aba:1159
--comment: OSDP-1335 create centralus and eastus osse regions
INSERT INTO MSS.CLOUD_REGION_INSTANCE (ID, INTERNAL_CODE, PROVIDER, REGION, DISPLAY_NAME, CLUSTER_URL, LATITUDE_DIRECTION, LATITUDE_DEGREES, LATITUDE_MINUTES, LATITUDE_SECONDS, LONGITUDE_DIRECTION, LONGITUDE_DEGREES, LONGITUDE_MINUTES, LONGITUDE_SECONDS)
VALUES (6, 'azu-centralus-1', 'azure', 'centralus', 'SSE RegioHub 1 on Azure centralus', 'https://osse-prod-azu-centralus-1-e8xxvdfq.hcp.centralus.azmk8s.io', 'N', '41', '35', '27', 'W', '093', '37', '15');

INSERT INTO MSS.CLOUD_REGION_INSTANCE (ID, INTERNAL_CODE, PROVIDER, REGION, DISPLAY_NAME, CLUSTER_URL, LATITUDE_DIRECTION, LATITUDE_DEGREES, LATITUDE_MINUTES, LATITUDE_SECONDS, LONGITUDE_DIRECTION, LONGITUDE_DEGREES, LONGITUDE_MINUTES, LONGITUDE_SECONDS)
VALUES (7, 'azu-eastus-1', 'azure', 'eastus', 'SSE RegioHub 1 on Azure eastus', 'https://osse-prod-azu-eastus-1-b2jji1ob.hcp.eastus.azmk8s.io', 'N', '36', '40', '40', 'W', '078', '22', '29');

--changeset fis:1160
--comment: MX-4394 rename phishing protection dbprop to urlprotection
update mss.key k set k.NAME='urlprotection' where k.id=22510 and k.name='phishingprotection';
update mss.key k set k.NAME='urlprotection.log_only' where k.id=22511 and k.name='phishingprotection.log_only';

--changeset fis:1161
--comment: MX-4396 rename mail.advanced_protection dbprops to mail.activeguard
update mss.key k set k.NAME='mail.activeguard' where k.id=22431 and k.name='mail.advanced_protection';
update mss.key k set k.NAME='mail.activeguard.log_only' where k.id=22432 and k.name='mail.advanced_protection.log_only';

--changeset ogl:1162
--comment: DB-1837: permissions for interface updates
grant delete on mss.NAT_IIFACE_2_OIFACE to SVC_CONIFER;
grant delete on fw.ZONE_MEMBER to SVC_CONIFER;

--changeset ogl:1163
--comment: missing permission for interface query
grant select on mss.ISP_LINK_SOURCING_TYPE to SVC_CONIFER;

--changeset nis:1164
--comment: Allows ticketing service user to access mss.ADDRESS
grant select on mss.ADDRESS TO SVC_API_TICKETING;

--changeset nis:1165
--comment: Allows ticketing service user to access mss.CITY and mss.COUNTRY
grant select on mss.CITY TO SVC_API_TICKETING;
grant select on mss.COUNTRY TO SVC_API_TICKETING;

--changeset mma:1166
--comment: PRX-7743: Add dbprop to configure Netstar full DB
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (56760, 'squid.urlfilter.netstar.fulldb', 1, NULL, '^[01]$', NULL, 'enable full netstar urlfilter db');

--changeset mlo:1167
--comment: MC-26087: create custom policy lists from MCA
GRANT SELECT,INSERT,UPDATE on MAIL.CUSTOM_POLICY_LIST to MCA;

--changeset mlo:1168
--comment: MC-26087: create custom policy lists from MCA permissions for sequence
GRANT SELECT on MAIL.CUSTOM_POLICY_LIST_SEQ to MCA;

--changeset nop:1169
--comment: SRE-421: Allow fetching of company name to connectivity coordinator
GRANT SELECT on STOP.COMPANY to SVC_CONNECTIVITY_COORDINATOR;

--changeset ogl:1170
--comment: DB-1752: Keystats EOL DB cleanup
DROP TABLE GUMA2.KEYSTAT;

--changeset ogl:1171
--comment: DB-1752: Keystats EOL DB cleanup
DROP USER KEYSTAT CASCADE;

--changeset ogl:1172
--comment: DB-1752: Keystats EOL DB cleanup
DELETE FROM GUMA2."#JDO_PROPERTIES" where key like 'KEYSTAT.%';
DELETE FROM MSS."#JDO_PROPERTIES" where key = 'HOST.naming.inverse.GUMA2.KEYSTAT_FK1';

--changeset nop:1173
--comment: Allows connectivity coordinator to write to ISP links
GRANT UPDATE ON MSS.ISP_LINK TO SVC_CONNECTIVITY_COORDINATOR;
UPDATE mss.KEY set string_default='1' where name='migrate.sang.turnoff_ticket_events';

--changeset nop:1174
--comment: Cleanup of dbprops
DELETE FROM MSS.KEY WHERE name='migrate.sang.turnoff_ticket_events';
DELETE FROM MSS.KEY WHERE name='migrate.progressive_rollout.connectivity_alerts_1';
DELETE FROM MSS.KEY WHERE name='migrate.custom_exporter.emergency_turnoff';

--changeset mag:1175
--comment: PRX-7769: Add new DB Prop squid.urlfilter.netstar.use_dlhosts
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (56761, 'squid.urlfilter.netstar.use_dlhosts', 1, NULL, '^[01]$', NULL, 'enable connection to netstar via dl hosts');

--changeset rse:1176
--comment: FW-5933: Add new dbprop for firewall hits count metric migration
INSERT INTO MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
VALUES (56770, 'migrate.2023.fw.hitscount', 1, '0', '^[01]$', NULL, 'enable firewall hits count instead of legacy gauge');

--changeset ogl:1177
--comment: additional permissions for emergency contacts
grant select on stop.CONTACT_LIST_MEMBER to SVC_CONIFER;
grant select on stop.REACH_ON_TYPE to SVC_CONIFER;

--changeset ssk:1178
--comment: FW-5947: Add missing permissions to edit objects in FW-API
GRANT INSERT,UPDATE,DELETE ON FW.IP_SERVICE TO SVC_FIREWALL_API;
GRANT INSERT,UPDATE,DELETE ON FW.DNS_OBJECT TO SVC_FIREWALL_API;
GRANT INSERT,UPDATE,DELETE ON FW.SERVICE_GROUP TO SVC_FIREWALL_API;
GRANT INSERT,UPDATE,DELETE ON FW.SERVICE_GROUP2SERVICE_GROUP TO SVC_FIREWALL_API;
GRANT INSERT,UPDATE,DELETE ON FW.SERVICE_GROUP2IP_SERVICE TO SVC_FIREWALL_API;
GRANT INSERT,UPDATE,DELETE ON FW.APP_GROUP TO SVC_FIREWALL_API;
GRANT INSERT,UPDATE,DELETE ON FW.APP_GROUP2APP TO SVC_FIREWALL_API;
GRANT INSERT,UPDATE,DELETE ON FW.APP_GROUP2APP_GROUP TO SVC_FIREWALL_API;
GRANT INSERT,UPDATE,DELETE ON FW.IP_GROUP TO SVC_FIREWALL_API;
GRANT INSERT,UPDATE,DELETE ON FW.IP_GROUP_MEMBER TO SVC_FIREWALL_API;
GRANT INSERT,UPDATE,DELETE ON FW.SCOPED_IP_GROUP_MEMBER TO SVC_FIREWALL_API;
GRANT INSERT,UPDATE,DELETE ON FW.SCOPED_IP_GROUP TO SVC_FIREWALL_API;
GRANT INSERT,UPDATE,DELETE ON FW.SCOPED_IP_GROUP_SCOPE TO SVC_FIREWALL_API;

--changeset ogl:1179
--comment: additional permissions for local contacts
grant select on mss.LOCAL_CONTACT_TYPE to SVC_CONIFER;

--changeset phm:1180
--comment: MON-3815: allow alert-handler user to access customer maintenance windows
GRANT SELECT ON TT.CUST_MAINTENANCE_WINDOW TO SVC_ALERTHANDLER;

--changeset jwj:1181
--comment: MX-4365: Rename PhishingProtection plugin to URLProtection
UPDATE MAIL.POLICY_LIST_TAG SET NAME='url_protection', DESCRIPTION='URL Protection' WHERE NAME='phishing_protection';

--changeset jwj:1182
--comment: MX-4374: Add Phishing plugin exclusion list
INSERT INTO MAIL.POLICY_LIST_TAG(MAIL.POLICY_LIST_TAG.ID, MAIL.POLICY_LIST_TAG.NAME, MAIL.POLICY_LIST_TAG.DESCRIPTION, MAIL.POLICY_LIST_TAG.POLICY_LIST_TYPE_ID) VALUES (17, 'phishing', 'Phishing', 1);

--changeset ssk:1183
--comment: FW-5973: Update audit trail master data
UPDATE MCAUDIT.COMPONENT SET NAME='Firewall API' WHERE ID=79;

--changeset ogl:1184
--comment: DB-1872: IPv6 support
GRANT SELECT,INSERT,UPDATE,DELETE on MSS.INTERFACE_ADDRESS to SVC_CONIFER;
GRANT SELECT,INSERT,UPDATE,DELETE on MSS.IPV6_ADDRESS to SVC_CONIFER;
GRANT SELECT,INSERT,UPDATE,DELETE on MSS.IPV6_PREFIX to SVC_CONIFER;
GRANT SELECT,INSERT,UPDATE,DELETE on MSS.IPV6_STATIC_ROUTE to SVC_CONIFER;
GRANT SELECT on mss.IPV6PREFIX_SEQ to SVC_CONIFER;
GRANT SELECT on mss.IPV6ADDRESS_SEQ to SVC_CONIFER;
GRANT SELECT on mss.INTERFACEADDRESS_SEQ to SVC_CONIFER;

--changeset nop:1186
--comment: SRE-421: Rebuild constraint without MON_SERVER_ID
ALTER TABLE MC.MON_SERVER_CONNECTION_SRE DROP CONSTRAINT MONSERVERCONNECTIONSRE_PK;

--changeset nop:1187
--comment: SRE-421: Rebuild constraint without MON_SERVER_ID
ALTER TABLE MC.MON_SERVER_CONNECTION_SRE MODIFY MON_SERVER_ID NULL;

--changeset nop:1188
--comment: SRE-421: Rebuild constraint without MON_SERVER_ID
ALTER TABLE MC.MON_SERVER_CONNECTION_SRE ADD CONSTRAINT MONSERVERCONNECTIONSRE_PK PRIMARY KEY (HOST_ID);

--changeset rse:1189
--comment: Cleanup obsolete and unused dbprop juniper.ntp.listen
DELETE FROM MSS.KEY WHERE name='juniper.ntp.listen';

--changeset alg:1200 tag:v1.1.0
--comment: Base of new container
SELECT 1 FROM DUAL;

--changeset nop:1201
--comment: Additional grants for connectivity coordinator (to resolve all hosts from all scopes)
GRANT SELECT on MSS.SERVICE TO SVC_CONNECTIVITY_COORDINATOR;
GRANT SELECT on MSS.HOST2SERVICE TO SVC_CONNECTIVITY_COORDINATOR;
GRANT SELECT on STOP.COMPANY TO SVC_CONNECTIVITY_COORDINATOR;
GRANT UPDATE on MC.ISP_LINK_HISTORY TO SVC_CONNECTIVITY_COORDINATOR;
GRANT UPDATE on MC.CONNECTION_INTERRUPT_CLOSED TO SVC_CONNECTIVITY_COORDINATOR;
GRANT UPDATE on MC.CONNECTION_INTERRUPT_OPEN TO SVC_CONNECTIVITY_COORDINATOR;
GRANT SELECT on TT.EVENT TO SVC_CONNECTIVITY_COORDINATOR;

--changeset nop:1202
--comment: SRE-482: Add column IS_OPENVPN to MON_SERVER_CONNECTION tables
ALTER TABLE MC.MON_SERVER_CONNECTION ADD IS_OPENVPN NUMBER(1,0) DEFAULT 0 NOT NULL;
ALTER TABLE MC.MON_SERVER_CONNECTION_SRE ADD IS_OPENVPN NUMBER(1,0) DEFAULT 0 NOT NULL;

--changeset rha:1203
--comment: certtool: Add certificates to config API
GRANT SELECT,INSERT,UPDATE,DELETE on CERTS.CERTIFICATE to SVC_CONIFER;
GRANT SELECT,INSERT,UPDATE,DELETE on CERTS.CERTIFICATE_SCOPE_TYPE to SVC_CONIFER;
GRANT SELECT,INSERT,UPDATE,DELETE on CERTS.CERTIFICATE_USAGE to SVC_CONIFER;
GRANT SELECT,INSERT,UPDATE,DELETE on CERTS.PRIVATE_KEY to SVC_CONIFER;
GRANT SELECT,INSERT,UPDATE,DELETE on CERTS.CSR to SVC_CONIFER;
GRANT SELECT,INSERT,UPDATE,DELETE on CERTS.SAN to SVC_CONIFER;
GRANT SELECT on certs.CERTIFICATE_SEQ to SVC_CONIFER;
GRANT SELECT on certs.CERTIFICATE_USAGE_SEQ to SVC_CONIFER;
GRANT SELECT on certs.CSR_SEQ to SVC_CONIFER;
GRANT SELECT on certs.PRIVATE_KEY_SEQ to SVC_CONIFER;
GRANT SELECT on certs.SAN_SEQ to SVC_CONIFER;

--changeset rha:1205
--comment: certtool: dbprop default value update of migrate.mep.certificate_tool to use the certtool
UPDATE MSS.KEY SET MSS.KEY.STRING_DEFAULT='1' WHERE MSS.KEY.ID = 22601;

--changeset ogl:1206
--comment: check cluster flag of interfaces
insert into MCDB_CHECKS.CONSISTENCY_CHECKS(ID, CHECK_KEY, CHECK_GROUP, STATEMENT, MESSAGE, PLOGLEVEL, SLOGLEVEL)
values (78, 'SEL_cluster_interface', 'default',
        'select distinct ha.NAME service, ia.NAME interface
from mss.HOST2SERVICE ha2s, mss.HOST2SERVICE hb2s, mss.INTERFACE ia, mss.INTERFACE ib,
     mss.HOST ha, mss.HOST hb
where ha2s.SERVICE_ID = hb2s.SERVICE_ID
and ha2s.HOST_ID < hb2s.HOST_ID
and ha2s.HOST_ID = ia.HOST_ID
and hb2s.HOST_ID = ib.HOST_ID
and ia.HOST_ID = ha.ID
and ib.HOST_ID = hb.ID
and ha.ACTIVE = 1
and hb.ACTIVE = 1
and ia.NAME = ib.NAME
and ia.IS_CLUSTER_MANAGED != ib.IS_CLUSTER_MANAGED
order by ha.NAME, ia.NAME',
        'There are interfaces with inconsistent cluster flag across nodes!',
        6,
        'INFO');

--changeset rha:1207
--comment: certtool: minimise private key access for MC config API (write only)
REVOKE SELECT,UPDATE,DELETE on CERTS.PRIVATE_KEY from SVC_CONIFER;

--changeset yab:1208
--comment: DISPLAY_NAME for platform types should not include the internal code in parentheses
UPDATE MSS.PLATFORM_TYPE SET DISPLAY_NAME='SDP' WHERE INTERNAL_CODE='osix';
UPDATE MSS.PLATFORM_TYPE SET DISPLAY_NAME='CloudSSE' WHERE INTERNAL_CODE='k8s';

--changeset thw:1209
--comment: Allow access to IPV6 Data, SRE-518
GRANT SELECT ON MSS.IPV6_ADDRESS TO SVC_ALERTHANDLER;

--changeset msc:1210
--comment: WAN-2617: Add dbprops for bgp_core implementation
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (56771, 'wan.bgp_core', 1, '0', '^[01]$', NULL, 'Enable BGP Core configuration');
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (56772, 'wan.bgp_core.ebgp', 1, '0', '^[01]$', NULL, 'Activate eBGP configuration');
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (56773, 'wan.bgp_core.ibgp', 1, '0', '^[01]$', NULL, 'Activate iBGP configuration in the Regions');
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (56774, 'wan.bgp_core.redistribute_ospf', 1, '0', '^[01]$', NULL, 'Activate redistribution of OSPF into eBGP');
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (56775, 'wan.bgp_core.disable_ospf', 1, '0', '^[01]$', NULL, 'Disable OSPF peering in the Core');

--changeset djg:1211
--comment: DB-1933: Add mgmt dbprop for oracle hosts
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (56776, 'mgmtserver.oradb', 1, '0', '^[01]$', NULL, 'Management host with Oracle database');

--changeset rha:1212
--comment: certtool: unique certificate usages
ALTER TABLE "CERTS"."CERTIFICATE_USAGE" ADD CONSTRAINT CERTIFICATE_USAGE_UV1 UNIQUE("CERTIFICATE_SCOPE_TYPE_ID","CERTIFICATE_SCOPE_NAME","COMPANY_ID","GROUP_ID","SERVICE_ID","HOST_ID")

--changeset ogl:1213
--comment: allow static route management
GRANT INSERT,UPDATE,DELETE ON mss.STATIC_ROUTE TO "SVC_CONIFER";

--changeset nis:1214
--comment: Allows ticketing service user to access mss.PLATFORM_TYPE
grant select on mss.PLATFORM_TYPE TO SVC_API_TICKETING;

--changeset cwa:1215
--comment: MC-26242: Add BGP Core field to VPN partitions
alter table VPN.PARTITION add BGP_CORE NUMBER(1) default 0 not null;
comment on column VPN.PARTITION.BGP_CORE is 'Boolean flag if this is a BGP Core partition';

--changeset cwa:1216
--comment: MC-26242: Set default value of OSPF_AREA to 0.0.0.0
alter table VPN.PARTITION modify OSPF_AREA default 0;

--changeset cwa:1217
--comment: MC-26242: AS Number field to VPN partitions
alter table VPN.PARTITION add AS_NUMBER NUMBER(10);
comment on column VPN.PARTITION.AS_NUMBER is 'AS Number if it is a BGP Core partition';

--changeset mlo:1218
--comment: MC-26438: adapt host decom to SRE tables
GRANT SELECT,INSERT,UPDATE,DELETE ON MC.CONNECTION_INTERRUPT_CLOSED_SRE TO DECOMM;
GRANT SELECT,INSERT,UPDATE,DELETE ON MC.CONNECTION_INTERRUPT_OPEN_SRE TO DECOMM;
GRANT SELECT,INSERT,UPDATE,DELETE ON MC.HOST_CONNECTION_STATUS_SRE TO DECOMM;
GRANT SELECT,INSERT,UPDATE,DELETE ON MC.MON_SERVER_CONNECTION_SRE TO DECOMM;

--changeset phh:1219
--comment: FW-5703: remove migrate.2020.fw.log and migrate.2020.fw.log.fallback dbprop
DELETE FROM MSS."KEY" k WHERE k.NAME = 'migrate.2020.fw.log' AND k.ID = 22604;
DELETE FROM MSS."KEY" k WHERE k.NAME = 'migrate.2020.fw.log.fallback' AND k.ID = 22605;

--changeset rha:1220
--comment: certtool: SAN either assigned to certificate or CSR, not both
ALTER TABLE "CERTS"."SAN" ADD CONSTRAINT SAN_CK2 CHECK(CERTIFICATE_ID IS NULL OR CSR_ID IS NULL);

--changeset rse:1221
--comment: TRIVIAL: Add mgmtserver dbprops for new connectivity monitoring
INSERT INTO MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
VALUES (56780, 'mgmtserver.conn.probe',       1, '0', '^[01]$', NULL, 'Enables connectivity probing');
INSERT INTO MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
VALUES (56781, 'mgmtserver.conn.probe.hosts', 1, '0', '^[01]$', NULL, 'Enables probing of host IP addresses');
INSERT INTO MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
VALUES (56782, 'mgmtserver.conn.probe.isps',  1, '0', '^[01]$', NULL, 'Enables probing of ISP router IP addresses');
INSERT INTO MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
VALUES (56783, 'mgmtserver.conn.probe.ovpn',  1, '0', '^[01]$', NULL, 'Enables probing of OpenVPN IP addresses');

--changeset phm:1222
--comment: MON-3888: add field migrated boolean field
ALTER TABLE GUMA2.SIGNATURE ADD (MIGRATED NUMBER(1) default 0 not null);
COMMENT ON COLUMN GUMA2.SIGNATURE.MIGRATED
     IS 'end of 2023 guma migration to loki pipeline; disables guma pipeline when set to 1';

--changeset rse:1223
--comment: CONF-3380: Cleanup legacy data model for configuration rollouts
ALTER TABLE MSS.CONFIG_DEPLOYMENT DROP CONSTRAINT CONFIG_DEPLOYMENT_FK2;
ALTER TABLE MSS.CONFIG_DEPLOYMENT DROP CONSTRAINT CONFIG_DEPLOYMENT_FK3;
ALTER TABLE MSS.CONFIG_DEPLOYMENT DROP COLUMN LAST_UPDATE;
ALTER TABLE MSS.CONFIG_DEPLOYMENT DROP COLUMN CONFIG_DEPLOYMENT_USE_CASE_ID;
ALTER TABLE MSS.CONFIG_DEPLOYMENT DROP COLUMN CONFIG_DEPLOYMENT_STATUS_ID;
ALTER TABLE MSS.CONFIG_DEPLOYMENT DROP COLUMN DEPLOYMENT_GROUP_ID;
DROP TABLE MSS.CONFIG_DEPLOYMENT_STATUS;

--changeset lel:1224
--comment MON-3891: add service user for GUMA migration to log-based alerting
CREATE USER "SVC_GUMA_MIGRATION" IDENTIFIED BY "xxxxxx" ACCOUNT LOCK
  DEFAULT TABLESPACE "USERS"
  TEMPORARY TABLESPACE "TEMP";
  
GRANT "MSS_LOGIN_USER" TO "SVC_GUMA_MIGRATION";
ALTER USER "SVC_GUMA_MIGRATION" DEFAULT ROLE "MSS_LOGIN_USER";
GRANT EXEMPT ACCESS POLICY TO "SVC_GUMA_MIGRATION";

GRANT SELECT,UPDATE ON GUMA2.SIGNATURE TO SVC_GUMA_MIGRATION;

--changeset lel:1225 contextFilter:dummyPasswords
alter user SVC_GUMA_MIGRATION identified by "password" account unlock;

--changeset gta:1226
--comment: WAN-2638: add new t2ee dbprop
INSERT INTO MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
VALUES (56784, 't2ee', 1, '0', '^[01]$', NULL, 'Enables Tunnels to External Entities');

--changeset ogl:1227
--comment: DB-1940
drop package body mc.provider_mgmt;
drop package mc.provider_mgmt;

--changeset nis:1228
--comment: MC-26374
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID)
VALUES (367, 'Zitadel API user created', 'zitadel_api_user_created', 'A new API user has been created', 2);

INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID)
VALUES (368, 'Zitadel API user updated', 'zitadel_api_user_updated', 'An API user has been updated', 2);

INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID)
VALUES (369, 'Zitadel API user deleted', 'zitadel_api_user_deleted', 'An API user has been deleted', 2);

INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID)
VALUES (370, 'Zitadel API token created', 'zitadel_api_user_token_created', 'An API token has been created', 2);

INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID)
VALUES (371, 'Zitadel API token deleted', 'zitadel_api_user_token_deleted', 'An API token has been deleted', 2);

--changeset nis:1229
--comment: MC-26374
UPDATE MCAUDIT.RECORD_TYPE SET SYSTEM_ID=1 WHERE ID IN (367, 368, 369,370,371);

--changeset ogl:1230
--comment: DB-1949: add config group support
grant select,insert,update,delete on mss.CONFIGURATION_GROUP to SVC_CONIFER;
grant select on mss.CONFIGURATION_GROUP_SEQ to SVC_CONIFER;

--changeset gta:1231
--comment: WAN-2638: delete tunnel_external dbprops
delete from mss.value where key_id in (24300, 24301);
DELETE FROM MSS.KEY WHERE name='tunnel_external.gre' or name='tunnel_external.gre.name';

--changeset sym:1232
--comment: OSDP-1480: add dbprop to control squid logs ingestion with filebeat
INSERT INTO MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
VALUES (56785, 'beat.forwarding.squid', 1, '1', '^[01]$', NULL, 'Enables filebeat logs ingestion for squid');

--changeset ogl:1233
--comment: DB-1949: set service config group
grant update on mss.SERVICE to SVC_CONIFER;

--changeset sym:1234
--comment: osdp-1480: adjust name of the dbprop
update mss.key set name='beats.forwarding.squid' where id= 56785;

--changeset jad:1235
--comment: mep-2139: adjust regex of the dbprop
update mss.key set regexp='^(?:\&amp;\#[A-Za-z0-9]+\;)ICP(?:\&amp;\#[A-Za-z0-9]+\;)\d+(?:\&amp;\#[A-Za-z0-9]+\;)(?:-\d+)?$' where id=21607;

--changeset ogl:1236
--comment: DB-1909: create user that owns scoped config files
CREATE USER "FILES" IDENTIFIED BY "xxxxxx" ACCOUNT LOCK
  DEFAULT TABLESPACE "USERS"
  TEMPORARY TABLESPACE "TEMP";
GRANT "MSS_SCHEMA_USER" TO "FILES";
ALTER USER "FILES" DEFAULT ROLE "MSS_SCHEMA_USER";
ALTER USER "FILES" QUOTA UNLIMITED ON "USERS";
GRANT EXEMPT ACCESS POLICY TO "FILES";

--changeset ogl:1237 contextFilter:dummyPasswords
alter user FILES identified by "password" account unlock;

--changeset ogl:1238
--comment: DB-1909: data structure for scoped config files
create table FILES.SCOPED_FILE (
   ID       NUMBER        NOT NULL,
   SCOPE    VARCHAR2(16)  NOT NULL,
   OWNER_ID NUMBER        NOT NULL,
   NAME     VARCHAR2(256) NOT NULL,
   ISTEXT   NUMBER(1) DEFAULT 0 NOT NULL,
   CREATED  DATE      DEFAULT SYSDATE NOT NULL,
   CONTENT  BLOB              NULL,
   CONSTRAINT SCOPEDFILE_PK PRIMARY KEY (ID),
   CONSTRAINT SCOPEDFILE_UN UNIQUE (NAME, OWNER_ID, SCOPE)
);
COMMENT ON TABLE FILES.SCOPED_FILE IS 'Scoped files';

--changeset ogl:1239
--comment: DB-1909: data structure for scoped config files
CREATE INDEX FILES.IDX_SCOPED_FILE_1 ON FILES.SCOPED_FILE (OWNER_ID, SCOPE);

--changeset ogl:1240
--comment: DB-1909: data structure for scoped config files
CREATE SEQUENCE FILES.SCOPEDFILE_SEQ;

--changeset ogl:1241
--comment: DB-1909: grant config API access
GRANT SELECT,INSERT,UPDATE,DELETE on FILES.SCOPED_FILE to SVC_CONIFER;
GRANT SELECT on FILES.SCOPEDFILE_SEQ to SVC_CONIFER;

--changeset fis:1242
--comment: MX-4377: add new mail.antispam.activeguard dbprop
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (56786, 'mail.antispam.activeguard', 1, '0', '^[01]$', NULL, 'Activeguard results for spam checks');
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (56787, 'mail.antispam.activeguard.log_only', 1, '0', '^[01]$', NULL, 'Activeguard results for spam checks in log-only mode');

--changeset nop:1243
--comment: Allow connectivity-coordinator to reach the production tables in MC schema
GRANT INSERT on MC.HOST_CONNECTION_STATUS to SVC_CONNECTIVITY_COORDINATOR;
GRANT SELECT on MC.HOST_CONNECTION_STATUS to SVC_CONNECTIVITY_COORDINATOR;
GRANT UPDATE on MC.HOST_CONNECTION_STATUS to SVC_CONNECTIVITY_COORDINATOR;
GRANT DELETE on MC.HOST_CONNECTION_STATUS to SVC_CONNECTIVITY_COORDINATOR;

GRANT INSERT on MC.MON_SERVER_CONNECTION to SVC_CONNECTIVITY_COORDINATOR;
GRANT SELECT on MC.MON_SERVER_CONNECTION to SVC_CONNECTIVITY_COORDINATOR;
GRANT UPDATE on MC.MON_SERVER_CONNECTION to SVC_CONNECTIVITY_COORDINATOR;
GRANT DELETE on MC.MON_SERVER_CONNECTION to SVC_CONNECTIVITY_COORDINATOR;

GRANT SELECT on MC.ISP_LINK_HISTORY to SVC_CONNECTIVITY_COORDINATOR;
GRANT UPDATE on MC.ISP_LINK_HISTORY to SVC_CONNECTIVITY_COORDINATOR;

GRANT INSERT on MC.CONNECTION_INTERRUPT_CLOSED to SVC_CONNECTIVITY_COORDINATOR;
GRANT SELECT on MC.CONNECTION_INTERRUPT_CLOSED to SVC_CONNECTIVITY_COORDINATOR;
GRANT UPDATE on MC.CONNECTION_INTERRUPT_CLOSED to SVC_CONNECTIVITY_COORDINATOR;
GRANT DELETE on MC.CONNECTION_INTERRUPT_CLOSED to SVC_CONNECTIVITY_COORDINATOR;

GRANT INSERT on MC.CONNECTION_INTERRUPT_OPEN to SVC_CONNECTIVITY_COORDINATOR;
GRANT SELECT on MC.CONNECTION_INTERRUPT_OPEN to SVC_CONNECTIVITY_COORDINATOR;
GRANT UPDATE on MC.CONNECTION_INTERRUPT_OPEN to SVC_CONNECTIVITY_COORDINATOR;
GRANT DELETE on MC.CONNECTION_INTERRUPT_OPEN to SVC_CONNECTIVITY_COORDINATOR;

--changeset mlo:1244
--comment: MC-25460: Change 'migrate.zitadel' dbprop to be 0/1/2/3/4 instead of 0/1/2/3
update mss.key k
set k.REGEXP='^[01234]$'
where k.id=56701
  and k.name='migrate.zitadel';

--changeset ogl:1245
--comment: DB-1909: modify dbprops from config api
grant insert,update,delete on mss.VALUE to SVC_CONIFER;
grant update on mss.KEY to SVC_CONIFER;
grant select on mss.VALUE_SEQ to SVC_CONIFER;

--changeset ysh:1246
--comment: SRE-475: Grant Read permissions to read the local contact ot the alert-handler
GRANT SELECT ON MSS.LOCAL_CONTACT TO SVC_ALERTHANDLER;
GRANT SELECT ON STOP.CONTACT TO SVC_ALERTHANDLER;

--changeset pem:1247
--comment: IDS-2629: Add new backbone and backbone.gre.network dbprops
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (56790, 'backbone', 1, '0', '^[01]$', NULL, 'Enable WAN Backbone service');
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (56791, 'backbone.gre.network', 4, NULL, '^(?:[0-9]{1,3}\.){3}[0-9]{1,3}(?:$|\/(?:8|16|24))$', NULL, 'Base subnet to be assigned to the GRE tunnels for WAN Backbone service across the company');

--changeset ogl:1248
--comment: DB-1909: create schema that owns wan backbone
CREATE USER "WANBB" IDENTIFIED BY "xxxxxx" ACCOUNT LOCK
  DEFAULT TABLESPACE "USERS"
  TEMPORARY TABLESPACE "TEMP";
GRANT "MSS_SCHEMA_USER" TO "WANBB";
ALTER USER "WANBB" DEFAULT ROLE "MSS_SCHEMA_USER";
ALTER USER "WANBB" QUOTA UNLIMITED ON "USERS";
GRANT EXEMPT ACCESS POLICY TO "WANBB";

--changeset ogl:1249 contextFilter:dummyPasswords
alter user WANBB identified by "password" account unlock;

--changeset ogl:1250
CREATE TABLE WANBB.TERIDION_SITE(
  SERVICE_ID        INTEGER NOT NULL,
  IFC_NAME          VARCHAR2(32) NOT NULL,
  TERIDION_ID       VARCHAR2(256),
  NETWORK_SLOT      NUMBER(6),
  MASK              NUMBER(3) NOT NULL,
  BW_IN             NUMBER(9),
  BW_OUT            NUMBER(9),
  CONSTRAINT TERIDIONSITE_PK PRIMARY KEY (SERVICE_ID, IFC_NAME),
  CONSTRAINT TERIDIONSITE_UN UNIQUE (TERIDION_ID)
);

--changeset ogl:1251
GRANT select,insert,update,delete on wanbb.TERIDION_SITE to SVC_CONIFER;

--changeset alg:1248
--comment: DB-1970: Fix null Crash on Hardware type
grant SELECT ON MSS.HARDWARE_TYPE TO SVC_CONIFER;

--changeset ogl:1252
--comment: more API grants
grant select on fw.policy to SVC_CONIFER;
grant select on appid.PATH_SELECTION_PROFILE to SVC_CONIFER;

--changeset nop:1253
--comment: allow connectivity-coordinator to read the host associated to a service window
GRANT SELECT ON TT.HOST2SERVICE_WINDOW to SVC_CONNECTIVITY_COORDINATOR;

--changeset jah:1254
--comment: OSIX-5566: Add new DB Prop cicd.buildkite.agent.spawn
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (56800, 'cicd.buildkite.agent.spawn', 2, NULL, '^\d+$', 22, 'Set the number of OSIX buildkite-agent instances to be spawned in parallel');

--changeset phh:1255
--comment: WAN-2671: remove opnet dbprop
DELETE FROM MSS."KEY" k WHERE k.NAME = 'opnet' AND k.ID = 8085;

--changeset lut:1256
--comment: FW-5963: allow svc_firewall_api to access contact information
GRANT SELECT on STOP.CONTACT TO SVC_FIREWALL_API;

--changeset mag:1257
--comment: PRX-7878: Delete migrate.2023.squid.urlfilter
DELETE FROM mss.VALUE v WHERE v.key_id = 56704;
DELETE FROM mss.KEY WHERE id = 56704;

--changeset tho:1258
--comment: WAN-2670: Add new DB Prop net.log.routes
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (56810, 'net.log.routes', 1, 0, '^[01]$', 22, 'Activate logging of routing changes');

--changeset phm:1259
--comment: MON-3906: Add new DB Prop for control promtail configuration for now
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (56811, 'observability.scrubpii', 1, 0, '^[01]$', 22, 'Activate scrubbing of personal identifiable information observability pipelines where implemented.');

--changeset jve:1260
--comment: MON-3991: New dbprops to control log, metric, and trace shipping from OSIX hosts
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (56812, 'observability.logs.enabled', 1, 0, '^[01]$', 22, 'Enable log shipping via the OpenTelemetry mesh');
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (56813, 'observability.metrics.enabled', 1, 0, '^[01]$', 22, 'Enable metrics shipping via the OpenTelemetry mesh');
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (56814, 'observability.traces.enabled', 1, 0, '^[01]$', 22, 'Enable trace shipping via the OpenTelemetry mesh');

--changeset jve:1261
--comment: MON-3991: Update the default value of the observability dbprops to 1
--comment: observability.logs.enabled
UPDATE MSS.KEY SET MSS.KEY.STRING_DEFAULT='1' WHERE MSS.KEY.ID = 56812;
--comment: observability.metrics.enabled
UPDATE MSS.KEY SET MSS.KEY.STRING_DEFAULT='1' WHERE MSS.KEY.ID = 56813;
--comment: observability.traces.enabled
UPDATE MSS.KEY SET MSS.KEY.STRING_DEFAULT='1' WHERE MSS.KEY.ID = 56814;

--changeset rha:1262
--comment: MEP-2192: Prevent duplicate SANs
ALTER TABLE "CERTS"."SAN" ADD CONSTRAINT SAN_UV1 UNIQUE (CERTIFICATE_ID, CSR_ID, NAME);

--changeset nop:1263
--comment: SRE-526: Remove SRE tables
INSERT INTO MC."#JDO_PROPERTIES" ("KEY","VALUE") VALUES ('HOST_CONNECTION_STATUS_SRE.naming','none');
INSERT INTO MC."#JDO_PROPERTIES" ("KEY","VALUE") VALUES ('ISP_LINK_HISTORY_SRE.naming','none');
INSERT INTO MC."#JDO_PROPERTIES" ("KEY","VALUE") VALUES ('CONNECTION_INTERRUPT_CLOSED_SRE.naming','none');
INSERT INTO MC."#JDO_PROPERTIES" ("KEY","VALUE") VALUES ('CONNECTION_INTERRUPT_OPEN_SRE.naming','none');

--changeset nop:1264
--comment: SRE-526: drop constraint for monitoring server for thanos data
ALTER TABLE MC.MON_SERVER_CONNECTION DROP CONSTRAINT FK_MSC_MON_SERVER_ID;

--changeset nop:1265
--comment: SRE-526: drop constraint for monitoring server for thanos data
ALTER TABLE MSS.ISP_LINK DROP CONSTRAINT ISPLINK_FK16;
ALTER TABLE MSS.ISP_LINK DROP COLUMN ISP_LINK_STATUS_TYPE_ID_SRE;

--changeset jve:1266
--comment: FIX: switch off OTLP log shipping temporarily
--comment: observability.logs.enabled
UPDATE MSS.KEY SET MSS.KEY.STRING_DEFAULT='0' WHERE MSS.KEY.ID = 56812;

--changeset ssk:1267
--comment: FW-6120: allow reading audit applications
GRANT SELECT on MCAUDIT.APPLICATION TO SVC_FIREWALL_API;

--changeset nop:1268
--comment: SRE-594: Create DB users for automation use cases (dbwatcher)
CREATE USER "SVC_AUTOMATION_DBWATCHER" IDENTIFIED BY "xxxxxx" ACCOUNT LOCK
    DEFAULT TABLESPACE "USERS"
    TEMPORARY TABLESPACE "TEMP";
GRANT "MSS_LOGIN_USER" TO "SVC_AUTOMATION_DBWATCHER";
ALTER USER "SVC_AUTOMATION_DBWATCHER" DEFAULT ROLE "MSS_LOGIN_USER";
GRANT EXEMPT ACCESS POLICY TO "SVC_AUTOMATION_DBWATCHER";
GRANT SELECT ON TT.EVENT TO SVC_AUTOMATION_DBWATCHER;
GRANT SELECT ON TT.TICKET TO SVC_AUTOMATION_DBWATCHER;

--changeset nop:1269
--comment: SRE-594: Create DB users for automation use cases (workload user)
CREATE USER "SVC_AUTOMATION_EXECUTOR" IDENTIFIED BY "xxxxxx" ACCOUNT LOCK
    DEFAULT TABLESPACE "USERS"
    TEMPORARY TABLESPACE "TEMP";
GRANT "MSS_LOGIN_USER" TO "SVC_AUTOMATION_EXECUTOR";
ALTER USER "SVC_AUTOMATION_EXECUTOR" DEFAULT ROLE "MSS_LOGIN_USER";
GRANT EXEMPT ACCESS POLICY TO "SVC_AUTOMATION_EXECUTOR";
GRANT SELECT ON TT.EVENT TO SVC_AUTOMATION_EXECUTOR;
GRANT SELECT ON TT.TICKET TO SVC_AUTOMATION_EXECUTOR;
GRANT EXECUTE ON TT.EVENT_INTERFACE TO SVC_AUTOMATION_EXECUTOR;
GRANT INSERT ON TT.EVENT TO SVC_AUTOMATION_EXECUTOR;

--changeset isa:1270
--comment: FW-5337: remove hotspot dbprops
delete from mss.VALUE where KEY_ID>=2594 and key_id<=2604;
delete from mss.VALUE where KEY_ID in (3768, 3907, 3908, 5170, 5776, 8219);

DELETE FROM MSS."KEY" k WHERE k.NAME = 'hotspot' AND k.ID = 2594;
DELETE FROM MSS."KEY" k WHERE k.NAME = 'hotspot.loginhostname' AND k.ID = 2595;
DELETE FROM MSS."KEY" k WHERE k.NAME = 'hotspot.mobileagents' AND k.ID = 2596;
DELETE FROM MSS."KEY" k WHERE k.NAME = 'hotspot.proxyserver' AND k.ID = 2597;
DELETE FROM MSS."KEY" k WHERE k.NAME = 'hotspot.radiussecret' AND k.ID = 2598;
DELETE FROM MSS."KEY" k WHERE k.NAME = 'hotspot.timeout.absolute' AND k.ID = 2599;
DELETE FROM MSS."KEY" k WHERE k.NAME = 'hotspot.timeout.relative' AND k.ID = 2600;
DELETE FROM MSS."KEY" k WHERE k.NAME = 'hotspot.vpnservers' AND k.ID = 2601;
DELETE FROM MSS."KEY" k WHERE k.NAME = 'hotspot.wlanif' AND k.ID = 2602;
DELETE FROM MSS."KEY" k WHERE k.NAME = 'hotspot.forwarderzones' AND k.ID = 2603;
DELETE FROM MSS."KEY" k WHERE k.NAME = 'hotspot.logintokenfield' AND k.ID = 2604;
DELETE FROM MSS."KEY" k WHERE k.NAME = 'hotspot.vpnservers.nocaptive' AND k.ID = 3768;
DELETE FROM MSS."KEY" k WHERE k.NAME = 'hotspot.ttl' AND k.ID = 3907;
DELETE FROM MSS."KEY" k WHERE k.NAME = 'hotspot.ttl.accept' AND k.ID = 3908;
DELETE FROM MSS."KEY" k WHERE k.NAME = 'hotspot.radiusserver' AND k.ID = 5170;
DELETE FROM MSS."KEY" k WHERE k.NAME = 'rpdb.internaldefault.hotspotexit' AND k.ID = 5776;
DELETE FROM MSS."KEY" k WHERE k.NAME = 'hotspot.wpad' AND k.ID = 8219;

--changeset ogl:1271 contextFilter:dummyPasswords
ALTER USER "SVC_AUTOMATION_DBWATCHER" IDENTIFIED BY "password" ACCOUNT UNLOCK;
ALTER USER "SVC_AUTOMATION_EXECUTOR" IDENTIFIED BY "password" ACCOUNT UNLOCK;

--changeset rha:1272
--comment MEP-2200: Create service type Proxy CA / 400
INSERT INTO CERTS.CERTIFICATE_SCOPE_TYPE(id, name, description) values (400, 'proxy-ca-tls', 'Secure Web Gateway TLS interception');

--changeset rha:1273
--comment: MEP-2201: retract write access to master data
REVOKE INSERT,UPDATE,DELETE on CERTS.CERTIFICATE_SCOPE_TYPE from SVC_CONIFER;

--changeset rha:1274
--comment: MEP-2202: remove service type email quarantine from master data
DELETE FROM CERTS.CERTIFICATE_SCOPE_TYPE WHERE id = 210 AND name = 'mail-quarantine';

--changeset ssk:1275
--comment: FW-5163: remove obsolete and unused dbprop fw.log.legacy
DELETE FROM MSS.KEY WHERE name='fw.log.legacy';

--changeset gul:1276
--comment: WAN-2609: Add new DB Prop t2ee.tunnel_local_proxy_traffic
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (56820, 't2ee.tunnel_local_proxy_traffic', 1, 0, '^[01]$', 22, 'Enable routing of local Proxy traffic though the t2ee tunnel');

--changeset djg:1277
--comment: MON-4015: Set default=1 for dbprop migrate.2023.fw.hitscount
UPDATE mss.KEY set string_default='1' where name='migrate.2023.fw.hitscount';

--changeset nop:1278
--comment: SRE-421: Drop SRE tables
DROP TABLE MC.CONNECTION_INTERRUPT_CLOSED_SRE;
DROP TABLE MC.CONNECTION_INTERRUPT_OPEN_SRE;
DROP TABLE MC.HOST_CONNECTION_STATUS_SRE;
DROP TABLE MC.ISP_LINK_HISTORY_SRE;
DROP TABLE MC.MON_SERVER_CONNECTION_SRE;

--changeset rha:1279
--comment: MEP-2195: allow fast lookup of embedded intermediate and root certificates by fingerprints
CREATE TABLE CERTS.CERTIFICATE_INDEX
(
  ID NUMBER(11) NOT NULL,
  CERTIFICATE_ID NUMBER(11) NOT NULL,
  FINGERPRINT VARCHAR2(64) NOT NULL,
  CONSTRAINT CERTIFICATE_INDEX_PK PRIMARY KEY (ID) ENABLE,
  CONSTRAINT CERTIFICATE_INDEX_UK1 UNIQUE (FINGERPRINT, CERTIFICATE_ID) ENABLE,
  CONSTRAINT "CERTIFICATE_INDEX_FK1" FOREIGN KEY ("CERTIFICATE_ID") REFERENCES CERTS.CERTIFICATE (ID) ON DELETE CASCADE ENABLE
);
--changeset rha:1280
CREATE SEQUENCE CERTS.CERTIFICATE_INDEX_SEQ;

GRANT SELECT,INSERT,DELETE on CERTS.CERTIFICATE_INDEX to SVC_CONIFER;
GRANT SELECT on CERTS.CERTIFICATE_INDEX_SEQ to SVC_CONIFER;

INSERT INTO certs."#JDO_PROPERTIES" (key, value) values ('CERTIFICATE_INDEX.naming', 'none');

--changeset lok:1281
--comment: DB-1987: Add new audit record_type for file create / mutate / delete
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID) VALUES
    (372, 'File created', 'file_created', 'The file did not exist and was successfully created.', 1);
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID) VALUES
    (373, 'File modified', 'file_modified', 'The file did exist and was overwritten.', 1);
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID) VALUES
    (374, 'File deleted', 'file_deleted', 'The file did exist and was deleted.', 1);

--changeset thw:1282
--comment: Cleanup of dbprop
DELETE FROM MSS.VALUE v where v.key_id = 56745;
DELETE FROM MSS.KEY WHERE name='migrate.node_exporter.emergency_turnoff';

--changeset lok:1283
--comment: DB-1987: Add new audit record_type for wanbb (teridion)
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID) VALUES
    (375, 'WanBB created', 'wanbb_created', 'The WanBB did not exist and was successfully created.', 1);
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID) VALUES
    (376, 'WanBB modified', 'wanbb_modified', 'The WanBB did exist and was overwritten.', 1);
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID) VALUES
    (377, 'WanBB deleted', 'wanbb_deleted', 'The WanBB did exist and was deleted.', 1);

--changeset cwa:1284
--comment: MC-26766: Add BGP_HUB_PRIORITY field to VPN members
alter table VPN.VPN_MEMBER add BGP_HUB_PRIORITY NUMBER(10);
comment on column VPN.VPN_MEMBER.BGP_HUB_PRIORITY is 'Priority in a BGP Hub, with 1 being the highest priority.';

--changeset lok:1285
--comment: DB-2008: manage ping groups from api
GRANT SELECT,INSERT,UPDATE,DELETE on MSS.PING_IP to SVC_CONIFER;
GRANT SELECT,INSERT,UPDATE,DELETE on MSS.PING_IP_GROUP to SVC_CONIFER;
GRANT SELECT on MSS.PING_IP_SEQ to SVC_CONIFER;
GRANT SELECT on MSS.PING_IP_GROUP_SEQ to SVC_CONIFER;

--changeset mlo:1282
--comment: MC-26876: Extend login field to be 250 chars
--comment: drop indices on login field before increasing size
drop index AUTH.U_IDX_LOGIN_LOWER_LOGIN_HOMEAUTHHOST;
drop index AUTH.U_LOGIN_LOGIN_COMPANY_NOCASE;
--comment: increase login field size
alter table AUTH.LOGIN modify LOGIN VARCHAR2(250);
--comment: recreate indices on login field
create unique index AUTH.U_IDX_LOGIN_LOWER_LOGIN_HOMEAUTHHOST
    on AUTH.LOGIN (LOWER("LOGIN"), HOMEAUTHHOST_ID);
create unique index AUTH.U_LOGIN_LOGIN_COMPANY_NOCASE
    on AUTH.LOGIN (LOWER("LOGIN"), COMPANY_ID);

--changeset nis:1283
--comment: MC-26895: Add a new permission for API Users
INSERT INTO AUTH.USER_ROLE (ID, NAME, DESCRIPTION, IS_INTERNAL, USER_ROLE_SCOPE_TYPE_ID)
VALUES (2012, 'mc-cust-api-users-mgmt', 'Api Users Management', 0, 1);
INSERT INTO AUTH.user_role2required_role (USER_ROLE_ID, REQUIRED_USER_ROLE_ID)
VALUES (2012, 1003);

--changeset rha:1284
--comment: MEP-2220: rename fingerprint column to reflect specific purpose
alter table CERTS.CERTIFICATE_INDEX rename column fingerprint to subject_key_id;

--changeset sis:1286
--comment: OSAP-810: change default value of zitadel dbprop
update mss.key k
set k.STRING_DEFAULT='1'
where k.id=56700
and k.name='zitadel';

--changeset ogl:1287
--comment: DB-2009: permissions for service creation from API
grant insert,delete on mss.SERVICE to SVC_CONIFER;
grant select on mss.SERVICE_SEQ to SVC_CONIFER;
grant insert on mc.SERVICE_CONN_SLA_CONFIG to SVC_CONIFER;
grant select on mc.SERVICE_CONN_SLA_CONFIG_SEQ to SVC_CONIFER;
grant select on mss.PLATFORM_TYPE to SVC_CONIFER;
grant select on mss.SERVICE_LEVEL to SVC_CONIFER;
grant select on mss.CLOUD_REGION_INSTANCE to SVC_CONIFER;
grant select on mc.CONN_SLA_CLASS to SVC_CONIFER;

--changeset ogl:1288
--comment: DB-2044: user for copilot team
CREATE USER "SVC_COPILOT" IDENTIFIED BY "xxxxxx" ACCOUNT LOCK
  DEFAULT TABLESPACE "USERS"
  TEMPORARY TABLESPACE "TEMP";
GRANT "MSS_LOGIN_USER" TO "SVC_COPILOT";

ALTER USER "SVC_COPILOT" DEFAULT ROLE "MSS_LOGIN_USER";

GRANT EXEMPT ACCESS POLICY TO "SVC_COPILOT";

grant select on mss.ADDRESS TO "SVC_COPILOT";
grant select on mss.HOST TO "SVC_COPILOT";
grant select on mss.CITY TO "SVC_COPILOT";
grant select on mss.ISP_LINK TO "SVC_COPILOT";
grant select on mss.INTERFACE2ISP_LINK TO "SVC_COPILOT";
grant select on mss.INTERFACE TO "SVC_COPILOT";
grant select on mss.TIME_ZONE_DATA TO "SVC_COPILOT";
grant select on mss.COUNTRY TO "SVC_COPILOT";
grant select on stop.COMPANY TO "SVC_COPILOT";
grant select on tt.EVENT TO "SVC_COPILOT";
grant select on tt.HOST2SERVICE_WINDOW TO "SVC_COPILOT";
grant select on tt.TICKET TO "SVC_COPILOT";
grant select on tt.SERVICE_WINDOW TO "SVC_COPILOT";
grant select on tt.CUST_MAINTENANCE_WINDOW TO "SVC_COPILOT";
grant select on tt.MAINTENANCE_WINDOW TO "SVC_COPILOT";
grant select on tt.ROLLOUT_WINDOW TO "SVC_COPILOT";

--changeset ogl:1289 contextFilter:dummyPasswords
alter user SVC_COPILOT identified by "password" account unlock;

--changeset ogl:1290
--comment: DB-2011: delete service
grant delete on mss.service to SVC_CONIFER;
grant delete on mc.SERVICE_CONN_SLA_CONFIG to SVC_CONIFER;

--changeset phm:1291
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM dba_users WHERE username='osixinfo'
CREATE USER "OSIXINFO" IDENTIFIED BY "xxxxxx" ACCOUNT LOCK
DEFAULT TABLESPACE "USERS"
TEMPORARY TABLESPACE "TEMP";

--changeset phm:1292
--comment: MON-3976: add osixinfo table similar to guma2.osix_info
CREATE TABLE "OSIXINFO"."OSIXINFO"
  (	"ID" NUMBER(10,0),
"KEY" VARCHAR2(128 BYTE),
"VALUE" VARCHAR2(128 BYTE),
"CHANGE_TIMESTAMP" TIMESTAMP (6) WITH TIME ZONE DEFAULT SYSTIMESTAMP,
"HARDWARE_ID" NUMBER(10,0)
  ) ;

CREATE UNIQUE INDEX "OSIXINFO"."OSIXINFO_PK" ON "OSIXINFO"."OSIXINFO" ("ID");
ALTER TABLE "OSIXINFO"."OSIXINFO" ADD CONSTRAINT "OSIXINFO_PK" PRIMARY KEY ("ID");
ALTER TABLE "OSIXINFO"."OSIXINFO" MODIFY ("ID" NOT NULL ENABLE);
ALTER TABLE "OSIXINFO"."OSIXINFO" MODIFY ("KEY" NOT NULL ENABLE);
ALTER TABLE "OSIXINFO"."OSIXINFO" MODIFY ("CHANGE_TIMESTAMP" NOT NULL ENABLE);
GRANT REFERENCES ON "MSS"."HARDWARE" TO "OSIXINFO";
ALTER TABLE "OSIXINFO"."OSIXINFO" ADD CONSTRAINT "OSIXINFO_FK1" FOREIGN KEY ("HARDWARE_ID")
	  REFERENCES "MSS"."HARDWARE" ("ID") ON DELETE CASCADE DEFERRABLE ENABLE;

CREATE SEQUENCE OSIXINFO.OSIXINFO_SEQ;

--changeset phm:1293
--comment: MON-3976: system, object grants for osixinfo
GRANT SELECT ON "OSIXINFO"."OSIXINFO" TO "BIREADER";
GRANT SELECT ON "OSIXINFO"."OSIXINFO" TO "GETNODES";
GRANT SELECT ON "OSIXINFO"."OSIXINFO" TO "GUMA_SERVER";
GRANT DELETE ON "OSIXINFO"."OSIXINFO" TO "GUMA_SERVER";
GRANT INSERT ON "OSIXINFO"."OSIXINFO" TO "GUMA_SERVER";
GRANT UPDATE ON "OSIXINFO"."OSIXINFO" TO "GUMA_SERVER";
GRANT SELECT ON "OSIXINFO"."OSIXINFO_SEQ" TO "GUMA_SERVER";

--changeset phm:1294
--comment: MON-3976: osixinfo consumer still used guma_server user, give him his own user
CREATE USER "SVC_BALUOSIXINFO" IDENTIFIED BY "xxxxxx" ACCOUNT LOCK
  DEFAULT TABLESPACE "USERS"
  TEMPORARY TABLESPACE "TEMP";
GRANT "MSS_LOGIN_USER" TO "SVC_BALUOSIXINFO";

ALTER USER "SVC_BALUOSIXINFO" DEFAULT ROLE "MSS_LOGIN_USER";
GRANT INSERT ON "GUMA2"."OSIX_INFO" TO "SVC_BALUOSIXINFO";
GRANT UPDATE ON "GUMA2"."OSIX_INFO" TO "SVC_BALUOSIXINFO";
GRANT INSERT ON "OSIXINFO"."OSIXINFO" TO "SVC_BALUOSIXINFO";
GRANT UPDATE ON "OSIXINFO"."OSIXINFO" TO "SVC_BALUOSIXINFO";

GRANT SELECT ON "OSIXINFO"."OSIXINFO_SEQ" TO "SVC_BALUOSIXINFO";

--changeset phm:1295 contextFilter:dummyPasswords
alter user SVC_BALUOSIXINFO identified by "password" account unlock;

--changeset sym:1291
--connect ORE-304: Create new OSSE region in Central India
INSERT INTO mss.cloud_region_instance (ID, INTERNAL_CODE, PROVIDER, REGION, DISPLAY_NAME, CLUSTER_URL, LATITUDE_DIRECTION, LATITUDE_DEGREES, LATITUDE_MINUTES, LATITUDE_SECONDS, LONGITUDE_DIRECTION, LONGITUDE_DEGREES, LONGITUDE_MINUTES, LONGITUDE_SECONDS)
VALUES (8, 'azu-centralindia-1', 'azure', 'centralindia', 'SSE RegioHub 1 on Azure centralindia', 'https://osse-prod-azu-centralindia-1-hr3n0kef.hcp.centralindia.azmk8s.io', 'N', '18', '30', '51', 'E', '73', '51', '51');

--changeset rse:1297
--comment: CONF-3469: Add mgmtserver dbprop for UBS jump hosts
INSERT INTO MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
VALUES (56830, 'mgmtserver.sshgateway.ubs', 1, '0', '^[01]$', NULL, 'management host with SSH gateway functionality for UBS ("UBS jump host")');

--changeset ogl:1298 endDelimiter:/
--comment: DB-2020: remove old SANG jobs
BEGIN
  for r in (select 1 from SYS.DBA_SCHEDULER_JOBS where OWNER='MC' and JOB_NAME='CHECK_MONITORING_SERVERS') loop
  DBMS_SCHEDULER.DROP_JOB(job_name => '"MC"."CHECK_MONITORING_SERVERS"',
                          defer => false,
                          force => true);
  end loop;
END;
/

--changeset ogl:1299 endDelimiter:/
--comment: DB-2020: remove old SANG jobs
BEGIN
  for r in (select 1 from SYS.DBA_SCHEDULER_JOBS where OWNER='MC' and JOB_NAME='CLEANUP_OLD_CONNECTION_ENTRIES') loop
  DBMS_SCHEDULER.DROP_JOB(job_name => '"MC"."CLEANUP_OLD_CONNECTION_ENTRIES"',
                          defer => false,
                          force => true);
  end loop;
END;
/

--changeset ogl:1300
--comment: DB-2020: remove dead code
DROP PROCEDURE mc.monitor_monitoring_servers;

--changeset ogl:1301
--comment: DB-2020: remove dead code
DROP PROCEDURE mc.remove_old_connection_entries;

--changeset ogl:1302
--comment: MON-3976: permissions for schema owner
GRANT "MSS_SCHEMA_USER" TO osixinfo;
ALTER USER osixinfo DEFAULT ROLE "MSS_SCHEMA_USER";
ALTER USER osixinfo QUOTA UNLIMITED ON "USERS";

--changeset phm:1303
--comment: MON-3976: add missing grants for determining current state of db
GRANT SELECT ON "GUMA2"."OSIX_INFO" TO "SVC_BALUOSIXINFO";
GRANT SELECT ON "OSIXINFO"."OSIXINFO" TO "SVC_BALUOSIXINFO";
GRANT SELECT ON "OSIXINFO"."OSIXINFO" TO "GUMA_SERVER";

--changeset rha:1304
--comment: MEP-2240 prepare certtool for MEP SAML certificates
INSERT INTO CERTS.CERTIFICATE_SCOPE_TYPE (id, name, description) VALUES (110, 'mep-saml', 'Mobile Entry Point SAML authentication');

--changeset mlo:1305
--comment: MC-26926: add unmigrate record type value
INSERT INTO mcaudit.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID)
values (378, 'Login OIDC Unmigrated', 'login_oidc_unmigrated', 'Login was unmigrated from OIDC', 2);

--changeset phm:1306
--comment: MON-3976: add missing grants for receiving the hardware id
GRANT SELECT ON "MSS"."HOST" TO "SVC_BALUOSIXINFO";
GRANT SELECT ON "MSS"."HARDWARE" TO "SVC_BALUOSIXINFO";

--changeset ogl:1307
--comment: DB-2010: permissions for host creation
grant select on mss.OPERATING_SYSTEM to SVC_CONIFER;
grant select on mss.HARDWARE to SVC_CONIFER;
grant select on mss.HARDWARE_LIFECYCLE_ITEM to SVC_CONIFER;
grant insert on mss.HOST2SERVICE to SVC_CONIFER;

--changeset ogl:1308
--comment: DB-2059: permissions for hardware creation
grant select on mss.HARDWARE_SEQ to SVC_CONIFER;
grant insert,update,delete on mss.HARDWARE to SVC_CONIFER;
grant select on mss.HARDWARE_LIFECYCLE_ITEM_SEQ to SVC_CONIFER;
grant insert on mss.HARDWARE_LIFECYCLE_ITEM to SVC_CONIFER;

--changeset rse:1309
--comment: TRIVIAL: Remove traceroute nightmare from PLSQL code
DROP PROCEDURE mc.traceroute;

--changeset phm:1310
-- comment: MON-4034: permissions for get the next ID
GRANT SELECT ON "GUMA2"."OSIX_INFO_SEQ" TO "SVC_BALUOSIXINFO";

--changeset jah:1311
--comment: DNS-426: Change 'resolver' dbprop default value to 1
update mss.key k
set k.string_default='1'
where k.name='resolver';

--changeset jah:1312
--comment: DNS-426: Change 'named' dbprop default value to 1
update mss.key k
set k.string_default='1'
where k.name='named';

--changeset jah:1313
--comment: DNS-426: Change 'resolver.domains' dbprop default value to open.ch
update mss.key k
set k.string_default='open.ch'
where k.name='resolver.domains';

--changeset nop:1314
--comment: SRE-612: Give greants to automation user to interact with tickets and events
GRANT UPDATE ON TT.EVENT TO SVC_AUTOMATION_EXECUTOR;
GRANT INSERT ON TT.TICKET TO SVC_AUTOMATION_EXECUTOR;
GRANT UPDATE ON TT.TICKET TO SVC_AUTOMATION_EXECUTOR;

--changeset ogl:1315
--comment: DB-2013: grant delete host privis
grant update,delete on mss.HOST to SVC_CONIFER;
grant delete on mss.HOST2SERVICE to SVC_CONIFER;
grant delete on mc.HOST_MAINTENANCE_HISTORY to SVC_CONIFER;
grant delete on mss.HARDWARE_LIFECYCLE_ITEM to SVC_CONIFER;

--changeset ogl:1316
--comment: DB-2013: grant delete hosts privis
grant select,insert on mss.DECOMM_HOST to SVC_CONIFER;
grant select on fw.IP_GROUP_MEMBER to SVC_CONIFER;
grant select on fw.IP_GROUP to SVC_CONIFER;
grant execute on TT.TICKET_INTERFACE to SVC_CONIFER;
grant update on TT.TICKET to SVC_CONIFER;

--changeset ogl:1317
--comment: DB-2013: grant delete hosts privis
grant select on guma2.EXTERNAL_SENSOR to SVC_CONIFER;

--changeset ogl:1318
--comment: DB-2013: grant delete ISPLink privis
grant delete on mss.ISP_LINK to SVC_CONIFER;
grant delete on mss.INTERFACE2ISP_LINK to SVC_CONIFER;
grant delete on mss.INTERFACE to SVC_CONIFER;
grant select on tt.EVENT_NOTIFICATION to SVC_CONIFER;
grant select on tt.EVENT_NOTIFICATION_TYPE to SVC_CONIFER;

--changeset nis:1319
--comment: Allows ticketing api to create service windows
grant select ON TT.MAINTENANCEWINDOW_SEQ TO SVC_API_TICKETING;
grant select ON TT.ROLLOUTWINDOW_SEQ TO SVC_API_TICKETING;
grant select ON TT.SERVICEWINDOW_SEQ TO SVC_API_TICKETING;

--changeset dmg:1320
--comment: OSAP-840: Add new DB Prop migrate.zitadel.mep
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (56831, 'migrate.zitadel.mep', 2, 0, '^[01234]$', NULL, 'Specifies if MEP for the company was migrated to Zitadel');

--changeset nop:1321
--comment: Allows ticketing api to create service windows
GRANT EXECUTE ON TT.TICKET_INTERFACE TO SVC_AUTOMATION_EXECUTOR;

--changeset ngl:1322
--comment: Allows mc-automation to create maintenance windows
GRANT INSERT ON TT.SERVICE_WINDOW TO SVC_AUTOMATION_EXECUTOR;
GRANT INSERT ON TT.HOST2SERVICE_WINDOW TO SVC_AUTOMATION_EXECUTOR;
GRANT INSERT ON TT.MAINTENANCE_WINDOW TO SVC_AUTOMATION_EXECUTOR;
GRANT SELECT ON TT.SERVICEWINDOW_SEQ TO SVC_AUTOMATION_EXECUTOR;
GRANT SELECT ON TT.EVENT_SEQUENCE TO SVC_AUTOMATION_EXECUTOR;

--changeset ngl:1323
--comment: Allows mc-automation to select maintenance windows
GRANT SELECT ON TT.SERVICE_WINDOW TO SVC_AUTOMATION_EXECUTOR;
GRANT SELECT ON TT.HOST2SERVICE_WINDOW TO SVC_AUTOMATION_EXECUTOR;
GRANT SELECT ON TT.MAINTENANCE_WINDOW TO SVC_AUTOMATION_EXECUTOR;

--changeset ngl:1324
--comment: Allows mc-automation to select maintenance windows seq
GRANT SELECT ON TT.MAINTENANCEWINDOW_SEQ TO SVC_AUTOMATION_EXECUTOR;

--changeset ogl:1325
--comment: Grants for host deletion
grant delete on mc.CONNECTION_INTERRUPT_CLOSED to SVC_CONIFER;
grant delete on mc.CONNECTION_INTERRUPT_OPEN to SVC_CONIFER;
grant insert,delete on mss.INTERFACE2ISP_LINK to SVC_CONIFER;

--changeset phm:1326
--comment: Create views for mssquery usage
-- heartbeat.baseimage
CREATE OR REPLACE FORCE VIEW OSIXINFO.V_FIRMWAREBASE AS 
  SELECT 
    value as firmware_base, 
    hardware_id as hardware_id,
    change_timestamp as change_timestamp
  FROM osixinfo.osixinfo 
  WHERE key='firmwareBase';

-- heartbeat.is_master
CREATE OR REPLACE FORCE VIEW OSIXINFO.V_HOSTCLUSTERSTATE AS 
  SELECT 
    value as host_cluster_state, 
    hardware_id as hardware_id,
    change_timestamp as change_timestamp
  FROM osixinfo.osixinfo 
  WHERE key='hostClusterState';

-- heartbeat.build
CREATE OR REPLACE FORCE VIEW OSIXINFO.V_IMAGE AS 
  SELECT 
    value as image, 
    hardware_id as hardware_id,
    change_timestamp as change_timestamp
  FROM osixinfo.osixinfo 
  WHERE key='image';

-- heartbeat.macaddr
CREATE OR REPLACE FORCE VIEW OSIXINFO.V_HARDWARE AS 
  SELECT 
    value as hardware, 
    hardware_id as hardware_id,
    change_timestamp as change_timestamp
  FROM osixinfo.osixinfo 
  WHERE key='hardware';

-- heartbeat.version
CREATE OR REPLACE FORCE VIEW OSIXINFO.V_FIRMWARE AS 
  SELECT 
    value as firmware, 
    hardware_id as hardware_id,
    change_timestamp as change_timestamp
  FROM osixinfo.osixinfo 
  WHERE key='firmware';

-- heartbeat.log_update
CREATE OR REPLACE FORCE VIEW OSIXINFO.V_LAST_UPDATE AS 
  SELECT 
    value as last_update, 
    hardware_id as hardware_id,
    change_timestamp as change_timestamp
  FROM osixinfo.osixinfo 
  WHERE key='last_update';

GRANT SELECT ON "OSIXINFO"."V_FIRMWAREBASE" TO "GETNODES";
GRANT SELECT ON "OSIXINFO"."V_HOSTCLUSTERSTATE" TO "GETNODES";
GRANT SELECT ON "OSIXINFO"."V_IMAGE" TO "GETNODES";
GRANT SELECT ON "OSIXINFO"."V_HARDWARE" TO "GETNODES";
GRANT SELECT ON "OSIXINFO"."V_FIRMWARE" TO "GETNODES";
GRANT SELECT ON "OSIXINFO"."V_LAST_UPDATE" TO "GETNODES";

--changeset ogl:1327
--comment: DB-2011: delete local rules
grant select,delete on fw.SUB_SECTION to SVC_CONIFER;
grant delete on fw.RULE2TICKET to SVC_CONIFER;
grant select,delete on fw.RULE to SVC_CONIFER;

--changeset mta:1328
--comment: WAN-2238: Add new DB Prop qos.exclude_routing
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (56840, 'qos.exclude_routing', 1, '0', '^[01]$', NULL, 'Do not apply any bandwidth control on routing traffic');

--changeset phm:1329
--comment: add host_id field to views when available
GRANT SELECT ON "MSS"."HOST" TO "OSIXINFO";

-- heartbeat.baseimage
CREATE OR REPLACE FORCE VIEW OSIXINFO.V_FIRMWAREBASE AS
  SELECT
    osixinfo.value as firmware_base,
    osixinfo.hardware_id hardware_id,
    osixinfo.change_timestamp change_timestamp,
    h.id host_id
  FROM osixinfo.osixinfo
  JOIN
    MSS.HARDWARE hardware ON (osixinfo.hardware_id = hardware.id)
  LEFT JOIN
    MSS.HOST h ON (hardware.id = h.hardware_id)
  WHERE osixinfo.key='firmwareBase';

-- heartbeat.is_master
CREATE OR REPLACE FORCE VIEW OSIXINFO.V_HOSTCLUSTERSTATE AS
  SELECT
    osixinfo.value host_cluster_state,
    osixinfo.hardware_id hardware_id,
    osixinfo.change_timestamp change_timestamp,
    h.id host_id
  FROM osixinfo.osixinfo
  JOIN
    MSS.HARDWARE hardware ON (osixinfo.hardware_id = hardware.id)
  LEFT JOIN
    MSS.HOST h ON (hardware.id = h.hardware_id)
  WHERE osixinfo.key='hostClusterState';

-- heartbeat.build
CREATE OR REPLACE FORCE VIEW OSIXINFO.V_IMAGE AS
  SELECT
    osixinfo.value image,
    osixinfo.hardware_id hardware_id,
    osixinfo.change_timestamp change_timestamp,
    h.id host_id
  FROM osixinfo.osixinfo
  JOIN
    MSS.HARDWARE hardware ON (osixinfo.hardware_id = hardware.id)
  LEFT JOIN
    MSS.HOST h ON (hardware.id = h.hardware_id)
  WHERE osixinfo.key='image';

-- heartbeat.macaddr
CREATE OR REPLACE FORCE VIEW OSIXINFO.V_HARDWARE AS
  SELECT
    osixinfo.value hardware,
    osixinfo.hardware_id hardware_id,
    osixinfo.change_timestamp change_timestamp,
    h.id host_id
  FROM osixinfo.osixinfo
  JOIN
    MSS.HARDWARE hardware ON (osixinfo.hardware_id = hardware.id)
  LEFT JOIN
    MSS.HOST h ON (hardware.id = h.hardware_id)
  WHERE osixinfo.key='hardware';

-- heartbeat.version
CREATE OR REPLACE FORCE VIEW OSIXINFO.V_FIRMWARE AS
  SELECT
    osixinfo.value firmware,
    osixinfo.hardware_id hardware_id,
    osixinfo.change_timestamp change_timestamp,
    h.id host_id
  FROM osixinfo.osixinfo
  JOIN
    MSS.HARDWARE hardware ON (osixinfo.hardware_id = hardware.id)
  LEFT JOIN
    MSS.HOST h ON (hardware.id = h.hardware_id)
  WHERE osixinfo.key='firmware';

-- heartbeat.log_update
CREATE OR REPLACE FORCE VIEW OSIXINFO.V_LAST_UPDATE AS
  SELECT
    osixinfo.value last_update,
    osixinfo.hardware_id hardware_id,
    osixinfo.change_timestamp change_timestamp,
    h.id host_id
  FROM osixinfo.osixinfo
  JOIN
    MSS.HARDWARE hardware ON (osixinfo.hardware_id = hardware.id)
  LEFT JOIN
    MSS.HOST h ON (hardware.id = h.hardware_id)
  WHERE osixinfo.key='last_update';

--changeset jho:1330
--comment: MX-4625: Clean up authentication dbprops - remove dbprops
delete from mss.value v
where v.KEY_ID in (select ID from mss.KEY
                   where NAME in ('postfix.dkim','postfix.dmarc','postfix.dmarc.log_only','postfix.restrictions.spf'));
delete from mss.key
where NAME in ('postfix.dkim','postfix.dmarc','postfix.dmarc.log_only','postfix.restrictions.spf');

--changeset phm:1331
--comment: fix last_update view's values

 CREATE OR REPLACE FORCE VIEW OSIXINFO.V_LAST_UPDATE AS
  SELECT
    osixinfo.change_timestamp last_update,
    osixinfo.hardware_id hardware_id,
    osixinfo.change_timestamp change_timestamp
  FROM osixinfo.osixinfo
  WHERE osixinfo.key='last_update';

--changeset phm:1332
--comment: remove host_id field as permissions get too broad

-- heartbeat.baseimage
CREATE OR REPLACE FORCE VIEW OSIXINFO.V_FIRMWAREBASE AS
  SELECT
    osixinfo.value firmware_base,
    osixinfo.hardware_id hardware_id,
    osixinfo.change_timestamp change_timestamp
  FROM osixinfo.osixinfo
  WHERE osixinfo.key='firmwareBase';

-- heartbeat.is_master
CREATE OR REPLACE FORCE VIEW OSIXINFO.V_HOSTCLUSTERSTATE AS
  SELECT
    osixinfo.value host_cluster_state,
    osixinfo.hardware_id hardware_id,
    osixinfo.change_timestamp change_timestamp
  FROM osixinfo.osixinfo
  WHERE osixinfo.key='hostClusterState';

-- heartbeat.build
CREATE OR REPLACE FORCE VIEW OSIXINFO.V_IMAGE AS
  SELECT
    osixinfo.value image,
    osixinfo.hardware_id hardware_id,
    osixinfo.change_timestamp change_timestamp
  FROM osixinfo.osixinfo
  WHERE osixinfo.key='image';

-- heartbeat.macaddr
CREATE OR REPLACE FORCE VIEW OSIXINFO.V_HARDWARE AS
  SELECT
    osixinfo.value hardware,
    osixinfo.hardware_id hardware_id,
    osixinfo.change_timestamp change_timestamp
  FROM osixinfo.osixinfo
  WHERE osixinfo.key='hardware';

-- heartbeat.version
CREATE OR REPLACE FORCE VIEW OSIXINFO.V_FIRMWARE AS
  SELECT
    osixinfo.value firmware,
    osixinfo.hardware_id hardware_id,
    osixinfo.change_timestamp change_timestamp
  FROM osixinfo.osixinfo
  WHERE osixinfo.key='firmware';

--changeset rse:1333
--comment: CONF-2856: Decommission obsolete dbprop dlclient.publicip
DELETE FROM MSS.KEY WHERE name='dlclient.publicip';

--changeset ogl:1334
--comment: DB-2074: permissions on ztna data
grant select on SVC_ZEROTRUST.ZTNA_TENANT to SVC_CONIFER;

--changeset ogl:1335
--comment: DB-2042: files have been migrated to github
drop table FILES.SCOPED_FILE;

--changeset ogl:1336
--comment: DB-2042: files have been migrated to github
drop sequence FILES.SCOPEDFILE_SEQ;

--changeset ogl:1337
--comment: DB-2042: files have been migrated to github
drop user FILES;

--changeset nis:1338
--comment: MC-27025: revoke unneeded grants for CONTRACT user
REVOKE ALL ON TT.EVENT_INTERFACE FROM CONTRACT;
REVOKE ALL ON TT.OSAG_TT_WEBRLS FROM CONTRACT;
REVOKE ALL ON TT.TICKET_INTERFACE FROM CONTRACT;
REVOKE ALL ON TT.EVENT FROM CONTRACT;
REVOKE ALL ON TT.EVENT_TYPE FROM CONTRACT;
REVOKE ALL ON TT.STATUS FROM CONTRACT;
REVOKE ALL ON TT.TICKET FROM CONTRACT;
REVOKE ALL ON TT.TICKET_TYPE FROM CONTRACT;

--changeset diw:1339
--comment: IDS-2781: Drop uniqueness constraint on teridion_id
ALTER TABLE WANBB.TERIDION_SITE DROP CONSTRAINT TERIDIONSITE_UN;

--changeset ogl:1340
--comment: missing perm
grant select on mss.DECOMM_HOST_SEQ to SVC_CONIFER;

--changeset jho:1341
--comment: MX-5023: Create authmilter migration dbprop
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (56841, 'migrate.mail.authmilter', 1, '0', '^[01]$', NULL, 'Switch from opendkim/opendmarc to authmilter');

--changeset nop:1342
--comment: SRE-637: Implememnt site criticality dbprop
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (56842, 'relmgmt.criticality', 4, 'normal', '^(normal|24x7|critical)$', NULL, 'Criticality value');

--changeset ogl:1343
--comment: DB-1780: add missing privs
grant select on mss.NAT_IIFACE_2_OIFACE to SVC_CONIFER;

--changeset phm:1344
--comment: MON-3977: allow osixinfo to execute hardware replacements
GRANT SELECT ON MSS.HARDWARE_LIFECYCLE_ITEM_SEQ TO OSIXINFO;
GRANT INSERT ON MSS.HARDWARE_LIFECYCLE_ITEM TO OSIXINFO;
GRANT SELECT ON MSS.HARDWARE_LIFECYCLE_ITEM TO OSIXINFO;
GRANT SELECT ON MSS.HARDWAREHISTORY_SEQ TO OSIXINFO;
GRANT INSERT ON MSS.HARDWARE_HISTORY TO OSIXINFO;
GRANT SELECT ON MSS.HARDWARE_HISTORY TO OSIXINFO;
GRANT SELECT ON MSS.HARDWARE_DISPOSAL_REASON TO OSIXINFO;
GRANT SELECT ON MSS.HARDWARE_TYPE TO OSIXINFO;
GRANT SELECT ON MSS.SERVICE_TYPE TO OSIXINFO;
GRANT SELECT ON MSS.SERVICE TO OSIXINFO;
GRANT SELECT ON STOP.CONTACT TO OSIXINFO;
GRANT SELECT ON STOP.COMPANY TO OSIXINFO;
GRANT UPDATE ON MSS.HARDWARE TO OSIXINFO;
GRANT UPDATE ON MSS.HOST TO OSIXINFO;
GRANT EXECUTE ON TT.EVENT_INTERFACE TO OSIXINFO;

--changeset phm:1345
--comment: DB-2111: allow conifer to access the HARDWARE_LC_STATE table
GRANT SELECT ON MSS.HARDWARE_LC_STATE TO SVC_CONIFER;

--changeset phm:1346
--comment: MON-3977: allow osixinfo to execute hardware replacements
GRANT EXECUTE ON TT.EVENT_INTERFACE TO SVC_BALUOSIXINFO;
GRANT SELECT ON MSS.HOST2SERVICE TO OSIXINFO;
GRANT SELECT ON MSS.HARDWARE TO OSIXINFO;

--changeset mlo:1345
--comment: TRIVIAL: increase todo_list_template description length
alter table TT.TODO_LIST_TEMPLATE modify DESCRIPTION VARCHAR2(4000);

--changeset ogl:1346
--comment: DB-2120: ticket evolution
CREATE USER "TICKETEVOLUTION" IDENTIFIED BY "xxxxxx" ACCOUNT LOCK
  DEFAULT TABLESPACE "USERS"
  TEMPORARY TABLESPACE "TEMP";
GRANT "MSS_SCHEMA_USER" TO "TICKETEVOLUTION";

ALTER USER "TICKETEVOLUTION" DEFAULT ROLE "MSS_SCHEMA_USER";
GRANT EXEMPT ACCESS POLICY TO "TICKETEVOLUTION";

GRANT SELECT on TT.TICKET to TICKETEVOLUTION;
GRANT SELECT on TT.STATUS to TICKETEVOLUTION;
GRANT SELECT on TT.TICKET_TYPE to TICKETEVOLUTION;
GRANT SELECT on TT.EVENT to TICKETEVOLUTION;

--changeset ogl:1347
--comment: DB-2120: ticket evolution
create table TICKETEVOLUTION.tickev (
                                      event_id integer not null,
                                      ticket_id integer not null,
                                      ticket_status varchar2(32),
                                      emergency_state varchar2(32),
                                      assigned_engineer varchar2(32),
                                      mcc_state varchar2(32),
                                      ticket_type varchar2(32),
                                      ticket_label varchar2(32),
                                      date_from date,
                                      date_to date,
                                      update_dt date default sysdate not null,
                                      deleted number(1) default 0 not null
);

--changeset ogl:1348
--comment: DB-2120: ticket evolution
create index i_tickev_tid on TICKETEVOLUTION.tickev(ticket_id, event_id);

--changeset ogl:1349
--comment: DB-2120: ticket evolution
create index i_tickev_upd on TICKETEVOLUTION.tickev(update_dt);

--changeset ogl:1350 endDelimiter:/
--comment: DB-2120: ticket evolution

CREATE OR REPLACE PACKAGE TICKETEVOLUTION.CALCULATOR IS
END CALCULATOR;
/

--changeset ogl:1351
--comment: DB-2120: ticket evolution
create table TICKETEVOLUTION.state (
  key varchar2(32),
  value_dt date not null
);

--changeset phm:1352 endDelimiter:/
--comment: MON-3977: create stub package for allowing svc_baluosixinfo to trigger hardware replacements
CREATE OR REPLACE PACKAGE OSIXINFO.OSAG_EXCEPTIONS IS
END OSIXINFO.OSAG_EXCEPTIONS;
/

CREATE OR REPLACE PACKAGE OSIXINFO.OSAG_HARDWARE IS
END OSIXINFO.OSAG_HARDWARE;
/

--changeset phm:1353
--comment: MON-3977: allow osixinfo to execute hardware replacements
GRANT EXECUTE ON OSIXINFO.OSAG_HARDWARE TO SVC_BALUOSIXINFO;

--changeset ogl:1354
--comment: let TICKETEVOLUTION use TS
ALTER USER "TICKETEVOLUTION" QUOTA UNLIMITED ON "USERS";

--changeset ogl:1355
--comment: DB-2120: grants
GRANT SELECT on TICKETEVOLUTION.TICKEV to BIREADER;

--changeset jve:1356
--comment: Ship firewall debug logs to Loki by default
--observability.logs.enabled
UPDATE MSS.KEY SET MSS.KEY.STRING_DEFAULT='1' WHERE MSS.KEY.ID = 56812;
--fw.log.loki
UPDATE MSS.KEY SET MSS.KEY.STRING_DEFAULT='1' WHERE MSS.KEY.ID = 56750;
--fw.log.debug.loki
UPDATE MSS.KEY SET MSS.KEY.STRING_DEFAULT='1' WHERE MSS.KEY.ID = 56751;

--changeset ogl:1357
--comment: DB-2136: access to CASB policy groups
grant select on prx.PRX_POLICY_GROUP to SVC_CONIFER;

--changeset rfr:1358
--comment: PRX-8217: remove samba and msint related dbprops
DELETE FROM MSS.KEY WHERE name like 'samba%' OR name='squid.auth.msint';

--changeset nis:1359
--comment: MC-27266: Cleanup unused users
REVOKE EXECUTE ON TT.TICKET_INTERFACE FROM DECOMM;
REVOKE EXECUTE ON TT.ESCALATION_INTERFACE FROM WEBSW;
REVOKE EXECUTE ON TT.EVENT_INTERFACE FROM WEBSW;
REVOKE EXECUTE ON TT.TICKET_INTERFACE FROM WEBSW;
REVOKE EXECUTE ON TT.ESCALATION_INTERFACE FROM REPORT;

--changeset ako:1360
--comment: NC-87: Add new DB Prop migrate.frrouting.integrated_config
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (56850, 'migrate.frrouting.integrated_config', 1, '0', '^[01]$', NULL, 'Enable the integrated config for frrouting');

--changeset ako:1361
--comment: NC-81: Add new DB Prop rps
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (56860, 'rps', 1, '0', '^[01]$', NULL, 'Enable Receive Packet Steering (RPS)');

--changeset jmj:1362
--comment: decommission dbprop drbd.interface
DELETE FROM MSS.KEY WHERE name='drbd.interface';

--changeset ogl:1363
--comment: DB-2114: use TUNNEL_SEQUENCE for t2ee tunnels
grant select on vpn.TUNNEL_SEQUENCE to SVC_CONIFER;

--changeset ogl:1364
--comment: DB-2120: move index to right owner
drop index i_tickev_tid;
create index TICKETEVOLUTION.i_tickev_tid on TICKETEVOLUTION.tickev(ticket_id, event_id);

--changeset ogl:1365
--comment: DB-2120: move index to right owner
drop index i_tickev_upd;
create index TICKETEVOLUTION.i_tickev_upd on TICKETEVOLUTION.tickev(update_dt);

--changeset dmg:1366
--comment: OSAP-903: remove migrate.zitadel
DELETE FROM MSS.KEY WHERE name='migrate.zitadel' OR name='migrate.zitadel.earlyaccess';

--changeset ogl:1367
--comment: DB-2151: add FK index to improve delete performance on the parent table
create index mail.IDX_DMARC_RR_FK4 on mail.DMARC_REPORT_RECORD(DMARC_REPORT_ID);

--changeset mlo:1368
--comment: MC-27291: user for users internal API
CREATE USER "SVC_USERS_INTERNAL_API" IDENTIFIED BY "xxxxxx" ACCOUNT LOCK
    DEFAULT TABLESPACE "USERS"
    TEMPORARY TABLESPACE "TEMP";

GRANT "MSS_LOGIN_USER" TO "SVC_USERS_INTERNAL_API";
ALTER USER "SVC_USERS_INTERNAL_API" DEFAULT ROLE "MSS_LOGIN_USER";
GRANT EXEMPT ACCESS POLICY TO "SVC_USERS_INTERNAL_API";

-- read company, read and update login and contacts
GRANT SELECT on stop.company to SVC_USERS_INTERNAL_API;
GRANT SELECT on auth.login to SVC_USERS_INTERNAL_API;
GRANT UPDATE on auth.login to SVC_USERS_INTERNAL_API;
GRANT SELECT on stop.contact to SVC_USERS_INTERNAL_API;
GRANT UPDATE on stop.contact to SVC_USERS_INTERNAL_API;
-- audit trail necessary permissions (create new audit trail entries)
GRANT SELECT ON MCAUDIT.RECORD_SEQ TO SVC_USERS_INTERNAL_API;
GRANT SELECT ON MCAUDIT.TRANSACTION_SEQ TO SVC_USERS_INTERNAL_API;
GRANT SELECT ON MCAUDIT.APPLICATION TO SVC_USERS_INTERNAL_API;
GRANT SELECT ON MCAUDIT.COMPONENT TO SVC_USERS_INTERNAL_API;
GRANT SELECT ON MCAUDIT.RECORD_TYPE TO SVC_USERS_INTERNAL_API;
GRANT SELECT ON MCAUDIT.SEVERITY TO SVC_USERS_INTERNAL_API;
GRANT SELECT ON MCAUDIT.SYSTEM TO SVC_USERS_INTERNAL_API;
GRANT SELECT ON MSS.OBJECT_TYPE TO SVC_USERS_INTERNAL_API;
GRANT SELECT ON MSS.FIELD_MAPPING TO SVC_USERS_INTERNAL_API;
GRANT SELECT ON MSS.FIELD_MAPPING_TYPE TO SVC_USERS_INTERNAL_API;
GRANT SELECT ON MCAUDIT.RECORD TO SVC_USERS_INTERNAL_API;
GRANT INSERT ON MCAUDIT.RECORD TO SVC_USERS_INTERNAL_API;
GRANT UPDATE ON MCAUDIT.RECORD TO SVC_USERS_INTERNAL_API;

--changeset mlo:1370 contextFilter:dummyPasswords
alter user SVC_USERS_INTERNAL_API identified by "password" account unlock;

--changeset ako:1368
--comment: NC-81: Add new DB Prop rps.mask
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (56870, 'rps.mask', 4, 'ffffffff,ffffffff', '^[0-9a-fA-F,]*$', NULL, 'RPS CPU mask');

--changeset ako:1369
--comment: NC-81: Add new DB Prop rps.interface
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (56880, 'rps.interface', 4, '@if_LOCAL_GRE', '^[@a-zA-Z][0-9a-zA-Z_ -]*$', NULL, 'RPS interfaces');

--changeset mlo:1371
--comment: MC-27291: permissions for contact_sync table
GRANT SELECT on stop.CONTACT_SYNC to SVC_USERS_INTERNAL_API;

--changeset nop:1372
--comment: SRE-652: permission to read from AUTH.LOGIN for SVC_AUTOMATION
GRANT SELECT on AUTH.LOGIN to SVC_AUTOMATION_DBWATCHER;

--changeset lok:1373
--comment: TRIVIAL: access to mail policy for mc-config-api
grant select on MAIL.CUSTOM_POLICY_LIST to SVC_CONIFER;
grant select on MAIL.CUSTOM_POLICY_LIST_VALUE to SVC_CONIFER;

--changeset nop:1374
--comment: SRE-645: temporary permissions to get timezone data (until config API supports it)
GRANT SELECT on MSS.TIME_ZONE_DATA to SVC_AUTOMATION_EXECUTOR;
GRANT SELECT on MSS.CITY to SVC_AUTOMATION_EXECUTOR;
GRANT SELECT on MSS.ADDRESS to SVC_AUTOMATION_EXECUTOR;

--changeset phm:1375
--comment: DB-2172: expose timezone information via mc config api
GRANT SELECT on MSS.TIME_ZONE_DATA to SVC_CONIFER;

--changeset msc:1376
--comment: NC-95: default rps mask should exclude cpu0
update mss.KEY
set string_default='ffffffff,fffffffe'
where name='rps.mask';

--changeset jve:1377
--comment: OB-21: set default value of `beats.forwarding.squid` to 0
UPDATE MSS.KEY SET MSS.KEY.STRING_DEFAULT='0' WHERE MSS.KEY.ID = 56875;

--changeset nis:1378
--comment: Allows ticketing api to create service windows
grant select ON TT.TICKET_SEQUENCE TO SVC_API_TICKETING;

--changeset ngl:1379
--comment: SRE-630: mc-automation needs mss.Host to map tz data
GRANT SELECT on MSS.HOST to SVC_AUTOMATION_EXECUTOR;

--changeset lok:1380
--comment: revert SRE-630: mc-automation needs mss.Host to map tz data
REVOKE SELECT on MSS.HOST from SVC_AUTOMATION_EXECUTOR;

--changeset msc:1381
--comment: NC-103: Add new DB Prop rps.vpn_peers
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (56890, 'rps.vpn_peers', 4, NULL, '^[0-9 ]*$', NULL, 'RPS on selected vpn peers');

--changeset lut:1382
--comment: Add new T2EE dbprop to route local DNS traffic through T2EE tunnels
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (56900, 't2ee.tunnel_local_dns_traffic', 1, '0', '^[01]$', 22, 'Enable routing of local DNS (bind) traffic though the t2ee tunnel')

--changeset sev:1383
--comment: MEP-2362: add new dbprop sslvpn.block.clientless
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (56910, 'sslvpn.block.clientless', 1, '0', '^[01]$', NULL, 'enable blocking requests of type clientless');

--changeset sev:1384
--comment: MEP-2365: add new dbprop sslvpn.block.failed_requests
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (56911, 'sslvpn.block.failed_requests', 1, '0', '^[01]$', NULL, 'enable blocking mechanism based on failed requests');

--changeset gip:1385
--comment: MX-5063: grant permissions on mail.CUSTOM_POLICY_LIST_VALUE to allow access for config API
grant select on mail.CUSTOM_POLICY_LIST_VALUE_SEQ to SVC_CONIFER;
grant insert,update,delete on MAIL.CUSTOM_POLICY_LIST_VALUE to SVC_CONIFER;

--changeset sev:1386
--comment: MEP-2367: change default of sslvpn.block features to 1
update mss.KEY set string_default='1' where name='sslvpn.block.clientless';
update mss.KEY set string_default='1' where name='sslvpn.block.failed_requests';

--changeset ogl:1387 endDelimiter:/
--comment: DB-2202: create sequence for cloud region instances
declare
  v_max integer;
begin
  begin
    select max(id)+1 into v_max from mss.CLOUD_REGION_INSTANCE;
  exception
    when no_data_found then
      v_max := 1;
  end;

  execute immediate 'create sequence mss.CLOUD_REGION_INSTANCE_SEQ START WITH '|| v_max;
end;
/

--changeset ogl:1388
--comment: DB-2202
create index mss.CLOUD_REGION_INSTANCE_U on mss.CLOUD_REGION_INSTANCE(INTERNAL_CODE);
grant select on mss.CLOUD_REGION_INSTANCE_SEQ to SVC_CONIFER;
grant insert,update,delete on mss.CLOUD_REGION_INSTANCE to SVC_CONIFER;

--changeset msc:1389
--comment: NC-121: update regex for rps.interface to match complex formats, allowing chars ,=/ but disallow -
update mss.KEY
set regexp='^$|@if_LOCAL_(GRE|ALLPHYS) ?|(peth|t[46]_)[0-9]+(\/rx[0-9]+)?(=[0-9a-f]{0,8}(,[0-9a-f]{0,8})?)? ?'
where name='rps.interface';

--changeset ogl:1390
--comment: improve TS alerting: ignore DKA's schema, notify is not critical, use TS size and percentage
update MCDB_CHECKS.CONSISTENCY_CHECKS
set statement='SELECT object_type, owner, object_name
FROM sys.dba_objects o
WHERE o.status = ''INVALID''
and o.OWNER not in (''DKA'')'
where check_key='SEL_invalid_objs';

update MCDB_CHECKS.CONSISTENCY_CHECKS
set check_group='default',
statement='select tablespace_name, size_gb, max_gb,
       (size_gb - free_gb) used_gb,
       free_gb,
       (max_gb - size_gb + free_gb) avail_gb,
       round(100*(max_gb - size_gb + free_gb)/max_gb, 2) avail_pct
from (
       select f.tablespace_name,
              sum(f.bytes/1024/1024/1024) size_gb,
              sum(greatest(f.maxbytes, f.bytes)/1024/1024/1024) max_gb,
              sum((select sum(s.bytes)/1024/1024/1024
                   from dba_free_space s
                   where s.tablespace_name = f.tablespace_name
                     and s.file_id = f.file_id
                   group by s.tablespace_name, s.file_id))  free_gb
       from dba_data_files f
where f.TABLESPACE_NAME not in (''UNDO'', ''TEMP'')
       group by f.tablespace_name)
where round(100*(max_gb - size_gb + free_gb)/max_gb, 2) between 5 and 2
and free_gb between 4 and 2'
where check_key='SEL_datafile_notify';

update MCDB_CHECKS.CONSISTENCY_CHECKS
set statement='select tablespace_name, size_gb, max_gb,
       (size_gb - free_gb) used_gb,
       free_gb,
       (max_gb - size_gb + free_gb) avail_gb,
       round(100*(max_gb - size_gb + free_gb)/max_gb, 2) avail_pct
from (
       select f.tablespace_name,
              sum(f.bytes/1024/1024/1024) size_gb,
              sum(greatest(f.maxbytes, f.bytes)/1024/1024/1024) max_gb,
              sum((select sum(s.bytes)/1024/1024/1024
                   from dba_free_space s
                   where s.tablespace_name = f.tablespace_name
                     and s.file_id = f.file_id
                   group by s.tablespace_name, s.file_id))  free_gb
       from dba_data_files f
where f.TABLESPACE_NAME not in (''UNDO'', ''TEMP'')
       group by f.tablespace_name)
where round(100*(max_gb - size_gb + free_gb)/max_gb, 2) < 2
and free_gb < 2'
where check_key='SEL_datafile_alert';

--changeset ogl:1391
--comment: MX-5064: add missing indexes
create index MAIL.I_CUSTOM_POLICY_LIST_VALUE_FK2  on MAIL.CUSTOM_POLICY_LIST_VALUE(LAST_MODIFIED_CONTACT_ID);

--changeset ogl:1392
--comment: MX-5064: add missing indexes
create index MAIL.I_CUSTOM_POLICY_LIST_VALUE_UN on MAIL.CUSTOM_POLICY_LIST_VALUE(CUSTOM_POLICY_LIST_ID, VALUE);

--changeset ogl:1393
--comment: MON-3976: ORM OSIXINFO
CREATE TABLE OSIXINFO."#JDO_PROPERTIES" (KEY VARCHAR2(400 BYTE) NOT NULL, VALUE VARCHAR2(400 BYTE) DEFAULT 'none', CONSTRAINT JDO_PROPERTIES_PK PRIMARY KEY (KEY));

--changeset ogl:1394
--comment: MON-3976: ORM OSIXINFO
insert into OSIXINFO."#JDO_PROPERTIES" (key, value)
values ('package.prefix', 'ch.open.mss.db.osixinfo');

insert into OSIXINFO."#JDO_PROPERTIES" (key, value)
values ('V_HOSTCLUSTERSTATE.fk.FK_VHOCLST', 'HARDWARE_ID:MSS.HARDWARE.ID');

insert into OSIXINFO."#JDO_PROPERTIES" (key, value)
values ('V_HOSTCLUSTERSTATE.naming.inverse.MSS.HARDWARE', 'hostClusterState');

--changeset ogl:1395
--comment: views need ID for ORM
-- heartbeat.baseimage
CREATE OR REPLACE FORCE VIEW OSIXINFO.V_FIRMWAREBASE AS
SELECT
  id,
  value as firmware_base,
  hardware_id as hardware_id,
  change_timestamp as change_timestamp
FROM osixinfo.osixinfo
WHERE key='firmwareBase';

-- heartbeat.is_master
CREATE OR REPLACE FORCE VIEW OSIXINFO.V_HOSTCLUSTERSTATE AS
SELECT
  id,
  value as host_cluster_state,
  hardware_id as hardware_id,
  change_timestamp as change_timestamp
FROM osixinfo.osixinfo
WHERE key='hostClusterState';

-- heartbeat.build
CREATE OR REPLACE FORCE VIEW OSIXINFO.V_IMAGE AS
SELECT
  id,
  value as image,
  hardware_id as hardware_id,
  change_timestamp as change_timestamp
FROM osixinfo.osixinfo
WHERE key='image';

-- Rename old heartbeat.macaddr because of an ORM property name conflict
insert into OSIXINFO."#JDO_PROPERTIES" (key, value)
values ('V_HARDWARE.naming', 'none');

-- heartbeat.macaddr
CREATE OR REPLACE FORCE VIEW OSIXINFO.V_MAC AS
SELECT
    id,
    osixinfo.value mac,
    osixinfo.hardware_id hardware_id,
    osixinfo.change_timestamp change_timestamp
FROM osixinfo.osixinfo
WHERE osixinfo.key='hardware';
GRANT SELECT ON "OSIXINFO"."V_MAC" TO "GETNODES";
DROP VIEW OSIXINFO.V_HARDWARE;

-- heartbeat.version
CREATE OR REPLACE FORCE VIEW OSIXINFO.V_FIRMWARE AS
SELECT
  id,
  value as firmware,
  hardware_id as hardware_id,
  change_timestamp as change_timestamp
FROM osixinfo.osixinfo
WHERE key='firmware';

-- heartbeat.log_update
CREATE OR REPLACE FORCE VIEW OSIXINFO.V_LAST_UPDATE AS
SELECT
  id,
  value as last_update,
  hardware_id as hardware_id,
  change_timestamp as change_timestamp
FROM osixinfo.osixinfo
WHERE key='last_update';

--changeset ogl:1396
--comment: DB-2229: cloud region exposed name
alter table mss.CLOUD_REGION_INSTANCE add (
  REGION_INTERNAL_CODE VARCHAR2(64)
);

--changeset ogl:1397
--comment: DB-2229: cloud region exposed name
update mss.CLOUD_REGION_INSTANCE set REGION_INTERNAL_CODE='br-south' where region='brazilsouth';
update mss.CLOUD_REGION_INSTANCE set REGION_INTERNAL_CODE='in-west' where region='centralindia';
update mss.CLOUD_REGION_INSTANCE set REGION_INTERNAL_CODE='us-central' where region='centralus';
update mss.CLOUD_REGION_INSTANCE set REGION_INTERNAL_CODE='hk-central' where region='cn-hongkong';
update mss.CLOUD_REGION_INSTANCE set REGION_INTERNAL_CODE='es-east' where region='eastus';
update mss.CLOUD_REGION_INSTANCE set REGION_INTERNAL_CODE='fr-central' where region='francecentral';
update mss.CLOUD_REGION_INSTANCE set REGION_INTERNAL_CODE='de-west' where region='germanywestcentral';
update mss.CLOUD_REGION_INSTANCE set REGION_INTERNAL_CODE='it-north' where region='italynorth';
update mss.CLOUD_REGION_INSTANCE set REGION_INTERNAL_CODE='sg-central' where region='southeastasia';
update mss.CLOUD_REGION_INSTANCE set REGION_INTERNAL_CODE='ch-north' where region='switzerlandnorth';
update mss.CLOUD_REGION_INSTANCE set REGION_INTERNAL_CODE='uk-west' where region='ukwest';
update mss.CLOUD_REGION_INSTANCE set REGION_INTERNAL_CODE='us-west' where region='westus';

--changeset mag:1398
--comment: PRX-8054: create new dbprops for visualisation&discovery and policy enforcement for casbng service
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (56912, 'squid.casbng.discovery', 1, '0', '^[01]$', NULL, 'Enable CASB visualisation and discovery dashboard in MC portal');

insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (56913, 'squid.casbng.enforcement', 1, '0', '^[01]$', NULL, 'Enable CASB policy enforcement feature');

--changeset rha:1399
--comment: MEP-2240: Add new DB Prop migrate.mep-saml.certificate_tool
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (56914, 'migrate.mep-saml.certificate_tool', 1, '0', '^[01]$', NULL, 'Use MEP SAML certificate from certtool');

--changeset ogl:1400
--comment: DB-2229: cloud region exposed name
update mss.CLOUD_REGION_INSTANCE set REGION_INTERNAL_CODE='cn-north' where region='cn-beijing';
update mss.CLOUD_REGION_INSTANCE set REGION_INTERNAL_CODE='pop-'||REGION_INTERNAL_CODE
where REGION_INTERNAL_CODE is not null
and REGION_INTERNAL_CODE not like 'pop-%';

comment on column mss.CLOUD_REGION_INSTANCE.REGION_INTERNAL_CODE is 'Location code for use in hostnames';

--changeset ogl:1401
alter table mss.CLOUD_REGION_INSTANCE modify INTERNAL_CODE NOT NULL;
alter table mss.CLOUD_REGION_INSTANCE modify PROVIDER NOT NULL;
alter table mss.CLOUD_REGION_INSTANCE modify REGION NOT NULL;
alter table mss.CLOUD_REGION_INSTANCE modify DISPLAY_NAME NOT NULL;
alter table mss.CLOUD_REGION_INSTANCE modify REGION_INTERNAL_CODE NOT NULL;
alter table mss.CLOUD_REGION_INSTANCE modify CLUSTER_URL NOT NULL;
alter table mss.CLOUD_REGION_INSTANCE add constraint CLOUD_REGION_INSTANCE_UQ1 UNIQUE (INTERNAL_CODE);
alter table mss.CLOUD_REGION_INSTANCE add constraint CLOUD_REGION_INSTANCE_UQ2 UNIQUE (CLUSTER_URL);
alter table mss.CLOUD_REGION_INSTANCE add constraint CLOUD_REGION_INSTANCE_UQ3 UNIQUE (PROVIDER, REGION);
alter table mss.CLOUD_REGION_INSTANCE add constraint CLOUD_REGION_INSTANCE_UQ4 UNIQUE (PROVIDER, REGION_INTERNAL_CODE);

--changeset nis:1402
--comment: Allows ticketing service user to access MC_FILE related tables
GRANT SELECT ON MC.MC_FILE TO SVC_API_TICKETING;
GRANT SELECT ON MC.MC_FILE_TYPE TO SVC_API_TICKETING;
GRANT SELECT ON MC.MC_FILE_RELEASE TO SVC_API_TICKETING;

--changeset nis:1403
--comment: Allows ticketing service user to access MC_FILE related tables
GRANT SELECT,INSERT,UPDATE,DELETE ON TT.TICKET2MC_FILE TO SVC_API_TICKETING;

--changeset ogl:1404
--comment: DB-2255: Create new event types for automation
-- some already exists on DEV but not on PROD
insert into TT.EVENT_SOURCE (ID, NAME, HEX_COLOR)
select 7, 'robot', 'd7bcd7' from dual
where not exists (select 1 from tt.EVENT_SOURCE where id=7);

merge into TT.EVENT_TYPE et
using (select * from TT.EVENT_TYPE where id=10500) e
on (e.id = et.id)
when matched then
  update set et.NAME='automation info', et.DESCRIPTION='informational output from automation'
when not matched then
  insert (ID, NAME, SOURCE, IS_NOTIFIED, ESCALATION, DESCRIPTION, SMS_MESSAGE_TEMPLATE_ID, EMAIL_MESSAGE_TEMPLATE_ID, PINNABLE, AUTOPIN)
  values (10500, 'automation info', 7, 0, 0, 'informational output from automation', 1, 2, 0, 0);

merge into TT.EVENT_TYPE et
using (select * from TT.EVENT_TYPE where id=10501) e
on (e.id = et.id)
when matched then
  update set et.NAME='automation proposal', et.DESCRIPTION='proposal from automation for the user to take a decision'
when not matched then
  insert (ID, NAME, SOURCE, IS_NOTIFIED, ESCALATION, DESCRIPTION, SMS_MESSAGE_TEMPLATE_ID, EMAIL_MESSAGE_TEMPLATE_ID, PINNABLE, AUTOPIN)
  values (10501, 'automation proposal', 7, 0, 0, 'proposal from automation for the user to take a decision', 1, 2, 0, 0);

merge into TT.EVENT_TYPE et
using (select * from TT.EVENT_TYPE where id=10502) e
on (e.id = et.id)
when matched then
  update set et.NAME='automation failed', et.DESCRIPTION='automation failed and will not retry the workflow'
when not matched then
  insert (ID, NAME, SOURCE, IS_NOTIFIED, ESCALATION, DESCRIPTION, SMS_MESSAGE_TEMPLATE_ID, EMAIL_MESSAGE_TEMPLATE_ID, PINNABLE, AUTOPIN)
  values (10502, 'automation failed', 7, 0, 0, 'automation failed and will not retry the workflow', 1, 2, 0, 0);

insert into TT.EVENT_TYPE (ID, NAME, SOURCE, IS_NOTIFIED, ESCALATION, DESCRIPTION, SMS_MESSAGE_TEMPLATE_ID, EMAIL_MESSAGE_TEMPLATE_ID, PINNABLE, AUTOPIN)
values (102001, 'automation start', 10, 0, 0, 'automation framework started workflow', 1, 2, 0, 0);
insert into TT.EVENT_TYPE (ID, NAME, SOURCE, IS_NOTIFIED, ESCALATION, DESCRIPTION, SMS_MESSAGE_TEMPLATE_ID, EMAIL_MESSAGE_TEMPLATE_ID, PINNABLE, AUTOPIN)
values (102002, 'automation end', 10, 0, 0, 'automation framework finished executing workflow successfully', 1, 2, 0, 0);
insert into TT.EVENT_TYPE (ID, NAME, SOURCE, IS_NOTIFIED, ESCALATION, DESCRIPTION, SMS_MESSAGE_TEMPLATE_ID, EMAIL_MESSAGE_TEMPLATE_ID, PINNABLE, AUTOPIN)
values (102003, 'automation failed & retry', 10, 0, 0, 'automation workflow execution failed but will retry', 1, 2, 0, 0);
insert into TT.EVENT_TYPE (ID, NAME, SOURCE, IS_NOTIFIED, ESCALATION, DESCRIPTION, SMS_MESSAGE_TEMPLATE_ID, EMAIL_MESSAGE_TEMPLATE_ID, PINNABLE, AUTOPIN)
values (102004, 'automation debug', 10, 0, 0, 'automation framework debugging info', 1, 2, 0, 0);

--changeset rha:1405
--comment: MEP-2386: allow certificate with key_id NULL
alter table certs.certificate modify (KEY_ID NULL);

--changeset ogl:1406
--comment DB-2255: correct the merge statements above
merge into TT.EVENT_TYPE et
using dual
on (et.id = 10500)
when matched then
  update set et.NAME='automation info', et.DESCRIPTION='informational output from automation'
when not matched then
  insert (ID, NAME, SOURCE, IS_NOTIFIED, ESCALATION, DESCRIPTION, SMS_MESSAGE_TEMPLATE_ID, EMAIL_MESSAGE_TEMPLATE_ID, PINNABLE, AUTOPIN)
  values (10500, 'automation info', 7, 0, 0, 'informational output from automation', 1, 2, 0, 0);

merge into TT.EVENT_TYPE et
using dual
on (et.id = 10501)
when matched then
  update set et.NAME='automation proposal', et.DESCRIPTION='proposal from automation for the user to take a decision'
when not matched then
  insert (ID, NAME, SOURCE, IS_NOTIFIED, ESCALATION, DESCRIPTION, SMS_MESSAGE_TEMPLATE_ID, EMAIL_MESSAGE_TEMPLATE_ID, PINNABLE, AUTOPIN)
  values (10501, 'automation proposal', 7, 0, 0, 'proposal from automation for the user to take a decision', 1, 2, 0, 0);

merge into TT.EVENT_TYPE et
using dual
on (et.id = 10502)
when matched then
  update set et.NAME='automation failed', et.DESCRIPTION='automation failed and will not retry the workflow'
when not matched then
  insert (ID, NAME, SOURCE, IS_NOTIFIED, ESCALATION, DESCRIPTION, SMS_MESSAGE_TEMPLATE_ID, EMAIL_MESSAGE_TEMPLATE_ID, PINNABLE, AUTOPIN)
  values (10502, 'automation failed', 7, 0, 0, 'automation failed and will not retry the workflow', 1, 2, 0, 0);

--changeset ogl:1407
--comment DB-2261: SSE Region Changes
-- strip #1
update mss.CLOUD_REGION_INSTANCE
set REGION_INTERNAL_CODE = regexp_replace(REGION_INTERNAL_CODE, '#[0-9]+', '');

-- new display name
update mss.CLOUD_REGION_INSTANCE
set DISPLAY_NAME = REGION_INTERNAL_CODE||' on '||INTERNAL_CODE;

--changeset tho:1408
--comment: RTNG-76: Add new DB Prop wan.ospf_area
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (56915, 'wan.ospf_area', 4, NULL, '^([0-9]|[1-9]\d|1\d\d|2[0-4]\d|25[0-5])\.([0-9]|[1-9]\d|1\d\d|2[0-4]\d|25[0-5])\.([0-9]|[1-9]\d|1\d\d|2[0-4]\d|25[0-5])\.([0-9]|[1-9]\d|1\d\d|2[0-4]\d|25[0-5])$', NULL, 'Set if WAN uses an area other than 0.0.0.0');

--changeset pem:1409
--comment: IDS-2828: Add new DB Prop ndr.scandetection
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (56916, 'ndr.scandetection', 1,'0','^[01]$',NULL,'Triggers whether Scan Detection is active on a host');

--comment: IDS-2828: Add new DB Prop ndr.scandetection.checkperiod
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (56917, 'ndr.scandetection.checkperiod', 2,'24','^[1-9][0-9]*$',NULL,'Defines the re-checking interval for scanning hosts (in hours)');

--comment: IDS-2828: Add new DB Prop ndr.scandetection.interfaces
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (56918, 'ndr.scandetection.interfaces', 4,'nsm0','^nsm0$|^(eth|lacp)[1-9]?[0-9](\.([1-3][0-9]{0,3}|[4-9][0-9]{0,2}|40(9[0-4]|[0-8][0-9])))?$',NULL,'Restricts Scan Detection to local networks of the listed interfaces');

--comment: IDS-2828: Add new DB Prop ndr.scandetection.slowdown
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (56919, 'ndr.scandetection.slowdown', 1,'0','^[01]$',NULL,'Enable Scan Slowdown for connections from scanning hosts');

--comment: IDS-2828: Add new DB Prop ndr.scandetection.slowdown.mode
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (56920, 'ndr.scandetection.slowdown.mode', 4,'connlimit','^(block|connlimit|portlimit)$',NULL,'Defines the Scan Slowdown mode: block (block all connections), connlimit (limit all connections) or portlimit (limit per port)');

--comment: IDS-2828: Add new DB Prop ndr.scandetection.slowdown.rate
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (56921, 'ndr.scandetection.slowdown.rate', '4','15/min','^[1-9][0-9]*/(hour|min)$',NULL,'Defines the maximal rate (connections/time) for scanning hosts (string: xx/min or xx/hour) unless mode is block');

--comment: IDS-2828: Add new DB Prop ndr.scandetection.tickets
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (56922, 'ndr.scandetection.tickets', 1,'0','^[01]$',NULL,'Enables generation of tickets from scan detection in Mission Control');

--comment: IDS-2828: Add new DB Prop ndr.zeek.logs
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (56923, 'ndr.zeek.logs', 1,'0','^[01]$',NULL,'Enables the generation of the extra logs provided by Zeek on a host');

--changeset sev:1410
--comment: MEP-2284: Set sslvpn.asav.version to new current version 9.18.4_22
update mss.KEY set STRING_DEFAULT='9.18.4_22' where NAME='sslvpn.asav.version';

--changeset phm:1411
--comment: DB-2156: audit context
grant select on MCAUDIT.RECORD to SVC_CONIFER;

-- changeset jhu:1412
-- comment: ZTNA-1118: Introduce new DB for CAGs for usage with ZTNA
ALTER TABLE MSS.CVPN_GROUP ADD IS_ZTNA_COMPATIBLE NUMBER(1,0) DEFAULT 0 NOT NULL;
COMMENT ON COLUMN MSS.CVPN_GROUP.IS_ZTNA_COMPATIBLE IS 'ZTNA-1118: Introduce Field for concurrent use with ZTNA';

--changeset alg:1500 tag:v1.1.1
--comment: Base of new container
SELECT 1 FROM DUAL;

--changeset fis:1501
--comment: MX-5129: Delete mail.activeguard.* dbprops
delete from MSS.VALUE where key_id=22431;
delete from MSS.KEY where id=22431;
delete from MSS.VALUE where key_id=22432;
delete from MSS.KEY where id=22432;

--changeset mma:1502
--comment: PRX-8191: Delete squid.param.visible_hostname
delete from mss.value v where v.key_id=385;
delete from mss.key where id = 385;

--changeset alg:1503
--comment: DB-2241: Prevent Duplicate event ID on data load
alter table TICKETEVOLUTION.TICKEV
    add TICKET_STATUS_ID NUMBER(22)
;
merge INTO TICKETEVOLUTION.TICKEV t USING TT.STATUS s
ON ( t.TICKET_STATUS = s.NAME )
WHEN MATCHED THEN UPDATE set TICKET_STATUS_ID = s.ID;

--changeset gta:1504
--comment: RTNG-80: Add new DB Prop path.crosstunnel_check
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (56924, 'path.crosstunnel_check', 1, 1, '^[01]$', NULL, 'Enable Cross Tunnel check');

--changeset ogl:1505
--comment: DB-2272: make last_update a TIMESTAMP value again
CREATE OR REPLACE FORCE VIEW OSIXINFO.V_LAST_UPDATE AS
SELECT
  osixinfo.id,
  osixinfo.change_timestamp last_update,
  osixinfo.hardware_id hardware_id,
  osixinfo.change_timestamp change_timestamp
FROM osixinfo.osixinfo
WHERE osixinfo.key='last_update';

--changeset mma:1506
--comment: PRX-8482: Add new DB Prop squid.extauth.networks
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (56925, 'squid.extauth.networks', 4, NULL, '^([0-9]|[1-9]\d|1\d\d|2[0-4]\d|25[0-5]).([0-9]|[1-9]\d|1\d\d|2[0-4]\d|25[0-5]).([0-9]|[1-9]\d|1\d\d|2[0-4]\d|25[0-5]).([0-9]|[1-9]\d|1\d\d|2[0-4]\d|25[0-5])(/([0-9]|1[0-9]|2[0-9]|3[0-2]))?([\s]+([0-9]|[1-9]\d|1\d\d|2[0-4]\d|25[0-5]).([0-9]|[1-9]\d|1\d\d|2[0-4]\d|25[0-5]).([0-9]|[1-9]\d|1\d\d|2[0-4]\d|25[0-5]).([0-9]|[1-9]\d|1\d\d|2[0-4]\d|25[0-5])(/([0-9]|1[0-9]|2[0-9]|3[0-2]))?)*$', NULL, 'Space separated list of networks for which external auth header authentication is enabled in squid');

--changeset fis:1507
--comment: BGP-245: Delete bwmon.* dbprops
delete from MSS.VALUE where key_id=21910;
delete from MSS.KEY where id=21910;
delete from MSS.VALUE where key_id=21911;
delete from MSS.KEY where id=21911;

--changeset phm:1508
--comment: DB-2156
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID)
VALUES (379, 'CASB Blocking Rule created', 'casb_blocking_rule_add', 'A new blocking rule has been added to a casb policy', 2);

INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID)
VALUES (380, 'CASB Blocking Rule updated', 'casb_blocking_rule_modify', 'A blocking rule of a casb policy has been adapted', 2);

INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID)
VALUES (381, 'CASB Blocking Rule deleted', 'casb_blocking_rule_delete', 'A blocking rule of a casb policy has been deleted', 2);

--changeset alg:1509
--comment: DB-2233
INSERT INTO MSS.PLATFORM_TYPE (ID, INTERNAL_CODE, DESCRIPTION, DBCOMMENT, DEPRECATED, DISPLAY_NAME)
VALUES (0, 'none', 'none', 'DB-2233', 0, null);

MERGE INTO MSS.SERVICE ss using
    (select distinct s.ID ora_service_id from mss.service s inner join mss.HOST2SERVICE h2s on s.ID = h2s.SERVICE_ID inner join mss.HOST ON h2s.HOST_ID = HOST.ID where HOST.NAME like 'ora19%') x ON (x.ora_service_id = ss.ID)
WHEN MATCHED THEN
    UPDATE SET PLATFORM_TYPE_ID = 0;

--changeset jho:1510
--comment: MX-5232: Implement call to get all DNS zones in table
grant select on mail.domain to svc_conifer;

--changeset alg:1511
--comment: DB-2233
UPDATE MSS.PLATFORM_TYPE SET DISPLAY_NAME='None' WHERE ID = 0;

--changeset mtt:1512
--comment: TRIVIAL: Add mss.cloud_region_instance and mss.service read permission to svc_zertotrust user
grant select on MSS.CLOUD_REGION_INSTANCE to SVC_ZEROTRUST;
grant select on MSS.SERVICE to SVC_ZEROTRUST;

--changeset phm:1513
--comment: HACK: Add missing permissions for svc_conifer
grant update on MSS.ISP_LINK to SVC_CONIFER;

--changeset rha:1514
--comment: PRX-8279: Add new DB Prop migrate.proxy.certificate_tool
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (56926, 'migrate.proxy.certificate_tool', 1, '0', '^[01]$', NULL, 'Use proxy CA certificate from certtool');

--changeset rfr:1515
--comment: PRX-8394: remove migrate.squid.tlsinspector usage
delete from mss.VALUE where KEY_ID=6899;
DELETE FROM MSS.KEY WHERE name='migrate.squid.tlsinspector';

--changeset alg:1516
--comment: FIX MON-3976
delete from OSIXINFO."#JDO_PROPERTIES" where "KEY" = 'V_HOSTCLUSTERSTATE.naming.inverse.MSS.HARDWARE';

insert into MSS."#JDO_PROPERTIES" ("KEY", "VALUE")
values ('HARDWARE.naming.inverse.OSIXINFO.FK_VHOCLST', 'hostClusterState');

--changeset alg:1517
--comment: Followup MON-3976
GRANT SELECT ON OSIXINFO.V_HOSTCLUSTERSTATE TO webrls;
GRANT SELECT ON OSIXINFO.V_HOSTCLUSTERSTATE TO WEBCACHE;
GRANT SELECT ON osixinfo.v_last_update TO webrls;
GRANT SELECT ON osixinfo.v_last_update TO WEBCACHE;

--changeset jho:1518
--comment: MX-4184: remove all pmx dbprops
delete from mss.value where key_id in (
  select id from mss.key where name like 'pmx%'
);
delete from mss.key where name like 'pmx%';

--changeset rfr:1519
--comment: WAN-2928: Add dbprop to enable zero-downtime migration
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (56930, 'wan.bgp_core.redistribute_sites', 1, '0', '^[01]$', NULL, 'Redistribute static/connected routes on BGP core sites');

--changeset ogl:1520
--comment: DB prop for random testing which never has any side effects.
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (99999, 'test.null', 4, '', '^.*$', NULL, 'For testing random things. Never has any real effects.');

--changeset mta:1521
--comment: CLOUD-307: Add protocol (gre/ipsec) for backbone sites
ALTER TABLE WANBB.TERIDION_SITE ADD PROTOCOL VARCHAR2(16) DEFAULT 'gre' NOT NULL;
COMMENT ON COLUMN WANBB.TERIDION_SITE.PROTOCOL IS 'Tunnel protocol for the site';

--changeset nop:1522
--comment: SRE-847: move automation debug into audits
UPDATE TT.EVENT_TYPE SET SOURCE=10 WHERE name='automation failed';

--changeset phm:1523
--comment: DB-2156
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID)
VALUES (382, 'Cert Bundle Imported', 'cert_import', 'A certificate bundle has been imported', 1);

--changeset rha:1524
--comment: MEP-2452: rename certtool service type to proxy-sslscan
UPDATE CERTS.CERTIFICATE_SCOPE_TYPE SET name = 'proxy-sslscan' WHERE id = 400 AND name = 'proxy-ca-tls';

--changeset alg:1525
--comment: DB-2328: New Currency in ISP Links
INSERT INTO MSS.CURRENCY (ID,SHORT) VALUES (12, 'BOB');

--changeset alg:1526
--comment: DB-2328: New Currencies in ISP Links
INSERT INTO MSS.CURRENCY (ID,SHORT) VALUES (13, 'IDR');
INSERT INTO MSS.CURRENCY (ID,SHORT) VALUES (14, 'MXN');
INSERT INTO MSS.CURRENCY (ID,SHORT) VALUES (15, 'PHP');
INSERT INTO MSS.CURRENCY (ID,SHORT) VALUES (16, 'QAR');
INSERT INTO MSS.CURRENCY (ID,SHORT) VALUES (17, 'VND');

--changeset doi:1527
--comment: PRX-8134: remove dbprops squid.caching, squid.antimalware.apc and squid.antimalware.apc.fileupload
DELETE FROM MSS.VALUE WHERE key_id IN (SELECT id FROM MSS.KEY WHERE name='squid.caching');
DELETE FROM MSS.VALUE WHERE key_id IN (SELECT id FROM MSS.KEY WHERE name='squid.antimalware.apc');
DELETE FROM MSS.VALUE WHERE key_id IN (SELECT id FROM MSS.KEY WHERE name='squid.antimalware.apc.fileupload');
DELETE FROM MSS.KEY WHERE name='squid.caching';
DELETE FROM MSS.KEY WHERE name='squid.antimalware.apc';
DELETE FROM MSS.KEY WHERE name='squid.antimalware.apc.fileupload';

--changeset doi:1528
--comment: PRX-8514: remove dbprop squid.urlfilter.netstar.fulldb
DELETE FROM MSS.VALUE WHERE key_id IN (SELECT id FROM MSS.KEY WHERE name='squid.urlfilter.netstar.fulldb');
DELETE FROM MSS.KEY WHERE name='squid.urlfilter.netstar.fulldb';

--changeset mlo:1529
--comment: MC-27560: add permissions for SVC_USERS_INTERNAL_API to create accounts

-- being able to select required fields to add to the user
GRANT SELECT on auth.AUTHSYS to SVC_USERS_INTERNAL_API;
GRANT SELECT on auth.AUTHHOST2AUTHSYS to SVC_USERS_INTERNAL_API;
GRANT SELECT on auth.AUTHHOST to SVC_USERS_INTERNAL_API;
GRANT SELECT on auth.USER_UNIT to SVC_USERS_INTERNAL_API;
GRANT SELECT on auth.PASSWORDTYPE to SVC_USERS_INTERNAL_API;
GRANT SELECT on auth.AUTHTYPE to SVC_USERS_INTERNAL_API;
GRANT SELECT on auth.TOKENREPLACEMENTSTATE to SVC_USERS_INTERNAL_API;
GRANT SELECT on auth.USER_ROLE to SVC_USERS_INTERNAL_API;

-- allow creating login and contacts
GRANT INSERT on auth.login to SVC_USERS_INTERNAL_API;
GRANT INSERT on stop.contact to SVC_USERS_INTERNAL_API;

-- allow selection of sequences for creations
GRANT SELECT on auth.SEQ_LOGIN_ID to SVC_USERS_INTERNAL_API;
GRANT SELECT on stop.CONTACT_SEQ to SVC_USERS_INTERNAL_API;

-- This is needed to grant basic portal access role
GRANT EXECUTE on AUTH.OSAG_AUTH to SVC_USERS_INTERNAL_API;

--changeset jad:1530
--comment: ZTNA-774: Add new DB Prop ztna.scaling
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (24507, 'ztna.scaling', 2, '1', '^[1-9]$', NULL, 'Number of EPs');

--changeset mlo:1531
--comment: MC-27560: add permissions for SVC_USERS_INTERNAL_API to audit trail newly created accounts
GRANT SELECT on auth.LOGIN2GROUPS to SVC_USERS_INTERNAL_API;
GRANT SELECT on auth.GROUPS to SVC_USERS_INTERNAL_API;
GRANT SELECT on auth.LOGIN2TUNNELGROUP to SVC_USERS_INTERNAL_API;
GRANT SELECT on auth.TUNNELGROUP to SVC_USERS_INTERNAL_API;
GRANT SELECT on auth.LOGIN2PROFILE to SVC_USERS_INTERNAL_API;
GRANT SELECT on auth.PROFILE to SVC_USERS_INTERNAL_API;

--changeset nis:1532
--comment: TRIVIAL: Add a new permission for Casb self service
INSERT INTO AUTH.USER_ROLE (ID, NAME, DESCRIPTION, IS_INTERNAL, USER_ROLE_SCOPE_TYPE_ID)
VALUES (2013, 'mc-cust-casb-policy-mgmt', 'Casb Policy Management', 0, 1);
INSERT INTO AUTH.user_role2required_role (USER_ROLE_ID, REQUIRED_USER_ROLE_ID)
VALUES (2013, 1003);

--changeset lut:1533
--comment: RTNG-103: Add Backbone boolean to WAN tunnels
ALTER TABLE VPN.TUNNEL ADD BACKBONE NUMBER(1) DEFAULT 0 NOT NULL;
COMMENT ON COLUMN VPN.TUNNEL.BACKBONE is '1 if this WAN tunnel is built on top of the WAN Backbone';

--changeset mgr:1534
--comment: MX-5356: create migrate.mail.goqueue dbprop
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (24508, 'migrate.mail.goqueue', 2, '0', '^[012]$', NULL, 'Migration to mxfilter without goqueues');

--changeset mlo:1535
--comment: TRIVIAL: allow access to OSAG MC authsys for mc-cust-users-monitor role for all RLS areas
update rlsdef.predicate
set predicate='auth.authsys.id = 2 or company_id = sys_context(''web'', ''current_company_id'')'
where SCHEMA_NAME='AUTH'
  and table_name='AUTHSYS'
  and role_id=12;

--changeset jah:1536
--comment: TRIVIAL: automatically patch this dev host after the prod patch rollout has finished
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (56940, 'cicd.autopatch', 1, '1', '^[01]$', 22, 'Automatically patch after prod patch rollout');

--changeset aas:1537
--comment: ZTNA-1257: create portal.ztna dbprop
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (24509, 'portal.ztna', 1, '0', '^[01]$', NULL, 'ZTNA content shown in the portal');

--changeset mlo:1538
--comment: MC-27611: orm setup for last update
insert into OSIXINFO."#JDO_PROPERTIES" (key, value)
values ('V_LAST_UPDATE.fk.FK_VHOLU', 'HARDWARE_ID:MSS.HARDWARE.ID');

insert into MSS."#JDO_PROPERTIES" ("KEY", "VALUE")
values ('HARDWARE.naming.inverse.OSIXINFO.FK_VHOLU', 'lastUpdate');

--changeset diw:1539
--comment: CLOUD-359: Add field isWanOnly for backbone sites
ALTER TABLE WANBB.TERIDION_SITE ADD IS_WAN_ONLY NUMBER(1) DEFAULT 1 NOT NULL;
COMMENT ON COLUMN WANBB.TERIDION_SITE.IS_WAN_ONLY IS '1 if tunnels are used for WAN traffic only, no internet traffic';

--changeset mlo:1540
--comment: FIX: decom check can't see heartbeats, grant permission to MCA user
GRANT SELECT ON OSIXINFO.V_HOSTCLUSTERSTATE TO mca;
GRANT SELECT ON osixinfo.v_last_update TO mca;

--changeset mlo:1541
--comment: FIX: remove SEL_bad_user_roles consistency check because all users can have user mgmt permission now
DELETE FROM MCDB_CHECKS.CONSISTENCY_CHECKS where CHECK_KEY='SEL_bad_user_roles';
DELETE FROM MCDB_CHECKS.CONSISTENCY_CHECK_RUN where CHECK_KEY='SEL_bad_user_roles';

--changeset alg:1542
--comment DB-2328 - add more currencies
INSERT INTO MSS.CURRENCY (ID,SHORT) VALUES (18,'BDT');
INSERT INTO MSS.CURRENCY (ID,SHORT) VALUES (19,'BGN');
INSERT INTO MSS.CURRENCY (ID,SHORT) VALUES (20,'CAD');
INSERT INTO MSS.CURRENCY (ID,SHORT) VALUES (21,'CLP ');
INSERT INTO MSS.CURRENCY (ID,SHORT) VALUES (22,'ETB ');
INSERT INTO MSS.CURRENCY (ID,SHORT) VALUES (23,'GHC ');
INSERT INTO MSS.CURRENCY (ID,SHORT) VALUES (24,'HKD ');
INSERT INTO MSS.CURRENCY (ID,SHORT) VALUES (25,'IQD ');
INSERT INTO MSS.CURRENCY (ID,SHORT) VALUES (26,'LKR ');
INSERT INTO MSS.CURRENCY (ID,SHORT) VALUES (27,'MOP');
INSERT INTO MSS.CURRENCY (ID,SHORT) VALUES (28,'PLN');
INSERT INTO MSS.CURRENCY (ID,SHORT) VALUES (29,'PYG');
INSERT INTO MSS.CURRENCY (ID,SHORT) VALUES (30,'RON ');
INSERT INTO MSS.CURRENCY (ID,SHORT) VALUES (31,'SEK ');
INSERT INTO MSS.CURRENCY (ID,SHORT) VALUES (32,'SGD ');
INSERT INTO MSS.CURRENCY (ID,SHORT) VALUES (33,'ZAR');

--changeset sev:1543
--comment: ZTNA-1220: Add dbprop to dnat proxy traffic to a specific IP (dedicated SWG)
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (56941, 'ztna.forward-proxy.dnat_ip', 4, '', '(?:(?:25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]|[0-9])\.(?:25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]|[0-9])\.(?:25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]|[0-9])\.(?:25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]|[0-9]))', NULL, 'IP to DNAT forward proxy traffic to');

--changeset gip:1544
--comment: DNS-436: Modify default value of migrate.forwarderzones to 1
update MSS.key k
set k.STRING_DEFAULT='1'
where k.id=56710 and k.name='migrate.forwarderzones';

--changeset nop:1545
--comment: SRE-899: Necessary grants to get sign-off contacts 
GRANT SELECT ON STOP.CONTACT TO SVC_AUTOMATION_EXECUTOR;
GRANT SELECT ON AUTH.LOGIN TO SVC_AUTOMATION_EXECUTOR;
GRANT SELECT ON AUTH.PERMISSION TO SVC_AUTOMATION_EXECUTOR;
GRANT SELECT ON AUTH.USER_COMPANY_SCOPE TO SVC_AUTOMATION_EXECUTOR;
GRANT SELECT ON AUTH.USER_COMPANY_UNIT_SCOPE TO SVC_AUTOMATION_EXECUTOR;
GRANT SELECT ON STOP.COMPANY_UNIT TO SVC_AUTOMATION_EXECUTOR;
GRANT SELECT ON STOP.COMPANY TO SVC_AUTOMATION_EXECUTOR;

--changeset nop:1546
--comment SRE-894 - allow dbwatcher to track change requests
GRANT SELECT ON TT.CHANGE_REQUEST TO SVC_AUTOMATION_DBWATCHER;

--changeset jad:1547
--comment: ZTNA-1224: Add appid read permission to svc_zerotrust user
grant select on APPID.QUICKID_DNS to SVC_ZEROTRUST;
grant select on APPID.QUICKID_NET4 to SVC_ZEROTRUST;
grant select on APPID.QUICKID_NET6 to SVC_ZEROTRUST;

--changeset ogl:1548
--comment: DB-2421: add customer site code
ALTER TABLE mss.ADDRESS add (
  CUST_SITE_CODE varchar2(10) null
);

-- only add index entries if cust_site_code is not null at all, since CUST_SITE_CODE can be NULL
CREATE unique index mss.U2_ADDRESS on mss.ADDRESS (
   case when CUST_SITE_CODE is not null then CUST_SITE_CODE end,
   case when CUST_SITE_CODE is not null then COMPANY_ID end
);

--changeset ogl:1549
--comment: DB-2421: add customer site code
comment on column mss.ADDRESS.CUST_SITE_CODE is 'Custom short identifier of a site';

--changeset jad:1550
--comment: ZTNA-1268: Add appid.app read permission to svc_zerotrust user
grant select on APPID.APP to SVC_ZEROTRUST;

--changeset nop:1551
--comment: SRE-899: Necessary grants to get sign-off contacts 
GRANT SELECT ON AUTH.USER_PERMISSION TO SVC_AUTOMATION_EXECUTOR;
GRANT SELECT ON AUTH.LOGIN2PROFILE TO SVC_AUTOMATION_EXECUTOR;

--changeset ssk:1552
--comment: CLOUD-375
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID)
VALUES (383, 'Tunnel to external entity created', 't2ee_created', 'A new tunnel to an external entity has been configured on a host', 1);

INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID)
VALUES (384, 'Tunnel to external entity modified', 't2ee_modified', 'A tunnel to an external entity has been reconfigured', 1);

INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID)
VALUES (385, 'Tunnel to external entity deleted', 't2ee_deleted', 'A tunnel to an external entity has been deconfigured', 1);

--changeset rse:1553
--comment: BASE-95: Teleport agentless integration
INSERT INTO MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
VALUES (56950, 'mgmtaccess.teleport', 1, '0', '^[01]$', NULL, 'Enable management access via agentless Teleport');

--changeset alg:1553
--comment: DB-2402: add prefix to STOP.COMPANY
ALTER TABLE STOP.COMPANY ADD PREFIX VARCHAR2(10) null;
UPDATE STOP.COMPANY SET PREFIX = 'hi' WHERE SHORT = 'cop';
UPDATE STOP.COMPANY SET PREFIX = 'me' WHERE SHORT = 'messina';
UPDATE STOP.COMPANY SET PREFIX = 'repi' WHERE SHORT = 'repower';
UPDATE STOP.COMPANY SET PREFIX = 'sic' WHERE SHORT = 'sicpa';
UPDATE STOP.COMPANY SET PREFIX = 'sun' WHERE SHORT = 'sulzer';
UPDATE STOP.COMPANY SET PREFIX = 'slog' WHERE SHORT = 'swisslog';

--changeset ogl:1554
--comment: DB-2421: make site code case in-sensitive
-- only add index entries if cust_site_code is not null at all, since CUST_SITE_CODE can be NULL
DROP INDEX mss.U2_ADDRESS;
CREATE unique index mss.U2_ADDRESS on mss.ADDRESS (
     case when CUST_SITE_CODE is not null then LOWER(CUST_SITE_CODE) end,
     case when CUST_SITE_CODE is not null then COMPANY_ID end
);

--changeset rha:1555
--comment: flip default value of dbprop migrate.mep-saml.certificate_tool (migration in production completed)
UPDATE MSS.KEY SET STRING_DEFAULT = '1' WHERE id = 56914 AND name = 'migrate.mep-saml.certificate_tool';

--changeset nop:1556
--comment: SRE-878: Necessary grants to get the ticket TODOS (not supported by the ticketing API yet)
GRANT SELECT ON TT.TODO_ITEM TO SVC_AUTOMATION_EXECUTOR;

--changeset rha:1557
--comment: remove dbprop migrate.mep-saml.certificate_tool (migration in production completed)
DELETE FROM MSS.VALUE WHERE key_id = 56914;
DELETE FROM MSS.KEY WHERE id = 56914 AND name = 'migrate.mep-saml.certificate_tool';

--changeset dnb:1558
--comment: MX-5345: Delete quarantine migration dbprops
DELETE FROM MSS.VALUE WHERE key_id IN (SELECT id FROM MSS.KEY WHERE name='migrate.mail-quarantine.certificate_tool');
DELETE FROM MSS.VALUE WHERE key_id IN (SELECT id FROM MSS.KEY WHERE name='migrate.mail.enable_old_quarantine');
DELETE FROM MSS.VALUE WHERE key_id IN (SELECT id FROM MSS.KEY WHERE name='migrate.mail.enduser_quarantine');
DELETE FROM MSS.VALUE WHERE key_id IN (SELECT id FROM MSS.KEY WHERE name='migrate.mail.quarantine');
DELETE FROM MSS.VALUE WHERE key_id IN (SELECT id FROM MSS.KEY WHERE name='migrate.mail.quarantine_migration_date');
DELETE FROM MSS.VALUE WHERE key_id IN (SELECT id FROM MSS.KEY WHERE name='migrate.mail.quarantine.tag_relay');
DELETE FROM MSS.VALUE WHERE key_id IN (SELECT id FROM MSS.KEY WHERE name='migrate.mail.quarantine.tag_relay.date');
DELETE FROM MSS.KEY WHERE name='migrate.mail-quarantine.certificate_tool';
DELETE FROM MSS.KEY WHERE name='migrate.mail.enable_old_quarantine';
DELETE FROM MSS.KEY WHERE name='migrate.mail.enduser_quarantine';
DELETE FROM MSS.KEY WHERE name='migrate.mail.quarantine';
DELETE FROM MSS.KEY WHERE name='migrate.mail.quarantine_migration_date';
DELETE FROM MSS.KEY WHERE name='migrate.mail.quarantine.tag_relay';
DELETE FROM MSS.KEY WHERE name='migrate.mail.quarantine.tag_relay.date';

--changeset dnb:1559
--comment: MX-5343: Delete custom policy list for quarantine migration
DELETE FROM MAIL.CUSTOM_POLICY_LIST_VALUE WHERE custom_policy_list_id IN (SELECT id FROM MAIL.CUSTOM_POLICY_LIST WHERE name='migration_bypass_end_user_quarantine');
DELETE FROM MAIL.CUSTOM_POLICY_LIST WHERE name='migration_bypass_end_user_quarantine';

--changeset jad:1560
--comment: ZTNA-1286: New audit record type for ZTNA policy upsert
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID)
VALUES (386, 'Upserted ZTNA policy', 'upsert-policy', 'A ZTNA policy has been upserted', 1);

--changeset jwj:1561
--comment: DNS-437: Delete unused forwarder dbprops named.caching.forwarderzones(ID:159), named.caching.forward_insecure(ID:318), migrate.forwarderzones(ID:56710)
DELETE FROM mss.VALUE WHERE KEY_ID IN (159, 318, 56710);
DELETE FROM mss.KEY WHERE ID IN (159, 318, 56710);

--changeset rha:1562
--comment: MX-5535: Buildall shall depend on dbprop postfix.smtpdtls to activate TLS in postfix SMTP listener
INSERT INTO MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
VALUES (12013, 'postfix.smtpdtls', 1, '1', '^[01]$', NULL, 'Activate TLS in postfix SMTP listener');

--changeset alg:1563
--comment: DB-2328: New Currencies in ISP Links , v3
INSERT INTO MSS.CURRENCY (ID,SHORT) VALUES (34,'AED');
INSERT INTO MSS.CURRENCY (ID,SHORT) VALUES (35,'AUD');
INSERT INTO MSS.CURRENCY (ID,SHORT) VALUES (36,'BYN');
INSERT INTO MSS.CURRENCY (ID,SHORT) VALUES (37,'CFA');
INSERT INTO MSS.CURRENCY (ID,SHORT) VALUES (38,'COP');
INSERT INTO MSS.CURRENCY (ID,SHORT) VALUES (39,'CRC');
INSERT INTO MSS.CURRENCY (ID,SHORT) VALUES (40,'CZK');
INSERT INTO MSS.CURRENCY (ID,SHORT) VALUES (41,'DOP');
INSERT INTO MSS.CURRENCY (ID,SHORT) VALUES (42,'DZD');
INSERT INTO MSS.CURRENCY (ID,SHORT) VALUES (43,'EGP');
INSERT INTO MSS.CURRENCY (ID,SHORT) VALUES (44,'HUF');
INSERT INTO MSS.CURRENCY (ID,SHORT) VALUES (45,'MNT');
INSERT INTO MSS.CURRENCY (ID,SHORT) VALUES (46,'MZN');
INSERT INTO MSS.CURRENCY (ID,SHORT) VALUES (47,'NGN');
INSERT INTO MSS.CURRENCY (ID,SHORT) VALUES (48,'NZD');
INSERT INTO MSS.CURRENCY (ID,SHORT) VALUES (49,'OMR');
INSERT INTO MSS.CURRENCY (ID,SHORT) VALUES (50,'PKR');
INSERT INTO MSS.CURRENCY (ID,SHORT) VALUES (51,'RUB');
INSERT INTO MSS.CURRENCY (ID,SHORT) VALUES (52,'TWD');
INSERT INTO MSS.CURRENCY (ID,SHORT) VALUES (53,'UAH');
INSERT INTO MSS.CURRENCY (ID,SHORT) VALUES (54,'UYU');

--changeset ogl:1564
--comment: GEA CaaS classes
create table mss.caas_class (
                              id number(10) not null,
                              name varchar2(32) not null,
                              description varchar2(400),
                              constraint caasclass_pk primary key (id)
);

--changeset ogl:1565
--comment: GEA CaaS classes data
insert into mss.caas_class(id, name, description) values (1, 'Platinum +', 'Bundled (2x) DIA Internet connections with a 1Gbps baseline Port speed, 10Gbps Access speed. POP and Path Diversity');
insert into mss.caas_class(id, name, description) values (2, 'Platinum', 'Bundled (2x) DIA Internet connections with a 1Gbps baseline Port speed, 10Gbps Access speed. POP Diversity');
insert into mss.caas_class(id, name, description) values (3, 'Gold +', 'Bundled (2x) DIA Internet connections with a 200Mbps baseline Port speed, 1Gbps Access speed. POP and Path Diversity');
insert into mss.caas_class(id, name, description) values (4, 'Gold', 'Bundled (2x) DIA Internet connections with a 200Mbps baseline Port speed, 1Gbps Access speed. POP Diversity');
insert into mss.caas_class(id, name, description) values (5, 'Silver', 'Bundled 1x Broadband and 1x DIA Internet connections with a 100Mbps baseline Port speed. POP and Path Diversity is implied.');
insert into mss.caas_class(id, name, description) values (6, 'Bronze', 'Bundled (2x) Internet connections with a 50Mbps baseline Port speed');
insert into mss.caas_class(id, name, description) values (7, 'Copper +', 'Single (1x) Broadband Internet connection with 20Mbps baseline Port speed');
insert into mss.caas_class(id, name, description) values (8, 'Copper', 'Single (1x) Broadband Internet connection');

--changeset ogl:1566
--comment: GEA CaaS classes assignment
alter table mss.ISP_LINK add (
  caas_class_id number(10) null,
  constraint isplink_fk16 foreign key (caas_class_id) references mss.caas_class (id)
);

--changeset alg:1567
--comment: DB-2373: Add new dbprop migrate.ztna.vault.config-api
INSERT INTO MSS.KEY (DESCRIPTION,ID,KEY_TYPE_ID,NAME,OPERATING_SYSTEM_ID,REGEXP,SERVICE_OPTION_TYPE_ID,STRING_DEFAULT) VALUES ('Activates the new URLF engine on a host for migrating customers',56942,1,'migrate.ztna.vault.config-api',22,'^[01]$',NULL,0);

--changeset phh:1568
--comment: FW-5776: Remove all remnants of fw.droplog
delete from mss.VALUE where KEY_ID in (22150, 22151, 22152);
DELETE FROM MSS."KEY" k WHERE k.id in (22150, 22151, 22152);

--changeset ogl:1569
--comment: DB-2451: lower case MAC addresses
update mss.HARDWARE
set MAC_ADDRESS = lower(MAC_ADDRESS)
where MAC_ADDRESS != lower(MAC_ADDRESS);

create index hardware_uv4 on mss.hardware(lower(mac_address));

--changeset tho:1570
--comment: RTNG-324: change default of migrate.frrouting.integrated_config to 1
update MSS.key k
set k.STRING_DEFAULT='1'
where k.id=56850 and k.name='migrate.frrouting.integrated_config';

--changeset tho:1571
--comment: RTNG-323: add new table columns to hold information about ospf priority and message digest key
ALTER TABLE MSS.INTERFACE ADD OSPF_PRIORITY NUMBER(10,0) NULL;
ALTER TABLE MSS.INTERFACE ADD OSPF_DIGESTKEY NUMBER(10,0) DEFAULT 1 NULL;
comment on column mss.interface.ospf_priority is 'Set priority, relevant for DR election';
comment on column mss.interface.ospf_digestkey is 'Set id of message digest key, relevant for OSPF authentication';

--changeset gip:1572
--comment: MX-5205: Modify default value of migrate.mail.authmilter to 1
update MSS.key k
set k.STRING_DEFAULT='1'
where k.id=56841 and k.name='migrate.mail.authmilter';

--changeset mlo:1572
--comment: CaaS classes, add company ID fk
alter table mss.caas_class add (
    company_id number(22) null,
    constraint caas_class_fk16 foreign key (company_id) references stop.company (id)
    );

--changeset rha:1574
--comment: toggle default value of dbprop migrate.mail-smtp.certificate_tool as migration has been completed
UPDATE MSS.KEY SET STRING_DEFAULT = '1' WHERE id = 22602 AND name = 'migrate.mail-smtp.certificate_tool';

--changeset rha:1575
--comment: MEP-2188: remove dbprop migrate.mep.certificate_tool
DELETE FROM MSS.VALUE WHERE key_id = 22601;
DELETE FROM MSS.KEY WHERE id = 22601 AND name = 'migrate.mep.certificate_tool';

--changeset rha:1576
--comment: toggle default value of dbprop migrate.proxy.certificate_tool as migration has been completed
UPDATE MSS.KEY SET STRING_DEFAULT = '1' WHERE id = 56926 AND name = 'migrate.proxy.certificate_tool';

--changeset rha:1577
--comment: toggle default value of dbprop migrate.sslvpn.asav5ram as migration has been completed
UPDATE MSS.KEY SET STRING_DEFAULT = '1' WHERE id = 21605 AND name = 'migrate.sslvpn.asav5ram';

--changeset del:1578
--comment: OSCI-569: Add new DB Prop mgmtserver.gcp.logcollector
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (57000, 'mgmtserver.gcp.logcollector', 1, '0', '^[01]$', NULL, 'Management host collecting logs from GCP pubsub topic');

--changeset tho:1579
--comment: RTNG-386: add new service component for SD-WAN Backbone
INSERT INTO MSS.SERVICE_COMPONENT (ID, NAME,INTERNAL_CODE,DEPRECATED,INTERNAL)
	VALUES (37,'SD-WAN Backbone','backbone',0,0);

--changeset isa:1580
--comment: RTNG-360: Add new DB Prop ospfd.redist.connected_as_stub
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (57001, 'ospfd.redist.connected_as_stub', 1, '0', '^[01]$', NULL, 'Redistribute directly connected routes as stub networks in OSPF (FRRouting)');

--changeset ogl:1581
--comment: DB-2484: eliminate queue consistency_check_results
grant select,insert,update,delete on MCDB_MONITOR.LAST_CONSISTENCY_CHECK_RESULTS to MCDB_CHECKS;

--changeset ogl:1582
--comment: DB-2484
drop package body MCDB_MONITOR.RESULT_CONSUMER;

--changeset ogl:1583
--comment: DB-2484
drop package MCDB_MONITOR.RESULT_CONSUMER;

--changeset ogl:1584 endDelimiter:/
--comment: DB-2484
begin
  DBMS_AQADM.STOP_QUEUE(
  queue_name => 'MCDB_MONITOR.consistency_check_results'
  );

  DBMS_AQADM.DROP_QUEUE(
  queue_name => 'MCDB_MONITOR.consistency_check_results'
  );

  DBMS_AQADM.DROP_QUEUE_TABLE(
  queue_table => 'MCDB_MONITOR.consistency_check_results_table'
  );

  DBMS_AQADM.REVOKE_SYSTEM_PRIVILEGE(
  privilege          =>    'ENQUEUE_ANY',
  grantee            =>    'MCDB_CHECKS');
end;
/

--changeset mcp:1585
--comment: OSIX-6503: add new dbprop relmgmt.patch_pull to enable pull RPM install for certain hosts/companies/services
INSERT INTO MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
VALUES (57010, 'relmgmt.patch_pull', 1, '0', '^[01]$', 22, 'Host will pull RPM install');

--changeset mzi:1586
--comment: toggle default value of dbprop cicd.buildkite.agent.root
UPDATE MSS.KEY SET STRING_DEFAULT = '1' WHERE name = 'cicd.buildkite.agent.root';

--changeset cwa:1587
--comment: MC-28127: add unique constraint to news entry image names
ALTER TABLE MSS.NEWS_ENTRY_IMAGE ADD CONSTRAINT U_NEWS_ENTRY_IMAGE UNIQUE (NAME);

--changeset ssk:1588
--comment: CLOUD-432: grant needed appvis perms to svc_conifer
GRANT SELECT ON FW.IP_PROTOCOL TO svc_conifer;
GRANT SELECT ON APPID.APP TO svc_conifer;
GRANT SELECT ON APPID.APP_TYPE TO svc_conifer;
GRANT SELECT ON APPID.APP_CATEGORY TO svc_conifer;
GRANT SELECT ON APPID.QUICKID_DNS TO svc_conifer;
GRANT SELECT ON APPID.QUICKID_NET4 TO svc_conifer;
GRANT SELECT ON APPID.QUICKID_NET6 TO svc_conifer;
GRANT SELECT ON APPID.QUICKID_PROTO TO svc_conifer;
GRANT SELECT ON APPID.QUICKID_TOS TO svc_conifer;

--changeset ogl:1589
--comment: DB-2487 introduce service name
alter table mss.SERVICE add name varchar2(32) null;

--changeset mlo:1590
--comment: MC-28225: user for MC portal to replace webrls long term
CREATE USER "SVC_MC_PORTAL" IDENTIFIED BY "xxxxxx" ACCOUNT LOCK
    DEFAULT TABLESPACE "USERS"
    TEMPORARY TABLESPACE "TEMP";

GRANT "MSS_LOGIN_USER" TO "SVC_MC_PORTAL";
ALTER USER "SVC_MC_PORTAL" DEFAULT ROLE "MSS_LOGIN_USER";
GRANT EXEMPT ACCESS POLICY TO "SVC_MC_PORTAL";

-- PLSQL grants equivalent to what WEBRLS has
GRANT EXECUTE ON ESP.OSAG_DUTY TO SVC_MC_PORTAL;
GRANT EXECUTE ON MSS.OSAG_DBPROP TO SVC_MC_PORTAL;
-- the 3 grants below replace the grant to TT.OSAG_TT_WEBRLS
GRANT EXECUTE ON TT.OSAG_NOTIFY TO SVC_MC_PORTAL;
GRANT EXECUTE ON TT.EVENT_INTERFACE TO SVC_MC_PORTAL;
GRANT EXECUTE ON TT.TICKET_INTERFACE TO SVC_MC_PORTAL;
-- this grant replaces the grant to AUTH.OSAG_AUTH_WEBRLS
GRANT EXECUTE ON AUTH.OSAG_AUTH TO SVC_MC_PORTAL;

-- Table grants equivalent to what WEBRLS has
GRANT SELECT ON APPID.PATH_OVERRIDE_DEFAULTS_SEQ TO SVC_MC_PORTAL;
GRANT SELECT ON APPID.PATH_OVERRIDE_MEMBER_LINK_SEQ TO SVC_MC_PORTAL;
GRANT SELECT ON APPID.PATH_SELECT_OVERRIDE_MEM_SEQ TO SVC_MC_PORTAL;
GRANT SELECT ON AUTH.API_KEY_SEQ TO SVC_MC_PORTAL;
GRANT SELECT ON AUTH.SEQ_ALIAS_ID TO SVC_MC_PORTAL;
GRANT SELECT ON AUTH.SEQ_CONSENTED_TERM TO SVC_MC_PORTAL;
GRANT SELECT ON AUTH.SEQ_LOGIN_ID TO SVC_MC_PORTAL;
GRANT SELECT ON AUTH.SEQ_PROFILE TO SVC_MC_PORTAL;
GRANT SELECT ON AUTH.SEQ_SYNCDOMAIN_ID TO SVC_MC_PORTAL;
GRANT SELECT ON AUTH.SEQ_TOKEN_ID TO SVC_MC_PORTAL;
GRANT SELECT ON AUTH.SEQ_USER_COMPANY_SCOPE TO SVC_MC_PORTAL;
GRANT SELECT ON AUTH.SEQ_USER_COMPANY_UNIT_SCOPE TO SVC_MC_PORTAL;
GRANT SELECT ON AUTH.SEQ_USER_PERMISSION TO SVC_MC_PORTAL;
GRANT SELECT ON AUTH.SEQ_USER_SERVICE_SCOPE TO SVC_MC_PORTAL;
GRANT SELECT ON AUTH.SEQ_USER_SERVICE_TYPE_SCOPE TO SVC_MC_PORTAL;
GRANT SELECT ON AUTH.SEQ_USER_UNIT_SCOPE TO SVC_MC_PORTAL;
GRANT SELECT ON AUTH.TEMP_ACCESS_KEY_SEQ TO SVC_MC_PORTAL;
GRANT SELECT ON AUTH.TOKENPOOL_SEQ TO SVC_MC_PORTAL;
GRANT SELECT ON CERTS.CERTIFICATE_SEQ TO SVC_MC_PORTAL;
GRANT SELECT ON CERTS.CERTIFICATE_USAGE_SEQ TO SVC_MC_PORTAL;
GRANT SELECT ON CERTS.CSR_SEQ TO SVC_MC_PORTAL;
GRANT SELECT ON CERTS.SAN_SEQ TO SVC_MC_PORTAL;
GRANT SELECT ON ESP.MCCENTERCONTACT_SEQ TO SVC_MC_PORTAL;
GRANT SELECT ON FYI.FILTER_SUBJECT_REGEX_SEQ TO SVC_MC_PORTAL;
GRANT SELECT ON FYI.SUBSCRIPTION_SEQ TO SVC_MC_PORTAL;
GRANT SELECT ON GUMA2.SUPPRESSED_SIGNATURE_SEQ TO SVC_MC_PORTAL;
GRANT SELECT ON MAIL.CUSTOM_POLICY_LIST_SEQ TO SVC_MC_PORTAL;
GRANT SELECT ON MAIL.CUSTOM_POLICY_LIST_VALUE_SEQ TO SVC_MC_PORTAL;
GRANT SELECT ON MAIL.POLICY_LIST_VALUE_SEQ TO SVC_MC_PORTAL;
GRANT SELECT ON MAIL.USER_GROUP_SEQ TO SVC_MC_PORTAL;
GRANT SELECT ON MC.AVAILABILITY_REPORT_SEQ TO SVC_MC_PORTAL;
GRANT SELECT ON MC.CONNECTION_INTERRUPT_SEQUENCE TO SVC_MC_PORTAL;
GRANT SELECT ON MC.MCFILERELEASE_SEQ TO SVC_MC_PORTAL;
GRANT SELECT ON MC.MCFILE_SEQ TO SVC_MC_PORTAL;
GRANT SELECT ON MCAUDIT.RECORD_SEQ TO SVC_MC_PORTAL;
GRANT SELECT ON MCAUDIT.TRANSACTION_SEQ TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.CONFIG_LIST_SEQ TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.CONFIG_LIST_TYPE_SEQ TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.CONFIG_LIST_VALUE_SEQ TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.INTERFACE_SEQUENCE TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.IPV6STATICROUTE_SEQ TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.NEWS_ENTRY_2_LOGIN_SEQ TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.STATIC_ROUTE_SEQUENCE TO SVC_MC_PORTAL;
GRANT SELECT ON NIDS.DYNSIGNATUREGROUP_SEQ TO SVC_MC_PORTAL;
GRANT SELECT ON NIDS.EVENTFILTERRULE_SEQ TO SVC_MC_PORTAL;
GRANT SELECT ON NIDS.INVESTIGATION_ENTRY_SEQ TO SVC_MC_PORTAL;
GRANT SELECT ON NIDS.INVESTIGATION_SEQ TO SVC_MC_PORTAL;
GRANT SELECT ON NIDS.KS_ENFORCEMENT_SCOPE_SEQ TO SVC_MC_PORTAL;
GRANT SELECT ON NIDS.KS_ENFORCEMENT_SEQ TO SVC_MC_PORTAL;
GRANT SELECT ON NIDS.MDR_FILTER_RULE_SEQ TO SVC_MC_PORTAL;
GRANT SELECT ON NIDS.MDR_SIGNATURE_GROUP_MEMBER_SEQ TO SVC_MC_PORTAL;
GRANT SELECT ON NIDS.MDR_SIGNATURE_GROUP_SEQ TO SVC_MC_PORTAL;
GRANT SELECT ON NIDS.NIDSIPADDRESS_SEQ TO SVC_MC_PORTAL;
GRANT SELECT ON NIDS.NIDSIPNETWORK_SEQ TO SVC_MC_PORTAL;
GRANT SELECT ON NIDS.NIDSIPV6ADDRESS_SEQ TO SVC_MC_PORTAL;
GRANT SELECT ON NIDS.NIDSIPV6PREFIX_SEQ TO SVC_MC_PORTAL;
GRANT SELECT ON NIDS.NIDS_DEVICE_SEQ TO SVC_MC_PORTAL;
GRANT SELECT ON NIDS.NIDS_ENTITY_GROUP_SEQ TO SVC_MC_PORTAL;
GRANT SELECT ON NIDS.NIDS_ENTITY_SEQ TO SVC_MC_PORTAL;
GRANT SELECT ON NIDS.NIDS_FILE_SEQ TO SVC_MC_PORTAL;
GRANT SELECT ON NIDS.NIDS_USER_SEQ TO SVC_MC_PORTAL;
GRANT SELECT ON NIDS.SCOPE_SEQ TO SVC_MC_PORTAL;
GRANT SELECT ON NIDS.SIGNATUREGROUPMEMBER_SEQ TO SVC_MC_PORTAL;
GRANT SELECT ON NIDS.SIGNATUREGROUP_SEQ TO SVC_MC_PORTAL;
GRANT SELECT ON PRX.PRX_POLICY_ITEM_SEQ TO SVC_MC_PORTAL;
GRANT SELECT ON STOP.CONTACT_SEQ TO SVC_MC_PORTAL;
GRANT SELECT ON TIM.BLACKLIST_VALUE_SEQ TO SVC_MC_PORTAL;
GRANT SELECT ON TIM.BLACKLIST_ZONE_FILE_SEQ TO SVC_MC_PORTAL;
GRANT SELECT ON TIM.EXCLUSION_LIST_VALUE_SEQ TO SVC_MC_PORTAL;
GRANT SELECT ON TT.ATTACHMENT_SEQ TO SVC_MC_PORTAL;
GRANT SELECT ON TT.CHANGEREQUEST_SEQ TO SVC_MC_PORTAL;
GRANT SELECT ON TT.CUSTMAINTENANCEWINDOW_SEQ TO SVC_MC_PORTAL;
GRANT SELECT ON TT.EVENTNOTIFICATION_SEQ TO SVC_MC_PORTAL;
GRANT SELECT ON TT.EVENT_SEQUENCE TO SVC_MC_PORTAL;
GRANT SELECT ON TT.MAINTENANCEWINDOW_SEQ TO SVC_MC_PORTAL;
GRANT SELECT ON TT.ROLLOUTWINDOW_SEQ TO SVC_MC_PORTAL;
GRANT SELECT ON TT.SERVICEWINDOW_SEQ TO SVC_MC_PORTAL;
GRANT SELECT ON TT.TICKETDOCSPAGE_SEQ TO SVC_MC_PORTAL;
GRANT SELECT ON TT.TICKETRATING_SEQ TO SVC_MC_PORTAL;
GRANT SELECT ON TT.TICKET_SEQUENCE TO SVC_MC_PORTAL;
GRANT SELECT ON TT.TODOITEM_SEQ TO SVC_MC_PORTAL;
GRANT SELECT ON VPN.PARTNER_ACCESS_RANGE_SEQUENCE TO SVC_MC_PORTAL;
GRANT SELECT ON VPN.PARTNER_CONTACT_SEQUENCE TO SVC_MC_PORTAL;
GRANT SELECT ON VPN.PARTNER_IFACE_SEQUENCE TO SVC_MC_PORTAL;
GRANT SELECT ON VPN.PARTNER_LOCATION_SEQUENCE TO SVC_MC_PORTAL;
GRANT SELECT ON VPN.PARTNER_MONITORING_SEQUENCE TO SVC_MC_PORTAL;
GRANT SELECT ON VPN.PARTNER_PHASE1_SEQUENCE TO SVC_MC_PORTAL;
GRANT SELECT ON VPN.PARTNER_PHASE2_SEQUENCE TO SVC_MC_PORTAL;
GRANT SELECT ON VPN.PARTNER_STATIC_NET_SEQUENCE TO SVC_MC_PORTAL;
GRANT SELECT ON APPID.APP TO SVC_MC_PORTAL;
GRANT SELECT ON APPID.APP_2_BANDWIDTH_PROFILE_MEMBER TO SVC_MC_PORTAL;
GRANT DELETE ON APPID.APP_2_PATH_OVERRIDE_MEMBER TO SVC_MC_PORTAL;
GRANT INSERT ON APPID.APP_2_PATH_OVERRIDE_MEMBER TO SVC_MC_PORTAL;
GRANT SELECT ON APPID.APP_2_PATH_OVERRIDE_MEMBER TO SVC_MC_PORTAL;
GRANT UPDATE ON APPID.APP_2_PATH_OVERRIDE_MEMBER TO SVC_MC_PORTAL;
GRANT SELECT ON APPID.APP_2_PATH_PROFILE_MEMBER TO SVC_MC_PORTAL;
GRANT SELECT ON APPID.APP_CATEGORY TO SVC_MC_PORTAL;
GRANT SELECT ON APPID.APP_OPTIMIZATION_HOST_ADDRESS TO SVC_MC_PORTAL;
GRANT SELECT ON APPID.APP_OPTIMIZATION_NETWORK TO SVC_MC_PORTAL;
GRANT SELECT ON APPID.APP_OPTIMIZATION_PROTOCOL TO SVC_MC_PORTAL;
GRANT SELECT ON APPID.APP_OPTIMIZATION_SETTING TO SVC_MC_PORTAL;
GRANT SELECT ON APPID.APP_TYPE TO SVC_MC_PORTAL;
GRANT SELECT ON APPID.BANDWIDTH_CONTROL_CLASS TO SVC_MC_PORTAL;
GRANT SELECT ON APPID.BANDWIDTH_CONTROL_PROFILE TO SVC_MC_PORTAL;
GRANT SELECT ON APPID.BANDWIDTH_MEMBER_2_PROFILE TO SVC_MC_PORTAL;
GRANT SELECT ON APPID.BANDWIDTH_PROFILE_MEMBER TO SVC_MC_PORTAL;
GRANT SELECT ON APPID.OPTIMIZATION_POOL TO SVC_MC_PORTAL;
GRANT SELECT ON APPID.OPTIMIZATION_POOL_2_SERVICE TO SVC_MC_PORTAL;
GRANT DELETE ON APPID.PATH_OVERRIDE_DEFAULTS TO SVC_MC_PORTAL;
GRANT INSERT ON APPID.PATH_OVERRIDE_DEFAULTS TO SVC_MC_PORTAL;
GRANT SELECT ON APPID.PATH_OVERRIDE_DEFAULTS TO SVC_MC_PORTAL;
GRANT UPDATE ON APPID.PATH_OVERRIDE_DEFAULTS TO SVC_MC_PORTAL;
GRANT DELETE ON APPID.PATH_OVERRIDE_MEMBER_LINK TO SVC_MC_PORTAL;
GRANT INSERT ON APPID.PATH_OVERRIDE_MEMBER_LINK TO SVC_MC_PORTAL;
GRANT SELECT ON APPID.PATH_OVERRIDE_MEMBER_LINK TO SVC_MC_PORTAL;
GRANT UPDATE ON APPID.PATH_OVERRIDE_MEMBER_LINK TO SVC_MC_PORTAL;
GRANT SELECT ON APPID.PATH_PROFILE_2_LINK_CLASS TO SVC_MC_PORTAL;
GRANT SELECT ON APPID.PATH_PROFILE_MEMBER_2_PROFILE TO SVC_MC_PORTAL;
GRANT SELECT ON APPID.PATH_PROFILE_MEMBER_LINK TO SVC_MC_PORTAL;
GRANT SELECT ON APPID.PATH_SELECTION_FAILOVER_TYPE TO SVC_MC_PORTAL;
GRANT SELECT ON APPID.PATH_SELECTION_LINK_CLASS TO SVC_MC_PORTAL;
GRANT DELETE ON APPID.PATH_SELECTION_OVERRIDE_MEMBER TO SVC_MC_PORTAL;
GRANT INSERT ON APPID.PATH_SELECTION_OVERRIDE_MEMBER TO SVC_MC_PORTAL;
GRANT SELECT ON APPID.PATH_SELECTION_OVERRIDE_MEMBER TO SVC_MC_PORTAL;
GRANT UPDATE ON APPID.PATH_SELECTION_OVERRIDE_MEMBER TO SVC_MC_PORTAL;
GRANT SELECT ON APPID.PATH_SELECTION_PROFILE TO SVC_MC_PORTAL;
GRANT SELECT ON APPID.PATH_SELECTION_PROFILE_MEMBER TO SVC_MC_PORTAL;
GRANT SELECT ON APPID.PATH_SELECTION_STICKINESS TO SVC_MC_PORTAL;
GRANT SELECT ON APPID.QUICKID_DNS TO SVC_MC_PORTAL;
GRANT SELECT ON APPID.QUICKID_NET4 TO SVC_MC_PORTAL;
GRANT SELECT ON APPID.QUICKID_NET6 TO SVC_MC_PORTAL;
GRANT SELECT ON APPID.QUICKID_PROTO TO SVC_MC_PORTAL;
GRANT SELECT ON APPID.QUICKID_TOS TO SVC_MC_PORTAL;
GRANT SELECT ON APPID.WAN_OPTIMIZATION_EXCEPTION TO SVC_MC_PORTAL;
GRANT DELETE ON AUTH.ALIAS TO SVC_MC_PORTAL;
GRANT INSERT ON AUTH.ALIAS TO SVC_MC_PORTAL;
GRANT SELECT ON AUTH.ALIAS TO SVC_MC_PORTAL;
GRANT UPDATE ON AUTH.ALIAS TO SVC_MC_PORTAL;
GRANT DELETE ON AUTH.API_KEY TO SVC_MC_PORTAL;
GRANT INSERT ON AUTH.API_KEY TO SVC_MC_PORTAL;
GRANT SELECT ON AUTH.API_KEY TO SVC_MC_PORTAL;
GRANT UPDATE ON AUTH.API_KEY TO SVC_MC_PORTAL;
GRANT SELECT ON AUTH.AUTHHOST TO SVC_MC_PORTAL;
GRANT SELECT ON AUTH.AUTHHOST2AUTHSYS TO SVC_MC_PORTAL;
GRANT SELECT ON AUTH.AUTHSYS TO SVC_MC_PORTAL;
GRANT SELECT ON AUTH.AUTHTYPE TO SVC_MC_PORTAL;
GRANT DELETE ON AUTH.CONSENTED_TERM TO SVC_MC_PORTAL;
GRANT INSERT ON AUTH.CONSENTED_TERM TO SVC_MC_PORTAL;
GRANT SELECT ON AUTH.CONSENTED_TERM TO SVC_MC_PORTAL;
GRANT UPDATE ON AUTH.CONSENTED_TERM TO SVC_MC_PORTAL;
GRANT SELECT ON AUTH.CONSENTED_TERM_TYPE TO SVC_MC_PORTAL;
GRANT SELECT ON AUTH.DIRTYAUTHHOST TO SVC_MC_PORTAL;
GRANT SELECT ON AUTH.GROUPS TO SVC_MC_PORTAL;
GRANT SELECT ON AUTH.HTML_MAIL_PART TO SVC_MC_PORTAL;
GRANT SELECT ON AUTH.HTML_MAIL_PART_TYPE TO SVC_MC_PORTAL;
GRANT SELECT ON AUTH.HTML_MAIL_TEMPLATE TO SVC_MC_PORTAL;
GRANT DELETE ON AUTH.LOGIN TO SVC_MC_PORTAL;
GRANT INSERT ON AUTH.LOGIN TO SVC_MC_PORTAL;
GRANT SELECT ON AUTH.LOGIN TO SVC_MC_PORTAL;
GRANT UPDATE ON AUTH.LOGIN TO SVC_MC_PORTAL;
GRANT DELETE ON AUTH.LOGIN2GROUPS TO SVC_MC_PORTAL;
GRANT INSERT ON AUTH.LOGIN2GROUPS TO SVC_MC_PORTAL;
GRANT SELECT ON AUTH.LOGIN2GROUPS TO SVC_MC_PORTAL;
GRANT UPDATE ON AUTH.LOGIN2GROUPS TO SVC_MC_PORTAL;
GRANT DELETE ON AUTH.LOGIN2PROFILE TO SVC_MC_PORTAL;
GRANT INSERT ON AUTH.LOGIN2PROFILE TO SVC_MC_PORTAL;
GRANT SELECT ON AUTH.LOGIN2PROFILE TO SVC_MC_PORTAL;
GRANT UPDATE ON AUTH.LOGIN2PROFILE TO SVC_MC_PORTAL;
GRANT DELETE ON AUTH.LOGIN2TUNNELGROUP TO SVC_MC_PORTAL;
GRANT INSERT ON AUTH.LOGIN2TUNNELGROUP TO SVC_MC_PORTAL;
GRANT SELECT ON AUTH.LOGIN2TUNNELGROUP TO SVC_MC_PORTAL;
GRANT UPDATE ON AUTH.LOGIN2TUNNELGROUP TO SVC_MC_PORTAL;
GRANT SELECT ON AUTH.LOGINTYPE TO SVC_MC_PORTAL;
GRANT SELECT ON AUTH.MV_SERVICE_ACCESS TO SVC_MC_PORTAL;
GRANT SELECT ON AUTH.PASSWORDTYPE TO SVC_MC_PORTAL;
GRANT SELECT ON AUTH.PERMISSION TO SVC_MC_PORTAL;
GRANT DELETE ON AUTH.PROFILE TO SVC_MC_PORTAL;
GRANT INSERT ON AUTH.PROFILE TO SVC_MC_PORTAL;
GRANT SELECT ON AUTH.PROFILE TO SVC_MC_PORTAL;
GRANT UPDATE ON AUTH.PROFILE TO SVC_MC_PORTAL;
GRANT SELECT ON AUTH.PW_CHANGE_CONFIG TO SVC_MC_PORTAL;
GRANT SELECT ON AUTH.ROLE TO SVC_MC_PORTAL;
GRANT SELECT ON AUTH.SHADOWAUTHHOST TO SVC_MC_PORTAL;
GRANT SELECT ON AUTH.SHADOWAUTHHOST2AUTHHOST TO SVC_MC_PORTAL;
GRANT SELECT ON AUTH.SOFT_TOKEN_ACTIVATION_CONFIG TO SVC_MC_PORTAL;
GRANT DELETE ON AUTH.SYNCDOMAIN TO SVC_MC_PORTAL;
GRANT INSERT ON AUTH.SYNCDOMAIN TO SVC_MC_PORTAL;
GRANT SELECT ON AUTH.SYNCDOMAIN TO SVC_MC_PORTAL;
GRANT UPDATE ON AUTH.SYNCDOMAIN TO SVC_MC_PORTAL;
GRANT SELECT ON AUTH.SYNCTYPE TO SVC_MC_PORTAL;
GRANT DELETE ON AUTH.TEMP_ACCESS_KEY TO SVC_MC_PORTAL;
GRANT INSERT ON AUTH.TEMP_ACCESS_KEY TO SVC_MC_PORTAL;
GRANT SELECT ON AUTH.TEMP_ACCESS_KEY TO SVC_MC_PORTAL;
GRANT UPDATE ON AUTH.TEMP_ACCESS_KEY TO SVC_MC_PORTAL;
GRANT SELECT ON AUTH.TEMP_ACCESS_TYPE TO SVC_MC_PORTAL;
GRANT DELETE ON AUTH.TOKEN TO SVC_MC_PORTAL;
GRANT INSERT ON AUTH.TOKEN TO SVC_MC_PORTAL;
GRANT SELECT ON AUTH.TOKEN TO SVC_MC_PORTAL;
GRANT UPDATE ON AUTH.TOKEN TO SVC_MC_PORTAL;
GRANT SELECT ON AUTH.TOKENFORM TO SVC_MC_PORTAL;
GRANT SELECT ON AUTH.TOKENREPLACEMENTSTATE TO SVC_MC_PORTAL;
GRANT SELECT ON AUTH.TOKENTYPE TO SVC_MC_PORTAL;
GRANT DELETE ON AUTH.TOKEN_POOL TO SVC_MC_PORTAL;
GRANT INSERT ON AUTH.TOKEN_POOL TO SVC_MC_PORTAL;
GRANT SELECT ON AUTH.TOKEN_POOL TO SVC_MC_PORTAL;
GRANT UPDATE ON AUTH.TOKEN_POOL TO SVC_MC_PORTAL;
GRANT SELECT ON AUTH.TUNNELGROUP TO SVC_MC_PORTAL;
GRANT DELETE ON AUTH.USER_COMPANY_SCOPE TO SVC_MC_PORTAL;
GRANT INSERT ON AUTH.USER_COMPANY_SCOPE TO SVC_MC_PORTAL;
GRANT SELECT ON AUTH.USER_COMPANY_SCOPE TO SVC_MC_PORTAL;
GRANT UPDATE ON AUTH.USER_COMPANY_SCOPE TO SVC_MC_PORTAL;
GRANT DELETE ON AUTH.USER_COMPANY_UNIT_SCOPE TO SVC_MC_PORTAL;
GRANT INSERT ON AUTH.USER_COMPANY_UNIT_SCOPE TO SVC_MC_PORTAL;
GRANT SELECT ON AUTH.USER_COMPANY_UNIT_SCOPE TO SVC_MC_PORTAL;
GRANT UPDATE ON AUTH.USER_COMPANY_UNIT_SCOPE TO SVC_MC_PORTAL;
GRANT DELETE ON AUTH.USER_PERMISSION TO SVC_MC_PORTAL;
GRANT INSERT ON AUTH.USER_PERMISSION TO SVC_MC_PORTAL;
GRANT SELECT ON AUTH.USER_PERMISSION TO SVC_MC_PORTAL;
GRANT UPDATE ON AUTH.USER_PERMISSION TO SVC_MC_PORTAL;
GRANT SELECT ON AUTH.USER_ROLE TO SVC_MC_PORTAL;
GRANT SELECT ON AUTH.USER_ROLE2REQUIRED_ROLE TO SVC_MC_PORTAL;
GRANT SELECT ON AUTH.USER_ROLE_SCOPE_TYPE TO SVC_MC_PORTAL;
GRANT DELETE ON AUTH.USER_SERVICE_SCOPE TO SVC_MC_PORTAL;
GRANT INSERT ON AUTH.USER_SERVICE_SCOPE TO SVC_MC_PORTAL;
GRANT SELECT ON AUTH.USER_SERVICE_SCOPE TO SVC_MC_PORTAL;
GRANT UPDATE ON AUTH.USER_SERVICE_SCOPE TO SVC_MC_PORTAL;
GRANT DELETE ON AUTH.USER_SERVICE_TYPE_SCOPE TO SVC_MC_PORTAL;
GRANT INSERT ON AUTH.USER_SERVICE_TYPE_SCOPE TO SVC_MC_PORTAL;
GRANT SELECT ON AUTH.USER_SERVICE_TYPE_SCOPE TO SVC_MC_PORTAL;
GRANT UPDATE ON AUTH.USER_SERVICE_TYPE_SCOPE TO SVC_MC_PORTAL;
GRANT SELECT ON AUTH.USER_UNIT TO SVC_MC_PORTAL;
GRANT SELECT ON AUTH.USER_UNIT2GROUPS TO SVC_MC_PORTAL;
GRANT SELECT ON AUTH.USER_UNIT2TUNNELGROUP TO SVC_MC_PORTAL;
GRANT DELETE ON AUTH.USER_UNIT_SCOPE TO SVC_MC_PORTAL;
GRANT INSERT ON AUTH.USER_UNIT_SCOPE TO SVC_MC_PORTAL;
GRANT SELECT ON AUTH.USER_UNIT_SCOPE TO SVC_MC_PORTAL;
GRANT UPDATE ON AUTH.USER_UNIT_SCOPE TO SVC_MC_PORTAL;
GRANT DELETE ON CERTS.CERTIFICATE TO SVC_MC_PORTAL;
GRANT INSERT ON CERTS.CERTIFICATE TO SVC_MC_PORTAL;
GRANT SELECT ON CERTS.CERTIFICATE TO SVC_MC_PORTAL;
GRANT UPDATE ON CERTS.CERTIFICATE TO SVC_MC_PORTAL;
GRANT SELECT ON CERTS.CERTIFICATE_SCOPE_TYPE TO SVC_MC_PORTAL;
GRANT DELETE ON CERTS.CERTIFICATE_USAGE TO SVC_MC_PORTAL;
GRANT INSERT ON CERTS.CERTIFICATE_USAGE TO SVC_MC_PORTAL;
GRANT SELECT ON CERTS.CERTIFICATE_USAGE TO SVC_MC_PORTAL;
GRANT UPDATE ON CERTS.CERTIFICATE_USAGE TO SVC_MC_PORTAL;
GRANT DELETE ON CERTS.CSR TO SVC_MC_PORTAL;
GRANT INSERT ON CERTS.CSR TO SVC_MC_PORTAL;
GRANT SELECT ON CERTS.CSR TO SVC_MC_PORTAL;
GRANT UPDATE ON CERTS.CSR TO SVC_MC_PORTAL;
GRANT DELETE ON CERTS.SAN TO SVC_MC_PORTAL;
GRANT INSERT ON CERTS.SAN TO SVC_MC_PORTAL;
GRANT SELECT ON CERTS.SAN TO SVC_MC_PORTAL;
GRANT UPDATE ON CERTS.SAN TO SVC_MC_PORTAL;
GRANT SELECT ON ESP.MC_CENTER TO SVC_MC_PORTAL;
GRANT DELETE ON ESP.MC_CENTER_CONTACT TO SVC_MC_PORTAL;
GRANT INSERT ON ESP.MC_CENTER_CONTACT TO SVC_MC_PORTAL;
GRANT SELECT ON ESP.MC_CENTER_CONTACT TO SVC_MC_PORTAL;
GRANT UPDATE ON ESP.MC_CENTER_CONTACT TO SVC_MC_PORTAL;
GRANT SELECT ON ESP.SPECIAL_DAY TO SVC_MC_PORTAL;
GRANT SELECT ON FW.ACTION TO SVC_MC_PORTAL;
GRANT SELECT ON FW.APP_GROUP TO SVC_MC_PORTAL;
GRANT SELECT ON FW.APP_GROUP2APP TO SVC_MC_PORTAL;
GRANT SELECT ON FW.APP_GROUP2APP_GROUP TO SVC_MC_PORTAL;
GRANT SELECT ON FW.CHE_DNAT_SRC_ZONE TO SVC_MC_PORTAL;
GRANT SELECT ON FW.CHE_SNAT_DST_ZONE TO SVC_MC_PORTAL;
GRANT SELECT ON FW.CHE_SNAT_SRC_ZONE TO SVC_MC_PORTAL;
GRANT SELECT ON FW.CONFIG_LOCK TO SVC_MC_PORTAL;
GRANT SELECT ON FW.DESTINATION_NAT_RULE TO SVC_MC_PORTAL;
GRANT SELECT ON FW.DESTINATION_NAT_RULE2TICKET TO SVC_MC_PORTAL;
GRANT SELECT ON FW.DNS_OBJECT TO SVC_MC_PORTAL;
GRANT SELECT ON FW.EXTERNAL_IP_LIST TO SVC_MC_PORTAL;
GRANT SELECT ON FW.ICMPV6_TYPE TO SVC_MC_PORTAL;
GRANT SELECT ON FW.ICMP_TYPE TO SVC_MC_PORTAL;
GRANT SELECT ON FW.IP_ADDRESS TO SVC_MC_PORTAL;
GRANT SELECT ON FW.IP_GROUP TO SVC_MC_PORTAL;
GRANT SELECT ON FW.IP_GROUP_MEMBER TO SVC_MC_PORTAL;
GRANT SELECT ON FW.IP_PROTOCOL TO SVC_MC_PORTAL;
GRANT SELECT ON FW.IP_SERVICE TO SVC_MC_PORTAL;
GRANT SELECT ON FW.IP_SERVICE2TCP_FLAG TO SVC_MC_PORTAL;
GRANT SELECT ON FW.LOG_TARGET TO SVC_MC_PORTAL;
GRANT SELECT ON FW.MEMBER_TYPE TO SVC_MC_PORTAL;
GRANT SELECT ON FW.MEMBER_USAGE TO SVC_MC_PORTAL;
GRANT SELECT ON FW.NAT_ACTION TO SVC_MC_PORTAL;
GRANT SELECT ON FW.NAT_SECTION TO SVC_MC_PORTAL;
GRANT SELECT ON FW.NAT_SECTION_TYPE TO SVC_MC_PORTAL;
GRANT SELECT ON FW.POLICY TO SVC_MC_PORTAL;
GRANT SELECT ON FW.RULE TO SVC_MC_PORTAL;
GRANT SELECT ON FW.RULE2TICKET TO SVC_MC_PORTAL;
GRANT SELECT ON FW.SCOPED_IP_GROUP TO SVC_MC_PORTAL;
GRANT SELECT ON FW.SCOPED_IP_GROUP_MEMBER TO SVC_MC_PORTAL;
GRANT SELECT ON FW.SCOPED_IP_GROUP_MEMBER_TYPE TO SVC_MC_PORTAL;
GRANT SELECT ON FW.SCOPED_IP_GROUP_SCOPE TO SVC_MC_PORTAL;
GRANT SELECT ON FW.SECTION TO SVC_MC_PORTAL;
GRANT SELECT ON FW.SERVICE_GROUP TO SVC_MC_PORTAL;
GRANT SELECT ON FW.SERVICE_GROUP2IP_SERVICE TO SVC_MC_PORTAL;
GRANT SELECT ON FW.SERVICE_GROUP2SERVICE_GROUP TO SVC_MC_PORTAL;
GRANT SELECT ON FW.SOURCE_NAT_RULE TO SVC_MC_PORTAL;
GRANT SELECT ON FW.SOURCE_NAT_RULE2TICKET TO SVC_MC_PORTAL;
GRANT SELECT ON FW.SUB_SECTION TO SVC_MC_PORTAL;
GRANT SELECT ON FW.SUB_SECTION_TYPE TO SVC_MC_PORTAL;
GRANT SELECT ON FW.TCP_FLAG TO SVC_MC_PORTAL;
GRANT SELECT ON FW.ZONE TO SVC_MC_PORTAL;
GRANT SELECT ON FW.ZONE_MEMBER TO SVC_MC_PORTAL;
GRANT SELECT ON FYI.AFFECTED_HOST TO SVC_MC_PORTAL;
GRANT DELETE ON FYI.FILTER_COMPANY TO SVC_MC_PORTAL;
GRANT INSERT ON FYI.FILTER_COMPANY TO SVC_MC_PORTAL;
GRANT SELECT ON FYI.FILTER_COMPANY TO SVC_MC_PORTAL;
GRANT UPDATE ON FYI.FILTER_COMPANY TO SVC_MC_PORTAL;
GRANT DELETE ON FYI.FILTER_COMPANY_UNIT TO SVC_MC_PORTAL;
GRANT INSERT ON FYI.FILTER_COMPANY_UNIT TO SVC_MC_PORTAL;
GRANT SELECT ON FYI.FILTER_COMPANY_UNIT TO SVC_MC_PORTAL;
GRANT UPDATE ON FYI.FILTER_COMPANY_UNIT TO SVC_MC_PORTAL;
GRANT DELETE ON FYI.FILTER_SERVICE TO SVC_MC_PORTAL;
GRANT INSERT ON FYI.FILTER_SERVICE TO SVC_MC_PORTAL;
GRANT SELECT ON FYI.FILTER_SERVICE TO SVC_MC_PORTAL;
GRANT UPDATE ON FYI.FILTER_SERVICE TO SVC_MC_PORTAL;
GRANT DELETE ON FYI.FILTER_SERVICE_TYPE TO SVC_MC_PORTAL;
GRANT INSERT ON FYI.FILTER_SERVICE_TYPE TO SVC_MC_PORTAL;
GRANT SELECT ON FYI.FILTER_SERVICE_TYPE TO SVC_MC_PORTAL;
GRANT UPDATE ON FYI.FILTER_SERVICE_TYPE TO SVC_MC_PORTAL;
GRANT DELETE ON FYI.FILTER_SUBJECT_REGEX TO SVC_MC_PORTAL;
GRANT INSERT ON FYI.FILTER_SUBJECT_REGEX TO SVC_MC_PORTAL;
GRANT SELECT ON FYI.FILTER_SUBJECT_REGEX TO SVC_MC_PORTAL;
GRANT UPDATE ON FYI.FILTER_SUBJECT_REGEX TO SVC_MC_PORTAL;
GRANT DELETE ON FYI.FILTER_TARGET_NAME TO SVC_MC_PORTAL;
GRANT INSERT ON FYI.FILTER_TARGET_NAME TO SVC_MC_PORTAL;
GRANT SELECT ON FYI.FILTER_TARGET_NAME TO SVC_MC_PORTAL;
GRANT UPDATE ON FYI.FILTER_TARGET_NAME TO SVC_MC_PORTAL;
GRANT SELECT ON FYI.LAST_SEEN TO SVC_MC_PORTAL;
GRANT SELECT ON FYI.NOTIFICATION_EVENT TO SVC_MC_PORTAL;
GRANT SELECT ON FYI.NOTIFICATION_TYPE TO SVC_MC_PORTAL;
GRANT DELETE ON FYI.SUBSCRIPTION TO SVC_MC_PORTAL;
GRANT INSERT ON FYI.SUBSCRIPTION TO SVC_MC_PORTAL;
GRANT SELECT ON FYI.SUBSCRIPTION TO SVC_MC_PORTAL;
GRANT UPDATE ON FYI.SUBSCRIPTION TO SVC_MC_PORTAL;
GRANT SELECT ON FYI.TARGET TO SVC_MC_PORTAL;
GRANT SELECT ON FYI.TARGET_NAME TO SVC_MC_PORTAL;
GRANT SELECT ON FYI.TOPIC TO SVC_MC_PORTAL;
GRANT SELECT ON FYI.TOPIC_GROUP TO SVC_MC_PORTAL;
GRANT SELECT ON GUMA2.EXTERNAL_SENSOR TO SVC_MC_PORTAL;
GRANT SELECT ON GUMA2.HEARTBEAT TO SVC_MC_PORTAL;
GRANT SELECT ON GUMA2.LIBRARY_VERSION TO SVC_MC_PORTAL;
GRANT SELECT ON GUMA2.PATTERN TO SVC_MC_PORTAL;
GRANT SELECT ON GUMA2.SENSOR_TYPE TO SVC_MC_PORTAL;
GRANT SELECT ON GUMA2.SIGNATURE TO SVC_MC_PORTAL;
GRANT DELETE ON GUMA2.SUPPRESSED_SIGNATURE TO SVC_MC_PORTAL;
GRANT INSERT ON GUMA2.SUPPRESSED_SIGNATURE TO SVC_MC_PORTAL;
GRANT SELECT ON GUMA2.SUPPRESSED_SIGNATURE TO SVC_MC_PORTAL;
GRANT UPDATE ON GUMA2.SUPPRESSED_SIGNATURE TO SVC_MC_PORTAL;
GRANT SELECT ON GUMA2.SYSLOG_FACILITY TO SVC_MC_PORTAL;
GRANT SELECT ON GUMA2.SYSLOG_MESSAGE TO SVC_MC_PORTAL;
GRANT SELECT ON GUMA2.SYSLOG_MESSAGE_TYPE TO SVC_MC_PORTAL;
GRANT SELECT ON GUMA2.SYSLOG_SEVERITY TO SVC_MC_PORTAL;
GRANT DELETE ON MAIL.CUSTOM_POLICY_LIST TO SVC_MC_PORTAL;
GRANT INSERT ON MAIL.CUSTOM_POLICY_LIST TO SVC_MC_PORTAL;
GRANT SELECT ON MAIL.CUSTOM_POLICY_LIST TO SVC_MC_PORTAL;
GRANT UPDATE ON MAIL.CUSTOM_POLICY_LIST TO SVC_MC_PORTAL;
GRANT DELETE ON MAIL.CUSTOM_POLICY_LIST_VALUE TO SVC_MC_PORTAL;
GRANT INSERT ON MAIL.CUSTOM_POLICY_LIST_VALUE TO SVC_MC_PORTAL;
GRANT SELECT ON MAIL.CUSTOM_POLICY_LIST_VALUE TO SVC_MC_PORTAL;
GRANT UPDATE ON MAIL.CUSTOM_POLICY_LIST_VALUE TO SVC_MC_PORTAL;
GRANT SELECT ON MAIL.DMARC_DISPOSITION TO SVC_MC_PORTAL;
GRANT SELECT ON MAIL.DMARC_DKIM_RESULT TO SVC_MC_PORTAL;
GRANT SELECT ON MAIL.DMARC_REPORT TO SVC_MC_PORTAL;
GRANT SELECT ON MAIL.DMARC_REPORT_DOMAIN TO SVC_MC_PORTAL;
GRANT SELECT ON MAIL.DMARC_REPORT_ORG TO SVC_MC_PORTAL;
GRANT SELECT ON MAIL.DMARC_REPORT_RECORD TO SVC_MC_PORTAL;
GRANT SELECT ON MAIL.DMARC_SPF_RESULT TO SVC_MC_PORTAL;
GRANT SELECT ON MAIL.POLICY_LIST_TAG TO SVC_MC_PORTAL;
GRANT SELECT ON MAIL.POLICY_LIST_TYPE TO SVC_MC_PORTAL;
GRANT DELETE ON MAIL.POLICY_LIST_VALUE TO SVC_MC_PORTAL;
GRANT INSERT ON MAIL.POLICY_LIST_VALUE TO SVC_MC_PORTAL;
GRANT SELECT ON MAIL.POLICY_LIST_VALUE TO SVC_MC_PORTAL;
GRANT UPDATE ON MAIL.POLICY_LIST_VALUE TO SVC_MC_PORTAL;
GRANT DELETE ON MAIL.POLICY_LIST_VALUE_2_GROUP TO SVC_MC_PORTAL;
GRANT INSERT ON MAIL.POLICY_LIST_VALUE_2_GROUP TO SVC_MC_PORTAL;
GRANT SELECT ON MAIL.POLICY_LIST_VALUE_2_GROUP TO SVC_MC_PORTAL;
GRANT UPDATE ON MAIL.POLICY_LIST_VALUE_2_GROUP TO SVC_MC_PORTAL;
GRANT DELETE ON MAIL.POLICY_LIST_VALUE_2_TAG TO SVC_MC_PORTAL;
GRANT INSERT ON MAIL.POLICY_LIST_VALUE_2_TAG TO SVC_MC_PORTAL;
GRANT SELECT ON MAIL.POLICY_LIST_VALUE_2_TAG TO SVC_MC_PORTAL;
GRANT UPDATE ON MAIL.POLICY_LIST_VALUE_2_TAG TO SVC_MC_PORTAL;
GRANT SELECT ON MAIL.POLICY_LIST_VALUE_TYPE TO SVC_MC_PORTAL;
GRANT DELETE ON MAIL.USER_GROUP TO SVC_MC_PORTAL;
GRANT INSERT ON MAIL.USER_GROUP TO SVC_MC_PORTAL;
GRANT SELECT ON MAIL.USER_GROUP TO SVC_MC_PORTAL;
GRANT UPDATE ON MAIL.USER_GROUP TO SVC_MC_PORTAL;
GRANT DELETE ON MC.AVAILABILITY_REPORT TO SVC_MC_PORTAL;
GRANT INSERT ON MC.AVAILABILITY_REPORT TO SVC_MC_PORTAL;
GRANT SELECT ON MC.AVAILABILITY_REPORT TO SVC_MC_PORTAL;
GRANT UPDATE ON MC.AVAILABILITY_REPORT TO SVC_MC_PORTAL;
GRANT SELECT ON MC.AVAILABILITY_REPORT_STATUS TO SVC_MC_PORTAL;
GRANT DELETE ON MC.CONNECTION_INTERRUPT_CLOSED TO SVC_MC_PORTAL;
GRANT INSERT ON MC.CONNECTION_INTERRUPT_CLOSED TO SVC_MC_PORTAL;
GRANT SELECT ON MC.CONNECTION_INTERRUPT_CLOSED TO SVC_MC_PORTAL;
GRANT UPDATE ON MC.CONNECTION_INTERRUPT_CLOSED TO SVC_MC_PORTAL;
GRANT DELETE ON MC.CONNECTION_INTERRUPT_OPEN TO SVC_MC_PORTAL;
GRANT INSERT ON MC.CONNECTION_INTERRUPT_OPEN TO SVC_MC_PORTAL;
GRANT SELECT ON MC.CONNECTION_INTERRUPT_OPEN TO SVC_MC_PORTAL;
GRANT UPDATE ON MC.CONNECTION_INTERRUPT_OPEN TO SVC_MC_PORTAL;
GRANT SELECT ON MC.CONN_SLA_CLASS TO SVC_MC_PORTAL;
GRANT SELECT ON MC.CONN_SLA_TARGET TO SVC_MC_PORTAL;
GRANT SELECT ON MC.CON_INT_TYPE TO SVC_MC_PORTAL;
GRANT SELECT ON MC.HOST_CONNECTION_STATUS TO SVC_MC_PORTAL;
GRANT SELECT ON MC.HOST_MAINTENANCE_HISTORY TO SVC_MC_PORTAL;
GRANT SELECT ON MC.INTERRUPT_REVIEW_STATUS TO SVC_MC_PORTAL;
GRANT SELECT ON MC.ISP_AVAILABILITY_REPORT TO SVC_MC_PORTAL;
GRANT SELECT ON MC.ISP_LINK_HISTORY TO SVC_MC_PORTAL;
GRANT SELECT ON MC.ISP_LINK_MAINTENANCE_HISTORY TO SVC_MC_PORTAL;
GRANT SELECT ON MC.ISP_LINK_STATUS_TYPE TO SVC_MC_PORTAL;
GRANT SELECT ON MC.MAINTENANCE_STATUS TO SVC_MC_PORTAL;
GRANT DELETE ON MC.MC_FILE TO SVC_MC_PORTAL;
GRANT INSERT ON MC.MC_FILE TO SVC_MC_PORTAL;
GRANT SELECT ON MC.MC_FILE TO SVC_MC_PORTAL;
GRANT UPDATE ON MC.MC_FILE TO SVC_MC_PORTAL;
GRANT DELETE ON MC.MC_FILE_RELEASE TO SVC_MC_PORTAL;
GRANT INSERT ON MC.MC_FILE_RELEASE TO SVC_MC_PORTAL;
GRANT SELECT ON MC.MC_FILE_RELEASE TO SVC_MC_PORTAL;
GRANT UPDATE ON MC.MC_FILE_RELEASE TO SVC_MC_PORTAL;
GRANT SELECT ON MC.MC_FILE_TYPE TO SVC_MC_PORTAL;
GRANT SELECT ON MC.MON_SERVER_CONNECTION TO SVC_MC_PORTAL;
GRANT SELECT ON MC.SERVICE_CONN_SLA_CONFIG TO SVC_MC_PORTAL;
GRANT SELECT ON MCAUDIT.APPLICATION TO SVC_MC_PORTAL;
GRANT SELECT ON MCAUDIT.COMPONENT TO SVC_MC_PORTAL;
GRANT DELETE ON MCAUDIT.RECORD TO SVC_MC_PORTAL;
GRANT INSERT ON MCAUDIT.RECORD TO SVC_MC_PORTAL;
GRANT SELECT ON MCAUDIT.RECORD TO SVC_MC_PORTAL;
GRANT UPDATE ON MCAUDIT.RECORD TO SVC_MC_PORTAL;
GRANT SELECT ON MCAUDIT.RECORD_TYPE TO SVC_MC_PORTAL;
GRANT SELECT ON MCAUDIT.SEVERITY TO SVC_MC_PORTAL;
GRANT SELECT ON MCAUDIT.SYSTEM TO SVC_MC_PORTAL;
GRANT SELECT ON MSG.OUTGOING_MAIL TO SVC_MC_PORTAL;
GRANT SELECT ON MSG.OUTGOING_MAIL_RCPT TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.ADDRESS TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.APPLICATION TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.APPLICATION_GROUP TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.APPLICATION_TEAM TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.APPLICATION_TEAM_CONTACT TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.APPLICATION_TYPE TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.BLUEPRINT TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.BLUEPRINT_ENTRY TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.CAS_PORT TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.CITY TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.CLIENT_PROFILE_TYPE TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.CLOUD_REGION_INSTANCE TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.CONFIGURATION_GROUP TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.CONFIG_DEPLOYMENT TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.CONFIG_DEPLOYMENT_ERROR TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.CONFIG_DEPLOYMENT_USE_CASE TO SVC_MC_PORTAL;
GRANT DELETE ON MSS.CONFIG_LIST TO SVC_MC_PORTAL;
GRANT INSERT ON MSS.CONFIG_LIST TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.CONFIG_LIST TO SVC_MC_PORTAL;
GRANT UPDATE ON MSS.CONFIG_LIST TO SVC_MC_PORTAL;
GRANT DELETE ON MSS.CONFIG_LIST_TYPE TO SVC_MC_PORTAL;
GRANT INSERT ON MSS.CONFIG_LIST_TYPE TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.CONFIG_LIST_TYPE TO SVC_MC_PORTAL;
GRANT UPDATE ON MSS.CONFIG_LIST_TYPE TO SVC_MC_PORTAL;
GRANT DELETE ON MSS.CONFIG_LIST_VALUE TO SVC_MC_PORTAL;
GRANT INSERT ON MSS.CONFIG_LIST_VALUE TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.CONFIG_LIST_VALUE TO SVC_MC_PORTAL;
GRANT UPDATE ON MSS.CONFIG_LIST_VALUE TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.CONFIG_LIST_VALUE_TYPE TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.CONFIG_ROLLOUT TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.CONTINENT TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.COST_CENTER TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.COUNTRY TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.CURRENCY TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.CVPN_DHCP_SERVER TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.CVPN_DNS_CONFIG TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.CVPN_GROUP TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.CVPN_GROUP_2_APP TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.CVPN_GROUP_DNS_TYPE TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.CVPN_GROUP_PROXY_TYPE TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.CVPN_POOL TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.CVPN_PROXY_CONFIG TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.CVPN_PROXY_EXCEPTION TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.CVPN_SERVICE TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.CVPN_SERVICE_DNS_TYPE TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.CVPN_SERVICE_PROXY_TYPE TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.CVPN_SPLIT_TUNNELING_ROUTE TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.DELETED_HOST TO SVC_MC_PORTAL;
GRANT DELETE ON MSS.DELETED_HOST2SERVICE_WINDOW TO SVC_MC_PORTAL;
GRANT INSERT ON MSS.DELETED_HOST2SERVICE_WINDOW TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.DELETED_HOST2SERVICE_WINDOW TO SVC_MC_PORTAL;
GRANT UPDATE ON MSS.DELETED_HOST2SERVICE_WINDOW TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.DNSSEC_ALGORITHM TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.DNSSEC_KEY TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.DNSSEC_KEY_DIGEST TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.DNSSEC_KEY_DIGEST_TYPE TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.DNSSEC_KEY_STATE TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.DNSSEC_KEY_TYPE TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.DNS_RECORD TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.DNS_SEARCH_DOMAIN_TYPE TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.DNS_ZONE TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.DNS_ZONE_GROUP TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.FIELD_MAPPING TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.FIELD_MAPPING_TYPE TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.HARDWARE TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.HARDWARE_DEPLOY_REASON TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.HARDWARE_DISPOSAL_REASON TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.HARDWARE_LC_LOCATION TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.HARDWARE_LC_STATE TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.HARDWARE_LC_TRANSIT_INFO TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.HARDWARE_LC_TRANSIT_STATE TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.HARDWARE_LICENSE TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.HARDWARE_LICENSE_REQUIREMENT TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.HARDWARE_LICENSE_TYPE TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.HARDWARE_LIFECYCLE_ITEM TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.HARDWARE_TYPE TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.HOST TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.HOST2SERVICE TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.INSTALLATION_PROJECT TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.INSTALLATION_PROJECT_ITEM TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.INTERCONTINENTAL_LATENCY TO SVC_MC_PORTAL;
GRANT DELETE ON MSS.INTERFACE TO SVC_MC_PORTAL;
GRANT INSERT ON MSS.INTERFACE TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.INTERFACE TO SVC_MC_PORTAL;
GRANT UPDATE ON MSS.INTERFACE TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.INTERFACE2ISP_LINK TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.INTERFACE_ADDRESS TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.INTERFACE_DYNAMIC_IP_STATE TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.INTERFACE_RIP_MODE TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.INTERFACE_SPEED TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.IPV6_ADDRESS TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.IPV6_PREFIX TO SVC_MC_PORTAL;
GRANT DELETE ON MSS.IPV6_STATIC_ROUTE TO SVC_MC_PORTAL;
GRANT INSERT ON MSS.IPV6_STATIC_ROUTE TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.IPV6_STATIC_ROUTE TO SVC_MC_PORTAL;
GRANT UPDATE ON MSS.IPV6_STATIC_ROUTE TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.ISP_LINK TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.ISP_LINK_SOURCING_TYPE TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.ISP_LINK_TRANSPORT_MEDIA TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.ISP_OFFER TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.KEY TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.KEY_TYPE TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.LOCAL_CONTACT TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.LOCAL_CONTACT_NOTIFICATION TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.LOCAL_CONTACT_TYPE TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.NAT_IIFACE_2_OIFACE TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.NETWORK TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.NEWS_ENTRY TO SVC_MC_PORTAL;
GRANT DELETE ON MSS.NEWS_ENTRY_2_LOGIN TO SVC_MC_PORTAL;
GRANT INSERT ON MSS.NEWS_ENTRY_2_LOGIN TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.NEWS_ENTRY_2_LOGIN TO SVC_MC_PORTAL;
GRANT UPDATE ON MSS.NEWS_ENTRY_2_LOGIN TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.NEWS_ENTRY_2_LOGIN_TYPE TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.NEWS_ENTRY_CATEGORY TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.NEWS_ENTRY_IMAGE TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.NEWS_ENTRY_STATUS TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.OBJECT_TYPE TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.OPENVPN_INTERFACE TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.OPERATING_SYSTEM TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.PING_IP TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.PING_IP_GROUP TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.PLATFORM_TYPE TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.PROJECT_ITEM_STATUS TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.RELEASE_INSTALLATION TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.SERVICE TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.SERVICE_COMPONENT TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.SERVICE_COMPONENT2SERVICE TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.SERVICE_FEATURE TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.SERVICE_FEATURE_STATE TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.SERVICE_LEVEL TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.SERVICE_OPTION_TYPE TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.SERVICE_TYPE TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.SOFTWARE_RELEASE TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.SPLIT_TUNNELING_TYPE TO SVC_MC_PORTAL;
GRANT DELETE ON MSS.STATIC_ROUTE TO SVC_MC_PORTAL;
GRANT INSERT ON MSS.STATIC_ROUTE TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.STATIC_ROUTE TO SVC_MC_PORTAL;
GRANT UPDATE ON MSS.STATIC_ROUTE TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.S_OPTION_TYPE2S_LEVEL TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.TAXCODE TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.TIME_ZONE_DATA TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.UPLOAD TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.UPLOAD_TYPE TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.VALUE TO SVC_MC_PORTAL;
GRANT SELECT ON NIDS.DIRECTION TO SVC_MC_PORTAL;
GRANT DELETE ON NIDS.DYNAMIC_SIGNATURE_GROUP TO SVC_MC_PORTAL;
GRANT INSERT ON NIDS.DYNAMIC_SIGNATURE_GROUP TO SVC_MC_PORTAL;
GRANT SELECT ON NIDS.DYNAMIC_SIGNATURE_GROUP TO SVC_MC_PORTAL;
GRANT UPDATE ON NIDS.DYNAMIC_SIGNATURE_GROUP TO SVC_MC_PORTAL;
GRANT SELECT ON NIDS.ENTITY_TYPE TO SVC_MC_PORTAL;
GRANT DELETE ON NIDS.EVENT_FILTER_RULE TO SVC_MC_PORTAL;
GRANT INSERT ON NIDS.EVENT_FILTER_RULE TO SVC_MC_PORTAL;
GRANT SELECT ON NIDS.EVENT_FILTER_RULE TO SVC_MC_PORTAL;
GRANT UPDATE ON NIDS.EVENT_FILTER_RULE TO SVC_MC_PORTAL;
GRANT SELECT ON NIDS.FILTER_ACTION TO SVC_MC_PORTAL;
GRANT DELETE ON NIDS.INVESTIGATION TO SVC_MC_PORTAL;
GRANT INSERT ON NIDS.INVESTIGATION TO SVC_MC_PORTAL;
GRANT SELECT ON NIDS.INVESTIGATION TO SVC_MC_PORTAL;
GRANT UPDATE ON NIDS.INVESTIGATION TO SVC_MC_PORTAL;
GRANT DELETE ON NIDS.INVESTIGATION_ENTRY TO SVC_MC_PORTAL;
GRANT INSERT ON NIDS.INVESTIGATION_ENTRY TO SVC_MC_PORTAL;
GRANT SELECT ON NIDS.INVESTIGATION_ENTRY TO SVC_MC_PORTAL;
GRANT UPDATE ON NIDS.INVESTIGATION_ENTRY TO SVC_MC_PORTAL;
GRANT SELECT ON NIDS.INVESTIGATION_FINDING TO SVC_MC_PORTAL;
GRANT SELECT ON NIDS.INVESTIGATION_STATUS TO SVC_MC_PORTAL;
GRANT DELETE ON NIDS.KS_ENFORCEMENT TO SVC_MC_PORTAL;
GRANT INSERT ON NIDS.KS_ENFORCEMENT TO SVC_MC_PORTAL;
GRANT SELECT ON NIDS.KS_ENFORCEMENT TO SVC_MC_PORTAL;
GRANT UPDATE ON NIDS.KS_ENFORCEMENT TO SVC_MC_PORTAL;
GRANT DELETE ON NIDS.KS_ENFORCEMENT_SCOPE TO SVC_MC_PORTAL;
GRANT INSERT ON NIDS.KS_ENFORCEMENT_SCOPE TO SVC_MC_PORTAL;
GRANT SELECT ON NIDS.KS_ENFORCEMENT_SCOPE TO SVC_MC_PORTAL;
GRANT UPDATE ON NIDS.KS_ENFORCEMENT_SCOPE TO SVC_MC_PORTAL;
GRANT SELECT ON NIDS.KS_SCOPE_TYPE TO SVC_MC_PORTAL;
GRANT SELECT ON NIDS.MDR_FILTER_ACTION TO SVC_MC_PORTAL;
GRANT DELETE ON NIDS.MDR_FILTER_RULE TO SVC_MC_PORTAL;
GRANT INSERT ON NIDS.MDR_FILTER_RULE TO SVC_MC_PORTAL;
GRANT SELECT ON NIDS.MDR_FILTER_RULE TO SVC_MC_PORTAL;
GRANT UPDATE ON NIDS.MDR_FILTER_RULE TO SVC_MC_PORTAL;
GRANT SELECT ON NIDS.MDR_SIGNATURE TO SVC_MC_PORTAL;
GRANT DELETE ON NIDS.MDR_SIGNATURE_GROUP TO SVC_MC_PORTAL;
GRANT INSERT ON NIDS.MDR_SIGNATURE_GROUP TO SVC_MC_PORTAL;
GRANT SELECT ON NIDS.MDR_SIGNATURE_GROUP TO SVC_MC_PORTAL;
GRANT UPDATE ON NIDS.MDR_SIGNATURE_GROUP TO SVC_MC_PORTAL;
GRANT DELETE ON NIDS.MDR_SIGNATURE_GROUP_MEMBER TO SVC_MC_PORTAL;
GRANT INSERT ON NIDS.MDR_SIGNATURE_GROUP_MEMBER TO SVC_MC_PORTAL;
GRANT SELECT ON NIDS.MDR_SIGNATURE_GROUP_MEMBER TO SVC_MC_PORTAL;
GRANT UPDATE ON NIDS.MDR_SIGNATURE_GROUP_MEMBER TO SVC_MC_PORTAL;
GRANT SELECT ON NIDS.MDR_SIG_GROUP_MEMBER_TYPE TO SVC_MC_PORTAL;
GRANT DELETE ON NIDS.NIDS_DEVICE TO SVC_MC_PORTAL;
GRANT INSERT ON NIDS.NIDS_DEVICE TO SVC_MC_PORTAL;
GRANT SELECT ON NIDS.NIDS_DEVICE TO SVC_MC_PORTAL;
GRANT UPDATE ON NIDS.NIDS_DEVICE TO SVC_MC_PORTAL;
GRANT DELETE ON NIDS.NIDS_ENTITY TO SVC_MC_PORTAL;
GRANT INSERT ON NIDS.NIDS_ENTITY TO SVC_MC_PORTAL;
GRANT SELECT ON NIDS.NIDS_ENTITY TO SVC_MC_PORTAL;
GRANT UPDATE ON NIDS.NIDS_ENTITY TO SVC_MC_PORTAL;
GRANT DELETE ON NIDS.NIDS_ENTITY_GROUP TO SVC_MC_PORTAL;
GRANT INSERT ON NIDS.NIDS_ENTITY_GROUP TO SVC_MC_PORTAL;
GRANT SELECT ON NIDS.NIDS_ENTITY_GROUP TO SVC_MC_PORTAL;
GRANT UPDATE ON NIDS.NIDS_ENTITY_GROUP TO SVC_MC_PORTAL;
GRANT SELECT ON NIDS.NIDS_ENTITY_TYPE TO SVC_MC_PORTAL;
GRANT SELECT ON NIDS.NIDS_EVENT TO SVC_MC_PORTAL;
GRANT DELETE ON NIDS.NIDS_FILE TO SVC_MC_PORTAL;
GRANT INSERT ON NIDS.NIDS_FILE TO SVC_MC_PORTAL;
GRANT SELECT ON NIDS.NIDS_FILE TO SVC_MC_PORTAL;
GRANT UPDATE ON NIDS.NIDS_FILE TO SVC_MC_PORTAL;
GRANT DELETE ON NIDS.NIDS_IPV6_ADDRESS TO SVC_MC_PORTAL;
GRANT INSERT ON NIDS.NIDS_IPV6_ADDRESS TO SVC_MC_PORTAL;
GRANT SELECT ON NIDS.NIDS_IPV6_ADDRESS TO SVC_MC_PORTAL;
GRANT UPDATE ON NIDS.NIDS_IPV6_ADDRESS TO SVC_MC_PORTAL;
GRANT DELETE ON NIDS.NIDS_IPV6_PREFIX TO SVC_MC_PORTAL;
GRANT INSERT ON NIDS.NIDS_IPV6_PREFIX TO SVC_MC_PORTAL;
GRANT SELECT ON NIDS.NIDS_IPV6_PREFIX TO SVC_MC_PORTAL;
GRANT UPDATE ON NIDS.NIDS_IPV6_PREFIX TO SVC_MC_PORTAL;
GRANT DELETE ON NIDS.NIDS_IP_ADDRESS TO SVC_MC_PORTAL;
GRANT INSERT ON NIDS.NIDS_IP_ADDRESS TO SVC_MC_PORTAL;
GRANT SELECT ON NIDS.NIDS_IP_ADDRESS TO SVC_MC_PORTAL;
GRANT UPDATE ON NIDS.NIDS_IP_ADDRESS TO SVC_MC_PORTAL;
GRANT DELETE ON NIDS.NIDS_IP_NETWORK TO SVC_MC_PORTAL;
GRANT INSERT ON NIDS.NIDS_IP_NETWORK TO SVC_MC_PORTAL;
GRANT SELECT ON NIDS.NIDS_IP_NETWORK TO SVC_MC_PORTAL;
GRANT UPDATE ON NIDS.NIDS_IP_NETWORK TO SVC_MC_PORTAL;
GRANT DELETE ON NIDS.NIDS_USER TO SVC_MC_PORTAL;
GRANT INSERT ON NIDS.NIDS_USER TO SVC_MC_PORTAL;
GRANT SELECT ON NIDS.NIDS_USER TO SVC_MC_PORTAL;
GRANT UPDATE ON NIDS.NIDS_USER TO SVC_MC_PORTAL;
GRANT DELETE ON NIDS.SCOPE TO SVC_MC_PORTAL;
GRANT INSERT ON NIDS.SCOPE TO SVC_MC_PORTAL;
GRANT SELECT ON NIDS.SCOPE TO SVC_MC_PORTAL;
GRANT UPDATE ON NIDS.SCOPE TO SVC_MC_PORTAL;
GRANT SELECT ON NIDS.SCOPE_TYPE TO SVC_MC_PORTAL;
GRANT SELECT ON NIDS.SIGNATURE TO SVC_MC_PORTAL;
GRANT SELECT ON NIDS.SIGNATURE_CLASS TO SVC_MC_PORTAL;
GRANT DELETE ON NIDS.SIGNATURE_GROUP TO SVC_MC_PORTAL;
GRANT INSERT ON NIDS.SIGNATURE_GROUP TO SVC_MC_PORTAL;
GRANT SELECT ON NIDS.SIGNATURE_GROUP TO SVC_MC_PORTAL;
GRANT UPDATE ON NIDS.SIGNATURE_GROUP TO SVC_MC_PORTAL;
GRANT DELETE ON NIDS.SIGNATURE_GROUP_MEMBER TO SVC_MC_PORTAL;
GRANT INSERT ON NIDS.SIGNATURE_GROUP_MEMBER TO SVC_MC_PORTAL;
GRANT SELECT ON NIDS.SIGNATURE_GROUP_MEMBER TO SVC_MC_PORTAL;
GRANT UPDATE ON NIDS.SIGNATURE_GROUP_MEMBER TO SVC_MC_PORTAL;
GRANT SELECT ON NIDS.SIGNATURE_GROUP_MEMBER_TYPE TO SVC_MC_PORTAL;
GRANT SELECT ON NIDS.SIGNATURE_REFERENCE TO SVC_MC_PORTAL;
GRANT SELECT ON NIDS.SIGNATURE_REFERENCE_TYPE TO SVC_MC_PORTAL;
GRANT DELETE ON NIDS.TICKET2RULE TO SVC_MC_PORTAL;
GRANT INSERT ON NIDS.TICKET2RULE TO SVC_MC_PORTAL;
GRANT SELECT ON NIDS.TICKET2RULE TO SVC_MC_PORTAL;
GRANT UPDATE ON NIDS.TICKET2RULE TO SVC_MC_PORTAL;
GRANT SELECT ON NIDS.XDR_TYPE TO SVC_MC_PORTAL;
GRANT SELECT ON PRX.PRX_POLICY_GROUP TO SVC_MC_PORTAL;
GRANT SELECT ON PRX.PRX_POLICY_GROUP_ENTRY TO SVC_MC_PORTAL;
GRANT DELETE ON PRX.PRX_POLICY_ITEM TO SVC_MC_PORTAL;
GRANT INSERT ON PRX.PRX_POLICY_ITEM TO SVC_MC_PORTAL;
GRANT SELECT ON PRX.PRX_POLICY_ITEM TO SVC_MC_PORTAL;
GRANT UPDATE ON PRX.PRX_POLICY_ITEM TO SVC_MC_PORTAL;
GRANT DELETE ON PRX.PRX_POLICY_ITEM2GROUP TO SVC_MC_PORTAL;
GRANT INSERT ON PRX.PRX_POLICY_ITEM2GROUP TO SVC_MC_PORTAL;
GRANT SELECT ON PRX.PRX_POLICY_ITEM2GROUP TO SVC_MC_PORTAL;
GRANT UPDATE ON PRX.PRX_POLICY_ITEM2GROUP TO SVC_MC_PORTAL;
GRANT SELECT ON PRX.PRX_POLICY_ITEM_TYPE TO SVC_MC_PORTAL;
GRANT SELECT ON PRX.PRX_POLICY_TYPE TO SVC_MC_PORTAL;
GRANT SELECT ON STOP.COMPANY TO SVC_MC_PORTAL;
GRANT SELECT ON STOP.COMPANY_AM TO SVC_MC_PORTAL;
GRANT SELECT ON STOP.COMPANY_SECTOR TO SVC_MC_PORTAL;
GRANT SELECT ON STOP.COMPANY_TAM TO SVC_MC_PORTAL;
GRANT SELECT ON STOP.COMPANY_UNIT TO SVC_MC_PORTAL;
GRANT SELECT ON STOP.COMPTYPE TO SVC_MC_PORTAL;
GRANT SELECT ON STOP.COMP_COMPTYPE_REF TO SVC_MC_PORTAL;
GRANT DELETE ON STOP.CONTACT TO SVC_MC_PORTAL;
GRANT INSERT ON STOP.CONTACT TO SVC_MC_PORTAL;
GRANT SELECT ON STOP.CONTACT TO SVC_MC_PORTAL;
GRANT UPDATE ON STOP.CONTACT TO SVC_MC_PORTAL;
GRANT SELECT ON STOP.CONTACT_HANDLING TO SVC_MC_PORTAL;
GRANT SELECT ON STOP.CONTACT_LIST TO SVC_MC_PORTAL;
GRANT SELECT ON STOP.CONTACT_LIST_MEMBER TO SVC_MC_PORTAL;
GRANT DELETE ON STOP.CONTACT_SYNC TO SVC_MC_PORTAL;
GRANT INSERT ON STOP.CONTACT_SYNC TO SVC_MC_PORTAL;
GRANT SELECT ON STOP.CONTACT_SYNC TO SVC_MC_PORTAL;
GRANT UPDATE ON STOP.CONTACT_SYNC TO SVC_MC_PORTAL;
GRANT SELECT ON STOP.CUSTOMER_REFERENCE_LINK TO SVC_MC_PORTAL;
GRANT SELECT ON STOP.PARTNER_DOMAIN TO SVC_MC_PORTAL;
GRANT SELECT ON STOP.REACH_ON_TYPE TO SVC_MC_PORTAL;
GRANT SELECT ON SVC_ZEROTRUST.ZTNA_TENANT TO SVC_MC_PORTAL;
GRANT DELETE ON TIM.BLACKLIST_VALUE TO SVC_MC_PORTAL;
GRANT INSERT ON TIM.BLACKLIST_VALUE TO SVC_MC_PORTAL;
GRANT SELECT ON TIM.BLACKLIST_VALUE TO SVC_MC_PORTAL;
GRANT UPDATE ON TIM.BLACKLIST_VALUE TO SVC_MC_PORTAL;
GRANT SELECT ON TIM.BLACKLIST_VALUE_CATEGORY TO SVC_MC_PORTAL;
GRANT SELECT ON TIM.BLACKLIST_VALUE_TYPE TO SVC_MC_PORTAL;
GRANT DELETE ON TIM.BLACKLIST_ZONE_FILE TO SVC_MC_PORTAL;
GRANT INSERT ON TIM.BLACKLIST_ZONE_FILE TO SVC_MC_PORTAL;
GRANT SELECT ON TIM.BLACKLIST_ZONE_FILE TO SVC_MC_PORTAL;
GRANT UPDATE ON TIM.BLACKLIST_ZONE_FILE TO SVC_MC_PORTAL;
GRANT DELETE ON TIM.EXCLUSION_LIST_VALUE TO SVC_MC_PORTAL;
GRANT INSERT ON TIM.EXCLUSION_LIST_VALUE TO SVC_MC_PORTAL;
GRANT SELECT ON TIM.EXCLUSION_LIST_VALUE TO SVC_MC_PORTAL;
GRANT UPDATE ON TIM.EXCLUSION_LIST_VALUE TO SVC_MC_PORTAL;
GRANT SELECT ON TIM.EXCLUSION_LIST_VALUE_TYPE TO SVC_MC_PORTAL;
GRANT DELETE ON TT.ATTACHMENT TO SVC_MC_PORTAL;
GRANT INSERT ON TT.ATTACHMENT TO SVC_MC_PORTAL;
GRANT SELECT ON TT.ATTACHMENT TO SVC_MC_PORTAL;
GRANT UPDATE ON TT.ATTACHMENT TO SVC_MC_PORTAL;
GRANT DELETE ON TT.CHANGE_REQUEST TO SVC_MC_PORTAL;
GRANT INSERT ON TT.CHANGE_REQUEST TO SVC_MC_PORTAL;
GRANT SELECT ON TT.CHANGE_REQUEST TO SVC_MC_PORTAL;
GRANT UPDATE ON TT.CHANGE_REQUEST TO SVC_MC_PORTAL;
GRANT SELECT ON TT.CHANGE_REQUEST_STATE TO SVC_MC_PORTAL;
GRANT DELETE ON TT.CUST_MAINTENANCE_WINDOW TO SVC_MC_PORTAL;
GRANT INSERT ON TT.CUST_MAINTENANCE_WINDOW TO SVC_MC_PORTAL;
GRANT SELECT ON TT.CUST_MAINTENANCE_WINDOW TO SVC_MC_PORTAL;
GRANT UPDATE ON TT.CUST_MAINTENANCE_WINDOW TO SVC_MC_PORTAL;
GRANT SELECT ON TT.ESCALATION_STATUS TO SVC_MC_PORTAL;
GRANT DELETE ON TT.EVENT TO SVC_MC_PORTAL;
GRANT INSERT ON TT.EVENT TO SVC_MC_PORTAL;
GRANT SELECT ON TT.EVENT TO SVC_MC_PORTAL;
GRANT UPDATE ON TT.EVENT TO SVC_MC_PORTAL;
GRANT SELECT ON TT.EVENT_ACTION TO SVC_MC_PORTAL;
GRANT DELETE ON TT.EVENT_NOTIFICATION TO SVC_MC_PORTAL;
GRANT INSERT ON TT.EVENT_NOTIFICATION TO SVC_MC_PORTAL;
GRANT SELECT ON TT.EVENT_NOTIFICATION TO SVC_MC_PORTAL;
GRANT UPDATE ON TT.EVENT_NOTIFICATION TO SVC_MC_PORTAL;
GRANT SELECT ON TT.EVENT_NOTIFICATION_TYPE TO SVC_MC_PORTAL;
GRANT SELECT ON TT.EVENT_SOURCE TO SVC_MC_PORTAL;
GRANT SELECT ON TT.EVENT_TYPE TO SVC_MC_PORTAL;
GRANT SELECT ON TT.EVENT_TYPE2EVENT_TYPE_GROUP TO SVC_MC_PORTAL;
GRANT SELECT ON TT.EVENT_TYPE_ACTION TO SVC_MC_PORTAL;
GRANT SELECT ON TT.EVENT_TYPE_GROUP TO SVC_MC_PORTAL;
GRANT SELECT ON TT.EVENT_TYPE_MESSAGE TO SVC_MC_PORTAL;
GRANT DELETE ON TT.HOST2SERVICE_WINDOW TO SVC_MC_PORTAL;
GRANT INSERT ON TT.HOST2SERVICE_WINDOW TO SVC_MC_PORTAL;
GRANT SELECT ON TT.HOST2SERVICE_WINDOW TO SVC_MC_PORTAL;
GRANT UPDATE ON TT.HOST2SERVICE_WINDOW TO SVC_MC_PORTAL;
GRANT SELECT ON TT.LABEL TO SVC_MC_PORTAL;
GRANT DELETE ON TT.MAINTENANCE_WINDOW TO SVC_MC_PORTAL;
GRANT INSERT ON TT.MAINTENANCE_WINDOW TO SVC_MC_PORTAL;
GRANT SELECT ON TT.MAINTENANCE_WINDOW TO SVC_MC_PORTAL;
GRANT UPDATE ON TT.MAINTENANCE_WINDOW TO SVC_MC_PORTAL;
GRANT DELETE ON TT.ROLLOUT_WINDOW TO SVC_MC_PORTAL;
GRANT INSERT ON TT.ROLLOUT_WINDOW TO SVC_MC_PORTAL;
GRANT SELECT ON TT.ROLLOUT_WINDOW TO SVC_MC_PORTAL;
GRANT UPDATE ON TT.ROLLOUT_WINDOW TO SVC_MC_PORTAL;
GRANT DELETE ON TT.SERVICE_WINDOW TO SVC_MC_PORTAL;
GRANT INSERT ON TT.SERVICE_WINDOW TO SVC_MC_PORTAL;
GRANT SELECT ON TT.SERVICE_WINDOW TO SVC_MC_PORTAL;
GRANT UPDATE ON TT.SERVICE_WINDOW TO SVC_MC_PORTAL;
GRANT SELECT ON TT.STATUS TO SVC_MC_PORTAL;
GRANT DELETE ON TT.TICKET TO SVC_MC_PORTAL;
GRANT INSERT ON TT.TICKET TO SVC_MC_PORTAL;
GRANT SELECT ON TT.TICKET TO SVC_MC_PORTAL;
GRANT UPDATE ON TT.TICKET TO SVC_MC_PORTAL;
GRANT DELETE ON TT.TICKET2MC_FILE TO SVC_MC_PORTAL;
GRANT INSERT ON TT.TICKET2MC_FILE TO SVC_MC_PORTAL;
GRANT SELECT ON TT.TICKET2MC_FILE TO SVC_MC_PORTAL;
GRANT UPDATE ON TT.TICKET2MC_FILE TO SVC_MC_PORTAL;
GRANT DELETE ON TT.TICKET2RELATED_TICKET TO SVC_MC_PORTAL;
GRANT INSERT ON TT.TICKET2RELATED_TICKET TO SVC_MC_PORTAL;
GRANT SELECT ON TT.TICKET2RELATED_TICKET TO SVC_MC_PORTAL;
GRANT UPDATE ON TT.TICKET2RELATED_TICKET TO SVC_MC_PORTAL;
GRANT DELETE ON TT.TICKET_DOCS_PAGE TO SVC_MC_PORTAL;
GRANT INSERT ON TT.TICKET_DOCS_PAGE TO SVC_MC_PORTAL;
GRANT SELECT ON TT.TICKET_DOCS_PAGE TO SVC_MC_PORTAL;
GRANT UPDATE ON TT.TICKET_DOCS_PAGE TO SVC_MC_PORTAL;
GRANT DELETE ON TT.TICKET_RATING TO SVC_MC_PORTAL;
GRANT INSERT ON TT.TICKET_RATING TO SVC_MC_PORTAL;
GRANT SELECT ON TT.TICKET_RATING TO SVC_MC_PORTAL;
GRANT UPDATE ON TT.TICKET_RATING TO SVC_MC_PORTAL;
GRANT SELECT ON TT.TICKET_REQUEST_CLASSIFICATION TO SVC_MC_PORTAL;
GRANT SELECT ON TT.TICKET_TYPE TO SVC_MC_PORTAL;
GRANT DELETE ON TT.TODO_ITEM TO SVC_MC_PORTAL;
GRANT INSERT ON TT.TODO_ITEM TO SVC_MC_PORTAL;
GRANT SELECT ON TT.TODO_ITEM TO SVC_MC_PORTAL;
GRANT UPDATE ON TT.TODO_ITEM TO SVC_MC_PORTAL;
GRANT SELECT ON TT.TODO_ITEM_STATUS TO SVC_MC_PORTAL;
GRANT SELECT ON TT.TODO_LIST_TEMPLATE TO SVC_MC_PORTAL;
GRANT SELECT ON VPN.PARTITION TO SVC_MC_PORTAL;
GRANT DELETE ON VPN.PARTNER_ACCESS_RANGE TO SVC_MC_PORTAL;
GRANT INSERT ON VPN.PARTNER_ACCESS_RANGE TO SVC_MC_PORTAL;
GRANT SELECT ON VPN.PARTNER_ACCESS_RANGE TO SVC_MC_PORTAL;
GRANT UPDATE ON VPN.PARTNER_ACCESS_RANGE TO SVC_MC_PORTAL;
GRANT DELETE ON VPN.PARTNER_CONTACT TO SVC_MC_PORTAL;
GRANT INSERT ON VPN.PARTNER_CONTACT TO SVC_MC_PORTAL;
GRANT SELECT ON VPN.PARTNER_CONTACT TO SVC_MC_PORTAL;
GRANT UPDATE ON VPN.PARTNER_CONTACT TO SVC_MC_PORTAL;
GRANT DELETE ON VPN.PARTNER_IFACE TO SVC_MC_PORTAL;
GRANT INSERT ON VPN.PARTNER_IFACE TO SVC_MC_PORTAL;
GRANT SELECT ON VPN.PARTNER_IFACE TO SVC_MC_PORTAL;
GRANT UPDATE ON VPN.PARTNER_IFACE TO SVC_MC_PORTAL;
GRANT DELETE ON VPN.PARTNER_LOCATION TO SVC_MC_PORTAL;
GRANT INSERT ON VPN.PARTNER_LOCATION TO SVC_MC_PORTAL;
GRANT SELECT ON VPN.PARTNER_LOCATION TO SVC_MC_PORTAL;
GRANT UPDATE ON VPN.PARTNER_LOCATION TO SVC_MC_PORTAL;
GRANT DELETE ON VPN.PARTNER_MONITORING TO SVC_MC_PORTAL;
GRANT INSERT ON VPN.PARTNER_MONITORING TO SVC_MC_PORTAL;
GRANT SELECT ON VPN.PARTNER_MONITORING TO SVC_MC_PORTAL;
GRANT UPDATE ON VPN.PARTNER_MONITORING TO SVC_MC_PORTAL;
GRANT DELETE ON VPN.PARTNER_PHASE1 TO SVC_MC_PORTAL;
GRANT INSERT ON VPN.PARTNER_PHASE1 TO SVC_MC_PORTAL;
GRANT SELECT ON VPN.PARTNER_PHASE1 TO SVC_MC_PORTAL;
GRANT UPDATE ON VPN.PARTNER_PHASE1 TO SVC_MC_PORTAL;
GRANT DELETE ON VPN.PARTNER_PHASE2 TO SVC_MC_PORTAL;
GRANT INSERT ON VPN.PARTNER_PHASE2 TO SVC_MC_PORTAL;
GRANT SELECT ON VPN.PARTNER_PHASE2 TO SVC_MC_PORTAL;
GRANT UPDATE ON VPN.PARTNER_PHASE2 TO SVC_MC_PORTAL;
GRANT DELETE ON VPN.PARTNER_STATIC_NET TO SVC_MC_PORTAL;
GRANT INSERT ON VPN.PARTNER_STATIC_NET TO SVC_MC_PORTAL;
GRANT SELECT ON VPN.PARTNER_STATIC_NET TO SVC_MC_PORTAL;
GRANT UPDATE ON VPN.PARTNER_STATIC_NET TO SVC_MC_PORTAL;
GRANT SELECT ON VPN.TUNNEL TO SVC_MC_PORTAL;
GRANT SELECT ON VPN.TUNNEL_RATING TO SVC_MC_PORTAL;
GRANT SELECT ON VPN.TUNNEL_RATING_INTERVAL TO SVC_MC_PORTAL;
GRANT SELECT ON VPN.VPN TO SVC_MC_PORTAL;
GRANT SELECT ON VPN.VPN_MEMBER TO SVC_MC_PORTAL;
GRANT SELECT ON MAIL.DMARC_REPORT_SUMMARY TO SVC_MC_PORTAL;
GRANT SELECT ON MC.CONNECTION_INTERRUPT TO SVC_MC_PORTAL;
GRANT SELECT ON MC.V_HOST_CONNECTION_STATUS TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.TIME_ZONE TO SVC_MC_PORTAL;
GRANT SELECT ON MSS.V_HOST_KEY_VALUE TO SVC_MC_PORTAL;
GRANT SELECT ON OSIXINFO.V_HOSTCLUSTERSTATE TO SVC_MC_PORTAL;
GRANT SELECT ON OSIXINFO.V_LAST_UPDATE TO SVC_MC_PORTAL;

--changeset tho:1591
--comment: RTNG-405: email exchange with teridion should be private ticket events
INSERT INTO STOP.PARTNER_DOMAIN (ID,"DOMAIN",PUBLIC_EVENTS)
	VALUES (242,'teridion.com',0);

--changeset mag:1592
--comment: PRX-8458: Add new policy type to support casbng exclusion list
insert into PRX.PRX_POLICY_TYPE (id, policy_type)
values (8, 'CASB_EXCLUSION')

--changeset nkj:1593
--comment: MC-28198: Clean up Atlas
DROP USER analytics_atlas CASCADE;

--changeset nop:1594
--comment: SRE-868: switch ticketautoresolve to automation
DROP USER ticketing_autoresolve; 

--changeset jad:1595
--comment: FIX: Change regex of DB Prop ztna.scaling
update mss.key k
set k.REGEXP='^[0-9]$'
where k.id=24507
  and k.name='ztna.scaling';

--changeset jkl:1596
--comment: RTNG-311: Add new DB Prop ipsec.prometheus-exporter
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (57011, 'ipsec.prometheus-exporter', 1, '0', '^[01]$', NULL, 'Enable Prometheus exporter for IPsec (Strongswan)');

--changeset aas:1597
--comment: ZTNA-1329: add new dbprop ztna.core to define if a ZTNA enforcement point (EP) is part of the core cluster
INSERT INTO MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
VALUES (57012, 'ztna.core', 1, '0', '^[01]$', NULL, 'ZTNA enforcement point (EP) on this host is part of the core cluster');

--changeset ogl:1598
--comment: DB-2551: cascade service deletion
grant delete on mss.SERVICE_COMPONENT2SERVICE to SVC_CONIFER;

--changeset nkj:1599
--comment: MC-28198: Clean up portal.sdwananalyticsmap dbprop
delete from mss.value where key_id = 22204;
delete from mss.key where id = 22204;

--changeset ogl:1600
--comment: DB-2547: unique service name
create unique index mss.IDX_SERVICE_UNAME on mss.service lower(name);

--changeset mlo:1601
--comment: remove caas_class table
alter table mss.ISP_LINK drop constraint isplink_fk16;
alter table mss.ISP_LINK drop column caas_class_id;
drop table mss.caas_class;

--changeset rha:1602
--comment: PRX-8740: remove dbprop migrate.mail.certificate_tool and migrate.proxy.certificate_tool
DELETE FROM MSS.VALUE WHERE key_id = 22602;
DELETE FROM MSS.KEY WHERE id = 22602 AND name = 'migrate.mail-smtp.certificate_tool';
DELETE FROM MSS.VALUE WHERE key_id = 56926;
DELETE FROM MSS.KEY WHERE id = 56926 AND name = 'migrate.proxy.certificate_tool';

--changeset rha:1603
--comment: MEP-2248: remove dbprop migrate.sslvpn.asav5ram
DELETE FROM MSS.VALUE WHERE key_id = 21605;
DELETE FROM MSS.KEY WHERE id = 21605 AND name = 'migrate.sslvpn.asav5ram';

--changeset fla:1604
--comment: MC-28234: Add MSS.IPV6_ADDRESS permission to webcache to be able to prefetch ISP link information
GRANT SELECT ON MSS.IPV6_ADDRESS TO WEBCACHE;

--changeset ogl:1605
--comment: DB-2547: make service name mandatory
alter table mss.service modify name not null;

--changeset ogl:1606
--comment: mark deprecated service components
update mss.SERVICE_COMPONENT set DEPRECATED=1 where INTERNAL_CODE in ('waf', 'hotspot', 'edr', 'qos', 'aqr', 'mdr', 'dns', 'incidentresponse');

--changeset isa:1607
--comment: RTNG-361: Add new DB Prop ospfd.access-list.merge-overlapping-networks
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (57013, 'ospfd.access-list.merge-overlapping-networks', 1, '0', '^[01]$', NULL, 'Merge overlapping access-list network entries in OSPF (FRRouting)');

--changeset jkl:1611
--comment: RTNG-467: Add new dbprop to enable p2p transit LANs
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (57014, 'ospfd.transit.p2p', 1, '0', '^[01]$', NULL, 'Enable point-to-point in transit LANs (FRRouting)');

--changeset jkl:1612
--comment: RTNG-467: Add new dbprop to enable prefix suppression in transit LANs
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (57015, 'ospfd.transit.suppression', 1, '0', '^[01]$', NULL, 'Enable network prefix suppression in transit LANs (FRRouting)');

--changeset ssk:1613
--comment: CLOUD-399: grant app group perms to svc_conifer
GRANT SELECT ON FW.APP_GROUP TO svc_conifer;
GRANT SELECT ON FW.APP_GROUP2APP_GROUP TO svc_conifer;
GRANT SELECT ON FW.APP_GROUP2APP TO svc_conifer;

--changeset aea:1614
--comment: OSCT-307: grant SVC_COPILOT access to tables for alfred
GRANT SELECT ON TT.EVENT_TYPE TO "SVC_COPILOT";
GRANT SELECT ON PRX.PRX_POLICY_GROUP TO "SVC_COPILOT";
GRANT SELECT ON PRX.PRX_POLICY_ITEM TO "SVC_COPILOT";
GRANT SELECT ON PRX.PRX_POLICY_ITEM_TYPE TO "SVC_COPILOT";
GRANT SELECT ON PRX.PRX_POLICY_TYPE TO "SVC_COPILOT";
GRANT SELECT ON STOP.CONTACT TO "SVC_COPILOT";

--changeset cge:1615
--comment: PRX-8734: Cleanup buildsmall usecase squid_k8s
DELETE FROM mss.CONFIG_DEPLOYMENT_USE_CASE where name='squid_k8s';

--changeset ogl:1616
--comment: DB-2641: make host/service name validation optional
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (57020, 'confmgmt.validation.hostname', 1, '1', '^[01]$', NULL, 'Whether host names are validated (company scope)');
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (57021, 'confmgmt.validation.servicename', 1, '1', '^[01]$', NULL, 'Whether service names are validated (company scope)');

--changeset gks:1618
--comment: IDS-3013: Add new DB Prop 'ndr.suricata'
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (57030, 'ndr.suricata', 1, '0', '^[01]$', NULL, 'Enable Suricata IDS Software');

--changeset mlo:1619
--comment: MC-28834: orm link from profile to logins
UPDATE AUTH."#JDO_PROPERTIES" t
SET t.VALUE = 'logins'
WHERE t.KEY='PROFILE.naming.inverse.AUTH.FK_LOGIN2PROFILE_PROFILE';

--changeset ssk:1620
--comment: CLOUD-247: Add VERSION columns to FW tables
ALTER TABLE FW.POLICY ADD VERSION NUMBER(10,0) DEFAULT 0 NOT NULL;
ALTER TABLE FW.SECTION ADD VERSION NUMBER(10,0) DEFAULT 0 NOT NULL;
ALTER TABLE FW.NAT_SECTION ADD VERSION NUMBER(10,0) DEFAULT 0 NOT NULL;
ALTER TABLE FW.RULE ADD VERSION NUMBER(10,0) DEFAULT 0 NOT NULL;
ALTER TABLE FW.DESTINATION_NAT_RULE ADD VERSION NUMBER(10,0) DEFAULT 0 NOT NULL;
ALTER TABLE FW.SOURCE_NAT_RULE ADD VERSION NUMBER(10,0) DEFAULT 0 NOT NULL;
ALTER TABLE FW.APP_GROUP ADD VERSION NUMBER(10,0) DEFAULT 0 NOT NULL;

--changeset isa:1621
--comment: RTNG-171: Add new dbprop to enable FRRouting debug logging
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (57031, 'frrouting.log.debug', 4, '', '^(\w+(:\w+(,\w+)*)?)( \w+(:\w+(,\w+)*)?)*$', NULL, 'Space separated list of FRRouting components to enable debug logs, in format "component:target_1,target_2", i.e. "ospf:bfd bgp:vnc,pbr memstats-at-exit"');

--changeset gks:1622
--comment: IDS-3015: Make zeek logs forwarding configurable
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (57032, 'ndr.zeek.logs.forwarding ', 1, '1', '^[01]$', NULL, 'Enable log forwarding for Zeek');

--changeset gks:1623
--comment: IDS-3015: Rename 'ndr.zeek.logs.forwarding ' dbprop to 'ndr.zeek.logs.forwarding'
update mss.key k
set k.NAME='ndr.zeek.logs.forwarding'
where k.id=57032
and k.name='ndr.zeek.logs.forwarding ';

--changeset isa:1624
--comment: RTNG-171: edit dbprop frrouting.log.debug REGEXP to allow "-"
update MSS.KEY k
set k.REGEXP='^([\w-]+(:[\w-]+(,[\w-]+)*)?)( [\w-]+(:[\w-]+(,[\w-]+)*)?)*$'
where k.ID=57031
and k.NAME='frrouting.log.debug';

--changeset ssk:1625
--comment: CLOUD-499: grant needed perms for firewall changes to svc_conifer
GRANT UPDATE,DELETE ON FW.IP_ADDRESS TO svc_conifer;
GRANT UPDATE,DELETE ON MSS.NETWORK TO svc_conifer;
GRANT SELECT,INSERT,UPDATE,DELETE ON FW.DNS_OBJECT TO svc_conifer;
GRANT SELECT ON FW.ICMP_TYPE TO svc_conifer;
GRANT SELECT ON FW.ICMPV6_TYPE TO svc_conifer;
GRANT SELECT,INSERT,UPDATE,DELETE ON FW.IP_SERVICE TO svc_conifer;
GRANT SELECT,INSERT,UPDATE,DELETE ON FW.SERVICE_GROUP TO svc_conifer;
GRANT SELECT,INSERT,DELETE ON FW.SERVICE_GROUP2SERVICE_GROUP TO svc_conifer;
GRANT SELECT,INSERT,DELETE ON FW.SERVICE_GROUP2IP_SERVICE TO svc_conifer;
GRANT INSERT,UPDATE,DELETE ON FW.APP_GROUP TO svc_conifer;
GRANT INSERT,DELETE ON FW.APP_GROUP2APP TO svc_conifer;
GRANT INSERT,DELETE ON FW.APP_GROUP2APP_GROUP TO svc_conifer;
GRANT INSERT,UPDATE,DELETE ON FW.IP_GROUP TO svc_conifer;
GRANT INSERT,DELETE ON FW.IP_GROUP_MEMBER TO svc_conifer;
GRANT SELECT ON FW.MEMBER_TYPE TO svc_conifer;
GRANT SELECT ON FW.MEMBER_USAGE TO svc_conifer;
GRANT SELECT,INSERT,UPDATE,DELETE ON FW.SCOPED_IP_GROUP TO svc_conifer;
GRANT SELECT,INSERT,DELETE ON FW.SCOPED_IP_GROUP_MEMBER TO svc_conifer;
GRANT SELECT ON FW.SCOPED_IP_GROUP_MEMBER_TYPE TO svc_conifer;
GRANT SELECT,INSERT,DELETE ON FW.SCOPED_IP_GROUP_SCOPE TO svc_conifer;
GRANT SELECT,INSERT,UPDATE,DELETE ON FW.SECTION TO svc_conifer;
GRANT INSERT,DELETE ON FW.SUB_SECTION TO svc_conifer;
GRANT SELECT ON FW.SUB_SECTION_TYPE TO svc_conifer;
GRANT INSERT,UPDATE,DELETE ON FW.RULE TO svc_conifer;
GRANT SELECT,DELETE ON FW.CONFIG_LOCK TO svc_conifer;
GRANT SELECT ON MSS.CVPN_POOL TO svc_conifer;
GRANT SELECT ON MSS.OPENVPN_INTERFACE TO svc_conifer;
GRANT SELECT ON FW.LOG_TARGET TO svc_conifer;
GRANT SELECT ON FW.ACTION TO svc_conifer;
GRANT SELECT ON FW.APPGROUP_SEQ TO svc_conifer;
GRANT SELECT ON FW.DNS_OBJECT_SEQ TO svc_conifer;
GRANT SELECT ON FW.FILTERRULE_SEQ TO svc_conifer;
GRANT SELECT ON FW.IPGROUPMEMBER_SEQ TO svc_conifer;
GRANT SELECT ON FW.IPGROUP_SEQ TO svc_conifer;
GRANT SELECT ON FW.IPSERVICE_SEQ TO svc_conifer;
GRANT SELECT ON FW.SCOPED_IP_GROUP_MEMBER_SEQ TO svc_conifer;
GRANT SELECT ON FW.SCOPED_IP_GROUP_SCOPE_SEQ TO svc_conifer;
GRANT SELECT ON FW.SCOPED_IP_GROUP_SEQ TO svc_conifer;
GRANT SELECT ON FW.SECTION_SEQ TO svc_conifer;
GRANT SELECT ON FW.SERVICEGROUP_SEQ TO svc_conifer;
GRANT SELECT ON FW.SUB_SECTION_SEQ TO svc_conifer;

--changeset msc:1626
--comment: NC-352: change default of rps to 1
update MSS.key k
set k.STRING_DEFAULT='1'
where k.id=56860 and k.name='rps';

--changeset mxd:1627
--comment: OSAP-1313: create new audit record types to support zitadel configuration changes in mc-config-api
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID)
VALUES (387, 'Identity Provider Configuration updated', 'zitadel_config_update', 'Identity Provider configuration updated', 1);
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID)
VALUES (388, 'Identity Provider Domains updated', 'zitadel_org_domains_update', 'Identity Provider whitelisted domains updated', 1);
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID)
VALUES (389, 'Identity Provider Federation Secret updated', 'zitadel_federation_secret_update', 'Identity Provider secret used for federation with remote IDP updated', 1);

--changeset rha:1628
--comment: MEP-2189: remove dbprop migrate.2022.sslvpn.logrelay
DELETE FROM MSS.VALUE WHERE key_id = 24519;
DELETE FROM MSS.KEY WHERE id = 24519 AND name = 'migrate.2022.sslvpn.logrelay';

--changeset sev:1630
--comment: ZTNA-1377 rename dbprop ztna.forward-proxy.dnat_ip to ztna.swg.dnat_ip
update mss.key k set k.NAME='ztna.swg.dnat_ip' where k.id=56941 and k.name='ztna.forward-proxy.dnat_ip';

--changeset ssk:1631
--comment: CLOUD-493: add grants needed for e2e tests
GRANT SELECT ON FW.CONFIGLOCK_SEQ TO svc_conifer;
GRANT INSERT ON FW.CONFIG_LOCK TO svc_conifer;

--changeset jwj:1632
--comment: MX-5687: Create a dbprop to control msgtracker log shipping
INSERT INTO MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
VALUES (57040, 'mail.msgtracker.logs_api', 1, '0', '^[01]$', NULL, 'Enable msgtracker log shipping to the Logs API for customer access');

--changeset aea:1633
--comment: OSCT-351: create a new ticket event types for alfred
insert into TT.EVENT_SOURCE (ID, NAME, HEX_COLOR)
values (8, 'alfred', 'd4f997');

insert into TT.EVENT_TYPE (ID, NAME, SOURCE, IS_NOTIFIED, ESCALATION, DESCRIPTION, SMS_MESSAGE_TEMPLATE_ID, EMAIL_MESSAGE_TEMPLATE_ID, PINNABLE, AUTOPIN)
values (10600, 'alfred proposal', 8, 0, 0, 'proposal from alfred for the user to take a decision', 1, 2, 0, 0);

insert into TT.EVENT_TYPE (ID, NAME, SOURCE, IS_NOTIFIED, ESCALATION, DESCRIPTION, SMS_MESSAGE_TEMPLATE_ID, EMAIL_MESSAGE_TEMPLATE_ID, PINNABLE, AUTOPIN)
values (103001, 'alfred debug', 10, 0, 0, 'alfred debugging info', 1, 2, 0, 0);

--changeset aea:1634
--comment: OSCT-383 grant SVC_COPILOT access to table for alfred
GRANT SELECT ON MSS.SERVICE_COMPONENT TO "SVC_COPILOT";

--changeset nop:1635
--comment: SRE-1046: Allow automation to write audit logs
GRANT INSERT ON MCAUDIT.RECORD TO "SVC_AUTOMATION_EXECUTOR";
INSERT INTO MCAUDIT.APPLICATION (ID, NAME, SHORT, DESCRIPTION ) VALUES ( 17, 'MC automation', 'mcautomation', 'MC Automation framework' );


--changeset mlo:1628
--comment:MC-28999: create new tables for passport contacts

create table STOP.PASSPORT_CONTACT
(
    ID         NUMBER(22) not null
        constraint PASSPORT_CONTACT_PK
            primary key,
    LASTNAME   VARCHAR2(50),
    FIRSTNAME  VARCHAR2(50),
    COMPANY_ID NUMBER(22),
    DIRECT     VARCHAR2(30),
    EMAIL      VARCHAR2(250),
    FAX        VARCHAR2(30),
    FUNCTION   VARCHAR2(100),
    HOME       VARCHAR2(30),
    MOBILE     VARCHAR2(30),
    OFFICE     VARCHAR2(30),
    CREATED    TIMESTAMP(6) WITH TIME ZONE default SYSTIMESTAMP,
    MODIFIED   TIMESTAMP(6) WITH TIME ZONE default SYSTIMESTAMP,
    COMMENTS   VARCHAR2(200)
);

create index STOP.IDX_PASSPORT_CONTACT_COMPANY
    on STOP.PASSPORT_CONTACT (COMPANY_ID);

ALTER TABLE STOP.PASSPORT_CONTACT
    add (
        CONSTRAINT FK_PASSPORT_CONTACT_COMPANY_ID foreign key (company_id) references STOP.COMPANY(ID) deferrable
        );

--to make sure this can have an incoming constraint from auth tables
grant references on stop.PASSPORT_CONTACT to auth;

-- We will define triggers later from AUTH that select things in passport contact so we need the grant
GRANT SELECT ON STOP.PASSPORT_CONTACT to AUTH;

--changeset mlo:1629
--comment:MC-28999: create new tables for passport logins

create table AUTH.PASSPORT_LOGIN
(
    ID                       NUMBER(11)                            not null
        constraint PASSPORT_LOGIN_PK
            primary key,
    LOGIN                    VARCHAR2(250)               default '',
    CONTACT_ID               NUMBER(22)                  default 0 not null,
    TOKEN_ID                 NUMBER(11),
    REPLACEMENTTOKEN_ID      NUMBER(11),
    EMAIL                    VARCHAR2(250),
    SMSAUTHNUMBER            VARCHAR2(32),
    TOKENREPLACEMENTSTATE_ID NUMBER(11)                  default 0 not null,
    HOMEAUTHHOST_ID          NUMBER(11),
    ENABLED                  NUMBER(1)                   default 0 not null,
    LOCKED                   NUMBER(1)                   default 0 not null,
    MAXRETRIES               NUMBER(2)                   default 0,
    LASTACCEPT               DATE,
    LASTREJECT               DATE,
    ANYTUNNELGROUP           NUMBER(1)                   default 0 not null,
    PASSWORDEXPIRY           DATE,
    COST_CENTER_ID           NUMBER(11),
    COMPANY_ID               NUMBER(11)                            not null,
    PASSWORDTYPE_ID          NUMBER(10)                  default 1 not null,
    TWOFACTORENABLED         NUMBER(1)                   default 0 not null,
    USER_UNIT_ID             NUMBER(10),
    MODIFIED                 TIMESTAMP(6) WITH TIME ZONE default SYSTIMESTAMP,
    LASTTOKENREQUESTDATE     TIMESTAMP(6) WITH TIME ZONE,
    AUTHTYPE_ID              NUMBER(11)                            not null,
    PWHASH                   VARCHAR2(64),
    SALT                     VARCHAR2(64),
    LASTPWCHANGE             TIMESTAMP(6) WITH TIME ZONE,
    TMPPWDONLYEXPIRY         TIMESTAMP(6) WITH TIME ZONE,
    CREATIONDATE             TIMESTAMP(6) WITH TIME ZONE,
    LOGINTYPE_ID             NUMBER(10),
    constraint U_CONST_PASSPORT_LOGIN_LOWER_LOGIN_HOMEAUTHHOST
        unique (LOGIN, HOMEAUTHHOST_ID)
);

ALTER TABLE AUTH.PASSPORT_LOGIN
    add (
        constraint FK_PASSPORT_LOGIN_STOP_PASSPORT_CONTACT_ID
            foreign key (CONTACT_ID) references STOP.PASSPORT_CONTACT(ID)
                deferrable,
        constraint FK_PASSPORT_LOGIN_TOKEN_ID
            foreign key (TOKEN_ID) references AUTH.TOKEN(ID)
                deferrable,
        constraint FK_PASSPORT_LOGIN_REPLACEMENTTOKEN_ID
            foreign key (REPLACEMENTTOKEN_ID) references AUTH.TOKEN(ID)
                deferrable,
        constraint FK_PASSPORT_LOGIN_TOKENREPLSTATE_ID
            foreign key (TOKENREPLACEMENTSTATE_ID) references AUTH.TOKENREPLACEMENTSTATE(ID)
                deferrable,
        constraint FK_PASSPORT_LOGIN_HOMEAUTHHOST_ID
            foreign key (HOMEAUTHHOST_ID) references AUTH.AUTHHOST(ID)
                deferrable,
        constraint FK_PASSPORT_LOGIN_COST_CENTER_ID
            foreign key (COST_CENTER_ID) references MSS.COST_CENTER(ID)
                deferrable,
        constraint FK_PASSPORT_LOGIN_COMPANY_ID
            foreign key (COMPANY_ID) references STOP.COMPANY(ID)
                deferrable,
        constraint FK_PASSPORT_LOGIN_PASSWORDTYPE_ID
            foreign key (PASSWORDTYPE_ID) references AUTH.PASSWORDTYPE(ID)
                deferrable,
        constraint FK_PASSPORT_LOGIN_USER_UNIT_ID
            foreign key (USER_UNIT_ID) references AUTH.USER_UNIT(ID)
                deferrable,
        constraint FK_PASSPORT_LOGIN_AUTHTYPE_ID
            foreign key (AUTHTYPE_ID) references AUTH.AUTHTYPE(ID)
                deferrable,
        constraint FK_PASSPORT_LOGIN_LOGINTYPE_ID
            foreign key (LOGINTYPE_ID) references AUTH.LOGINTYPE(ID)
                deferrable
        );

comment on column AUTH.PASSPORT_LOGIN.EMAIL is 'Email address used for authentication (as login name), if any.';

comment on column AUTH.PASSPORT_LOGIN.SMSAUTHNUMBER is 'Mobile phone number for use with SMS authentication, if any.';

comment on column AUTH.PASSPORT_LOGIN.TOKENREPLACEMENTSTATE_ID is 'for externally managed tokens; see table TOKENREPLACEMENTSTATE';

comment on column AUTH.PASSPORT_LOGIN.PASSWORDEXPIRY is '
if the password expiry date has passed, the user cannot login anymore via the auth server
the password must be changed first in mission control (logging in to mc is still possible)
';

comment on column AUTH.PASSPORT_LOGIN.LASTTOKENREQUESTDATE is '
The date when the last token replacement has been requested.
This might happen explicitly in case of externally managed tokens or implicitly in case a token is disabled
and therefore a new one is required.
Note: the date should not be reset once the token is replaced that''s why it is called *last* token request date.
';

comment on column AUTH.PASSPORT_LOGIN.AUTHTYPE_ID is 'The authentication type. Historically points to 1/token and was not used in the portal; it was resurrected for
                 SMS authentication.';

comment on column AUTH.PASSPORT_LOGIN.PWHASH is ' Hex representation of the SHA-256 hash of salt concatenated with password. The hash is calculated as sha256(salt + md5(password)).';

comment on column AUTH.PASSPORT_LOGIN.SALT is 'Hex representation of the salt. Generate the salt using a cryptographically secure pseudo-random number generator (CSPRNG).';

comment on column AUTH.PASSPORT_LOGIN.LASTPWCHANGE is 'The date on which the password has been changed.';

comment on column AUTH.PASSPORT_LOGIN.TMPPWDONLYEXPIRY is 'The date when the temporary password expires';

comment on column AUTH.PASSPORT_LOGIN.CREATIONDATE is 'The date when a user entry was created, i.e., the first AD sync or the time of user creation in the portal';

comment on column AUTH.PASSPORT_LOGIN.LOGINTYPE_ID is 'The type of the login';

create index AUTH.IDX_PASSPORT_LOGIN_COSTCENTER_ID
    on AUTH.PASSPORT_LOGIN (COST_CENTER_ID);

create index AUTH.PASSPORT_LOGIN_LOGIN_IDX_ASC
    on AUTH.PASSPORT_LOGIN (LOGIN, ID);

create unique index AUTH.U_PASSPORT_LOGIN_REPLACEMENTTOKEN_ID
    on AUTH.PASSPORT_LOGIN (REPLACEMENTTOKEN_ID);


create unique index AUTH.U_PASSPORT_LOGIN_TOKEN_ID
    on AUTH.PASSPORT_LOGIN (TOKEN_ID);

create unique index AUTH.U_PASSPORT_LOGIN_CONTACT_ID
    on AUTH.PASSPORT_LOGIN (CONTACT_ID);

create unique index AUTH.U_PASSPORT_LOGIN_EMAIL
    on AUTH.PASSPORT_LOGIN (LOWER("EMAIL"));

create index AUTH.IDX_PASSPORT_LOGIN_TYPE_ID
    on AUTH.PASSPORT_LOGIN (LOGINTYPE_ID);

create unique index AUTH.U_IDX_PASSPORT_LOGIN_LOWER_LOGIN_HOMEAUTHHOST
    on AUTH.PASSPORT_LOGIN (LOWER("LOGIN"), HOMEAUTHHOST_ID);

create unique index AUTH.U_PASSPORT_LOGIN_LOGIN_COMPANY_NOCASE
    on AUTH.PASSPORT_LOGIN (LOWER("LOGIN"), COMPANY_ID);

-- We will define triggers later from STOP that select things in passport login so we need the grant
GRANT SELECT ON AUTH.PASSPORT_LOGIN to STOP;

--changeset mlo:1630
--comment:MC-28999: create new tables for passport contact sync

create table STOP.PASSPORT_CONTACT_SYNC
(
    CONTACT_ID        NUMBER(22) not null
        constraint PASSPORTCONTACTSYNC_PK
            primary key
        constraint FK_PASSPORT_CONTACT_SYNC_CONTACT_ID
            references STOP.PASSPORT_CONTACT
                deferrable,
    SYNCDOMAIN_ID     NUMBER(10) not null
        constraint FK_PASSPORT_CONTACT_SYNC_SYNCDOMAIN_ID
            references AUTH.SYNCDOMAIN
                deferrable,
    DOMAIN            VARCHAR2(256),
    GUID              VARCHAR2(32),
    SID               VARCHAR2(56),
    SYNCTYPE_ID       NUMBER(10) not null
        constraint FK_PASSPORT_CONTACT_SYNC_SYNCTYPE_ID
            references AUTH.SYNCTYPE
                deferrable,
    USNCHANGED        NUMBER(20),
    DISTINGUISHEDNAME VARCHAR2(2048)
);

comment on column STOP.PASSPORT_CONTACT_SYNC.GUID is 'globally unique id';

comment on column STOP.PASSPORT_CONTACT_SYNC.SID is 'active directory "security ID"';

comment on column STOP.PASSPORT_CONTACT_SYNC.USNCHANGED is 'active directory "update sequence number"';

comment on column STOP.PASSPORT_CONTACT_SYNC.DISTINGUISHEDNAME is 'active directory "distinguishedName" or "dn"';

create index STOP.IDX_PASSPORT_CONTACT_SYNC_SYNCDOMAIN
    on STOP.PASSPORT_CONTACT_SYNC (SYNCDOMAIN_ID);

--changeset mlo:1631
--comment:MC-28999: create new tables for passport login 2 groups and login 2 tunnel groups

create table AUTH.PASSPORT_LOGIN2GROUPS
(
    LOGIN_ID NUMBER(11) not null
        constraint FK_PL2G_LOGIN_ID
            references AUTH.PASSPORT_LOGIN
                deferrable,
    GROUP_ID NUMBER(11) not null
        constraint FK_PL2G_GROUPS_ID
            references AUTH.GROUPS
                deferrable,
    constraint PASSPORTLOGIN2GROUPS_PK
        primary key (LOGIN_ID, GROUP_ID)
);

create table AUTH.PASSPORT_LOGIN2TUNNELGROUP
(
    LOGIN_ID       NUMBER(11) not null
        constraint FK_PL2T_LOGIN_ID
            references AUTH.PASSPORT_LOGIN
                deferrable,
    TUNNELGROUP_ID NUMBER(11) not null
        constraint FK_PL2T_TUNNELGROUP_ID
            references AUTH.TUNNELGROUP
                deferrable,
    constraint PASSPORTLOGIN2TUNNELGROUP_PK
        primary key (LOGIN_ID, TUNNELGROUP_ID)
);

create unique index AUTH.U_PL2T_LOGIN_ID
    on AUTH.PASSPORT_LOGIN2TUNNELGROUP (LOGIN_ID);

--changeset mlo:1632
--comment:MC-28999: create new tables grants for passport users

GRANT DELETE ON STOP.PASSPORT_CONTACT TO SVC_MC_PORTAL;
GRANT INSERT ON STOP.PASSPORT_CONTACT TO SVC_MC_PORTAL;
GRANT SELECT ON STOP.PASSPORT_CONTACT TO SVC_MC_PORTAL;
GRANT UPDATE ON STOP.PASSPORT_CONTACT TO SVC_MC_PORTAL;
GRANT DELETE ON STOP.PASSPORT_CONTACT_SYNC TO SVC_MC_PORTAL;
GRANT INSERT ON STOP.PASSPORT_CONTACT_SYNC TO SVC_MC_PORTAL;
GRANT SELECT ON STOP.PASSPORT_CONTACT_SYNC TO SVC_MC_PORTAL;
GRANT UPDATE ON STOP.PASSPORT_CONTACT_SYNC TO SVC_MC_PORTAL;
GRANT DELETE ON AUTH.PASSPORT_LOGIN2TUNNELGROUP TO SVC_MC_PORTAL;
GRANT INSERT ON AUTH.PASSPORT_LOGIN2TUNNELGROUP TO SVC_MC_PORTAL;
GRANT SELECT ON AUTH.PASSPORT_LOGIN2TUNNELGROUP TO SVC_MC_PORTAL;
GRANT UPDATE ON AUTH.PASSPORT_LOGIN2TUNNELGROUP TO SVC_MC_PORTAL;
GRANT DELETE ON AUTH.PASSPORT_LOGIN TO SVC_MC_PORTAL;
GRANT INSERT ON AUTH.PASSPORT_LOGIN TO SVC_MC_PORTAL;
GRANT SELECT ON AUTH.PASSPORT_LOGIN TO SVC_MC_PORTAL;
GRANT UPDATE ON AUTH.PASSPORT_LOGIN TO SVC_MC_PORTAL;
GRANT DELETE ON AUTH.PASSPORT_LOGIN2GROUPS TO SVC_MC_PORTAL;
GRANT INSERT ON AUTH.PASSPORT_LOGIN2GROUPS TO SVC_MC_PORTAL;
GRANT SELECT ON AUTH.PASSPORT_LOGIN2GROUPS TO SVC_MC_PORTAL;
GRANT UPDATE ON AUTH.PASSPORT_LOGIN2GROUPS TO SVC_MC_PORTAL;

GRANT DELETE ON STOP.PASSPORT_CONTACT TO AUTHSYNC;
GRANT INSERT ON STOP.PASSPORT_CONTACT TO AUTHSYNC;
GRANT SELECT ON STOP.PASSPORT_CONTACT TO AUTHSYNC;
GRANT UPDATE ON STOP.PASSPORT_CONTACT TO AUTHSYNC;
GRANT DELETE ON STOP.PASSPORT_CONTACT_SYNC TO AUTHSYNC;
GRANT INSERT ON STOP.PASSPORT_CONTACT_SYNC TO AUTHSYNC;
GRANT SELECT ON STOP.PASSPORT_CONTACT_SYNC TO AUTHSYNC;
GRANT UPDATE ON STOP.PASSPORT_CONTACT_SYNC TO AUTHSYNC;
GRANT DELETE ON AUTH.PASSPORT_LOGIN2TUNNELGROUP TO AUTHSYNC;
GRANT INSERT ON AUTH.PASSPORT_LOGIN2TUNNELGROUP TO AUTHSYNC;
GRANT SELECT ON AUTH.PASSPORT_LOGIN2TUNNELGROUP TO AUTHSYNC;
GRANT UPDATE ON AUTH.PASSPORT_LOGIN2TUNNELGROUP TO AUTHSYNC;
GRANT DELETE ON AUTH.PASSPORT_LOGIN TO AUTHSYNC;
GRANT INSERT ON AUTH.PASSPORT_LOGIN TO AUTHSYNC;
GRANT SELECT ON AUTH.PASSPORT_LOGIN TO AUTHSYNC;
GRANT UPDATE ON AUTH.PASSPORT_LOGIN TO AUTHSYNC;
GRANT DELETE ON AUTH.PASSPORT_LOGIN2GROUPS TO AUTHSYNC;
GRANT INSERT ON AUTH.PASSPORT_LOGIN2GROUPS TO AUTHSYNC;
GRANT SELECT ON AUTH.PASSPORT_LOGIN2GROUPS TO AUTHSYNC;
GRANT UPDATE ON AUTH.PASSPORT_LOGIN2GROUPS TO AUTHSYNC;

--changeset mlo:1634
--comment:MC-28999: jdo properties for newly created passport tables

INSERT INTO AUTH."#JDO_PROPERTIES" (KEY, VALUE) VALUES ('PASSPORT_LOGIN.naming.inverse.AUTH.FK_PL2G_LOGIN_ID', 'groups');
INSERT INTO AUTH."#JDO_PROPERTIES" (KEY, VALUE) VALUES ('PASSPORT_LOGIN.naming.inverse.AUTH.FK_PL2T_LOGIN_ID', 'tunnelGroups');
INSERT INTO AUTH."#JDO_PROPERTIES" (KEY, VALUE) VALUES ('TUNNELGROUP.naming.inverse.AUTH.FK_PL2T_TUNNELGROUP_ID', 'passportLogins');
INSERT INTO AUTH."#JDO_PROPERTIES" (KEY, VALUE) VALUES ('GROUPS.naming.inverse.AUTH.FK_PL2G_GROUPS_ID', 'passportLogins');

--changeset mlo:1635
--comment: FIX: add grants for heartbeat views to DECOM

GRANT SELECT ON OSIXINFO.V_HOSTCLUSTERSTATE TO DECOMM;
GRANT SELECT ON osixinfo.v_last_update TO DECOMM;

--changeset mlo:1636
--comment: FIX: allow null city id on deleted host

alter table MSS.DELETED_HOST modify CITY_ID null;

--changeset dnb:1636
--comment: MX-5752: Create a dbprop for migration to new auth tables
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (57041, 'migrate.auth.new_tables', 1, '0', '^[01]$', NULL, 'Enable use of new auth schema');

--changeset gta:1637
--comment: RTNG-494: remove migrate.frrouting.integrated_config dbprop
delete from MSS.VALUE where KEY_ID=56850;
delete from MSS.KEY where ID=56850;

--changeset nop:1638
--comment: SRE-1052: assign execute permission on event_interface to automation, remove when SRE-1054 is implemented
GRANT EXECUTE ON TT.UTIL TO SVC_AUTOMATION_EXECUTOR;

--changeset gic:1639
--comment: OSIX-6397: Add new DB Prop corosync.token.timeout
INSERT INTO MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
VALUES (57042, 'pacemaker.corosync.token.timeout', 2, '1200', '^[1-9][0-9]00$', 22, 'Corosync token timeout in ms');

--changeset ogl:1646 contextFilter:unit-tests
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM dba_users WHERE username='ASERTO_TEST'
CREATE USER "ASERTO_TEST" IDENTIFIED BY "xxxxxx" ACCOUNT LOCK
  DEFAULT TABLESPACE "USERS"
  TEMPORARY TABLESPACE "TEMP";

--changeset ogl:1647 contextFilter:unit-tests
--comment: system, object grants for ASERTO_TEST
GRANT "MSS_SCHEMA_USER" TO "ASERTO_TEST";
ALTER USER "ASERTO_TEST" DEFAULT ROLE "MSS_SCHEMA_USER";
GRANT EXEMPT ACCESS POLICY TO "ASERTO_TEST";
GRANT SELECT,INSERT,UPDATE,DELETE ON stop.COMPANY TO ASERTO_TEST;
GRANT SELECT,INSERT,UPDATE,DELETE ON stop.COMP_COMPTYPE_REF TO ASERTO_TEST;
GRANT SELECT,INSERT,UPDATE,DELETE ON stop.CONTACT TO ASERTO_TEST;
GRANT SELECT,INSERT,UPDATE,DELETE ON stop.CONTACT_LIST TO ASERTO_TEST;
GRANT SELECT,INSERT,UPDATE,DELETE ON stop.CONTACT_HANDLING TO ASERTO_TEST;
GRANT SELECT,INSERT,UPDATE,DELETE ON stop.COMPANY_UNIT TO ASERTO_TEST;
GRANT SELECT,INSERT,UPDATE,DELETE ON mss.SERVICE TO ASERTO_TEST;
GRANT SELECT,INSERT,UPDATE,DELETE ON mss.HOST TO ASERTO_TEST;
GRANT SELECT,INSERT,UPDATE,DELETE ON mss.HOST2SERVICE TO ASERTO_TEST;
GRANT EXECUTE ON auth.OSAG_AUTH TO ASERTO_TEST;
GRANT SELECT,INSERT,UPDATE,DELETE ON auth.login TO ASERTO_TEST;
GRANT SELECT,INSERT,UPDATE,DELETE ON auth.USER_SERVICE_SCOPE TO ASERTO_TEST;
GRANT SELECT,INSERT,UPDATE,DELETE ON auth.USER_COMPANY_UNIT_SCOPE TO ASERTO_TEST;
GRANT SELECT,INSERT,UPDATE,DELETE ON auth.USER_COMPANY_SCOPE TO ASERTO_TEST;
GRANT SELECT,INSERT,UPDATE,DELETE ON auth.USER_PERMISSION TO ASERTO_TEST;
GRANT SELECT,INSERT,UPDATE,DELETE ON auth.profile TO ASERTO_TEST;
GRANT SELECT,INSERT,UPDATE,DELETE ON auth.login2profile TO ASERTO_TEST;
GRANT SELECT ON MCDB_MONITOR.PLOG_OUTPUT TO ASERTO_TEST;

--changeset mlo:1646
--comment: MC-28981: adapt JDO generated names

INSERT INTO AUTH."#JDO_PROPERTIES" (KEY, VALUE) VALUES ('PASSPORT_LOGIN.naming.TOKENREPLACEMENTSTATE_ID', 'tokenReplacementState');
INSERT INTO AUTH."#JDO_PROPERTIES" (KEY, VALUE) VALUES ('PASSPORT_LOGIN.naming.TWOFACTORENABLED', 'twofactorEnabled');
INSERT INTO AUTH."#JDO_PROPERTIES" (KEY, VALUE) VALUES ('PASSPORT_LOGIN.naming.PWHASH', 'pwHash');
INSERT INTO AUTH."#JDO_PROPERTIES" (KEY, VALUE) VALUES ('PASSPORT_LOGIN.naming.AUTHTYPE_ID', 'authType');
INSERT INTO AUTH."#JDO_PROPERTIES" (KEY, VALUE) VALUES ('PASSPORT_LOGIN.naming.SMSAUTHNUMBER', 'smsAuthNumber');
INSERT INTO AUTH."#JDO_PROPERTIES" (KEY, VALUE) VALUES ('PASSPORT_LOGIN.naming.REPLACEMENTTOKEN_ID', 'replacementToken');
INSERT INTO AUTH."#JDO_PROPERTIES" (KEY, VALUE) VALUES ('PASSPORT_LOGIN.naming.MAXRETRIES', 'maxRetries');
INSERT INTO AUTH."#JDO_PROPERTIES" (KEY, VALUE) VALUES ('PASSPORT_LOGIN.naming.LASTACCEPT', 'lastAccept');
INSERT INTO AUTH."#JDO_PROPERTIES" (KEY, VALUE) VALUES ('PASSPORT_LOGIN.naming.LOGINTYPE_ID', 'loginType');
INSERT INTO AUTH."#JDO_PROPERTIES" (KEY, VALUE) VALUES ('PASSPORT_LOGIN.naming.LASTREJECT', 'lastReject');
INSERT INTO AUTH."#JDO_PROPERTIES" (KEY, VALUE) VALUES ('PASSPORT_LOGIN.naming.LASTPWCHANGE', 'lastPwChange');
INSERT INTO AUTH."#JDO_PROPERTIES" (KEY, VALUE) VALUES ('PASSPORT_LOGIN.naming.ANYTUNNELGROUP', 'anyTunnelGroup');
INSERT INTO AUTH."#JDO_PROPERTIES" (KEY, VALUE) VALUES ('PASSPORT_LOGIN.naming.PASSWORDEXPIRY', 'passwordExpiry');
INSERT INTO AUTH."#JDO_PROPERTIES" (KEY, VALUE) VALUES ('PASSPORT_LOGIN.naming.PASSWORDTYPE_ID', 'passwordType');
INSERT INTO AUTH."#JDO_PROPERTIES" (KEY, VALUE) VALUES ('PASSPORT_LOGIN.naming.HOMEAUTHHOST_ID', 'homeAuthHost');
INSERT INTO AUTH."#JDO_PROPERTIES" (KEY, VALUE) VALUES ('PASSPORT_LOGIN.naming.MANAGING_LOGIN_ID', 'managingLogin');
INSERT INTO AUTH."#JDO_PROPERTIES" (KEY, VALUE) VALUES ('PASSPORT_LOGIN.naming.LASTTOKENREQUESTDATE', 'lastTokenRequestDate');
INSERT INTO STOP."#JDO_PROPERTIES" (KEY, VALUE) VALUES ('PASSPORT_CONTACT.naming.FIRSTNAME', 'firstName');
INSERT INTO STOP."#JDO_PROPERTIES" (KEY, VALUE) VALUES ('PASSPORT_CONTACT.naming.LASTNAME', 'lastName');
INSERT INTO STOP."#JDO_PROPERTIES" (KEY, VALUE) VALUES ('PASSPORT_CONTACT.naming.inverse.STOP.FK_PASSPORT_CONTACT_SYNC_CONTACT_ID', 'contactSync');
INSERT INTO STOP."#JDO_PROPERTIES" (KEY, VALUE) VALUES ('PASSPORT_CONTACT_SYNC.naming.SYNCDOMAIN_ID', 'syncDomain');
INSERT INTO STOP."#JDO_PROPERTIES" (KEY, VALUE) VALUES ('PASSPORT_CONTACT_SYNC.naming.SYNCTYPE_ID', 'syncType');
INSERT INTO STOP."#JDO_PROPERTIES" (KEY, VALUE) VALUES ('PASSPORT_CONTACT_SYNC.naming.USNCHANGED', 'usnChanged');

--changeset ogl:1648 contextFilter:unit-tests
--comment: DB-2701: more Aserto test coverage
grant select on auth.seq_profile to aserto_test;
grant select on auth.seq_user_permission to aserto_test;
grant select on auth.SEQ_USER_COMPANY_UNIT_SCOPE to aserto_test;
grant select on auth.SEQ_USER_SERVICE_SCOPE to aserto_test;

--changeset aea:1649
--comment: OSCT-379 grant SVC_COPILOT access to table for alfred
GRANT SELECT ON MSS.HOST2SERVICE TO "SVC_COPILOT";
GRANT SELECT ON MSS.SERVICE TO "SVC_COPILOT";
GRANT SELECT ON MSS.V_HOST_KEY_VALUE TO "SVC_COPILOT";

--changeset rse:1650
--comment: Allow SVC_BALUOSIXINFO to DELETE records
GRANT DELETE ON "OSIXINFO"."OSIXINFO" TO "SVC_BALUOSIXINFO";
GRANT DELETE ON "GUMA2"."OSIX_INFO" TO "SVC_BALUOSIXINFO";

--changeset gip:1651
--comment: MX-5751: grant permissions for new passport tables
GRANT SELECT,REFERENCES on stop.PASSPORT_CONTACT_SYNC to AUTH;
GRANT SELECT,INSERT,UPDATE,DELETE on stop.PASSPORT_CONTACT to AUTH;
GRANT SELECT,INSERT,UPDATE,DELETE on stop.PASSPORT_CONTACT_SYNC to AUTH;

--changeset mlo:1652
--comment: FIX: grant permissions on new passport tables to MCA
GRANT DELETE ON AUTH.PASSPORT_LOGIN TO MCA;
GRANT INSERT ON AUTH.PASSPORT_LOGIN TO MCA;
GRANT SELECT ON AUTH.PASSPORT_LOGIN TO MCA;
GRANT UPDATE ON AUTH.PASSPORT_LOGIN TO MCA;
GRANT DELETE ON AUTH.PASSPORT_LOGIN2GROUPS TO MCA;
GRANT INSERT ON AUTH.PASSPORT_LOGIN2GROUPS TO MCA;
GRANT SELECT ON AUTH.PASSPORT_LOGIN2GROUPS TO MCA;
GRANT UPDATE ON AUTH.PASSPORT_LOGIN2GROUPS TO MCA;
GRANT DELETE ON AUTH.PASSPORT_LOGIN2TUNNELGROUP TO MCA;
GRANT INSERT ON AUTH.PASSPORT_LOGIN2TUNNELGROUP TO MCA;
GRANT SELECT ON AUTH.PASSPORT_LOGIN2TUNNELGROUP TO MCA;
GRANT UPDATE ON AUTH.PASSPORT_LOGIN2TUNNELGROUP TO MCA;
GRANT DELETE ON STOP.PASSPORT_CONTACT TO MCA;
GRANT INSERT ON STOP.PASSPORT_CONTACT TO MCA;
GRANT SELECT ON STOP.PASSPORT_CONTACT TO MCA;
GRANT UPDATE ON STOP.PASSPORT_CONTACT TO MCA;
GRANT DELETE ON STOP.PASSPORT_CONTACT_SYNC TO MCA;
GRANT INSERT ON STOP.PASSPORT_CONTACT_SYNC TO MCA;
GRANT SELECT ON STOP.PASSPORT_CONTACT_SYNC TO MCA;
GRANT UPDATE ON STOP.PASSPORT_CONTACT_SYNC TO MCA;


--changeset mlo:1647
--comment: MC-28983: set JDO generated name and sequences for creation

INSERT INTO STOP."#JDO_PROPERTIES" (KEY, VALUE) VALUES ('PASSPORT_CONTACT.naming.inverse.AUTH.FK_PASSPORT_LOGIN_STOP_PASSPORT_CONTACT_ID', 'login');
INSERT INTO STOP."#JDO_PROPERTIES" (KEY, VALUE) VALUES ('PASSPORT_CONTACT.seq.for.pk.ID', 'CONTACT_SEQ');
INSERT INTO AUTH."#JDO_PROPERTIES" (KEY, VALUE) VALUES ('PASSPORT_LOGIN.seq.for.pk.ID', 'SEQ_LOGIN_ID');

INSERT INTO AUTH."#JDO_PROPERTIES" (KEY, VALUE) VALUES ('TOKEN.naming.inverse.AUTH.FK_PASSPORT_LOGIN_TOKEN_ID', 'passportLogin');
INSERT INTO AUTH."#JDO_PROPERTIES" (KEY, VALUE) VALUES ('TOKEN.naming.inverse.AUTH.FK_PASSPORT_LOGIN_REPLACEMENTTOKEN_ID', 'passportLoginAsRepl');

--changeset phm:1648
--comment: ORE-5991: New Currencies in ISP Links
INSERT INTO MSS.CURRENCY (ID,SHORT) VALUES (55, 'SAR');
INSERT INTO MSS.CURRENCY (ID,SHORT) VALUES (56, 'JOD');
INSERT INTO MSS.CURRENCY (ID,SHORT) VALUES (57, 'GHS');
INSERT INTO MSS.CURRENCY (ID,SHORT) VALUES (58, 'KZT');

--changeset mxd:1649
--comment: OSAP-1291: create new audit record types to support zitadel configuration changes in mc-config-api
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID)
VALUES (390, 'Identity Provider ZTNA tenant updated', 'zitadel_ztna_tenant_update', 'Identity Provider ZTNA tenant updated', 1);

--changeset ogl:1653 endDelimiter:/
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:0 select count(*) from SYS.DBA_OBJECTS where OWNER='AUTH' and OBJECT_NAME='OSAG_AUTH_PASSPORT' and OBJECT_TYPE='PACKAGE'
--comment: MX-5755: grant execute permission for new passport package
create package auth.osag_auth_passport is
end osag_auth_passport;
/

--changeset dnb:1654
--comment: MX-5755: grant execute permission for new passport package
GRANT EXECUTE ON auth.OSAG_AUTH_PASSPORT TO AUTHSYNC;

--changeset ogl:1655
--comment: GUMA removal
delete from MCDB_MONITOR.LAST_CONSISTENCY_CHECK_RESULTS where check_id='SEL_heartbeats_linux';
delete from MCDB_CHECKS.CONSISTENCY_CHECKS where check_key='SEL_heartbeats_linux';

--changeset ogl:1656
--comment: DB-2725 guma removal
grant select on osixinfo.V_FIRMWARE to mss;
grant select on osixinfo.OSIXINFO to mss;

--changeset rse:1657
--comment: TRIVIAL: Remove EOL dbprop mgmtserver.kubernetes and mgmtserver.kubernetes.role
DELETE FROM MSS.VALUE WHERE key_id = 22060;
DELETE FROM MSS.KEY WHERE id = 22060 AND name = 'mgmtserver.kubernetes';
DELETE FROM MSS.VALUE WHERE key_id = 22061;
DELETE FROM MSS.KEY WHERE id = 22061 AND name = 'mgmtserver.kubernetes.role';

--changeset rse:1658
--comment: TRIVIAL: Remove EOL GUMA dbprops
DELETE FROM MSS.VALUE WHERE key_id = 4135;
DELETE FROM MSS.KEY WHERE id = 4135 AND name = 'transport';
DELETE FROM MSS.VALUE WHERE key_id = 8361;
DELETE FROM MSS.KEY WHERE id = 8361 AND name = 'guma.client.message.queue.size';
DELETE FROM MSS.VALUE WHERE key_id = 8362;
DELETE FROM MSS.KEY WHERE id = 8362 AND name = 'guma.client.message.rate.limit';
DELETE FROM MSS.VALUE WHERE key_id = 21465;
DELETE FROM MSS.KEY WHERE id = 21465 AND name = 'mgmtserver.guma';

--changeset rha:1659
--comment: MEP-1720: remove dbprop migrate.sslvpn.global_overrides
DELETE FROM MSS.VALUE WHERE key_id = 24518;
DELETE FROM MSS.KEY WHERE name = 'migrate.sslvpn.global_overrides' AND id = 24518;

--changeset mlo:1657
--comment: MC-29163: create passport_temp_access_key

create table AUTH.PASSPORT_TEMP_ACCESS_KEY
(
    ID                  NUMBER(10) not null
        constraint PASSPORT_TEMPACCESSKEY_PK
            primary key,
    LOGIN_ID            NUMBER(10) not null
        constraint FK_PASSPORT_TEMP_ACCESS_KEY_PASSPORT_LOGIN_ID
            references AUTH.PASSPORT_LOGIN
                deferrable,
    KEY                 VARCHAR2(32),
    VALID_UNTIL         TIMESTAMP(6) WITH TIME ZONE,
    TEMP_ACCESS_TYPE_ID NUMBER(10) not null
        constraint FK_PASSPORT_TEMP_ACCESS_TYPE_ID
            references AUTH.TEMP_ACCESS_TYPE
                deferrable,
    OTP                 VARCHAR2(255),
    OTP_VALID_UNTIL     TIMESTAMP(6) WITH TIME ZONE,
    TOKEN_ID            NUMBER(11)
        constraint PASSPORT_TEMP_ACCESS_KEY_UQ1
            unique
        constraint FK_PASSPORT_TEMP_ACCESS_KEY_TOKEN_ID
            references AUTH.TOKEN
                deferrable
);

create unique index AUTH.IDX_PASSPORT_TEMP_ACCESS_KEY
    on AUTH.PASSPORT_TEMP_ACCESS_KEY (KEY);

create index AUTH.IDX_PASSPORT_TEMP_ACCESS_KEY_LOGIN
    on AUTH.PASSPORT_TEMP_ACCESS_KEY (LOGIN_ID);

INSERT INTO AUTH."#JDO_PROPERTIES" (KEY, VALUE) VALUES ('PASSPORT_TEMP_ACCESS_KEY.seq.for.pk.ID', 'TEMP_ACCESS_KEY_SEQ');
INSERT INTO AUTH."#JDO_PROPERTIES" (KEY, VALUE) VALUES ('TOKEN.naming.inverse.AUTH.FK_PASSPORT_TEMP_ACCESS_KEY_TOKEN_ID', 'passportTempAccessKey');


GRANT DELETE ON AUTH.PASSPORT_TEMP_ACCESS_KEY TO SVC_MC_PORTAL;
GRANT INSERT ON AUTH.PASSPORT_TEMP_ACCESS_KEY TO SVC_MC_PORTAL;
GRANT SELECT ON AUTH.PASSPORT_TEMP_ACCESS_KEY TO SVC_MC_PORTAL;
GRANT UPDATE ON AUTH.PASSPORT_TEMP_ACCESS_KEY TO SVC_MC_PORTAL;


--changeset mlo:1658
--comment: FIX: grant permissions on new passport tables to MCA

GRANT DELETE ON AUTH.PASSPORT_TEMP_ACCESS_KEY TO MCA;
GRANT INSERT ON AUTH.PASSPORT_TEMP_ACCESS_KEY TO MCA;
GRANT SELECT ON AUTH.PASSPORT_TEMP_ACCESS_KEY TO MCA;
GRANT UPDATE ON AUTH.PASSPORT_TEMP_ACCESS_KEY TO MCA;


--changeset tte:1659
--comment: FIX: grant permissions on new passport tables to WEBRLS
GRANT DELETE ON AUTH.PASSPORT_LOGIN TO WEBRLS;
GRANT INSERT ON AUTH.PASSPORT_LOGIN TO WEBRLS;
GRANT SELECT ON AUTH.PASSPORT_LOGIN TO WEBRLS;
GRANT UPDATE ON AUTH.PASSPORT_LOGIN TO WEBRLS;
GRANT DELETE ON AUTH.PASSPORT_LOGIN2GROUPS TO WEBRLS;
GRANT INSERT ON AUTH.PASSPORT_LOGIN2GROUPS TO WEBRLS;
GRANT SELECT ON AUTH.PASSPORT_LOGIN2GROUPS TO WEBRLS;
GRANT UPDATE ON AUTH.PASSPORT_LOGIN2GROUPS TO WEBRLS;
GRANT DELETE ON AUTH.PASSPORT_LOGIN2TUNNELGROUP TO WEBRLS;
GRANT INSERT ON AUTH.PASSPORT_LOGIN2TUNNELGROUP TO WEBRLS;
GRANT SELECT ON AUTH.PASSPORT_LOGIN2TUNNELGROUP TO WEBRLS;
GRANT UPDATE ON AUTH.PASSPORT_LOGIN2TUNNELGROUP TO WEBRLS;
GRANT DELETE ON STOP.PASSPORT_CONTACT TO WEBRLS;
GRANT INSERT ON STOP.PASSPORT_CONTACT TO WEBRLS;
GRANT SELECT ON STOP.PASSPORT_CONTACT TO WEBRLS;
GRANT UPDATE ON STOP.PASSPORT_CONTACT TO WEBRLS;
GRANT DELETE ON STOP.PASSPORT_CONTACT_SYNC TO WEBRLS;
GRANT INSERT ON STOP.PASSPORT_CONTACT_SYNC TO WEBRLS;
GRANT SELECT ON STOP.PASSPORT_CONTACT_SYNC TO WEBRLS;
GRANT UPDATE ON STOP.PASSPORT_CONTACT_SYNC TO WEBRLS;
GRANT DELETE ON AUTH.PASSPORT_TEMP_ACCESS_KEY TO WEBRLS;
GRANT INSERT ON AUTH.PASSPORT_TEMP_ACCESS_KEY TO WEBRLS;
GRANT SELECT ON AUTH.PASSPORT_TEMP_ACCESS_KEY TO WEBRLS;
GRANT UPDATE ON AUTH.PASSPORT_TEMP_ACCESS_KEY TO WEBRLS;

--changeset mlo:1660
--comment: FIX: add RLS predicates for new tables accessible by WEBRLS

INSERT INTO RLSDEF.PREDICATE (ID, SCHEMA_NAME, TABLE_NAME, ROLE_ID, PREDICATE, EXTENDED_PREDICATE, PRIORITY, READ_WRITE,
                              AREA_ID)
VALUES (RLSDEF.PREDICATE_SEQ.nextval, 'STOP', 'PASSPORT_CONTACT', 6, null, null, 1, 1, 1);
INSERT INTO RLSDEF.PREDICATE (ID, SCHEMA_NAME, TABLE_NAME, ROLE_ID, PREDICATE, EXTENDED_PREDICATE, PRIORITY, READ_WRITE,
                              AREA_ID)
VALUES (RLSDEF.PREDICATE_SEQ.nextval, 'STOP', 'PASSPORT_CONTACT', 6, null, null, 1, 1, 2);
INSERT INTO RLSDEF.PREDICATE (ID, SCHEMA_NAME, TABLE_NAME, ROLE_ID, PREDICATE, EXTENDED_PREDICATE, PRIORITY, READ_WRITE,
                              AREA_ID)
VALUES (RLSDEF.PREDICATE_SEQ.nextval, 'STOP', 'PASSPORT_CONTACT', 1,
        'company_id = sys_context(''web'', ''current_company_id'')',
        'company_id = 6 OR company_id = sys_context(''web'', ''current_company_id'') OR EXISTS (SELECT company_id FROM stop.comp_comptype_ref ccr WHERE stop.contact.company_id = ccr.company_id AND ccr.comptype_id IN (3))',
        2, 1, 1);
INSERT INTO RLSDEF.PREDICATE (ID, SCHEMA_NAME, TABLE_NAME, ROLE_ID, PREDICATE, EXTENDED_PREDICATE, PRIORITY, READ_WRITE,
                              AREA_ID)
VALUES (RLSDEF.PREDICATE_SEQ.nextval, 'STOP', 'PASSPORT_CONTACT', 12,
        'company_id = sys_context(''web'', ''current_company_id'')',
        'company_id = 6 OR company_id = sys_context(''web'', ''current_company_id'')', 2, 1, 2);
INSERT INTO RLSDEF.PREDICATE (ID, SCHEMA_NAME, TABLE_NAME, ROLE_ID, PREDICATE, EXTENDED_PREDICATE, PRIORITY, READ_WRITE,
                              AREA_ID)
VALUES (RLSDEF.PREDICATE_SEQ.nextval, 'STOP', 'PASSPORT_CONTACT', 12,
        'id = sys_context(''web'', ''current_contact_id'')',
        'company_id = 6 OR company_id = sys_context(''web'', ''current_company_id'')', 3, 1, 1);
INSERT INTO RLSDEF.PREDICATE (ID, SCHEMA_NAME, TABLE_NAME, ROLE_ID, PREDICATE, EXTENDED_PREDICATE, PRIORITY, READ_WRITE,
                              AREA_ID)
VALUES (RLSDEF.PREDICATE_SEQ.nextval, 'STOP', 'PASSPORT_CONTACT', 3,
        'EXISTS (SELECT l.id FROM auth.passport_login l WHERE l.contact_id = stop.passport_contact.id)', '1=2', 3, 1,
        2);
INSERT INTO RLSDEF.PREDICATE (ID, SCHEMA_NAME, TABLE_NAME, ROLE_ID, PREDICATE, EXTENDED_PREDICATE, PRIORITY, READ_WRITE,
                              AREA_ID)
VALUES (RLSDEF.PREDICATE_SEQ.nextval, 'STOP', 'PASSPORT_CONTACT', 3,
        'EXISTS (SELECT l.id FROM auth.passport_login l WHERE l.contact_id = stop.passport_contact.id)', '1=2', 4, 1,
        1);
INSERT INTO RLSDEF.PREDICATE (ID, SCHEMA_NAME, TABLE_NAME, ROLE_ID, PREDICATE, EXTENDED_PREDICATE, PRIORITY, READ_WRITE,
                              AREA_ID)
VALUES (RLSDEF.PREDICATE_SEQ.nextval, 'STOP', 'PASSPORT_CONTACT', 3,
        'EXISTS (SELECT l.id FROM auth.passport_login l WHERE l.contact_id = stop.passport_contact.id)', '1=2', 1, 2,
        1);
INSERT INTO RLSDEF.PREDICATE (ID, SCHEMA_NAME, TABLE_NAME, ROLE_ID, PREDICATE, EXTENDED_PREDICATE, PRIORITY, READ_WRITE,
                              AREA_ID)
VALUES (RLSDEF.PREDICATE_SEQ.nextval, 'STOP', 'PASSPORT_CONTACT', 5, null, null, 1, 2, 2);
INSERT INTO RLSDEF.PREDICATE (ID, SCHEMA_NAME, TABLE_NAME, ROLE_ID, PREDICATE, EXTENDED_PREDICATE, PRIORITY, READ_WRITE,
                              AREA_ID)
VALUES (RLSDEF.PREDICATE_SEQ.nextval, 'STOP', 'PASSPORT_CONTACT', 11,
        'company_id = sys_context(''web'', ''current_company_id'')',
        'company_id = sys_context(''web'', ''current_company_id'')', 2, 2, 2);
INSERT INTO RLSDEF.PREDICATE (ID, SCHEMA_NAME, TABLE_NAME, ROLE_ID, PREDICATE, EXTENDED_PREDICATE, PRIORITY, READ_WRITE,
                              AREA_ID)
VALUES (RLSDEF.PREDICATE_SEQ.nextval, 'STOP', 'PASSPORT_CONTACT', 3,
        'EXISTS (SELECT l.id FROM auth.passport_login l WHERE l.contact_id = stop.passport_contact.id)', '1=2', 3, 2,
        2);



INSERT INTO RLSDEF.PREDICATE (ID, SCHEMA_NAME, TABLE_NAME, ROLE_ID, PREDICATE, EXTENDED_PREDICATE, PRIORITY, READ_WRITE,
                              AREA_ID)
VALUES (RLSDEF.PREDICATE_SEQ.nextval, 'AUTH', 'PASSPORT_LOGIN', 6, null, null, 1, 1, 2);
INSERT INTO RLSDEF.PREDICATE (ID, SCHEMA_NAME, TABLE_NAME, ROLE_ID, PREDICATE, EXTENDED_PREDICATE, PRIORITY, READ_WRITE,
                              AREA_ID)
VALUES (RLSDEF.PREDICATE_SEQ.nextval, 'AUTH', 'PASSPORT_LOGIN', 6, null, null, 1, 1, 1);
INSERT INTO RLSDEF.PREDICATE (ID, SCHEMA_NAME, TABLE_NAME, ROLE_ID, PREDICATE, EXTENDED_PREDICATE, PRIORITY, READ_WRITE,
                              AREA_ID)
VALUES (RLSDEF.PREDICATE_SEQ.nextval, 'AUTH', 'PASSPORT_LOGIN', 1, '1=2',
        'company_id = sys_context(''web'', ''current_company_id'')', 2, 1, 1);
INSERT INTO RLSDEF.PREDICATE (ID, SCHEMA_NAME, TABLE_NAME, ROLE_ID, PREDICATE, EXTENDED_PREDICATE, PRIORITY, READ_WRITE,
                              AREA_ID)
VALUES (RLSDEF.PREDICATE_SEQ.nextval, 'AUTH', 'PASSPORT_LOGIN', 11, '1=2',
        'company_id = sys_context(''web'', ''current_company_id'')', 3, 1, 1);
INSERT INTO RLSDEF.PREDICATE (ID, SCHEMA_NAME, TABLE_NAME, ROLE_ID, PREDICATE, EXTENDED_PREDICATE, PRIORITY, READ_WRITE,
                              AREA_ID)
VALUES (RLSDEF.PREDICATE_SEQ.nextval, 'AUTH', 'PASSPORT_LOGIN', 5, null, null, 1, 2, 2);



INSERT INTO RLSDEF.PREDICATE (ID, SCHEMA_NAME, TABLE_NAME, ROLE_ID, PREDICATE, EXTENDED_PREDICATE, PRIORITY, READ_WRITE,
                              AREA_ID)
VALUES (RLSDEF.PREDICATE_SEQ.nextval, 'STOP', 'PASSPORT_CONTACT_SYNC', 6, null, null, 1, 1, 2);
INSERT INTO RLSDEF.PREDICATE (ID, SCHEMA_NAME, TABLE_NAME, ROLE_ID, PREDICATE, EXTENDED_PREDICATE, PRIORITY, READ_WRITE,
                              AREA_ID)
VALUES (RLSDEF.PREDICATE_SEQ.nextval, 'STOP', 'PASSPORT_CONTACT_SYNC', 12,
        'EXISTS (SELECT c.id FROM stop.passport_contact c WHERE c.id = stop.passport_contact_sync.contact_id)', '1=2',
        2, 1, 2);
INSERT INTO RLSDEF.PREDICATE (ID, SCHEMA_NAME, TABLE_NAME, ROLE_ID, PREDICATE, EXTENDED_PREDICATE, PRIORITY, READ_WRITE,
                              AREA_ID)
VALUES (RLSDEF.PREDICATE_SEQ.nextval, 'STOP', 'PASSPORT_CONTACT_SYNC', 3,
        'EXISTS (SELECT l.id FROM auth.passport_login l WHERE l.contact_id = stop.passport_contact_sync.contact_id)',
        '1=2', 3, 1, 2);
INSERT INTO RLSDEF.PREDICATE (ID, SCHEMA_NAME, TABLE_NAME, ROLE_ID, PREDICATE, EXTENDED_PREDICATE, PRIORITY, READ_WRITE,
                              AREA_ID)
VALUES (RLSDEF.PREDICATE_SEQ.nextval, 'STOP', 'PASSPORT_CONTACT_SYNC', 5, null, null, 1, 2, 2);
INSERT INTO RLSDEF.PREDICATE (ID, SCHEMA_NAME, TABLE_NAME, ROLE_ID, PREDICATE, EXTENDED_PREDICATE, PRIORITY, READ_WRITE,
                              AREA_ID)
VALUES (RLSDEF.PREDICATE_SEQ.nextval, 'STOP', 'PASSPORT_CONTACT_SYNC', 11,
        'EXISTS (SELECT c.id FROM stop.passport_contact c WHERE c.id = stop.passport_contact_sync.contact_id)', '1=2',
        2, 2, 2);



INSERT INTO RLSDEF.PREDICATE (ID, SCHEMA_NAME, TABLE_NAME, ROLE_ID, PREDICATE, EXTENDED_PREDICATE, PRIORITY, READ_WRITE,
                              AREA_ID)
VALUES (RLSDEF.PREDICATE_SEQ.nextval, 'AUTH', 'PASSPORT_LOGIN2GROUPS', 6, null, null, 1, 1, 2);
INSERT INTO RLSDEF.PREDICATE (ID, SCHEMA_NAME, TABLE_NAME, ROLE_ID, PREDICATE, EXTENDED_PREDICATE, PRIORITY, READ_WRITE,
                              AREA_ID)
VALUES (RLSDEF.PREDICATE_SEQ.nextval, 'AUTH', 'PASSPORT_LOGIN2GROUPS', 12,
        'EXISTS (SELECT g.id FROM auth.groups g WHERE auth.passport_login2groups.group_id = g.id)', '1=2', 2, 1, 2);
INSERT INTO RLSDEF.PREDICATE (ID, SCHEMA_NAME, TABLE_NAME, ROLE_ID, PREDICATE, EXTENDED_PREDICATE, PRIORITY, READ_WRITE,
                              AREA_ID)
VALUES (RLSDEF.PREDICATE_SEQ.nextval, 'AUTH', 'PASSPORT_LOGIN2GROUPS', 5, null, null, 1, 2, 2);



INSERT INTO RLSDEF.PREDICATE (ID, SCHEMA_NAME, TABLE_NAME, ROLE_ID, PREDICATE, EXTENDED_PREDICATE, PRIORITY, READ_WRITE,
                              AREA_ID)
VALUES (RLSDEF.PREDICATE_SEQ.nextval, 'AUTH', 'PASSPORT_LOGIN2TUNNELGROUP', 6, null, null, 1, 1, 1);
INSERT INTO RLSDEF.PREDICATE (ID, SCHEMA_NAME, TABLE_NAME, ROLE_ID, PREDICATE, EXTENDED_PREDICATE, PRIORITY, READ_WRITE,
                              AREA_ID)
VALUES (RLSDEF.PREDICATE_SEQ.nextval, 'AUTH', 'PASSPORT_LOGIN2TUNNELGROUP', 6, null, null, 1, 1, 2);
INSERT INTO RLSDEF.PREDICATE (ID, SCHEMA_NAME, TABLE_NAME, ROLE_ID, PREDICATE, EXTENDED_PREDICATE, PRIORITY, READ_WRITE,
                              AREA_ID)
VALUES (RLSDEF.PREDICATE_SEQ.nextval, 'AUTH', 'PASSPORT_LOGIN2TUNNELGROUP', 1,
        'EXISTS (SELECT t.id FROM auth.tunnelgroup t WHERE t.id = auth.passport_login2tunnelgroup.tunnelgroup_id)',
        '1=2', 2, 1, 1);
INSERT INTO RLSDEF.PREDICATE (ID, SCHEMA_NAME, TABLE_NAME, ROLE_ID, PREDICATE, EXTENDED_PREDICATE, PRIORITY, READ_WRITE,
                              AREA_ID)
VALUES (RLSDEF.PREDICATE_SEQ.nextval, 'AUTH', 'PASSPORT_LOGIN2TUNNELGROUP', 12,
        'EXISTS (SELECT t.id FROM auth.tunnelgroup t WHERE t.id = auth.passport_login2tunnelgroup.tunnelgroup_id)',
        '1=2', 2, 1, 2);
INSERT INTO RLSDEF.PREDICATE (ID, SCHEMA_NAME, TABLE_NAME, ROLE_ID, PREDICATE, EXTENDED_PREDICATE, PRIORITY, READ_WRITE,
                              AREA_ID)
VALUES (RLSDEF.PREDICATE_SEQ.nextval, 'AUTH', 'PASSPORT_LOGIN2TUNNELGROUP', 5, null, null, 1, 2, 2);

INSERT INTO RLSDEF.PREDICATE (ID, SCHEMA_NAME, TABLE_NAME, ROLE_ID, PREDICATE, EXTENDED_PREDICATE, PRIORITY, READ_WRITE,
                              AREA_ID)
VALUES (RLSDEF.PREDICATE_SEQ.nextval, 'AUTH', 'PASSPORT_TEMP_ACCESS_KEY', 6, null, '1=2', 1, 1, 2);
INSERT INTO RLSDEF.PREDICATE (ID, SCHEMA_NAME, TABLE_NAME, ROLE_ID, PREDICATE, EXTENDED_PREDICATE, PRIORITY, READ_WRITE,
                              AREA_ID)
VALUES (RLSDEF.PREDICATE_SEQ.nextval, 'AUTH', 'PASSPORT_TEMP_ACCESS_KEY', 5, null, '1=2', 1, 2, 2);

--changeset ako:1661
--comment: NC-339: Add new DB Prop migrate.2025.dhcp-relay
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (57050, 'migrate.2025.dhcp-relay', 1, '0', '^[01]$', NULL, 'Migrate to the new DHCP relay agent (2025)');

--changeset ogl:1662
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:1 SELECT COUNT(*) FROM dba_triggers WHERE owner='STOP' and TRIGGER_NAME='T_COMPANY_ASERTO'
--comment: DB-2701: move trigger to other table
drop trigger STOP.t_company_aserto;

--changeset gip:1663
--comment: MX-5705: Delete mail goqueue migration dbprop
DELETE FROM MSS.VALUE WHERE key_id IN (SELECT id FROM MSS.KEY WHERE name='migrate.mail.goqueue');
DELETE FROM MSS.KEY WHERE name='migrate.mail.goqueue';

--changeset mlo:1664
--comment: TRIVIAL: drop unused DX users

DROP USER SDWAN_ANALYTICS;
DROP USER SVC_OIDC_MIGRATION;

--changeset ogl:1665
--comment: ORE-6666
update mss.KEY set STRING_DEFAULT='23:00-06:00' where name='relmgmt.off_hours';

--changeset ogl:1666
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:1 SELECT COUNT(*) FROM dba_triggers WHERE owner='STOP' and TRIGGER_NAME='T_SERVICE_ASERTO'
--comment: DB-2701: move trigger to MSS schema
drop trigger STOP.t_service_aserto;

--changeset ogl:1667
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:1 SELECT COUNT(*) FROM dba_triggers WHERE owner='STOP' and TRIGGER_NAME='T_HOST2SERVICE_ASERTO'
--comment: DB-2701: move trigger to MSS schema
drop trigger STOP.t_host2service_aserto;

--changeset ogl:1668
--comment: ORE-6710: cascade delete to deployments
grant delete on MSS.CONFIG_DEPLOYMENT to SVC_CONIFER;

--changeset aea:1669
--comment: OSCT-412: add event type alfred comment
insert into TT.EVENT_TYPE (ID, NAME, SOURCE, IS_NOTIFIED, ESCALATION, DESCRIPTION, SMS_MESSAGE_TEMPLATE_ID, EMAIL_MESSAGE_TEMPLATE_ID, PINNABLE, AUTOPIN)
values (10601, 'alfred comment', 8, 0, 0, 'comment from alfred', 1, 2, 0, 0);

--changeset ogl:1670
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:1 SELECT COUNT(*) FROM dba_triggers WHERE owner='AUTH' and TRIGGER_NAME='T_LOGIN_SET_DEFAULT_UNIT'
--comment: DB-2750: merge triggers of same type
drop trigger auth.t_login_set_default_unit;

--changeset mlo:1671
--comment: MC-29167: disable jdo generation for guma classes
INSERT INTO GUMA2."#JDO_PROPERTIES" ("KEY","VALUE") VALUES ('HEARTBEAT.naming','none');
INSERT INTO GUMA2."#JDO_PROPERTIES" ("KEY","VALUE") VALUES ('SUPPRESSED_SIGNATURE.naming','none');
INSERT INTO GUMA2."#JDO_PROPERTIES" ("KEY","VALUE") VALUES ('SYSLOG_MESSAGE.naming','none');
INSERT INTO GUMA2."#JDO_PROPERTIES" ("KEY","VALUE") VALUES ('SYSLOG_MESSAGE_TYPE.naming','none');
INSERT INTO GUMA2."#JDO_PROPERTIES" ("KEY","VALUE") VALUES ('SYSLOG_FACILITY.naming','none');
INSERT INTO GUMA2."#JDO_PROPERTIES" ("KEY","VALUE") VALUES ('SIGNATURE.naming','none');
INSERT INTO GUMA2."#JDO_PROPERTIES" ("KEY","VALUE") VALUES ('PATTERN.naming','none');

-- changeset jhu:1672
-- comment: ZTNA-1521: Introduce new column for cert autorenewal
ALTER TABLE SVC_ZEROTRUST.ZTNA_TENANT ADD CERT_AUTORENEWAL NUMBER(1,0) DEFAULT 0 NOT NULL;
COMMENT ON COLUMN SVC_ZEROTRUST.ZTNA_TENANT.CERT_AUTORENEWAL IS 'ZTNA-1521: Introduce new column for cert autorenewal';

--changeset ogl:1673
--comment: DB-2725: remove guma2.heartbeat
drop table guma2.heartbeat;

--changeset del:1674
--comment: OSCI-642: Add new DB Prop pacemaker.http-health and pacemaker.http-health.allowed-client-networks
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (57051, 'pacemaker.http-health', 1, 0, '^[01]$', 22, 'Enable HTTP health endpoints reporting the Master host in a pacemaker cluster.');

insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (57052, 'pacemaker.http-health.allowed-client-networks', 4, NULL, '^(?:25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])(?:\.(?:25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])){3}($|\/\b([0-9]|[12][0-9]|3[0-2])\b)(?:\s(?:25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])(?:\.(?:25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])){3})($|\/\b([0-9]|[12][0-9]|3[0-2])\b)?$', 22, 'Client networks that are allowed to call the health endpoint in CIDR notation in a space separated list');


--changeset ogl:1675
--comment: container fixup
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM dba_users where USERNAME='SVC_VPN_CONNECTIONS'
CREATE USER "SVC_VPN_CONNECTIONS" IDENTIFIED BY "xxxxxx" ACCOUNT LOCK
  DEFAULT TABLESPACE "USERS"
  TEMPORARY TABLESPACE "TEMP";

GRANT "MSS_LOGIN_USER" TO "SVC_VPN_CONNECTIONS";

ALTER USER "SVC_VPN_CONNECTIONS" DEFAULT ROLE "MSS_LOGIN_USER";

GRANT EXEMPT ACCESS POLICY TO "SVC_VPN_CONNECTIONS";

GRANT SELECT on STOP.COMPANY to SVC_VPN_CONNECTIONS;
GRANT SELECT on MSS.HOST to SVC_VPN_CONNECTIONS;
GRANT SELECT on MSS.HOST2SERVICE to SVC_VPN_CONNECTIONS;
GRANT SELECT on MSS.SERVICE to SVC_VPN_CONNECTIONS;
GRANT SELECT on MSS.INTERFACE to SVC_VPN_CONNECTIONS;
GRANT SELECT on VPN.TUNNEL to SVC_VPN_CONNECTIONS;
GRANT SELECT on VPN.PARTITION to SVC_VPN_CONNECTIONS;
GRANT SELECT on VPN.VPN to SVC_VPN_CONNECTIONS;
GRANT SELECT on VPN.VPN_MEMBER to SVC_VPN_CONNECTIONS;

--changeset fla:1676
--comment: MC-28991: Add missing grants to SVC_VPN_CONNECTIONS user for retrieving additional tunnel information
GRANT SELECT on MSS.SERVICE_TYPE to SVC_VPN_CONNECTIONS;
GRANT SELECT on MSS.ISP_LINK to SVC_VPN_CONNECTIONS;
GRANT SELECT on MSS.INTERFACE2ISP_LINK to SVC_VPN_CONNECTIONS;

--changeset mlo:1675
--comment: MC-29323: create passport recent password table

create table AUTH.PASSPORT_RECENTPASSWORD
(
    ID       NUMBER(11) not null
        constraint PASSPORT_RECENTPASSWORD_PK
            primary key,
    LOGIN_ID NUMBER(11) not null
        constraint FK_PASSPORT_RECENTPASSWORD_LOGIN_ID
            references AUTH.PASSPORT_LOGIN
                deferrable,
    PASSWORD VARCHAR2(64),
    VERSION  NUMBER(11) not null,
    SALT     VARCHAR2(64)
);

comment on column AUTH.PASSPORT_RECENTPASSWORD.SALT is 'Hex representation of the salt. If a salt is set the password (hash) has been generated using this salt.';

create index AUTH.IDX_PASSPORT_RECENTPASSWORD_LOGIN_ID
    on AUTH.PASSPORT_RECENTPASSWORD (LOGIN_ID);

GRANT SELECT,INSERT,UPDATE,DELETE ON AUTH.PASSPORT_RECENTPASSWORD TO MCA;
GRANT SELECT,INSERT,UPDATE,DELETE ON AUTH.PASSPORT_RECENTPASSWORD TO WEBRLS;
GRANT SELECT,INSERT,UPDATE,DELETE ON AUTH.PASSPORT_RECENTPASSWORD TO SVC_MC_PORTAL;
GRANT SELECT,INSERT,UPDATE,DELETE ON AUTH.PASSPORT_RECENTPASSWORD TO AUTHSYNC;

INSERT INTO AUTH."#JDO_PROPERTIES" (KEY, VALUE) VALUES ('PASSPORT_RECENTPASSWORD.naming', 'PassportRecentPassword');
INSERT INTO AUTH."#JDO_PROPERTIES" (KEY, VALUE) VALUES ('PASSPORT_RECENTPASSWORD.seq.for.pk.ID', 'SEQ_RECENTPASSWORD_ID');
INSERT INTO AUTH."#JDO_PROPERTIES" (KEY, VALUE) VALUES ('PASSPORT_LOGIN.naming.inverse.AUTH.FK_PASSPORT_RECENTPASSWORD_LOGIN_ID', 'recentPasswords');

--changeset mlo:1676
--comment: MC-29323: create passport alias table

create table AUTH.PASSPORT_ALIAS
(
    ID       NUMBER(11) not null
        constraint PASSPORT_ALIAS_PK
            primary key,
    LOGIN_ID NUMBER(11) not null
        constraint FK_PASSPORT_ALIAS_LOGIN_ID
            references AUTH.PASSPORT_LOGIN
                deferrable,
    ALIAS    VARCHAR2(50)
);

create index AUTH.IDX_PASSPORT_ALIAS_LOGIN_ID
    on AUTH.PASSPORT_ALIAS (LOGIN_ID);

GRANT SELECT,INSERT,UPDATE,DELETE ON AUTH.PASSPORT_ALIAS TO MCA;
GRANT SELECT,INSERT,UPDATE,DELETE ON AUTH.PASSPORT_ALIAS TO WEBRLS;
GRANT SELECT,INSERT,UPDATE,DELETE ON AUTH.PASSPORT_ALIAS TO SVC_MC_PORTAL;
GRANT SELECT,INSERT,UPDATE,DELETE ON AUTH.PASSPORT_ALIAS TO AUTHSYNC;

INSERT INTO AUTH."#JDO_PROPERTIES" (KEY, VALUE) VALUES ('PASSPORT_ALIAS.seq.for.pk.ID', 'SEQ_ALIAS_ID');
INSERT INTO AUTH."#JDO_PROPERTIES" (KEY, VALUE) VALUES ('PASSPORT_LOGIN.naming.inverse.AUTH.FK_PASSPORT_ALIAS_LOGIN_ID', 'aliases');


INSERT INTO RLSDEF.PREDICATE (ID, SCHEMA_NAME, TABLE_NAME, ROLE_ID, PREDICATE, EXTENDED_PREDICATE, PRIORITY, READ_WRITE, AREA_ID) VALUES (RLSDEF.PREDICATE_SEQ.nextval, 'AUTH', 'PASSPORT_ALIAS', 5, null, null, 1, 2, 2);
INSERT INTO RLSDEF.PREDICATE (ID, SCHEMA_NAME, TABLE_NAME, ROLE_ID, PREDICATE, EXTENDED_PREDICATE, PRIORITY, READ_WRITE, AREA_ID) VALUES (RLSDEF.PREDICATE_SEQ.nextval, 'AUTH', 'PASSPORT_ALIAS', 6, null, null, 1, 1, 2);
INSERT INTO RLSDEF.PREDICATE (ID, SCHEMA_NAME, TABLE_NAME, ROLE_ID, PREDICATE, EXTENDED_PREDICATE, PRIORITY, READ_WRITE, AREA_ID) VALUES (RLSDEF.PREDICATE_SEQ.nextval, 'AUTH', 'PASSPORT_ALIAS', 11, 'EXISTS (SELECT l.id FROM auth.passport_login l WHERE l.id = auth.passport_alias.login_id)', '1=2', 2, 2, 2);
INSERT INTO RLSDEF.PREDICATE (ID, SCHEMA_NAME, TABLE_NAME, ROLE_ID, PREDICATE, EXTENDED_PREDICATE, PRIORITY, READ_WRITE, AREA_ID) VALUES (RLSDEF.PREDICATE_SEQ.nextval, 'AUTH', 'PASSPORT_ALIAS', 12, 'EXISTS (SELECT l.id FROM auth.passport_login l WHERE l.id = auth.passport_alias.login_id)', '1=2', 2, 1, 2);

--changeset baj:1677
--comment: IDS-3075: Add new DB Prop migrate.2025.alertd
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (57053, 'migrate.2025.alertd', 1, '0', '^[01]$', NULL, 'Replace snort-alertd with alertd');

--changeset dnb:1678
--comment: AUT-1257: fix permissions for temp access key table
GRANT SELECT,INSERT,UPDATE,DELETE ON AUTH.PASSPORT_TEMP_ACCESS_KEY TO AUTHSYNC;


--changeset mlo:1678
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:1 SELECT COUNT(*) FROM dba_triggers WHERE owner='AUTH' and TRIGGER_NAME='T_ALIAS_PASSPORT_ALIAS_REPLICATION'
--comment: MC-29362: remove passport replication triggers
drop trigger auth.T_ALIAS_PASSPORT_ALIAS_REPLICATION;

--changeset mlo:1679
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:1 SELECT COUNT(*) FROM dba_triggers WHERE owner='AUTH' and TRIGGER_NAME='T_RECENTPASSWORD_PASSPORT_RECENTPASSWORD_REPLICATION'
--comment: MC-29362: remove passport replication triggers
drop trigger auth.T_RECENTPASSWORD_PASSPORT_RECENTPASSWORD_REPLICATION;

--changeset mlo:1680
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:1 SELECT COUNT(*) FROM dba_triggers WHERE owner='AUTH' and TRIGGER_NAME='T_LOGIN_PASSPORT_LOGIN_REPLICATION'
--comment: MC-29362: remove passport replication triggers
drop trigger auth.T_LOGIN_PASSPORT_LOGIN_REPLICATION;

--changeset mlo:1681
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:1 SELECT COUNT(*) FROM dba_triggers WHERE owner='AUTH' and TRIGGER_NAME='T_LOGIN2GROUPS_PASSPORT_LOGIN2GROUPS_REPLICATION'
--comment: MC-29362: remove passport replication triggers
drop trigger auth.T_LOGIN2GROUPS_PASSPORT_LOGIN2GROUPS_REPLICATION;

--changeset mlo:1682
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:1 SELECT COUNT(*) FROM dba_triggers WHERE owner='AUTH' and TRIGGER_NAME='T_LOGIN2TUNNELGROUP_PASSPORT_LOGIN2TUNNELGROUP_REPLICATION'
--comment: MC-29362: remove passport replication triggers
drop trigger auth.T_LOGIN2TUNNELGROUP_PASSPORT_LOGIN2TUNNELGROUP_REPLICATION;

--changeset mlo:1685
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:1 SELECT COUNT(*) FROM dba_triggers WHERE owner='STOP' and TRIGGER_NAME='T_CONTACT_SYNC_PASSPORT_CONTACT_SYNC_REPLICATION'
--comment: MC-29362: remove passport replication triggers
drop trigger stop.T_CONTACT_SYNC_PASSPORT_CONTACT_SYNC_REPLICATION;

--changeset mlo:1686
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:1 SELECT COUNT(*) FROM dba_triggers WHERE owner='STOP' and TRIGGER_NAME='T_CONTACT_PASSPORT_CONTACT_REPLICATION'
--comment: MC-29362: remove passport replication triggers
drop trigger stop.T_CONTACT_PASSPORT_CONTACT_REPLICATION;

--changeset lut:1687
--comment: RTNG-122: Add local auth ID as configuration parameter for Partner Connect
ALTER TABLE VPN.PARTNER_PHASE1 ADD LOCAL_AUTH_ID VARCHAR2(100) NULL;
COMMENT ON COLUMN VPN.PARTNER_PHASE1.LOCAL_AUTH_ID IS 'IKE identity to use for authentication round of local end of the tunnel. Can be an IP address, a fully-qualified domain name, an email address or a Distinguished Name.';

--changeset isa:1688
--comment: RTNG-770: Add new dbprop migrate.frr.bgpd.conf.v2
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (57054, 'migrate.frr.bgpd.conf.v2', 1, '0', '^[01]$', NULL, 'Version 2 of an improved method for generating bgpd.conf in CBLX (FRRouting)');

--changeset mlo:1688
--comment: TRIVIAL: increase contact function size
alter table STOP.CONTACT modify FUNCTION VARCHAR2(250);
alter table STOP.PASSPORT_CONTACT modify FUNCTION VARCHAR2(250);

--changeset mlo:1689
--comment: MC-29173: create OpenSystems Identity User Management Permissions

-- new scope type for open systems identity user management
INSERT INTO AUTH.USER_ROLE_SCOPE_TYPE (ID, NAME, DESCRIPTION)
VALUES (4, 'open-systems-identity-user-mgmt-scope', 'Roles which have Open Systems Identity user management scope.');
-- we start at 5xxx to separate from the rest
INSERT INTO AUTH.USER_ROLE (ID, NAME, IS_INTERNAL, USER_ROLE_SCOPE_TYPE_ID, DESCRIPTION)
VALUES (5002, 'mc-cust-open-systems-identity-users-admin', 0, 4, 'Open Systems Identity User Management Administrator');
INSERT INTO AUTH.USER_ROLE (ID, NAME, IS_INTERNAL, USER_ROLE_SCOPE_TYPE_ID, DESCRIPTION)
VALUES (5003, 'mc-cust-open-systems-identity-users-auditor', 0, 4, 'Open Systems Identity User Management Auditor');
INSERT INTO AUTH.USER_ROLE (ID, NAME, IS_INTERNAL, USER_ROLE_SCOPE_TYPE_ID, DESCRIPTION)
VALUES (5005, 'mc-cust-open-systems-identity-users-monitor', 0, 4, 'Open Systems Identity User Management Monitor');

-- auditor requires monitor
INSERT INTO AUTH.USER_ROLE2REQUIRED_ROLE (USER_ROLE_ID, REQUIRED_USER_ROLE_ID)
VALUES (5002, 5005);
-- admin requires monitor
INSERT INTO AUTH.USER_ROLE2REQUIRED_ROLE (USER_ROLE_ID, REQUIRED_USER_ROLE_ID)
VALUES (5003, 5005);
-- monitor requires basic portal access
INSERT INTO AUTH.USER_ROLE2REQUIRED_ROLE (USER_ROLE_ID, REQUIRED_USER_ROLE_ID)
VALUES (5005, 1000);

--changeset mlo:1690 endDelimiter:/
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:0 select count(*) from SYS.DBA_OBJECTS where OWNER='AUTH' and OBJECT_NAME='OSAG_AUTH_WEBRLS_PASSPORT' and OBJECT_TYPE='PACKAGE'
--comment: MC-29401: grant passport PLSQL to portal users
create package auth.OSAG_AUTH_WEBRLS_PASSPORT is
end OSAG_AUTH_WEBRLS_PASSPORT;
/

--changeset mlo:1691
--comment: MC-29401: grant passport PLSQL to portal users
GRANT EXECUTE ON AUTH.OSAG_AUTH_PASSPORT TO SVC_MC_PORTAL;
GRANT EXECUTE ON AUTH.OSAG_AUTH_WEBRLS_PASSPORT TO WEBRLS;

--changeset mlo:1692
--comment: MC-29176: create audit trail component for Open Systems Identity User Editor
INSERT INTO MCAUDIT.COMPONENT (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID)
VALUES (81, 'Open Systems Identity User Editor', 'open_systems_identity_user_editor', 'Open Systems Identity User Editor', 2);

--changeset gta:1693
--comment: RTNG-837: lift restriction on backbone.gre.network subnet size
UPDATE mss.key k
SET k.regexp='^(([0-9]|[1-9]\d|1\d\d|2[0-4]\d|25[0-5]).){3}([0-9]|[1-9]\d|1\d\d|2[0-4]\d|25[0-5])\/([0-9]|1[0-9]|2[0-9]|3[0-2])$'
WHERE k.name='backbone.gre.network';

--changeset pas:1694
--comment: IDS-3106: Change default value of dbprop ndr.zeek.logs.forwarding to 0
update MSS.key k
set k.STRING_DEFAULT='0'
WHERE k.ID = 57032 AND k.NAME='ndr.zeek.logs.forwarding';

--changeset doi:1695
--comment: PRX-8902
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID)
VALUES (391, 'CASB Rule created', 'casb_rule_add', 'A new rule has been added to a casb policy', 2);

INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID)
VALUES (392, 'CASB Rule updated', 'casb_rule_modify', 'A rule of a casb policy has been adapted', 2);

INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID)
VALUES (393, 'CASB Rule deleted', 'casb_rule_delete', 'A rule of a casb policy has been deleted', 2);

--changeset rse:1696
--comment: TRIVIAL: Add new dbprop balu.gateway.scrape
INSERT INTO MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
VALUES (57060, 'balu.gateway.scrape', 1, '0', '^[01]$', NULL, 'Enable prometheus scraping of the Balu Gateway');

--changeset rse:1697
--comment: TRIVIAL: Add new dbprop ntpd.listen.ratelimit
INSERT INTO MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
VALUES (57061, 'ntpd.listen.ratelimit', 1, '1', '^[01]$', NULL, 'Enable rate limiting of abusive NTP clients querying the local NTP server excessively');

--changeset ogl:1698
--comment: improve query perf
create index MC.IDX_ISP_LINK_HISTORY_DATE2
    on MC.ISP_LINK_HISTORY (ISP_LINK_ID, CHANGE_DATE);

drop index mc.IDX_ISP_LINK_HISTORY_ID;

--changeset ssk:1699
--comment: CLOUD-481: grant perms needed for firewall changes to svc_conifer
GRANT SELECT,INSERT,UPDATE,DELETE ON FW.POLICY TO svc_conifer;
GRANT SELECT,INSERT,UPDATE,DELETE ON FW.NAT_SECTION TO svc_conifer;
GRANT SELECT,INSERT,UPDATE,DELETE ON FW.SOURCE_NAT_RULE TO svc_conifer;
GRANT SELECT,INSERT,UPDATE,DELETE ON FW.DESTINATION_NAT_RULE TO svc_conifer;
GRANT SELECT,INSERT,UPDATE,DELETE ON FW.CHE_DNAT_SRC_ZONE TO svc_conifer;
GRANT SELECT,INSERT,UPDATE,DELETE ON FW.CHE_SNAT_DST_ZONE TO svc_conifer;
GRANT SELECT,INSERT,UPDATE,DELETE ON FW.CHE_SNAT_SRC_ZONE TO svc_conifer;
GRANT SELECT,INSERT,UPDATE,DELETE ON FW.SOURCE_NAT_RULE2TICKET TO svc_conifer;
GRANT SELECT,INSERT,UPDATE,DELETE ON FW.DESTINATION_NAT_RULE2TICKET TO svc_conifer;
GRANT SELECT,INSERT,UPDATE ON FW.RULE2TICKET TO svc_conifer;
GRANT INSERT,UPDATE,DELETE ON FW.ZONE TO svc_conifer;
GRANT UPDATE,DELETE ON FW.ZONE_MEMBER TO svc_conifer;
GRANT SELECT ON FW.NAT_ACTION TO svc_conifer;
GRANT SELECT ON FW.NAT_SECTION_TYPE TO svc_conifer;
GRANT SELECT ON MSS.CVPN_POOL TO svc_conifer;
GRANT SELECT ON MSS.CVPN_SERVICE TO svc_conifer;
GRANT SELECT ON FW.ZONE_SEQ TO svc_conifer;

--changeset phh:1700
--comment: FW-6565: dbprop for firewall backend
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (57062, 'fw.backend', 4, 'iptables', '^(iptables|nftables)$', 22, 'Configuration backend for the firewall policy');

--changeset isa:1701
--comment: RTNG-867: add new dbprop migrate.frr.upgrade.v10
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (57063, 'migrate.frr.upgrade.v10', 1, '0', '^[01]$', NULL, 'Major version upgrade of FRRouting suite (v10)');

--changeset mlo:1701
--comment: MC-29400: increase news entry title to 100 characters

alter table MSS.NEWS_ENTRY modify TITLE VARCHAR2(100);

--changeset alg:1702
--cleanup after rse:1223, remove references to dropped table
DELETE FROM MSS."#JDO_PROPERTIES" WHERE "KEY" IN ('CONFIG_DEPLOYMENT_STATUS.cacheable');

--changeset niv:1703
--comment: add new dbprop balu.gateway.hcv_cert
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (57064, 'balu.gateway.hcv_cert', 1, '0', '^[01]$', NULL, 'Enables writing of new balu certs based on Hashicorp Vault PKI');

--changeset fla:1704
--comment: MC-29360: Drop SVC_VPN_CONNECTIONS user since it is no longer used in the portal
DROP USER SVC_VPN_CONNECTIONS;

--changeset gul:1705
--comment: NC-15: Add new DB Prop dhcpd.loghost
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (57065, 'dhcpd.loghost', 4, NULL, '^((\d|[1-9]\d|1\d\d|2[0-4]\d|25[0-5])\.(\d|[1-9]\d|1\d\d|2[0-4]\d|25[0-5])\.(\d|[1-9]\d|1\d\d|2[0-4]\d|25[0-5])\.(\d|[1-9]\d|1\d\d|2[0-4]\d|25[0-5])(\/(((tcp)\/(\d){1,5})|((udp)\/(\d){1,5}))){0,1})( (\d|[1-9]\d|1\d\d|2[0-4]\d|25[0-5])\.(\d|[1-9]\d|1\d\d|2[0-4]\d|25[0-5])\.(\d|[1-9]\d|1\d\d|2[0-4]\d|25[0-5])\.(\d|[1-9]\d|1\d\d|2[0-4]\d|25[0-5])(\/(((tcp)\/(\d){1,5})|((udp)\/(\d){1,5}))){0,1})*$', 22, 'IP address where to send the dhcpd logs using syslog as transport');

--changeset ssk:1706
--comment: CLOUD-568: add new component and record types for fw changes
UPDATE MCAUDIT.COMPONENT SET NAME='Firewall', SHORT='firewall', DESCRIPTION='Firewall configuration' WHERE ID=79;

INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID) VALUES (394, 'Forward section created', 'forward_section_created', 'A new forward section was created', 1);
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID) VALUES (395, 'Forward section modified', 'forward_section_modified', 'A forward section was modified', 1);
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID) VALUES (396, 'Forward section deleted', 'forward_section_deleted', 'A forward section was deleted', 1);

INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID) VALUES (397, 'Forward rule created', 'forward_rule_created', 'A new forward rule was created', 1);
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID) VALUES (398, 'Forward rule modified', 'forward_rule_modified', 'A forward rule was modified', 1);
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID) VALUES (399, 'Forward rule deleted', 'forward_rule_deleted', 'A forward rule was deleted', 1);

INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID) VALUES (400, 'NAT section created', 'nat_section_created', 'A new NAT section was created', 1);
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID) VALUES (401, 'NAT section modified', 'nat_section_modified', 'A NAT section was modified', 1);
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID) VALUES (402, 'NAT section deleted', 'nat_section_deleted', 'A NAT section was deleted', 1);

INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID) VALUES (403, 'SNAT rule created', 'snat_rule_created', 'A new SNAT rule was created', 1);
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID) VALUES (404, 'SNAT rule modified', 'snat_rule_modified', 'A SNAT rule was modified', 1);
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID) VALUES (405, 'SNAT rule deleted', 'snat_rule_deleted', 'A SNAT rule was deleted', 1);

INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID) VALUES (406, 'DNAT rule created', 'dnat_rule_created', 'A new DNAT rule was created', 1);
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID) VALUES (407, 'DNAT rule modified', 'dnat_rule_modified', 'A DNAT rule was modified', 1);
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID) VALUES (408, 'DNAT rule deleted', 'dnat_rule_deleted', 'A DNAT rule was deleted', 1);

INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID) VALUES (409, 'IPv4 address created', 'addr4_created', 'A new IPv4 address was created', 1);
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID) VALUES (410, 'IPv4 address modified', 'addr4_modified', 'An IPv4 address was modified', 1);
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID) VALUES (411, 'IPv4 address deleted', 'addr4_deleted', 'An IPv4 address was deleted', 1);

INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID) VALUES (412, 'IPv6 address created', 'addr6_created', 'A new IPv6 address was created', 1);
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID) VALUES (413, 'IPv6 address modified', 'addr6_modified', 'An IPv6 address was modified', 1);
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID) VALUES (414, 'IPv6 address deleted', 'addr6_deleted', 'An IPv6 address was deleted', 1);

INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID) VALUES (415, 'IPv4 network created', 'net4_created', 'A new IPv4 network was created', 1);
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID) VALUES (416, 'IPv4 network modified', 'net4_modified', 'An IPv4 network was modified', 1);
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID) VALUES (417, 'IPv4 network deleted', 'net4_deleted', 'An IPv4 network was deleted', 1);

INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID) VALUES (418, 'IPv6 network created', 'net6_created', 'A new IPv6 network was created', 1);
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID) VALUES (419, 'IPv6 network modified', 'net6_modified', 'An IPv6 network was modified', 1);
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID) VALUES (420, 'IPv6 network deleted', 'net6_deleted', 'An IPv6 network was deleted', 1);

INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID) VALUES (421, 'DNS object created', 'dns_object_created', 'A new DNS object was created', 1);
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID) VALUES (422, 'DNS object modified', 'dns_object_modified', 'A DNS object was modified', 1);
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID) VALUES (423, 'DNS object deleted', 'dns_object_deleted', 'A DNS object was deleted', 1);

INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID) VALUES (424, 'IP service created', 'ip_service_created', 'A new IP service was created', 1);
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID) VALUES (425, 'IP service modified', 'ip_service_modified', 'An IP service was modified', 1);
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID) VALUES (426, 'IP service deleted', 'ip_service_deleted', 'An IP service was deleted', 1);

INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID) VALUES (427, 'IP group created', 'ip_group_created', 'A new IP group was created', 1);
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID) VALUES (428, 'IP group modified', 'ip_group_modified', 'An IP group was modified', 1);
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID) VALUES (429, 'IP group deleted', 'ip_group_deleted', 'An IP group was deleted', 1);

INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID) VALUES (430, 'IP service group created', 'ip_service_group_created', 'A new IP service group was created', 1);
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID) VALUES (431, 'IP service group modified', 'ip_service_group_modified', 'An IP service group was modified', 1);
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID) VALUES (432, 'IP service group deleted', 'ip_service_group_deleted', 'An IP service group was deleted', 1);

INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID) VALUES (433, 'App group created', 'app_group_created', 'A new app group was created', 1);
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID) VALUES (434, 'App group modified', 'app_group_modified', 'An app group was modified', 1);
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID) VALUES (435, 'App group deleted', 'app_group_deleted', 'An app group was deleted', 1);

INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID) VALUES (436, 'Scoped IP group created', 'scoped_ip_group_created', 'A new scoped IP group was created', 1);
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID) VALUES (437, 'Scoped IP group modified', 'scoped_ip_group_modified', 'A scoped IP group was modified', 1);
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID) VALUES (438, 'Scoped IP group deleted', 'scoped_ip_group_deleted', 'A scoped IP group was deleted', 1);

INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID) VALUES (439, 'IP group member added', 'ip_group_member_added', 'An IP group member was added', 1);
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID) VALUES (440, 'IP group member removed', 'ip_group_member_removed', 'An IP group member was removed', 1);
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID) VALUES (441, 'App group member added', 'app_group_member_added', 'An app group member was added', 1);
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID) VALUES (442, 'App group member removed', 'app_group_member_removed', 'An app group member was removed', 1);
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID) VALUES (443, 'Service group member added', 'service_group_member_added', 'A service group member was added', 1);
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID) VALUES (444, 'Service group member removed', 'service_group_member_removed', 'A service group member was removed', 1);
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID) VALUES (445, 'Scoped IP group member added', 'scoped_ip_group_member_added', 'A scoped IP group member was added', 1);
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID) VALUES (446, 'Scoped IP group member removed', 'scoped_ip_group_member_removed', 'A scoped IP group member was removed', 1);

INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID) VALUES (447, 'Forward rule source member added', 'forward_rule_src_member_added', 'A source member was added', 1);
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID) VALUES (448, 'Forward rule source member removed', 'forward_rule_src_member_removed', 'A source member was removed', 1);
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID) VALUES (449, 'Forward rule destination member added', 'forward_rule_dst_member_added', 'A destination member was added', 1);
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID) VALUES (450, 'Forward rule destination member removed', 'forward_rule_dst_member_removed', 'A destination member was removed', 1);
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID) VALUES (451, 'Forward rule service member added', 'forward_rule_srv_member_added', 'A service member was added', 1);
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID) VALUES (452, 'Forward rule service member removed', 'forward_rule_srv_member_removed', 'A service member was removed', 1);
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID) VALUES (453, 'Forward rule app member added', 'forward_rule_app_member_added', 'An app member was added', 1);
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID) VALUES (454, 'Forward rule app member removed', 'forward_rule_app_member_removed', 'An app member was removed', 1);

--changeset mlo:1706
--comment: MC-29656: grant select on user activation config to svc_mc_portal
GRANT SELECT ON AUTH.USER_ACTIVATION_CONFIG TO SVC_MC_PORTAL;

--changeset mlo:1707
--comment: MC-29503: grant permissions for passport tables for activation email job
GRANT DELETE ON AUTH.PASSPORT_TEMP_ACCESS_KEY TO STOKENSYNC;
GRANT INSERT ON AUTH.PASSPORT_TEMP_ACCESS_KEY TO STOKENSYNC;
GRANT SELECT ON AUTH.PASSPORT_TEMP_ACCESS_KEY TO STOKENSYNC;
GRANT UPDATE ON AUTH.PASSPORT_TEMP_ACCESS_KEY TO STOKENSYNC;
GRANT DELETE ON AUTH.PASSPORT_LOGIN TO STOKENSYNC;
GRANT INSERT ON AUTH.PASSPORT_LOGIN TO STOKENSYNC;
GRANT SELECT ON AUTH.PASSPORT_LOGIN TO STOKENSYNC;
GRANT UPDATE ON AUTH.PASSPORT_LOGIN TO STOKENSYNC;
GRANT SELECT ON STOP.PASSPORT_CONTACT TO STOKENSYNC;

--changeset mlo:1708
--comment: MC-29503: generate temp access key field for passport login in jdo
INSERT INTO AUTH."#JDO_PROPERTIES" (KEY, VALUE) VALUES ('PASSPORT_LOGIN.naming.inverse.AUTH.FK_PASSPORT_TEMP_ACCESS_KEY_PASSPORT_LOGIN_ID', 'tempAccessKeys');

--changeset tho:1709
--comment: RTNG-874: add new service component for T2EE
INSERT INTO MSS.SERVICE_COMPONENT (ID, NAME,INTERNAL_CODE,DEPRECATED,INTERNAL) VALUES (38,'Tunneling to External Entity','t2ee',0,0);

--changeset mlo:1710
--comment: MC-29503: grant permissions on contact sync tables for activation email job
GRANT SELECT ON STOP.CONTACT_SYNC TO STOKENSYNC;
GRANT SELECT ON STOP.PASSPORT_CONTACT_SYNC TO STOKENSYNC;

--changeset gta:1711
--comment: RTNG-862: add dbprop for path selection
INSERT INTO MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (57066, 'path', 1, '0', '^[01]$', NULL, 'Enable path selection');

--changeset lut:1712
--comment: RTNG-872: Add new logical interfaces DB Prop
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (57067, 'migrate.path.logical_interfaces', 1, '0', '^[01]$', NULL, 'Enables logical interfaces configuration in Path Selection');
