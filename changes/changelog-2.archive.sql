--liquibase formatted sql logicalFilePath:changelog-2.sql
-- CAUTION:
--  Always append at the end only!
-- If you modify a changeset, then specify runOnChange:true if you want it to be executed again

--changeset alg:2000 tag:v2.0.0
--comment: This initial changeset servers as a placeholder
SELECT 1 FROM DUAL;

--changeset alg:2001 tag:v2.0.1
--comment: This changeset servers also as a placeholder, but for tagging the container as :latest too
SELECT 1 FROM DUAL;

--changeset gks:2002
--comment: IDS-3164: Configure NDR Certificate Check
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (57070, 'ndr.certificate_check', 1, '0', '^[01]$', NULL, 'Enables NDR certificate checks');

--changeset aea:2003
--comment: OSCT-471: grant SVC_COPILOT access to tables in TIM
GRANT SELECT ON TIM.BLACKLIST_VALUE TO "SVC_COPILOT";
GRANT SELECT ON TIM.BLACKLIST_VALUE_CATEGORY TO "SVC_COPILOT";
GRANT SELECT ON TIM.BLACKLIST_VALUE_TYPE TO "SVC_COPILOT";
GRANT SELECT ON TIM.BLACKLIST_ZONE_FILE TO "SVC_COPILOT";
GRANT SELECT ON TIM.EXCLUSION_LIST_VALUE TO "SVC_COPILOT";
GRANT SELECT ON TIM.EXCLUSION_LIST_VALUE_TYPE TO "SVC_COPILOT";


--changeset mlo:2006
--comment: MC-29524: grants for SVC_USERS_INTERNAL_API to reset 2fa and passwords for MEP

GRANT SELECT,UPDATE on AUTH.PASSPORT_LOGIN to SVC_USERS_INTERNAL_API;
GRANT SELECT,UPDATE on AUTH.TOKEN to SVC_USERS_INTERNAL_API;
GRANT SELECT,DELETE on AUTH.PASSPORT_TEMP_ACCESS_KEY to SVC_USERS_INTERNAL_API;
GRANT SELECT on AUTH.AUTHSYS to SVC_USERS_INTERNAL_API;
GRANT EXECUTE on AUTH.OSAG_AUTH_PASSPORT to SVC_USERS_INTERNAL_API;
GRANT EXECUTE on AUTH.OSAG_AUTH to SVC_USERS_INTERNAL_API;

--changeset mlo:2004
--comment: MC-29506: expose components used for open systems identity users
UPDATE MCAUDIT.SYSTEM SET NAME = 'MEP Identity Service', DESCRIPTION = 'MEP Identity Service' WHERE MCAUDIT.SYSTEM.SHORT='auth';
INSERT INTO MCAUDIT.SYSTEM (ID, NAME, SHORT, DESCRIPTION) VALUES (5, 'Open Systems Identity Service', 'open_systems_identity_auth', 'Open Systems Identity Service');


--changeset mlo:2005
--comment: MC-29506: move portal related component to open systems identity system
UPDATE MCAUDIT.COMPONENT SET SYSTEM_ID = 5 WHERE SHORT = 'personal_settings';
UPDATE MCAUDIT.COMPONENT SET SYSTEM_ID = 5 WHERE SHORT = 'mca_contact_editor';
UPDATE MCAUDIT.COMPONENT SET SYSTEM_ID = 5 WHERE SHORT = 'permission_editor';
UPDATE MCAUDIT.COMPONENT SET SYSTEM_ID = 5 WHERE SHORT = 'mc_terms_consent';
UPDATE MCAUDIT.COMPONENT SET SYSTEM_ID = 5 WHERE SHORT = 'open_systems_identity_user_editor';

--changeset alg:2007
--comment: DB-2734: Cleanup job for lingering tickets in DEV
grant SELECT on SYS.V_$INSTANCE to "TT";

--changeset mlo:2008
--comment: MC-29524: additional grants for SVC_USERS_INTERNAL_API to reset 2fa and passwords for MEP

GRANT SELECT on AUTH.TEMP_ACCESS_TYPE to SVC_USERS_INTERNAL_API;

--changeset msc:2009
--comment: NC-1107: add dhcp-relay.init to the default of pacemaker.subsystems
update MSS.key k
set k.STRING_DEFAULT='dhcprelay.init dhcp-relay.init ospfd.init ripd.init'
where k.id=21406 and k.name='pacemaker.subsystems';

--changeset msc:2010
--comment: NC-1108: add @if_LOCAL_T2EE to the default of rps.interface
UPDATE MSS.key k SET k.STRING_DEFAULT='@if_LOCAL_GRE @if_LOCAL_T2EE' WHERE k.id=56880 and k.name='rps.interface';
UPDATE MSS.key k SET k.REGEXP='^$|@if_LOCAL_(GRE|ALLPHYS|T2EE) ?|(peth|(t[e46]|gre)_)[0-9]+(\/rx[0-9]+)?(=[0-9a-f]{0,8}(,[0-9a-f]{0,8})?)? ?' WHERE k.id=56880 and k.name='rps.interface';

--changeset rfr:2011
--comment: PRX-8945: Add new DB Prop migrate.2025.balanceng
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (57080, 'migrate.2025.balanceng', 1, '0', '^[01]$', NULL, 'BalanceNG migration dbprop');

--changeset lut:2012
--comment: RTNG-551: Implement DB changes for logical interfaces
-- new table to enumerate path selection link colors
CREATE TABLE APPID.PATH_SELECTION_COLOR (
	ID NUMBER(10,0) NOT NULL,
	NAME VARCHAR2(32) NULL,
	CONSTRAINT PATHSELECTIONCOLOR_PK PRIMARY KEY (ID)
);
INSERT INTO APPID.PATH_SELECTION_COLOR (ID, NAME) VALUES (0, NULL);
INSERT INTO APPID.PATH_SELECTION_COLOR (ID, NAME) VALUES (1, 'red');
INSERT INTO APPID.PATH_SELECTION_COLOR (ID, NAME) VALUES (2, 'blue');
INSERT INTO APPID.PATH_SELECTION_COLOR (ID, NAME) VALUES (3, 'yellow');
INSERT INTO APPID.PATH_SELECTION_COLOR (ID, NAME) VALUES (4, 'green');
INSERT INTO APPID.PATH_SELECTION_COLOR (ID, NAME) VALUES (5, 'orange');
INSERT INTO APPID.PATH_SELECTION_COLOR (ID, NAME) VALUES (6, 'purple');
INSERT INTO APPID.PATH_SELECTION_COLOR (ID, NAME) VALUES (7, 'black');
GRANT SELECT ON APPID.PATH_SELECTION_COLOR TO MCA;
GRANT SELECT ON APPID.PATH_SELECTION_COLOR TO VPN_GUI;
GRANT SELECT ON APPID.PATH_SELECTION_COLOR TO WEBRLS;
GRANT SELECT ON APPID.PATH_SELECTION_COLOR TO DECOMM;
GRANT SELECT ON APPID.PATH_SELECTION_COLOR TO CHE;
GRANT SELECT ON APPID.PATH_SELECTION_COLOR TO BIREADER;
GRANT SELECT ON APPID.PATH_SELECTION_COLOR TO SVC_BUILDSSE;
GRANT SELECT ON APPID.PATH_SELECTION_COLOR TO SVC_BUILDALL;
GRANT SELECT ON APPID.PATH_SELECTION_COLOR TO SVC_MC_PORTAL;

-- each link class has now a color
ALTER TABLE APPID.PATH_SELECTION_LINK_CLASS ADD (
  COLOR_ID NUMBER(10,0) DEFAULT 0 NOT NULL,
  CONSTRAINT PATH_SELECTION_LINK_CLASS_FK2 FOREIGN KEY (COLOR_ID) REFERENCES APPID.PATH_SELECTION_COLOR(ID)
);
COMMENT ON COLUMN APPID.PATH_SELECTION_LINK_CLASS.COLOR_ID IS 'Color ID of the link. Used in logical interfaces';

-- path selection overrides are now associated to a link class
ALTER TABLE APPID.PATH_OVERRIDE_MEMBER_LINK ADD (
  LINK_CLASS_ID NUMBER(10,0),
  CONSTRAINT PATH_OVERRIDE_MEMBER_LINK_FK4 FOREIGN KEY (LINK_CLASS_ID) REFERENCES APPID.PATH_SELECTION_LINK_CLASS(ID)
);
COMMENT ON COLUMN APPID.PATH_OVERRIDE_MEMBER_LINK.LINK_CLASS_ID IS 'Link ID of the override member';

-- introduce n:n relation between path selection link classes and interfaces
CREATE TABLE APPID.INTERFACE_2_PS_LINK_CLASS (
	INTERFACE_ID NUMBER(10,0) NOT NULL,
	LINK_CLASS_ID NUMBER(10,0) NOT NULL,
	CONSTRAINT INTERFACE_2_PS_LINK_CLASS_PK PRIMARY KEY (INTERFACE_ID,LINK_CLASS_ID),
	CONSTRAINT INTERFACE_2_PS_LINK_CLASS_FK1 FOREIGN KEY (LINK_CLASS_ID) REFERENCES APPID.PATH_SELECTION_LINK_CLASS(ID),
	CONSTRAINT INTERFACE_2_PS_LINK_CLASS_FK2 FOREIGN KEY (INTERFACE_ID) REFERENCES MSS.INTERFACE(ID)
);
GRANT SELECT,INSERT,UPDATE,DELETE ON APPID.INTERFACE_2_PS_LINK_CLASS TO MCA;
GRANT SELECT ON APPID.INTERFACE_2_PS_LINK_CLASS TO GETNODES;
GRANT SELECT ON APPID.INTERFACE_2_PS_LINK_CLASS TO VPN_GUI;
GRANT SELECT ON APPID.INTERFACE_2_PS_LINK_CLASS TO WEBRLS;
GRANT SELECT ON APPID.INTERFACE_2_PS_LINK_CLASS TO DECOMM;
GRANT SELECT ON APPID.INTERFACE_2_PS_LINK_CLASS TO CHE;
GRANT SELECT ON APPID.INTERFACE_2_PS_LINK_CLASS TO BIREADER;
GRANT SELECT ON APPID.INTERFACE_2_PS_LINK_CLASS TO SVC_BUILDSSE;
GRANT SELECT ON APPID.INTERFACE_2_PS_LINK_CLASS TO SVC_BUILDALL;
GRANT SELECT ON APPID.INTERFACE_2_PS_LINK_CLASS TO SVC_CONIFER;
GRANT SELECT ON APPID.INTERFACE_2_PS_LINK_CLASS TO SVC_MC_PORTAL;

--changeset rse:2013
--comment: TRIVIAL: Grant permissions to user mcmgw for passport DB split
GRANT SELECT ON AUTH.PASSPORT_LOGIN TO MCMGW;
GRANT SELECT ON STOP.PASSPORT_CONTACT TO MCMGW;

--changeset msc:2014
--comment: NC-1112: DBPROP to disable openvswitch as core component
INSERT into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
VALUES (57090, 'net.dpdk', 1, '0', '^[01]$', NULL, 'Allow to use DPDK on the system');

--changeset jkl:2015
--comment: RTNG-895: add BGP Hold Time field to VPN partitions
alter table VPN.PARTITION add BGP_HOLD_TIME NUMBER(10) DEFAULT 180;
comment on column VPN.PARTITION.BGP_HOLD_TIME is 'BGP Hold Time if it is a BGP Core partition.';

--changeset jkl:2016
--comment: RTNG-895: add BGP Keepalive field to VPN partitions
alter table VPN.PARTITION add BGP_KEEPALIVE NUMBER(10) DEFAULT 60;
comment on column VPN.PARTITION.BGP_KEEPALIVE is 'BGP Keepalive if it is a BGP Core partition.';

--changeset zak:2017
--comment: IE-42: grant city and address sequence SELECT permissions for site creation
GRANT SELECT ON MSS.ADDRESS_SEQ TO SVC_CONIFER;
GRANT SELECT ON MSS.CITY_SEQ TO SVC_CONIFER;

--changeset zak:2018
--comment: IE-42: grant city and address sequence INSERT permissions for site creation
GRANT INSERT ON MSS.CITY TO SVC_CONIFER;
GRANT INSERT ON MSS.ADDRESS TO SVC_CONIFER;
GRANT SELECT ON MSS.TIME_ZONE to SVC_CONIFER;

--changeset jad:2019
--comment: ZTNA-1537: permissions on ztna data
grant insert,update,delete on SVC_ZEROTRUST.ZTNA_TENANT to SVC_CONIFER;
grant select on SVC_ZEROTRUST.ZTNA_TENANT_SEQ to SVC_CONIFER;

--changeset mlo:2020
--comment: MC-29524: additional grants for SVC_USERS_INTERNAL_API to reset 2fa and passwords for MEP
GRANT SELECT on AUTH.TOKENTYPE to SVC_USERS_INTERNAL_API;

--changeset zak:2021
--comment IE-42: new record type for address creation
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID)
VALUES (455, 'Address created', 'address_create', 'A new company address has been created',1);

--changeset jmu:2022
--comment: PRX-8997: add city reference to cloud region to allow site creation from a cloud region
ALTER TABLE MSS.CLOUD_REGION_INSTANCE ADD CITY_ID NUMBER(10, 0);
ALTER TABLE MSS.CLOUD_REGION_INSTANCE ADD CONSTRAINT CLOUDREGIONINSTANCE_FK1 FOREIGN KEY (CITY_ID) REFERENCES MSS.CITY (ID);

CREATE INDEX MSS.IDX_CLOUD_REGION_CITY ON MSS.CLOUD_REGION_INSTANCE (CITY_ID);

COMMENT ON COLUMN MSS.CLOUD_REGION_INSTANCE.CITY_ID IS 'The city where the data center for the cloud region is located.
Knowing it allows to automatically set the address for services located in that cloud region.';

--changeset jmu:2023
--comment: PRX-8997: store cloud swg geolocation and exclusive IP config
ALTER TABLE MSS.CLOUD_REGION_INSTANCE ADD REGION_INTERNAL_IP NUMBER(10, 0);

CREATE TABLE MSS.GEO_LOCATION_IP(
    ID NUMBER(10) NOT NULL
        CONSTRAINT GEO_LOCATION_IP_PK
            PRIMARY KEY,
    INTERNAL_ID VARCHAR(63 BYTE) NOT NULL
        CONSTRAINT U_GEO_LOCATION_IP_INTERNAL_ID
            UNIQUE,
    NAME VARCHAR2(128) NOT NULL
        CONSTRAINT U_GEO_LOCATION_IP_NAME
            UNIQUE,
    CLOUD_REGION_INSTANCE_ID NUMBER(10,0)
        CONSTRAINT GEO_LOCATION_IP_FK1
            REFERENCES MSS.CLOUD_REGION_INSTANCE (ID),
    COUNTRY_ID NUMBER(10, 0) NOT NULL
        CONSTRAINT GEO_LOCATION_IP_FK2
            REFERENCES MSS.COUNTRY (ID),
    SUBDIVISION_CODE VARCHAR2(6 BYTE),
    CITY VARCHAR2(32),
    PRIORITY NUMBER(10, 0) NOT NULL,
    INTERNAL_IPV4 NUMBER(10, 0),
    EXTERNAL_IPV4 NUMBER(10, 0)
        CONSTRAINT U_GEO_LOCATION_IP_EXTERNAL_IPV4
            UNIQUE
);

CREATE SEQUENCE MSS.GEO_LOCATION_IP_SEQ;

COMMENT ON TABLE MSS.GEO_LOCATION_IP IS 'A geo location IP represents an egress IP that has a geofeed entry.
Traffic sent to a cloud swg available at the internal IP can egress to the internet with the external IP.
The country, subdivions, city correspond to the geofeed entry for the external IP, NOT the cloud region location.';
COMMENT ON COLUMN MSS.GEO_LOCATION_IP.INTERNAL_ID IS 'DNS label compliant ID, used by the cloud swg helm chart.';
COMMENT ON COLUMN MSS.GEO_LOCATION_IP.NAME IS 'Human reabled name to identify the IP object.';
COMMENT ON COLUMN MSS.GEO_LOCATION_IP.CLOUD_REGION_INSTANCE_ID IS 'The cloud region where the external IP has been onboarded (BYOIP).';
COMMENT ON COLUMN MSS.GEO_LOCATION_IP.PRIORITY IS 'If multiple IPs match a user''s location, the priority is used to decide which one to use. Higher number -> higher priority.';

CREATE INDEX MSS.IDX_GEOLOCIP_CLOUD_REGION ON MSS.GEO_LOCATION_IP (CLOUD_REGION_INSTANCE_ID);
CREATE INDEX MSS.IDX_GEOLOCIP_COUNTRY ON MSS.GEO_LOCATION_IP (COUNTRY_ID);

GRANT SELECT ON MSS.GEO_LOCATION_IP TO SVC_CONIFER;
GRANT INSERT ON MSS.GEO_LOCATION_IP TO SVC_CONIFER;
GRANT UPDATE ON MSS.GEO_LOCATION_IP TO SVC_CONIFER;
GRANT DELETE ON MSS.GEO_LOCATION_IP TO SVC_CONIFER;


CREATE TABLE MSS.EXCLUSIVE_IP(
    ID NUMBER(10) NOT NULL
        CONSTRAINT EXCLUSIVE_IP_PK
            PRIMARY KEY,
    INTERNAL_ID VARCHAR(63 BYTE) NOT NULL
        CONSTRAINT U_EXCLUSIVE_IP_INTERNAL_ID
            UNIQUE,
    CLOUD_REGION_INSTANCE_ID NUMBER(10,0)
        CONSTRAINT EXCLUSIVE_IP_FK1
            REFERENCES MSS.CLOUD_REGION_INSTANCE (ID),
    SERVICE_ID NUMBER(10, 0)
        CONSTRAINT EXCLUSIVE_IP_FK2
            REFERENCES MSS.SERVICE (ID)
            ON DELETE SET NULL,
    NAME VARCHAR2(128) NOT NULL
        CONSTRAINT U_EXCLUSIVE_IP_NAME
            UNIQUE,
    INTERNAL_IPV4 NUMBER(10, 0),
    EXTERNAL_IPV4 NUMBER(10, 0)
        CONSTRAINT U_EXCLUSIVE_IP_EXTERNAL_IPV4
            UNIQUE
);

CREATE SEQUENCE MSS.EXCLUSIVE_IP_SEQ;

CREATE INDEX MSS.IDX_EXCLUSIVE_IP_CLOUD_REGION ON MSS.EXCLUSIVE_IP (CLOUD_REGION_INSTANCE_ID);
CREATE INDEX MSS.IDX_EXCLUSIVE_IP_SERVICE ON MSS.EXCLUSIVE_IP (SERVICE_ID);

COMMENT ON TABLE MSS.EXCLUSIVE_IP IS 'An exclusive IP is available in a single cloud region.
In can be assigned to at most one service.
The service must be a cloud swg.';
COMMENT ON COLUMN MSS.EXCLUSIVE_IP.INTERNAL_ID IS 'DNS label compliant ID, used by the cloud swg helm chart.';
COMMENT ON COLUMN MSS.EXCLUSIVE_IP.NAME IS 'Human reabled name to identify the IP object.';
COMMENT ON COLUMN MSS.EXCLUSIVE_IP.CLOUD_REGION_INSTANCE_ID IS 'The cloud region where the external IP has been onboarded (BYOIP).';
COMMENT ON COLUMN MSS.EXCLUSIVE_IP.SERVICE_ID IS 'Service that this public IP is attached to.';

GRANT SELECT ON MSS.EXCLUSIVE_IP TO SVC_CONIFER;
GRANT INSERT ON MSS.EXCLUSIVE_IP TO SVC_CONIFER;
GRANT UPDATE ON MSS.EXCLUSIVE_IP TO SVC_CONIFER;
GRANT DELETE ON MSS.EXCLUSIVE_IP TO SVC_CONIFER;

CREATE TABLE MSS.SERVICE2GEO_LOCATION_IP(
    ID NUMBER(10, 0) NOT NULL
        CONSTRAINT SERVICE2GEO_LOCATION_IP_PK
            PRIMARY KEY,
    SERVICE_ID NUMBER(10, 0)
        CONSTRAINT SERVICE2GEO_LOCATION_IP_FK1
            REFERENCES MSS.SERVICE (ID)
            ON DELETE CASCADE,
    ENABLED_GEO_LOCATION_IP_ID NUMBER(10, 0)
        CONSTRAINT SERVICE2GEO_LOCATION_IP_FK2
            REFERENCES MSS.GEO_LOCATION_IP (ID)
            ON DELETE CASCADE,
    CONSTRAINT U_PROXY_SERVICE_GEO_LOCATION_IP
        UNIQUE (
            SERVICE_ID,
            ENABLED_GEO_LOCATION_IP_ID
        )
);

CREATE SEQUENCE MSS.SERVICE2GEO_LOCATION_IP_SEQ;

CREATE INDEX MSS.IDX_SERVICE_GEO_IP_1 ON MSS.SERVICE2GEO_LOCATION_IP (SERVICE_ID);
CREATE INDEX MSS.IDX_SERVICE_GEO_IP_2 ON MSS.SERVICE2GEO_LOCATION_IP (ENABLED_GEO_LOCATION_IP_ID);

COMMENT ON TABLE MSS.SERVICE2GEO_LOCATION_IP IS 'Link between MSS.SERVICE and MSS.GEO_LOCATION_IP.
An entry represents that the specified geolocation IP is enabled for the service.
The service must be cloud swg.';

GRANT SELECT ON MSS.SERVICE2GEO_LOCATION_IP TO SVC_CONIFER;
GRANT INSERT ON MSS.SERVICE2GEO_LOCATION_IP TO SVC_CONIFER;
GRANT UPDATE ON MSS.SERVICE2GEO_LOCATION_IP TO SVC_CONIFER;
GRANT DELETE ON MSS.SERVICE2GEO_LOCATION_IP TO SVC_CONIFER;

--changeset jmu:2024
--comment: PRX-8997: link IDAC and cloud swg in DB
GRANT REFERENCES ON MSS.SERVICE TO PRX;

CREATE TABLE PRX.CLOUDSWG_SERVICE2IDAC_SERVICE(
    ID NUMBER(10, 0) NOT NULL
        CONSTRAINT CLOUDSWG_SERVICE2IDAC_SERVICE_PK
            PRIMARY KEY,
    CLOUDSWG_SERVICE_ID NUMBER(10, 0) NOT NULL
        CONSTRAINT CLOUDSWG_SERVICE2IDAC_SERVICE_FK1
            REFERENCES MSS.SERVICE (ID)
            ON DELETE CASCADE,
    IDAC_SERVICE_ID NUMBER(10, 0) NOT NULL
        CONSTRAINT CLOUDSWG_SERVICE2IDAC_SERVICE_FK2
            REFERENCES MSS.SERVICE (ID)
            ON DELETE CASCADE,
    CONSTRAINT U_CLOUDSWG_SERVICE_IDAC_SERVICE
        UNIQUE (
            CLOUDSWG_SERVICE_ID,
            IDAC_SERVICE_ID
        )
);

CREATE SEQUENCE PRX.CLOUDSWG_SERVICE2IDAC_SERVICE_SEQ;

CREATE UNIQUE INDEX PRX.IDX_CLOUDSWG_IDAC_1 ON PRX.CLOUDSWG_SERVICE2IDAC_SERVICE (CLOUDSWG_SERVICE_ID);
CREATE INDEX PRX.IDX_CLOUDSWG_IDAC_2 ON PRX.CLOUDSWG_SERVICE2IDAC_SERVICE (IDAC_SERVICE_ID);

COMMENT ON TABLE PRX.CLOUDSWG_SERVICE2IDAC_SERVICE IS 'Enforement point (IDAC) and cloud swg are separate services.
They must be linked for the cswg to be reachable.';

GRANT SELECT ON PRX.CLOUDSWG_SERVICE2IDAC_SERVICE TO SVC_CONIFER;
GRANT INSERT ON PRX.CLOUDSWG_SERVICE2IDAC_SERVICE TO SVC_CONIFER;
GRANT UPDATE ON PRX.CLOUDSWG_SERVICE2IDAC_SERVICE TO SVC_CONIFER;
GRANT DELETE ON PRX.CLOUDSWG_SERVICE2IDAC_SERVICE TO SVC_CONIFER;

--changeset ngl:2025
--comment: SRE-1183: allow mc-automation to query SLA data
GRANT SELECT ON MC.AVAILABILITY_REPORT TO SVC_AUTOMATION_EXECUTOR;
GRANT SELECT ON MC.CONN_SLA_TARGET TO SVC_AUTOMATION_EXECUTOR;

--changeset rha:2026
--comment: MEP-2567: track CSR creation timestamp
ALTER TABLE CERTS.CSR ADD CREATED TIMESTAMP(6) WITH TIME ZONE DEFAULT SYSTIMESTAMP;

--changeset niv:2027
--comment: DBPROP to enable writing of new HCV cert material for the rabbitMQ servers
INSERT into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
VALUES (57091, 'mgmtserver.balu_broker.hcv_cert', 1, '0', '^[01]$', NULL, 'Write new HCV cert material for the rabbitMQ servers');

--changeset ogl:2027
--comment: AUT-1260: Use new passport schema in the auth update
GRANT EXECUTE ON AUTH.OSAG_AUTH_PASSPORT TO GUMA2;

--changeset aas:2028
--comment: ZTNA-1641: Set ztna.prod.osse.io as default for ztna.upstream
UPDATE MSS.key k SET k.STRING_DEFAULT='ztna.prod.osse.io' WHERE k.id=24506 and k.name='ztna.upstream';

--changeset ogl:2029
--comment: DB-2800: unified app inventory
insert into MCAUDIT.RECORD_TYPE(ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID)
VALUES (456, 'Unified App Group modified', 'uappgroup_modified', 'An application group was modified', 1);
insert into MCAUDIT.RECORD_TYPE(ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID)
VALUES (457, 'Unified App modified', 'uapp_modified', 'An application was modified', 1);
insert into MCAUDIT.RECORD_TYPE(ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID)
VALUES (458, 'Unified App Group member added', 'uappgroup_member_created', 'An application was added to a group', 1);
insert into MCAUDIT.RECORD_TYPE(ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID)
VALUES (459, 'Unified App member deleted', 'uappgroup_member_deleted', 'An application was removed from a group', 1);

--changeset mlo:2030
--comment: TRIVIAL: disable code generation for CERTS tables
DELETE FROM CERTS."#JDO_PROPERTIES" where 1=1;
INSERT INTO CERTS."#JDO_PROPERTIES" ("KEY","VALUE") VALUES ('CERTIFICATE.naming','none');
INSERT INTO CERTS."#JDO_PROPERTIES" ("KEY","VALUE") VALUES ('CERTIFICATE_INDEX.naming','none');
INSERT INTO CERTS."#JDO_PROPERTIES" ("KEY","VALUE") VALUES ('CERTIFICATE_SCOPE_TYPE.naming','none');
INSERT INTO CERTS."#JDO_PROPERTIES" ("KEY","VALUE") VALUES ('CERTIFICATE_USAGE.naming','none');
INSERT INTO CERTS."#JDO_PROPERTIES" ("KEY","VALUE") VALUES ('CSR.naming','none');
INSERT INTO CERTS."#JDO_PROPERTIES" ("KEY","VALUE") VALUES ('PRIVATE_KEY.naming','none');
INSERT INTO CERTS."#JDO_PROPERTIES" ("KEY","VALUE") VALUES ('SAN.naming','none');

--changeset jmu:2031
--comment: PRX-8999: grant access to sequences to config api user
GRANT SELECT ON MSS.GEO_LOCATION_IP_SEQ TO SVC_CONIFER;
GRANT SELECT ON MSS.EXCLUSIVE_IP_SEQ TO SVC_CONIFER;
GRANT SELECT ON MSS.SERVICE2GEO_LOCATION_IP_SEQ TO SVC_CONIFER;
GRANT SELECT ON PRX.CLOUDSWG_SERVICE2IDAC_SERVICE_SEQ TO SVC_CONIFER;

--changeset ogl:2032
--comment: DB-2800: unified app inventory
insert into MCAUDIT.RECORD_TYPE(ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID)
VALUES (460, 'Unified App selector modified', 'uappselector_modified', 'An selector was modified', 1);

--changeset niv:2033
--comment: use new hcv client cert by default
update mss.KEY
set string_default='1'
where name='balu.gateway.hcv_cert';

--changelog ogl:2034
--comment: DB-2800: unified app inventory QuickID integration
GRANT SELECT ON APPID.APP_SEQUENCE TO SVC_CONIFER;
GRANT INSERT,DELETE on APPID.QUICKID_DNS TO SVC_CONIFER;
GRANT INSERT,DELETE on APPID.QUICKID_NET4 TO SVC_CONIFER;
GRANT INSERT,DELETE on APPID.QUICKID_NET6 TO SVC_CONIFER;
GRANT INSERT,DELETE on APPID.QUICKID_PROTO TO SVC_CONIFER;
GRANT INSERT,DELETE on APPID.QUICKID_TOS TO SVC_CONIFER;
GRANT SELECT ON APPID.QUICKID_DNS_SEQUENCE TO SVC_CONIFER;
GRANT SELECT ON APPID.QUICKID_NET4_SEQUENCE TO SVC_CONIFER;
GRANT SELECT ON APPID.QUICKID_NET6_SEQUENCE TO SVC_CONIFER;
GRANT SELECT ON APPID.QUICKID_PROTO_SEQUENCE TO SVC_CONIFER;
GRANT SELECT ON APPID.QUICKID_TOS_SEQUENCE TO SVC_CONIFER;

--changeset niv:2035
--comment: DBPROP to enable writing of new HCV cert material for the mcapp balu client
INSERT into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
VALUES (57092, 'mgmtserver.mcapp.balu_hcv_cert', 1, '0', '^[01]$', NULL, 'Write new HCV cert material for the mcapp client');

--changeset mlo:2036
--comment: MC-29821: remove deprecated FK constraint between AUTH.LOGIN and AUTH.TOKEN
ALTER TABLE AUTH.LOGIN
    disable constraint FK_LOGIN_REPLACEMENTTOKEN_ID
    disable constraint FK_LOGIN_TOKEN_ID;
ALTER TABLE AUTH.TEMP_ACCESS_KEY
    disable constraint FK_TEMP_ACCESS_KEY_TOKEN_ID;

--changeset fpi:2037
--comment: FW-6482: Remove unused juniper.* DB Props
DELETE FROM MSS.KEY WHERE ID=20600 AND NAME='juniper.loghost';
DELETE FROM MSS.KEY WHERE ID=20601 AND NAME='juniper.netdebug.int';
DELETE FROM MSS.KEY WHERE ID=20602 AND NAME='juniper.netdebug.ext';
DELETE FROM MSS.KEY WHERE ID=20604 AND NAME='juniper.cluster.node_id';
DELETE FROM MSS.KEY WHERE ID=20605 AND NAME='juniper.cluster.priority';
DELETE FROM MSS.KEY WHERE ID=20606 AND NAME='juniper.cluster.id';
DELETE FROM MSS.KEY WHERE ID=20610 AND NAME='juniper.ospf.export.rip';
DELETE FROM MSS.KEY WHERE ID=20611 AND NAME='juniper.ospf.export.default';
DELETE FROM MSS.KEY WHERE ID=20620 AND NAME='juniper.rip.export.ospf';
DELETE FROM MSS.KEY WHERE ID=20621 AND NAME='juniper.rip.import.default';
DELETE FROM MSS.KEY WHERE ID=20622 AND NAME='juniper.rip.distance';
DELETE FROM MSS.KEY WHERE ID=20900 AND NAME='juniper.alg.sip';
DELETE FROM MSS.KEY WHERE ID=20901 AND NAME='juniper.alg.h323';
DELETE FROM MSS.KEY WHERE ID=20902 AND NAME='juniper.alg.sql';
DELETE FROM MSS.KEY WHERE ID=20903 AND NAME='juniper.alg.sccp';
DELETE FROM MSS.KEY WHERE ID=20904 AND NAME='juniper.alg.msrpc';
DELETE FROM MSS.KEY WHERE ID=20905 AND NAME='juniper.alg.sunrpc';

--changeset gta:2038
--comment: RTNG-931: add MTU to TUNNEL table
ALTER TABLE vpn.TUNNEL
ADD MTU NUMBER(6);

--changeset ogl:2039
--comment: fk index
create index mss.ADDRESS_COMPANY on mss.ADDRESS(COMPANY_ID);

--changeset lut:2040
--comment: Remove unused path.topo-aware-ospf-costs dbprop
DELETE FROM MSS.KEY WHERE ID = 22520;

--changeset jkl:2041
--comment: RTNG-938: Add dbprop for eBGP to OSPF redistribution
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (57093, 'wan.bgp_core.redistribute_ebgp_ospf', 1, '0', '^[0-9]{1,10}(?: [0-9]{1,10})*$', NULL, 'Redistribute eBGP routes into OSPF on the given partitions (space separated list of partition IDs)');

--changeset sst:2042
--comment: IE-44: grant localcontact sequence SELECT permissions for localcontact creation
GRANT SELECT ON MSS.LOCALCONTACT_SEQ TO SVC_CONIFER;

--changeset lut:2043
--comment: Revert changeset lut:2040 until CBLX 11.63 is released
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (57094, 'path.topo-aware-ospf-costs', 1, '0', '^[01]$', NULL, 'Incorporate Path Selecion Topologies into OSPF cost computation');

--changeset sst:2044
--comment: IE-44: grant localcontact sequence SELECT permissions for localcontact creation
GRANT SELECT,INSERT,UPDATE,DELETE ON MSS.LOCAL_CONTACT TO SVC_CONIFER;
GRANT SELECT,INSERT,UPDATE,DELETE ON STOP.CONTACT TO SVC_CONIFER;

--changeset sst:2045
--comment: IE-44: add record type
insert into MCAUDIT.RECORD_TYPE(ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID)
VALUES (461, 'Local contact add', 'localcontact_add', 'a new local contact has been added', 1);

--changeset jkl:2046
--comment: RTNG-938: Correct key type of dbprop for eBGP to OSPF redistribution
DELETE FROM MSS.KEY WHERE ID = 57093;
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (57093, 'wan.bgp_core.redistribute_ebgp_ospf', 4, NULL, '^[0-9]{1,10}(?: [0-9]{1,10})*$', NULL, 'Redistribute eBGP routes into OSPF on the given partitions (space separated list of partition IDs)');

--changeset rha:2047
--comment: ZTNA-1621: create ZTNA cert reload migration dbprop
INSERT INTO MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
VALUES (57081, 'migrate.2025.ztna.cert-reload', 1, '0', '^[01]$', NULL, 'ZTNA certificate reload migration dbprop');

--changeset rse:2048
--comment: TRIVIAL: Add update timestamp column for MSS.OPENVPN_INTERFACE
ALTER TABLE MSS.OPENVPN_INTERFACE ADD TIMESTAMP_UPDATE_UNIX_US NUMBER DEFAULT 0;
COMMENT ON COLUMN MSS.OPENVPN_INTERFACE.TIMESTAMP_UPDATE_UNIX_US IS 'Entry update UNIX timestamp in microseconds from the client-(dis)connect script on the OpenVPN server';

insert into mss."#JDO_PROPERTIES" (key, value)
values ('OPENVPN_INTERFACE.naming.TIMESTAMP_UPDATE_UNIX_US', 'none');

--changeset sst:2049
--comment: IE-44: grant contact sequence SELECT permissions for contact creation
GRANT SELECT ON STOP.CONTACT_SEQ TO SVC_CONIFER;

--changeset gks:2050
--comment: IDS-3028: Implement host isolation (killswitch) in the mc-config-api
GRANT SELECT,INSERT,UPDATE ON NIDS.INVESTIGATION TO SVC_CONIFER;
GRANT SELECT,INSERT,UPDATE ON NIDS.INVESTIGATION_ENTRY TO SVC_CONIFER;
GRANT SELECT,INSERT,UPDATE ON NIDS.KS_ENFORCEMENT TO SVC_CONIFER;
GRANT SELECT,INSERT,UPDATE ON NIDS.KS_ENFORCEMENT_SCOPE TO SVC_CONIFER;
GRANT SELECT ON NIDS.INVESTIGATION_SEQ TO SVC_CONIFER;
GRANT SELECT ON NIDS.INVESTIGATION_ENTRY_SEQ TO SVC_CONIFER;
GRANT SELECT ON NIDS.KS_ENFORCEMENT_SEQ TO SVC_CONIFER;
GRANT SELECT ON NIDS.KS_ENFORCEMENT_SCOPE_SEQ TO SVC_CONIFER;
GRANT SELECT ON NIDS.INVESTIGATION_FINDING TO SVC_CONIFER;
GRANT SELECT ON NIDS.INVESTIGATION_STATUS TO SVC_CONIFER;
GRANT SELECT ON NIDS.KS_SCOPE_TYPE TO SVC_CONIFER;

--changeset niv:2046
--comment: disuse new hcv client cert by default
update mss.KEY
set string_default='0'
where name='balu.gateway.hcv_cert';

--changeset mlo:2051
--comment: MC-29845: Add auth.role and RLS predicates for open systems identity user management roles

--create the 3 roles => IDs are the same as existing user roles + 10
INSERT INTO AUTH.ROLE (ID, NAME, DESCRIPTION)
VALUES (21, 'mc-cust-open-systems-identity-users-admin', 'Open Systems Identity User Management Administrator');
INSERT INTO AUTH.ROLE (ID, NAME, DESCRIPTION)
VALUES (22, 'mc-cust-open-systems-identity-users-monitor', 'Open Systems Identity User Management Monitor');
INSERT INTO AUTH.ROLE (ID, NAME, DESCRIPTION)
VALUES (26, 'mc-cust-open-systems-identity-users-auditor', 'Open Systems Identity User Management Auditor');

--copy all the predicates from mep user management roles to their corresponding open systems id user management role
-- copy predicates from  'mc-cust-users-admin' to 'mc-cust-open-systems-identity-users-admin'
INSERT INTO RLSDEF.PREDICATE(ID, SCHEMA_NAME, TABLE_NAME,
                             ROLE_ID, PREDICATE, EXTENDED_PREDICATE,
                             PRIORITY, READ_WRITE, AREA_ID)
SELECT RLSDEF.PREDICATE_SEQ.nextval,
       SCHEMA_NAME,
       TABLE_NAME,
       21,
       PREDICATE,
       EXTENDED_PREDICATE,
       PRIORITY,
       READ_WRITE,
       AREA_ID
from RLSDEF.PREDICATE
where role_id = 11;
-- copy predicates from 'mc-cust-users-monitor' to 'mc-cust-open-systems-identity-users-monitor'
INSERT INTO RLSDEF.PREDICATE(ID, SCHEMA_NAME, TABLE_NAME,
                             ROLE_ID, PREDICATE, EXTENDED_PREDICATE,
                             PRIORITY, READ_WRITE, AREA_ID)
SELECT RLSDEF.PREDICATE_SEQ.nextval,
       SCHEMA_NAME,
       TABLE_NAME,
       22,
       PREDICATE,
       EXTENDED_PREDICATE,
       PRIORITY,
       READ_WRITE,
       AREA_ID
from RLSDEF.PREDICATE
where role_id = 12;
-- copy predicates from 'mc-cust-users-auditor' to 'mc-cust-open-systems-identity-users-auditor'
INSERT INTO RLSDEF.PREDICATE(ID, SCHEMA_NAME, TABLE_NAME,
                             ROLE_ID, PREDICATE, EXTENDED_PREDICATE,
                             PRIORITY, READ_WRITE, AREA_ID)
SELECT RLSDEF.PREDICATE_SEQ.nextval,
       SCHEMA_NAME,
       TABLE_NAME,
       26,
       PREDICATE,
       EXTENDED_PREDICATE,
       PRIORITY,
       READ_WRITE,
       AREA_ID
from RLSDEF.PREDICATE
where role_id = 16;

--changeset ogl:2052
--comment: DB-2872: stop triggers needs service
grant select on mss.SERVICE to STOP;
-- fix regression due to new version trigger
grant select on MSS.interface to svc_fast_interface_rename;

--changeset doi:2053
--comment: PRX-9090: casb self-service update existing db audit entries and delete old record types
UPDATE MCAUDIT.RECORD SET RECORD_TYPE_ID = 391 WHERE RECORD_TYPE_ID = 379;
UPDATE MCAUDIT.RECORD SET RECORD_TYPE_ID = 392 WHERE RECORD_TYPE_ID = 380;
UPDATE MCAUDIT.RECORD SET RECORD_TYPE_ID = 393 WHERE RECORD_TYPE_ID = 381;

DELETE FROM MCAUDIT.RECORD_TYPE WHERE ID IN (379, 380, 381);

--changeset lut:2054
--comment: Remove again unused path.topo-aware-ospf-costs dbprop
DELETE FROM MSS.VALUE WHERE KEY_ID = 57094;
DELETE FROM MSS.KEY WHERE ID = 57094;

--changeset evv:2055
--comment: PRX-9084: Add audit record types for Cloud SWG geolocation on ZTNA and Proxy nodes
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID)
VALUES (462, 'ZTNA Proxy Updated', 'ztna_proxy_modified', 'Proxy service linked to a ZTNA tenant updated', 2);

INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID)
VALUES (463, 'WebSec Enforcement Point Updated', 'websec_enforcement_point_modified', 'WebSec enforcement point updated', 2);

INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID)
VALUES (464, 'WebSec Locations Updated', 'websec_locations_modified', 'Locations assigned to a service', 2);

INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID)
VALUES (465, 'WebSec Exclusive IP Updated', 'websec_exclusive_ip_modified', 'Exclusive IP assigned to a service', 2);

--changeset dnb:2056
--comment: MX-5910: Remove obsolete mail.antispam.ctasd* and mail.antispam.sophos* dbprops and set new expurgate defaults
DELETE FROM mss.value WHERE key_id IN (SELECT id FROM mss.key WHERE name = 'mail.antispam.ctasd');
DELETE FROM mss.key WHERE name = 'mail.antispam.ctasd';

DELETE FROM mss.value WHERE key_id IN (SELECT id FROM mss.key WHERE name = 'mail.antispam.ctasd.log_only');
DELETE FROM mss.key WHERE name = 'mail.antispam.ctasd.log_only';

DELETE FROM mss.value WHERE key_id IN (SELECT id FROM mss.key WHERE name = 'mail.antispam.sophos');
DELETE FROM mss.key WHERE name = 'mail.antispam.sophos';

DELETE FROM mss.value WHERE key_id IN (SELECT id FROM mss.key WHERE name = 'mail.antispam.sophos.log_only');
DELETE FROM mss.key WHERE name = 'mail.antispam.sophos.log_only';

UPDATE mss.key SET string_default = '1' WHERE name = 'mail.antispam.expurgate';
UPDATE mss.key SET string_default = '0' WHERE name = 'mail.antispam.expurgate.log_only';

--changeset mlo:2052
--comment: MC-29532: Disable JDO generation of LOGIN join tables
DELETE FROM AUTH."#JDO_PROPERTIES" where KEY='LOGIN2GROUPS.naming';
INSERT INTO AUTH."#JDO_PROPERTIES" (KEY, VALUE) values ('LOGIN2GROUPS.naming', 'none');

DELETE FROM AUTH."#JDO_PROPERTIES" where KEY='LOGIN2TUNNELGROUP.naming';
INSERT INTO AUTH."#JDO_PROPERTIES" (KEY, VALUE) values ('LOGIN2TUNNELGROUP.naming', 'none');

DELETE FROM AUTH."#JDO_PROPERTIES" where KEY='TEMP_ACCESS_KEY.naming';
INSERT INTO AUTH."#JDO_PROPERTIES" (KEY, VALUE) values ('TEMP_ACCESS_KEY.naming', 'none');

DELETE FROM AUTH."#JDO_PROPERTIES" where KEY='ALIAS.naming';
INSERT INTO AUTH."#JDO_PROPERTIES" (KEY, VALUE) values ('ALIAS.naming', 'none');

DELETE FROM AUTH."#JDO_PROPERTIES" where KEY='RECENTPASSWORD.naming';
INSERT INTO AUTH."#JDO_PROPERTIES" (KEY, VALUE) values ('RECENTPASSWORD.naming', 'none');

DELETE FROM STOP."#JDO_PROPERTIES" where KEY='CONTACT_SYNC.naming';
INSERT INTO STOP."#JDO_PROPERTIES" (KEY, VALUE) values ('CONTACT_SYNC.naming', 'none');

--changeset tte:2057
--comment: Clean CONFIG_DEPLOYMENT_USE_CASE table usage
DELETE FROM MSS."#JDO_PROPERTIES" where KEY='CONFIG_DEPLOYMENT_USE_CASE.naming';
INSERT INTO MSS."#JDO_PROPERTIES" (KEY, VALUE) values ('CONFIG_DEPLOYMENT_USE_CASE.naming', 'none');

--changeset phm:2058
--comment: HACK-2024: Add missing permissions for svc_conifer
grant update on MSS.ISP_LINK to SVC_CONIFER;

--changeset fla:2059
--comment:
ALTER TABLE APPID.PATH_SELECTION_LINK_CLASS MODIFY COLOR_ID DEFAULT ON NULL 0;

--changeset mlo:2059
--comment: MC-29532: Grant necessary selects to BIREADER
GRANT SELECT on AUTH.PASSPORT_LOGIN to BIREADER;
GRANT SELECT on AUTH.PASSPORT_LOGIN2TUNNELGROUP to BIREADER;
GRANT SELECT on AUTH.PASSPORT_LOGIN2GROUPS to BIREADER;
GRANT SELECT on STOP.PASSPORT_CONTACT to BIREADER;

--changeset mlo:20260 endDelimiter:/
--comment: MC-29532: Adapt BIREADER views referencing wrong login tables


create or replace force view BIREADER.V_AUTH_LOGIN2GROUPS as
Select l2tg.login_id, tg.name

FROM AUTH.PASSPORT_LOGIN2TUNNELGROUP l2tg
         JOIN AUTH.TUNNELGROUP tg on (l2tg.TUNNELGROUP_id = tg.id)
         JOIN AUTH.PASSPORT_LOGIN l ON l2tg.login_id=l.id
         JOIN STOP.PASSPORT_CONTACT c ON l.contact_id=c.id
WHERE c.company_id=6
/

create or replace force view BIREADER.V_AUTH_LOGIN2TUNNELGROUP as
select l.id,
       g.name          as radiusgroup_name,
       g.description   as radiusgroup_description
FROM AUTH.PASSPORT_LOGIN2GROUPS l2g
         JOIN AUTH.PASSPORT_LOGIN          l on (l2g.LOGIN_ID=l.id)
         JOIN AUTH.GROUPS         g on (l2g.GROUP_ID = g.id)
         JOIN STOP.PASSPORT_CONTACT        c on (c.id = l.contact_id)
WHERE c.company_id=6
/

create or replace force view BIREADER.V_AUTH_LOGIN2TUNNELGROUP_NEW as
SELECT LOGIN_ID, TUNNELGROUP_ID FROM AUTH.PASSPORT_LOGIN2TUNNELGROUP
/

create or replace force view BIREADER.V_MC_PERMISSION_RADIUS as
SELECT    l.id  as login_id,    g.id as radiusgroup_id,    g.name  as radiusgroup_name,    g.description as radiusgroup_description
FROM AUTH.PASSPORT_LOGIN2GROUPS l2g
         JOIN AUTH.PASSPORT_LOGIN l on (l2g.LOGIN_ID=l.id)
         JOIN AUTH.GROUPS  g on (l2g.GROUP_ID = g.id)
         JOIN STOP.PASSPORT_CONTACT c on (c.id = l.contact_id)
WHERE c.company_id=6
/

--changeset mlo:2064
--comment: MC-29532: Disable JDO generation of LOGIN join tables
DROP TABLE AUTH.LOGIN2GROUPS;
DROP TABLE AUTH.LOGIN2TUNNELGROUP;
DROP TABLE AUTH.TEMP_ACCESS_KEY;
DROP TABLE AUTH.ALIAS;
DROP TABLE AUTH.RECENTPASSWORD;
DROP TABLE STOP.CONTACT_SYNC;

--changeset jkl:2065
--comment: RTNG-979: Add dbprop to enable frrouting monitoring and anomaly detection
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (57094, 'frrouting.mad', 1, '0', '^[01]$', NULL, 'Enable frrouting monitoring and anomaly detection');

--changeset jkl:2066
--comment: RTNG-979: Add dbprop to set the polling interval for frrouting monitoring and anomaly detection
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (57095, 'frrouting.mad.poll_interval', 2, '30', '^[1-9][0-9]*$', NULL, 'Set the polling interval for frrouting monitoring and anomaly detection');

--changeset jkl:2067
--comment: RTNG-979: Add dbprop to set the debug level for frrouting monitoring and anomaly detection
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (57096, 'frrouting.mad.debug_level', 4, 'none', '^[A-Za-z0-9 _]+$', NULL, 'Set the debug level for frrouting monitoring and anomaly detection');

--changeset mlo:2068
--comment: MC-29963: Disable JDO generation of COST_CENTER table and column
DELETE FROM MSS."#JDO_PROPERTIES" where KEY='COST_CENTER.naming';
INSERT INTO MSS."#JDO_PROPERTIES" (KEY, VALUE) values ('COST_CENTER.naming', 'none');
DELETE FROM AUTH."#JDO_PROPERTIES" where KEY='LOGIN.naming.COST_CENTER_ID';
INSERT INTO AUTH."#JDO_PROPERTIES" (KEY, VALUE) values ('LOGIN.naming.COST_CENTER_ID', 'none');
DELETE FROM AUTH."#JDO_PROPERTIES" where KEY='PASSPORT_LOGIN.naming.COST_CENTER_ID';
INSERT INTO AUTH."#JDO_PROPERTIES" (KEY, VALUE) values ('PASSPORT_LOGIN.naming.COST_CENTER_ID', 'none');

--changeset mlo:2069
--comment: MC-29963: drop FK constraints to cost center table
ALTER TABLE AUTH.PASSPORT_LOGIN drop constraint FK_PASSPORT_LOGIN_COST_CENTER_ID;
ALTER TABLE AUTH.LOGIN drop constraint FK_LOGIN_COST_CENTER_ID;

--changeset ogl:2070
--comment: DB-2877: cascade delete availability reports
GRANT DELETE ON MC.AVAILABILITY_REPORT TO SVC_CONIFER;

--changeset ahd:2071
--comment: FW-6651: Add new DB Prop fw.log.loki.debug
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (57100, 'fw.log.loki.debug', 4, 'forward ingress', '^[A-Za-z0-9 _]+$', NULL, 'Ship debug logs of these categories via loki (space separated list of log categories). Set to empty if fw.log.loki is 0;');

--changeset mlo:2072 endDelimiter:/
--comment: MC-29963: adapt views that were using cost centers

create or replace force view AUTH.V_LOGIN as
SELECT l.id, l.login, l.contact_id, l.locked, l.homeauthhost_id, l.maxretries, l.lastaccept, l.lastreject,
       l.anytunnelgroup, l.passwordexpiry,
       c.firstname contact_firstname, c.lastname contact_lastname, c.email contact_email,
       c.company_id contact_company_id, c.fax contact_fax, c.direct contact_direct, c.mobile contact_mobile,
       c.home contact_home, at.id authtype_id, at.name authtype_name, tt.id tokentype_id,
       tt.name tokentype_name, t.id token_id, t.serial token_serial, a.id authsys_id, a.name authsys_name,
       h.name host_name, h.id host_id, t.EXPIRYDATE token_expirydate
FROM auth.login l, auth.token t, auth.authsys a, auth.authtype at, auth.tokentype tt, stop.contact c,
     authhost2authsys ah2a, mss.host h, auth.authhost ah
WHERE l.contact_id = c.id
  AND at.id = l.authtype_id
  AND l.token_id = t.id(+)
  AND tt.id(+) = t.tokentype_id
  AND ah.id = l.homeauthhost_id
  AND ah.host_id = h.id
  AND ah2a.authhost_id = l.homeauthhost_id
  AND ah2a.authsys_id = a.id
WITH READ ONLY
/

create or replace force view AUTH.V_S_LOGIN as
SELECT id,
       login,
       contact_id,
       token_id,
       replacementtoken_id,
       email,
       smsauthnumber,
       tokenreplacementstate_id,
       homeauthhost_id,
       enabled,
       locked,
       maxretries,
       lastaccept,
       lastreject,
       anytunnelgroup,
       passwordexpiry,
       company_id,
       passwordtype_id,
       twofactorenabled,
       user_unit_id,
       modified,
       lasttokenrequestdate,
       managing_login_id,
       authtype_id,
       lastpwchange,
       tmppwdonlyexpiry,
       creationdate
FROM login
WITH READ ONLY
/

--changeset mlo:2073
--comment: MC-29963: cost center table and columns
ALTER TABLE AUTH.LOGIN drop column COST_CENTER_ID;

--changeset mlo:2074
--comment: MC-29972: add soc analyst column on login table
ALTER TABLE AUTH.LOGIN add SOC_ANALYST NUMBER(1) default on null 0 not null;

--changeset gks:2075
--comment: IDS-3280: Sanitize NDR IPS dbprops
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (57110, 'ndr.ips', 1, '0', '^[01]$', NULL, 'Enables NDR Intrusion Prevention System (IPS)');
update mss.key k
set k.NAME='ndr.ioc.abuse-ch'
where k.id=57070
and k.name='ndr.certificate_check';

--changeset ogl:2076
--comment: DB-2922: add record type for auth/deauth
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID)
VALUES (466, 'Unified App authorized', 'uappauth_created', 'An application or group has been authorized to a user or group',1);
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID)
VALUES (467, 'Unified App deauthorized', 'uappauth_deleted', 'An application or group has been deauthorized from a user or group',1);

--changeset gta:2077
--comment: RTNG-950: Add migrate dbprop to enable 'Avoid ESP Fragments' on ISP Links
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (57111, 'migrate.isp_internal_fragmentation', 1, NULL, '^[01]$', NULL, 'Set the ISP Link to avoid ESP fragments. When set to 0 or 1, the same value will be set for MSS.ISP_LINK.IPSEC_INTERNAL_FRAGMENTATION. If NULL, the ISP Link will not be changed.');
grant update on mss.isp_link to vpn_gui;
grant update on mss.isp_link to SVC_BUILDALL;

--changeset tte:2078
--comment: MC-30025 add naming.inverse values so Interface.java and PathSelectionLinkClass.java refer to each other via link table
INSERT INTO APPID."#JDO_PROPERTIES" (KEY, VALUE) VALUES ('PATH_SELECTION_LINK_CLASS.naming.inverse.APPID.INTERFACE_2_PS_LINK_CLASS_FK1', 'interfaces');
INSERT INTO MSS."#JDO_PROPERTIES" (KEY, VALUE) VALUES ('INTERFACE.naming.inverse.APPID.INTERFACE_2_PS_LINK_CLASS_FK2', 'linkClasses');

--changeset ogl:2079
--comment: DB-2923: quickid permissions
grant insert,update,delete on appid.APP to SVC_CONIFER;

--changeset ogl:2080
--comment: DB-2671: remove unused tables from mapping
delete from mss."#JDO_PROPERTIES" where key like 'CONFIG_ROLLOUT.%';
insert into mss."#JDO_PROPERTIES" (KEY, VALUE)
values ('CONFIG_ROLLOUT.naming', 'none');

delete from mss."#JDO_PROPERTIES" where key like 'CONFIG_DEPLOYMENT.%';
insert into mss."#JDO_PROPERTIES" (KEY, VALUE)
values ('CONFIG_DEPLOYMENT.naming', 'none');

delete from mss."#JDO_PROPERTIES" where key like 'CONFIG_DEPLOYMENT_ERROR.%';
insert into mss."#JDO_PROPERTIES" (KEY, VALUE)
values ('CONFIG_DEPLOYMENT_ERROR.naming', 'none');

--changeset phm:2081
--comment: ORE-8902: allow to remove a service
GRANT SELECT ON MC.SERVICE_CONN_SLA_CONFIG TO SVC_CONIFER;

--changeset ogl:2082
--comment: ORE-8902: service cascade delete availability reports
GRANT SELECT ON MC.AVAILABILITY_REPORT TO SVC_CONIFER;

--changeset mlo:2083
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:1 SELECT COUNT(*) FROM dba_triggers WHERE owner='AUTH' and TRIGGER_NAME='T_LOGIN_SET_AUTHTYPE'
--comment: MC-29960: drop deprecated login triggers
drop trigger AUTH.T_LOGIN_SET_AUTHTYPE;

--changeset mlo:2084
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:1 SELECT COUNT(*) FROM dba_triggers WHERE owner='AUTH' and TRIGGER_NAME='T_LOGIN_SET_DIRTYAUTHHOST'
--comment: MC-29960: drop deprecated login triggers
drop trigger AUTH.T_LOGIN_SET_DIRTYAUTHHOST;

--changeset mlo:2085
--comment: TRIVIAL: add delete grant for INTERFACE_2_PS_LINK_CLASS to DECOMM
GRANT DELETE ON APPID.INTERFACE_2_PS_LINK_CLASS TO DECOMM;

--changeset nop:2086
--comment: SRE-1295: Allw SVC_CONNECTIVITY_COORDINATOR to read hardware type and hardware type ID
GRANT SELECT ON MSS.HARDWARE_TYPE TO SVC_CONNECTIVITY_COORDINATOR;
GRANT SELECT ON MSS.HARDWARE TO SVC_CONNECTIVITY_COORDINATOR;

--changeset ahd:2087
--comment: FW-6652: Remove obsolete fw.log.*.loki dbprops. They are superseded by fw.log.loki.debug.
DELETE FROM mss.value WHERE key_id IN (SELECT id FROM mss.key WHERE name = 'fw.log.debug.loki');
DELETE FROM mss.key WHERE name = 'fw.log.debug.loki';

DELETE FROM mss.value WHERE key_id IN (SELECT id FROM mss.key WHERE name = 'fw.log.input.loki');
DELETE FROM mss.key WHERE name = 'fw.log.input.loki';

--changeset jmu:2088
--comment: TRIVIAL: add country AX to MSS.COUNTRY
INSERT INTO MSS.COUNTRY
(ID, NAME, CODE, CONTINENT_ID, CAPITAL, LARGEST_CITY, INTERNET_TLD, CALLING_CODE, TAXCODE_ID)
VALUES(257, 'Aland Islands', 'AX', 5, 'Mariehamn', '.ax', '+35818', '', NULL);

--changeset ogl:2089
--comment: DB-2671: drop unused tables
drop table mss.CONFIG_DEPLOYMENT;
drop table mss.CONFIG_ROLLOUT;
drop table mss.CONFIG_DEPLOYMENT_USE_CASE;
drop table mss.CONFIG_DEPLOYMENT_ERROR;
drop sequence mss.CONFIG_DEPLOYMENT_SEQ;
drop sequence mss.CONFIG_ROLLOUT_SEQ;


--changeset ngl:2090
--comment: SRE-1308: grant mc-automation user to write to mc audit
GRANT SELECT, INSERT ON MCAUDIT.RECORD TO SVC_AUTOMATION_EXECUTOR;

--changeset ngl:2091
--comment: SRE-1308: grant mc-automation user to select seq on mc audit
GRANT SELECT ON MCAUDIT.RECORD_SEQ TO SVC_AUTOMATION_EXECUTOR;

--changeset ngl:2092
--comment: SRE-1308: grant mc-automation user to execute on mc audit
GRANT EXECUTE ON MCAUDIT.OSAG_AUDIT TO SVC_AUTOMATION_EXECUTOR;

--changeset ogl:2093
--comment: ORE-10275: prevent duplicate dbprops
ALTER TABLE mss.value
  ADD CONSTRAINT uq_value_unique_entry
    UNIQUE (key_id, host_id, service_id, vpn_id, company_id, configuration_group_id);

--changeset mxd:2093
--comment: OSAP-1483: add Identity Management application
INSERT INTO MCAUDIT.APPLICATION (ID, NAME, SHORT, DESCRIPTION) VALUES (18,'Identity Management', 'identity-mgmt' ,'Identity Management Service' )

--changeset ogl:2094
--comment: DB-2863: needed by util.despam_ticket
grant select on mc.ISP_LINK_HISTORY to tt;

--changeset mlo:2096
--comment: MC-30116: grant osag auth passport to MCA
GRANT EXECUTE ON AUTH.OSAG_AUTH_PASSPORT TO MCA;

--changeset mlo:2095
--comment: MC-29960: add generated field for passport logins on user units
INSERT INTO AUTH."#JDO_PROPERTIES" (KEY, VALUE) VALUES ('USER_UNIT.naming.inverse.AUTH.FK_PASSPORT_LOGIN_USER_UNIT_ID', 'passportLogins');

--changeset mlo:2086
--comment: MC-29960: remove FK constraints for deprecated login columns
ALTER TABLE AUTH.LOGIN drop constraint FK_LOGIN_HOMEAUTHHOST_ID;
ALTER TABLE AUTH.LOGIN drop constraint FK_LOGIN_PASSWORDTYPE_ID;
ALTER TABLE AUTH.LOGIN drop constraint FK_LOGIN_REPLACEMENTTOKEN_ID;
ALTER TABLE AUTH.LOGIN drop constraint FK_LOGIN_TOKEN_ID;
ALTER TABLE AUTH.LOGIN drop constraint FK_LOGIN_AUTHTYPE_ID;
ALTER TABLE AUTH.LOGIN drop constraint FK_LOGIN_TOKENREPLSTATE_ID;
ALTER TABLE AUTH.LOGIN drop constraint FK_LOGIN_USER_UNIT_ID;
ALTER TABLE AUTH.LOGIN drop constraint FK_LOGINTYPE_ID;
ALTER TABLE AUTH.LOGIN drop constraint FK_MANAGING_LOGIN_ID;


--changeset mlo:2087
--comment: MC-29960: make deprecated login columns nullable

alter table AUTH.LOGIN
    modify (
        TOKENREPLACEMENTSTATE_ID null,
        ANYTUNNELGROUP null,
        PASSWORDTYPE_ID null,
        TWOFACTORENABLED null,
        AUTHTYPE_ID null);

--changeset mlo:2088
--comment: MC-29960: disable JDO generation for deprecated login columns

DELETE FROM AUTH."#JDO_PROPERTIES" where KEY='LOGIN.naming.TOKEN_ID';
INSERT INTO AUTH."#JDO_PROPERTIES" (KEY, VALUE) values ('LOGIN.naming.TOKEN_ID', 'none');

DELETE FROM AUTH."#JDO_PROPERTIES" where KEY='LOGIN.naming.REPLACEMENTTOKEN_ID';
INSERT INTO AUTH."#JDO_PROPERTIES" (KEY, VALUE) values ('LOGIN.naming.REPLACEMENTTOKEN_ID', 'none');

DELETE FROM AUTH."#JDO_PROPERTIES" where KEY='LOGIN.naming.SMSAUTHNUMBER';
INSERT INTO AUTH."#JDO_PROPERTIES" (KEY, VALUE) values ('LOGIN.naming.SMSAUTHNUMBER','none');

DELETE FROM AUTH."#JDO_PROPERTIES" where KEY='LOGIN.naming.HOMEAUTHHOST_ID';
INSERT INTO AUTH."#JDO_PROPERTIES" (KEY, VALUE) values ('LOGIN.naming.HOMEAUTHHOST_ID','none');

DELETE FROM AUTH."#JDO_PROPERTIES" where KEY='LOGIN.naming.LASTREJECT';
INSERT INTO AUTH."#JDO_PROPERTIES" (KEY, VALUE) values ('LOGIN.naming.LASTREJECT','none');

DELETE FROM AUTH."#JDO_PROPERTIES" where KEY='LOGIN.naming.TOKENREPLACEMENTSTATE_ID';
INSERT INTO AUTH."#JDO_PROPERTIES" (KEY, VALUE) values ('LOGIN.naming.TOKENREPLACEMENTSTATE_ID','none');

DELETE FROM AUTH."#JDO_PROPERTIES" where KEY='LOGIN.naming.PASSWORDEXPIRY';
INSERT INTO AUTH."#JDO_PROPERTIES" (KEY, VALUE) values ('LOGIN.naming.PASSWORDEXPIRY','none');

DELETE FROM AUTH."#JDO_PROPERTIES" where KEY='LOGIN.naming.LASTACCEPT';
INSERT INTO AUTH."#JDO_PROPERTIES" (KEY, VALUE) values ('LOGIN.naming.LASTACCEPT','none');

DELETE FROM AUTH."#JDO_PROPERTIES" where KEY='LOGIN.naming.EMAIL';
INSERT INTO AUTH."#JDO_PROPERTIES" (KEY, VALUE) values ('LOGIN.naming.EMAIL','none');

DELETE FROM AUTH."#JDO_PROPERTIES" where KEY='LOGIN.naming.ANYTUNNELGROUP';
INSERT INTO AUTH."#JDO_PROPERTIES" (KEY, VALUE) values ('LOGIN.naming.ANYTUNNELGROUP','none');

DELETE FROM AUTH."#JDO_PROPERTIES" where KEY='LOGIN.naming.TWOFACTORENABLED';
INSERT INTO AUTH."#JDO_PROPERTIES" (KEY, VALUE) values ('LOGIN.naming.TWOFACTORENABLED','none');

DELETE FROM AUTH."#JDO_PROPERTIES" where KEY='LOGIN.naming.MAXRETRIES';
INSERT INTO AUTH."#JDO_PROPERTIES" (KEY, VALUE) values ('LOGIN.naming.MAXRETRIES','none');

DELETE FROM AUTH."#JDO_PROPERTIES" where KEY='LOGIN.naming.PASSWORDTYPE_ID';
INSERT INTO AUTH."#JDO_PROPERTIES" (KEY, VALUE) values ('LOGIN.naming.PASSWORDTYPE_ID','none');

DELETE FROM AUTH."#JDO_PROPERTIES" where KEY='LOGIN.naming.USER_UNIT_ID';
INSERT INTO AUTH."#JDO_PROPERTIES" (KEY, VALUE) values ('LOGIN.naming.USER_UNIT_ID','none');

DELETE FROM AUTH."#JDO_PROPERTIES" where KEY='LOGIN.naming.LASTTOKENREQUESTDATE';
INSERT INTO AUTH."#JDO_PROPERTIES" (KEY, VALUE) values ('LOGIN.naming.LASTTOKENREQUESTDATE','none');

DELETE FROM AUTH."#JDO_PROPERTIES" where KEY='LOGIN.naming.AUTHTYPE_ID';
INSERT INTO AUTH."#JDO_PROPERTIES" (KEY, VALUE) values ('LOGIN.naming.AUTHTYPE_ID','none');

DELETE FROM AUTH."#JDO_PROPERTIES" where KEY='LOGIN.naming.MANAGING_LOGIN_ID';
INSERT INTO AUTH."#JDO_PROPERTIES" (KEY, VALUE) values ('LOGIN.naming.MANAGING_LOGIN_ID','none');

DELETE FROM AUTH."#JDO_PROPERTIES" where KEY='LOGIN.naming.PWHASH';
INSERT INTO AUTH."#JDO_PROPERTIES" (KEY, VALUE) values ('LOGIN.naming.PWHASH','none');

DELETE FROM AUTH."#JDO_PROPERTIES" where KEY='LOGIN.naming.SALT';
INSERT INTO AUTH."#JDO_PROPERTIES" (KEY, VALUE) values ('LOGIN.naming.SALT','none');

DELETE FROM AUTH."#JDO_PROPERTIES" where KEY='LOGIN.naming.LASTPWCHANGE';
INSERT INTO AUTH."#JDO_PROPERTIES" (KEY, VALUE) values ('LOGIN.naming.LASTPWCHANGE','none');

DELETE FROM AUTH."#JDO_PROPERTIES" where KEY='LOGIN.naming.TMPPWDONLYEXPIRY';
INSERT INTO AUTH."#JDO_PROPERTIES" (KEY, VALUE) values ('LOGIN.naming.TMPPWDONLYEXPIRY','none');

DELETE FROM AUTH."#JDO_PROPERTIES" where KEY='LOGIN.naming.LOGINTYPE_ID';
INSERT INTO AUTH."#JDO_PROPERTIES" (KEY, VALUE) values ('LOGIN.naming.LOGINTYPE_ID','none');

--changeset mcp:2097
--comment: OSIX-6868: set dbprop relmgmt.patch_pull default to 1
update mss.KEY
set string_default='1'
where name='relmgmt.patch_pull';

--changeset fla:2098
--comment: MC-30161: fix job decomm error due to missing grants
GRANT SELECT,UPDATE,DELETE ON TT.ATTACHMENT TO DECOMM;

--changeset ahd:2099
--comment: FW-6741: Clean up bot detection
DELETE FROM mss.value WHERE key_id IN (SELECT id FROM mss.key WHERE name = 'fw.botdetection');
DELETE FROM mss.key WHERE name = 'fw.botdetection';

DELETE FROM mss.value WHERE key_id IN (SELECT id FROM mss.key WHERE name = 'fw.botdetection.block');
DELETE FROM mss.key WHERE name = 'fw.botdetection.block';

--changeset ogl:2100
--comment: DB-2971: relevant FK indexes on APPID schema
create index APPID.IDX_PS_LINK_CLASS_1 on appid.PATH_SELECTION_LINK_CLASS (COMPANY_ID, COLOR_ID);
create index APPID.IDX_APP_COMPANY_1 on appid.APP (COMPANY_ID, TYPE_ID);
create index appid.ID_BANDWIDTH_PROFILE_MEMBER_1 on appid.BANDWIDTH_PROFILE_MEMBER (BANDWIDTH_CONTROL_CLASS_ID);
create index appid.PATH_SELECTION_OVERRIDE_MEMBER_1 on appid.PATH_SELECTION_OVERRIDE_MEMBER(HOST_ID, STICKINESS_ID);
create index appid.WAN_OPTIMIZATION_EXCEPTION_1 on appid.WAN_OPTIMIZATION_EXCEPTION (APP_ID, SERVICE_ID);
create index appid.WAN_OPTIMIZATION_EXCEPTION_2 on appid.WAN_OPTIMIZATION_EXCEPTION (SERVICE_ID, APP_ID);

--changeset lel:2101
--comment: OB-556: Configure GTFO Actors IP blocklist dbprop
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (57112, 'gtfo', 1, '0', '^[01]$', NULL, 'Enables the GTFO Actors IP blocklist');

--changeset ogl:2102
--comment: FK indexes
create index tt.IDX_CHANGE_REQUEST_1 on tt.CHANGE_REQUEST (REQUESTER_ID);
create index tt.IDX_CHANGE_REQUEST_2 on tt.CHANGE_REQUEST (APPROVER_ID);
create index tim.IDX_BLACKLIST_1 on tim.BLACKLIST_VALUE (LAST_MODIFIED_CONTACT_ID);
create index tim.IDX_BLACKLIST_2 on tim.BLACKLIST_VALUE (TICKET_ID);
create index tim.IDX_BLACKLIST_3 on tim.BLACKLIST_VALUE (BLACKLIST_ZONE_FILE_ID);
create index tim.IDX_BLACKLIST_4 on tim.BLACKLIST_VALUE (BLACKLIST_VALUE_CATEGORY_ID);
create index mss.IDX_CONFIG_LV_1 on mss.CONFIG_LIST_VALUE (CONFIG_LIST_ID);
create index mss.IDX_CONFIG_LV_2 on mss.CONFIG_LIST_VALUE (LAST_MODIFIED_CONTACT_ID);
create index fw.IDX_DST_NAT_RULE_1 on fw.DESTINATION_NAT_RULE (LAST_UPDATER_ID);
create index fw.IDX_DST_NAT_RULE_2 on fw.DESTINATION_NAT_RULE (NAT_SECTION_ID);
create index fw.IDX_DST_NAT_RULE_3 on fw.DESTINATION_NAT_RULE (ORIG_SRC_GROUP_ID);
create index fw.IDX_DST_NAT_RULE_4 on fw.DESTINATION_NAT_RULE (ORIG_DST_GROUP_ID);
create index fw.IDX_DST_NAT_RULE_5 on fw.DESTINATION_NAT_RULE (ORIG_SERVICE_GROUP_ID);
create index fw.IDX_DST_NAT_RULE_6 on fw.DESTINATION_NAT_RULE (NAT_ACTION_ID);
create index fw.IDX_DST_NAT_RULE_7 on fw.DESTINATION_NAT_RULE (TRANS_DST_GROUP_ID);
create index fw.IDX_DST_NAT_RULE_8 on fw.DESTINATION_NAT_RULE (TRANS_SERVICE_GROUP_ID);
create index fw.IDX_DST_NAT_RULE_9 on fw.DESTINATION_NAT_RULE (LOG_TARGET_ID);
create index tim.IDX_EXCLUSION_LV_1 on tim.EXCLUSION_LIST_VALUE (LAST_MODIFIED_CONTACT_ID);
create index tim.IDX_EXCLUSION_LV_2 on tim.EXCLUSION_LIST_VALUE (COMPANY_ID);
create index tim.IDX_EXCLUSION_LV_3 on tim.EXCLUSION_LIST_VALUE (TICKET_ID);
create index mss.IDX_HW_LCI_1 on mss.HARDWARE_LIFECYCLE_ITEM(CREATOR);
create index mss.IDX_HW_LCI_2 on mss.HARDWARE_LIFECYCLE_ITEM(HARDWARE_ID);
create index mss.IDX_HW_LCI_3 on mss.HARDWARE_LIFECYCLE_ITEM(HARDWARE_LC_STATE_ID);
create index mss.IDX_HW_LCI_4 on mss.HARDWARE_LIFECYCLE_ITEM(HARDWARE_LC_LOCATION_ID);
create index mss.IDX_HW_LCI_5 on mss.HARDWARE_LIFECYCLE_ITEM(HARDWARE_LC_TRANSIT_STATE_ID);
create index mss.IDX_HW_LCI_6 on mss.HARDWARE_LIFECYCLE_ITEM(HARDWARE_LC_TRANSIT_INFO_ID);
create index mss.IDX_INSTPRJI_1 on mss.INSTALLATION_PROJECT_ITEM(ORDER_CONTACT_ID);
create index mss.IDX_INSTPRJI_2 on mss.INSTALLATION_PROJECT_ITEM(APPROVAL_CONTACT_ID);
create index nids.IDX_INVESTIGATION_1 on nids.INVESTIGATION(CONTACT_ID);
create index nids.IDX_INVESTIGATION_2 on nids.INVESTIGATION(INVESTIGATION_STATUS_ID);
create index nids.IDX_INVESTIGATION_3 on nids.INVESTIGATION(INVESTIGATION_FINDING_ID);
create index nids.IDX_INVESTIGATION_4 on nids.INVESTIGATION(COMPANY_ID);
create index nids.IDX_INVESTIGATION_5 on nids.INVESTIGATION(ENTITY_TYPE_ID);
create index nids.IDX_INVESTIGATIONE_1 on nids.INVESTIGATION_ENTRY(CONTACT_ID);
create index nids.IDX_INVESTIGATIONE_2 on nids.INVESTIGATION_ENTRY(INVESTIGATION_ID);
create index mail.IDX_POLLV_1 on mail.POLICY_LIST_VALUE(LAST_MODIFIED_CONTACT_ID);
create index mail.IDX_POLLV_2 on mail.POLICY_LIST_VALUE(COMPANY_ID);
create index mail.IDX_POLLV_3 on mail.POLICY_LIST_VALUE(POLICY_LIST_TYPE_ID);
create index mail.IDX_POLLV_4 on mail.POLICY_LIST_VALUE(POLICY_LIST_VALUE_TYPE_ID);
create index prx.IDX_POLICY_ITEM_1 on prx.PRX_POLICY_ITEM(LAST_MODIFIED_CONTACT_ID);
create index prx.IDX_POLICY_ITEM_2 on prx.PRX_POLICY_ITEM(COMPANY_ID);
create index prx.IDX_POLICY_ITEM_3 on prx.PRX_POLICY_ITEM(TICKET_ID);
create index prx.IDX_POLICY_ITEM_4 on prx.PRX_POLICY_ITEM(PRX_POLICY_ITEM_TYPE_ID);
create index prx.IDX_POLICY_ITEM_5 on prx.PRX_POLICY_ITEM(PRX_POLICY_TYPE_ID);
create index fw.IDX_RECENT_POLICY_1 on fw.RECENT_POLICY(CONTACT_ID);
create index fw.IDX_RECENT_POLICY_2 on fw.RECENT_POLICY(POLICY_ID);
create index fw.IDX_RECENT_POLICY_3 on fw.RECENT_POLICY(SERVICE_ID);
create index mss.IDX_REPORT_1 on mss.REPORT(CONTACT_ID);
create index mss.IDX_REPORT_2 on mss.REPORT(REPORT_TYPE_ID);
create index mss.IDX_REPORT_3 on mss.REPORT(REPORT_SCHEDULE_ID);
create index mss.IDX_REPORT_4 on mss.REPORT(COMPANY_ID);
create index mss.IDX_REPORT_5 on mss.REPORT(REPORT_STATE_ID);
create index fw.IDX_RULE_1 on fw.RULE(LAST_UPDATER_ID);
create index fw.IDX_RULE_2 on fw.RULE(SUB_SECTION_ID);
create index fw.IDX_RULE_3 on fw.RULE(SRC_IP_GROUP_ID);
create index fw.IDX_RULE_4 on fw.RULE(DST_IP_GROUP_ID);
create index fw.IDX_RULE_5 on fw.RULE(SERVICE_GROUP_ID);
create index fw.IDX_RULE_6 on fw.RULE(ACTION_ID);
create index fw.IDX_RULE_7 on fw.RULE(LOG_TARGET_ID);
create index fw.IDX_RULE_8 on fw.RULE(APP_GROUP_ID);
create index fw.IDX_SRC_NAT_RULE_2 on fw.SOURCE_NAT_RULE(NAT_SECTION_ID);
create index fw.IDX_SRC_NAT_RULE_3 on fw.SOURCE_NAT_RULE(ORIG_SRC_GROUP_ID);
create index fw.IDX_SRC_NAT_RULE_4 on fw.SOURCE_NAT_RULE(ORIG_DST_GROUP_ID);
create index fw.IDX_SRC_NAT_RULE_5 on fw.SOURCE_NAT_RULE(ORIG_SERVICE_GROUP_ID);
create index fw.IDX_SRC_NAT_RULE_6 on fw.SOURCE_NAT_RULE(NAT_ACTION_ID);
create index fw.IDX_SRC_NAT_RULE_7 on fw.SOURCE_NAT_RULE(TRANS_SRC_GROUP_ID);
create index fw.IDX_SRC_NAT_RULE_8 on fw.SOURCE_NAT_RULE(LOG_TARGET_ID);

--changeset igs:2103
--comment: ZTNA-1648: remove unused tables from mapping
UPDATE MSS.key k SET k.REGEXP='^(eth|lacp)([1-9]?[0-9](\.[1-9][0-9]{0,3})?(:[0-9]+)?)?(| (eth|lacp)([1-9]?[0-9](\.[1-9][0-9]{0,3})?(:[0-9]+)?)?)*$' WHERE k.id=24503 and k.name='ztna.onprem.interfaces';
INSERT INTO MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
VALUES (57113, 'ztna.onprem.clients', 4, NULL, '^(?:(?:@if_LOCAL_(?:INT|EXT|ALL))|(?:eth|lacp)[1-9]?[0-9](?:\.[1-9][0-9]{0,3})?)(?: (?:(?:@if_LOCAL_(?:INT|EXT|ALL))|(eth|lacp)[1-9]?[0-9](\.[1-9][0-9]{0,3})?))*$', NULL, 'When using a ZTNA on-prem edge, only traffic from these internal and external interfaces will be allowed to access the on-prem edge.');

--changeset phm:2104
--comment: TRIVIAL: allow config api to access mss.key_type
GRANT SELECT ON MSS.KEY_TYPE TO SVC_CONIFER;

--changeset dnb:2105
--comment MX-6218: Add component and for mail-addrsync in mc-config-api
DELETE FROM MCAUDIT.RECORD_TYPE where ID = 468 AND name = 'Address added';
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID)
VALUES (468, 'Email address added', 'mail_addrsync_add', 'An email address was added to a list',1);
DELETE FROM MCAUDIT.RECORD_TYPE where ID = 469 AND name = 'Address removed';
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID)
VALUES (469, 'Email address removed', 'mail_addrsync_remove', 'An email address was removed from a list',1);


--changeset mlo:2106
--comment MC-30088: Make passport temp access keys cascade on delete

alter table AUTH.PASSPORT_TEMP_ACCESS_KEY
    drop constraint FK_PASSPORT_TEMP_ACCESS_KEY_PASSPORT_LOGIN_ID;

alter table AUTH.PASSPORT_TEMP_ACCESS_KEY
    add constraint FK_PASSPORT_TEMP_ACCESS_KEY_PASSPORT_LOGIN_ID
        foreign key (LOGIN_ID) references AUTH.PASSPORT_LOGIN
            on delete cascade
            deferrable;

alter table AUTH.PASSPORT_TEMP_ACCESS_KEY
    drop constraint FK_PASSPORT_TEMP_ACCESS_KEY_TOKEN_ID;

alter table AUTH.PASSPORT_TEMP_ACCESS_KEY
    add constraint FK_PASSPORT_TEMP_ACCESS_KEY_TOKEN_ID
        foreign key (TOKEN_ID) references AUTH.TOKEN
            on delete cascade
            deferrable;

--changeset mlo:2099
--comment: MC-29960: drop constraints on deprecated columns

ALTER TABLE AUTH.LOGIN drop constraint U_CONST_LOGIN_LOWER_LOGIN_HOMEAUTHHOST;
DROP INDEX AUTH.IDX_LOGIN_TYPE_ID;
DROP INDEX AUTH.IDX_LOGIN_MANAGED_LOGIN_ID;
DROP INDEX AUTH.U_LOGIN_TOKEN_ID;
DROP INDEX AUTH.U_LOGIN_REPLACEMENTTOKEN_ID;
DROP INDEX AUTH.U_LOGIN_EMAIL;
DROP INDEX AUTH.U_IDX_LOGIN_LOWER_LOGIN_HOMEAUTHHOST;



--changeset mlo:2100 endDelimiter:/
--comment: MC-29960: Adapt AUTH views referencing deprecated columns

create or replace force view AUTH.V_S_LOGIN as
SELECT login.id as id,
       login,
       c.EMAIL as email,
       contact_id,
       enabled,
       locked,
       login.company_id as company_id,
       login.modified as modified,
       creationdate
FROM auth.login login, stop.contact c
WHERE login.contact_id = c.id
WITH READ ONLY
/

create or replace force view AUTH.V_LOGIN as
SELECT l.id, l.login, l.contact_id, l.locked,
       c.firstname contact_firstname, c.lastname contact_lastname, c.email contact_email,
       c.company_id contact_company_id, c.fax contact_fax, c.direct contact_direct, c.mobile contact_mobile,
       c.home contact_home
FROM auth.login l, stop.contact c
WHERE l.contact_id = c.id
WITH READ ONLY
/

--changeset mlo:2101
--comment: MC-29960: grant to auth.login for bireader
GRANT SELECT ON AUTH.LOGIN to BIREADER;

--changeset mlo:2102 endDelimiter:/
--comment: MC-29960: Adapt BIREADER views referencing deprecated columns
create or replace force view BIREADER.V_AUTH_V_S_LOGIN as
SELECT ID, LOGIN, CONTACT_ID FROM AUTH.LOGIN
/

--changeset mlo:2103
--comment: MC-29960: drop deprecated login columns
ALTER TABLE AUTH.LOGIN
    drop (
          TOKEN_ID,
          REPLACEMENTTOKEN_ID,
          SMSAUTHNUMBER,
          HOMEAUTHHOST_ID,
          LASTREJECT,
          TOKENREPLACEMENTSTATE_ID,
          PASSWORDEXPIRY,
          LASTACCEPT,
          EMAIL,
          ANYTUNNELGROUP,
          TWOFACTORENABLED,
          MAXRETRIES,
          PASSWORDTYPE_ID,
          USER_UNIT_ID,
          LASTTOKENREQUESTDATE,
          AUTHTYPE_ID,
          MANAGING_LOGIN_ID,
          PWHASH,
          SALT,
          LASTPWCHANGE,
          TMPPWDONLYEXPIRY,
          LOGINTYPE_ID
        );

--changeset mlo:2105 endDelimiter:/
--comment: MC-29960: adapt auth.v_s_login view

create or replace force view AUTH.V_S_LOGIN as
SELECT login.id as id,
       login,
       null as email,
       contact_id,
       enabled,
       locked,
       login.company_id as company_id,
       login.modified as modified,
       creationdate
FROM auth.login login
WITH READ ONLY
/

--changeset gpe:2106
--comment: FW-6694: add new dbprop fw.appid.pace2
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (57114, 'fw.appid.pace2', 1, '0', '^[01]$', NULL, 'Enable pace2 DPI engine');

--changeset sst:2107
--comment: IE-77: create sequence localcontact notification sequence and grant permissions to svc_conifer
CREATE SEQUENCE MSS.LOCAL_CONTACT_NOTIFICATION_SEQ;
GRANT SELECT ON MSS.LOCAL_CONTACT_NOTIFICATION_SEQ TO SVC_CONIFER;

--changeset sst:2108
--comment: IE-77: grant insert permission on mss.local_contact_notification table
GRANT INSERT ON MSS.LOCAL_CONTACT_NOTIFICATION TO SVC_CONIFER;


--changeset mlo:2109
--comment: MC-29960: fix AUTH.LOGIN RLS predicates

DELETE RLSDEF.PREDICATE where SCHEMA_NAME = 'AUTH' AND TABLE_NAME = 'LOGIN' AND ROLE_ID = 12 AND AREA_ID = 2;
UPDATE RLSDEF.PREDICATE SET PREDICATE = 'EXISTS (SELECT perm.COMPANY_ID FROM auth.PERMISSION perm WHERE perm.login_id = sys_context(''web'', ''current_login_id'') AND perm.company_id = sys_context(''web'', ''current_company_id'') AND perm.COMPANY_ID = login.company_id AND perm.role_id = 22) OR contact_id = sys_context(''web'', ''current_contact_id'')', EXTENDED_PREDICATE = 'company_id = sys_context(''web'', ''current_company_id'') OR contact_id = sys_context(''web'', ''current_contact_id'')' where SCHEMA_NAME = 'AUTH' AND TABLE_NAME = 'LOGIN' AND  ROLE_ID = 22 AND PRIORITY = 2 AND READ_WRITE = 1 AND AREA_ID = 2;
UPDATE RLSDEF.PREDICATE SET PREDICATE = 'EXISTS (SELECT perm.COMPANY_ID FROM auth.PERMISSION perm WHERE perm.login_id = sys_context(''web'', ''current_login_id'') AND perm.company_id = sys_context(''web'', ''current_company_id'') AND perm.COMPANY_ID = auth.login.company_id AND perm.role_id = 22) OR contact_id = sys_context(''web'', ''current_contact_id'')', EXTENDED_PREDICATE = 'EXISTS (SELECT perm.COMPANY_ID FROM auth.PERMISSION perm WHERE perm.login_id = sys_context(''web'', ''current_login_id'') AND perm.company_id = sys_context(''web'', ''current_company_id'') AND perm.COMPANY_ID = auth.login.COMPANY_ID AND perm.role_id = 22) OR id = sys_context(''web'', ''current_login_id'')' where SCHEMA_NAME = 'AUTH' AND TABLE_NAME = 'LOGIN' AND  ROLE_ID = 22 AND PRIORITY = 2 AND READ_WRITE = 2 AND AREA_ID = 2;

--changeset thw:2110
--comment: SRE-1245: allow mc-automation to query SLA classes and config
GRANT SELECT ON MC.SERVICE_CONN_SLA_CONFIG TO SVC_AUTOMATION_EXECUTOR;
GRANT SELECT ON MC.CONN_SLA_CLASS TO SVC_AUTOMATION_EXECUTOR;

--changeset jdv:2111
--comment: FW-6674: Add new DB Prop t2ee.exclude_interfaces
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (57115, 't2ee.exclude_interfaces', 4, NULL, '^.*$', 22, 'Traffic from specified interfaces is excluded from being routed through a T2EE tunnel. The interfaces should be provided as a space separated list. Optionally networks can be provided. The network is used to match the source address. It is possible to specify multiple networks separated by a comma. Example: "eth0 eth1:192.168.2.0/24,2001::/64 eth1:10.10.0.0/16" bypasses t2ee for traffic from eth0 (both ipv4 and ipv6) and from eth1 if the the packet is coming from one of the three given networks.');

--changeset gta:2112
--comment: RTNG-1011: add dbprop to enable/disable rip
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (57116, 'ripd', 1, '0', '^[01]$', NULL, 'Enable/disable RIP protocol');

--changeset tte:2113
--comment: Fix AUTH.AUTHHOST RLS predicates
UPDATE RLSDEF.PREDICATE SET PREDICATE = 'EXISTS (SELECT h.id FROM mss.host h WHERE h.id = auth.authhost.host_id)' where SCHEMA_NAME = 'AUTH' AND TABLE_NAME = 'AUTHHOST' AND  ROLE_ID = 1 AND PRIORITY = 2 AND READ_WRITE = 1 AND AREA_ID = 1;
DELETE RLSDEF.PREDICATE where SCHEMA_NAME = 'AUTH' AND TABLE_NAME = 'AUTHHOST' AND  ROLE_ID = 3 AND PRIORITY = 3 AND READ_WRITE = 1 AND AREA_ID = 1;
DELETE RLSDEF.PREDICATE where SCHEMA_NAME = 'AUTH' AND TABLE_NAME = 'AUTHHOST' AND  ROLE_ID = 3 AND PRIORITY = 3 AND READ_WRITE = 1 AND AREA_ID = 2;

--changeset jkl:2114
--comment: RTNG-1007: Grant privileges for routing peering queries
GRANT SELECT ON MSS.V_NONFAKE_INTERFACE TO SVC_CONIFER;
GRANT EXECUTE ON VPN.OSAG_VPN TO SVC_CONIFER;

--changeset gta:2115
--comment: RTNG-1011: add dbprop to enable/disable RIP for IPv6
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (57117, 'ripngd', 1, '0', '^[01]$', NULL, 'Enable/disable RIP protocol for IPv6');

--changeset alg:2116
--comment: DB-2984: Fix 2 MCDB_CHECKs after AUTH overhaul
UPDATE MCDB_CHECKS.CONSISTENCY_CHECKS SET CHECK_KEY = 'SEL_um_alien_user_unit', CHECK_GROUP = 'default', STATEMENT = 'SELECT l.id AS login_id, l.contact_id, l.company_id AS login_company_id, c1.name AS login_company, c.id AS contact_id, c.email, l.login, u.id AS user_unit_id, u.company_id AS user_unit_company_id, c2.name AS user_unit_company
            FROM auth.passport_login l, stop.contact c, auth.user_unit u, stop.company c1, stop.company c2
            WHERE u.id = l.user_unit_id AND c.id = l.contact_id AND c1.id = l.company_id AND c2.id = u.company_id AND l.company_id <> u.company_id
            ORDER BY login_company_id' WHERE ID = 15;
/* Removed the dropped eMail column from the output of AUTH.LOGIN */
UPDATE MCDB_CHECKS.CONSISTENCY_CHECKS SET CHECK_KEY = 'SEL_perm_orphan', CHECK_GROUP = 'default', STATEMENT = 'SELECT p.ID AS permission_id, ur.name, l.login, l.EMAIL
FROM AUTH.USER_PERMISSION p
         LEFT JOIN AUTH.USER_COMPANY_SCOPE cs ON p.id = cs.PERMISSION_ID
         LEFT JOIN AUTH.USER_COMPANY_UNIT_SCOPE cus ON p.id = cus.PERMISSION_ID
         LEFT JOIN AUTH.USER_SERVICE_TYPE_SCOPE sts ON p.id = sts.PERMISSION_ID
         LEFT JOIN AUTH.USER_SERVICE_SCOPE ss ON p.id = ss.PERMISSION_ID
         LEFT JOIN AUTH.USER_UNIT_SCOPE uus ON p.id = uus.PERMISSION_ID
         JOIN auth.user_role ur ON p.USER_ROLE_ID = ur.id
         JOIN auth.login2profile l2p ON l2p.PROFILE_ID = p.PROFILE_ID
         JOIN auth.PASSPORT_LOGIN l ON l2p.LOGIN_ID = l.id
WHERE p.USER_ROLE_ID >= 1000
  AND cs.COMPANY_ID IS NULL
  AND cus.COMPANY_UNIT_ID IS NULL
  AND sts.SERVICE_TYPE_ID IS NULL
  AND ss.SERVICE_ID IS NULL
  AND uus.USER_UNIT_ID IS NULL
UNION ALL
SELECT p.ID AS permission_id, ur.name, l.login, ''''
FROM AUTH.USER_PERMISSION p
         LEFT JOIN AUTH.USER_COMPANY_SCOPE cs ON p.id = cs.PERMISSION_ID
         LEFT JOIN AUTH.USER_COMPANY_UNIT_SCOPE cus ON p.id = cus.PERMISSION_ID
         LEFT JOIN AUTH.USER_SERVICE_TYPE_SCOPE sts ON p.id = sts.PERMISSION_ID
         LEFT JOIN AUTH.USER_SERVICE_SCOPE ss ON p.id = ss.PERMISSION_ID
         LEFT JOIN AUTH.USER_UNIT_SCOPE uus ON p.id = uus.PERMISSION_ID
         JOIN auth.user_role ur ON p.USER_ROLE_ID = ur.id
         JOIN auth.login2profile l2p ON l2p.PROFILE_ID = p.PROFILE_ID
         JOIN auth.LOGIN l ON l2p.LOGIN_ID = l.id
WHERE p.USER_ROLE_ID >= 1000
  AND cs.COMPANY_ID IS NULL
  AND cus.COMPANY_UNIT_ID IS NULL
  AND sts.SERVICE_TYPE_ID IS NULL
  AND ss.SERVICE_ID IS NULL
  AND uus.USER_UNIT_ID IS NULL;' WHERE ID = 63;

--changeset rse:2117
--comment: TRIVIAL: add dbprops to enable/disable RabbitMQ server scraping
INSERT INTO MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
VALUES (57120, 'mgmtserver.balu_broker.scrape',         1, '0', '^[01]$', NULL, 'Enable/disable scraping of RabbitMQ server metrics');
INSERT INTO MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
VALUES (57121, 'mgmtserver.balu_broker.scrape.details', 1, '0', '^[01]$', NULL, 'Enable/disable scraping of very detailed RabbitMQ server metrics');

--changeset alg:2200 tag:v2.1.0
--comment: This initial changeset servers as export marker for SCN 618640767735
SELECT 1 FROM DUAL;

--changeset doi:2201
--comment: PRX-8460: Delete outdated casb db props (squid.casb.discovery, squid.casb.netskope.action.steer, squid.casb.netskope.tenant, squid.casb.mscas.action.blockunsanctioned)
DELETE FROM MSS.VALUE WHERE KEY_ID IN (6905,6906,6907,6908);
DELETE FROM MSS.KEY WHERE ID = 6905;
DELETE FROM MSS.KEY WHERE ID = 6906;
DELETE FROM MSS.KEY WHERE ID = 6907;
DELETE FROM MSS.KEY WHERE ID = 6908;

--changeset alg:2202
--comment: NOTICKET, fix DB-2984: Fix 2 MCDB_CHECKs after AUTH overhaul. A semicolon too much for once
UPDATE MCDB_CHECKS.CONSISTENCY_CHECKS t SET t.STATEMENT = 'SELECT p.ID AS permission_id, ur.name, l.login, l.EMAIL
                                   FROM AUTH.USER_PERMISSION p
                                            LEFT JOIN AUTH.USER_COMPANY_SCOPE cs ON p.id = cs.PERMISSION_ID
                                            LEFT JOIN AUTH.USER_COMPANY_UNIT_SCOPE cus ON p.id = cus.PERMISSION_ID
                                            LEFT JOIN AUTH.USER_SERVICE_TYPE_SCOPE sts ON p.id = sts.PERMISSION_ID
                                            LEFT JOIN AUTH.USER_SERVICE_SCOPE ss ON p.id = ss.PERMISSION_ID
                                            LEFT JOIN AUTH.USER_UNIT_SCOPE uus ON p.id = uus.PERMISSION_ID
                                            JOIN auth.user_role ur ON p.USER_ROLE_ID = ur.id
                                            JOIN auth.login2profile l2p ON l2p.PROFILE_ID = p.PROFILE_ID
                                            JOIN auth.PASSPORT_LOGIN l ON l2p.LOGIN_ID = l.id
                                   WHERE p.USER_ROLE_ID >= 1000
                                     AND cs.COMPANY_ID IS NULL
                                     AND cus.COMPANY_UNIT_ID IS NULL
                                     AND sts.SERVICE_TYPE_ID IS NULL
                                     AND ss.SERVICE_ID IS NULL
                                     AND uus.USER_UNIT_ID IS NULL
                                   UNION ALL
                                   SELECT p.ID AS permission_id, ur.name, l.login, ''''
                                   FROM AUTH.USER_PERMISSION p
                                            LEFT JOIN AUTH.USER_COMPANY_SCOPE cs ON p.id = cs.PERMISSION_ID
                                            LEFT JOIN AUTH.USER_COMPANY_UNIT_SCOPE cus ON p.id = cus.PERMISSION_ID
                                            LEFT JOIN AUTH.USER_SERVICE_TYPE_SCOPE sts ON p.id = sts.PERMISSION_ID
                                            LEFT JOIN AUTH.USER_SERVICE_SCOPE ss ON p.id = ss.PERMISSION_ID
                                            LEFT JOIN AUTH.USER_UNIT_SCOPE uus ON p.id = uus.PERMISSION_ID
                                            JOIN auth.user_role ur ON p.USER_ROLE_ID = ur.id
                                            JOIN auth.login2profile l2p ON l2p.PROFILE_ID = p.PROFILE_ID
                                            JOIN auth.LOGIN l ON l2p.LOGIN_ID = l.id
                                   WHERE p.USER_ROLE_ID >= 1000
                                     AND cs.COMPANY_ID IS NULL
                                     AND cus.COMPANY_UNIT_ID IS NULL
                                     AND sts.SERVICE_TYPE_ID IS NULL
                                     AND ss.SERVICE_ID IS NULL
                                     AND uus.USER_UNIT_ID IS NULL' WHERE t.ID = 63;

--changeset ogl:2203
--comment: UAI missing perms
grant insert,update,delete on APPID.QUICKID_DNS to SVC_CONIFER;
grant insert,update,delete on APPID.QUICKID_NET4 to SVC_CONIFER;
grant insert,update,delete on APPID.QUICKID_NET6 to SVC_CONIFER;
grant insert,update,delete on APPID.QUICKID_PROTO to SVC_CONIFER;
grant insert,update,delete on APPID.QUICKID_TOS to SVC_CONIFER;

--changeset jkl:2204
--comment: RTNG-917: Remove DB Prop ospfd.redist.connected_as_stub
DELETE FROM MSS.VALUE WHERE key_id IN (SELECT id FROM MSS.KEY WHERE name='ospfd.redist.connected_as_stub');
DELETE FROM MSS.KEY WHERE name='ospfd.redist.connected_as_stub';

--changeset jkl:2205
--comment: RTNG-782: Add dbprop to enable the wan peering exporter
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (57122, 'wan.prometheus-exporter', 1, '0', '^[01]$', NULL, 'Enable WAN peering exporter');

--changeset ogl:2206 tag:v2.1.1
--comment: Base of new container
SELECT 1 FROM DUAL;

--changeset igs:2207
--comment: ZTNA-1834: update macros for ztna.onprem.interfaces and ztna.onprem.clients
UPDATE MSS.key k SET k.REGEXP='^(@if_LOCAL_(INTVIRT|EXTVIRT|ALLVIRT)|(eth|lacp)[1-9]?[0-9](\.[1-9][0-9]{0,3})?:[0-9]+)( (@if_LOCAL_(INTVIRT|EXTVIRT|ALLVIRT)|(eth|lacp)[1-9]?[0-9](\.[1-9][0-9]{0,3})?:[0-9]+))*$' WHERE k.id=24503 and k.name='ztna.onprem.interfaces';
UPDATE MSS.key k SET k.REGEXP='^(@if_LOCAL_(INTPHYS|EXTPHYS|ALLPHYS)|(eth|lacp)[1-9]?[0-9](\.[1-9][0-9]{0,3})?)( (@if_LOCAL_(INTPHYS|EXTPHYS|ALLPHYS)|(eth|lacp)[1-9]?[0-9](\.[1-9][0-9]{0,3})?))*$' WHERE k.id=57113 and k.name='ztna.onprem.clients';

--changeset sev:2208
--comment: MEP-2597: Set sslvpn.asav.version to new current version 9.18.4_66
update mss.KEY set STRING_DEFAULT='9.18.4_66' where NAME='sslvpn.asav.version';

--changeset phh:2117
--comment: FW-6694: Add categories and apps for pace2
ALTER TABLE APPID.APP MODIFY NAME VARCHAR2(64);
INSERT INTO APPID.APP_TYPE (ID, NAME) VALUES(3, 'Pace2');

INSERT INTO APPID.APP_CATEGORY (ID, NAME) VALUES (2056, 'Streaming');
INSERT INTO APPID.APP_CATEGORY (ID, NAME) VALUES (2085, 'Enterprise Services');
INSERT INTO APPID.APP_CATEGORY (ID, NAME) VALUES (2060, 'Network Management');
INSERT INTO APPID.APP_CATEGORY (ID, NAME) VALUES (2070, 'Advertisement and Analytic Services');
INSERT INTO APPID.APP_CATEGORY (ID, NAME) VALUES (2079, 'Audio Entertainment');
INSERT INTO APPID.APP_CATEGORY (ID, NAME) VALUES (2072, 'Health and Fitness');
INSERT INTO APPID.APP_CATEGORY (ID, NAME) VALUES (2083, 'Multimedia Service Providers');
INSERT INTO APPID.APP_CATEGORY (ID, NAME) VALUES (2084, 'Organizers');
INSERT INTO APPID.APP_CATEGORY (ID, NAME) VALUES (2062, 'Filetransfer');
INSERT INTO APPID.APP_CATEGORY (ID, NAME) VALUES (2078, 'Books and Magazines');
INSERT INTO APPID.APP_CATEGORY (ID, NAME) VALUES (2093, 'Smart Home');
INSERT INTO APPID.APP_CATEGORY (ID, NAME) VALUES (2087, 'Browsers');
INSERT INTO APPID.APP_CATEGORY (ID, NAME) VALUES (2090, 'Wallet');
INSERT INTO APPID.APP_CATEGORY (ID, NAME) VALUES (2096, 'Food and Drink');
INSERT INTO APPID.APP_CATEGORY (ID, NAME) VALUES (2081, 'M2M and IoT');
INSERT INTO APPID.APP_CATEGORY (ID, NAME) VALUES (2092, 'Virtual and Augmented Reality');
INSERT INTO APPID.APP_CATEGORY (ID, NAME) VALUES (2048, 'Generic');
INSERT INTO APPID.APP_CATEGORY (ID, NAME) VALUES (2068, 'Industrial');
INSERT INTO APPID.APP_CATEGORY (ID, NAME) VALUES (2069, 'Encrypted');

--changeset jkl:2209
--comment: RTNG-1007: Add MC Audit record types for WAN Peering Alert Configuration
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID)
VALUES (470, 'WAN peering alert configuration created', 'wan_peering_alert_configuration_created', 'A WAN peering alert configuration has been created', 1);

INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID)
VALUES (471, 'WAN peering alert configuration modified', 'wan_peering_alert_configuration_modified', 'A WAN peering alert configuration has been modified', 1);

INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID)
VALUES (472, 'WAN peering alert configuration deleted', 'wan_peering_alert_configuration_deleted', 'A WAN peering alert configuration has been deleted', 1);

--changeset gta:2210
--comment: RTNG-1064: make path_override_member_link.interface_id nullable
ALTER TABLE appid.PATH_OVERRIDE_MEMBER_LINK MODIFY INTERFACE_ID NULL;
ALTER TABLE appid.PATH_OVERRIDE_MEMBER_LINK
    ADD CONSTRAINT PATH_OVERRIDE_MEMBER_LINK_CHK1
    CHECK (
        INTERFACE_ID IS NOT NULL OR LINK_CLASS_ID IS NOT NULL
    );

--changeset mlo:2211
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:1 SELECT count(*) from SYS.ALL_CONSTRAINTS where CONSTRAINT_NAME='U_PATH_OVERRIDE_MEMBER_LINK'
--comment: RTNG-1064: adapt index to include link_class_id
alter table APPID.PATH_OVERRIDE_MEMBER_LINK
    drop constraint U_PATH_OVERRIDE_MEMBER_LINK;
drop index appid.U_PATH_OVERRIDE_MEMBER_LINK;

--changeset mlo:2212
--comment: RTNG-1064: adapt index to include link_class_id
alter table APPID.PATH_OVERRIDE_MEMBER_LINK
    add constraint U_PATH_OVERRIDE_MEMBER_LINK
        unique (MEMBER_ID, INTERFACE_ID, LINK_CLASS_ID)
            deferrable;

--changeset ogl:2213
--comment: MC-30233: remove unnecessary trigger
drop trigger APPID.t_ps_link_class;

--changeset ogl:2214
--comment: ORE-11542: remove VWAN
drop sequence VPN.AZURE_VWAN_SITE_SEQUENCE;
drop sequence VPN.AZURE_VWAN_TUNNEL_SEQUENCE;
drop table vpn.AZURE_VWAN_TUNNEL;
drop table vpn.AZURE_VWAN_SITE;
drop user AZURE_VWAN;
delete from vpn."#JDO_PROPERTIES" where key like 'AZURE_VWAN_%';
delete from mss."#JDO_PROPERTIES" where key like '%VPN.AZURE_VWAN_%';

--changeset gta:2215
--comment: RTNG-1069: set default for ipsec_internal_fragmentation to 1
ALTER TABLE MSS.ISP_LINK MODIFY IPSEC_INTERNAL_FRAGMENTATION default on null 1;

--changeset yuy:2216
--comment: IDS-3416: Add new DB Prop ndr.zeek.interfaces
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (57123, 'ndr.zeek.interfaces', 4, NULL, '^[A-Za-z0-9.:]+(?: [A-Za-z0-9.:]+)*$', NULL, 'Make zeek interfaces configurable');

--changeset nop:2217
--comment: SRE-1413: Add new audit component for interface edition
INSERT INTO MCAUDIT.COMPONENT (ID,NAME,SHORT,DESCRIPTION,SYSTEM_ID)
	VALUES (82,'Interface Editor','interface_editor','Interface editor',1);

--changeset doi:2218
--comment: PRX-9405: add casb audit component
INSERT INTO MCAUDIT.COMPONENT (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID)
VALUES (83, 'CASB Self-Service', 'casb', 'CASB Configuration', 1);

--changeset quv:2219
--comment: SRE-1414: new mutation for creating isplink
GRANT SELECT ON mss.ISPLINK_SEQ to SVC_CONIFER;

--changeset alg:2220 tag:v2.0.1
--comment: base for container v2.1.2
SELECT 1 FROM DUAL;

--changeset del:2221
--comment: OSCI-759: Rename DB Prop pacemaker.http-health.clientnetworks and update regex
update MSS.KEY set REGEXP='/^(?:((25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]?|0)\.){3}(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]?|0)(\/([0-9]|[1-2][0-9]|3[0-2]))?)(?:\s+((25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]?|0)\.){3}(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]?|0)(\/([0-9]|[1-2][0-9]|3[0-2]))?)*$/' where name = 'pacemaker.http-health.allowed-client-networks';

update mss.key k
set k.NAME='pacemaker.http-health.clientnetworks'
where k.id=57052
and k.name='pacemaker.http-health.allowed-client-networks';

--changeset quv:2221
--comment: SRE-1414: new mutation for creating isplink
GRANT INSERT ON mss.ISP_LINK to SVC_CONIFER;

--changeset gta:2222
--comment: RTNG-882: populate APPID.INTERFACE_2_PS_LINK_CLASS. Assumes the table is empty.
INSERT INTO APPID.INTERFACE_2_PS_LINK_CLASS (INTERFACE_ID, LINK_CLASS_ID)
SELECT
    i.ID AS INTERFACE_ID,
    i.PATH_SELECTION_LINK_CLASS_ID AS LINK_CLASS_ID
FROM MSS.INTERFACE i
WHERE i.PATH_SELECTION_LINK_CLASS_ID IS NOT NULL
and not exists (select 1 from APPID.INTERFACE_2_PS_LINK_CLASS x
                where x.INTERFACE_ID = i.ID
                and x.LINK_CLASS_ID = i.PATH_SELECTION_LINK_CLASS_ID);

--changeset gta:2223
--comment: RTNG-882: populate APPID.PATH_OVERRIDE_MEMBER_LINK.LINK_CLASS_ID
UPDATE APPID.PATH_OVERRIDE_MEMBER_LINK poml
SET LINK_CLASS_ID = (
    SELECT i.PATH_SELECTION_LINK_CLASS_ID
    FROM MSS.INTERFACE i
    WHERE i.id = poml.INTERFACE_ID
    AND i.PATH_SELECTION_LINK_CLASS_ID IS NOT NULL
)
WHERE poml.LINK_CLASS_ID IS NULL;

--changeset gta:2224
--comment: RTNG-882: deprecate MSS.INTERFACE.PATH_SELECTION_LINK_CLASS_ID
COMMENT ON COLUMN MSS.INTERFACE.PATH_SELECTION_LINK_CLASS_ID IS
'DEPRECATED: This column is deprecated as of 29.08.2025. Use table APPID.PATH_SELECTION_LINK_CLASS instead.';

--changeset ogl:2225
--comment: do not block portal interface delete
grant select on mss.interface to appid;
ALTER TABLE APPID.INTERFACE_2_PS_LINK_CLASS drop CONSTRAINT INTERFACE_2_PS_LINK_CLASS_FK2;
ALTER TABLE APPID.INTERFACE_2_PS_LINK_CLASS add CONSTRAINT INTERFACE_2_PS_LINK_CLASS_FK2 FOREIGN KEY (INTERFACE_ID) REFERENCES MSS.INTERFACE(ID) on delete cascade;

--changeset ang:2226
--comment: IDS-3367: add resolvers for NDR signatures
GRANT SELECT,INSERT,UPDATE,DELETE ON NIDS.SIGNATURE TO SVC_CONIFER;
GRANT SELECT ON NIDS.SIGNATURE_SEQ TO SVC_CONIFER;
GRANT SELECT,INSERT,UPDATE,DELETE ON NIDS.SIGNATURE_CLASS TO SVC_CONIFER;
GRANT SELECT ON NIDS.SIGNATURECLASS_SEQ TO SVC_CONIFER;
GRANT SELECT,INSERT,UPDATE,DELETE ON NIDS.SIGNATURE_GROUP TO SVC_CONIFER;
GRANT SELECT ON NIDS.SIGNATUREGROUP_SEQ TO SVC_CONIFER;
GRANT SELECT,INSERT,UPDATE,DELETE ON NIDS.SIGNATURE_GROUP_MEMBER TO SVC_CONIFER;
GRANT SELECT ON NIDS.SIGNATURE_GROUP_MEMBER_TYPE TO SVC_CONIFER;
GRANT SELECT ON NIDS.SIGNATUREGROUPMEMBER_SEQ TO SVC_CONIFER;
GRANT SELECT,INSERT,UPDATE,DELETE ON NIDS.SIGNATURE_REFERENCE TO SVC_CONIFER;
GRANT SELECT ON NIDS.SIGNATURE_REFERENCE_TYPE TO SVC_CONIFER;
GRANT SELECT ON NIDS.SIGNATURE_REFERENCE_SEQ TO SVC_CONIFER;
GRANT SELECT,INSERT,UPDATE,DELETE ON NIDS.DYNAMIC_SIGNATURE_GROUP TO SVC_CONIFER;
GRANT SELECT ON NIDS.DYNSIGNATUREGROUP_SEQ TO SVC_CONIFER;
GRANT SELECT ON NIDS.DIRECTION TO SVC_CONIFER;

--changeset ogl:2227
--comment: NC-1111: resetDynIpState
grant delete on MSS.INTERFACE_DYNAMIC_IP_STATE to SVC_CONIFER;

--changeset ang:2228
--comment: IDS-3367: add audit record type for NDR signatures
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID)
VALUES (473, 'NDR signature created', 'ndr_signature_created', 'A new NDR signature has been created',1);
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID)
VALUES (474, 'NDR signature deleted', 'ndr_signature_deleted', 'A NDR signature has been deleted',1);

--changeset nis:2229
--comment: MC-30427: allow TT.TICKET_FLOW select for portal pm user
grant select on TT.TICKET_FLOW to SVC_MC_PORTAL;

--changeset rse:2230
--comment: TRIVIAL: Remove EOL balu migration dbprops migrate.balu.amqp and migrate.balu.rabbitmq_gateway
DELETE FROM MSS.VALUE WHERE key_id IN (SELECT id FROM MSS.KEY WHERE name='migrate.balu.amqp');
DELETE FROM MSS.KEY WHERE name='migrate.balu.amqp';
DELETE FROM MSS.VALUE WHERE key_id IN (SELECT id FROM MSS.KEY WHERE name='migrate.balu.rabbitmq_gateway');
DELETE FROM MSS.KEY WHERE name='migrate.balu.rabbitmq_gateway';

--changeset rse:2231
--comment: TRIVIAL: Add dbprop balu.gateway.rabbitmq_cluster to select RabbitMQ cluster for Balu Gateway
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (57130, 'balu.gateway.rabbitmq_cluster', 4, NULL, '^(?:[a-z0-9.:_-]+(?:\h+[a-z0-9.:]+)*)?$', NULL, 'RabbitMQ cluster subdomain(s) for Balu Gateway');

--changeset del:2232
--comment: TRIVIAL: Fix pacemaker.http-health.clientnetworks regex
update MSS.KEY set REGEXP='^((25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]?|0)\.){3}(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]?|0)\/([0-9]|[1-2][0-9]|3[0-2])(?:\s+((25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]?|0)\.){3}(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]?|0)\/([0-9]|[1-2][0-9]|3[0-2]))*$' where name = 'pacemaker.http-health.clientnetworks';

--changeset mag:2233
--comment: PRX-7762: Set squid.urlfilter.anonymisation default value to 0
update mss.KEY set STRING_DEFAULT='0' where NAME='squid.urlfilter.anonymisation';

--changeset lut:2234
--comment: RTNG-1096: Add dbprop to control rollout of color-based IPsets and firewall rules
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (57131, 'migrate.path.color_ipsets', 1, '0', '^[01]$', NULL, 'Triggers Path Selection migration to color-based IPsets and firewall rules');

--changeset gks:2235
--comment: IDS-3420: Create zeek file extraction dbprop
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (57140, 'ndr.file_scanning', 1,'0','^[01]$',NULL,'Enables or disables NDR file scanning');

--changeset ang:2236
--comment: IDS-3369: add audit record type for NDR signatures groups
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID)
VALUES (475, 'NDR signature group created', 'ndr_signature_group_created', 'A new NDR signature group has been created',1);
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID)
VALUES (476, 'NDR signature group deleted', 'ndr_signature_group_deleted', 'A NDR signature group has been deleted',1);
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID)
VALUES (477, 'NDR signature group memeber added', 'ndr_signature_group_member_added', 'A member has been added to an NDR signature group',1);
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID)
VALUES (478, 'NDR signature group memeber removed', 'ndr_signature_group_member_removed', 'A member has been removed from an NDR signature group',1);
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID)
VALUES (479, 'NDR dynamic signature group created', 'ndr_dynamic_signature_group_created', 'A new NDR dynamic signature group has been created',1);
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID)
VALUES (480, 'NDR dynamic signature group deleted', 'ndr_dynamic_signature_group_deleted', 'A NDR dynamic signature group has been deleted',1);

--changeset nis:2237
--comment: MC-30503: grants for DECOMM user to allow to decommission routers
grant select on MC.INTERRUPT_REVIEW_STATUS to DECOMM;
grant select on MC.CON_INT_TYPE to DECOMM;

--changeset ogl:2238
--comment: ORE-11984 missing perms for dynamic ip reset
grant select,update,delete on MSS.INTERFACE_DYNAMIC_IP_STATE to SVC_CONIFER;

--changeset nis:2239
--comment: MC-30503: grants for DECOMM user to allow to decommission routers
grant select on MC.CONNECTION_INTERRUPT_CLOSED to DECOMM;

--changeset doi:2240
--comment: PRX-9437: add dbprop to enable/disable the warning page feature
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (57141, 'squid.warningpage', 1, '0', '^[01]$', NULL, 'Enable warning page feature');

--changeset aas:2241
--comment: ZTNA-1845: Add new DB Prop migrate.ztna.users_in_portal
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (57150, 'migrate.ztna.users_in_portal', 1, '0', '^[01]$', NULL, 'Enable ZTNA users in our portal');

--changeset rse:2242
--comment: TRIVIAL: Add dbprop ntp.xleave (support RFC 9769)
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (57160, 'ntp.xleave', 1, '0', '^[01]$', NULL, 'Enable NTP interleaved modes (RFC 9769) for upstream NTP servers');

--changeset lel:2243
--comment: STAFFE-27: Add new DB Prop deployment.environment.name
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (57161, 'deployment.environment.name', 1,'prod', '^dev|test|prod$', NULL, 'Describes the environment an SDP belongs to');

--changeset lel:2244
--comment: STAFFE-27: Correct type of dbprop to string
update MSS.KEY SET KEY_TYPE_ID = 4 WHERE ID = 57161;

--changeset ssk:2245
--comment: CLOUD-922: avoid full table scans in recursive cte for firewall usages
CREATE INDEX FW.IDX_IPGROUPMEMBER_MEMBERIPGROUP ON FW.IP_GROUP_MEMBER (MEMBER_IP_GROUP_ID);
CREATE INDEX FW.IDX_SCOPEDIPGROUPSCOPE_SCOPEDIPGROUP ON FW.SCOPED_IP_GROUP_SCOPE (SCOPED_IP_GROUP_ID);
create index FW.IDX_SCOPEDIPGRPMEM on FW.SCOPED_IP_GROUP_MEMBER(SCOPED_IP_GROUP_ID, SPECIFIC_SCOPE_SERVICE_ID);

--changeset ogl:2246
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM dba_users WHERE username='FOO'
CREATE USER "SVC_TICKET_EMBEDDINGS" IDENTIFIED BY "xxxxxx" ACCOUNT LOCK
  DEFAULT TABLESPACE "USERS"
  TEMPORARY TABLESPACE "TEMP";

--changeset ogl:2247 contextFilter:dummyPasswords
--comment: only for login users, not for schema users
ALTER USER "SVC_TICKET_EMBEDDINGS" IDENTIFIED BY "password" ACCOUNT UNLOCK;

--changeset ogl:2248
--comment: system, object grants for FOO
GRANT "MSS_LOGIN_USER" TO "SVC_TICKET_EMBEDDINGS";
ALTER USER "SVC_TICKET_EMBEDDINGS" DEFAULT ROLE "MSS_LOGIN_USER";
GRANT SELECT ON tt.TICKET TO SVC_TICKET_EMBEDDINGS;
GRANT SELECT ON tt.EVENT TO SVC_TICKET_EMBEDDINGS;
GRANT SELECT ON tt.STATUS TO SVC_TICKET_EMBEDDINGS;

--changeset emd:2249
--comment: MC-30018: Grant attachment sequence permission to the internal ticketing user to store attachments.
GRANT SELECT ON TT.ATTACHMENT_SEQ TO SVC_USERS_INTERNAL_API;

--changeset mag:2250
--comment: PRX-9277: Remove deprecated squid.urlfilter.anonymisation DB Prop
DELETE FROM MSS.VALUE v where v.key_id = (SELECT k.id from MSS.KEY k where k.name = 'squid.urlfilter.anonymisation');
DELETE FROM MSS.KEY where name = 'squid.urlfilter.anonymisation';

--changeset ang:2251
--comment: IDS-3365: Create IPS blocking duration dbprop ndr.ips.block.ttl
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (57162, 'ndr.ips.block.ttl', 4,'4h','^(4s|4m|4h|4d|4w|4y)$',NULL,'Duration of an IPS block');

--changeset ogl:2252
--comment: DNSSEC is unused
drop user DNSSEC;

--changeset ang:2253
--comment: IDS-3365: adjust the regex of ndr.ips.block.ttl to allow any number
update MSS.key k
set k.REGEXP='^[0-9]+(s|m|h|d|w|y)$'
where k.id=57162 and k.name='ndr.ips.block.ttl';

--changeset ogl:2254
--comment: DB-3074: unmap CHECKLIST schema
drop table CHECKLIST."#JDO_PROPERTIES";

--changeset fak:2255
--comment: OB-600: Add new DB Prop lldp
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (57163, 'lldp', 1, '0', '^[01]$', NULL, 'Enable lldp daemon');
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (57164, 'lldp.interfaces', 1, '@if_LOCAL_INT', '^(?:(?:@if_LOCAL_(?:INT|EXT|ALL))|(?:eth|lacp)[1-9]?[0-9](?:\.[1-9][0-9]{0,3})?)(?: (?:(?:@if_LOCAL_(?:INT|EXT|ALL))|(eth|lacp)[1-9]?[0-9](\.[1-9][0-9]{0,3})?))*$', NULL, 'Interfaces for lldp to be enabled on');

--changeset fak:2256
--comment: OB-600: Fix key type of DB Prop lldp.interfaces
UPDATE MSS.key k
SET k.KEY_TYPE_ID=4
WHERE k.id=57164 and k.name='lldp.interfaces';

--changeset ogl:2257
--comment: DB-3060: Add dbprop to enable docker on lamarr
insert into mss.KEY(ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, DESCRIPTION, OPERATING_SYSTEM_ID)
values (57165, 'mgmtserver.docker', 1, '0', '^[01]$', 'Enables Docker on a mgmt host', 22);

--changeset ogl:2258
--comment: remove CHECKLIST
drop user CHECKLIST cascade;
drop user WEBCHECKLISTS;
delete from auth."#JDO_PROPERTIES" where key like '%.naming.inverse.CHECKLIST.%';
delete from mss."#JDO_PROPERTIES" where key like '%.naming.inverse.CHECKLIST.%';
delete from stop."#JDO_PROPERTIES" where key like '%.naming.inverse.CHECKLIST.%';
delete from tt."#JDO_PROPERTIES" where key like '%.naming.inverse.CHECKLIST.%';

--changeset nis:2259
--comment: MC-30503: grants for DECOMM user to allow to decommission routers
grant update on AUTH.AUTHHOST to DECOMM;

--changeset nis:2260
--comment: MC-30503: grants for DECOMM user to allow to decommission routers
grant delete on AUTH.AUTHHOST to DECOMM;

--changeset fak:2261
--comment: OB-600: Fix regexp for DB Prop lldp.interfaces
UPDATE MSS.key k
SET k.REGEXP='^(?:(?:@if_LOCAL_(?:INT|EXT|ALL))|!?(?:eth|lacp)[1-9]?[0-9](?:\.[1-9][0-9]{0,3})?)(?: (?:(?:@if_LOCAL_(?:INT|EXT|ALL))|!?(eth|lacp)[1-9]?[0-9](\.[1-9][0-9]{0,3})?))*$'
WHERE k.id=57164 and k.name='lldp.interfaces';

--changeset alg:2262
--comment: ORE-12311: DB User for Syncify
CREATE USER "SVC_SYNCIFY" IDENTIFIED BY "xxxxxx" ACCOUNT LOCK
  DEFAULT TABLESPACE "USERS"
  TEMPORARY TABLESPACE "TEMP";

--changeset alg:2263 contextFilter:dummyPasswords
--comment: only for login users, not for schema users
ALTER USER "SVC_SYNCIFY" IDENTIFIED BY "password" ACCOUNT UNLOCK;

--changeset alg:2264
--comment: system, object grants for SVC_SYNCIFY
GRANT "MSS_LOGIN_USER" TO "SVC_SYNCIFY";
ALTER USER "SVC_SYNCIFY" DEFAULT ROLE "MSS_LOGIN_USER";
GRANT SELECT ON STOP.COMPANY TO SVC_SYNCIFY;
GRANT SELECT ON STOP.COMP_COMPTYPE_REF TO SVC_SYNCIFY;
GRANT SELECT ON STOP.COMPANY_UNIT TO SVC_SYNCIFY;
GRANT SELECT ON STOP.CONTACT TO SVC_SYNCIFY;
GRANT SELECT ON AUTH.LOGIN TO SVC_SYNCIFY;
GRANT SELECT ON AUTH.LOGIN2PROFILE TO SVC_SYNCIFY;
GRANT SELECT ON AUTH.PROFILE TO SVC_SYNCIFY;
GRANT SELECT ON AUTH.USER_PERMISSION TO SVC_SYNCIFY;
GRANT SELECT ON AUTH.USER_COMPANY_SCOPE TO SVC_SYNCIFY;
GRANT SELECT ON AUTH.USER_COMPANY_UNIT_SCOPE TO SVC_SYNCIFY;
GRANT SELECT ON AUTH.USER_ROLE TO SVC_SYNCIFY;
GRANT SELECT ON AUTH.USER_SERVICE_SCOPE TO SVC_SYNCIFY;
GRANT SELECT ON AUTH.USER_UNIT TO SVC_SYNCIFY;
GRANT SELECT ON AUTH.USER_UNIT_SCOPE TO SVC_SYNCIFY;
GRANT SELECT ON MSS.SERVICE TO SVC_SYNCIFY;
GRANT SELECT ON MSS.HOST2SERVICE TO SVC_SYNCIFY;
GRANT SELECT ON ESP.MC_CENTER_CONTACT TO SVC_SYNCIFY;

--changeset nis:2265
--comment: MC-30503: grants for DECOMM user to allow to decommission routers
GRANT SELECT, DELETE, UPDATE on AUTH.DIRTYAUTHHOST to DECOMM;

--changeset ogl:2266
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:1 select count(*) from DBA_INDEXES where INDEX_NAME='IDX_H2S_HOST_UN' and owner='SYS'
--comment: move index out of SYS
drop index sys.IDX_H2S_HOST_UN;

--changeset ogl:2267
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:0 select count(*) from DBA_INDEXES where INDEX_NAME='IDX_H2S_HOST_UN' and owner='MSS'
--comment: move index out of SYS
create unique index mss.IDX_H2S_HOST_UN on mss.HOST2SERVICE(HOST_ID);

--changeset ogl:2268
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:1 select count(*) from DBA_INDEXES where INDEX_NAME='HARDWARE_UV4' and owner='SYS'
--comment: move index out of SYS
drop index sys.HARDWARE_UV4;

--changeset ogl:2269
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:0 select count(*) from DBA_INDEXES where INDEX_NAME='HARDWARE_UV4' and owner='MSS'
--comment: move index out of SYS
create index mss.hardware_uv4 on mss.hardware(lower(mac_address));

--changeset ogl:2270
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:1 select count(*) from DBA_INDEXES where INDEX_NAME='SERVICETYPE_UV1' and owner='SYS'
--comment: move index out of SYS
drop index sys.SERVICETYPE_UV1;

--changeset ogl:2271
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:0 select count(*) from DBA_INDEXES where INDEX_NAME='SERVICETYPE_UV1' and owner='MSS'
--comment: move index out of SYS
create unique index mss.SERVICETYPE_UV1 on mss.SERVICE_TYPE(INTERNAL_CODE);

--changeset nis:2272
--comment: MC-30427: Move out of RLS for the portal
DROP TABLE RLSDEF."#JDO_PROPERTIES";

--changeset mtt:2273
--comment: MEP-2609: Set sslvpn.asav.version to new current version 9.18.4_67
update mss.KEY set STRING_DEFAULT='9.18.4_67' where NAME='sslvpn.asav.version';

--changeset nis:2274
--comment: MC-30427: Move out of RLS for the portal
delete from auth."#JDO_PROPERTIES" where key='ROLE.naming.inverse.RLSDEF.PREDICATE_FK1';

--changeset mgr:2275
--comment: MX-6471: Delete obsolete dbprops postfix.batv and postfix.batv.reject
DELETE FROM MSS.VALUE v where v.key_id = (SELECT k.id from MSS.KEY k where k.name = 'postfix.batv');
DELETE FROM MSS.KEY where name = 'postfix.batv';
DELETE FROM MSS.VALUE v where v.key_id = (SELECT k.id from MSS.KEY k where k.name = 'postfix.batv.reject');
DELETE FROM MSS.KEY where name = 'postfix.batv.reject';

--changeset nis:2276
--comment: MC-30427: Move out of RLS for the portal
DROP USER RLSDEF CASCADE;
DROP USER WEBRLS CASCADE;
DROP PACKAGE TT.OSAG_TT_WEBRLS;
DROP PACKAGE AUTH.OSAG_AUTH_WEBRLS;
DROP PACKAGE AUTH.OSAG_AUTH_WEBRLS_PASSPORT;

--changeset ogl:2277 endDelimiter:/
--comment: remove any RLS policies
begin
  for r in (select * from all_policies where pf_owner = 'RLSDEF') loop
      dbms_rls.DROP_POLICY(r.OBJECT_OWNER, r.OBJECT_NAME, r.POLICY_NAME);
    end loop;
end;
/

--changeset emd:2278
--comment: Allows ticketing api to create tickets with attachment
grant select ON TT.ATTACHMENT_SEQ TO SVC_API_TICKETING;

--changeset ssk:2279
--comment: CLOUD-712: index foreign key columns
CREATE INDEX MSS.IDX_NETWORK_SCOPECOMPANYID ON MSS.NETWORK (SCOPE_COMPANY_ID);
CREATE INDEX MSS.IDX_IPV6ADDRESS_COMPANYID ON MSS.IPV6_ADDRESS (COMPANY_ID);
CREATE INDEX FW.IDX_DNSOBJECT_COMPANYID ON FW.DNS_OBJECT (COMPANY_ID);
CREATE INDEX FW.IDX_APPGROUP_COMPANYID ON FW.APP_GROUP (COMPANY_ID);
CREATE INDEX FW.IDX_SCOPEDIPGROUP_COMPANYID ON FW.SCOPED_IP_GROUP (COMPANY_ID);
CREATE INDEX FW.IDX_ZONE_COMPANYID ON FW.ZONE (COMPANY_ID);
CREATE INDEX FW.IDX_SUBSECTION_SECTIONID ON FW.SUB_SECTION (SECTION_ID);
CREATE INDEX FW.IDX_SECTION_POLICYID ON FW.SECTION (POLICY_ID);
CREATE INDEX FW.IDX_NATSECTION_POLICYID ON FW.NAT_SECTION (POLICY_ID);
CREATE INDEX FW.IDX_IPGROUPMEMBER_DNSOBJECTID ON FW.IP_GROUP_MEMBER (DNS_OBJECT_ID);
CREATE INDEX FW.IDX_IPGROUPMEMBER_IPV6PREFIXID ON FW.IP_GROUP_MEMBER (IPV6_PREFIX_ID);
CREATE INDEX FW.IDX_IPGROUPMEMBER_IPV6ADDRESSID ON FW.IP_GROUP_MEMBER (IPV6_ADDRESS_ID);
CREATE INDEX FW.IDX_IPGROUPMEMBER_IPADDRESSID ON FW.IP_GROUP_MEMBER (IP_ADDRESS_ID);
CREATE INDEX FW.IDX_IPGROUPMEMBER_SCOPEDIPGROUPMEMBERID ON FW.IP_GROUP_MEMBER (SCOPED_IP_GROUP_MEMBER_ID);

--changeset nop:2280
--comment: Add new customer configuration change
insert into TT.EVENT_TYPE (ID, NAME, SOURCE, IS_NOTIFIED, ESCALATION, DESCRIPTION, SMS_MESSAGE_TEMPLATE_ID, EMAIL_MESSAGE_TEMPLATE_ID, PINNABLE, AUTOPIN)
values (30023, 'configuration change', 3, 0, 0, 'customer configuration change', 1, 2, 0, 0);

--changeset baj:2281
--comment: IDS-3456: Implement new database tables in oracle for NDR policy rules
-- NDR Action Rules main table
CREATE TABLE NIDS.POLICY_RULE (
	ID NUMBER(11,0) NOT NULL,
	DESCRIPTION VARCHAR2(255 BYTE),
	PRECEDENCE NUMBER(11,0) NOT NULL,
	DIRECTION_ID NUMBER(11,0),
	SRC_AUTOMATIC_IP_GROUP_ID NUMBER(11,0),
	DST_AUTOMATIC_IP_GROUP_ID NUMBER(11,0),
	SIGNATURE_GROUP_ID NUMBER(11,0),
	COMPANY_ID NUMBER(11,0),
	SERVICE_ID NUMBER(11,0),
	CONSTRAINT POLICY_RULE_PK PRIMARY KEY (ID),
    CONSTRAINT POLICY_RULE_FK1 FOREIGN KEY (DIRECTION_ID) REFERENCES NIDS.DIRECTION (ID),
    CONSTRAINT POLICY_RULE_FK2 FOREIGN KEY (SRC_AUTOMATIC_IP_GROUP_ID) REFERENCES FW.IP_GROUP (ID),
    CONSTRAINT POLICY_RULE_FK3 FOREIGN KEY (DST_AUTOMATIC_IP_GROUP_ID) REFERENCES FW.IP_GROUP (ID),
    CONSTRAINT POLICY_RULE_FK4 FOREIGN KEY (SIGNATURE_GROUP_ID) REFERENCES NIDS.SIGNATURE_GROUP (ID),
    CONSTRAINT POLICY_RULE_FK5 FOREIGN KEY (COMPANY_ID) REFERENCES STOP.COMPANY (ID),
    CONSTRAINT POLICY_RULE_FK6 FOREIGN KEY (SERVICE_ID) REFERENCES MSS.SERVICE (ID)
);

COMMENT ON TABLE NIDS.POLICY_RULE IS 'NDR Policy Rules that define automated responses to network security events based on criteria like direction, source/destination, signatures, and organizational scope';
COMMENT ON COLUMN NIDS.POLICY_RULE.DESCRIPTION IS 'Optional string that describes why this rule exists';
COMMENT ON COLUMN NIDS.POLICY_RULE.PRECEDENCE IS 'Ordering of the rules. Per scope the rules are processed/checked in an order, lowest number for precedence is checked first';
COMMENT ON COLUMN NIDS.POLICY_RULE.DIRECTION_ID IS 'FK to table NIDS.DIRECTION. NULL means any direction';
COMMENT ON COLUMN NIDS.POLICY_RULE.SRC_AUTOMATIC_IP_GROUP_ID IS 'FK to table FW.IP_GROUP. NULL means any source. This IP Group will be an automatic IP group that is created (similar as for firewall rules) if a source is being added to a rule';
COMMENT ON COLUMN NIDS.POLICY_RULE.DST_AUTOMATIC_IP_GROUP_ID IS 'FK to table FW.IP_GROUP. NULL means any destination. This IP Group will be an automatic IP group that is created (similar as for firewall rules) if a destination is being added to a rule';
COMMENT ON COLUMN NIDS.POLICY_RULE.SIGNATURE_GROUP_ID IS 'FK to table NIDS.SIGNATURE_GROUP, the linked signature group has the automatic flag set (i.e. a new automatic signature group is created if a signature is selected as a filter). NULL means any signature';
COMMENT ON COLUMN NIDS.POLICY_RULE.COMPANY_ID IS 'FK to table STOP.COMPANY. Needs to be set when when scope is company or service';
COMMENT ON COLUMN NIDS.POLICY_RULE.SERVICE_ID IS 'FK to table MSS.SERVICE. Needs to be set when when scope is service';

CREATE SEQUENCE NIDS.POLICY_RULE_SEQ;

-- Indexes on foreign key columns for NIDS.POLICY_RULE
CREATE INDEX NIDS.IDX_POLICY_RULE_DIRECTION ON NIDS.POLICY_RULE (DIRECTION_ID);
CREATE INDEX NIDS.IDX_POLICY_RULE_SRC_IP_GROUP ON NIDS.POLICY_RULE (SRC_AUTOMATIC_IP_GROUP_ID);
CREATE INDEX NIDS.IDX_POLICY_RULE_DST_IP_GROUP ON NIDS.POLICY_RULE (DST_AUTOMATIC_IP_GROUP_ID);
CREATE INDEX NIDS.IDX_POLICY_RULE_SIG_GROUP ON NIDS.POLICY_RULE (SIGNATURE_GROUP_ID);
CREATE INDEX NIDS.IDX_POLICY_RULE_COMPANY ON NIDS.POLICY_RULE (COMPANY_ID);
CREATE INDEX NIDS.IDX_POLICY_RULE_SERVICE ON NIDS.POLICY_RULE (SERVICE_ID);

GRANT SELECT,INSERT,UPDATE,DELETE ON NIDS.POLICY_RULE TO SVC_CONIFER;
GRANT SELECT ON NIDS.POLICY_RULE_SEQ TO SVC_CONIFER;

-- NDR Action lookup table
CREATE TABLE NIDS.ACTION (
	ID NUMBER(11,0) NOT NULL,
	ACTION_TYPE VARCHAR2(255 BYTE) NOT NULL,
	CONSTRAINT ACTION_PK PRIMARY KEY (ID),
    CONSTRAINT ACTION_TYPE_UK UNIQUE (ACTION_TYPE)
);

COMMENT ON TABLE NIDS.ACTION IS 'Lookup table for available NDR actions that can be executed as part of policy rules';
COMMENT ON COLUMN NIDS.ACTION.ACTION_TYPE IS 'Action type that defines what to do when the action is triggered';

INSERT INTO NIDS.ACTION (ID, ACTION_TYPE) VALUES (1, 'no_action');
INSERT INTO NIDS.ACTION (ID, ACTION_TYPE) VALUES (2, 'drop');
INSERT INTO NIDS.ACTION (ID, ACTION_TYPE) VALUES (3, 'block_src');
INSERT INTO NIDS.ACTION (ID, ACTION_TYPE) VALUES (4, 'block_dst');

CREATE SEQUENCE NIDS.ACTION_SEQ;

GRANT SELECT,INSERT,UPDATE,DELETE ON NIDS.ACTION TO SVC_CONIFER;
GRANT SELECT ON NIDS.ACTION_SEQ TO SVC_CONIFER;

-- NDR Rule to Action junction table
CREATE TABLE NIDS.RULE2ACTION (
	RULE_ID NUMBER(11,0) NOT NULL,
	ACTION_ID NUMBER(11,0) NOT NULL,
	CONSTRAINT RULE2ACTION_PK PRIMARY KEY (RULE_ID, ACTION_ID),
    CONSTRAINT RULE2ACTION_FK1 FOREIGN KEY (RULE_ID) REFERENCES NIDS.POLICY_RULE (ID),
    CONSTRAINT RULE2ACTION_FK2 FOREIGN KEY (ACTION_ID) REFERENCES NIDS.ACTION (ID)
);

COMMENT ON TABLE NIDS.RULE2ACTION IS 'Junction table that links NDR Policy Rules with one or more Actions';
COMMENT ON COLUMN NIDS.RULE2ACTION.RULE_ID IS 'FK to NIDS.POLICY_RULE, one rule can have multiple actions';
COMMENT ON COLUMN NIDS.RULE2ACTION.ACTION_ID IS 'FK to NIDS.ACTION, defines which action to execute';

-- Indexes on foreign key columns for NIDS.RULE2ACTION
CREATE INDEX NIDS.IDX_RULE2ACTION_RULE ON NIDS.RULE2ACTION (RULE_ID);
CREATE INDEX NIDS.IDX_RULE2ACTION_ACTION ON NIDS.RULE2ACTION (ACTION_ID);

GRANT SELECT,INSERT,UPDATE,DELETE ON NIDS.RULE2ACTION TO SVC_CONIFER;

-- NDR Rule to Ticket junction table
CREATE TABLE NIDS.RULE2TICKET (
	RULE_ID NUMBER(11,0) NOT NULL,
	TICKET_ID NUMBER(11,0) NOT NULL,
	CONSTRAINT RULE2TICKET_PK PRIMARY KEY (RULE_ID, TICKET_ID),
    CONSTRAINT RULE2TICKET_FK1 FOREIGN KEY (RULE_ID) REFERENCES NIDS.POLICY_RULE (ID),
    CONSTRAINT RULE2TICKET_FK2 FOREIGN KEY (TICKET_ID) REFERENCES TT.TICKET (ID)
);

COMMENT ON TABLE NIDS.RULE2TICKET IS 'Junction table that links NDR Policy Rules to tickets';
COMMENT ON COLUMN NIDS.RULE2TICKET.RULE_ID IS 'FK to NIDS.POLICY_RULE, one rule can create multiple tickets';
COMMENT ON COLUMN NIDS.RULE2TICKET.TICKET_ID IS 'FK to TT.TICKET, reference to the created ticket';

-- Indexes on foreign key columns for NIDS.RULE2TICKET
CREATE INDEX NIDS.IDX_RULE2TICKET_RULE ON NIDS.RULE2TICKET (RULE_ID);
CREATE INDEX NIDS.IDX_RULE2TICKET_TICKET ON NIDS.RULE2TICKET (TICKET_ID);

GRANT SELECT,INSERT,UPDATE,DELETE ON NIDS.RULE2TICKET TO SVC_CONIFER;

--changeset ang:2281
--comment: IDS-3478: Create dbprop migrate.2025.zeek.clustermode for the migration of zeek to cluster mode
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (57166, 'migrate.2025.zeek.clustermode', 1, '0', '^[01]$', NULL, 'Run zeek in cluster mode');

--changeset fak:2282
--comment: OB-612: Update default value of LLDP listen interfaces to physical only
UPDATE MSS.key k
SET   k.STRING_DEFAULT='@if_LOCAL_INTPHYS',
      k.REGEXP='^(?:(?:@if_LOCAL_(?:INT|EXT|ALL)(PHYS)?)|!?(?:eth|lacp)[1-9]?[0-9](?:\.[1-9][0-9]{0,3})?)(?: (?:(?:@if_LOCAL_(?:INT|EXT|ALL)(PHYS)?)|!?(eth|lacp)[1-9]?[0-9](\.[1-9][0-9]{0,3})?))*$'
WHERE k.id=57164 and k.name='lldp.interfaces';

--changeset fla:2283
--comment: Adds grants for portal db users to be able to read the new NDR policy rules

-- portal pm user
GRANT SELECT ON NIDS.POLICY_RULE TO SVC_MC_PORTAL;
GRANT SELECT ON NIDS.POLICY_RULE_SEQ TO SVC_MC_PORTAL;
GRANT SELECT ON NIDS.ACTION TO SVC_MC_PORTAL;
GRANT SELECT ON NIDS.ACTION_SEQ TO SVC_MC_PORTAL;
GRANT SELECT ON NIDS.RULE2ACTION TO SVC_MC_PORTAL;
GRANT SELECT ON NIDS.RULE2TICKET TO SVC_MC_PORTAL;

-- ming user
GRANT SELECT ON NIDS.POLICY_RULE TO CHE;
GRANT SELECT ON NIDS.POLICY_RULE_SEQ TO CHE;
GRANT SELECT ON NIDS.ACTION TO CHE;
GRANT SELECT ON NIDS.ACTION_SEQ TO CHE;
GRANT SELECT ON NIDS.RULE2ACTION TO CHE;
GRANT SELECT ON NIDS.RULE2TICKET TO CHE;

-- mca user
GRANT SELECT ON NIDS.POLICY_RULE TO MCA;
GRANT SELECT ON NIDS.POLICY_RULE_SEQ TO MCA;
GRANT SELECT ON NIDS.ACTION TO MCA;
GRANT SELECT ON NIDS.ACTION_SEQ TO MCA;
GRANT SELECT ON NIDS.RULE2ACTION TO MCA;
GRANT SELECT ON NIDS.RULE2TICKET TO MCA;

--changeset mxd:2284
--comment: ORE-12311: system, object grants for SVC_SYNCIFY
GRANT SELECT ON STOP.COMPTYPE TO SVC_SYNCIFY;

--changeset nop:2285
--comment: SRE-1443: access to VPN tables for SVC_AUTOMATION_EXECUTOR
GRANT SELECT ON VPN.TUNNEL TO SVC_AUTOMATION_EXECUTOR;
GRANT SELECT ON VPN.VPN_MEMBER TO SVC_AUTOMATION_EXECUTOR;

--changeset mxd:2286
--comment: OSAP-1482
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID)
VALUES (481, 'User group created', 'user_group_created', 'A new user group has been created', 5);
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID)
VALUES (482, 'User group updated', 'user_group_updated', 'A user group has been updated', 5);
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID)
VALUES (483, 'User group deleted', 'user_group_deleted', 'A user group has been deleted', 5);

--changeset alg:2287
--comment: DB-3084: DB User for Netfabric
CREATE USER "SVC_NETFABRIC" IDENTIFIED BY "xxxxxx" ACCOUNT LOCK
  DEFAULT TABLESPACE "USERS"
  TEMPORARY TABLESPACE "TEMP";

--changeset alg:2288 contextFilter:dummyPasswords
--comment: only for login users, not for schema users
ALTER USER "SVC_NETFABRIC" IDENTIFIED BY "password" ACCOUNT UNLOCK;

--changeset alg:2289
--comment: system, object grants for SVC_NETFABRIC
GRANT "MSS_LOGIN_USER" TO "SVC_NETFABRIC";
ALTER USER "SVC_NETFABRIC" DEFAULT ROLE "MSS_LOGIN_USER";
GRANT SELECT ON TT.TICKET TO "SVC_NETFABRIC";
GRANT SELECT ON TT.EVENT TO "SVC_NETFABRIC";
--changeset ogl:2287
--comment: ORE-12806 add NIDS.POLICY_RULE to consistency checks
update MCDB_CHECKS.CONSISTENCY_CHECKS
set statement='SELECT ig.id FROM FW.IP_GROUP ig WHERE
  ig.automatic = 1 AND
  NOT EXISTS (SELECT 1 FROM FW.IP_GROUP_MEMBER WHERE IP_GROUP_ID = ig.id or MEMBER_IP_GROUP_ID = ig.id) AND
  NOT EXISTS (SELECT 1 FROM FW.RULE WHERE SRC_IP_GROUP_ID = ig.id or DST_IP_GROUP_ID = ig.id) AND
  NOT EXISTS (SELECT 1 FROM FW.DESTINATION_NAT_RULE WHERE ORIG_SRC_GROUP_ID = ig.id or ORIG_DST_GROUP_ID = ig.id or TRANS_DST_GROUP_ID = ig.id) AND
  NOT EXISTS (SELECT 1 FROM FW.SOURCE_NAT_RULE WHERE ORIG_SRC_GROUP_ID = ig.id or ORIG_DST_GROUP_ID = ig.id or TRANS_SRC_GROUP_ID = ig.id) AND
  NOT EXISTS (SELECT 1 FROM FW.SCOPED_IP_GROUP_SCOPE WHERE IP_GROUP_ID = ig.id) AND
  NOT EXISTS (SELECT 1 FROM MSS.INTERFACE WHERE ANTI_SPOOFING_IP_GROUP_ID = ig.id) AND
  NOT EXISTS (SELECT 1 FROM NIDS.POLICY_RULE WHERE SRC_AUTOMATIC_IP_GROUP_ID = ig.id or DST_AUTOMATIC_IP_GROUP_ID = ig.id)'
where check_key='SEL_unref_automatic_ip_group';

--changeset gta:2288
--comment: RTNG-882: deprecate APPID.PATH_OVERRIDE_MEMBER_LINK.INTERFACE_ID
COMMENT ON COLUMN APPID.PATH_OVERRIDE_MEMBER_LINK.INTERFACE_ID IS
'DEPRECATED: This column is deprecated as of 29.08.2025. Use table APPID.PATH_OVERRIDE_MEMBER_LINK.LINK_CLASS_ID instead.';

--changeset baj:2229
--comment: IDS-3501: add audit entry record type for policy rules
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID)
VALUES (484, 'NDR policy rule created', 'ndr_policy_rule_created', 'A new NDR policy rule has been created',1);
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID)
VALUES (485, 'NDR policy rule modified', 'ndr_policy_rule_modified', 'A NDR policy rule has been modified',1);
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID)
VALUES (486, 'NDR policy rule deleted', 'ndr_policy_rule_deleted', 'A NDR policy rule has been deleted',1);

--changeset rha:2230
--comment: MEP-2618: remove obsolete certtool service type 'waf-virtualhost'
DELETE FROM CERTS.CERTIFICATE_SCOPE_TYPE WHERE ID = 0 AND name = 'waf-virtualhost';

--changeset cwa:2289
--comment: MC-30869: create network administrator permission
INSERT INTO AUTH.USER_ROLE (ID, NAME, DESCRIPTION, IS_INTERNAL, USER_ROLE_SCOPE_TYPE_ID)
VALUES (2014, 'mc-cust-network-admin', 'Network Administrator', 0, 1);
INSERT INTO AUTH.user_role2required_role (USER_ROLE_ID, REQUIRED_USER_ROLE_ID)
VALUES (2014, 1003);

--changeset rse:2290
--comment: TRIVIAL: Add dbprop mgmtaccess.boundary to enable SDP access via Boundary
INSERT INTO MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
VALUES (57170, 'mgmtaccess.boundary', 1, '0', '^[01]$', NULL, 'Enable management access via Boundary');

--changeset nis:2291
--comment: Adds zitadel ID columns for TT tables
ALTER TABLE TT.CHANGE_REQUEST ADD REQUESTER_ZITADEL_ID VARCHAR2(128) NULL;
ALTER TABLE TT.CHANGE_REQUEST ADD APPROVER_ZITADEL_ID VARCHAR2(128) NULL;
ALTER TABLE TT.EVENT ADD CONTACT_ZITADEL_ID VARCHAR2(128) NULL;
ALTER TABLE TT.EVENT ADD PEER_CONTACT_ZITADEL_ID VARCHAR2(128) NULL;
ALTER TABLE TT.TICKET ADD CONTACT_ZITADEL_ID VARCHAR2(128) NULL;
ALTER TABLE TT.TICKET ADD WORKER_ZITADEL_ID VARCHAR2(128) NULL;

--changeset ogl:2292
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM dba_users WHERE username='UAI'
CREATE USER "UAI" IDENTIFIED BY "xxxxxx" ACCOUNT LOCK
  DEFAULT TABLESPACE "USERS"
  TEMPORARY TABLESPACE "TEMP";

GRANT "MSS_SCHEMA_USER" TO "UAI";
ALTER USER "UAI" DEFAULT ROLE "MSS_SCHEMA_USER";

--changeset ogl:2293
--comment: DB-3143: UAI DB schema
grant references on stop.COMPANY to uai;

create table uai.app_group (
                             id number(10) not null,
                             name varchar2(128) not null,
                             company_id number(10) null,
                             description varchar2(512) null,
                             tags varchar2(512) null,
                             create_user varchar2(128) null,
                             created timestamp with time zone default systimestamp,
                             update_user varchar2(128) null,
                             updated timestamp with time zone default systimestamp,
                             constraint pk_app_group primary key (id),
                             constraint fk_appgroup_company foreign key (company_id) references stop.company(id)
);

comment on table uai.app_group is 'Unified Application Groups';
comment on column uai.app_group.company_id is 'null for shared groups';
comment on column uai.app_group.tags is 'Space separated list of tags';
comment on column uai.app_group.create_user is 'Zitadel ID or k8s service account';
comment on column uai.app_group.update_user is 'Zitadel ID or k8s service account';

create index uai.i_appgroup_company on uai.app_group (company_id);
create index uai.i_appgroup_name on uai.app_group lower(name);

create table uai.traffic_class (
                                 id number(10) not null,
                                 name varchar2(128) not null,
                                 description varchar2(512) null,
                                 constraint pk_traffic_class primary key (id)
);

comment on table uai.traffic_class is 'Traffic Class Masterdata';

create index uai.i_trafficclass_name on uai.traffic_class lower(name);

grant references on appid.app to uai;

create table uai.selector_quickid (
                                    id number(10) not null,
                                    quick_id number(10) null,
                                    traffic_class_id number(10) null,
                                    create_user varchar2(128) null,
                                    created timestamp with time zone default systimestamp,
                                    update_user varchar2(128) null,
                                    updated timestamp with time zone default systimestamp,
                                    constraint pk_selector_quickid primary key (id),
                                    constraint fk_selquickid_quick foreign key (quick_id) references appid.app(id),
                                    constraint fk_selquickid_tc foreign key (traffic_class_id) references uai.traffic_class(id)
);

comment on table uai.selector_quickid is 'QuickID Selectors for Apps';

create table uai.app (
                       id number(10) not null,
                       name varchar2(128) not null,
                       company_id number(10) null,
                       description varchar2(512) null,
                       vendor varchar2(128) null,
                       enabled number(1) default 1 not null,
                       website varchar2(256) null,
                       icon varchar2(256) null,
                       app_group_id number(10) not null,
                       include_app_id number(10) null,
                       tags varchar2(512) null,
                       selector_quickid_id number(10) null,
                       create_user varchar2(128) null,
                       created timestamp with time zone default systimestamp,
                       update_user varchar2(128) null,
                       updated timestamp with time zone default systimestamp,
                       constraint pk_app primary key (id),
                       constraint fk_app_company foreign key (company_id) references stop.company(id),
                       constraint fk_app_appgroup foreign key (app_group_id) references uai.app_group(id),
                       constraint fk_app_incapp foreign key (include_app_id) references uai.app(id),
                       constraint fk_app_selquickid foreign key (selector_quickid_id) references uai.selector_quickid(id)
);

comment on table uai.app is 'Unified Applications';
comment on column uai.app.company_id is 'null for shared apps';
comment on column uai.app.tags is 'Space separated list of tags';
comment on column uai.app.website is 'URL';
comment on column uai.app.icon is 'URL';
comment on column uai.app.create_user is 'Zitadel ID or k8s service account';
comment on column uai.app.update_user is 'Zitadel ID or k8s service account';

create index uai.i_app_company on uai.app (company_id);
create index uai.i_app_name on uai.app lower(name);
create index uai.i_app_inc on uai.app (include_app_id);
create index uai.i_app_appgroup on uai.app (app_group_id);
create index uai.i_app_quick on uai.app (selector_quickid_id);

grant references on fw.IP_GROUP to uai;
grant references on fw.SERVICE_GROUP to uai;

create table uai.selector (
                            id number(10) not null,
                            app_id number(10) not null,
                            position number(10) not null,
                            traffic_class_id number(10) not null,
                            dst_ip_group_id number(10) null,
                            dst_svc_group_id number(10) null,
                            create_user varchar2(128) null,
                            created timestamp with time zone default systimestamp,
                            update_user varchar2(128) null,
                            updated timestamp with time zone default systimestamp,
                            constraint pk_selector primary key (id),
                            constraint fk_sel_app foreign key (app_id) references uai.app(id),
                            constraint fk_sel_tc foreign key (traffic_class_id) references uai.traffic_class(id),
                            constraint fk_sel_dipg foreign key (dst_ip_group_id) references fw.ip_group(id),
                            constraint fk_sel_dscg foreign key (dst_svc_group_id) references fw.service_group(id)
);

comment on table uai.selector is 'Entity-based Selectors';
comment on column uai.selector.position is 'Ordering within the same app_id, starting with 1';
comment on column uai.selector.dst_ip_group_id is 'Automatic IP Group';
comment on column uai.selector.dst_svc_group_id is 'Automatic Service Group';

create index uai.i_selector_app_pos on uai.selector (app_id, position);
create index uai.i_selector_tc on uai.selector (traffic_class_id);
create index uai.i_selector_dipg on uai.selector (dst_ip_group_id);
create index uai.i_selector_dscg on uai.selector (dst_svc_group_id);

create table uai.selector_tos (
                                id number(10) not null,
                                selector_id number(10) not null,
                                mask number(3) not null,
                                value number(3) not null,
                                comments varchar2(512) null,
                                create_user varchar2(128) null,
                                created timestamp with time zone default systimestamp,
                                update_user varchar2(128) null,
                                updated timestamp with time zone default systimestamp,
                                constraint pk_selectortos primary key (id),
                                constraint fk_selectortos_sel foreign key (selector_id) references uai.selector(id)
);

comment on table uai.selector_tos is 'Type-of-Service / Differentiated-Services header field filters for Selectors';
comment on column uai.selector_tos.mask is 'The mask is ANDed with the packet TOS/DSCP value before comparing to value';
comment on column uai.selector_tos.value is 'The value to compare the masked TOS/DSCP value against';

create index uai.i_selectortos_sel on uai.selector_tos (selector_id);

create table uai.property (
                            id number(10) not null,
                            name varchar2(128) not null,
                            description varchar2(512) null,
                            regex varchar2(256) not null,
                            constraint pk_properties primary key (id)
);

comment on table uai.property is 'Properties Masterdata';
comment on column uai.property.name is 'Property name';
comment on column uai.property.regex is 'Regex to validate property values';

create index uai.i_properties_name on uai.property lower(name);

create table uai.uapp_prop (
                             id number(10) not null,
                             app_id number(10) not null,
                             property_id number(10) not null,
                             value varchar2(2048) not null,
                             create_user varchar2(128) null,
                             created timestamp with time zone default systimestamp,
                             update_user varchar2(128) null,
                             updated timestamp with time zone default systimestamp,
                             constraint pk_prop primary key (id),
                             constraint fk_prop_property foreign key (property_id) references uai.property(id),
                             constraint fk_prop_app foreign key (app_id) references uai.app(id)
);

comment on table uai.uapp_prop is 'Properties of Apps';

create index uai.i_uappprop_prop on uai.uapp_prop (property_id);
create index uai.i_uappprop_app on uai.uapp_prop (app_id);

--changeset mcg:2294
--comment: Updateable view that provides restricted access to certs.private_key
CREATE OR REPLACE FORCE VIEW CERTS.V_PRIVATE_KEY_RESTRICTED AS SELECT PK.ID, PK.GENERATED FROM CERTS.PRIVATE_KEY PK;
INSERT INTO CERTS."#JDO_PROPERTIES" (KEY, VALUE) VALUES ('V_PRIVATE_KEY_RESTRICTED.naming', 'none');

--changeset ogl:2295
--comment: DB-3143: UAI DB schema
create sequence uai.app_group_seq;
create sequence uai.app_seq;
create sequence uai.selector_quickid_seq;
create sequence uai.selector_seq;
create sequence uai.selector_tos_seq;
create sequence uai.uapp_prop_seq;

--changeset ogl:2296
--comment: DB-3143: master data
ALTER USER "UAI" QUOTA UNLIMITED ON "USERS";
insert into uai.traffic_class (id, name, description) values (100, 'raw', 'Traffic not classified as anything else.');
insert into uai.traffic_class (id, name, description) values (200, 'unfiltered', '(Internet) traffic that must go directly to the destination (from a client endpoint) without passing through ZTNA/MEP');
insert into uai.traffic_class (id, name, description) values (300, 'http-no-proxy', 'Traffic that is http but should never go through an http proxy.');
insert into uai.traffic_class (id, name, description) values (400, 'http-proxy', 'Traffic that is http and is compatible with an http proxy.');
insert into uai.traffic_class (id, name, description) values (500, 'http-wss', 'Traffic is an http websocket supported by the proxy.');

--changeset ogl:2297
--comment: DB-3143: appgroup members, unique indexes
create table uai.appgroup_member (
                                   app_group_id number(10) not null,
                                   app_id number(10) not null,
                                   constraint pk_appgroup_member primary key (app_group_id, app_id),
                                   constraint fk_agm_app foreign key (app_id) references uai.app(id),
                                   constraint fk_agm_appgroup foreign key (app_group_id) references uai.app_group(id)
);

comment on table uai.appgroup_member is 'Groups app into app groups';

create index uai.i_appgroupmember_app on uai.appgroup_member (app_id);

alter table uai.app drop column app_group_id;

create unique index uai.i_uappprop_un on uai.uapp_prop(app_id, property_id);

drop index uai.i_properties_name;
create unique index uai.i_properties_name on uai.property lower(name);

create unique index uai.i_selectortos_un on uai.selector_tos (selector_id, mask, value);

drop index uai.i_selector_app_pos;
create unique index uai.i_selector_un on uai.selector (app_id, position);

create unique index uai.i_app_un on uai.app (company_id, lower(name));

create unique index uai.i_appgroup_un on uai.app_group(company_id, lower(name));

--changeset ogl:2298
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM dba_users WHERE username='svc_certtool_cleanup'
CREATE USER svc_certtool_cleanup IDENTIFIED BY "xxxxxx" ACCOUNT LOCK
  DEFAULT TABLESPACE "USERS"
  TEMPORARY TABLESPACE "TEMP";

--changeset ogl:2299 contextFilter:dummyPasswords
--comment: only for login users, not for schema users
ALTER USER svc_certtool_cleanup IDENTIFIED BY "password" ACCOUNT UNLOCK;

--changeset ogl:2300
--comment: system, object grants for FOO
GRANT "MSS_LOGIN_USER" TO svc_certtool_cleanup;
ALTER USER svc_certtool_cleanup DEFAULT ROLE "MSS_LOGIN_USER";
GRANT SELECT,UPDATE,DELETE ON CERTS.PRIVATE_KEY TO svc_certtool_cleanup;
GRANT EXECUTE ON mcaudit.OSAG_AUDIT TO svc_certtool_cleanup;

--changeset ogl:2301
--comment: add permissions
grant select on certs.certificate TO svc_certtool_cleanup;
grant select on certs.csr TO svc_certtool_cleanup;

--changeset ogl:2302
--comment: DB-3143: schema grants for UAI
alter table uai.selector_quickid rename column quick_id to quickid_id;
alter table uai.uapp_prop rename to app_prop;
alter index uai.i_uappprop_prop rename to i_appprop_prop;
alter index uai.i_uappprop_app rename to i_appprop_app;
drop sequence uai.uapp_prop_seq;
create sequence uai.app_prop_seq;

grant select,insert,update,delete on uai.app_group to SVC_CONIFER;
grant select,insert,update,delete on uai.appgroup_member to SVC_CONIFER;
grant select,insert,update,delete on uai.app to SVC_CONIFER;
grant select on uai.traffic_class to SVC_CONIFER;
grant select,insert,update,delete on uai.selector_quickid to SVC_CONIFER;
grant select,insert,update,delete on uai.selector to SVC_CONIFER;
grant select,insert,update,delete on uai.selector_tos to SVC_CONIFER;
grant select on uai.property to SVC_CONIFER;
grant select,insert,update,delete on uai.app_prop to SVC_CONIFER;
grant select on uai.app_seq to SVC_CONIFER;
grant select on uai.app_group_seq to SVC_CONIFER;
grant select on uai.selector_seq to SVC_CONIFER;
grant select on uai.selector_quickid_seq to SVC_CONIFER;
grant select on uai.selector_tos_seq to SVC_CONIFER;
grant select on uai.app_prop_seq to SVC_CONIFER;

--changeset gul:2303
--comment: NC-1257: Add new dbprop migrate.xfrm
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (57180, 'migrate.xfrm', 1, '0', '^[01]$', NULL, 'Enable xfrm interfaces for all tunnels');

--changeset ogl:2304
--comment: missing permissions
grant select,update,delete on mc.HOST_MAINTENANCE_HISTORY to SVC_CONIFER;
grant select,update,delete on mc.CONNECTION_INTERRUPT_OPEN to SVC_CONIFER;
grant select,update,delete on mc.CONNECTION_INTERRUPT_CLOSED to SVC_CONIFER;

--changeset baj:2305
--comment: IDS-3577: Update ndr.zeek.interfaces to accept macros
UPDATE MSS.key k
SET k.REGEXP='^(?:(?:@if_NDR_[^\s]*|@if_LOCAL_[^\s]*|nsm0|proxy_tap|asa_int|eth\d{1,2}(?:\.\d{1,3})?))(?: (?:(?:@if_NDR_[^\s]*|@if_LOCAL_[^\s]*|nsm0|proxy_tap|asa_int|eth\d{1,2}(?:\.\d{1,3})?)))*$'
WHERE k.id=57123 and k.name='ndr.zeek.interfaces';

--changeset phm:2306
--comment: TRIVIAL: create db users to replace all-in-one-user "guma_server"
CREATE USER SVC_BALUCONSUMER_OPENVPN IDENTIFIED BY "xxxxxx" ACCOUNT LOCK
  DEFAULT TABLESPACE "USERS"
  TEMPORARY TABLESPACE "TEMP";

-- default login user grants
GRANT "MSS_LOGIN_USER" TO SVC_BALUCONSUMER_OPENVPN;
ALTER USER SVC_BALUCONSUMER_OPENVPN DEFAULT ROLE "MSS_LOGIN_USER";

-- app specific grants
GRANT SELECT,INSERT,UPDATE,DELETE on MSS.OPENVPN_INTERFACE to SVC_BALUCONSUMER_OPENVPN;
GRANT SELECT on MSS.NETWORK to SVC_BALUCONSUMER_OPENVPN;
GRANT SELECT on MSS.INTERFACE to SVC_BALUCONSUMER_OPENVPN;
GRANT SELECT on MSS.INTERFACE_ADDRESS to SVC_BALUCONSUMER_OPENVPN;
GRANT EXECUTE on MSS.OSAG_IP to SVC_BALUCONSUMER_OPENVPN;
-- to allow OSAG_IP.getnet(:ovpn...)?

--changeset phm:2307
--comment: TRIVIAL: create db users to replace all-in-one-user "guma_server"
CREATE USER SVC_BALUCONSUMER_AUTHUPDATE IDENTIFIED BY "xxxxxx" ACCOUNT LOCK
  DEFAULT TABLESPACE "USERS"
  TEMPORARY TABLESPACE "TEMP";

-- default login user grants
GRANT "MSS_LOGIN_USER" TO SVC_BALUCONSUMER_AUTHUPDATE;
ALTER USER SVC_BALUCONSUMER_AUTHUPDATE DEFAULT ROLE "MSS_LOGIN_USER";

-- app specific grants
GRANT EXECUTE on GUMA2.OSAG_IMPLICATION to SVC_BALUCONSUMER_AUTHUPDATE;
-- to allow CALL OSAG_IMPLICATION.auth_update(TO_DATE(?, 'DD/MON/YYYY HH24:MI:SS'), ?)

--changeset phm:2308 contextFilter:dummyPasswords
--comment: only for login users, not for schema users
ALTER USER SVC_BALUCONSUMER_OPENVPN IDENTIFIED BY "password" ACCOUNT UNLOCK;
ALTER USER SVC_BALUCONSUMER_AUTHUPDATE IDENTIFIED BY "password" ACCOUNT UNLOCK;

--changeset yuy:2309
--comment: IDS-3419: Drop DB Prop ndr.scandetection.interfaces
DELETE FROM MSS.VALUE v where v.key_id = (SELECT k.id from MSS.KEY k where k.name = 'ndr.scandetection.interfaces');
DELETE FROM MSS.KEY where name = 'ndr.scandetection.interfaces';

--changeset phm:2310 endDelimiter:/
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:0 select count(*) from SYS.DBA_OBJECTS where OWNER='AUTH' and OBJECT_NAME='OSAG_IMPLICATION' and OBJECT_TYPE='PACKAGE'
--comment: permission on copied package
create package AUTH.OSAG_IMPLICATION is
end OSAG_IMPLICATION;
/

--changeset phm:2311
--comment: assign permission to the package
DROP public synonym OSAG_IMPLICATION;
GRANT EXECUTE ON AUTH.OSAG_IMPLICATION TO GUMA_SERVER;
GRANT EXECUTE ON AUTH.OSAG_IMPLICATION TO SVC_BALUCONSUMER_AUTHUPDATE;

--changeset ogl:2312
--comment: DB-3143: UAI DB schema
alter table uai.selector drop column position;
alter table uai.selector_tos drop constraint fk_selectortos_sel;
alter table uai.selector_tos add constraint fk_selectortos_sel foreign key (selector_id) references uai.selector(id) on delete cascade;

--changeset ogl:2313
--comment: DB-3145: UAI dbprop
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, DESCRIPTION)
values (57181, 'portal.applications', 1, '0', '^[01]$', 'Enable Applications screen and disable QuickID in MCA2');

--changeset ogl:2314
--comment: DB-3111: ZTNA uai properties
insert into uai.property(ID, NAME, DESCRIPTION, REGEX)
values (1000, 'ztna.enabled', 'App is enabled in ZTNA', '^[01]$');

insert into uai.property(ID, NAME, DESCRIPTION, REGEX)
values (1001, 'ztna.type', 'Type of ZTNA application', '^(?:Network)$');

insert into uai.property(ID, NAME, DESCRIPTION, REGEX)
values (1002, 'ztna.services', 'Services where to deploy the app', '^[-a-z0-9]+$');

--changeset rse:2315
--comment: TRIVIAL: grant openvpn service user the read access to the required sequence
GRANT SELECT ON MSS.OPENVPNINTERFACE_SEQ TO SVC_BALUCONSUMER_OPENVPN;

--changeset gta:2316
--comment: RTNG-1190: add feature flag for single VTEIP per host
INSERT INTO MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
VALUES (57182, 'migrate.single_vteip', 1, '0', '^[01]$', NULL, 'Migrate to single VTEIP per host');

--changeset phm:2317
--comment: lock before dropping
ALTER USER "GUMA_SERVER" ACCOUNT LOCK;

--changeset yuy:2318
--comment: IDS-3586: create zeek dbprop for listening interface
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (57190, 'ndr.zeek.listen.internal', 1, '1', '^[01]$', NULL, 'listen on internal eth and lacp interfaces');

insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (57191, 'ndr.zeek.listen.proxy', 1, '0', '^[01]$', NULL, 'listen on proxy tap if exists');

insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (57192, 'ndr.zeek.listen.mep', 1, '0', '^[01]$', NULL, 'listen on asa_int if it exists');

insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (57193, 'ndr.zeek.listen.ifaces.excluded', 4, NULL, '^[A-Za-z0-9_.:]+(?: [A-Za-z0-9_.:]+)*$', NULL, 'space separated list of interfaces to exclude from monitoring (no macros)');

--changeset evv:2319
--comment: PRX-9515: Create a migration dbprop
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (57200, 'migrate.squid.geoip.v2', 1, '0', '^[01]$', NULL, 'Migrate CSWG to use geo-awareness v2 (cost-effective architecture)');

--changeset gta:2320
--comment: RTNG-1196: add backbone boolean column to VPN.PARTITION
ALTER TABLE VPN.PARTITION ADD BACKBONE NUMBER(1) DEFAULT 0 NOT NULL;
COMMENT ON COLUMN VPN.PARTITION.BACKBONE IS 'Indicates if this partition is a backbone partition.';

--changeset jkl:2321
--comment: RTNG-1189: Add MC Audit record types for WAN Configuration
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID)
VALUES (487, 'WAN configuration created', 'wan_configuration_created', 'A WAN configuration has been created', 1);

INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID)
VALUES (488, 'WAN configuration modified', 'wan_configuration_modified', 'A WAN configuration has been modified', 1);

INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID)
VALUES (489, 'WAN configuration deleted', 'wan_configuration_deleted', 'A WAN configuration has been deleted', 1);

--changeset alg:2323 tag:v2.2.0
--comment: This initial changeset servers as a placeholder
SELECT 1 FROM DUAL;

--changeset ogl:2324
--comment: DB-3113: ZTNA uai properties
delete from uai.property where id in (1000, 1001, 1002);
insert into uai.property(ID, NAME, DESCRIPTION, REGEX)
values (1001, 'ztna.type', 'Type of ZTNA application', '^(?:network)$');
insert into uai.property(ID, NAME, DESCRIPTION, REGEX)
values (1002, 'ztna.service_ids', 'Comma separated list of services where to deploy the app, or * for all', '^(?:(?:[0-9]+)(?:,[0-9]+)*)|\*$');

--changeset phm:2325
--comment: DB-2328: New Currencies in ISP Links
INSERT INTO MSS.CURRENCY (ID,SHORT) VALUES (59, 'AZN');

--changeset ogl:2326
--comment: restore ztna.enabled UAI prop
insert into uai.property(ID, NAME, DESCRIPTION, REGEX)
values (1000, 'ztna.enabled', 'App is enabled in ZTNA. Defaults to true if not present.', '^[01]$');

--changeset gks:2327
--comment: IDS-3480: Zeek cluster mode migration cleanup, remove dbprop migrate dbprop
DELETE FROM mss.value WHERE key_id IN (SELECT id FROM mss.key WHERE name = 'migrate.2025.zeek.clustermode');
DELETE FROM mss.key WHERE name = 'migrate.2025.zeek.clustermode';

--changeset ogl:2328
--comment: traffic classes display name
alter table uai.traffic_class add display_name varchar2(32) null;
update uai.traffic_class set display_name=name;
alter table uai.traffic_class modify display_name not null;

--changeset ssk:2329
--comment: CLOUD-842: add new record types for DPI apps
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID)
VALUES (490, 'DPI app created', 'dpi_app_created', 'A new DPI app has been created', 1);
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID)
VALUES (491, 'DPI app modified', 'dpi_app_modified', 'A DPI app has been modified', 1);
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID)
VALUES (492, 'DPI app deleted', 'dpi_app_deleted', 'A DPI app has been deleted', 1);

--changeset baj:2330
--comment: IDS-3559: Index precedence of ndr rules
ALTER TABLE NIDS.POLICY_RULE ADD CONSTRAINT POLICY_RULE_UK UNIQUE (COMPANY_ID, SERVICE_ID, PRECEDENCE);

--changeset ogl:2331
--comment: ORE-13539: decom BGPMON
drop user BGPMON;

--changeset ogl:2332
--comment: DB-3160: UAI optimistic locking
alter table uai.app add version number(10) default 0 not null;

--changeset alg:2333 endDelimiter:/
--comment: DB-3156 Adjust CLOBS
CREATE OR REPLACE PROCEDURE sys.copy_column_comment_same_table (
    p_schema_name IN VARCHAR2,
    p_table_name IN VARCHAR2,
    p_source_column_name IN VARCHAR2,
    p_target_column_name IN VARCHAR2
) AS
BEGIN
DECLARE
    v_comment VARCHAR2(4000);
BEGIN
-- Retrieve the comment from the source column
SELECT COMMENTS INTO v_comment
FROM ALL_COL_COMMENTS
WHERE OWNER = UPPER(p_schema_name)
  AND TABLE_NAME = UPPER(p_table_name)
  AND COLUMN_NAME = UPPER(p_source_column_name);

-- If a comment exists, apply it to the target column
IF v_comment IS NOT NULL THEN
EXECUTE IMMEDIATE 'COMMENT ON COLUMN ' || UPPER(p_schema_name) || '.' || UPPER(p_table_name) || '.' || UPPER(p_target_column_name) || ' IS :comment'
                USING v_comment;
END IF;
EXCEPTION
        WHEN NO_DATA_FOUND THEN
            DBMS_OUTPUT.PUT_LINE('No comment found for source column: ' || p_source_column_name);
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('Error occurred: ' || SQLERRM);
            RAISE_APPLICATION_ERROR(-20001, 'Error copying column comment from ' || p_source_column_name || ' to ' || p_target_column_name || ' : ' || SQLERRM) ;
END;
END;

--changeset alg:2334 endDelimiter:/
--comment: DB-3156 Adjust CLOBS

CREATE OR REPLACE PROCEDURE sys.migrate_clob_to_varchar2 (
    p_schema_name IN VARCHAR2,
    p_table_name IN VARCHAR2,
    p_column_name IN VARCHAR2,
    p_varchar2_length IN NUMBER DEFAULT 4096,
    p_default IN VARCHAR2 DEFAULT NULL
) AS
BEGIN
DECLARE
    v_temp_column_name VARCHAR2(30) := p_column_name || '_TEMP';
BEGIN
DBMS_OUTPUT.PUT_LINE('Migrating CLOB column ' || p_schema_name || '.' || p_table_name || '.' || p_column_name || ' to VARCHAR2(' || p_varchar2_length || ')');
DBMS_OUTPUT.PUT_LINE( 'Step 1: Adding temporary column ' || v_temp_column_name);
        -- Step 1: Add a new VARCHAR2 column
EXECUTE IMMEDIATE 'ALTER TABLE ' || UPPER(p_schema_name) || '.' || UPPER(p_table_name) || ' ADD ' || UPPER(v_temp_column_name) || ' VARCHAR2(' || p_varchar2_length || ') DEFAULT ' ||
    CASE
        WHEN p_default IS NOT NULL THEN '''' || REPLACE(p_default, '''', '''''') || ''''
        ELSE 'NULL'
    END;
-- Step 2: Copy data from CLOB to VARCHAR2
EXECUTE IMMEDIATE 'UPDATE ' || UPPER(p_schema_name) || '.' || UPPER(p_table_name) || ' SET ' || UPPER(v_temp_column_name) || ' = DBMS_LOB.SUBSTR(' || UPPER(p_column_name) || ', ' || p_varchar2_length || ', 1) WHERE ' || UPPER(p_column_name) || ' IS NOT NULL';
-- Step 3: Copy column comments

sys.copy_column_comment_same_table(
                p_schema_name => p_schema_name,
                p_table_name => p_table_name,
                p_source_column_name => p_column_name,
                p_target_column_name => v_temp_column_name
        );
        -- Step 4: Drop the original CLOB column
EXECUTE IMMEDIATE 'ALTER TABLE ' || UPPER(p_schema_name) || '.' || UPPER(p_table_name) || ' DROP COLUMN ' || UPPER(p_column_name);
-- Step 5: Rename the new VARCHAR2 column to the original column name
EXECUTE IMMEDIATE 'ALTER TABLE ' || UPPER(p_schema_name) || '.' || UPPER(p_table_name) || ' RENAME COLUMN ' || UPPER(v_temp_column_name) || ' TO ' || UPPER(p_column_name);
DBMS_OUTPUT.PUT_LINE('Migration completed successfully.');
EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('Error occurred: ' || SQLERRM);
            RAISE_APPLICATION_ERROR(-20001, 'Error migrating column ' || p_column_name || ' in table ' || p_table_name || ' AS ' || USER || ' : ' || SQLERRM) ;
END;
end;
/

--changeset alg:2335 endDelimiter:/
--comment: DB-3156 Migrate CLOB columns in AUTH.SOFT_TOKEN_ACTIVATION_CONFIG to VARCHAR2
begin
sys.migrate_clob_to_varchar2(
        p_schema_name => 'AUTH',
        p_table_name => 'SOFT_TOKEN_ACTIVATION_CONFIG',
        p_column_name => 'ACTIVATION_INSTALL_TEXT',
        p_varchar2_length => 4096
    );

sys.migrate_clob_to_varchar2(
            p_schema_name => 'AUTH',
            p_table_name => 'SOFT_TOKEN_ACTIVATION_CONFIG',
            p_column_name => 'ACTIVATION_SCAN_TEXT',
            p_varchar2_length => 4096
    );

sys.migrate_clob_to_varchar2(
            p_schema_name => 'AUTH',
            p_table_name => 'SOFT_TOKEN_ACTIVATION_CONFIG',
            p_column_name => 'ACTIVATION_PASSWORD_TEXT',
            p_varchar2_length => 4096
    );

sys.migrate_clob_to_varchar2(
            p_schema_name => 'AUTH',
            p_table_name => 'SOFT_TOKEN_ACTIVATION_CONFIG',
            p_column_name => 'ACTIVATION_ACTIVATE_TEXT',
            p_varchar2_length => 4096
    );
end;
/

--changeset ogl:2336
--comment: ORE-13611: avoid full-table scan
create index fw.IDX_ZONEMEMBER_IFC on FW.ZONE_MEMBER(INTERFACE_ID);

--changeset ogl:2337 tag:v2.2.2
--comment: Base of new container
SELECT 1 FROM DUAL;

--changeset ogl:2338 tag:v2.3.0
--comment: Base of new container
SELECT 1 FROM DUAL;

--changeset alg:2339
--comment: DB-3156 Drop CLOB migration procedures, to rename them with osag_ prefix
DROP PROCEDURE IF EXISTS sys.migrate_clob_to_varchar2;
DROP PROCEDURE IF EXISTS sys.copy_column_comment_same_table;

--changeset alg:2340 endDelimiter:/
--comment: DB-3156 Adjust CLOBS
CREATE OR REPLACE PROCEDURE sys.osag_copy_column_comment_same_table (
    p_schema_name IN VARCHAR2,
    p_table_name IN VARCHAR2,
    p_source_column_name IN VARCHAR2,
    p_target_column_name IN VARCHAR2
) AS
BEGIN
    DECLARE
        v_comment VARCHAR2(4000);
    BEGIN
        -- Retrieve the comment from the source column
        SELECT COMMENTS INTO v_comment
        FROM ALL_COL_COMMENTS
        WHERE OWNER = UPPER(p_schema_name)
          AND TABLE_NAME = UPPER(p_table_name)
          AND COLUMN_NAME = UPPER(p_source_column_name);

-- If a comment exists, apply it to the target column
        IF v_comment IS NOT NULL THEN
            EXECUTE IMMEDIATE 'COMMENT ON COLUMN ' || UPPER(p_schema_name) || '.' || UPPER(p_table_name) || '.' || UPPER(p_target_column_name) || ' IS :comment'
                USING v_comment;
        END IF;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            DBMS_OUTPUT.PUT_LINE('No comment found for source column: ' || p_source_column_name);
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('Error occurred: ' || SQLERRM);
            RAISE_APPLICATION_ERROR(-20001, 'Error copying column comment from ' || p_source_column_name || ' to ' || p_target_column_name || ' : ' || SQLERRM) ;
    END;
END;

--changeset alg:2341 endDelimiter:/
--comment: DB-3156 Adjust CLOBS

CREATE OR REPLACE PROCEDURE sys.osag_migrate_clob_to_varchar2 (
    p_schema_name IN VARCHAR2,
    p_table_name IN VARCHAR2,
    p_column_name IN VARCHAR2,
    p_varchar2_length IN NUMBER DEFAULT 4096,
    p_default IN VARCHAR2 DEFAULT NULL
) AS
BEGIN
    DECLARE
        v_temp_column_name VARCHAR2(30) := p_column_name || '_TEMP';
    BEGIN
        DBMS_OUTPUT.PUT_LINE('Migrating CLOB column ' || p_schema_name || '.' || p_table_name || '.' || p_column_name || ' to VARCHAR2(' || p_varchar2_length || ')');
        DBMS_OUTPUT.PUT_LINE( 'Step 1: Adding temporary column ' || v_temp_column_name);
        -- Step 1: Add a new VARCHAR2 column
        EXECUTE IMMEDIATE 'ALTER TABLE ' || UPPER(p_schema_name) || '.' || UPPER(p_table_name) || ' ADD ' || UPPER(v_temp_column_name) || ' VARCHAR2(' || p_varchar2_length || ') DEFAULT ' ||
                          CASE
                              WHEN p_default IS NOT NULL THEN '''' || REPLACE(p_default, '''', '''''') || ''''
                              ELSE 'NULL'
                              END;
-- Step 2: Copy data from CLOB to VARCHAR2
        EXECUTE IMMEDIATE 'UPDATE ' || UPPER(p_schema_name) || '.' || UPPER(p_table_name) || ' SET ' || UPPER(v_temp_column_name) || ' = DBMS_LOB.SUBSTR(' || UPPER(p_column_name) || ', ' || p_varchar2_length || ', 1) WHERE ' || UPPER(p_column_name) || ' IS NOT NULL';
-- Step 3: Copy column comments

        sys.osag_copy_column_comment_same_table(
                p_schema_name => p_schema_name,
                p_table_name => p_table_name,
                p_source_column_name => p_column_name,
                p_target_column_name => v_temp_column_name
        );
        -- Step 4: Drop the original CLOB column
        EXECUTE IMMEDIATE 'ALTER TABLE ' || UPPER(p_schema_name) || '.' || UPPER(p_table_name) || ' DROP COLUMN ' || UPPER(p_column_name);
-- Step 5: Rename the new VARCHAR2 column to the original column name
        EXECUTE IMMEDIATE 'ALTER TABLE ' || UPPER(p_schema_name) || '.' || UPPER(p_table_name) || ' RENAME COLUMN ' || UPPER(v_temp_column_name) || ' TO ' || UPPER(p_column_name);
        DBMS_OUTPUT.PUT_LINE('Migration completed successfully.');
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('Error occurred: ' || SQLERRM);
            RAISE_APPLICATION_ERROR(-20001, 'Error migrating column ' || p_column_name || ' in table ' || p_table_name || ' AS ' || USER || ' : ' || SQLERRM) ;
    END;
end;
/

--changeset alg:2342 endDelimiter:/
--comment: DB-3156 Migrate CLOB columns in DNSZONE to VARCHAR2
begin
    sys.osag_migrate_clob_to_varchar2(
            p_schema_name => 'MSS',
            p_table_name => 'DNS_ZONE',
            p_column_name => 'ZONEFILE_SIGNED',
            p_varchar2_length => 32767
    );

end;
/

--changeset ogl:2343
--comment: unmap MSG user from DX
drop table msg."#JDO_PROPERTIES";

--changeset alg:2344 endDelimiter:/
--comment: DB-3156 Bugfix copy column comment procedure does not support bind variables
CREATE OR REPLACE PROCEDURE sys.osag_copy_column_comment_same_table (
    p_schema_name IN VARCHAR2,
    p_table_name IN VARCHAR2,
    p_source_column_name IN VARCHAR2,
    p_target_column_name IN VARCHAR2
) AS
BEGIN
    DECLARE
        v_comment VARCHAR2(4000);
    BEGIN
        -- Retrieve the comment from the source column
        SELECT COMMENTS INTO v_comment
        FROM ALL_COL_COMMENTS
        WHERE OWNER = UPPER(p_schema_name)
          AND TABLE_NAME = UPPER(p_table_name)
          AND COLUMN_NAME = UPPER(p_source_column_name);

-- If a comment exists, apply it to the target column
        IF v_comment IS NOT NULL THEN
            EXECUTE IMMEDIATE 'COMMENT ON COLUMN ' || UPPER(p_schema_name) || '.' || UPPER(p_table_name) || '.' || UPPER(p_target_column_name) ||
                              ' IS ''' || REPLACE(v_comment, '''', '''''') || ''''
            ;
        END IF;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            DBMS_OUTPUT.PUT_LINE('No comment found for source column: ' || p_source_column_name);
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('Error occurred: ' || SQLERRM);
            RAISE_APPLICATION_ERROR(-20001, 'Error copying column comment from ' || p_source_column_name || ' to ' || p_target_column_name || ' : ' || SQLERRM) ;
    END;
END;
/

--changeset alg:2345
--comment: DB-3156 Migrate most CLOB columns in TT to VARCHAR2. Recompile dependent objects
ALTER PROCEDURE sys.osag_migrate_clob_to_varchar2 COMPILE;

--changeset gta:2346
--comment: unmap BGP schema
DROP table bgp."#JDO_PROPERTIES"

--changeset quv:2347
--comment: SRE-1528: Add new audit component for static route Self-Service
INSERT INTO MCAUDIT.COMPONENT (ID,NAME,SHORT,DESCRIPTION,SYSTEM_ID)
    VALUES (84,'Static Route Editor','static_route','Static Route Configuration',1);

--changeset jkl:2348
--comment: RTNG-1204: Add MAPPED_TO field to PATH_SELECTION_LINK_CLASS
ALTER TABLE APPID.PATH_SELECTION_LINK_CLASS ADD MAPPED_TO NUMBER(2,0) DEFAULT 1 NOT NULL;
COMMENT ON COLUMN APPID.PATH_SELECTION_LINK_CLASS.MAPPED_TO IS 'Mapping type: 1=single_interface, 2=multiple_interfaces, 3=backbone, 4=any_entity';

--changeset nis:2349
--comment: MC-30898: grants for DECOMM user to allow to decommission service with no more hosts
GRANT SELECT, DELETE, UPDATE on appid.wan_optimization_exception to DECOMM;
GRANT SELECT, DELETE, UPDATE on appid.optimization_pool_2_service to DECOMM;
GRANT SELECT, DELETE, UPDATE on mss.service_feature to DECOMM;
GRANT SELECT, DELETE, UPDATE on fw.scoped_ip_group_member to DECOMM;
GRANT SELECT, DELETE, UPDATE on fw.nat_section to DECOMM;
GRANT SELECT, DELETE, UPDATE on mc.mc_file_release to DECOMM;
GRANT SELECT, DELETE, UPDATE on tt.event_notification to DECOMM;
GRANT SELECT, DELETE, UPDATE on mss.value to DECOMM;
GRANT SELECT, DELETE, UPDATE on tt.ticket to DECOMM;
GRANT SELECT, DELETE, UPDATE on auth.user_service_scope to DECOMM;
GRANT SELECT, DELETE, UPDATE on mss.host2service to DECOMM;
GRANT SELECT, DELETE, UPDATE on mss.service to DECOMM;

--changeset nis:2350
--comment: MC-30898: grants for DECOMM user to allow to decommission service with no more hosts
GRANT SELECT on MSS.INSTALLATION_PROJECT_ITEM to DECOMM;
GRANT SELECT on MSS.SERVICE_FEATURE_STATE to DECOMM;
GRANT SELECT on MSS.SERVICE_OPTION_TYPE to DECOMM;

--changeset nis:2351
--comment: MC-30898: grants for DECOMM user to allow to decommission service with no more hosts
GRANT SELECT on MSS.CLOUD_REGION_INSTANCE to DECOMM;
GRANT SELECT on STOP.COMPANY to DECOMM;
GRANT SELECT on STOP.COMPANY_UNIT to DECOMM;
GRANT SELECT on MSS.CONFIGURATION_GROUP to DECOMM;
GRANT SELECT on MC.SERVICE_CONN_SLA_CONFIG to DECOMM;
GRANT SELECT on MSS.CVPN_SERVICE to DECOMM;
GRANT SELECT on APPID.PATH_SELECTION_PROFILE to DECOMM;
GRANT SELECT on MSS.PLATFORM_TYPE to DECOMM;
GRANT SELECT on MSS.SERVICE_LEVEL to DECOMM;
GRANT SELECT on MSS.SERVICE_TYPE to DECOMM;
GRANT SELECT on MSS.ADDRESS to DECOMM;

--changeset nis:2352
--comment: MC-30898: grants for DECOMM user to allow to decommission service with no more hosts
GRANT SELECT on VPN.PARTNER_STATIC_NET to DECOMM;

--changeset ogl:2353
--comment: remove schema MSG
drop user MSG CASCADE;

--changeset gul:2355
--comment: TRIVIAL: Add new dbprop migrate.dynip_buildsmall
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (57210, 'migrate.dynip_buildsmall', 1, '0', '^[01]$', NULL, 'Enables the use of the dynip buildsmall target for this hosts vpnpeers');

--changeset nis:2356
--comment: MC-30898: grants for DECOMM user to allow to decommission service with no more hosts
GRANT SELECT on AUTH.PERMISSION to DECOMM;

--changeset nis:2357
--comment: MC-30898: grants for DECOMM user to allow to decommission service with no more hosts
GRANT SELECT ON MSS.SERVICE_COMPONENT2SERVICE TO DECOMM;
GRANT SELECT ON MSS.SERVICE2GEO_LOCATION_IP TO DECOMM;
GRANT SELECT ON AUTH.MV_SERVICE_ACCESS TO DECOMM;
GRANT SELECT ON AUTH.USER_SERVICE_SCOPE TO DECOMM;
GRANT SELECT ON AUTH.ROLE TO DECOMM;
GRANT SELECT ON AUTH.LOGIN TO DECOMM;
GRANT SELECT ON APPID.OPTIMIZATION_POOL TO DECOMM;
GRANT SELECT ON APPID.PATH_SELECTION_PROFILE TO DECOMM;
GRANT SELECT ON FW.IP_GROUP_MEMBER TO DECOMM;
GRANT SELECT ON MSS.ISP_LINK TO DECOMM;
GRANT SELECT ON VPN.PARTNER_PHASE1 TO DECOMM;
GRANT SELECT ON CERTS.CERTIFICATE_USAGE TO DECOMM;
GRANT SELECT ON CERTS.CERTIFICATE TO DECOMM;
GRANT SELECT ON NIDS.NIDS_EVENT TO DECOMM;
GRANT SELECT ON NIDS.SCOPE TO DECOMM;

--changeset dnb:2358
--comment: MX-6178: Add new dbprop postfix.disable_recipient_restrictions
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (57211, 'postfix.disable_recipient_restrictions', 1, '0', '^[01]$', NULL, 'Disables smtpd_recipient_restrictions in postfix main.cf');

--changeset ang:2359
--comment: IDS-3558: Pull Ticura IoCs to sensor
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (57212, 'ndr.ioc.ticura', 1, '0', '^[01]$', NULL, 'Pull Ticura IoCs to sensor');

--changeset ogl:2360
grant select on stop.COMPANY_AM to SVC_CONIFER;
grant select on stop.COMPANY_TAM to SVC_CONIFER;

--changeset nis:2361
--comment: MC-30898: grants for DECOMM user to allow to decommission service with no more hosts
GRANT SELECT, DELETE, UPDATE ON MC.AVAILABILITY_REPORT TO DECOMM;

--changeset tte:2362
--comment: MC-30900: grants for DECOMM user to allow to decommission hosts with VPN memberships
GRANT SELECT, DELETE, UPDATE ON VPN.VPN_MEMBER to DECOMM;
GRANT SELECT, DELETE, UPDATE ON VPN.TUNNEL to DECOMM;
GRANT SELECT, DELETE, UPDATE ON VPN.TUNNEL_RATING to DECOMM;
GRANT SELECT, DELETE, UPDATE ON APPID.APP_OPTIMIZATION_HOST_ADDRESS to DECOMM;
GRANT SELECT ON VPN.PARTITION to DECOMM;

--changeset pas:2363
--comment: IDS-3585: Delete old bro dbprops
DELETE FROM mss.value WHERE key_id IN (SELECT id FROM mss.key WHERE name = 'bro.tickets');
DELETE FROM mss.key WHERE name = 'bro.tickets';
DELETE FROM mss.value WHERE key_id IN (SELECT id FROM mss.key WHERE name = 'migrate.2025.alertd');
DELETE FROM mss.key WHERE name = 'migrate.2025.alertd';
DELETE FROM mss.value WHERE key_id IN (SELECT id FROM mss.key WHERE name = 'nsm.scandetection');
DELETE FROM mss.key WHERE name = 'nsm.scandetection';
DELETE FROM mss.value WHERE key_id IN (SELECT id FROM mss.key WHERE name = 'nsm.scandetection.checkperiod');
DELETE FROM mss.key WHERE name = 'nsm.scandetection.checkperiod';
DELETE FROM mss.value WHERE key_id IN (SELECT id FROM mss.key WHERE name = 'nsm.scandetection.interfaces');
DELETE FROM mss.key WHERE name = 'nsm.scandetection.interfaces';
DELETE FROM mss.value WHERE key_id IN (SELECT id FROM mss.key WHERE name = 'nsm.scandetection.slowdown');
DELETE FROM mss.key WHERE name = 'nsm.scandetection.slowdown';
DELETE FROM mss.value WHERE key_id IN (SELECT id FROM mss.key WHERE name = 'nsm.scandetection.slowdown.mode');
DELETE FROM mss.key WHERE name = 'nsm.scandetection.slowdown.mode';
DELETE FROM mss.value WHERE key_id IN (SELECT id FROM mss.key WHERE name = 'nsm.scandetection.slowdown.rate');
DELETE FROM mss.key WHERE name = 'nsm.scandetection.slowdown.rate';

--changeset nis:2364
--comment: MC-30898: grants for DECOMM user to allow to decommission service with no more hosts
GRANT SELECT, DELETE, UPDATE ON FW.SUB_SECTION TO DECOMM;

--changeset ogl:2365
--comment: DB-3167: BGP schema no longer used
drop user bgp cascade;

--changeset nis:2366
--comment: MC-30898: grants for DECOMM user to allow to decommission service with no more hosts
GRANT SELECT, DELETE, UPDATE ON FW.source_nat_rule TO DECOMM;
GRANT SELECT, DELETE, UPDATE ON FW.destination_nat_rule TO DECOMM;
GRANT SELECT, DELETE, UPDATE ON VPN.TUNNEL_RATING_INTERVAL TO DECOMM;

--changeset nis:2367
--comment: MC-30898: grants for DECOMM user to allow to decommission service with no more hosts
GRANT SELECT, DELETE, UPDATE ON fw.scoped_ip_group_scope TO DECOMM;
GRANT SELECT, DELETE, UPDATE ON fw.recent_policy TO DECOMM;
GRANT SELECT, DELETE, UPDATE ON fw.rule TO DECOMM;
GRANT SELECT, DELETE, UPDATE ON certs.certificate_usage TO DECOMM;

--changeset syf:2368
--comment: API-Training: add new DB User for MCAUDIT API
CREATE USER SVC_MCAUDIT_API IDENTIFIED BY "xxxxxx" ACCOUNT LOCK
  DEFAULT TABLESPACE "USERS"
  TEMPORARY TABLESPACE "TEMP";

-- default login user grants
GRANT "MSS_LOGIN_USER" TO SVC_MCAUDIT_API;
ALTER USER SVC_MCAUDIT_API DEFAULT ROLE "MSS_LOGIN_USER";
-- app specific grants
GRANT SELECT ON MCAUDIT.RECORD TO SVC_MCAUDIT_API;
GRANT SELECT ON MCAUDIT.RECORD_TYPE TO SVC_MCAUDIT_API;
GRANT SELECT ON MCAUDIT.SEVERITY TO SVC_MCAUDIT_API;
GRANT SELECT ON MCAUDIT.COMPONENT TO SVC_MCAUDIT_API;
GRANT SELECT ON MCAUDIT.APPLICATION TO SVC_MCAUDIT_API;
GRANT SELECT ON MSS.OBJECT_TYPE TO SVC_MCAUDIT_API;

--changeset alg:2369 contextFilter:dummyPasswords
--comment: only for login users, not for schema users
ALTER USER SVC_MCAUDIT_API IDENTIFIED BY "password" ACCOUNT UNLOCK;

--changeset nis:2370
--comment: MC-30898: grants for DECOMM user to allow to decommission service with no more hosts
GRANT SELECT, DELETE, UPDATE ON fw.source_nat_rule2ticket TO DECOMM;
GRANT SELECT, DELETE, UPDATE ON fw.destination_nat_rule2ticket TO DECOMM;
GRANT SELECT, DELETE, UPDATE ON fw.rule2ticket TO DECOMM;

--changeset nis:2371
--comment: MC-30898: grants for DECOMM user to allow to decommission service with no more hosts
GRANT SELECT, DELETE, UPDATE ON fw.ip_group_member TO DECOMM;
GRANT SELECT, DELETE, UPDATE ON fw.che_snat_dst_zone TO DECOMM;
GRANT SELECT, DELETE, UPDATE ON fw.che_snat_src_zone TO DECOMM;
GRANT SELECT, DELETE, UPDATE ON fw.che_dnat_src_zone TO DECOMM;
GRANT SELECT, DELETE, UPDATE ON mail.batv_key TO DECOMM;
GRANT SELECT, DELETE, UPDATE ON mail.domain TO DECOMM;
GRANT SELECT, DELETE, UPDATE ON fyi.filter_service TO DECOMM;

--changeset nis:2372
--comment: MC-30898: grants for DECOMM user to allow to decommission service with no more hosts
GRANT SELECT, DELETE, UPDATE ON mss.cvpn_pool TO DECOMM;
GRANT SELECT, DELETE, UPDATE ON mss.cvpn_service TO DECOMM;

--changeset nis:2373
--comment: MC-30898: grants for DECOMM user to allow to decommission service with no more hosts
GRANT SELECT, DELETE, UPDATE ON mss.config_list TO DECOMM;
GRANT SELECT, DELETE, UPDATE ON mss.service_component2service TO DECOMM;
GRANT SELECT, DELETE, UPDATE ON nids.scope TO DECOMM;
GRANT SELECT, DELETE, UPDATE ON vpn.partner_phase1 TO DECOMM;
GRANT SELECT, DELETE, UPDATE ON vpn.partner_access_range TO DECOMM;
GRANT SELECT, DELETE, UPDATE ON vpn.partner_static_net TO DECOMM;
GRANT SELECT, DELETE, UPDATE ON prx.cloudswg_service2idac_service TO DECOMM;
GRANT SELECT, DELETE, UPDATE ON mss.service2geo_location_ip TO DECOMM;

--changeset alg:2375 tag:v2.3.1
--comment: Base of new container, containing CLOB migration procedures
SELECT 1 FROM dual;

--changeset nis:2376
--comment: MC-30898: grants for DECOMM user to allow to decommission service with no more hosts
GRANT SELECT, DELETE, UPDATE ON appid.path_selection_override_member TO DECOMM;

--changeset nis:2377
--comment: MC-30898: grants for DECOMM user to allow to decommission service with no more hosts
GRANT SELECT, DELETE, UPDATE ON MC.ISP_LINK_HISTORY TO DECOMM;
GRANT SELECT, DELETE, UPDATE ON MC.CONNECTION_INTERRUPT_OPEN TO DECOMM;
GRANT SELECT, DELETE, UPDATE ON NIDS.NIDS_EVENT TO DECOMM;
GRANT SELECT, DELETE, UPDATE ON TT.TICKET_RATING TO DECOMM;

--changeset alg:2378 tag:v2.3.2
--comment: Base of new container, containing CLOB migration procedures
SELECT 1 FROM dual;

--changeset alg:2379
--comment: BA-6419 Remove redundant columns with internal names
CREATE OR REPLACE VIEW BIREADER.V_TT_SERVICE_WINDOW as
SELECT ID, TICKET_ID, START_DATE, END_DATE, DESCRIPTION, TITLE, COMPANY_ID FROM TT.SERVICE_WINDOW;


--changeset ako:2381
--comment: NC-1256: Add new DB Prop qos.backbone
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (57220, 'qos.backbone', 1, 0, '^[01]$', 22, 'Enable QoS on the WAN backbone');

--changeset yuy:2382
--comment: IDS-3589: Cleanupndr.zeek.interfaces
DELETE FROM MSS.VALUE v where v.key_id = (SELECT k.id from MSS.KEY k where k.name = 'ndr.zeek.interfaces');
DELETE FROM MSS.KEY where name = 'ndr.zeek.interfaces';

--changeset pls:2383
--comment: AIX-150: Add EVENT_TYPE and EVENT_SOURCE grants to SVC_TICKET_EMBEDDINGS user
GRANT SELECT ON tt.EVENT_TYPE TO "SVC_TICKET_EMBEDDINGS";
GRANT SELECT ON tt.EVENT_SOURCE TO "SVC_TICKET_EMBEDDINGS";

--changeset emd:2384
--comment: MC-31108: Update mail template for sign off events
UPDATE TT.EVENT_TYPE_MESSAGE SET SUBJECT_TEMPLATE = '$#EMERGENCY#$Ticket ($#TICKET_SUBJECT#$) is waiting for sign-off', MESSAGE_TEMPLATE = 'This is an automatically generated email to inform you that
ticket $#TICKET_ID#$ requires sign-off. The ticket will not
proceed until the request in the ticket is approved by a
listed sign-off contact.

Subject: $#EMERGENCY#$$#TICKET_SUBJECT#$
Host:    $#HOST_NAME#$
Date:    $#EVENT_DATE#$
Details: $#PUBLIC_DETAILS_FIRST_LINE#$

To view the complete ticket in the Open Systems Customer Portal,
click here:
https://control.open.ch/mc/ticket/$#TICKET_ID#$' WHERE ID = 16;

--changeset ang:2210
--comment: IDS-3640: Add MC Audit record types for NDR signature group modification
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID)
VALUES (493, 'NDR', 'ndr_signature_group_modified', 'NDR signature group modified', 1);

--changeset ang:2211
--comment: IDS-3640: Clean up audit record type
update mcaudit.RECORD set RECORD_TYPE_ID=493 where RECORD_TYPE_ID in (477, 478);
delete from mcaudit.RECORD_TYPE where id in (477, 478);

--changeset ogl:2212
--comment: cpl grants
grant select on mail.POLICY_LIST_VALUE_TYPE to SVC_CONIFER;
grant select on mail.CUSTOM_POLICY_LIST_SEQ to SVC_CONIFER;
grant insert,update,delete on mail.CUSTOM_POLICY_LIST to SVC_CONIFER;
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID)
VALUES (494, 'Mail CPL added', 'mail_cpl_created', 'A mail CPL has been added', 1);
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID)
VALUES (495, 'Mail CPL deleted', 'mail_cpl_deleted', 'A mail CPL has been deleted', 1);

--changeset doi:2213
--comment: PRX-9708: add dbprop to configure the squid warning page expiration time
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (57221, 'squid.warningpage.expiration', 4, '720h', '^[1-9][0-9]*h$', NULL, 'Set the warning page session expiration. After this duration the session expires and the warning page will be displayed again.');

--changeset tte:2214
--comment: DB-2328: New Currency for ISP Links. Ticket ref 2303976
INSERT INTO MSS.CURRENCY (ID,SHORT) VALUES (60, 'DKK');

--changeset mta:2215
--comment: new record type for firewall auditor config changes
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID)
VALUES (496, 'Firewall Auditor modified', 'fw_auditor_modified', 'The configuration of the Firewall Auditor has been modified', 1);

--changeset alg:2400 tag:v2.3.3
--comment: Base of new container, containing updated CLOB migration procedures
SELECT 1 FROM dual;

--changeset alg:2401 tag:v2.3.4
--comment: Base of new container, containing updated CLOB migration procedures
SELECT 1 FROM dual;

--changeset jdv:2402
--comment: FW-6884: activate ipsets on default scope
update mss.KEY
set string_default='1'
where name='nfgen.ipset';

--changeset nop:2403
--comment: SRE-1583: Grant REFERENCES privilege on VPN.TUNNEL for SPEED_TESTS FK
GRANT REFERENCES ON VPN.TUNNEL TO MSS;
GRANT REFERENCES ON FW.IP_PROTOCOL TO MSS;

--changeset nop:2404
--comment: SRE-1583: Create table for ISP line speed test configurations
CREATE TABLE MSS.SPEED_TESTS (
    ID NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    INTERFACE_ID NUMBER NOT NULL,
    PROTOCOL_ID NUMBER NOT NULL,
    BANDWIDTH_UP NUMBER NOT NULL,
    BANDWIDTH_DOWN NUMBER NOT NULL,
    AZURE_REGION VARCHAR2(50),
    TUNNEL_ID NUMBER,
    IPERF_HOST VARCHAR2(255),
    NUM_STREAMS NUMBER NOT NULL,
    CRON_EXPR VARCHAR2(50) NOT NULL,
    ADJUST_QOS NUMBER(1) NOT NULL,
    CONSTRAINT FK_SPEED_TESTS_INTERFACE FOREIGN KEY (INTERFACE_ID) 
        REFERENCES MSS.INTERFACE(ID) ON DELETE CASCADE,
    CONSTRAINT FK_SPEED_TESTS_TUNNEL FOREIGN KEY (TUNNEL_ID) 
        REFERENCES VPN.TUNNEL(ID) ON DELETE CASCADE,
    CONSTRAINT FK_SPEED_TESTS_PROTOCOL FOREIGN KEY (PROTOCOL_ID) 
        REFERENCES FW.IP_PROTOCOL(ID),
    CONSTRAINT CHK_SPEED_TESTS_BW_UP CHECK (BANDWIDTH_UP >= 0),
    CONSTRAINT CHK_SPEED_TESTS_BW_DOWN CHECK (BANDWIDTH_DOWN >= 0),
    CONSTRAINT CHK_SPEED_TESTS_TARGET CHECK (
        AZURE_REGION IS NOT NULL OR 
        TUNNEL_ID IS NOT NULL OR 
        IPERF_HOST IS NOT NULL
    ),
    CONSTRAINT CHK_SPEED_TESTS_ADJUST_QOS CHECK (ADJUST_QOS IN (0, 1))
);

CREATE INDEX IDX_SPEED_TESTS_INTERFACE ON MSS.SPEED_TESTS(INTERFACE_ID); --- To resolve from the config API's interface node -> speedtests
CREATE INDEX IDX_SPEED_TESTS_TUNNEL ON MSS.SPEED_TESTS(TUNNEL_ID); --- To resolve from the config API's tunnel node -> speedtests

COMMENT ON TABLE MSS.SPEED_TESTS IS 'Configuration for scheduled ISP line speed tests';
COMMENT ON COLUMN MSS.SPEED_TESTS.ID IS 'Primary key';
COMMENT ON COLUMN MSS.SPEED_TESTS.INTERFACE_ID IS 'Foreign key to INTERFACE table';
COMMENT ON COLUMN MSS.SPEED_TESTS.PROTOCOL_ID IS 'Test protocol. tcp or udp are supported';
COMMENT ON COLUMN MSS.SPEED_TESTS.BANDWIDTH_UP IS 'Upload bandwidth limit in bits per second (0 = unlimited for tcp, isp bandwidth for udp)';
COMMENT ON COLUMN MSS.SPEED_TESTS.BANDWIDTH_DOWN IS 'Download bandwidth limit in bits per second (0 = unlimited for tcp, isp bandwidth for udp)';
COMMENT ON COLUMN MSS.SPEED_TESTS.AZURE_REGION IS 'Azure region for site-to-azure tests (nullable), exclusive to other target types';
COMMENT ON COLUMN MSS.SPEED_TESTS.TUNNEL_ID IS 'Tunnel ID for t4_tunnel tests (nullable), exclusive to other target types';
COMMENT ON COLUMN MSS.SPEED_TESTS.IPERF_HOST IS 'Iperf host for site-to-site tests (nullable), exclusive to other target types';
COMMENT ON COLUMN MSS.SPEED_TESTS.NUM_STREAMS IS 'Number of parallel iperf streams for the test';
COMMENT ON COLUMN MSS.SPEED_TESTS.CRON_EXPR IS 'Cron expression for scheduling the test';
COMMENT ON COLUMN MSS.SPEED_TESTS.ADJUST_QOS IS 'Adjust QoS configuration to 90% of the bandwidth after the test';


--changeset nop:2405
--comment: SRE-1583: Grant access to SPEED_TESTS table to CONIFER service user
GRANT SELECT, INSERT, UPDATE, DELETE ON MSS.SPEED_TESTS TO SVC_CONIFER;

--changeset nop:2406
--comment: TRIVIAL: disable code generation for speed test tables
INSERT INTO MSS."#JDO_PROPERTIES" ("KEY","VALUE") VALUES ('SPEED_TESTS.naming','none');

--changeset ssk:2407
--comment: CLOUD-1057: prevent duplicate subsections in FW.SUB_SECTION
ALTER TABLE FW.SUB_SECTION ADD CONSTRAINT U_SUB_SECTION UNIQUE (SECTION_ID, SUB_SECTION_TYPE_ID, SOURCE_SERVICE_ID);

--changeset gks:2408
--comment: IDS-3706: create and use dbprop ndr.ioc.custom
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (57222, 'ndr.ioc.custom', 1, '0', '^[01]$', NULL, 'Pull Custom IoCs to sensor');

--changeset ogl:2409
--comment: UPOL schema
CREATE USER "UPOL" IDENTIFIED BY "xxxxxx" ACCOUNT LOCK
  DEFAULT TABLESPACE "USERS"
  TEMPORARY TABLESPACE "TEMP";

GRANT "MSS_SCHEMA_USER" TO "UPOL";
ALTER USER "UPOL" DEFAULT ROLE "MSS_SCHEMA_USER";
ALTER USER "UPOL" QUOTA UNLIMITED ON "USERS";

--changeset ogl:2410
--comment: upol model
grant references on stop.company to upol;
grant references on uai.app to upol;
grant references on uai.app_group to upol;

create table upol.action_type (
                                id number(10) not null,
                                action varchar2(100) not null,
                                constraint pk_action_type primary key (id),
                                constraint un_action_type unique (action)
);

insert into upol.action_type(id, action) values (1, 'allow');
insert into upol.action_type(id, action) values (9, 'deny');

create table upol.egroup_type (
                                id number(10) not null,
                                name varchar2(100) not null,
                                constraint pk_egrouptype primary key (id),
                                constraint un_egrouptype_name unique (name)
);
insert into upol.egroup_type(id, name) values (1, 'users');
insert into upol.egroup_type(id, name) values (2, 'uapps');

-- only "automatic" groups, no name
create table upol.entity_group (
                                 id number(10) not null,
                                 company_id number(10) not null,
                                 group_type_id number(10) not null,
                                 constraint pk_entitygroup primary key (id),
                                 constraint fk_entitygroup_company foreign key (company_id) references stop.company(id),
                                 constraint fk_entitygroup_grouptype foreign key (group_type_id) references upol.egroup_type(id)
);
create sequence upol.entity_group_seq;
create index upol.i_entitygroup_company on upol.entity_group(company_id);

create table upol.egmember_type (
                                  id number(10) not null,
                                  name varchar2(100) not null,
                                  constraint pk_egmembertype primary key (id),
                                  constraint un_egmembertype_name unique (name)
);
insert into upol.egmember_type(id, name) values (1, 'user');
insert into upol.egmember_type(id, name) values (2, 'user_group');
insert into upol.egmember_type(id, name) values (3, 'uapp');
insert into upol.egmember_type(id, name) values (4, 'uapp_group');

create table upol.entity_group_member (
                                        id number(10) not null,
                                        entity_group_id number(10) not null,
                                        member_type_id number(10) not null,
                                        user_id varchar2(64) null,
                                        user_group_id varchar2(64) null,
                                        uapp_id number(10) null,
                                        uapp_group_id number(10) null,
                                        constraint pk_entitygroupmember primary key (id),
                                        constraint fk_entitygm_grp foreign key (entity_group_id) references upol.entity_group(id),
                                        constraint fk_entitygm_mtype foreign key (member_type_id) references upol.egmember_type(id),
                                        constraint fk_entitygm_app foreign key (uapp_id) references uai.app(id),
                                        constraint fk_entitygm_appgrp foreign key (uapp_group_id) references uai.app_group(id)
);
create index upol.i_entitygm_grp on upol.entity_group_member(entity_group_id);
create index upol.i_entitygm_user on upol.entity_group_member(user_id);
create index upol.i_entitygm_usergrp on upol.entity_group_member(user_group_id);
create index upol.i_entitygm_app on upol.entity_group_member(uapp_id);
create index upol.i_entitygm_appgrp on upol.entity_group_member(uapp_group_id);

create table upol.policy (
                           id number(10) not null,
                           company_id number(10) not null,
                           position number(10) not null,
                           name varchar2(256) null,
                           description varchar2(1000) null,
                           action_type_id number(10) not null,
                           enabled number(1) default 1 not null,
                           subject_entity_group_id number(10) not null,
                           object_entity_group_id number(10) not null,
                           create_user varchar2(128) null,
                           created timestamp with time zone default systimestamp,
                           update_user varchar2(128) null,
                           updated timestamp with time zone default systimestamp,
                           constraint pk_policy primary key (id),
                           constraint fk_policy_company foreign key (company_id) references stop.company(id),
                           constraint fk_policy_action foreign key (action_type_id) references upol.action_type(id),
                           constraint fk_policy_subj_eg foreign key (subject_entity_group_id) references upol.entity_group(id),
                           constraint fk_policy_obj_eg foreign key (object_entity_group_id) references upol.entity_group(id)
);

create sequence upol.policy_seq;
create index upol.i_policy_company on upol.policy(company_id);
create index upol.i_policy_subj on upol.policy(subject_entity_group_id);
create index upol.i_policy_obj on upol.policy(object_entity_group_id);

create table upol.property (
                             id number(10) not null,
                             name varchar2(256) not null,
                             description varchar2(1000) null,
                             regex varchar2(1000) null,
                             constraint pk_property primary key (id),
                             constraint un_property_name unique (name)
);

create table upol.policy_prop (
                                id number(10) not null,
                                policy_id number(10) not null,
                                property_id number(10) not null,
                                prop_value varchar2(4000) null,
                                constraint pk_policyprop primary key (id),
                                constraint fk_policyprop_policy foreign key (policy_id) references upol.policy(id),
                                constraint fk_policyprop_property foreign key (property_id) references upol.property(id)
);
create sequence upol.policyprop_seq;

grant select on upol.egmember_type to SVC_CONIFER;
grant select on upol.egroup_type to SVC_CONIFER;
grant select on upol.action_type to SVC_CONIFER;
grant select on upol.property to SVC_CONIFER;
grant select on upol.entity_group_seq to SVC_CONIFER;
grant select on upol.policy_seq to SVC_CONIFER;
grant select on upol.policyprop_seq to SVC_CONIFER;
grant select,insert,update,delete on upol.entity_group to SVC_CONIFER;
grant select,insert,update,delete on upol.entity_group_member to SVC_CONIFER;
grant select,insert,update,delete on upol.policy to SVC_CONIFER;
grant select,insert,update,delete on upol.policy_prop to SVC_CONIFER;

--changeset phm:2411
--comment: DB-3218: replace vpn_gui users
CREATE USER SVC_DBPROP IDENTIFIED BY "xxxxxx" ACCOUNT LOCK
  DEFAULT TABLESPACE "USERS"
  TEMPORARY TABLESPACE "TEMP";

--default login user grants
GRANT "MSS_LOGIN_USER" TO SVC_DBPROP;
ALTER USER SVC_DBPROP DEFAULT ROLE "MSS_LOGIN_USER";

--changeset phm:2412
-- app specific grants
GRANT EXECUTE ON MCAUDIT.OSAG_AUDIT TO SVC_DBPROP;
GRANT SELECT ON mss.key TO SVC_DBPROP;
GRANT SELECT ON mss.value TO SVC_DBPROP;
GRANT DELETE ON mss.value TO SVC_DBPROP;
GRANT INSERT ON mss.value TO SVC_DBPROP;
GRANT UPDATE ON mss.value TO SVC_DBPROP;
GRANT SELECT ON mss.value_seq TO SVC_DBPROP;
GRANT SELECT ON mss.value_write_permission TO SVC_DBPROP;
GRANT SELECT ON mss.permission_group TO SVC_DBPROP;
GRANT SELECT ON stop.company TO SVC_DBPROP;
GRANT SELECT ON vpn.vpn TO SVC_DBPROP;
GRANT SELECT ON mss.v_configuration_group_name TO SVC_DBPROP;
GRANT SELECT ON mss.host TO SVC_DBPROP;
GRANT SELECT ON mss.host2service TO SVC_DBPROP;
GRANT SELECT ON vpn.partition TO SVC_DBPROP;
GRANT SELECT ON vpn.vpn_member TO SVC_DBPROP;
GRANT SELECT ON mss.interface TO SVC_DBPROP;

--changeset phm:2413
--comment: DB-3218: replace vpn_gui users
CREATE USER SVC_BUILDJUN IDENTIFIED BY "xxxxxx" ACCOUNT LOCK
  DEFAULT TABLESPACE "USERS"
  TEMPORARY TABLESPACE "TEMP";

--default login user grants
GRANT "MSS_LOGIN_USER" TO SVC_BUILDJUN;
ALTER USER SVC_BUILDJUN DEFAULT ROLE "MSS_LOGIN_USER";

--changeset phm:2414
--comment: DB-3218: replace vpn_gui users
-- app specific grants
GRANT EXECUTE ON GUMA2.OSAG_GUMA TO SVC_BUILDJUN;
GRANT EXECUTE ON MCAUDIT.OSAG_AUDIT TO SVC_BUILDJUN;
GRANT EXECUTE ON MSS.OSAG_DBPROP TO SVC_BUILDJUN;
GRANT EXECUTE ON VPN.OSAG_VPN TO SVC_BUILDJUN;
GRANT SELECT ON MSS.APPLICATION_SEQUENCE TO SVC_BUILDJUN;
GRANT SELECT ON MSS.CASPORT_SEQ TO SVC_BUILDJUN;
GRANT SELECT ON MSS.CONFIG_LIST_SEQ TO SVC_BUILDJUN;
GRANT SELECT ON MSS.CONFIG_LIST_TYPE_SEQ TO SVC_BUILDJUN;
GRANT SELECT ON MSS.CONFIG_LIST_VALUE_SEQ TO SVC_BUILDJUN;
GRANT SELECT ON MSS.DNSZONE_SEQ TO SVC_BUILDJUN;
GRANT SELECT ON MSS.HARDWARE_SEQ TO SVC_BUILDJUN;
GRANT SELECT ON MSS.HOST_SEQUENCE TO SVC_BUILDJUN;
GRANT SELECT ON MSS.INTERFACE_DYNAMIC_IP_STATE_SEQ TO SVC_BUILDJUN;
GRANT SELECT ON MSS.INTERFACE_SEQUENCE TO SVC_BUILDJUN;
GRANT SELECT ON MSS.IPV6STATICROUTE_SEQ TO SVC_BUILDJUN;
GRANT SELECT ON MSS.LOGFWD_DAR_SECRET_SEQ TO SVC_BUILDJUN;
GRANT SELECT ON MSS.NETWORK_SEQUENCE TO SVC_BUILDJUN;
GRANT SELECT ON MSS.STATIC_ROUTE_SEQUENCE TO SVC_BUILDJUN;
GRANT SELECT ON MSS.UPLOAD_SEQUENCE TO SVC_BUILDJUN;
GRANT SELECT ON MSS.VALUE_SEQ TO SVC_BUILDJUN;
GRANT SELECT ON VPN.IPSECSECRET_SEQ TO SVC_BUILDJUN;
GRANT SELECT ON VPN.PARTITION_SEQUENCE TO SVC_BUILDJUN;
GRANT SELECT ON VPN.PARTNER_ACCESS_RANGE_SEQUENCE TO SVC_BUILDJUN;
GRANT SELECT ON VPN.PARTNER_CONTACT_SEQUENCE TO SVC_BUILDJUN;
GRANT SELECT ON VPN.PARTNER_IFACE_SEQUENCE TO SVC_BUILDJUN;
GRANT SELECT ON VPN.PARTNER_LOCATION_SEQUENCE TO SVC_BUILDJUN;
GRANT SELECT ON VPN.PARTNER_MONITORING_SEQUENCE TO SVC_BUILDJUN;
GRANT SELECT ON VPN.PARTNER_PHASE1_SEQUENCE TO SVC_BUILDJUN;
GRANT SELECT ON VPN.PARTNER_PHASE2_SEQUENCE TO SVC_BUILDJUN;
GRANT SELECT ON VPN.PARTNER_STATIC_NET_SEQUENCE TO SVC_BUILDJUN;
GRANT SELECT ON VPN.TUNNEL_RATING_SEQ TO SVC_BUILDJUN;
GRANT SELECT ON VPN.TUNNEL_SEQUENCE TO SVC_BUILDJUN;
GRANT SELECT ON VPN.VPN_MEMBER_SEQUENCE TO SVC_BUILDJUN;
GRANT SELECT ON VPN.VPN_SEQUENCE TO SVC_BUILDJUN;
GRANT SELECT ON AUTH.AUTHHOST TO SVC_BUILDJUN;
GRANT SELECT ON AUTH.AUTHHOST2AUTHSYS TO SVC_BUILDJUN;
GRANT SELECT ON AUTH.AUTHSECRET TO SVC_BUILDJUN;
GRANT SELECT ON AUTH.AUTHSYS TO SVC_BUILDJUN;
GRANT SELECT ON AUTH.LOGIN TO SVC_BUILDJUN;
GRANT SELECT ON AUTH.SHADOWAUTHHOST TO SVC_BUILDJUN;
GRANT SELECT ON AUTH.SHADOWAUTHHOST2AUTHHOST TO SVC_BUILDJUN;
GRANT SELECT ON AUTH.SYNCDOMAIN TO SVC_BUILDJUN;
GRANT SELECT ON CERTS.CERTIFICATE TO SVC_BUILDJUN;
GRANT SELECT ON CERTS.CERTIFICATE_SCOPE_TYPE TO SVC_BUILDJUN;
GRANT SELECT ON CERTS.CERTIFICATE_USAGE TO SVC_BUILDJUN;
GRANT SELECT ON CERTS.CSR TO SVC_BUILDJUN;
GRANT SELECT ON CERTS.PRIVATE_KEY TO SVC_BUILDJUN;
GRANT SELECT ON CERTS.SAN TO SVC_BUILDJUN;
GRANT SELECT ON ESP.MC_CENTER TO SVC_BUILDJUN;
GRANT SELECT ON ESP.MC_CENTER_CONTACT TO SVC_BUILDJUN;
GRANT SELECT ON FW.ACTION TO SVC_BUILDJUN;
GRANT SELECT ON FW.APP_GROUP TO SVC_BUILDJUN;
GRANT SELECT ON FW.APP_GROUP2APP TO SVC_BUILDJUN;
GRANT SELECT ON FW.APP_GROUP2APP_GROUP TO SVC_BUILDJUN;
GRANT SELECT ON FW.CHE_DNAT_SRC_ZONE TO SVC_BUILDJUN;
GRANT SELECT ON FW.CHE_SNAT_DST_ZONE TO SVC_BUILDJUN;
GRANT SELECT ON FW.CHE_SNAT_SRC_ZONE TO SVC_BUILDJUN;
GRANT SELECT ON FW.CONFIG_LOCK TO SVC_BUILDJUN;
GRANT SELECT ON FW.DESTINATION_NAT_RULE TO SVC_BUILDJUN;
GRANT SELECT ON FW.DESTINATION_NAT_RULE2TICKET TO SVC_BUILDJUN;
GRANT SELECT ON FW.DNS_OBJECT TO SVC_BUILDJUN;
GRANT SELECT ON FW.EXTERNAL_IP_LIST TO SVC_BUILDJUN;
GRANT SELECT ON FW.ICMPV6_TYPE TO SVC_BUILDJUN;
GRANT SELECT ON FW.ICMP_TYPE TO SVC_BUILDJUN;
GRANT SELECT ON FW.IP_ADDRESS TO SVC_BUILDJUN;
GRANT SELECT ON FW.IP_GROUP TO SVC_BUILDJUN;
GRANT SELECT ON FW.IP_GROUP_MEMBER TO SVC_BUILDJUN;
GRANT SELECT ON FW.IP_PROTOCOL TO SVC_BUILDJUN;
GRANT SELECT ON FW.IP_SERVICE TO SVC_BUILDJUN;
GRANT SELECT ON FW.IP_SERVICE2TCP_FLAG TO SVC_BUILDJUN;
GRANT SELECT ON FW.LOG_TARGET TO SVC_BUILDJUN;
GRANT SELECT ON FW.MEMBER_TYPE TO SVC_BUILDJUN;
GRANT SELECT ON FW.MEMBER_USAGE TO SVC_BUILDJUN;
GRANT SELECT ON FW.NAT_ACTION TO SVC_BUILDJUN;
GRANT SELECT ON FW.NAT_SECTION TO SVC_BUILDJUN;
GRANT SELECT ON FW.NAT_SECTION_TYPE TO SVC_BUILDJUN;
GRANT SELECT ON FW.POLICY TO SVC_BUILDJUN;
GRANT SELECT ON FW.RECENT_POLICY TO SVC_BUILDJUN;
GRANT SELECT ON FW.RULE TO SVC_BUILDJUN;
GRANT SELECT ON FW.RULE2TICKET TO SVC_BUILDJUN;
GRANT SELECT ON FW.SCOPED_IP_GROUP TO SVC_BUILDJUN;
GRANT SELECT ON FW.SCOPED_IP_GROUP_MEMBER TO SVC_BUILDJUN;
GRANT SELECT ON FW.SCOPED_IP_GROUP_MEMBER_TYPE TO SVC_BUILDJUN;
GRANT SELECT ON FW.SCOPED_IP_GROUP_SCOPE TO SVC_BUILDJUN;
GRANT SELECT ON FW.SECTION TO SVC_BUILDJUN;
GRANT SELECT ON FW.SERVICE_GROUP TO SVC_BUILDJUN;
GRANT SELECT ON FW.SERVICE_GROUP2IP_SERVICE TO SVC_BUILDJUN;
GRANT SELECT ON FW.SERVICE_GROUP2SERVICE_GROUP TO SVC_BUILDJUN;
GRANT SELECT ON FW.SOURCE_NAT_RULE TO SVC_BUILDJUN;
GRANT SELECT ON FW.SOURCE_NAT_RULE2TICKET TO SVC_BUILDJUN;
GRANT SELECT ON FW.SUB_SECTION TO SVC_BUILDJUN;
GRANT SELECT ON FW.SUB_SECTION_TYPE TO SVC_BUILDJUN;
GRANT SELECT ON FW.TCP_FLAG TO SVC_BUILDJUN;
GRANT SELECT ON FW.ZONE TO SVC_BUILDJUN;
GRANT SELECT ON FW.ZONE_MEMBER TO SVC_BUILDJUN;
GRANT SELECT ON GUMA2.EXTERNAL_SENSOR TO SVC_BUILDJUN;
GRANT SELECT ON GUMA2.PATTERN TO SVC_BUILDJUN;
GRANT SELECT ON GUMA2.SENSOR_TYPE TO SVC_BUILDJUN;
GRANT SELECT ON GUMA2.SIGNATURE TO SVC_BUILDJUN;
GRANT SELECT ON GUMA2.SYSLOG_FACILITY TO SVC_BUILDJUN;
GRANT SELECT ON GUMA2.SYSLOG_SEVERITY TO SVC_BUILDJUN;
GRANT SELECT ON MCAUDIT.RECORD TO SVC_BUILDJUN;
GRANT SELECT ON MSS.ADDRESS TO SVC_BUILDJUN;
GRANT SELECT ON MSS.APPLICATION TO SVC_BUILDJUN;
GRANT SELECT ON MSS.APPLICATION_GROUP TO SVC_BUILDJUN;
GRANT SELECT ON MSS.APPLICATION_TYPE TO SVC_BUILDJUN;
GRANT SELECT ON MSS.BLUEPRINT TO SVC_BUILDJUN;
GRANT SELECT ON MSS.BLUEPRINT_ENTRY TO SVC_BUILDJUN;
GRANT SELECT ON MSS.CAS_PORT TO SVC_BUILDJUN;
GRANT SELECT ON MSS.CITY TO SVC_BUILDJUN;
GRANT SELECT ON MSS.CLIENT_PROFILE_TYPE TO SVC_BUILDJUN;
GRANT SELECT ON MSS.CLOUD_REGION_INSTANCE TO SVC_BUILDJUN;
GRANT SELECT ON MSS.CONFIGURATION_GROUP TO SVC_BUILDJUN;
GRANT SELECT ON MSS.CONFIG_LIST TO SVC_BUILDJUN;
GRANT SELECT ON MSS.CONFIG_LIST_TYPE TO SVC_BUILDJUN;
GRANT SELECT ON MSS.CONFIG_LIST_VALUE TO SVC_BUILDJUN;
GRANT SELECT ON MSS.CONTINENT TO SVC_BUILDJUN;
GRANT SELECT ON MSS.COUNTRY TO SVC_BUILDJUN;
GRANT SELECT ON MSS.DNSSEC_ALGORITHM TO SVC_BUILDJUN;
GRANT SELECT ON MSS.DNSSEC_KEY TO SVC_BUILDJUN;
GRANT SELECT ON MSS.DNSSEC_KEY_DIGEST TO SVC_BUILDJUN;
GRANT SELECT ON MSS.DNSSEC_KEY_DIGEST_TYPE TO SVC_BUILDJUN;
GRANT SELECT ON MSS.DNSSEC_KEY_STATE TO SVC_BUILDJUN;
GRANT SELECT ON MSS.DNSSEC_KEY_TYPE TO SVC_BUILDJUN;
GRANT SELECT ON MSS.DNSSEC_PRIVATE_KEY TO SVC_BUILDJUN;
GRANT SELECT ON MSS.DNS_RECORD TO SVC_BUILDJUN;
GRANT SELECT ON MSS.DNS_SEARCH_DOMAIN_TYPE TO SVC_BUILDJUN;
GRANT SELECT ON MSS.HARDWARE TO SVC_BUILDJUN;
GRANT SELECT ON MSS.HARDWARE_DEPLOY_REASON TO SVC_BUILDJUN;
GRANT SELECT ON MSS.HARDWARE_TYPE TO SVC_BUILDJUN;
GRANT SELECT ON MSS.HOST TO SVC_BUILDJUN;
GRANT UPDATE ON MSS.HOST TO SVC_BUILDJUN;
GRANT SELECT ON MSS.HOST2SERVICE TO SVC_BUILDJUN;
GRANT DELETE ON MSS.HOST_SECRET TO SVC_BUILDJUN;
GRANT INSERT ON MSS.HOST_SECRET TO SVC_BUILDJUN;
GRANT SELECT ON MSS.HOST_SECRET TO SVC_BUILDJUN;
GRANT UPDATE ON MSS.HOST_SECRET TO SVC_BUILDJUN;
GRANT SELECT ON MSS.INSTALLATION_PROJECT TO SVC_BUILDJUN;
GRANT SELECT ON MSS.INSTALLATION_PROJECT_ITEM TO SVC_BUILDJUN;
GRANT SELECT ON MSS.INTERCONTINENTAL_LATENCY TO SVC_BUILDJUN;
GRANT SELECT ON MSS.INTERFACE TO SVC_BUILDJUN;
GRANT SELECT ON MSS.INTERFACE2ISP_LINK TO SVC_BUILDJUN;
GRANT SELECT ON MSS.INTERFACE_ADDRESS TO SVC_BUILDJUN;
GRANT SELECT ON MSS.INTERFACE_DYNAMIC_IP_STATE TO SVC_BUILDJUN;
GRANT SELECT ON MSS.INTERFACE_RIP_MODE TO SVC_BUILDJUN;
GRANT SELECT ON MSS.INTERFACE_SPEED TO SVC_BUILDJUN;
GRANT SELECT ON MSS.IPV6_ADDRESS TO SVC_BUILDJUN;
GRANT SELECT ON MSS.IPV6_PREFIX TO SVC_BUILDJUN;
GRANT SELECT ON MSS.IPV6_STATIC_ROUTE TO SVC_BUILDJUN;
GRANT SELECT ON MSS.ISP_LINK TO SVC_BUILDJUN;
GRANT SELECT ON MSS.ISP_LINK_TRANSPORT_MEDIA TO SVC_BUILDJUN;
GRANT SELECT ON MSS.KEY TO SVC_BUILDJUN;
GRANT SELECT ON MSS.KEY_TYPE TO SVC_BUILDJUN;
GRANT SELECT ON MSS.LOGFWD_DAR_SECRET TO SVC_BUILDJUN;
GRANT SELECT ON MSS.NAT_IIFACE_2_OIFACE TO SVC_BUILDJUN;
GRANT SELECT ON MSS.NETWORK TO SVC_BUILDJUN;
GRANT SELECT ON MSS.OPENVPN_INTERFACE TO SVC_BUILDJUN;
GRANT SELECT ON MSS.OPERATING_SYSTEM TO SVC_BUILDJUN;
GRANT SELECT ON MSS.PERMISSION_GROUP TO SVC_BUILDJUN;
GRANT SELECT ON MSS.PING_IP TO SVC_BUILDJUN;
GRANT SELECT ON MSS.PLATFORM_TYPE TO SVC_BUILDJUN;
GRANT SELECT ON MSS.PROJECT_ITEM_STATUS TO SVC_BUILDJUN;
GRANT SELECT ON MSS.SERVICE TO SVC_BUILDJUN;
GRANT SELECT ON MSS.SERVICE_COMPONENT TO SVC_BUILDJUN;
GRANT INSERT ON MSS.SERVICE_COMPONENT2SERVICE TO SVC_BUILDJUN;
GRANT SELECT ON MSS.SERVICE_COMPONENT2SERVICE TO SVC_BUILDJUN;
GRANT UPDATE ON MSS.SERVICE_COMPONENT2SERVICE TO SVC_BUILDJUN;
GRANT SELECT ON MSS.SERVICE_OPTION_TYPE TO SVC_BUILDJUN;
GRANT SELECT ON MSS.SERVICE_TYPE TO SVC_BUILDJUN;
GRANT SELECT ON MSS.SPLIT_TUNNELING_TYPE TO SVC_BUILDJUN;
GRANT SELECT ON MSS.STATIC_ROUTE TO SVC_BUILDJUN;
GRANT SELECT ON MSS.TAXCODE TO SVC_BUILDJUN;
GRANT DELETE ON MSS.UPLOAD TO SVC_BUILDJUN;
GRANT INSERT ON MSS.UPLOAD TO SVC_BUILDJUN;
GRANT SELECT ON MSS.UPLOAD TO SVC_BUILDJUN;
GRANT UPDATE ON MSS.UPLOAD TO SVC_BUILDJUN;
GRANT SELECT ON MSS.UPLOAD_TYPE TO SVC_BUILDJUN;
GRANT SELECT ON MSS.VALUE TO SVC_BUILDJUN;
GRANT SELECT ON MSS.VALUE_WRITE_PERMISSION TO SVC_BUILDJUN;
GRANT SELECT ON STOP.COMPANY TO SVC_BUILDJUN;
GRANT SELECT ON STOP.COMPANY_TAM TO SVC_BUILDJUN;
GRANT SELECT ON STOP.COMPANY_UNIT TO SVC_BUILDJUN;
GRANT SELECT ON STOP.CONTACT TO SVC_BUILDJUN;
GRANT SELECT ON SVC_ZEROTRUST.ZTNA_TENANT TO SVC_BUILDJUN;
GRANT SELECT ON VPN.IPSEC_SECRET TO SVC_BUILDJUN;
GRANT SELECT ON VPN.PARTITION TO SVC_BUILDJUN;
GRANT SELECT ON VPN.PARTNER_ACCESS_RANGE TO SVC_BUILDJUN;
GRANT SELECT ON VPN.PARTNER_CONTACT TO SVC_BUILDJUN;
GRANT SELECT ON VPN.PARTNER_IFACE TO SVC_BUILDJUN;
GRANT SELECT ON VPN.PARTNER_LOCATION TO SVC_BUILDJUN;
GRANT SELECT ON VPN.PARTNER_MONITORING TO SVC_BUILDJUN;
GRANT SELECT ON VPN.PARTNER_PHASE1 TO SVC_BUILDJUN;
GRANT SELECT ON VPN.PARTNER_PHASE2 TO SVC_BUILDJUN;
GRANT SELECT ON VPN.PARTNER_STATIC_NET TO SVC_BUILDJUN;
GRANT SELECT ON VPN.TUNNEL TO SVC_BUILDJUN;
GRANT SELECT ON VPN.TUNNEL_RATING TO SVC_BUILDJUN;
GRANT SELECT ON VPN.TUNNEL_RATING_INTERVAL TO SVC_BUILDJUN;
GRANT SELECT ON VPN.VPN TO SVC_BUILDJUN;
GRANT SELECT ON VPN.VPN_MEMBER TO SVC_BUILDJUN;
GRANT SELECT ON AUTH.V_S_LOGIN TO SVC_BUILDJUN;
GRANT SELECT ON MSS.TIME_ZONE TO SVC_BUILDJUN;
GRANT SELECT ON MSS.V_CONFIGURATION_GROUP_NAME TO SVC_BUILDJUN;
GRANT SELECT ON MSS.V_HOST_KEY_VALUE TO SVC_BUILDJUN;
GRANT SELECT ON MSS.V_NONFAKE_INTERFACE TO SVC_BUILDJUN;

--changeset phm:2415
--comment: DB-3218: replace vpn_gui users
CREATE USER SVC_SSHSYNC IDENTIFIED BY "xxxxxx" ACCOUNT LOCK
  DEFAULT TABLESPACE "USERS"
  TEMPORARY TABLESPACE "TEMP";

--default login user grants
GRANT "MSS_LOGIN_USER" TO SVC_SSHSYNC;
ALTER USER SVC_SSHSYNC DEFAULT ROLE "MSS_LOGIN_USER";

--changeset phm:2416
--comment: DB-3218: replace vpn_gui users
-- app specific grants
GRANT SELECT ON MSS.HOST TO SVC_SSHSYNC;
GRANT UPDATE ON MSS.HOST TO SVC_SSHSYNC;
GRANT SELECT ON MSS.HOST2SERVICE TO SVC_SSHSYNC;
GRANT SELECT ON MSS.OPERATING_SYSTEM TO SVC_SSHSYNC;
GRANT SELECT ON MSS.SERVICE TO SVC_SSHSYNC;
GRANT SELECT ON MSS.SERVICE_TYPE TO SVC_SSHSYNC;
GRANT SELECT ON MSS.V_HOST_KEY_VALUE TO SVC_SSHSYNC;
GRANT SELECT ON MSS.INTERFACE TO SVC_SSHSYNC;
GRANT SELECT ON MSS.INTERFACE_ADDRESS TO SVC_SSHSYNC;
GRANT SELECT ON MSS.IPV6_ADDRESS TO SVC_SSHSYNC;

--changeset mlo:2417 endDelimiter:/
--comment: MC-31176: consider vte_ interfaces as fake

create or replace force view MSS.V_NONFAKE_INTERFACE as
SELECT "ID","NAME","VERSION","HOST_ID","IP_ADDRESS","MGMTACCESS","MTU","EXTERNAL","NETWORK_ID","QOS_BWIN","QOS_BWOUT","OSPF_AREA","OSPF_AUTHKEY","OSPF_COST","OSPF_DONT_PROPAGATE_ROUTE","OSPF_HELLOINTERVAL","OSPF_DEADINTERVAL","INTERFACE_RIP_MODE_ID","INTERFACE_RIP_AUTHKEY","INTERFACE_SPEED_ID","ANTI_SPOOFING_IP_GROUP_ID","DISABLE_ANTI_SPOOFING_CHECKS","INHERIT_TOS","AUTHOR","DESCRIPTION","COMMENTS","OSPF6_AREA","OSPF6_COST","OSPF6_HELLOINTERVAL","OSPF6_DEADINTERVAL","INTERFACE_RIPNG_MODE_ID","DYNAMIC_IPV4","HIDING_NAT","NAT_ADDRESS_ID","IS_CLUSTER_MANAGED","BANDWIDTH_CONTROL_PROFILE_ID","PATH_SELECTION_LINK_CLASS_ID","OSPF_P2MP","PATH_SELECTION_DISABLED","PUBLIC_NAT_IP"
FROM mss.interface
WHERE name NOT LIKE 'fake%' AND
    name NOT LIKE 'lbvirt%' AND
    name NOT LIKE 'vte_%' AND
    ip_address != 0
/

--changeset ssk:2417
--comment: CLOUD-833: add table to store completed firewall changes
CREATE SEQUENCE FW.CHANGE_SEQ;
CREATE TABLE FW.CHANGE (
    ID NUMBER NOT NULL,
    COMPANY_ID NUMBER(22, 0) NOT NULL,
    CUSTOMER_REFERENCE VARCHAR2(64 BYTE),
    DESCRIPTION VARCHAR2(1024 BYTE),
    TICKET_ID NUMBER(22, 0),
    SUMMARY_BLOB_NAME VARCHAR2(256 CHAR) NOT NULL,
    AUTHOR_USER VARCHAR2(128),
    AUTHORED TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT PK_CHANGE PRIMARY KEY (ID),
    CONSTRAINT FK_CHANGE_COMPANY FOREIGN KEY (COMPANY_ID) REFERENCES STOP.COMPANY(ID),
    CONSTRAINT FK_CHANGE_TICKET FOREIGN KEY (TICKET_ID) REFERENCES TT.TICKET(ID)
);
COMMENT ON TABLE FW.CHANGE IS 'Stores historic firewall change metadata. The change summary itself is stored as JSON in Azure Blob Storage.';
COMMENT ON COLUMN FW.CHANGE.ID IS 'Surrogate primary key.';
COMMENT ON COLUMN FW.CHANGE.COMPANY_ID IS 'The company for which the change was made.';
COMMENT ON COLUMN FW.CHANGE.CUSTOMER_REFERENCE IS 'A customer-internal reference for the change.';
COMMENT ON COLUMN FW.CHANGE.DESCRIPTION IS 'Customer-provided description of the change.';
COMMENT ON COLUMN FW.CHANGE.TICKET_ID IS 'Optional reference to a ticket associated with the change.';
COMMENT ON COLUMN FW.CHANGE.SUMMARY_BLOB_NAME IS 'The name of the blob storing the change summary in Azure Blob Storage.';
COMMENT ON COLUMN FW.CHANGE.AUTHOR_USER IS 'The user who authored the change at the time it was made.';
COMMENT ON COLUMN FW.CHANGE.AUTHORED IS 'Timestamp when the change was made.';
CREATE INDEX FW.IDX_CHANGE_TICKET ON FW.CHANGE (TICKET_ID);
CREATE INDEX FW.IDX_CHANGE_COMPANYCUSTREF ON FW.CHANGE (COMPANY_ID, CUSTOMER_REFERENCE);
CREATE INDEX FW.IDX_CHANGE_COMPANYAUTHORED ON FW.CHANGE (COMPANY_ID, AUTHORED);
insert into FW."#JDO_PROPERTIES" ("KEY","VALUE") VALUES ('CHANGE.naming','none');

--changeset diw:2419
--comment: CLOUD-1000: Add new tables for shared app maintenance metadata
CREATE TABLE FW.SYNC_METADATA (
    ID NUMBER NOT NULL,
    MAINTENANCE_PROCESS VARCHAR2(255) NOT NULL,
    LAST_SYNCHRONIZED timestamp with time zone default systimestamp,
    CONSTRAINT SYNCMD_UQ1 UNIQUE (MAINTENANCE_PROCESS),
    CONSTRAINT PK_SYNCMD PRIMARY KEY (ID)
);
COMMENT ON TABLE FW.SYNC_METADATA IS 'Stores metadata for shared app maintenance processes.';
COMMENT ON COLUMN FW.SYNC_METADATA.MAINTENANCE_PROCESS IS 'The unique name of the maintenance process (e.g., a sync job name).';
COMMENT ON COLUMN FW.SYNC_METADATA.LAST_SYNCHRONIZED IS 'Last successful synchronization. This does not imply that the related app or ipgroup were changed.';
CREATE SEQUENCE FW.SYNC_METADATA_SEQ;

CREATE TABLE FW.SYNC_METADATA2IPGROUP (
    IPGROUP_ID NUMBER(11,0) NOT NULL,
    SYNC_METADATA_ID NUMBER(11,0) NOT NULL,
    CONSTRAINT FK_IPGROUPSYNCMD_IPGROUP FOREIGN KEY (IPGROUP_ID) REFERENCES FW.IP_GROUP (ID),
    CONSTRAINT FK_IPGROUPSYNCMD_SYNCMD FOREIGN KEY (SYNC_METADATA_ID) REFERENCES FW.SYNC_METADATA (ID),
    CONSTRAINT PK_IPGROUPSYNCMD PRIMARY KEY (IPGROUP_ID, SYNC_METADATA_ID)
);
COMMENT ON TABLE FW.SYNC_METADATA2IPGROUP IS 'Associates an IP group with a maintenance process.';

CREATE TABLE FW.SYNC_METADATA2APP (
    APP_ID NUMBER(11,0) NOT NULL,
    SYNC_METADATA_ID NUMBER(11,0) NOT NULL,
    CONSTRAINT FK_APPSYNCMD_APP FOREIGN KEY (APP_ID) REFERENCES APPID.APP (ID),
    CONSTRAINT FK_APPSYNCMD_SYNCMD FOREIGN KEY (SYNC_METADATA_ID) REFERENCES FW.SYNC_METADATA (ID),
    CONSTRAINT PK_SMD2APP_APP_META PRIMARY KEY (APP_ID, SYNC_METADATA_ID)
);
COMMENT ON TABLE FW.SYNC_METADATA2APP IS 'Associates an application with a maintenance process.';

INSERT INTO FW."#JDO_PROPERTIES" ("KEY","VALUE") VALUES ('SYNC_METADATA.naming','none');
INSERT INTO FW."#JDO_PROPERTIES" ("KEY","VALUE") VALUES ('SYNC_METADATA2IPGROUP.naming','none');
INSERT INTO FW."#JDO_PROPERTIES" ("KEY","VALUE") VALUES ('SYNC_METADATA2APP.naming','none');

--changeset ogl:2420
--comment: missing sequence
create sequence upol.entity_group_member_seq;
grant select on upol.entity_group_member_seq to SVC_CONIFER;
comment on table upol.action_type is 'Rule actions types masterdata';
comment on table upol.egroup_type is 'Entity group types masterdata';
comment on table upol.egmember_type is 'Entity group member types masterdata';
comment on table upol.property is 'Policy properties masterdata';
comment on table upol.entity_group is 'Automatic entity groups used for policies';
comment on table upol.entity_group_member is 'Members of automatic entity groups. Only one of user_id, user_group_id, uapp_id, uapp_group_id is set depending on member_type_id';
comment on table upol.policy is 'Policies/Rules defining access between entity groups';
comment on table upol.policy_prop is 'Service specific properties assigned to policies';
comment on column upol.policy.position is 'Order of rules within a company, lower numbers have higher priority';

--changeset ako:2421
--comment: NC-1300: Adjust dhcp-fwd.clientinterfaces dbprop regex to not allow virtual interfaces
update MSS.KEY set REGEXP='^(eth|lacp)[1-9]?[0-9](\.[1-9][0-9]{0,3})?(| (eth|lacp)[1-9]?[0-9](\.[1-9][0-9]{0,3})?)*$' where name = 'dhcp-fwd.clientinterfaces';

--changeset quv:2422
--comment: SRE-1584: Add audit record types for speed test operations
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID)
VALUES (497, 'Speed test created', 'speedtest_add', 'A speed test configuration has been created', 1);

INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID)
VALUES (498, 'Speed test deleted', 'speedtest_delete', 'A speed test configuration has been deleted', 1);

--changeset tho:2423
--comment: NC-1245: dhcp-fwd migration mostly completed
update mss.KEY
set string_default='1'
where name='migrate.2025.dhcp-relay';

--changeset doi:2424
--comment: PRX-9735: Grant access to TIM tables to config-api service user 
GRANT SELECT, INSERT, UPDATE, DELETE ON TIM.BLACKLIST_VALUE TO SVC_CONIFER;
GRANT SELECT ON TIM.BLACKLIST_VALUE_CATEGORY TO SVC_CONIFER;
GRANT SELECT ON TIM.BLACKLIST_VALUE_TYPE TO SVC_CONIFER;
GRANT SELECT, INSERT, UPDATE, DELETE ON TIM.BLACKLIST_ZONE_FILE TO SVC_CONIFER;
GRANT SELECT, INSERT, UPDATE, DELETE ON TIM.EXCLUSION_LIST_VALUE TO SVC_CONIFER;
GRANT SELECT ON TIM.EXCLUSION_LIST_VALUE_TYPE TO SVC_CONIFER;
GRANT SELECT ON TIM.BLACKLIST_VALUE_SEQ TO SVC_CONIFER;
GRANT SELECT ON TIM.BLACKLIST_ZONE_FILE_SEQ TO SVC_CONIFER;
GRANT SELECT ON TIM.EXCLUSION_LIST_VALUE_SEQ TO SVC_CONIFER;

--changeset jah:2421
--comment: BE-1623: Add new DB Prop migrate.2026.artifactsurl
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (57230, 'migrate.2026.artifactsurl', 1, '0', '^[01]$', 22, 'Migration to OSAG controlled FQDN for our software repository.');

--changeset mta:2426
--comment: grant missing permissions for fwss and app maintenance to SVC_CONIFER
GRANT SELECT, INSERT ON FW.CHANGE TO SVC_CONIFER;
GRANT SELECT ON FW.CHANGE_SEQ TO SVC_CONIFER;
GRANT SELECT, INSERT, UPDATE, DELETE ON FW.SYNC_METADATA TO SVC_CONIFER;
GRANT SELECT, INSERT, UPDATE, DELETE ON FW.SYNC_METADATA2IPGROUP TO SVC_CONIFER;
GRANT SELECT, INSERT, UPDATE, DELETE ON FW.SYNC_METADATA2APP TO SVC_CONIFER;
GRANT SELECT ON FW.SYNC_METADATA_SEQ TO SVC_CONIFER;

--changeset gpe:2427
--comment: FW-7101: Add new DB Prop fw.app.pace2.poc for DPI FW PoC
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (57240, 'fw.app.pace2.poc', 1, '0', '^[01]$', 22, 'Enable pace2-based firewall PoC');

--changeset ogl:2428
--comment: optimize data access in cblx
create index vpn.IDX_MEMBER_FK3
  on vpn.VPN_MEMBER (PARTITION_ID,INTERFACE_ID, ID);

--changeset diw:2429
--comment: CLOUD-1002: Redesign sync metadata tables

-- Drop original tables and sequence from changeset diw:2419
DROP TABLE FW.SYNC_METADATA2APP;
DROP TABLE FW.SYNC_METADATA2IPGROUP;
DROP TABLE FW.SYNC_METADATA;
DROP SEQUENCE FW.SYNC_METADATA_SEQ;

-- Remove old JDO properties
DELETE FROM FW."#JDO_PROPERTIES" WHERE "KEY" IN ('SYNC_METADATA.naming', 'SYNC_METADATA2IPGROUP.naming', 'SYNC_METADATA2APP.naming');

-- Create new table for IP Group sync metadata
CREATE TABLE FW.IP_GROUP_SYNC_METADATA (
                                          ID NUMBER NOT NULL,
                                          IP_GROUP_ID NUMBER(11,0) NOT NULL,
                                          LAST_SYNCHRONIZED_TICKET_ID NUMBER(11,0),
                                          MAINTENANCE_PROCESS VARCHAR2(255) NOT NULL,
                                          LAST_SYNCHRONIZED timestamp with time zone default systimestamp,
                                          CONSTRAINT PK_IPGROUPSYNCMD PRIMARY KEY (ID),
                                          CONSTRAINT FK_IPGROUPSYNCMD_IPGROUP FOREIGN KEY (IP_GROUP_ID) REFERENCES FW.IP_GROUP (ID),
                                          CONSTRAINT FK_IPGROUPSYNCMD_TICKET FOREIGN KEY (LAST_SYNCHRONIZED_TICKET_ID) REFERENCES TT.TICKET (ID),
                                          CONSTRAINT IPGROUP_SYNCMD_UQ1 UNIQUE (IP_GROUP_ID, MAINTENANCE_PROCESS)
);
COMMENT ON TABLE FW.IP_GROUP_SYNC_METADATA IS 'Stores synchronization metadata for a specific IP group and maintenance process.';
COMMENT ON COLUMN FW.IP_GROUP_SYNC_METADATA.IP_GROUP_ID IS 'Reference to the IP group.';
COMMENT ON COLUMN FW.IP_GROUP_SYNC_METADATA.MAINTENANCE_PROCESS IS 'The unique name of the maintenance process.';
COMMENT ON COLUMN FW.IP_GROUP_SYNC_METADATA.LAST_SYNCHRONIZED IS 'Last successful synchronization timestamp.';
COMMENT ON COLUMN FW.IP_GROUP_SYNC_METADATA. LAST_SYNCHRONIZED_TICKET_ID IS 'Ticket containing configuration changes of last successful sync.';
CREATE SEQUENCE FW.IP_GROUP_SYNC_METADATA_SEQ;

-- Create new table for Application sync metadata
CREATE TABLE FW.APP_SYNC_METADATA (
                                      ID NUMBER NOT NULL,
                                      APP_ID NUMBER(11,0) NOT NULL,
                                      LAST_SYNCHRONIZED_TICKET_ID NUMBER(11,0),
                                      MAINTENANCE_PROCESS VARCHAR2(255) NOT NULL,
                                      LAST_SYNCHRONIZED timestamp with time zone default systimestamp,
                                      CONSTRAINT PK_APPSYNCMD PRIMARY KEY (ID),
                                      CONSTRAINT FK_APPSYNCMD_APP FOREIGN KEY (APP_ID) REFERENCES APPID.APP (ID),
                                      CONSTRAINT FK_APPSYNCMD_TICKET FOREIGN KEY (LAST_SYNCHRONIZED_TICKET_ID) REFERENCES TT.TICKET (ID),
                                      CONSTRAINT APP_SYNCMD_UQ1 UNIQUE (APP_ID, MAINTENANCE_PROCESS)
);
COMMENT ON TABLE FW.APP_SYNC_METADATA IS 'Stores synchronization metadata for a specific application and maintenance process.';
COMMENT ON COLUMN FW.APP_SYNC_METADATA.APP_ID IS 'Reference to the application.';
COMMENT ON COLUMN FW.APP_SYNC_METADATA.MAINTENANCE_PROCESS IS 'The unique name of the maintenance process.';
COMMENT ON COLUMN FW.APP_SYNC_METADATA.LAST_SYNCHRONIZED IS 'Last successful synchronization timestamp.';
COMMENT ON COLUMN FW.APP_SYNC_METADATA. LAST_SYNCHRONIZED_TICKET_ID IS 'Ticket containing configuration changes of last successful sync.';
CREATE SEQUENCE FW.APP_SYNC_METADATA_SEQ;

INSERT INTO FW."#JDO_PROPERTIES" ("KEY","VALUE") VALUES ('IP_GROUP_SYNC_METADATA.naming','none');
INSERT INTO FW."#JDO_PROPERTIES" ("KEY","VALUE") VALUES ('APP_SYNC_METADATA.naming','none');

GRANT SELECT, INSERT, UPDATE, DELETE ON FW.IP_GROUP_SYNC_METADATA TO SVC_CONIFER;
GRANT SELECT, INSERT, UPDATE, DELETE ON FW.APP_SYNC_METADATA TO SVC_CONIFER;
GRANT SELECT ON FW.IP_GROUP_SYNC_METADATA_SEQ TO SVC_CONIFER;
GRANT SELECT ON FW.APP_SYNC_METADATA_SEQ TO SVC_CONIFER;

--changeset quv:2430
--comment: SRE-1561: Add audit record types for ISP company, ISP contact mutations
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID)
VALUES (499, 'ISP Company created', 'isp_company_add', 'An ISP company has been created', 1);

INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID)
VALUES (500, 'ISP Company modified', 'isp_company_modify', 'An ISP company has been modified', 1);

INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID)
VALUES (501, 'ISP Company deleted', 'isp_company_delete', 'An ISP company has been deleted', 1);

INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID)
VALUES (502, 'ISP Contact created', 'isp_contact_add', 'An ISP contact has been created', 1);

INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID)
VALUES (503, 'ISP Contact modified', 'isp_contact_modify', 'An ISP contact has been modified', 1);

INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID)
VALUES (504, 'ISP Contact deleted', 'isp_contact_delete', 'An ISP contact has been deleted', 1);

--changeset ahd:2431
--comment: FW-7059: Add new DB Prop for firewall threat protection
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (57250, 'fw.tim', 1, '0', '^[01]$', 22, 'Enable threat protection in the firewall');

--changeset quv:2432
--comment: SRE-1561: Grant ISP company, ISP contact mutations to SVC_CONIFER
GRANT SELECT ON STOP.COMPANY_SEQ TO SVC_CONIFER;
GRANT INSERT, UPDATE, DELETE ON STOP.COMPANY TO SVC_CONIFER;
GRANT INSERT, DELETE ON STOP.COMP_COMPTYPE_REF TO SVC_CONIFER;

--changeset yuy:2433
--comment: IDS-3739: Create logstash2Alertd migration dbprop
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (57260, 'migrate.2026.logstash2alertd', 1, '0', '^[01]$', NULL, 'Logstash to alertd migration group');

--changeset kej:2434
--comment: FW-7105: add new dbprop for dns-inspection log shipping to Loki
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (57261, 'fw.dns.log.loki', 1, '0', '^[01]$', 22, 'Enable DNS inspection log shipping to Loki');

--changeset mta:2435
--comment: CLOUD-1000: Tables for shared objects maintenance
DROP TABLE FW.IP_GROUP_SYNC_METADATA;
DROP SEQUENCE FW.IP_GROUP_SYNC_METADATA_SEQ;
DROP TABLE FW.APP_SYNC_METADATA;
DROP SEQUENCE FW.APP_SYNC_METADATA_SEQ;
DELETE FROM FW."#JDO_PROPERTIES" WHERE "KEY" IN ('IP_GROUP_SYNC_METADATA.naming', 'APP_SYNC_METADATA.naming');

CREATE TABLE FW.MAINTAINED_OBJECTS (
    ID NUMBER NOT NULL,
    SYNC_NAME VARCHAR2(255) NOT NULL,
    PROCESS VARCHAR2(255) NOT NULL,
    LAST_SYNCHRONIZED timestamp with time zone default systimestamp,
    LAST_SYNC_TICKET_ID NUMBER(11,0),
    CONSTRAINT PK_MAINTAINED_OBJECTS PRIMARY KEY (ID),
    CONSTRAINT MAINTAINED_OBJECTS_UQ1 UNIQUE (SYNC_NAME, PROCESS),
    CONSTRAINT FK_MAINTAINED_OBJECTS_TICKET FOREIGN KEY (LAST_SYNC_TICKET_ID) REFERENCES TT.TICKET (ID)
);
COMMENT ON TABLE FW.MAINTAINED_OBJECTS IS 'Stores data about one collection of maintained shared objects (like a QuickID app and an IP group), in relation to their maintenance process.';
COMMENT ON COLUMN FW.MAINTAINED_OBJECTS.SYNC_NAME IS 'An identifier for the maintained objects, owned by the maintenance process.';
COMMENT ON COLUMN FW.MAINTAINED_OBJECTS.PROCESS IS 'The name of the maintenance process to which the maintained objects belong.';
COMMENT ON COLUMN FW.MAINTAINED_OBJECTS.LAST_SYNCHRONIZED IS 'Last successful synchronization. This does not imply that the maintained objects were changed.';
COMMENT ON COLUMN FW.MAINTAINED_OBJECTS.LAST_SYNC_TICKET_ID IS 'The ticket ID associated with the last successful synchronization.';

CREATE SEQUENCE FW.MAINTAINED_OBJECTS_SEQ;

CREATE TABLE FW.MAINTAINED_OBJECTS2IP_GROUP (
    IP_GROUP_ID NUMBER(11,0) NOT NULL,
    MAINTAINED_OBJECTS_ID NUMBER(11,0) NOT NULL,
    CONSTRAINT FK_MAINTOBJS2IPGROUP_IPGROUP FOREIGN KEY (IP_GROUP_ID) REFERENCES FW.IP_GROUP (ID),
    CONSTRAINT FK_MAINTOBJS2IPGROUP_MAINTOBJS FOREIGN KEY (MAINTAINED_OBJECTS_ID) REFERENCES FW.MAINTAINED_OBJECTS (ID),
    CONSTRAINT PK_MAINTOBJS2IPGROUP PRIMARY KEY (IP_GROUP_ID, MAINTAINED_OBJECTS_ID)
);
COMMENT ON TABLE FW.MAINTAINED_OBJECTS2IP_GROUP IS 'Associates an IP group with one collection of maintained objects.';

CREATE TABLE FW.MAINTAINED_OBJECTS2APP (
    APP_ID NUMBER(11,0) NOT NULL,
    MAINTAINED_OBJECTS_ID NUMBER(11,0) NOT NULL,
    CONSTRAINT FK_MAINTOBJS2APP_APP FOREIGN KEY (APP_ID) REFERENCES APPID.APP (ID),
    CONSTRAINT FK_MAINTOBJS2APP_MAINTOBJS FOREIGN KEY (MAINTAINED_OBJECTS_ID) REFERENCES FW.MAINTAINED_OBJECTS (ID),
    CONSTRAINT PK_MAINTOBJS2APP PRIMARY KEY (APP_ID, MAINTAINED_OBJECTS_ID)
);
COMMENT ON TABLE FW.MAINTAINED_OBJECTS2APP IS 'Associates an application with with one collection of maintained objects.';

INSERT INTO FW."#JDO_PROPERTIES" ("KEY","VALUE") VALUES ('MAINTAINED_OBJECTS.naming','none');
INSERT INTO FW."#JDO_PROPERTIES" ("KEY","VALUE") VALUES ('MAINTAINED_OBJECTS2IP_GROUP.naming','none');
INSERT INTO FW."#JDO_PROPERTIES" ("KEY","VALUE") VALUES ('MAINTAINED_OBJECTS2APP.naming','none');

GRANT SELECT, INSERT, UPDATE, DELETE ON FW.MAINTAINED_OBJECTS TO SVC_CONIFER;
GRANT SELECT, INSERT, UPDATE, DELETE ON FW.MAINTAINED_OBJECTS2IP_GROUP TO SVC_CONIFER;
GRANT SELECT, INSERT, UPDATE, DELETE ON FW.MAINTAINED_OBJECTS2APP TO SVC_CONIFER;
GRANT SELECT ON FW.MAINTAINED_OBJECTS_SEQ TO SVC_CONIFER;

--changeset lut:2436
--comment: RTNG-1098: Color IPset migration cleanup, remove migrate dbprop
DELETE FROM mss.value WHERE key_id IN (SELECT id FROM mss.key WHERE name = 'migrate.path.color_ipsets');
DELETE FROM mss.key WHERE name = 'migrate.path.color_ipsets';

--changeset gip:2437
--comment: MX-6575: Add new DBProp mail.ext2ext
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (57262, 'mail.ext2ext', 4, 'relay', '^(relay|quarantine|reject)$', 22, 'Defines how external-to-external emails are handled');

--changeset dnb:2438
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID)
VALUES (505, 'Addrsync threshold modified', 'mail_addrsync_threshold_mod', 'The sync thresholds for address sync were modified.',1);

--changeset rha:2439
--comment: ZTNA-1725: Add new dbprop ztna.swg connecting an on-prem SWG with ZTNA
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (24508, 'ztna.swg', 1, '0', '^[01]$', NULL, 'enable on-prem SWG');

--changeset diw:2440
--comment: CLOUD-11160: At most apps and ipgs can only be mapped to at most one process
ALTER TABLE FW.MAINTAINED_OBJECTS2IP_GROUP ADD CONSTRAINT UC_MAINTOBJS2IPGROUP_IPGROUP UNIQUE (IP_GROUP_ID);
ALTER TABLE FW.MAINTAINED_OBJECTS2APP ADD CONSTRAINT UC_MAINTOBJS2APP_APP UNIQUE (APP_ID);

--changeset jad:2441
--comment: ZTNA-1639 Increase ZTNA tenant name length to 253 bytes
ALTER TABLE SVC_ZEROTRUST.ZTNA_TENANT MODIFY NAME VARCHAR2(253 BYTE);

--changeset doi:2442
--comment: PRX-9827: Drop NOT NULL constraints for last modified fields on TP entries
ALTER TABLE TIM.BLACKLIST_VALUE
  MODIFY (
    LAST_MODIFIED_TIME TIMESTAMP WITH TIME ZONE NULL,
    LAST_MODIFIED_CONTACT_ID NUMBER(10,0) NULL
  );
ALTER TABLE TIM.EXCLUSION_LIST_VALUE
  MODIFY (
    LAST_MODIFIED_TIME TIMESTAMP WITH TIME ZONE NULL,
    LAST_MODIFIED_CONTACT_ID NUMBER(10,0) NULL
  );

--changeset lut:2443
--comment: RTNG-1345: Add dbprops to control rollout of Default Internet routing managed by Path Selection
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (57263, 'migrate.path.default_internet_fwd', 1, '0', '^[01]$', NULL, 'Enables migration of default internet forwarding traffic to be managed by Path Selection.');

insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (57264, 'migrate.path.default_internet_mgmt', 1, '0', '^[01]$', NULL, 'Enables migration of default internet management traffic to be managed by Path Selection.');

--changeset mlo:2442
--comment: TRIVIAL: add support for Zitadel-only users in audit trail
alter table MCAUDIT.RECORD
    add ZITADEL_USER_ID varchar2(128);
comment on column MCAUDIT.RECORD.ZITADEL_USER_ID is 'Zitadel ID (Sub) of the User who made this change (human or service user)';
alter table MCAUDIT.RECORD
    add ZITADEL_USER_NAME varchar2(128);
comment on column MCAUDIT.RECORD.ZITADEL_USER_NAME is 'Name at the time of the change of the Zitadel user who made this change (kept it for audit purposes in case of changes in Zitadel)';
alter table MCAUDIT.RECORD
    add ZITADEL_USER_COMPANY_ID NUMBER(22)
        constraint FK_RECORD_ZITADEL_USER_COMPANY_ID
            references STOP.COMPANY;
comment on column MCAUDIT.RECORD.ZITADEL_USER_COMPANY_ID is 'Company ID of the Zitadel User who made the change, stored here to see without additional fetching if change was made by Open Systems (MC) or the customer.';

-- for now we set their jdo name to none so we don't generate java code for it so that we're sure the new columns get deployed before we have code with their generated code released
-- we'll generate java code once they're deployed and we start using them
INSERT INTO MCAUDIT."#JDO_PROPERTIES" (KEY, VALUE) VALUES ('RECORD.naming.ZITADEL_USER_ID', 'none');
INSERT INTO MCAUDIT."#JDO_PROPERTIES" (KEY, VALUE) VALUES ('RECORD.naming.ZITADEL_USER_NAME', 'none');
INSERT INTO MCAUDIT."#JDO_PROPERTIES" (KEY, VALUE) VALUES ('RECORD.naming.ZITADEL_USER_COMPANY_ID', 'none');

--changeset lut:2444
--comment: RTNG-1350: Add dbprop to control rollout of Special Link Types
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (57265, 'migrate.path.special_link_types', 1, '0', '^[01]$', NULL, 'Triggers migration to special link types in Path Selection.');

--changeset bao:2445
--comment: NC-1370: Add dbprop to set leaf qdisc for bandwidth control htb
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (57266, 'qos.leaf_qdisc', 4, 'fqcodel', '^[A-Za-z0-9 _]+$', 22, 'Set the leaf qdisc for Bandwidth Control.');

--changeset ang:2446
--comment: IDS-3743: Set logstash2alertd migration dbprop to 1 by default
update MSS.KEY
set STRING_DEFAULT='1'
where NAME='migrate.2026.logstash2alertd';

--changeset mlo:2447
--comment: MC-31507: remove noBitcOps java generation
insert into STOP."#JDO_PROPERTIES" (key, value)
values ('COMPANY.naming.NO_BITC_OPS', 'none');

--changeset mlo:2448
--comment: MC-31507: remove noBitcOps column entirely
ALTER TABLE STOP.COMPANY DROP COLUMN NO_BITC_OPS;

--changeset slb:2449
--comment: MEP-2626: Set sslvpn.asav.version to new current version 9.18.4_76
update mss.KEY set STRING_DEFAULT='9.18.4_76' where NAME='sslvpn.asav.version';

--changeset nke:2450
--comment: MX-6900: Add direction enforcement exclusion scope to policy list tags
INSERT INTO MAIL.POLICY_LIST_TAG(MAIL.POLICY_LIST_TAG.ID, MAIL.POLICY_LIST_TAG.NAME, MAIL.POLICY_LIST_TAG.DESCRIPTION, MAIL.POLICY_LIST_TAG.POLICY_LIST_TYPE_ID) VALUES (18, 'direction', 'Direction Enforcement', 1);

--changeset nis:2451
--comment: MC-31675: grants for DECOMM user to fix FK violations during host and service decommission
GRANT SELECT, DELETE ON AUTH.MEDUSAHOST TO DECOMM;
GRANT SELECT, DELETE ON AUTH.SHADOWAUTHHOST TO DECOMM;
GRANT SELECT, DELETE ON AUTH.SHADOWAUTHHOST2AUTHHOST TO DECOMM;
GRANT SELECT, DELETE ON MSS.CONFIG_LIST_VALUE TO DECOMM;
GRANT SELECT, DELETE ON NIDS.POLICY_RULE TO DECOMM;
GRANT SELECT, DELETE ON NIDS.RULE2ACTION TO DECOMM;
GRANT SELECT, DELETE ON NIDS.RULE2TICKET TO DECOMM;
GRANT SELECT, DELETE ON NIDS.EVENT_FILTER_RULE TO DECOMM;
GRANT SELECT, DELETE ON NIDS.TICKET2RULE TO DECOMM;

--changeset jmu:2452
--comment: PRX-9822: Change default value of dbprop migrate.squid.geoip.v2 to 1
update MSS.KEY set STRING_DEFAULT='1' WHERE ID=57200 and NAME='migrate.squid.geoip.v2';

--changeset dnb:2453
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID)
VALUES (506, 'Addrsync list created', 'mail_addrsync_list_create', 'Email address sync list was created.',1);
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID)
VALUES (507, 'Addrsync list deleted', 'mail_addrsync_list_delete', 'Email address sync list was deleted.',1);

--changeset doi:2454
--comment: PRX-9882: Add suspicious category to blocklist value categories
INSERT INTO TIM.BLACKLIST_VALUE_CATEGORY (ID, CATEGORY, DESCRIPTION)
VALUES (4, 'suspicious', 'Suspicious content');

--changeset bao:2455
--comment: NC-1376: Drop DB Prop migrate.bandwidth_control_qdisc.fallback
DELETE FROM MSS.VALUE v where v.key_id = (SELECT k.id from MSS.KEY k where k.name = 'migrate.bandwidth_control_qdisc.fallback');
DELETE FROM MSS.KEY where name = 'migrate.bandwidth_control_qdisc.fallback';

--changeset diw:2456
--comment: CLOUD-1174: Tables for shared service group maintenance
CREATE TABLE FW.MAINTAINED_OBJECTS2SRV_GROUP (
    SERVICE_GROUP_ID NUMBER(11,0) NOT NULL,
    MAINTAINED_OBJECTS_ID NUMBER(11,0) NOT NULL,
    CONSTRAINT FK_MAINTOBJS2SRGROUP_IPGROUP FOREIGN KEY (SERVICE_GROUP_ID) REFERENCES FW.SERVICE_GROUP (ID),
    CONSTRAINT FK_MAINTOBJS2SRGROUP_MAINTOBJS FOREIGN KEY (MAINTAINED_OBJECTS_ID) REFERENCES FW.MAINTAINED_OBJECTS (ID),
    CONSTRAINT PK_MAINTOBJS2SRGROUP PRIMARY KEY (SERVICE_GROUP_ID, MAINTAINED_OBJECTS_ID)
);
COMMENT ON TABLE FW.MAINTAINED_OBJECTS2SRV_GROUP IS 'Associates a service group with one collection of maintained objects.';

INSERT INTO FW."#JDO_PROPERTIES" ("KEY","VALUE") VALUES ('MAINTAINED_OBJECTS2SRV_GROUP.naming','none');
GRANT SELECT, INSERT, UPDATE, DELETE ON FW.MAINTAINED_OBJECTS2SRV_GROUP TO SVC_CONIFER;

CREATE INDEX FW.IDX_MAINTOBJS2SRV_GRP ON FW.MAINTAINED_OBJECTS2SRV_GROUP (MAINTAINED_OBJECTS_ID);
CREATE INDEX FW.IDX_MAINTOBJS2IP_GRP ON FW.MAINTAINED_OBJECTS2IP_GROUP (MAINTAINED_OBJECTS_ID);
CREATE INDEX FW.IDX_MAINTOBJS2APP ON FW.MAINTAINED_OBJECTS2APP (MAINTAINED_OBJECTS_ID);

--changeset alg:2500 tag:v2.4.0
--comment: Base of new container, containing updated CLOB migration procedures
SELECT 1 FROM dual;

--changeset lut:2501
--comment: RTNG-1298: Add dbprop to enable bfdd on frrouting
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (57267, 'bfdd', 1, '0', '^[01]$', NULL, 'Enables BFD daemon in FRRouting.');

--changeset slb:2502
--comment: MEP-2626: Reset sslvpn.asav.version to version 9.18.4_67
update mss.KEY set STRING_DEFAULT='9.18.4_67' where NAME='sslvpn.asav.version';

--changeset gpe:2503
--comment: FW-7010: remove fw.appid.procera dbprop
DELETE FROM MSS.VALUE v where v.key_id = (SELECT k.id from MSS.KEY k where k.name = 'fw.appid.procera');
DELETE FROM MSS.KEY where name = 'fw.appid.procera';

--changeset qvu:2504
--comment: ORE-35208: Add reading rights to Automation Framework service account for getting customer maintenance windows
GRANT SELECT ON TT.CUST_MAINTENANCE_WINDOW TO SVC_AUTOMATION_EXECUTOR;

--changeset ogl:2505
--comment: drop unused influx dbprop
DELETE FROM MSS.VALUE v where v.key_id = (SELECT k.id from MSS.KEY k where k.name = 'mgmtserver.influxdb');
DELETE FROM MSS.KEY where name = 'mgmtserver.influxdb';

--changeset flg:2506
--comment: ORE-35216: Create service user for QSC assignment tool
CREATE USER "SVC_QSC_ASSIGNMENT" IDENTIFIED BY "xxxxxx" ACCOUNT LOCK
    DEFAULT TABLESPACE "USERS"
    TEMPORARY TABLESPACE "TEMP";
GRANT "MSS_LOGIN_USER" TO "SVC_QSC_ASSIGNMENT";
ALTER USER "SVC_QSC_ASSIGNMENT" DEFAULT ROLE "MSS_LOGIN_USER";
GRANT EXEMPT ACCESS POLICY TO "SVC_QSC_ASSIGNMENT";

--changeset flg:2507 contextFilter:dummyPasswords
--comment: ORE-35216: Create service user for QSC assignment tool
alter user SVC_QSC_ASSIGNMENT identified by "password" account unlock;

--changeset flg:2508
--comment: ORE-35216: Create service user for QSC assignment tool
GRANT SELECT ON TT.TICKET TO SVC_QSC_ASSIGNMENT;
GRANT SELECT ON TT.EVENT TO SVC_QSC_ASSIGNMENT;
GRANT SELECT ON MSS.SERVICE_COMPONENT TO SVC_QSC_ASSIGNMENT;

--changeset lel:2509
--comment: OB-592: Create fwhits metric migration dbprop
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (57268, 'migrate.2026.fw.hitscount.otel', 1, '0', '^[01]$', NULL, 'Ships fwhits_total via telemetry-mesh (OTel), disables direct remotewrite to Thanos');

--changeset mag:2510
--comment: PRX-9855: Remove suspicious category from blocklist value categories
DELETE FROM TIM.BLACKLIST_VALUE where BLACKLIST_VALUE_CATEGORY_ID = 4;
DELETE FROM TIM.BLACKLIST_VALUE_CATEGORY
WHERE ID = 4 AND CATEGORY = 'suspicious';

--changeset jkl:2511
--comment: RTNG-1391: Add dbprop to enable the strongswan-sentinel daemon
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (57269, 'ipsec.sentinel', 1, '0', '^[01]$', NULL, 'Enables the Strongswan Sentinel daemon.');

--changeset nop:2512
--comment: Allow SVC_ALERTHANDLER to query dbprops
GRANT SELECT ON MSS.KEY TO SVC_ALERTHANDLER;
GRANT SELECT ON MSS.MV_VALUE_HOST TO SVC_ALERTHANDLER;

--changeset alg:2513
--comment: TRIVIAL: add Indexes on FKs "pointing" to STOP.COMPANY
create index APPID.IDX_APP_OPTIMIZATION_SETTING_COMPANY_ID on APPID.APP_OPTIMIZATION_SETTING(COMPANY_ID);
create index MC.IDX_CONN_SLA_CLASS_COMPANY_ID on MC.CONN_SLA_CLASS(COMPANY_ID);
create index MAIL.IDX_CUSTOM_POLICY_LIST_COMPANY_ID on MAIL.CUSTOM_POLICY_LIST(COMPANY_ID);
create index MSS.IDX_DNS_ZONE_GROUP_COMPANY_ID on MSS.DNS_ZONE_GROUP(COMPANY_ID);
create index FW.IDX_EXTERNAL_IP_LIST_COMPANY_ID on FW.EXTERNAL_IP_LIST(COMPANY_ID);
create index MSS.IDX_LOGFWD_DAR_SECRET_COMPANY_ID on MSS.LOGFWD_DAR_SECRET(COMPANY_ID);
create index AUTH.IDX_LOGIN_COMPANY_ID on AUTH.LOGIN(COMPANY_ID);
create index NIDS.IDX_MDR_FILTER_RULE_COMPANY_ID on NIDS.MDR_FILTER_RULE(COMPANY_ID);
create index NIDS.IDX_MDR_SIGNATURE_COMPANY_ID on NIDS.MDR_SIGNATURE(COMPANY_ID);
create index NIDS.IDX_MDR_SIGNATURE_GROUP_COMPANY_ID on NIDS.MDR_SIGNATURE_GROUP(COMPANY_ID);
create index NIDS.IDX_NIDS_ENTITY_GROUP_COMPANY_ID on NIDS.NIDS_ENTITY_GROUP(COMPANY_ID);
create index NIDS.IDX_NIDS_IPV6_ADDRESS_COMPANY_ID on NIDS.NIDS_IPV6_ADDRESS(COMPANY_ID);
create index AUTH.IDX_PASSPORT_LOGIN_COMPANY_ID on AUTH.PASSPORT_LOGIN(COMPANY_ID);
create index FW.IDX_POLICY_COMPANY_ID on FW.POLICY(COMPANY_ID);
create index MSS.IDX_RELEASE_INSTALLATION_COMPANY_ID on MSS.RELEASE_INSTALLATION(COMPANY_ID);
create index TT.IDX_SERVICE_WINDOW_COMPANY_ID on TT.SERVICE_WINDOW(COMPANY_ID);
create index NIDS.IDX_SIGNATURE_COMPANY_ID on NIDS.SIGNATURE(COMPANY_ID);
create index MAIL.IDX_USER_GROUP_COMPANY_ID on MAIL.USER_GROUP(COMPANY_ID);
create index SVC_ZEROTRUST.IDX_ZTNA_TENANT_COMPANY_ID on SVC_ZEROTRUST.ZTNA_TENANT(COMPANY_ID);

--changeset alg:2514
--comment: TRIVIAL: add indexes to all FK in STOP.COMPANY
create index STOP.IDX_COMPANY_ADDRESS_ID on STOP.COMPANY(ADDRESS_ID);
create index STOP.IDX_COMPANY_DEFAULT_COMPANY_UNIT_ID on STOP.COMPANY(DEFAULT_COMPANY_UNIT_ID);
create index STOP.IDX_COMPANY_MANAGING_COMPANY_ID on STOP.COMPANY(MANAGING_COMPANY_ID);
create index STOP.IDX_COMPANY_COMPANY_SECTOR_ID on STOP.COMPANY(COMPANY_SECTOR_ID);

--changeset alg:2515
--comment: TRIVIAL: add indexes to all FK in MSS.ISP_LINK
create index MSS.IDX_INTERFACE2ISP_LINK_ISP_LINK_ID on MSS.INTERFACE2ISP_LINK(ISP_LINK_ID);
create index MSS.IDX_ISP_OFFER_ISP_LINK_ID on MSS.ISP_OFFER(ISP_LINK_ID);

--changeset alg:2516
--comment: TRIVIAL: add Indexes on FKs "pointing" to MSS.ISP_LINK
create index MSS.IDX_ISP_LINK_ISP_LINK_STATUS_TYPE_ID on MSS.ISP_LINK(ISP_LINK_STATUS_TYPE_ID);
create index MSS.IDX_ISP_LINK_MAINTENANCE_STATUS_ID on MSS.ISP_LINK(MAINTENANCE_STATUS_ID);
create index MSS.IDX_ISP_LINK_USAGE_INTERFACE_ID on MSS.ISP_LINK(USAGE_INTERFACE_ID);
create index MSS.IDX_ISP_LINK_ROUTER_IPV6_ADDRESS_ID on MSS.ISP_LINK(ROUTER_IPV6_ADDRESS_ID);
create index MSS.IDX_ISP_LINK_ISP_LINK_SOURCING_TYPE_ID on MSS.ISP_LINK(ISP_LINK_SOURCING_TYPE_ID);
create index MSS.IDX_ISP_LINK_ISP_LINK_TRANSPORT_MEDIA_ID on MSS.ISP_LINK(ISP_LINK_TRANSPORT_MEDIA_ID);
create index MSS.IDX_ISP_LINK_EVENT_TYPE_ID on MSS.ISP_LINK(EVENT_TYPE_ID);
create index MSS.IDX_ISP_LINK_CURRENCY_ID on MSS.ISP_LINK(CURRENCY_ID);
create index MSS.IDX_ISP_LINK_PING_IP_GROUP_ID on MSS.ISP_LINK(PING_IP_GROUP_ID);

--changeset nop:2517
--comment: Fix customer configuration change
UPDATE TT.EVENT_TYPE SET NAME = 'customer configuration change', DESCRIPTION = 'Customer configuration change initiated by a customer.' WHERE ID = 30023;

--changeset alg:2518
--comment TRIVIAL: add Indexes on FKs "pointing" to STOP.COMPANY (COMAPNY_PK )
create index MSS.IDX_HOST_SERVICE_COMPANY_ID on MSS.HOST(SERVICE_COMPANY_ID) ONLINE;
create index NIDS.IDX_NIDS_IP_NETWORK_SCOPE_COMPANY_ID on NIDS.NIDS_IP_NETWORK(SCOPE_COMPANY_ID) ONLINE;
create index VPN.IDX_PARTNER_PHASE1_CUSTOMER_COMPANY_ID on VPN.PARTNER_PHASE1(CUSTOMER_COMPANY_ID) ONLINE;
create index MCAUDIT.IDX_RECORD_ZITADEL_USER_COMPANY_ID on MCAUDIT.RECORD(ZITADEL_USER_COMPANY_ID) ONLINE;

--changeset aea:2519
--comment: AIX-487: add event type ask alfred
insert into TT.EVENT_TYPE (ID, NAME, SOURCE, IS_NOTIFIED, ESCALATION, DESCRIPTION, SMS_MESSAGE_TEMPLATE_ID, EMAIL_MESSAGE_TEMPLATE_ID, PINNABLE, AUTOPIN)
values (10602, 'ask alfred', 8, 0, 0, 'ask alfred', 1, 2, 0, 0);

--changeset lut:2520
--comment: Change comment of MAPPED_TO enum column
COMMENT ON COLUMN APPID.PATH_SELECTION_LINK_CLASS.MAPPED_TO IS 'Mapping type: 1=single_interface, 2=multiple_interfaces, 3=backbone, 4=t2ee';

--changeset ogl:2521
--comment: for deleteTicket
grant select, delete on FW.CHANGE to TT;

--changeset nop:2522
--comment: adds unstable to list of allowed criticality values
UPDATE MSS."KEY" x
	SET x.REGEXP='^(unstable|normal|24x7|critical)$'
	WHERE x.ID=56842;

--changeset ahd:2523
--comment: FW-7226: Add new DB Prop for protocol validation. This supersedes the fw.app.pace2.poc dbprop
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (57241, 'fw.appid.pace2.validation.protocols', 1, '0', '^[01]$', 22, 'Enable protocol validation in the firewall');

--changeset nis:2524
--comment: MC-31963: create network Requestor permission
INSERT INTO AUTH.USER_ROLE (ID, NAME, DESCRIPTION, IS_INTERNAL, USER_ROLE_SCOPE_TYPE_ID)
VALUES (2015, 'mc-cust-network-req', 'Network Requestor', 0, 1);
INSERT INTO AUTH.user_role2required_role (USER_ROLE_ID, REQUIRED_USER_ROLE_ID)
VALUES (2015, 1003);

--changeset ogl:2525
--comment: ORE-36131: scope master data
create table mss.scope (
    id number(11) not null,
    name varchar2(32) not null,
    constraint scope_pk primary key (id)
);
insert into mss.scope (id, name) values (1, 'host');
insert into mss.scope (id, name) values (2, 'service');
insert into mss.scope (id, name) values (3, 'group');
insert into mss.scope (id, name) values (4, 'vpn');
insert into mss.scope (id, name) values (5, 'company');
insert into mss.scope (id, name) values (9, 'default');

grant references,select on mss.scope to TIM;

insert into mss."#JDO_PROPERTIES" ("KEY","VALUE") values ('SCOPE.naming','none');

--changeset mma:2526
--comment: PRX-10003: add threat protection policy table
grant references,select on mss.configuration_group to TIM;
grant references,select on mss.service to TIM;
grant references,select on mss.host to TIM;
create table tim.policy
(
    id number(10) not null,
    scope_id number not null,
    company_id number null,
    group_id number null,
    service_id number null,
    host_id number null,
    protection_level number not null,
    log_only_protection_level number null,
    custom_feed_bundle number(1) default 0 not null,
    block_malware number(1) default 0 not null,
    block_phishing number(1) default 0 not null,
    block_pup number(1) default 0 not null,
    block_spam number(1) default 0 not null,
    block_suspicious number(1) default 0 not null,
    constraint pk_policy primary key (id),
    constraint fk_policy_scope foreign key (scope_id) references mss.scope(id),
    constraint fk_company_id foreign key (company_id) references stop.company(id),
    constraint fk_group_id foreign key (group_id) references mss.configuration_group(id),
    constraint fk_service_id foreign key (service_id) references mss.service(id),
    constraint fk_host_id foreign key (host_id) references mss.host(id)
);
create index tim.idx_policy_scope on tim.policy (scope_id);
create index tim.idx_company_id on tim.policy (company_id);
create index tim.idx_group_id on tim.policy (group_id);
create index tim.idx_service_id on tim.policy (service_id);
create index tim.idx_host_id on tim.policy (host_id);
create sequence tim.policy_seq;

insert into tim."#JDO_PROPERTIES" ("KEY","VALUE") values ('POLICY.naming','none');

--changeset ogl:2528
--comment: drop unused service user
drop user SVC_SERVICE_CONFIG;

--changeset nom:2529
--comment: OSAP-1788: Add ztna zitadel configuration tables
CREATE TABLE SVC_ZEROTRUST.ZTNA_ZITADEL_CONFIG (
                             id number(10) NOT NULL,
                             project_role_assertion NUMBER(1) NULL,
                             project_role_check NUMBER(1) NULL,
                             has_project_check NUMBER(1) NULL,
                             app_type VARCHAR2(31) NULL,
                             app_auth_method VARCHAR2(63) NULL,
                             app_id_token_role_assertion NUMBER(1) NULL,
                             app_dev_mode NUMBER(1) NULL,
                             app_id_token_userinfo_assertion NUMBER(1) NULL,
                             ztna_tenant_id NUMBER NOT NULL,
                             CONSTRAINT ZTNA_ZITADEL_CONFIG_PK PRIMARY KEY (id),
                             CONSTRAINT ZTNA_ZITADEL_CONFIG_FK FOREIGN KEY (ztna_tenant_id) REFERENCES SVC_ZEROTRUST.ZTNA_TENANT(id),
                             CONSTRAINT ZTNA_ZITADEL_CONFIG_UQ1 UNIQUE (ztna_tenant_id)
);

COMMENT ON TABLE SVC_ZEROTRUST.ZTNA_ZITADEL_CONFIG IS 'Stores Zitadel configuration for a ZTNA tenant.';

COMMENT ON COLUMN SVC_ZEROTRUST.ZTNA_ZITADEL_CONFIG.PROJECT_ROLE_ASSERTION IS 'Describes if roles of user should be added in token (0 or 1).';
COMMENT ON COLUMN SVC_ZEROTRUST.ZTNA_ZITADEL_CONFIG.PROJECT_ROLE_CHECK IS 'If set, users are only allowed to authenticate if any role is assigned to their account (0 or 1).';
COMMENT ON COLUMN SVC_ZEROTRUST.ZTNA_ZITADEL_CONFIG.HAS_PROJECT_CHECK IS 'Enable/disable to check if user organization has this project. If it is set, and the org does not have the project, the user cannot be authenticated (0 or 1).';
COMMENT ON COLUMN SVC_ZEROTRUST.ZTNA_ZITADEL_CONFIG.APP_TYPE IS 'The zitadel app type in OIDC workflow. It is one of the OIDC_APP_TYPE_WEB,OIDC_APP_TYPE_USER_AGENT,OIDC_APP_TYPE_NATIVE';
COMMENT ON COLUMN SVC_ZEROTRUST.ZTNA_ZITADEL_CONFIG.APP_AUTH_METHOD IS 'The zitadel app authentication method in OIDC workflow. It is one of the OIDC_AUTH_METHOD_TYPE_BASIC,OIDC_AUTH_METHOD_TYPE_POST,OIDC_AUTH_METHOD_TYPE_NONE,OIDC_AUTH_METHOD_TYPE_PRIVATE_KEY_JWT';
COMMENT ON COLUMN SVC_ZEROTRUST.ZTNA_ZITADEL_CONFIG.APP_ID_TOKEN_ROLE_ASSERTION IS 'Whether to add roles of the authenticated user to the ID token (0 or 1).';
COMMENT ON COLUMN SVC_ZEROTRUST.ZTNA_ZITADEL_CONFIG.APP_DEV_MODE IS 'Whether to enable development mode for the zitadel app(0 or 1).';
COMMENT ON COLUMN SVC_ZEROTRUST.ZTNA_ZITADEL_CONFIG.APP_ID_TOKEN_USERINFO_ASSERTION IS 'Whether to add details of the authenticated user to the ID token (0 or 1).';
COMMENT ON COLUMN SVC_ZEROTRUST.ZTNA_ZITADEL_CONFIG.ZTNA_TENANT_ID IS 'The ID of the ZTNA tenant this Zitadel configuration belongs to. (foreign key)';

CREATE SEQUENCE SVC_ZEROTRUST.ZTNA_ZITADEL_CONFIG_SEQ;

CREATE TABLE SVC_ZEROTRUST.ZTNA_ZITADEL_APP_REDIRECT_URI (
    id NUMBER(10) NOT NULL,
    ztna_zitadel_config_id NUMBER(10) NOT NULL,
    app_redirect_uri VARCHAR2(255) NOT NULL,
    CONSTRAINT ZTNA_ZITADEL_APP_REDIRECT_URI_PK PRIMARY KEY (id),
    CONSTRAINT ZTNA_ZITADEL_APP_REDIRECT_URI_FK FOREIGN KEY (ztna_zitadel_config_id) REFERENCES SVC_ZEROTRUST.ZTNA_ZITADEL_CONFIG(id),
    CONSTRAINT REDIRECT_URI_ZITADEL_CONFIG_UQ1 UNIQUE (ztna_zitadel_config_id, app_redirect_uri)
);

COMMENT ON TABLE SVC_ZEROTRUST.ZTNA_ZITADEL_APP_REDIRECT_URI IS 'Stores Zitadel app redirect URIs in the OIDC workflow.';

COMMENT ON COLUMN SVC_ZEROTRUST.ZTNA_ZITADEL_APP_REDIRECT_URI.APP_REDIRECT_URI IS 'One of the redirect URIs of the Zitadel app. It is in url format. It must be set.';

CREATE INDEX ZTNA_ZITADEL_APP_REDIRECT_URI_ID_2 ON SVC_ZEROTRUST.ZTNA_ZITADEL_APP_REDIRECT_URI (ztna_zitadel_config_id);
CREATE SEQUENCE SVC_ZEROTRUST.ZTNA_ZITADEL_APP_REDIRECT_URI_SEQ;

CREATE TABLE SVC_ZEROTRUST.ZTNA_ZITADEL_APP_RESPONSE_TYPE (
    id NUMBER(10) NOT NULL,
    ztna_zitadel_config_id NUMBER(10) NOT NULL,
    app_response_type VARCHAR2(63) NOT NULL,
    CONSTRAINT ZTNA_ZITADEL_APP_RESPONSE_TYPE_PK PRIMARY KEY (id),
    CONSTRAINT ZTNA_ZITADEL_APP_RESPONSE_TYPE_FK FOREIGN KEY (ztna_zitadel_config_id) REFERENCES SVC_ZEROTRUST.ZTNA_ZITADEL_CONFIG(id),
    CONSTRAINT RESPONSE_TYPE_ZITADEL_CONFIG_UQ1 UNIQUE (ztna_zitadel_config_id, app_response_type)
);

COMMENT ON TABLE SVC_ZEROTRUST.ZTNA_ZITADEL_APP_RESPONSE_TYPE IS 'Stores Zitadel app response types in OIDC workflow.';

COMMENT ON COLUMN SVC_ZEROTRUST.ZTNA_ZITADEL_APP_RESPONSE_TYPE.APP_RESPONSE_TYPE IS 'The response type of the Zitadel app. It is one of the OIDC_RESPONSE_TYPE_CODE, OIDC_RESPONSE_TYPE_ID_TOKEN, OIDC_RESPONSE_TYPE_ID_TOKEN_TOKEN';

CREATE INDEX ZTNA_ZITADEL_APP_RESPONSE_TYPE_ID_2 ON SVC_ZEROTRUST.ZTNA_ZITADEL_APP_RESPONSE_TYPE (ztna_zitadel_config_id);
CREATE SEQUENCE SVC_ZEROTRUST.ZTNA_ZITADEL_APP_RESPONSE_TYPE_SEQ;

CREATE TABLE SVC_ZEROTRUST.ZTNA_ZITADEL_APP_GRANT_TYPE (
    id NUMBER(10) NOT NULL,
    ztna_zitadel_config_id NUMBER(10) NOT NULL,
    app_grant_type VARCHAR2(63) NOT NULL,
    CONSTRAINT ZTNA_ZITADEL_APP_GRANT_TYPE_PK PRIMARY KEY (id),
    CONSTRAINT ZTNA_ZITADEL_APP_GRANT_TYPE_FK FOREIGN KEY (ztna_zitadel_config_id) REFERENCES SVC_ZEROTRUST.ZTNA_ZITADEL_CONFIG(id),
    CONSTRAINT GRANT_TYPE_ZITADEL_CONFIG_UQ1 UNIQUE (ztna_zitadel_config_id, app_grant_type)
);

COMMENT ON TABLE SVC_ZEROTRUST.ZTNA_ZITADEL_APP_GRANT_TYPE IS 'Stores Zitadel app grant types in OIDC workflow.';

COMMENT ON COLUMN SVC_ZEROTRUST.ZTNA_ZITADEL_APP_GRANT_TYPE.APP_GRANT_TYPE is 'The grant type of the Zitadel app. It is one of the OIDC_GRANT_TYPE_AUTHORIZATION_CODE, OIDC_GRANT_TYPE_IMPLICIT, OIDC_GRANT_TYPE_REFRESH_TOKEN, OIDC_GRANT_TYPE_DEVICE_CODE, OIDC_GRANT_TYPE_TOKEN_EXCHANGE';

CREATE INDEX ZTNA_ZITADEL_APP_GRANT_TYPE_ID_2 ON SVC_ZEROTRUST.ZTNA_ZITADEL_APP_GRANT_TYPE (ztna_zitadel_config_id);
CREATE SEQUENCE SVC_ZEROTRUST.ZTNA_ZITADEL_APP_GRANT_TYPE_SEQ;

insert into SVC_ZEROTRUST."#JDO_PROPERTIES" ("KEY","VALUE") values ('ZTNA_ZITADEL_CONFIG.naming','none');
insert into SVC_ZEROTRUST."#JDO_PROPERTIES" ("KEY","VALUE") values ('ZTNA_ZITADEL_APP_REDIRECT_URI.naming','none');
insert into SVC_ZEROTRUST."#JDO_PROPERTIES" ("KEY","VALUE") values ('ZTNA_ZITADEL_APP_RESPONSE_TYPE.naming','none');
insert into SVC_ZEROTRUST."#JDO_PROPERTIES" ("KEY","VALUE") values ('ZTNA_ZITADEL_APP_GRANT_TYPE.naming','none');

--changeset nom:2530
--comment: OSAP-1788: update grants for ztna zitadel configuration tables
GRANT SELECT,INSERT,UPDATE,DELETE ON SVC_ZEROTRUST.ZTNA_ZITADEL_CONFIG TO SVC_CONIFER;
GRANT SELECT,INSERT,UPDATE,DELETE ON SVC_ZEROTRUST.ZTNA_ZITADEL_APP_REDIRECT_URI TO SVC_CONIFER;
GRANT SELECT,INSERT,UPDATE,DELETE ON SVC_ZEROTRUST.ZTNA_ZITADEL_APP_RESPONSE_TYPE TO SVC_CONIFER;
GRANT SELECT,INSERT,UPDATE,DELETE ON SVC_ZEROTRUST.ZTNA_ZITADEL_APP_GRANT_TYPE TO SVC_CONIFER;
GRANT SELECT ON SVC_ZEROTRUST.ZTNA_ZITADEL_CONFIG_SEQ TO SVC_CONIFER;
GRANT SELECT ON SVC_ZEROTRUST.ZTNA_ZITADEL_APP_REDIRECT_URI_SEQ TO SVC_CONIFER;
GRANT SELECT ON SVC_ZEROTRUST.ZTNA_ZITADEL_APP_RESPONSE_TYPE_SEQ TO SVC_CONIFER;
GRANT SELECT ON SVC_ZEROTRUST.ZTNA_ZITADEL_APP_GRANT_TYPE_SEQ TO SVC_CONIFER;

--changeset nom:2531
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:1 select count(*) from DBA_INDEXES where INDEX_NAME='ZTNA_ZITADEL_APP_REDIRECT_URI_ID_2' and owner='SYS'
--comment: move index out of SYS
drop index sys.ZTNA_ZITADEL_APP_REDIRECT_URI_ID_2;

--changeset nom:2532
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:0 select count(*) from DBA_INDEXES where INDEX_NAME='ZTNA_ZITADEL_APP_REDIRECT_URI_ID_2' and owner='SVC_ZEROTRUST'
--comment: move index out of SYS
CREATE INDEX SVC_ZEROTRUST.ZTNA_ZITADEL_APP_REDIRECT_URI_ID_2 ON SVC_ZEROTRUST.ZTNA_ZITADEL_APP_REDIRECT_URI (ztna_zitadel_config_id);


--changeset nom:2533
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:1 select count(*) from DBA_INDEXES where INDEX_NAME='ZTNA_ZITADEL_APP_RESPONSE_TYPE_ID_2' and owner='SYS'
--comment: move index out of SYS
drop index sys.ZTNA_ZITADEL_APP_RESPONSE_TYPE_ID_2;

--changeset nom:2534
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:0 select count(*) from DBA_INDEXES where INDEX_NAME='ZTNA_ZITADEL_APP_RESPONSE_TYPE_ID_2' and owner='SVC_ZEROTRUST'
--comment: move index out of SYS
CREATE INDEX SVC_ZEROTRUST.ZTNA_ZITADEL_APP_RESPONSE_TYPE_ID_2 ON SVC_ZEROTRUST.ZTNA_ZITADEL_APP_RESPONSE_TYPE (ztna_zitadel_config_id);


--changeset nom:2535
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:1 select count(*) from DBA_INDEXES where INDEX_NAME='ZTNA_ZITADEL_APP_GRANT_TYPE_ID_2' and owner='SYS'
--comment: move index out of SYS
drop index sys.ZTNA_ZITADEL_APP_GRANT_TYPE_ID_2;

--changeset nom:2536
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:0 select count(*) from DBA_INDEXES where INDEX_NAME='ZTNA_ZITADEL_APP_GRANT_TYPE_ID_2' and owner='SVC_ZEROTRUST'
--comment: move index out of SYS
CREATE INDEX SVC_ZEROTRUST.ZTNA_ZITADEL_APP_GRANT_TYPE_ID_2 ON SVC_ZEROTRUST.ZTNA_ZITADEL_APP_GRANT_TYPE (ztna_zitadel_config_id);

--changeset lut:2537
--comment: RTNG-1392: Add dbprop to control rollout of IPsec IKE restart strategy
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (57270, 'migrate.ipsec.ike_restart_strategy', 1, '0', '^[01]$', NULL, 'Triggers migration to IPsec IKE restart strategy.');

--changeset nom:2538
--comment: OSAP-1788: force a unique tenant name in a company for ztna tenants configs, and drop the redundant index on company_id
CREATE UNIQUE INDEX SVC_ZEROTRUST.TENANT_NAME_COMPANY_ID_UQ1 ON SVC_ZEROTRUST.ZTNA_TENANT (company_id, name);
DROP INDEX SVC_ZEROTRUST.IDX_ZTNA_TENANT_COMPANY_ID;

--changeset nom:2539
--comment: OSAP-1788: add audit log for changes to ztna tenant's zitadel configuration. System id is set to 1 for audit.
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID)
VALUES (508, 'ZTNA Tenant Zitadel Config Modified', 'ztna_tenant_zitadel_config_modified', 'Zitadel configuration for a ZTNA tenant modified', 1);

--changeset thw:2540
--comment: remove migrate.blackbox_exporter.disable dbprop
DELETE FROM MSS.VALUE v WHERE v.key_id = (SELECT k.id FROM MSS.KEY k WHERE k.name = 'migrate.blackbox_exporter.disable');
DELETE FROM MSS.KEY WHERE name = 'migrate.blackbox_exporter.disable';

--changeset ogl:2541
--comment: DB-3466: add a way to filter for active companies
ALTER TABLE STOP.COMPANY add active NUMBER(1) DEFAULT ON NULL 1 NOT NULL;
comment on column STOP.COMPANY.active is '1 = active, 0 = decommissioned';

-- deactivate customer companies without any hosts
update stop.company c
set active = 0
where exists (select 1 from stop.COMP_COMPTYPE_REF ctr where ctr.company_id = c.id and ctr.comptype_id = 1)
and not exists ( select 1 from mss.HOST2SERVICE h2s, mss.SERVICE s where h2s.SERVICE_ID = s.id and s.COMPANY_ID =c.id);

--changeset evv:2542
--comment: Add migration dbprop for squid proxylogd
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (57280, 'migrate.2026.squid.proxylogd', 1, '0', '^[01]$', NULL, 'Use opentelemtery based proxylogd instead of legacy proxylogd');

--changeset ako:2543
--comment: NC-1367: Enable dynip buildsmall on default scope
UPDATE MSS.KEY k SET k.STRING_DEFAULT='1' WHERE k.NAME='migrate.dynip_buildsmall';

--changeset dnb:2544
--comment: remove migrate.auth.new_tables dbprop
DELETE FROM MSS.VALUE v WHERE v.key_id = (SELECT k.id FROM MSS.KEY k WHERE k.name = 'migrate.auth.new_tables');
DELETE FROM MSS.KEY WHERE name = 'migrate.auth.new_tables';

--changeset ssk:2545
--comment: CLOUD-1210: Add AUTHOR_COMPANY_ID to FW.CHANGE to record the author's company at time of change
ALTER TABLE FW.CHANGE ADD AUTHOR_COMPANY_ID NUMBER(11,0) DEFAULT NULL;
ALTER TABLE FW.CHANGE ADD CONSTRAINT FK_CHANGE_AUTHOR_COMPANY FOREIGN KEY (AUTHOR_COMPANY_ID) REFERENCES STOP.COMPANY (ID);
CREATE INDEX FW.IDX_CHANGE_AUTHOR_COMPANY ON FW.CHANGE (AUTHOR_COMPANY_ID);
COMMENT ON COLUMN FW.CHANGE.AUTHOR_COMPANY_ID IS 'The company of the user who authored the change at the time it was made.';

--changeset ogl:2546
--comment: DB-3473: add mgmtserver.dkim-cron
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (21480, 'mgmtserver.dkim-cron', 1, '0', '^[01]$', null, 'Enables the dkim-maintenance cron job');


--changeset nom:2547
--comment: OSAP-1776: Create zitadel user and schema
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM dba_users WHERE username='ZITADEL'
CREATE USER "ZITADEL" IDENTIFIED BY "xxxxxx" ACCOUNT LOCK
  DEFAULT TABLESPACE "USERS"
  TEMPORARY TABLESPACE "TEMP";

GRANT "MSS_SCHEMA_USER" TO "ZITADEL";
ALTER USER "ZITADEL" DEFAULT ROLE "MSS_SCHEMA_USER";

--changeset nom:2548
--comment: OSAP-1776: Create zitadel tables, indexes and grants
GRANT REFERENCES, SELECT ON STOP.COMPANY TO ZITADEL;
CREATE TABLE ZITADEL.CUSTOMER_CONFIG (
    id NUMBER(10) NOT NULL,
    company_id NUMBER(10) NOT NULL,
    customer_profile VARCHAR2(32) NOT NULL,
    sync_contactinfo_base NUMBER(1) DEFAULT 1 NOT NULL,
    sync_contactinfo_advanced NUMBER(1) DEFAULT 1 NOT NULL,
    allow_user_pass_login NUMBER(1) DEFAULT 0 NOT NULL,
    allow_register NUMBER(1) DEFAULT 1 NOT NULL,
    allow_external_idp NUMBER(1) DEFAULT 1 NOT NULL,
    allow_domain_discovery NUMBER(1) DEFAULT 1 NOT NULL,
    allow_passwordless VARCHAR2(32) NOT NULL,
    force_mfa NUMBER(1) DEFAULT 0 NOT NULL,
    force_mfa_local_only NUMBER(1) DEFAULT 0 NOT NULL,
    disable_email_login NUMBER(1) DEFAULT 0 NOT NULL,
    disable_phone_login NUMBER(1) DEFAULT 0 NOT NULL,
    pass_policy_min_len NUMBER(10) NULL,
    dp_validate_org_domains NUMBER(1) DEFAULT 0 NOT NULL,
    dp_user_login_with_domain NUMBER(1) DEFAULT 1 NOT NULL,
    dp_smtp_address_match NUMBER(1) DEFAULT 0 NOT NULL,
    force_english_language NUMBER(1) DEFAULT 1 NOT NULL,

    CONSTRAINT pk_custconfig PRIMARY KEY (id),
    CONSTRAINT fk_custconfig_company FOREIGN KEY (company_id) REFERENCES stop.company(id)
);
COMMENT ON TABLE ZITADEL.CUSTOMER_CONFIG IS 'Stores customer specific zitadel configuration for a company.';
COMMENT ON COLUMN ZITADEL.CUSTOMER_CONFIG.CUSTOMER_PROFILE IS 'Defines if a company can use local user, federated users or both. Used by the portal.';
COMMENT ON COLUMN ZITADEL.CUSTOMER_CONFIG.SYNC_CONTACTINFO_BASE IS 'Enable/disable the sync of base user data (familyName, firstName, email, userName, sub) with the Portal.';
COMMENT ON COLUMN ZITADEL.CUSTOMER_CONFIG.SYNC_CONTACTINFO_ADVANCED IS 'Enable/disable the sync of mobile phone, business phone and job title information from Entra ID into Zitadel metadata and with the Portal.';
COMMENT ON COLUMN ZITADEL.CUSTOMER_CONFIG.ALLOW_USER_PASS_LOGIN IS 'Enable/disable username password login on the Zitadel organization.';
COMMENT ON COLUMN ZITADEL.CUSTOMER_CONFIG.ALLOW_REGISTER IS 'Enable/disable the register function on the Zitadel organization.';
COMMENT ON COLUMN ZITADEL.CUSTOMER_CONFIG.ALLOW_EXTERNAL_IDP IS 'Enable/disable external identity providers on the Zitadel organization.';
COMMENT ON COLUMN ZITADEL.CUSTOMER_CONFIG.ALLOW_DOMAIN_DISCOVERY IS 'Enable/disable domain discovery on the Zitadel organization.';
COMMENT ON COLUMN ZITADEL.CUSTOMER_CONFIG.ALLOW_PASSWORDLESS IS 'Enable/disable passwordless login on the Zitadel organization.';
COMMENT ON COLUMN ZITADEL.CUSTOMER_CONFIG.FORCE_MFA IS 'Enable/disable enforcing multi-factor authentication (MFA) on the Zitadel organization.';
COMMENT ON COLUMN ZITADEL.CUSTOMER_CONFIG.FORCE_MFA_LOCAL_ONLY IS 'Enable/disable enforcing MFA on the Zitadel organization for local users only.';
COMMENT ON COLUMN ZITADEL.CUSTOMER_CONFIG.DISABLE_EMAIL_LOGIN IS 'Enable/disable login with email on the Zitadel organization.';
COMMENT ON COLUMN ZITADEL.CUSTOMER_CONFIG.DISABLE_PHONE_LOGIN IS 'Enable/disable login with phone number on the Zitadel organization.';
COMMENT ON COLUMN ZITADEL.CUSTOMER_CONFIG.PASS_POLICY_MIN_LEN IS 'The minimum length of password if the password policy is enabled.';
COMMENT ON COLUMN ZITADEL.CUSTOMER_CONFIG.DP_VALIDATE_ORG_DOMAINS IS 'DP stands for domain policy. Enable/disable validating organization domains on the Zitadel organization.';
COMMENT ON COLUMN ZITADEL.CUSTOMER_CONFIG.DP_USER_LOGIN_WITH_DOMAIN IS 'DP stands for domain policy. Enable/disable to add domain as suffix to login name';
COMMENT ON COLUMN ZITADEL.CUSTOMER_CONFIG.DP_SMTP_ADDRESS_MATCH IS 'DP stands for domain policy. Enable/disable matching smtp sender names.';
COMMENT ON COLUMN ZITADEL.CUSTOMER_CONFIG.FORCE_ENGLISH_LANGUAGE IS 'Set preferred language to English.';
CREATE INDEX ZITADEL.IDX_CUSTOMER_CONFIG_COMPANY_ID ON ZITADEL.CUSTOMER_CONFIG (company_id);
CREATE SEQUENCE ZITADEL.CUSTOMER_CONFIG_SEQ;
GRANT SELECT, INSERT, UPDATE, DELETE ON ZITADEL.CUSTOMER_CONFIG TO SVC_CONIFER;
GRANT SELECT ON ZITADEL.CUSTOMER_CONFIG_SEQ TO SVC_CONIFER;

CREATE TABLE ZITADEL.CUSTOMER_ORG_DOMAIN (
    id NUMBER(10) NOT NULL,
    zitadel_config_id NUMBER(10) NOT NULL,
    domain VARCHAR2(255) NOT NULL,
    CONSTRAINT pk_custorgdomain PRIMARY KEY (id),
    CONSTRAINT fk_custorgdomain_zitcfg FOREIGN KEY (zitadel_config_id) REFERENCES ZITADEL.CUSTOMER_CONFIG(id),
    CONSTRAINT un_custorgdomain UNIQUE (zitadel_config_id, domain)
);
COMMENT ON TABLE ZITADEL.CUSTOMER_ORG_DOMAIN IS 'For each company, it stores a list of organization domains to match the UPN pattern for zitadel configuration. It is used for domain discovery.';
CREATE SEQUENCE ZITADEL.CUSTOMER_ORG_DOMAIN_SEQ;
GRANT SELECT, INSERT, UPDATE, DELETE ON ZITADEL.CUSTOMER_ORG_DOMAIN TO SVC_CONIFER;
GRANT SELECT ON ZITADEL.CUSTOMER_ORG_DOMAIN_SEQ TO SVC_CONIFER;

CREATE TABLE ZITADEL.IDP_AAD (
    id NUMBER(10) NOT NULL,
    zitadel_config_id NUMBER(10) NOT NULL,
    tenant_id VARCHAR2(255) NOT NULL,
    display_name VARCHAR2(255) NOT NULL,
    sync_groups NUMBER(1) DEFAULT 0 NOT NULL,
    auto_creation NUMBER(1) DEFAULT 1 NOT NULL,
    auto_update NUMBER(1) DEFAULT 1 NOT NULL,
    CONSTRAINT pk_idp_aad PRIMARY KEY (id),
    CONSTRAINT fk_idp_aad_zitcfg FOREIGN KEY (zitadel_config_id) REFERENCES ZITADEL.CUSTOMER_CONFIG(id),
    CONSTRAINT un_idp_aad_tenant UNIQUE (zitadel_config_id, tenant_id)
);
COMMENT ON TABLE ZITADEL.IDP_AAD IS 'For each company, it stores the information of the Microsoft Azure Tenant identity provider(s) in Zitadel.';
COMMENT ON COLUMN ZITADEL.IDP_AAD.TENANT_ID IS 'The ID of the Microsoft Azure Tenant with whom to federate with Zitadel.';
COMMENT ON COLUMN ZITADEL.IDP_AAD.DISPLAY_NAME IS 'The display name of the Microsoft Azure Tenant identity provider in Zitadel.';
COMMENT ON COLUMN ZITADEL.IDP_AAD.SYNC_GROUPS IS 'Enable/disable the sync of Entra ID group IDs.';
COMMENT ON COLUMN ZITADEL.IDP_AAD.AUTO_CREATION IS 'Defines if a new account in ZITADEL should be created automatically on login with an external account.';
COMMENT ON COLUMN ZITADEL.IDP_AAD.AUTO_UPDATE IS 'Defines if a the ZITADEL account fields should be updated automatically on each login.';
CREATE SEQUENCE ZITADEL.IDP_AAD_SEQ;
GRANT SELECT, INSERT, UPDATE, DELETE ON ZITADEL.IDP_AAD TO SVC_CONIFER;
GRANT SELECT ON ZITADEL.IDP_AAD_SEQ TO SVC_CONIFER;

CREATE TABLE ZITADEL.IDP_OKTA (
    id NUMBER(10) NOT NULL,
    zitadel_config_id NUMBER(10) NOT NULL,
    issuer_url VARCHAR2(255) NOT NULL,
    display_name VARCHAR2(255) NOT NULL,
    auto_creation NUMBER(1) DEFAULT 1 NOT NULL,
    auto_update NUMBER(1) DEFAULT 1 NOT NULL,
    CONSTRAINT pk_idp_okta PRIMARY KEY (id),
    CONSTRAINT fk_idp_okta_zitcfg FOREIGN KEY (zitadel_config_id) REFERENCES ZITADEL.CUSTOMER_CONFIG(id),
    CONSTRAINT un_idp_okta_issuer UNIQUE (zitadel_config_id, issuer_url)
);
COMMENT ON TABLE ZITADEL.IDP_OKTA IS 'For each company, it stores the information of the Okta identity provider(s) in Zitadel.';
COMMENT ON COLUMN ZITADEL.IDP_OKTA.ISSUER_URL IS 'The URL of the Okta IdP to federate with.';
COMMENT ON COLUMN ZITADEL.IDP_OKTA.DISPLAY_NAME IS 'The display name of the Okta identity provider in Zitadel.';
COMMENT ON COLUMN ZITADEL.IDP_OKTA.AUTO_CREATION IS 'Defines if a new account in ZITADEL should be created automatically on login with an Okta account.';
COMMENT ON COLUMN ZITADEL.IDP_OKTA.AUTO_UPDATE IS 'Defines if a the ZITADEL account fields should be updated automatically on each login with an Okta account.';
CREATE SEQUENCE ZITADEL.IDP_OKTA_SEQ;
GRANT SELECT, INSERT, UPDATE, DELETE ON ZITADEL.IDP_OKTA TO SVC_CONIFER;
GRANT SELECT ON ZITADEL.IDP_OKTA_SEQ TO SVC_CONIFER;

CREATE TABLE ZITADEL.IDP_GENERIC_OIDC (
    id NUMBER(10) NOT NULL,
    zitadel_config_id NUMBER(10) NOT NULL,
    issuer_url VARCHAR2(255) NOT NULL,
    display_name VARCHAR2(255) NOT NULL,
    auto_creation NUMBER(1) DEFAULT 1 NOT NULL,
    auto_update NUMBER(1) DEFAULT 1 NOT NULL,
    CONSTRAINT pk_idp_genoidc PRIMARY KEY (id),
    CONSTRAINT fk_idp_genoidc_zitcfg FOREIGN KEY (zitadel_config_id) REFERENCES ZITADEL.CUSTOMER_CONFIG(id),
    CONSTRAINT un_idp_genoidc_issuer UNIQUE (zitadel_config_id, issuer_url)
);
COMMENT ON TABLE ZITADEL.IDP_GENERIC_OIDC IS 'For each company, it stores the information of the generic OIDC identity provider(s) in Zitadel.';
COMMENT ON COLUMN ZITADEL.IDP_GENERIC_OIDC.ISSUER_URL IS 'The URL of the generic OIDC IdP to federate with.';
COMMENT ON COLUMN ZITADEL.IDP_GENERIC_OIDC.DISPLAY_NAME IS 'The display name of the generic OIDC identity provider in Zitadel.';
COMMENT ON COLUMN ZITADEL.IDP_GENERIC_OIDC.AUTO_CREATION IS 'Defines if a new account in ZITADEL should be created automatically on login with a generic OIDC account.';
COMMENT ON COLUMN ZITADEL.IDP_GENERIC_OIDC.AUTO_UPDATE IS 'Defines if a the ZITADEL account fields should be updated automatically on each login with a generic OIDC account.';
CREATE SEQUENCE ZITADEL.IDP_GENERIC_OIDC_SEQ;
GRANT SELECT, INSERT, UPDATE, DELETE ON ZITADEL.IDP_GENERIC_OIDC TO SVC_CONIFER;
GRANT SELECT ON ZITADEL.IDP_GENERIC_OIDC_SEQ TO SVC_CONIFER;

CREATE TABLE ZITADEL.ADDITIONAL_PROJECTS_GRANTED (
    id NUMBER(10) NOT NULL,
    zitadel_config_id NUMBER(10) NOT NULL,
    project_name VARCHAR2(255) NOT NULL,
    CONSTRAINT pk_addprjgranted PRIMARY KEY (id),
    CONSTRAINT fk_addprjgranted_zitcfg FOREIGN KEY (zitadel_config_id) REFERENCES ZITADEL.CUSTOMER_CONFIG(id),
    CONSTRAINT un_addprjgranted UNIQUE (zitadel_config_id, project_name)
);
COMMENT ON TABLE ZITADEL.ADDITIONAL_PROJECTS_GRANTED IS 'For each company, it stores a list of projects to grant additionally to the default set of projects. Can be used to provide early-access to new APIs.';
CREATE SEQUENCE ZITADEL.ADDITIONAL_PROJECTS_GRANTED_SEQ;
GRANT SELECT, INSERT, UPDATE, DELETE ON ZITADEL.ADDITIONAL_PROJECTS_GRANTED TO SVC_CONIFER;
GRANT SELECT ON ZITADEL.ADDITIONAL_PROJECTS_GRANTED_SEQ TO SVC_CONIFER;

CREATE TABLE ZITADEL.IDP_AAD_APPS_NO_SYNC (
    id NUMBER(10) NOT NULL,
    idp_aad_id NUMBER(10) NOT NULL,
    app_id VARCHAR2(255) NOT NULL,
    CONSTRAINT pk_idpaadappsnosync PRIMARY KEY (id),
    CONSTRAINT fk_idpaadappsnosync_zitcfg FOREIGN KEY (idp_aad_id) REFERENCES ZITADEL.IDP_AAD(id),
    CONSTRAINT un_idpaadappsnosync UNIQUE (idp_aad_id, app_id)
);
COMMENT ON TABLE ZITADEL.IDP_AAD_APPS_NO_SYNC IS 'For each idp aad of a company, it stores a list with Zitadel application IDs for which to skip the sync.';
CREATE SEQUENCE ZITADEL.IDP_AAD_APPS_NO_SYNC_SEQ;
GRANT SELECT, INSERT, UPDATE, DELETE ON ZITADEL.IDP_AAD_APPS_NO_SYNC TO SVC_CONIFER;
GRANT SELECT ON ZITADEL.IDP_AAD_APPS_NO_SYNC_SEQ TO SVC_CONIFER;

--changeset nom:2549
--comment: OSAP-1776: force a unique zitadel customer config for each company
DROP INDEX ZITADEL.IDX_CUSTOMER_CONFIG_COMPANY_ID;
CREATE UNIQUE INDEX ZITADEL.CUSTOMER_CONF_COMPANY_ID_UQ ON ZITADEL.CUSTOMER_CONFIG (company_id);

--changeset jmu:2550
--comment: PRX-10008: drop unused column CUSTOM_FEED_BUNDLE from TIM.POLICY;
ALTER TABLE TIM.POLICY DROP COLUMN CUSTOM_FEED_BUNDLE;

--changeset jmu:2551
--comment: PRX-10008: grant permissions on TIM.POLICY to SVC_CONIFER
GRANT SELECT, INSERT, UPDATE, DELETE ON TIM.POLICY TO SVC_CONIFER;
GRANT SELECT ON TIM.POLICY_SEQ TO SVC_CONIFER;

--changeset quv:2552
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM dba_users WHERE username='SVC_CALLER_LOOKUP'
CREATE USER "SVC_CALLER_LOOKUP" IDENTIFIED BY "xxxxxx" ACCOUNT LOCK
  DEFAULT TABLESPACE "USERS"
  TEMPORARY TABLESPACE "TEMP";

--changeset quv:2553 contextFilter:dummyPasswords
--comment: only for login users, not for schema users
ALTER USER "SVC_CALLER_LOOKUP" IDENTIFIED BY "password" ACCOUNT UNLOCK;

--changeset quv:2554
--comment: Grants for caller lookup: contact info by contact ID
GRANT "MSS_LOGIN_USER" TO "SVC_CALLER_LOOKUP";
ALTER USER "SVC_CALLER_LOOKUP" DEFAULT ROLE "MSS_LOGIN_USER";
GRANT SELECT ON STOP.CONTACT TO SVC_CALLER_LOOKUP;
GRANT SELECT ON STOP.COMPANY TO SVC_CALLER_LOOKUP;

--changeset mma:2555
--comment: Add TIM_MIGRATION user
CREATE USER "TIM_MIGRATION" IDENTIFIED BY "xxxxxx" ACCOUNT LOCK
    DEFAULT TABLESPACE "USERS"
    TEMPORARY TABLESPACE "TEMP";

GRANT "MSS_LOGIN_USER" TO "TIM_MIGRATION";
ALTER USER "TIM_MIGRATION" DEFAULT ROLE "MSS_LOGIN_USER";
GRANT EXEMPT ACCESS POLICY TO "TIM_MIGRATION";

--changeset ogl:2556 contextFilter:dummyPasswords
--comment: only for login users, not for schema users
ALTER USER "TIM_MIGRATION" IDENTIFIED BY "password" ACCOUNT UNLOCK;

--changeset ogl:2557
--comment: ORE-36992 drop SVC_ALERTHANDLER
drop user SVC_ALERTHANDLER;

--changeset jmu:2558
--comment: PRX-10008 add constraints to allow only one threat protection policy per scope
ALTER TABLE TIM.POLICY ADD CONSTRAINT U_POLICY_COMPANY UNIQUE (COMPANY_ID);
ALTER TABLE TIM.POLICY ADD CONSTRAINT U_POLICY_GROUP UNIQUE (GROUP_ID);
ALTER TABLE TIM.POLICY ADD CONSTRAINT U_POLICY_SERVICE UNIQUE (SERVICE_ID);
ALTER TABLE TIM.POLICY ADD CONSTRAINT U_POLICY_HOST UNIQUE (HOST_ID);

--changeset jmu:2559
--comment: PRX-10008 add constraint to allow only one threat protection policy on default scope
CREATE UNIQUE INDEX IDX_UNIQUE_DEFAULT_SCOPE_POLICY ON TIM.POLICY (CASE WHEN SCOPE_ID = 9 THEN SCOPE_ID END);

--changeset nom:2560
--comment: OSAP-1776: grant the missing permissions to ZITADEL 
ALTER USER "ZITADEL" QUOTA UNLIMITED ON "USERS";

--changeset pem:2561
--comment: NIDS-INVESTIGATION: allow nullable investigation contact and add Zitadel subject columns
ALTER TABLE NIDS.INVESTIGATION MODIFY CONTACT_ID NULL;

ALTER TABLE NIDS.INVESTIGATION ADD ZITADEL_USER_ID VARCHAR2(128) NULL;
COMMENT ON COLUMN NIDS.INVESTIGATION.ZITADEL_USER_ID IS 'Zitadel subject (sub) of the user that last changed this investigation row';

ALTER TABLE NIDS.INVESTIGATION_ENTRY ADD ZITADEL_USER_ID VARCHAR2(128) NULL;
COMMENT ON COLUMN NIDS.INVESTIGATION_ENTRY.ZITADEL_USER_ID IS 'Zitadel subject (sub) copied from NIDS.INVESTIGATION at investigation entry write time';

-- staged rollout: suppress generated java fields until all environments are migrated
INSERT INTO NIDS."#JDO_PROPERTIES" (KEY, VALUE) VALUES ('INVESTIGATION.naming.ZITADEL_USER_ID', 'none');
INSERT INTO NIDS."#JDO_PROPERTIES" (KEY, VALUE) VALUES ('INVESTIGATION_ENTRY.naming.ZITADEL_USER_ID', 'none');

--changeset nop:2562
--comment: SRE-1770 Add monitored column to VPN.TUNNEL for alerting on tunnel conditions
ALTER TABLE VPN.TUNNEL ADD MONITORED NUMBER(1) DEFAULT ON NULL 0 NOT NULL;
COMMENT ON COLUMN VPN.TUNNEL.MONITORED IS '1 for alerting on tunnel conditions';

--changeset jmu:2563
--comment: PRX-10008: add threat protection policy audit record types
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID)
VALUES (509, 'TP policy created', 'tim_policy_created', 'A threat protection policy was created.', 1);
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID)
VALUES (510, 'TP policy modified', 'tim_policy_modified', 'A threat protection policy was modified.', 1);
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID)
VALUES (511, 'TP policy deleted', 'tim_policy_deleted', 'A threat protection policy was deleted.', 1);

--changeset mlo:2446
--comment: STAFFE-83: support zitadel only users in audit trail view
UPDATE MCAUDIT."#JDO_PROPERTIES" SET VALUE='zitadelUserId' WHERE KEY='RECORD.naming.ZITADEL_USER_ID';
UPDATE MCAUDIT."#JDO_PROPERTIES" SET VALUE='zitadelUserName' WHERE KEY='RECORD.naming.ZITADEL_USER_NAME';
UPDATE MCAUDIT."#JDO_PROPERTIES" SET VALUE='zitadelUserCompany' WHERE KEY='RECORD.naming.ZITADEL_USER_COMPANY_ID';

--changeset jmu:2564
--comment: PRX-10008: enforce protection level constraints in DB
ALTER TABLE TIM.POLICY ADD CONSTRAINT C_PROT_LT_LOG_ONLY CHECK (PROTECTION_LEVEL < LOG_ONLY_PROTECTION_LEVEL);
ALTER TABLE TIM.POLICY ADD CONSTRAINT C_PROT_LEVEL_VALUES CHECK (PROTECTION_LEVEL IN (1,2,3));
ALTER TABLE TIM.POLICY ADD CONSTRAINT C_PROT_LOG_ONLY_VALUES CHECK (LOG_ONLY_PROTECTION_LEVEL IN (1,2,3));

--changeset mma:2565
--comment: PRX-10076: remove migrate.squid.geoip.v2 dbprop
DELETE FROM mss.value WHERE key_id IN (SELECT id FROM mss.key WHERE name = 'migrate.squid.geoip.v2');
DELETE FROM mss.key WHERE name = 'migrate.squid.geoip.v2';

--changeset rse:2566
--comment: feat(openvpn/config): add `dbprop` to activate mitigations for hosts with broken path MTU discovery
INSERT INTO MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
VALUES (21490, 'openvpn.low_mtu', 1, '0', '^[01]$', null, 'Enable static MTU/MSS mitigations for OpenVPN clients with broken path MTU discovery.');

--changeset rse:2567
--comment: feat(time-sync/config): add `dbprop`s to configure local reference clock (e.g. /dev/ptp_hyperv on hyperv hosts)
INSERT INTO MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
VALUES (21500, 'ntp.local_refclock', 1, '0', '^[01]$', null, 'Enable local reference clock (e.g. /dev/ptp_hyperv on hyperv hosts) for time synchronization.');
--
INSERT INTO MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
VALUES (21501, 'ntp.local_refclock.noselect', 1, '1', '^[01]$', null, 'Never select the local reference clock for time synchronization (monitoring only).');

--changeset mag:2568
--comment: fix(dbprop): remove SWG weak cipher suites
update mss.KEY set string_default='AESGCM:HIGH:+kEECDH:+kEDH:+kRSA:!EXP:!eNULL:!aNULL:!CAMELLIA:!DSS:!SRP:!PSK:!kECDH:!kDH:!SHA256:!SHA384:-DHE-RSA-CHACHA20-POLY1305:!ARIA:!AESCCM:!ECDHE-ECDSA-AES128-SHA:!ECDHE-ECDSA-AES256-SHA:!DHE-RSA-AES128-SHA:!DHE-RSA-AES256-SHA:!AES256-SHA' where name='squid.sslscan.ciphers.client' or name='squid.sslscan.ciphers.server';

--changeset nom:2569
--comment: OSAP-1838: Update ZITADEL tables
ALTER TABLE ZITADEL.CUSTOMER_CONFIG DROP COLUMN sync_contactinfo_base;
ALTER TABLE ZITADEL.CUSTOMER_CONFIG ADD sync_contactinfo_base NUMBER(1) NULL;
ALTER TABLE ZITADEL.CUSTOMER_CONFIG DROP COLUMN sync_contactinfo_advanced;
ALTER TABLE ZITADEL.CUSTOMER_CONFIG ADD sync_contactinfo_advanced NUMBER(1) NULL;
ALTER TABLE ZITADEL.IDP_AAD ADD name VARCHAR2(128) NOT NULL;
ALTER TABLE ZITADEL.IDP_AAD DROP CONSTRAINT un_idp_aad_tenant;
ALTER TABLE ZITADEL.IDP_AAD
ADD CONSTRAINT un_idp_aad_name UNIQUE (zitadel_config_id, name);

ALTER TABLE ZITADEL.IDP_OKTA ADD name VARCHAR2(128) NOT NULL;
ALTER TABLE ZITADEL.IDP_OKTA DROP CONSTRAINT un_idp_okta_issuer;
ALTER TABLE ZITADEL.IDP_OKTA
ADD CONSTRAINT un_idp_okta_name UNIQUE (zitadel_config_id, name);

ALTER TABLE ZITADEL.IDP_GENERIC_OIDC ADD name VARCHAR2(128) NOT NULL;
ALTER TABLE ZITADEL.IDP_GENERIC_OIDC DROP CONSTRAINT un_idp_genoidc_issuer;
ALTER TABLE ZITADEL.IDP_GENERIC_OIDC
ADD CONSTRAINT un_idp_genoidc_name UNIQUE (zitadel_config_id, name);

--changeset thw:2570
--comment: fix(mc-config-api): SRE-1939 grant svc_conifer INSERT on NAT_IIFACE_2_OIFACE so hiding-NAT incoming interfaces survive an interface modify (svc_conifer already has DELETE+SELECT but not INSERT, so a modify wiped them)
GRANT INSERT ON MSS.NAT_IIFACE_2_OIFACE TO SVC_CONIFER;

--changeset ssk:2571
--comment: Rename misnamed foreign keys on FW.MAINTAINED_OBJECTS2SRV_GROUP
ALTER TABLE FW.MAINTAINED_OBJECTS2SRV_GROUP RENAME CONSTRAINT FK_MAINTOBJS2SRGROUP_IPGROUP TO FK_MAINTOBJS2SRVGROUP_SERVICEGROUP;
ALTER TABLE FW.MAINTAINED_OBJECTS2SRV_GROUP RENAME CONSTRAINT FK_MAINTOBJS2SRGROUP_MAINTOBJS TO FK_MAINTOBJS2SRVGROUP_MAINTOBJS;

--changeset jmu:2572
--comment: feat(cswg): add dbprops to migrate upsid tpb and surbl
INSERT INTO MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
VALUES (57290, 'migrate.upsid.surbl.shared', 1, '0', '^[01]$', null, 'Use shared bind instance for upsid surbl feed.');
--
INSERT INTO MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
VALUES (57291, 'migrate.upsid.tpb.shared', 1, '0', '^[01]$', null, 'Use shared bind instance for upsid tpb feed.');

--changeset mma:2573
--comment: feat(cswg): add dbprop to migrate to new cert validator
INSERT INTO MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
VALUES (57292, 'migrate.2026.squid.crlite', 1, '0', '^[01]$', null, 'Use new squid certificate validator with CRLite integration.');

--changeset ogl:2574
--comment: missing FK index
create index FW.IDX_SCOPEDIPGROUP_IPGROUP on FW.SCOPED_IP_GROUP_SCOPE(IP_GROUP_ID);

--changeset mlo:2575
--comment: MC-32490: create new API user editor component
INSERT INTO MCAUDIT.COMPONENT (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID) VALUES (85, 'API User Editor', 'api_user_editor', 'API User Editor', 5);

--changeset mlo:2576
--comment: MC-32490: fix audit trail record type names for API users
UPDATE MCAUDIT.RECORD_TYPE SET NAME = 'API token created' WHERE ID = 370;
UPDATE MCAUDIT.RECORD_TYPE SET NAME = 'API token deleted' WHERE ID = 371;
UPDATE MCAUDIT.RECORD_TYPE SET NAME = 'API user created' WHERE ID = 367;
UPDATE MCAUDIT.RECORD_TYPE SET NAME = 'API user deleted' WHERE ID = 369;
UPDATE MCAUDIT.RECORD_TYPE SET NAME = 'API user updated' WHERE ID = 368;

--changeset nis:2577
--comment: MC-32427: Remove ORM generation for metrics columns of VPN tunnel table
insert into VPN."#JDO_PROPERTIES" (key, value)
values ('TUNNEL.naming.LOSS', 'none');
insert into VPN."#JDO_PROPERTIES" (key, value)
values ('TUNNEL.naming.OCTETS_PER_SECOND_IN', 'none');
insert into VPN."#JDO_PROPERTIES" (key, value)
values ('TUNNEL.naming.OCTETS_PER_SECOND_OUT', 'none');
insert into VPN."#JDO_PROPERTIES" (key, value)
values ('TUNNEL.naming.RTT', 'none');
insert into VPN."#JDO_PROPERTIES" (key, value)
values ('TUNNEL.naming.STATUS', 'none');
insert into VPN."#JDO_PROPERTIES" (key, value)
values ('TUNNEL.naming.STATUS_DATE', 'none');

--changeset mma:2578
--comment: PRX-10016: Grant TIM_MIGRATION user use of TIM.POLICY_SEQ for inserting values
GRANT SELECT ON TIM.POLICY_SEQ TO TIM_MIGRATION;
GRANT SELECT,INSERT,UPDATE,DELETE on TIM.POLICY TO TIM_MIGRATION;

--changeset nis:2579
--comment: feat(dx/portals): add dbprop to control raw report access
INSERT INTO MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
VALUES (57293, 'pdfreport.raw.nids.enabled', 1, '0', '^[01]$', null, 'Controls access to raw nids reports.');

INSERT INTO MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
VALUES (57294, 'pdfreport.raw.proxy.enabled', 1, '0', '^[01]$', null, 'Controls access to raw proxy reports.');

INSERT INTO MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
VALUES (57295, 'pdfreport.raw.mail.enabled', 1, '0', '^[01]$', null, 'Controls access to raw mail reports.');

--changeset nis:2580
--comment: feat(dx/portals): Adds missing grants for SVC_USERS_INTERNAL_API to access event tables
GRANT SELECT on TT.EVENT_TYPE to SVC_USERS_INTERNAL_API;
GRANT SELECT on TT.EVENT_TYPE_GROUP to SVC_USERS_INTERNAL_API;
GRANT SELECT on TT.EVENT_NOTIFICATION_TYPE to SVC_USERS_INTERNAL_API;
GRANT SELECT,INSERT,UPDATE,DELETE on TT.EVENT_NOTIFICATION to SVC_USERS_INTERNAL_API;
GRANT SELECT ON TT.EVENTNOTIFICATION_SEQ TO SVC_USERS_INTERNAL_API;

--changeset mcg:2581
--comment: add ztna modify tenant audit record
INSERT INTO MCAUDIT.RECORD_TYPE (ID, NAME, SHORT, DESCRIPTION, SYSTEM_ID)
VALUES (512, 'ZTNA modify-tenant', 'modify-tenant', 'A ZTNA tenant has been modified', 1);

--changeset jmj:2582
--comment: feat(perlticket): grant PERLTICKET read access to MSS.HOST and MSS.HOST2SERVICE for OSAG::Ticketing
GRANT SELECT ON MSS.HOST TO PERLTICKET;
GRANT SELECT ON MSS.HOST2SERVICE TO PERLTICKET;

--changeset nis:2583
--comment: MC-32584: point the "new reports available" notification to the new Reports view
UPDATE TT.EVENT_TYPE_MESSAGE SET MESSAGE_TEMPLATE = 'This is an automatically generated email to inform you
that new reports were generated and are available
for download at

https://control.open.ch/mc/companies/$#COMPANY_ID#$/reports

To view the complete ticket in the Open Systems Customer Portal,
click here:
https://control.open.ch/mc/ticket/$#TICKET_ID#$' WHERE ID = 18;

--changeset nom:2584
--comment: OSAP-1674: Update ZITADEL tables default values
ALTER TABLE ZITADEL.CUSTOMER_CONFIG DROP COLUMN allow_user_pass_login;
ALTER TABLE ZITADEL.CUSTOMER_CONFIG ADD allow_user_pass_login NUMBER(1) DEFAULT 1 NOT NULL;
ALTER TABLE ZITADEL.CUSTOMER_CONFIG DROP COLUMN allow_register;
ALTER TABLE ZITADEL.CUSTOMER_CONFIG ADD allow_register NUMBER(1) DEFAULT 0 NOT NULL;
ALTER TABLE ZITADEL.CUSTOMER_CONFIG DROP COLUMN force_mfa_local_only;
ALTER TABLE ZITADEL.CUSTOMER_CONFIG ADD force_mfa_local_only NUMBER(1) DEFAULT 1 NOT NULL;
ALTER TABLE ZITADEL.CUSTOMER_CONFIG DROP COLUMN disable_phone_login;
ALTER TABLE ZITADEL.CUSTOMER_CONFIG ADD disable_phone_login NUMBER(1) DEFAULT 1 NOT NULL;

--changeset jkl:2585
--comment: RTNG-1562: Add dbprop to enable the CPE wan-api
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (57296, 'wan.api', 1, '0', '^[01]$', NULL, 'Enables the CPE WAN API.');

--changeset nop:2586
--comment: SRE-1976: Add SVC_AUDIT_WATCHER read-only DB user for the audit-watcher service
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM dba_users WHERE username='SVC_AUDIT_WATCHER'
CREATE USER "SVC_AUDIT_WATCHER" IDENTIFIED BY "xxxxxx" ACCOUNT LOCK
  DEFAULT TABLESPACE "USERS"
  TEMPORARY TABLESPACE "TEMP";

--changeset nop:2587 contextFilter:dummyPasswords
--comment: only for login users, not for schema users
ALTER USER "SVC_AUDIT_WATCHER" IDENTIFIED BY "password" ACCOUNT UNLOCK;

--changeset nop:2588
--comment: SRE-1976: system, object grants for SVC_AUDIT_WATCHER
GRANT "MSS_LOGIN_USER" TO "SVC_AUDIT_WATCHER";
ALTER USER "SVC_AUDIT_WATCHER" DEFAULT ROLE "MSS_LOGIN_USER";
GRANT SELECT ON MCAUDIT.RECORD TO SVC_AUDIT_WATCHER;

--changeset evv:2589
--comment: Set migrate.upsid.surbl.shared to 1 by default
UPDATE MSS.KEY k SET k.STRING_DEFAULT='1' WHERE k.NAME='migrate.upsid.surbl.shared';

--changeset ras:2590
--comment: BE-1630: Drop DB Prop migrate.2026.artifactsurl
DELETE FROM MSS.VALUE v where v.key_id = (SELECT k.id from MSS.KEY k where k.name = 'migrate.2026.artifactsurl');
DELETE FROM MSS.KEY where name = 'migrate.2026.artifactsurl';

--changeset evv:2591
--comment: Set migrate.2026.squid.proxylogd to 1 by default
UPDATE MSS.KEY k SET k.STRING_DEFAULT='1' WHERE k.NAME='migrate.2026.squid.proxylogd';

--changeset lut:2592
--comment: RTNG-1574: Add dbprop to allow redistribution of GRE peer IPs into OSPF
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (57297, 'ospfd.redist.connected.gre', 1, '0', '^[01]$', NULL, 'Allows redistribution of GRE peer IPs into OSPF.');

--changeset jkl:2593
--comment: RTNG-1603: Grant svc_conifer read access to APP_OPTIMIZATION_*
GRANT SELECT ON APPID.APP_OPTIMIZATION_SETTING      TO SVC_CONIFER;
GRANT SELECT ON APPID.APP_OPTIMIZATION_PROTOCOL     TO SVC_CONIFER;
GRANT SELECT ON APPID.APP_OPTIMIZATION_NETWORK      TO SVC_CONIFER;
GRANT SELECT ON APPID.APP_OPTIMIZATION_HOST_ADDRESS TO SVC_CONIFER;
GRANT SELECT ON APPID.OPTIMIZATION_POOL             TO SVC_CONIFER;
GRANT SELECT ON APPID.OPTIMIZATION_POOL_2_SERVICE   TO SVC_CONIFER;

--changeset sms:2594
--comment: Grant SVC_NETFABRIC read access to path selection tables
GRANT SELECT ON APPID.PATH_SELECTION_PROFILE TO SVC_NETFABRIC;
GRANT SELECT ON APPID.PATH_SELECTION_PROFILE_MEMBER TO SVC_NETFABRIC;
GRANT SELECT ON APPID.PATH_PROFILE_MEMBER_2_PROFILE TO SVC_NETFABRIC;
GRANT SELECT ON APPID.PATH_PROFILE_MEMBER_LINK TO SVC_NETFABRIC;
GRANT SELECT ON APPID.PATH_SELECTION_FAILOVER_TYPE TO SVC_NETFABRIC;
GRANT SELECT ON APPID.PATH_SELECTION_STICKINESS TO SVC_NETFABRIC;
GRANT SELECT ON APPID.PATH_SELECTION_LINK_CLASS TO SVC_NETFABRIC;
GRANT SELECT ON APPID.PATH_SELECTION_COLOR TO SVC_NETFABRIC;
GRANT SELECT ON APPID.PATH_SELECTION_OVERRIDE_MEMBER TO SVC_NETFABRIC;
GRANT SELECT ON APPID.PATH_OVERRIDE_MEMBER_LINK TO SVC_NETFABRIC;
GRANT SELECT ON APPID.PATH_OVERRIDE_DEFAULTS TO SVC_NETFABRIC;
GRANT SELECT ON APPID.PATH_PROFILE_2_LINK_CLASS TO SVC_NETFABRIC;
GRANT SELECT ON APPID.APP_2_PATH_PROFILE_MEMBER TO SVC_NETFABRIC;
GRANT SELECT ON APPID.APP_2_PATH_OVERRIDE_MEMBER TO SVC_NETFABRIC;
GRANT SELECT ON APPID.INTERFACE_2_PS_LINK_CLASS TO SVC_NETFABRIC;
GRANT SELECT ON MSS.SERVICE TO SVC_NETFABRIC;
GRANT SELECT ON MSS.INTERFACE TO SVC_NETFABRIC;
GRANT SELECT ON MSS.HOST TO SVC_NETFABRIC;

--changeset jho:2593
--comment: FW-7400: Add dbprop to toggle ping_input_rules_from_internal
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (57298, 'ping.internal', 1, '1', '^[01]$', NULL, 'Allow to ping CPE interfaces from internal networks.');

--changeset jmu:2596
--comment: Clean up migration dbprop for shared surbl zones in upsid
DELETE FROM MSS.VALUE WHERE KEY_ID = 57290;
DELETE FROM MSS.KEY WHERE ID = 57290 AND NAME = 'migrate.upsid.surbl.shared';

--changeset gks:2597
--comment: IDS-4218: Add new DB Prop ndr.ioc.tim
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (57299, 'ndr.ioc.tim', 1, '0', '^[01]$', NULL, 'Activate TIM IoCs for block and exclusion lists on the sensor.');

--changeset lut:2598
--comment: RTNG-1610: Add T2EE routing columns to APPID.PATH_SELECTION_LINK_CLASS
ALTER TABLE APPID.PATH_SELECTION_LINK_CLASS ADD T2EE_DNS_ROUTING NUMBER(1) DEFAULT 0 NOT NULL;
COMMENT ON COLUMN APPID.PATH_SELECTION_LINK_CLASS.T2EE_DNS_ROUTING IS 'Indicates if local DNS traffic is routed via this T2EE link.';
ALTER TABLE APPID.PATH_SELECTION_LINK_CLASS ADD T2EE_PROXY_ROUTING NUMBER(1) DEFAULT 0 NOT NULL;
COMMENT ON COLUMN APPID.PATH_SELECTION_LINK_CLASS.T2EE_PROXY_ROUTING IS 'Indicates if local proxy traffic is routed via this T2EE link.';

--changeset jmu:2599
--comment: Delete unused tables for EoL MSCAS integration
DROP TABLE PRX.MSCAS_BLOCKUNSANCTIONED;
DROP TABLE PRX.MSCAS_APP_BLOCKUNSANCTIONED;

--changeset igs:2600
--comment: ZTNA-2408: add new dbprop ztna.ep
INSERT INTO MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
VALUES (57300, 'ztna.ep', 1, '1', '^[01]$', NULL, 'Enable the enforcement point');

--changeset jmu:2601
--comment: restrict deletion of a service that still has an exclusive IP attached
ALTER TABLE MSS.EXCLUSIVE_IP DROP CONSTRAINT EXCLUSIVE_IP_FK2;
ALTER TABLE MSS.EXCLUSIVE_IP ADD CONSTRAINT EXCLUSIVE_IP_FK2 FOREIGN KEY (SERVICE_ID) REFERENCES MSS.SERVICE (ID);

--changeset sst:2602
--comment: IE-169: allow localcontact delete by granting delete on notification links
GRANT DELETE ON MSS.LOCAL_CONTACT_NOTIFICATION TO SVC_CONIFER;

--changeset gip:2603
--comment: MX-7372: Grant configAPI (SVC_CONIFER) access to DKIM tables (SELECT/INSERT/UPDATE/DELETE)
GRANT SELECT ON MAIL.DKIM_KEY TO SVC_CONIFER;
GRANT SELECT ON MAIL.DKIM_KEY_STATE TO SVC_CONIFER;
GRANT SELECT ON MAIL.DKIM_PRIVATE_KEY TO SVC_CONIFER;
GRANT SELECT ON MAIL.DOMAIN TO SVC_CONIFER;
GRANT SELECT ON MSS.DNS_ZONE TO SVC_CONIFER;
GRANT SELECT ON MSS.DNS_RECORD TO SVC_CONIFER;
GRANT INSERT,UPDATE,DELETE ON MAIL.DKIM_KEY TO SVC_CONIFER;
GRANT INSERT,UPDATE,DELETE ON MAIL.DKIM_KEY_STATE TO SVC_CONIFER;
GRANT INSERT,UPDATE,DELETE ON MAIL.DKIM_PRIVATE_KEY TO SVC_CONIFER;
GRANT INSERT,UPDATE,DELETE ON MAIL.DOMAIN TO SVC_CONIFER;
GRANT INSERT,UPDATE,DELETE ON MSS.DNS_ZONE TO SVC_CONIFER;
GRANT INSERT,UPDATE,DELETE ON MSS.DNS_RECORD TO SVC_CONIFER;
GRANT SELECT ON MAIL.DKIM_KEY_SEQ TO SVC_CONIFER;
GRANT SELECT ON MAIL.DOMAIN_SEQ TO SVC_CONIFER;
GRANT SELECT ON MSS.DNSZONE_SEQ TO SVC_CONIFER;
GRANT SELECT ON MSS.DNSRECORD_SEQ TO SVC_CONIFER;

--changeset hah:2604
--comment: RTNG-1626: Drop DB Prop ospfd.routerid.legacy
DELETE FROM MSS.VALUE v where v.key_id = (SELECT k.id from MSS.KEY k where k.name = 'ospfd.routerid.legacy');
DELETE FROM MSS.KEY where name = 'ospfd.routerid.legacy';

--changeset ogl:2605 endDelimiter:/
--comment: create empty dummy procedure for the grant below
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM dba_objects WHERE object_type='PROCEDURE' AND object_name='DELETE_AUTO_IP_GROUPS'
CREATE PROCEDURE FW.DELETE_AUTO_IP_GROUPS () AS
BEGIN
    NULL;
END FW.DELETE_AUTO_IP_GROUPS;
/

--changeset ogl:2606
GRANT EXECUTE ON FW.DELETE_AUTO_IP_GROUPS TO NIDS;

--changeset alg:2607 tag:v2.5.1
--comment: This changeset servers as export marker for SCN 628454616564
SELECT 1 FROM DUAL;

--changeset rha:2608
--comment: adjust regex of the dbprop sslvpn.icp: make the trailing HTML entity optional
update mss.key set regexp='^(?:\&amp;\#[A-Za-z0-9]+\;)ICP(?:\&amp;\#[A-Za-z0-9]+\;)\d+(?:\&amp;\#[A-Za-z0-9]+\;)?(?:-\d+)?$' where id=21607 and name='sslvpn.icp';

--changeset yuy:2609
--comment: IDS-4166: Add new DB Props for homenet
insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (57400, 'ndr.homenet', 4, '10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 fc00::/7', '^(?:(?:(?:25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\.){3}(?:25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\/(?:3[0-2]|[12]?[0-9])|(?:(?:[0-9A-Fa-f]{1,4}:){7}[0-9A-Fa-f]{1,4}|(?:[0-9A-Fa-f]{1,4}:){1,7}:|(?:[0-9A-Fa-f]{1,4}:){1,6}:[0-9A-Fa-f]{1,4}|(?:[0-9A-Fa-f]{1,4}:){1,5}(?::[0-9A-Fa-f]{1,4}){1,2}|(?:[0-9A-Fa-f]{1,4}:){1,4}(?::[0-9A-Fa-f]{1,4}){1,3}|(?:[0-9A-Fa-f]{1,4}:){1,3}(?::[0-9A-Fa-f]{1,4}){1,4}|(?:[0-9A-Fa-f]{1,4}:){1,2}(?::[0-9A-Fa-f]{1,4}){1,5}|[0-9A-Fa-f]{1,4}:(?::[0-9A-Fa-f]{1,4}){1,6}|:(?::[0-9A-Fa-f]{1,4}){1,7}|::)\/(?:12[0-8]|1[01][0-9]|[1-9]?[0-9]))(?: (?:(?:(?:25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\.){3}(?:25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\/(?:3[0-2]|[12]?[0-9])|(?:(?:[0-9A-Fa-f]{1,4}:){7}[0-9A-Fa-f]{1,4}|(?:[0-9A-Fa-f]{1,4}:){1,7}:|(?:[0-9A-Fa-f]{1,4}:){1,6}:[0-9A-Fa-f]{1,4}|(?:[0-9A-Fa-f]{1,4}:){1,5}(?::[0-9A-Fa-f]{1,4}){1,2}|(?:[0-9A-Fa-f]{1,4}:){1,4}(?::[0-9A-Fa-f]{1,4}){1,3}|(?:[0-9A-Fa-f]{1,4}:){1,3}(?::[0-9A-Fa-f]{1,4}){1,4}|(?:[0-9A-Fa-f]{1,4}:){1,2}(?::[0-9A-Fa-f]{1,4}){1,5}|[0-9A-Fa-f]{1,4}:(?::[0-9A-Fa-f]{1,4}){1,6}|:(?::[0-9A-Fa-f]{1,4}){1,7}|::)\/(?:12[0-8]|1[01][0-9]|[1-9]?[0-9])))*$', NULL, 'Networks considered internal/home networks for NDR (space separated list of IPv4/IPv6 CIDRs)');

insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (57401, 'ndr.homenet.extend', 4, '', '^(?:(?:(?:25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\.){3}(?:25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\/(?:3[0-2]|[12]?[0-9])|(?:(?:[0-9A-Fa-f]{1,4}:){7}[0-9A-Fa-f]{1,4}|(?:[0-9A-Fa-f]{1,4}:){1,7}:|(?:[0-9A-Fa-f]{1,4}:){1,6}:[0-9A-Fa-f]{1,4}|(?:[0-9A-Fa-f]{1,4}:){1,5}(?::[0-9A-Fa-f]{1,4}){1,2}|(?:[0-9A-Fa-f]{1,4}:){1,4}(?::[0-9A-Fa-f]{1,4}){1,3}|(?:[0-9A-Fa-f]{1,4}:){1,3}(?::[0-9A-Fa-f]{1,4}){1,4}|(?:[0-9A-Fa-f]{1,4}:){1,2}(?::[0-9A-Fa-f]{1,4}){1,5}|[0-9A-Fa-f]{1,4}:(?::[0-9A-Fa-f]{1,4}){1,6}|:(?::[0-9A-Fa-f]{1,4}){1,7}|::)\/(?:12[0-8]|1[01][0-9]|[1-9]?[0-9]))(?: (?:(?:(?:25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\.){3}(?:25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\/(?:3[0-2]|[12]?[0-9])|(?:(?:[0-9A-Fa-f]{1,4}:){7}[0-9A-Fa-f]{1,4}|(?:[0-9A-Fa-f]{1,4}:){1,7}:|(?:[0-9A-Fa-f]{1,4}:){1,6}:[0-9A-Fa-f]{1,4}|(?:[0-9A-Fa-f]{1,4}:){1,5}(?::[0-9A-Fa-f]{1,4}){1,2}|(?:[0-9A-Fa-f]{1,4}:){1,4}(?::[0-9A-Fa-f]{1,4}){1,3}|(?:[0-9A-Fa-f]{1,4}:){1,3}(?::[0-9A-Fa-f]{1,4}){1,4}|(?:[0-9A-Fa-f]{1,4}:){1,2}(?::[0-9A-Fa-f]{1,4}){1,5}|[0-9A-Fa-f]{1,4}:(?::[0-9A-Fa-f]{1,4}){1,6}|:(?::[0-9A-Fa-f]{1,4}){1,7}|::)\/(?:12[0-8]|1[01][0-9]|[1-9]?[0-9])))*$', NULL, 'Additional networks to add on top of ndr.homenet (space separated list of IPv4/IPv6 CIDRs)');

insert into MSS.KEY (ID, NAME, KEY_TYPE_ID, STRING_DEFAULT, REGEXP, OPERATING_SYSTEM_ID, DESCRIPTION)
values (57402, 'ndr.homenet.exclude', 4, '', '^(?:(?:(?:25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\.){3}(?:25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\/(?:3[0-2]|[12]?[0-9])|(?:(?:[0-9A-Fa-f]{1,4}:){7}[0-9A-Fa-f]{1,4}|(?:[0-9A-Fa-f]{1,4}:){1,7}:|(?:[0-9A-Fa-f]{1,4}:){1,6}:[0-9A-Fa-f]{1,4}|(?:[0-9A-Fa-f]{1,4}:){1,5}(?::[0-9A-Fa-f]{1,4}){1,2}|(?:[0-9A-Fa-f]{1,4}:){1,4}(?::[0-9A-Fa-f]{1,4}){1,3}|(?:[0-9A-Fa-f]{1,4}:){1,3}(?::[0-9A-Fa-f]{1,4}){1,4}|(?:[0-9A-Fa-f]{1,4}:){1,2}(?::[0-9A-Fa-f]{1,4}){1,5}|[0-9A-Fa-f]{1,4}:(?::[0-9A-Fa-f]{1,4}){1,6}|:(?::[0-9A-Fa-f]{1,4}){1,7}|::)\/(?:12[0-8]|1[01][0-9]|[1-9]?[0-9]))(?: (?:(?:(?:25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\.){3}(?:25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\/(?:3[0-2]|[12]?[0-9])|(?:(?:[0-9A-Fa-f]{1,4}:){7}[0-9A-Fa-f]{1,4}|(?:[0-9A-Fa-f]{1,4}:){1,7}:|(?:[0-9A-Fa-f]{1,4}:){1,6}:[0-9A-Fa-f]{1,4}|(?:[0-9A-Fa-f]{1,4}:){1,5}(?::[0-9A-Fa-f]{1,4}){1,2}|(?:[0-9A-Fa-f]{1,4}:){1,4}(?::[0-9A-Fa-f]{1,4}){1,3}|(?:[0-9A-Fa-f]{1,4}:){1,3}(?::[0-9A-Fa-f]{1,4}){1,4}|(?:[0-9A-Fa-f]{1,4}:){1,2}(?::[0-9A-Fa-f]{1,4}){1,5}|[0-9A-Fa-f]{1,4}:(?::[0-9A-Fa-f]{1,4}){1,6}|:(?::[0-9A-Fa-f]{1,4}){1,7}|::)\/(?:12[0-8]|1[01][0-9]|[1-9]?[0-9])))*$', NULL, 'Networks to exclude from ndr.homenet (space separated list of IPv4/IPv6 CIDRs)');

--changeset rha:2610
--comment: revert regex of the dbprop sslvpn.icp: trailing HTML entity is mandatory
update mss.key set regexp='^(?:\&amp;\#[A-Za-z0-9]+\;)ICP(?:\&amp;\#[A-Za-z0-9]+\;)\d+(?:\&amp;\#[A-Za-z0-9]+\;)(?:-\d+)?$' where id=21607 and name='sslvpn.icp';

--changeset mlo:2610
--comment: TRIVIAL: grant select on VPN.PARTNER_ACCESS_RANGE to MCA
GRANT SELECT on VPN.PARTNER_ACCESS_RANGE to MCA;
