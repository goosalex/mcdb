-- migration/test/bootstrap/10_schemas_roles.sql
--
-- Roles and schemas for the mcdb_tmpl template, built from ddl/migrated/users/
-- (the real ora2pg export -- untouched, per D-P7). This file does not edit those
-- files; it \ir-includes every one of them (all 116), plus two additive fixes for
-- gaps ora2pg's users/ export left behind. Both fixes are recorded in
-- ../../SCHEMA-FIXES.md (fix #1 and fix #2).
--
-- \ir is a relative include: paths below are resolved relative to this file's
-- own directory (migration/test/bootstrap/), not to psql's invocation cwd.

-- --------------------------------------------------------------------------
-- Fix #1 (SCHEMA-FIXES.md): every ddl/migrated/users/*.sql file does
-- `GRANT <role> TO postgresadmin`, assuming a `postgresadmin` role already
-- exists in the cluster (it is presumably created by container/cluster setup
-- in the real Oracle->PG target, outside ora2pg's export). It does not exist on
-- a bare local PostgreSQL instance. Without it, EVERY one of the 116 files below
-- fails atomically (the whole DO block rolls back, including the CREATE ROLE and
-- CREATE SCHEMA that precede the failing GRANT), so this must run first.
-- --------------------------------------------------------------------------
DO
$do$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'postgresadmin') THEN
        CREATE ROLE postgresadmin;
    END IF;
END
$do$;

\ir ../../../ddl/migrated/users/APPID.sql
\ir ../../../ddl/migrated/users/APP_MANAGER.sql
\ir ../../../ddl/migrated/users/ARMGEN.sql
\ir ../../../ddl/migrated/users/ASERTO_TEST.sql
\ir ../../../ddl/migrated/users/AUTH.sql
\ir ../../../ddl/migrated/users/AUTHSYNC.sql
\ir ../../../ddl/migrated/users/AVAILABILITY_REPORT.sql
\ir ../../../ddl/migrated/users/AZURE_VWAN.sql
\ir ../../../ddl/migrated/users/BGP.sql
\ir ../../../ddl/migrated/users/BIREADER.sql
\ir ../../../ddl/migrated/users/BOD.sql
\ir ../../../ddl/migrated/users/CERTS.sql
\ir ../../../ddl/migrated/users/CERTS_MGR.sql
\ir ../../../ddl/migrated/users/CGE.sql
\ir ../../../ddl/migrated/users/CHE.sql
\ir ../../../ddl/migrated/users/CHENERATOR.sql
\ir ../../../ddl/migrated/users/CONTRACT.sql
\ir ../../../ddl/migrated/users/DBDNS.sql
\ir ../../../ddl/migrated/users/DBMONITOR.sql
\ir ../../../ddl/migrated/users/DBREADER.sql
\ir ../../../ddl/migrated/users/DECOMM.sql
\ir ../../../ddl/migrated/users/DKA.sql
\ir ../../../ddl/migrated/users/DNSSEC.sql
\ir ../../../ddl/migrated/users/DYNIP.sql
\ir ../../../ddl/migrated/users/ESP.sql
\ir ../../../ddl/migrated/users/FW.sql
\ir ../../../ddl/migrated/users/FYI.sql
\ir ../../../ddl/migrated/users/FYI_REPORTER.sql
\ir ../../../ddl/migrated/users/GETNODES.sql
\ir ../../../ddl/migrated/users/GUMA2.sql
\ir ../../../ddl/migrated/users/GUMA_SERVER.sql
\ir ../../../ddl/migrated/users/ISP_AVAILABILITY_REPORTER.sql
\ir ../../../ddl/migrated/users/LINKMON.sql
\ir ../../../ddl/migrated/users/LOGFWD.sql
\ir ../../../ddl/migrated/users/LQB.sql
\ir ../../../ddl/migrated/users/MAIL.sql
\ir ../../../ddl/migrated/users/MAIL_DKIM.sql
\ir ../../../ddl/migrated/users/MAIL_DMARC.sql
\ir ../../../ddl/migrated/users/MC.sql
\ir ../../../ddl/migrated/users/MCA.sql
\ir ../../../ddl/migrated/users/MCAUDIT.sql
\ir ../../../ddl/migrated/users/MCDB_CHECKS.sql
\ir ../../../ddl/migrated/users/MCDB_MONITOR.sql
\ir ../../../ddl/migrated/users/MCMGW.sql
\ir ../../../ddl/migrated/users/MDR_SYNC.sql
\ir ../../../ddl/migrated/users/MSG.sql
\ir ../../../ddl/migrated/users/MSS.sql
\ir ../../../ddl/migrated/users/NFGEN.sql
\ir ../../../ddl/migrated/users/NIDS.sql
\ir ../../../ddl/migrated/users/NIDS_INVESTIGATION.sql
\ir ../../../ddl/migrated/users/OSAG.sql
\ir ../../../ddl/migrated/users/OSIXINFO.sql
\ir ../../../ddl/migrated/users/PDFREP.sql
\ir ../../../ddl/migrated/users/PERLTICKET.sql
\ir ../../../ddl/migrated/users/PRX.sql
\ir ../../../ddl/migrated/users/PRX_MISCAT.sql
\ir ../../../ddl/migrated/users/PRX_SELFSERVE.sql
\ir ../../../ddl/migrated/users/REMATO.sql
\ir ../../../ddl/migrated/users/REPORT.sql
\ir ../../../ddl/migrated/users/RLSDEF.sql
\ir ../../../ddl/migrated/users/SANG.sql
\ir ../../../ddl/migrated/users/SRVREP.sql
\ir ../../../ddl/migrated/users/STOCKREPORT.sql
\ir ../../../ddl/migrated/users/STOKENSYNC.sql
\ir ../../../ddl/migrated/users/STOP.sql
\ir ../../../ddl/migrated/users/SVC_ALERTHANDLER.sql
\ir ../../../ddl/migrated/users/SVC_API_TICKETING.sql
\ir ../../../ddl/migrated/users/SVC_AUTOMATION_DBWATCHER.sql
\ir ../../../ddl/migrated/users/SVC_AUTOMATION_EXECUTOR.sql
\ir ../../../ddl/migrated/users/SVC_BALUCONSUMER_AUTHUPDATE.sql
\ir ../../../ddl/migrated/users/SVC_BALUCONSUMER_OPENVPN.sql
\ir ../../../ddl/migrated/users/SVC_BALUOSIXINFO.sql
\ir ../../../ddl/migrated/users/SVC_BLACKBOX.sql
\ir ../../../ddl/migrated/users/SVC_BUILDALL.sql
\ir ../../../ddl/migrated/users/SVC_BUILDCLOUD_PARAMGEN.sql
\ir ../../../ddl/migrated/users/SVC_BUILDJUN.sql
\ir ../../../ddl/migrated/users/SVC_BUILDSSE.sql
\ir ../../../ddl/migrated/users/SVC_CERTTOOL_CLEANUP.sql
\ir ../../../ddl/migrated/users/SVC_CHECKHOSTS.sql
\ir ../../../ddl/migrated/users/SVC_CONIFER.sql
\ir ../../../ddl/migrated/users/SVC_CONNECTIVITY_COORDINATOR.sql
\ir ../../../ddl/migrated/users/SVC_COPILOT.sql
\ir ../../../ddl/migrated/users/SVC_DBPROP.sql
\ir ../../../ddl/migrated/users/SVC_EUQ.sql
\ir ../../../ddl/migrated/users/SVC_FAST_INTERFACE_RENAME.sql
\ir ../../../ddl/migrated/users/SVC_FEATURE_FLAG.sql
\ir ../../../ddl/migrated/users/SVC_FIREWALL_API.sql
\ir ../../../ddl/migrated/users/SVC_GUMA_MIGRATION.sql
\ir ../../../ddl/migrated/users/SVC_MCAUDIT_API.sql
\ir ../../../ddl/migrated/users/SVC_MC_PORTAL.sql
\ir ../../../ddl/migrated/users/SVC_NETFABRIC.sql
\ir ../../../ddl/migrated/users/SVC_SRE_METRICS_CFG.sql
\ir ../../../ddl/migrated/users/SVC_SSHSYNC.sql
\ir ../../../ddl/migrated/users/SVC_SYNCIFY.sql
\ir ../../../ddl/migrated/users/SVC_TERRAFORM_EXECUTOR.sql
\ir ../../../ddl/migrated/users/SVC_TICKET_EMBEDDINGS.sql
\ir ../../../ddl/migrated/users/SVC_USERS_INTERNAL_API.sql
\ir ../../../ddl/migrated/users/SVC_XDRCONVERT.sql
\ir ../../../ddl/migrated/users/SVC_ZEROTRUST.sql
\ir ../../../ddl/migrated/users/SYNC_MAILDIR.sql
\ir ../../../ddl/migrated/users/TICKETEVOLUTION.sql
\ir ../../../ddl/migrated/users/TICKETINDEXER.sql
\ir ../../../ddl/migrated/users/TIM.sql
\ir ../../../ddl/migrated/users/TT.sql
\ir ../../../ddl/migrated/users/UAI.sql
\ir ../../../ddl/migrated/users/UPOL.sql
\ir ../../../ddl/migrated/users/VAULTSVN.sql
\ir ../../../ddl/migrated/users/VPN.sql
\ir ../../../ddl/migrated/users/VPNSTATS.sql
\ir ../../../ddl/migrated/users/VPN_GUI.sql
\ir ../../../ddl/migrated/users/WANBB.sql
\ir ../../../ddl/migrated/users/WEBCACHE.sql
\ir ../../../ddl/migrated/users/WEBLOGIN.sql
\ir ../../../ddl/migrated/users/WEBRLS.sql
\ir ../../../ddl/migrated/users/WEBSW.sql
\ir ../../../ddl/migrated/users/ZEROTRUST_MGR.sql

-- --------------------------------------------------------------------------
-- Fix #2 (SCHEMA-FIXES.md): the 'checklist' schema owns tables in
-- ddl/migrated/tables/tables.pg.sql (CHECKLIST.* -- e.g. checklist."#jdo_properties")
-- but ddl/migrated/users/ ships no CHECKLIST.sql role/schema file for it -- a genuine
-- ora2pg export gap (every OTHER schema referenced in tables.pg.sql has a matching
-- users/ file; this is the only exception). Without this, 43 CREATE TABLE/ALTER
-- TABLE statements in tables.pg.sql fail with 'schema "checklist" does not exist'.
-- Reconstructed here using the exact same DO-block pattern ora2pg emits for every
-- other schema, so it composes identically with the rest of this file.
-- --------------------------------------------------------------------------
DO
$do$
    DECLARE
        v_user VARCHAR = 'checklist';
        v_admin VARCHAR = 'postgresadmin';
    BEGIN
        IF
            EXISTS (SELECT
                    FROM pg_catalog.pg_roles
                    WHERE rolname = v_user) THEN
            RAISE
                NOTICE 'Role v_user already exists. Skipping.';
        ELSE	EXECUTE format('CREATE ROLE %I', v_user);
END IF;
EXECUTE format('GRANT %I TO %I', v_user, v_admin);
EXECUTE format('CREATE SCHEMA AUTHORIZATION %I', v_user);
EXECUTE format('ALTER ROLE %I SET search_path TO %I, public', v_user, v_user);
END 
$do$;
