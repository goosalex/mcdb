--liquibase formatted sql logicalFilePath:pkgb/mcaudit_osag_audit.sql 
--changeset sys:1 runOnChange:true endDelimiter:/ splitStatements:true
CREATE OR REPLACE PACKAGE BODY MCAUDIT.OSAG_AUDIT IS
-- -----------------------------------------------------------------------------
-- PROCEDURE add_record:: add an audit record
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
                             i_zitadel_user_company_id mcaudit.record.zitadel_user_company_id%TYPE DEFAULT NULL) IS
    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        IF (io_transaction_id IS NULL) THEN
          io_transaction_id := transaction_seq.nextval;
        END IF;

        IF io_record_id IS NULL THEN
          io_record_id := record_seq.nextval;
        END IF;

        INSERT INTO record
        (id, timestamp, application_id, component_id, record_type_id, severity_id, message,
         details, transaction_id, company_id, contact_id, object_id, object_type_id, ticket_id, zitadel_user_id, zitadel_user_name, zitadel_user_company_id)
        VALUES (io_record_id, systimestamp, i_application_id, i_component_id,
                i_record_type_id, i_severity_id, i_message, i_details, io_transaction_id, i_company_id, i_contact_id,
                i_object_id, (SELECT id FROM mss.object_type WHERE table_name = i_table_name), i_ticket_id,
                i_zitadel_user_id, i_zitadel_user_name, i_zitadel_user_company_id);

    END add_record_raw2;

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
                             i_ticket_id mcaudit.record.ticket_id%TYPE DEFAULT NULL) IS
      v_record_id mcaudit.record.id%TYPE;
    BEGIN
      plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);

      add_record_raw2(
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
      v_record_id
      );

    END add_record_raw;

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
                         i_zitadel_user_company_id mcaudit.record.zitadel_user_company_id%TYPE DEFAULT NULL) IS

      v_application_id mcaudit.application.id%TYPE;
      v_component_id mcaudit.component.id%TYPE;
      v_record_type_id mcaudit.record_type.id%TYPE;
      v_severity_id mcaudit.severity.id%TYPE;

    BEGIN
      plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
      SELECT id INTO v_application_id FROM application WHERE short = i_application_short;
      SELECT id INTO v_component_id FROM component WHERE short = i_component_short;
      SELECT id INTO v_record_type_id FROM record_type WHERE short = i_record_type_short;
      SELECT id INTO v_severity_id FROM severity WHERE short = i_severity_short;

      add_record_raw2(i_application_id => v_application_id, i_component_id => v_component_id,
                     i_record_type_id => v_record_type_id, i_severity_id => v_severity_id,
                     io_transaction_id => io_transaction_id, i_message => i_message,
                     i_details => i_details, i_company_id => i_company_id, i_contact_id => i_contact_id,
                     i_table_name => i_table_name, i_object_id => i_object_id,
                     i_ticket_id => i_ticket_id, io_record_id => io_record_id, i_zitadel_user_id => i_zitadel_user_id,
                     i_zitadel_user_name => i_zitadel_user_name, i_zitadel_user_company_id => i_zitadel_user_company_id);

    END add_record2;

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
                         i_ticket_id mcaudit.record.ticket_id%TYPE DEFAULT NULL) IS

        v_application_id mcaudit.application.id%TYPE;
        v_component_id mcaudit.component.id%TYPE;
        v_record_type_id mcaudit.record_type.id%TYPE;
        v_severity_id mcaudit.severity.id%TYPE;
        v_record_id mcaudit.record.id%TYPE;
    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        SELECT id INTO v_application_id FROM application WHERE short = i_application_short;
        SELECT id INTO v_component_id FROM component WHERE short = i_component_short;
        SELECT id INTO v_record_type_id FROM record_type WHERE short = i_record_type_short;
        SELECT id INTO v_severity_id FROM severity WHERE short = i_severity_short;

        add_record_raw2(i_application_id => v_application_id, i_component_id => v_component_id,
                       i_record_type_id => v_record_type_id, i_severity_id => v_severity_id,
                       io_transaction_id => io_transaction_id, i_message => i_message,
                       i_details => i_details, i_company_id => i_company_id, i_contact_id => i_contact_id,
                       i_table_name => i_table_name, i_object_id => i_object_id,
                       i_ticket_id => i_ticket_id, io_record_id => v_record_id);

    END add_record;

END OSAG_AUDIT;
/
