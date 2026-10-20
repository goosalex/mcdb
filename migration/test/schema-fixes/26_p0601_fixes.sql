-- migration/test/schema-fixes/26_p0601_fixes.sql
--
-- Plan 06-01 (MC.OSAG_MAINTSYNC + MCAUDIT.OSAG_AUDIT). Additive, idempotent, applied
-- AFTER the base ddl/migrated load (D-P7: ddl/migrated/ itself is never edited).
-- Ledger entry: migration/test/SCHEMA-FIXES.md, fix #10.
--
-- ONE ora2pg gap: mcaudit.record is missing the three ZITADEL_USER_* columns.
--
--   Oracle export (ddl/generated/schema.oracle.sql:110):
--     ... ZITADEL_USER_ID VARCHAR2(128 BYTE), ZITADEL_USER_NAME VARCHAR2(128 BYTE),
--     ZITADEL_USER_COMPANY_ID NUMBER(22, 0) ...
--   plus COMMENT ON COLUMN x3 (schema.oracle.sql:119-121), the FK
--   FK_RECORD_ZITADEL_USER_COMPANY_ID -> STOP.COMPANY(ID) (constraints.oracle.sql:386)
--   and the index IDX_RECORD_ZITADEL_USER_COMPANY_ID (schema.oracle.sql:3618).
--   ora2pg output (ddl/migrated/tables/tables.pg.sql:627-642): none of them.
--
-- MCAUDIT.OSAG_AUDIT.add_record_raw2 writes all three columns
-- (ddl/src/pkgb/mcaudit_osag_audit.sql:32-38), so without them the translation cannot
-- insert a single audit record. Same shape as plan 02-12's fix for tt.change_request's
-- two missing zitadel columns (24_p12_fixes.sql) -- ora2pg appears to drop the columns a
-- late Liquibase changeset added (changes/changelog-2.archive.sql:4086-4095 added
-- ZITADEL_USER_COMPANY_ID) when it exported this table.
--
-- Column types follow what ora2pg did for this table's OTHER company-id FK column
-- (company_id NUMBER(10,0) -> bigint, FK to stop.company(id) numeric(22,0), which
-- PostgreSQL accepts): bigint, not numeric(22,0), so the new column matches its sibling.

ALTER TABLE mcaudit.record ADD COLUMN IF NOT EXISTS zitadel_user_id varchar(128);
ALTER TABLE mcaudit.record ADD COLUMN IF NOT EXISTS zitadel_user_name varchar(128);
ALTER TABLE mcaudit.record ADD COLUMN IF NOT EXISTS zitadel_user_company_id bigint;

COMMENT ON COLUMN mcaudit.record.zitadel_user_id IS
    'Zitadel ID (Sub) of the User who made this change (human or service user)';
COMMENT ON COLUMN mcaudit.record.zitadel_user_name IS
    'Name at the time of the change of the Zitadel user who made this change (kept it for audit purposes in case of changes in Zitadel)';
COMMENT ON COLUMN mcaudit.record.zitadel_user_company_id IS
    'Company ID of the Zitadel User who made the change, stored here to see without additional fetching if change was made by Open Systems (MC) or the customer.';

DO $do$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conname = 'fk_record_zitadel_user_company_id'
                     AND conrelid = 'mcaudit.record'::regclass) THEN
        ALTER TABLE mcaudit.record
            ADD CONSTRAINT fk_record_zitadel_user_company_id
            FOREIGN KEY (zitadel_user_company_id) REFERENCES stop.company (id) DEFERRABLE;
    END IF;
END
$do$;

CREATE INDEX IF NOT EXISTS idx_record_zitadel_user_company_id
    ON mcaudit.record (zitadel_user_company_id);
