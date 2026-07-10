--liquibase formatted sql logicalFilePath:pkg/guma2_osag_implication.sql 
--changeset sys:1 runOnChange:true endDelimiter:/ splitStatements:true
CREATE OR REPLACE PACKAGE GUMA2.OSAG_IMPLICATION AS
    PROCEDURE auth_update(
        i_logdate       IN syslog_message.log_date%TYPE,
        i_data          IN syslog_message.message%TYPE);

END OSAG_IMPLICATION;
/


