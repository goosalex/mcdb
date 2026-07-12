-- migration/test/schema-fixes/10_ora2pg_fixes.sql
--
-- Additive fixes applied AFTER the base load (bootstrap/20_ddl.sh) completes (D-P7:
-- ddl/migrated/ itself is never edited). Every fix here is written up in
-- ../SCHEMA-FIXES.md with the error it resolves, its root cause, and the action Phase 5
-- should take (apply this same file verbatim, or fix the ora2pg configuration and
-- regenerate). This file is loaded with -v ON_ERROR_STOP=on and MUST complete with zero
-- errors -- unlike the base load, nothing here is an "expected" failure.
--
-- Covers SCHEMA-FIXES.md fixes #3 (15 FK type mismatches) and #4 (3 lost CHECK
-- constraints). Fixes #1 (postgresadmin role) and #2 (checklist schema) live in
-- ../bootstrap/10_schemas_roles.sql instead, because they must exist BEFORE
-- tables.pg.sql loads, not after.

-- ============================================================================
-- Fix #3: 15 FK constraints in constraints/fk-constraints.pg.sql fail with
-- "cannot be implemented ... incompatible types: numeric and bigint".
--
-- Root cause: ora2pg maps unscaled Oracle NUMBER columns to `bigint` when it infers
-- the column is a sequence-backed surrogate primary key, but to plain unbounded
-- `numeric` for a FOREIGN KEY column pointing at that same kind of id -- even when
-- both columns originate from the identical Oracle NUMBER declaration. Every failure
-- below is this exact pattern: a `<x>_id numeric` column referencing a `id bigint`
-- primary key. Fixed by widening the FK column to bigint (matching its target), not by
-- narrowing the PK -- bigint is the correct type for a surrogate id column and is what
-- every OTHER working FK in this schema already uses.
-- ============================================================================

-- Three bireader.* views (loaded by tables/views.pg.sql, which runs before this file)
-- SELECT directly from three of the affected tables, and PostgreSQL refuses to ALTER a
-- column's type while a view depends on it (no CASCADE option exists for ALTER COLUMN
-- TYPE). Dropped here and recreated verbatim from tables/views.pg.sql lines 188, 195,
-- 263 immediately after the type fixes below.
DROP VIEW IF EXISTS bireader.v_mss_local_contact_notification;
DROP VIEW IF EXISTS bireader.v_tt_event;
DROP VIEW IF EXISTS bireader.v_tt_ticket;

ALTER TABLE mss.local_contact_notification ALTER COLUMN local_contact_id TYPE bigint USING local_contact_id::bigint;
ALTER TABLE nids.investigation ALTER COLUMN investigation_status_id TYPE bigint USING investigation_status_id::bigint;
ALTER TABLE nids.investigation ALTER COLUMN investigation_finding_id TYPE bigint USING investigation_finding_id::bigint;
ALTER TABLE nids.investigation_entry ALTER COLUMN investigation_id TYPE bigint USING investigation_id::bigint;
ALTER TABLE nids.ks_enforcement ALTER COLUMN investigation_id TYPE bigint USING investigation_id::bigint;
ALTER TABLE tt.event ALTER COLUMN host_id TYPE bigint USING host_id::bigint;
ALTER TABLE tt.event ALTER COLUMN deleted_host_id TYPE bigint USING deleted_host_id::bigint;
ALTER TABLE tt.event_notification ALTER COLUMN login_id TYPE bigint USING login_id::bigint;
ALTER TABLE tt.event_notification ALTER COLUMN service_id TYPE bigint USING service_id::bigint;
ALTER TABLE tt.event_notification ALTER COLUMN company_unit_id TYPE bigint USING company_unit_id::bigint;
ALTER TABLE tt.event_notification ALTER COLUMN service_type_id TYPE bigint USING service_type_id::bigint;
ALTER TABLE tt.rollout_window ALTER COLUMN software_release_id TYPE bigint USING software_release_id::bigint;
ALTER TABLE tt.ticket ALTER COLUMN deleted_host_id TYPE bigint USING deleted_host_id::bigint;
ALTER TABLE tt.ticket ALTER COLUMN host_id TYPE bigint USING host_id::bigint;
ALTER TABLE tt.ticket ALTER COLUMN mss_service_id TYPE bigint USING mss_service_id::bigint;

