-- migration/test/schema-fixes/24_p12_fixes.sql
--
-- Plan 02-12 (translation of TT.TICKET_INTERFACE) found TWO real gaps while writing and
-- testing the translation, both surfaced by tracing newticket_new's/deleteTicket's own
-- INSERT/DELETE statements against ddl/migrated/, not by any test failure (PL/pgSQL
-- defers validation of a statement's referenced columns/relations to first execution,
-- so neither would have surfaced merely by loading this file with `psql -f`).

-- =====================================================================================
-- Fix 1: tt.change_request.requester_zitadel_id / approver_zitadel_id -- missing columns
-- =====================================================================================
--
-- ERROR THAT WOULD BE OBSERVED (at first execution of newticket_new's
-- change-request-creation branch, v_create_cr = 1 -- an email from one of 9 well-known
-- ServiceNow-integration contact ids): `column "requester_zitadel_id" of relation
-- "change_request" does not exist`.
--
-- ROOT CAUSE: unlike tt.event.contact_zitadel_id / tt.ticket.contact_zitadel_id (fixed
-- by migration/test/schema-fixes/23_p11_fixes.sql, traceable to a real, if
-- not-yet-applied-to-the-export-snapshot, Liquibase changeset --
-- changes/changelog-current.sql:2194-2199), these two columns
-- (ddl/src/pkgb/tt_ticket_interface.sql:257, the INSERT column list) appear NOWHERE ELSE
-- in the entire repository -- not in ddl/export/schema.oracle.sql, not in
-- changes/changelog-current.sql, not in ddl/migrated/. There is no changelog entry to
-- point to. This looks like Oracle-side code that was written ahead of a schema change
-- that was planned but never actually shipped as a changeset -- genuinely different from
-- the contact_zitadel_id situation, not the same root cause reapplied.
--
-- FIX: add both columns as varchar(128), matching contact_zitadel_id's own established
-- type (the same "Zitadel ID" convention used everywhere else in this cycle group), as
-- an additive `ALTER TABLE ... ADD COLUMN IF NOT EXISTS` (idempotent, matches
-- 23_p11_fixes.sql's own additive philosophy -- D-P7, ddl/migrated/ itself is never
-- edited).

ALTER TABLE tt.change_request ADD COLUMN IF NOT EXISTS requester_zitadel_id varchar(128);
ALTER TABLE tt.change_request ADD COLUMN IF NOT EXISTS approver_zitadel_id varchar(128);

-- PHASE 5 ACTION: confirm with the application/product owner whether this column pair
-- was ever actually meant to ship (a genuine planned-but-never-applied schema change) or
-- is itself Oracle-side dead code nobody noticed (the v_create_cr=1 branch is a narrow
-- ServiceNow-integration heuristic gated on 9 hardcoded contact ids -- easy for a column
-- gap here to go unnoticed in production for a long time). If confirmed live, add a real
-- Liquibase changeset for both columns rather than carrying this fix file forward
-- indefinitely; if confirmed dead, the FIX above is still correct to keep (translation
-- must not silently drop a write Oracle's own source performs), but Phase 5 should flag
-- the branch itself for product review.

-- =====================================================================================
-- Fix 2: fw.change -- table missing entirely from ddl/migrated/
-- =====================================================================================
--
-- ERROR THAT WOULD BE OBSERVED (at first execution of deleteTicket): `relation
-- "fw.change" does not exist`.
--
-- ROOT CAUSE: fw.change genuinely exists in the Oracle export
-- (ddl/generated/schema.oracle.sql:1579, `CREATE TABLE FW.CHANGE (...)`) but is absent
-- from ddl/migrated/tables/tables.pg.sql in its ENTIRETY -- not a missing column like Fix
-- 1 above, the whole table. Confirmed: zero references to fw.change anywhere in
-- ddl/migrated/ (tables, constraints, or otherwise). This is a genuine ora2pg conversion
-- gap (the table was silently dropped somewhere in the ora2pg pipeline), distinct in
-- kind from Fix 1's changelog-timing gap.
--
-- FIX: recreate the table verbatim from the Oracle export's own column list and types
-- (mechanical NUMBER->numeric, VARCHAR2(n)->varchar(n), TIMESTAMP(6) WITH TIME
-- ZONE->timestamp -- matching this cycle group's established convention of naive
-- `timestamp` columns throughout tt.ticket/tt.event, since deleteTicket's own DELETE
-- statement never reads authored/summary_blob_name/etc., only ticket_id).

CREATE TABLE IF NOT EXISTS fw.change (
    id numeric(22) NOT NULL,
    company_id numeric(22) NOT NULL,
    customer_reference varchar(64),
    description varchar(1024),
    ticket_id numeric(22),
    summary_blob_name varchar(256) NOT NULL,
    author_user varchar(128),
    authored timestamp DEFAULT statement_timestamp() NOT NULL,
    PRIMARY KEY (id)
);
CREATE INDEX IF NOT EXISTS idx_change_companycustref ON fw.change (company_id, customer_reference);

-- PHASE 5 ACTION: file a fix upstream against the ora2pg export configuration/run so
-- fw.change (and any other silently-dropped table -- this plan did not exhaustively diff
-- every Oracle export table against ddl/migrated/, only the ones this package's
-- deleteTicket cascade actually references) is emitted, then regenerate ddl/migrated/ and
-- drop this CREATE TABLE from the fix file. Until then, carry this fix file forward
-- verbatim -- it is small, explicit, additive, and self-contained.
