--liquibase formatted sql logicalFilePath:pkg/mss_osag_dbprop_state.sql 
--changeset sys:1 runOnChange:true endDelimiter:/ splitStatements:true
CREATE OR REPLACE PACKAGE MSS.OSAG_DBPROP_STATE AS

    e_abort        EXCEPTION;    -- abort this procedure

    unknown_dbprop EXCEPTION;
    S_ERRNO_UNKNOWN_DBPROP CONSTANT NUMBER := -20801;
    PRAGMA EXCEPTION_INIT (unknown_dbprop, -20801);

END OSAG_DBPROP_STATE;
/
