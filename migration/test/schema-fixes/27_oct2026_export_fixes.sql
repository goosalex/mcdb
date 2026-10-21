-- migration/test/schema-fixes/27_oct2026_export_fixes.sql
--
-- Re-sync with the 2026-10-20 Oracle export (commit 0e5c990 "update to 20261020").
-- Additive, idempotent, applied AFTER the base ddl/migrated load (D-P7: ddl/ is read-only,
-- ddl/migrated/ is the frozen ora2pg output of an export OLDER than ddl/generated).
-- Ledger entry: migration/test/SCHEMA-FIXES.md, fix #11.
--
-- The TT.TICKET_INTERFACE body changed in that export (newticket_new resolves ServiceNow
-- sign-off senders by Zitadel user ID and writes the worker's Zitadel ID; change_worker
-- writes it too). Both routines write TT.TICKET.WORKER_ZITADEL_ID:
--
--   Oracle export (ddl/generated/schema.oracle.sql, CREATE TABLE TT.TICKET):
--     ... CONTACT_ZITADEL_ID VARCHAR2(128 BYTE), WORKER_ZITADEL_ID VARCHAR2(128 BYTE) ...
--   ora2pg output (ddl/migrated/tables/tables.pg.sql): neither column (contact_zitadel_id
--   was added by 23_p11_fixes.sql; worker_zitadel_id is added here, same type).
--
-- A live comparison of the Oracle container (mcdb-ora, state 2026-10-20) with mcdb_tmpl
-- shows 315 columns / 38 tables present in Oracle and absent here for the TT-closure
-- schemas (mostly *_bak_20250714 tables, materialized views and MC/MSS tables no TT code
-- touches). Only WORKER_ZITADEL_ID is referenced by the TT PL/SQL, so only it is added
-- here; the full re-generation of the ora2pg output from the running Oracle container is
-- Phase 5 work and must land in a new directory, not in ddl/migrated/.

ALTER TABLE tt.ticket ADD COLUMN IF NOT EXISTS worker_zitadel_id varchar(128);

COMMENT ON COLUMN tt.ticket.worker_zitadel_id IS
    'Zitadel user ID (oidc_zitadel_id of auth.login) of the worker; set by newticket_new and change_worker from auth.login by contact_id (2026-10-20 export)';
