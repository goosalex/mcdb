--liquibase formatted sql logicalFilePath:pkg/mcaudit_osag_audit.sql 
--changeset sys:1 runOnChange:true endDelimiter:/ splitStatements:true
CREATE OR REPLACE PACKAGE MCAUDIT.OSAG_AUDIT AS
    -- -----------------------------------------------------------------------------
    --
    -- create_package_OSAG_AUDIT.sql: Audit Procedures
    --
    -- Written by Stefan Moser (sm@open.ch), December 2006
    -- Copyright (c) 2006 Open Systems AG, Switzerland
    -- All Rights Reserved.
    --
    -- Collection of functions to be used with the Mission Control Audit schema
    -- ----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- PROCEDURE add_record_raw: add an audit record, secondary parameters are IDs
--
-- Note: I initially wanted this to be overloaded with add_record (i.e. share
--       share the same name), but when calling from DBI, the overload
--       resolution fails. Could be fixed maybe, but I'm not that hung up on it.
    PROCEDURE add_record_raw(i_application_id mcaudit.record.application_id%TYPE,
                             i_component_id mcaudit.record.component_id%TYPE,
                             i_record_type_id mcaudit.record.record_type_id%TYPE,
                             i_severity_id mcaudit.record.severity_id%TYPE,
                             io_transaction_id IN OUT mcaudit.record.transaction_id%TYPE,
                             i_message mcaudit.record.message%TYPE,
                             i_details mcaudit.record.details%TYPE,
                             i_company_id mcaudit.record.company_id%TYPE DEFAULT NULL,
                             i_contact_id mcaudit.record.contact_id%TYPE DEFAULT NULL,
                             i_table_name VARCHAR2 DEFAULT NULL,
                             i_object_id mcaudit.record.object_id%TYPE DEFAULT NULL,
                             i_ticket_id mcaudit.record.ticket_id%TYPE DEFAULT NULL);

    PROCEDURE add_record_raw2(i_application_id mcaudit.record.application_id%TYPE,
                             i_component_id mcaudit.record.component_id%TYPE,
                             i_record_type_id mcaudit.record.record_type_id%TYPE,
                             i_severity_id mcaudit.record.severity_id%TYPE,
                             io_transaction_id IN OUT mcaudit.record.transaction_id%TYPE,
                             i_message mcaudit.record.message%TYPE,
                             i_details mcaudit.record.details%TYPE,
                             i_company_id mcaudit.record.company_id%TYPE DEFAULT NULL,
                             i_contact_id mcaudit.record.contact_id%TYPE DEFAULT NULL,
                             i_table_name VARCHAR2 DEFAULT NULL,
                             i_object_id mcaudit.record.object_id%TYPE DEFAULT NULL,
                             i_ticket_id mcaudit.record.ticket_id%TYPE DEFAULT NULL,
                             io_record_id IN OUT mcaudit.record.id%TYPE,
                             i_zitadel_user_id mcaudit.record.zitadel_user_id%TYPE DEFAULT NULL,
                             i_zitadel_user_name mcaudit.record.zitadel_user_name%TYPE DEFAULT NULL,
                             i_zitadel_user_company_id mcaudit.record.zitadel_user_company_id%TYPE DEFAULT NULL);
-- -----------------------------------------------------------------------------
-- PROCEDURE add_record:: add an audit record, secondary parameters are strings
    PROCEDURE add_record(i_application_short mcaudit.application.short%TYPE,
                         i_component_short mcaudit.application.short%TYPE,
                         i_record_type_short mcaudit.record_type.short%TYPE,
                         i_severity_short mcaudit.severity.short%TYPE,
                         io_transaction_id IN OUT mcaudit.record.transaction_id%TYPE,
                         i_message mcaudit.record.message%TYPE,
                         i_details mcaudit.record.details%TYPE,
                         i_company_id mcaudit.record.company_id%TYPE DEFAULT NULL,
                         i_contact_id mcaudit.record.contact_id%TYPE DEFAULT NULL,
                         i_table_name VARCHAR2 DEFAULT NULL,
                         i_object_id mcaudit.record.object_id%TYPE DEFAULT NULL,
                         i_ticket_id mcaudit.record.ticket_id%TYPE DEFAULT NULL);
-- -----------------------------------------------------------------------------
-- PROCEDURE add_record2: returns the ID of the created record in the parameter io_record_id
    PROCEDURE add_record2(i_application_short mcaudit.application.short%TYPE,
                         i_component_short mcaudit.application.short%TYPE,
                         i_record_type_short mcaudit.record_type.short%TYPE,
                         i_severity_short mcaudit.severity.short%TYPE,
                         io_transaction_id IN OUT mcaudit.record.transaction_id%TYPE,
                         i_message mcaudit.record.message%TYPE,
                         i_details mcaudit.record.details%TYPE,
                         i_company_id mcaudit.record.company_id%TYPE DEFAULT NULL,
                         i_contact_id mcaudit.record.contact_id%TYPE DEFAULT NULL,
                         i_table_name VARCHAR2 DEFAULT NULL,
                         i_object_id mcaudit.record.object_id%TYPE DEFAULT NULL,
                         i_ticket_id mcaudit.record.ticket_id%TYPE DEFAULT NULL,
                         io_record_id IN OUT mcaudit.record.id%TYPE,
                         i_zitadel_user_id mcaudit.record.zitadel_user_id%TYPE DEFAULT NULL,
                         i_zitadel_user_name mcaudit.record.zitadel_user_name%TYPE DEFAULT NULL,
                         i_zitadel_user_company_id mcaudit.record.zitadel_user_company_id%TYPE DEFAULT NULL);
END OSAG_AUDIT;
/

CREATE OR REPLACE PUBLIC SYNONYM osag_audit FOR mcaudit.osag_audit
/

