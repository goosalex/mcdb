--liquibase formatted sql logicalFilePath:pkg/fyi_osag_fyi.sql 
--changeset sys:1 runOnChange:true endDelimiter:/ splitStatements:true
CREATE OR REPLACE PACKAGE fyi.OSAG_FYI AS

    /*
     * this package contains the procedure to automate the check and deletion
     * of old entries in the fyi tables
     *
     */

    /*
     * procedure check_old_entries
     *
     * this procedure checks the fyi.message_history, fyi.affected_host,
     * fyi_notification_event and fyi.target tables and delete entries older than 3 months
     *
     */
    PROCEDURE check_old_entries;


END OSAG_FYI;
/
