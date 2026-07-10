--liquibase formatted sql logicalFilePath:pkg/guma2_osag_guma_state.sql 
--changeset sys:1 runOnChange:true endDelimiter:/ splitStatements:true
CREATE OR REPLACE PACKAGE GUMA2.OSAG_GUMA_STATE AS
    /************************************************************
     *
     * Exceptions for the PL/SQL package OSAG_GUMA
     *
     ************************************************************/

    e_abort        EXCEPTION;    -- abort this procedure
    e_silentexit   EXCEPTION;    -- exit procedure silently (without exception)

END OSAG_GUMA_STATE;
/
