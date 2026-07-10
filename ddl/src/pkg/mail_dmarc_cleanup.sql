--liquibase formatted sql logicalFilePath:pkg/mail_dmarc_cleanup.sql 
--changeset sys:1 runOnChange:true endDelimiter:/ splitStatements:true
CREATE OR REPLACE PACKAGE mail.dmarc_cleanup AS

    PROCEDURE cleanup_reports_aged_days(days NUMBER);

END dmarc_cleanup;
/
