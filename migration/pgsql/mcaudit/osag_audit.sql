-- migration/pgsql/mcaudit/osag_audit.sql
--
-- Translation of MCAUDIT.OSAG_AUDIT (spec: migration/spec/mcaudit.osag_audit.md; Oracle body:
-- ddl/src/pkgb/mcaudit_osag_audit.sql, 150 lines). Names copied verbatim from
-- migration/mapping/name-map.csv's 4 OSAG_AUDIT rows (all pg_kind=procedure). No private
-- routines, no package state, no exception handler anywhere in the Oracle body -- every
-- error propagates to the caller, here too.
--
-- Oracle's usage-audit call (XCUT-06): all 4 plog.AuditUsage sites (lines 23, 56, 99, 134 --
-- one per routine) DELETED, not ported. See osag_audit.FINDINGS.md.
--
-- Parameter types are the resolved PostgreSQL column types of the Oracle %TYPE anchors
-- (mcaudit.record.*: bigint ids, message varchar(2000) -> varchar, details CLOB -> text,
-- zitadel_user_* varchar(128)/bigint; mcaudit.<lookup>.short varchar(64) -> varchar), written
-- out explicitly rather than as %TYPE so that this file still loads on a template that
-- predates schema-fixes/26_p0601_fixes.sql (the three zitadel_user_* columns ora2pg
-- dropped) -- the INSERT then fails at run time instead of the CREATE failing at install.
--
-- IN OUT -> INOUT. io_record_id (Oracle: IN OUT without a default, positioned after five
-- DEFAULT NULL parameters) gets DEFAULT NULL: PostgreSQL requires every input parameter
-- after a defaulted one to have a default, and NULL already means "allocate" (S-AUDIT-012).
--
-- '' vs NULL (Pitfall 2 / spec Checklist 1, S-AUDIT-013): the five string inputs the single
-- writer stores or looks up are normalised with NULLIF(x, '') so PostgreSQL stores (and, for
-- message, rejects) exactly what Oracle did. SYSTIMESTAMP -> statement_timestamp(),
-- seq.nextval -> nextval('mcaudit.<seq>'), unqualified record/application/component/
-- record_type/severity -> mcaudit.* (the package owner's schema).
--
-- "no data found" message-parity shim (migration/mapping/sqlstate-map.md rule 2): the eight
-- unguarded SELECT INTO lookups in add_record/add_record2 are externally reachable,
-- unhandled NO_DATA_FOUND sites (Oracle callers see ORA-01403); each routine's four lookups
-- share one handler that re-raises P0002 with Oracle's text (S-AUDIT-010).

-- ------------------------------------------------------------------------------------
-- add_record_raw2 (S-AUDIT-002..007, 012, 013): THE single writer.
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE mcaudit.osag_audit_add_record_raw2(
    i_application_id          bigint,
    i_component_id            bigint,
    i_record_type_id          bigint,
    i_severity_id             bigint,
    INOUT io_transaction_id   bigint,
    i_message                 varchar,
    i_details                 text,
    i_company_id              bigint  DEFAULT NULL,
    i_contact_id              bigint  DEFAULT NULL,
    i_table_name              varchar DEFAULT NULL,
    i_object_id               bigint  DEFAULT NULL,
    i_ticket_id               bigint  DEFAULT NULL,
    INOUT io_record_id        bigint  DEFAULT NULL,
    i_zitadel_user_id         varchar DEFAULT NULL,
    i_zitadel_user_name       varchar DEFAULT NULL,
    i_zitadel_user_company_id bigint  DEFAULT NULL)
LANGUAGE plpgsql
AS $fn$
BEGIN
    -- S-AUDIT-002
    IF (io_transaction_id IS NULL) THEN
        io_transaction_id := nextval('mcaudit.transaction_seq');
    END IF;

    -- S-AUDIT-003
    IF io_record_id IS NULL THEN
        io_record_id := nextval('mcaudit.record_seq');
    END IF;

    -- S-AUDIT-004 / 005 / 006 / 007 / 013. No handler: constraint and subquery errors
    -- propagate exactly as Oracle's did.
    INSERT INTO mcaudit.record
        (id, "timestamp", application_id, component_id, record_type_id, severity_id, message,
         details, transaction_id, company_id, contact_id, object_id, object_type_id, ticket_id,
         zitadel_user_id, zitadel_user_name, zitadel_user_company_id)
    VALUES (io_record_id, statement_timestamp(), i_application_id, i_component_id,
            i_record_type_id, i_severity_id, NULLIF(i_message, ''), NULLIF(i_details, ''),
            io_transaction_id, i_company_id, i_contact_id,
            i_object_id,
            (SELECT id FROM mss.object_type WHERE table_name = NULLIF(i_table_name, '')),
            i_ticket_id,
            NULLIF(i_zitadel_user_id, ''), NULLIF(i_zitadel_user_name, ''), i_zitadel_user_company_id);
END;
$fn$;

-- ------------------------------------------------------------------------------------
-- add_record_raw (S-AUDIT-008, 012): raw2 with the record id allocated and discarded.
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE mcaudit.osag_audit_add_record_raw(
    i_application_id        bigint,
    i_component_id          bigint,
    i_record_type_id        bigint,
    i_severity_id           bigint,
    INOUT io_transaction_id bigint,
    i_message               varchar,
    i_details               text,
    i_company_id            bigint  DEFAULT NULL,
    i_contact_id            bigint  DEFAULT NULL,
    i_table_name            varchar DEFAULT NULL,
    i_object_id             bigint  DEFAULT NULL,
    i_ticket_id             bigint  DEFAULT NULL)
LANGUAGE plpgsql
AS $fn$
DECLARE
    v_record_id bigint;   -- mcaudit.record.id%TYPE; stays NULL -> raw2 allocates and we discard it
BEGIN
    CALL mcaudit.osag_audit_add_record_raw2(
        i_application_id,
        i_component_id,
        i_record_type_id,
        i_severity_id,
        io_transaction_id,
        i_message,
        i_details,
        i_company_id,
        i_contact_id,
        i_table_name,
        i_object_id,
        i_ticket_id,
        v_record_id);
END;
$fn$;

-- ------------------------------------------------------------------------------------
-- add_record2 (S-AUDIT-009, 010, 012): shorts -> ids, then raw2 with io_record_id and the
-- Zitadel parameters passed through.
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE mcaudit.osag_audit_add_record2(
    i_application_short       varchar,
    i_component_short         varchar,   -- Oracle anchors this to application.short%TYPE (same varchar(64))
    i_record_type_short       varchar,
    i_severity_short          varchar,
    INOUT io_transaction_id   bigint,
    i_message                 varchar,
    i_details                 text,
    i_company_id              bigint  DEFAULT NULL,
    i_contact_id              bigint  DEFAULT NULL,
    i_table_name              varchar DEFAULT NULL,
    i_object_id               bigint  DEFAULT NULL,
    i_ticket_id               bigint  DEFAULT NULL,
    INOUT io_record_id        bigint  DEFAULT NULL,
    i_zitadel_user_id         varchar DEFAULT NULL,
    i_zitadel_user_name       varchar DEFAULT NULL,
    i_zitadel_user_company_id bigint  DEFAULT NULL)
LANGUAGE plpgsql
AS $fn$
DECLARE
    v_application_id bigint;
    v_component_id   bigint;
    v_record_type_id bigint;
    v_severity_id    bigint;
BEGIN
    BEGIN
        -- S-AUDIT-009 (strictness sites #1-#4): STRICT, unhandled in Oracle.
        SELECT id INTO STRICT v_application_id FROM mcaudit.application WHERE short = i_application_short;
        SELECT id INTO STRICT v_component_id   FROM mcaudit.component   WHERE short = i_component_short;
        SELECT id INTO STRICT v_record_type_id FROM mcaudit.record_type WHERE short = i_record_type_short;
        SELECT id INTO STRICT v_severity_id    FROM mcaudit.severity    WHERE short = i_severity_short;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            -- S-AUDIT-010: message-parity shim -- same SQLSTATE, Oracle's wording.
            RAISE EXCEPTION 'no data found' USING ERRCODE = 'P0002';
    END;

    CALL mcaudit.osag_audit_add_record_raw2(i_application_id => v_application_id, i_component_id => v_component_id,
                                             i_record_type_id => v_record_type_id, i_severity_id => v_severity_id,
                                             io_transaction_id => io_transaction_id, i_message => i_message,
                                             i_details => i_details, i_company_id => i_company_id, i_contact_id => i_contact_id,
                                             i_table_name => i_table_name, i_object_id => i_object_id,
                                             i_ticket_id => i_ticket_id, io_record_id => io_record_id, i_zitadel_user_id => i_zitadel_user_id,
                                             i_zitadel_user_name => i_zitadel_user_name, i_zitadel_user_company_id => i_zitadel_user_company_id);
END;
$fn$;

-- ------------------------------------------------------------------------------------
-- add_record (S-AUDIT-010, 011, 012): shorts -> ids, then raw2 with the record id
-- allocated and discarded, no Zitadel columns.
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE mcaudit.osag_audit_add_record(
    i_application_short     varchar,
    i_component_short       varchar,
    i_record_type_short     varchar,
    i_severity_short        varchar,
    INOUT io_transaction_id bigint,
    i_message               varchar,
    i_details               text,
    i_company_id            bigint  DEFAULT NULL,
    i_contact_id            bigint  DEFAULT NULL,
    i_table_name            varchar DEFAULT NULL,
    i_object_id             bigint  DEFAULT NULL,
    i_ticket_id             bigint  DEFAULT NULL)
LANGUAGE plpgsql
AS $fn$
DECLARE
    v_application_id bigint;
    v_component_id   bigint;
    v_record_type_id bigint;
    v_severity_id    bigint;
    v_record_id      bigint;   -- stays NULL -> allocated by raw2, discarded here
BEGIN
    BEGIN
        -- S-AUDIT-011 (strictness sites #5-#8): STRICT, unhandled in Oracle.
        SELECT id INTO STRICT v_application_id FROM mcaudit.application WHERE short = i_application_short;
        SELECT id INTO STRICT v_component_id   FROM mcaudit.component   WHERE short = i_component_short;
        SELECT id INTO STRICT v_record_type_id FROM mcaudit.record_type WHERE short = i_record_type_short;
        SELECT id INTO STRICT v_severity_id    FROM mcaudit.severity    WHERE short = i_severity_short;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            -- S-AUDIT-010: message-parity shim
            RAISE EXCEPTION 'no data found' USING ERRCODE = 'P0002';
    END;

    CALL mcaudit.osag_audit_add_record_raw2(i_application_id => v_application_id, i_component_id => v_component_id,
                                             i_record_type_id => v_record_type_id, i_severity_id => v_severity_id,
                                             io_transaction_id => io_transaction_id, i_message => i_message,
                                             i_details => i_details, i_company_id => i_company_id, i_contact_id => i_contact_id,
                                             i_table_name => i_table_name, i_object_id => i_object_id,
                                             i_ticket_id => i_ticket_id, io_record_id => v_record_id);
END;
$fn$;
