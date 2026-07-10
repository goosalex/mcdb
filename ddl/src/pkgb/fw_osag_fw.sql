--liquibase formatted sql logicalFilePath:pkgb/fw_osag_fw.sql 
--changeset sys:1 runOnChange:true endDelimiter:/ splitStatements:true
CREATE OR REPLACE PACKAGE BODY FW.OSAG_FW IS

    PROCEDURE config_lock_cleanup
        IS
        v_max_age TIMESTAMP WITH TIME ZONE;
    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        v_max_age := SYSDATE - (1/24);

        DELETE FROM fw.config_lock WHERE last_action < v_max_age;
    END;

END OSAG_FW;
/
