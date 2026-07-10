--liquibase formatted sql logicalFilePath:pkg/fw_osag_fw.sql 
--changeset sys:1 runOnChange:true endDelimiter:/ splitStatements:true
CREATE OR REPLACE PACKAGE FW.OSAG_FW AS
    --
    -- FW schema maintenance.

    --
    -- clean up old config locks
    --
    PROCEDURE config_lock_cleanup;

END OSAG_FW;
/