-- Now the 15 FK constraints that failed during the base load succeed (statement text
-- copied verbatim from constraints/fk-constraints.pg.sql lines 569, 637, 638, 643, 644,
-- 762, 764, 766, 772, 773, 774, 787, 795, 803, 804 -- same DEFERRABLE clause, unchanged).
ALTER TABLE mss.local_contact_notification ADD CONSTRAINT local_contact_notification_fk1 FOREIGN KEY (local_contact_id) REFERENCES mss.local_contact (id) DEFERRABLE;
ALTER TABLE nids.investigation ADD CONSTRAINT investigation_fk1 FOREIGN KEY (investigation_status_id) REFERENCES nids.investigation_status (id) DEFERRABLE;
ALTER TABLE nids.investigation ADD CONSTRAINT investigation_fk2 FOREIGN KEY (investigation_finding_id) REFERENCES nids.investigation_finding (id) DEFERRABLE;
ALTER TABLE nids.investigation_entry ADD CONSTRAINT investigation_entry_fk2 FOREIGN KEY (investigation_id) REFERENCES nids.investigation (id) DEFERRABLE;
ALTER TABLE nids.ks_enforcement ADD CONSTRAINT ks_enforcement_fk1 FOREIGN KEY (investigation_id) REFERENCES nids.investigation (id) DEFERRABLE;
ALTER TABLE tt.event ADD CONSTRAINT event_fk6 FOREIGN KEY (host_id) REFERENCES mss.host (id) DEFERRABLE;
ALTER TABLE tt.event ADD CONSTRAINT event_fk8 FOREIGN KEY (deleted_host_id) REFERENCES mss.deleted_host (id) DEFERRABLE;
ALTER TABLE tt.event_notification ADD CONSTRAINT event_notification_fk1 FOREIGN KEY (login_id) REFERENCES auth.login (id) DEFERRABLE;
ALTER TABLE tt.event_notification ADD CONSTRAINT event_notification_fk6 FOREIGN KEY (service_id) REFERENCES mss.service (id) DEFERRABLE;
ALTER TABLE tt.event_notification ADD CONSTRAINT event_notification_fk7 FOREIGN KEY (company_unit_id) REFERENCES stop.company_unit (id) DEFERRABLE;
ALTER TABLE tt.event_notification ADD CONSTRAINT event_notification_fk8 FOREIGN KEY (service_type_id) REFERENCES mss.service_type (id) DEFERRABLE;
ALTER TABLE tt.rollout_window ADD CONSTRAINT rollout_window_fk2 FOREIGN KEY (software_release_id) REFERENCES mss.software_release (id) DEFERRABLE;
ALTER TABLE tt.ticket ADD CONSTRAINT ticket_fk15 FOREIGN KEY (deleted_host_id) REFERENCES mss.deleted_host (id) DEFERRABLE;
ALTER TABLE tt.ticket ADD CONSTRAINT ticket_fk7 FOREIGN KEY (host_id) REFERENCES mss.host (id) DEFERRABLE;
ALTER TABLE tt.ticket ADD CONSTRAINT ticket_fk8 FOREIGN KEY (mss_service_id) REFERENCES mss.service (id) DEFERRABLE;

-- Recreate the three views dropped above, verbatim from tables/views.pg.sql (lines 188,
-- 195, 263) -- same column lists, same SELECT lists, unmodified.
SET search_path = bireader, public;
CREATE OR REPLACE VIEW bireader.v_tt_event (id, type_id, public_event, ticket_id, company_id, eventdate, contact_id, host_id, sign_off_ok, demoted, details_public, details_private, org_ticket_id) AS Select ID ,TYPE_ID ,PUBLIC_EVENT ,TICKET_ID ,COMPANY_ID ,EVENTDATE, CONTACT_ID, HOST_ID ,SIGN_OFF_OK ,DEMOTED ,DETAILS_PUBLIC,DETAILS_PRIVATE,ORG_TICKET_ID FROM TT.EVENT;
CREATE OR REPLACE VIEW bireader.v_tt_ticket (id, type_id, status_id, subject, host_id, mss_service_id, company_id, open_date, close_date, last_resolved_date, last_status_change_date, contact_id, priority, worker_id, customer_reference, partner_reference, emergency, handled_by_mcc, escalation_status_id, last_escalation_date, customer_ticket_rating_id, engineer_ticket_rating_id, update_timestamp, was_emergency, steps_total, steps_completed, service_component_id, label_id) AS Select ID, TYPE_ID, STATUS_ID, SUBJECT, HOST_ID, MSS_SERVICE_ID, COMPANY_ID, OPEN_DATE, CLOSE_DATE, LAST_RESOLVED_DATE, LAST_STATUS_CHANGE_DATE, CONTACT_ID, PRIORITY, WORKER_ID, CUSTOMER_REFERENCE, PARTNER_REFERENCE, EMERGENCY, HANDLED_BY_MCC, ESCALATION_STATUS_ID, LAST_ESCALATION_DATE, CUSTOMER_TICKET_RATING_ID, ENGINEER_TICKET_RATING_ID,UPDATE_TIMESTAMP, WAS_EMERGENCY, STEPS_TOTAL, STEPS_COMPLETED, SERVICE_COMPONENT_ID, LABEL_ID FROM TT.TICKET;
CREATE OR REPLACE VIEW bireader.v_mss_local_contact_notification (id, local_contact_id, event_notification_type_id) AS Select ID ,LOCAL_CONTACT_ID ,EVENT_NOTIFICATION_TYPE_ID FROM MSS.local_contact_notification;
RESET search_path;

-- ============================================================================
-- Fix #4: 3 CHECK constraints silently lost by ora2pg's line-based conversion.
--
-- Root cause: ddl/generated/check-constraints.oracle.sql shows two CHECK constraints
-- (NIDS.MDR_SIGNATURE_GROUP_MEMBER_C1, PRX.PRX_POLICY_GROUP_ENTRY_C1) whose Oracle
-- source spans multiple physical lines with continuation. ora2pg's PostgreSQL export
-- (constraints/check-constraints.pg.sql lines 15-17) kept the Oracle line breaks but
-- DROPPED the closing/continuation content and terminating semicolon entirely -- the
-- statement text just stops mid-expression and the next ALTER TABLE begins on the
-- next physical line with no separator. psql (correctly, since ON_ERROR_STOP=on
-- doesn't change statement *parsing*, only stop-on-failure behaviour) then treats the
-- unterminated text as one continuous statement running all the way to the next `;`
-- it finds -- which belongs to a THIRD, otherwise-correct constraint
-- (STOP.COMPANY.SHORT_LOWERCASE), swallowing it into the same syntax error. All three
-- are reconstructed here from ddl/generated/check-constraints.oracle.sql lines 28-34,
-- with the trailing ` DEFERRABLE` stripped -- PostgreSQL does not support deferrable
-- CHECK constraints (they are always immediate); ora2pg strips this suffix correctly
-- for every OTHER check constraint in the same output file, confirming this is the
-- right translation, not a new judgment call.
-- ============================================================================

ALTER TABLE nids.mdr_signature_group_member ADD CONSTRAINT mdr_signature_group_member_c1 CHECK (
    (mdr_member_signature_group_id IS NOT NULL AND mdr_signature_id IS NULL)
    OR (mdr_member_signature_group_id IS NULL AND mdr_signature_id IS NOT NULL)
);

ALTER TABLE prx.prx_policy_group_entry ADD CONSTRAINT prx_policy_group_entry_c1 CHECK (
    (ip4_address IS NOT NULL AND netmask IS NOT NULL AND ip6_address1 IS NULL AND ip6_address2 IS NULL AND authenticated_group_name IS NULL)
    OR (ip6_address1 IS NOT NULL AND ip6_address2 IS NOT NULL AND netmask IS NOT NULL AND ip4_address IS NULL AND authenticated_group_name IS NULL)
    OR (authenticated_group_name IS NOT NULL AND ip4_address IS NULL AND ip6_address1 IS NULL AND ip6_address2 IS NULL AND netmask IS NULL)
);

ALTER TABLE stop.company ADD CONSTRAINT short_lowercase CHECK (lower(short) = short);
