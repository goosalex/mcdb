--liquibase formatted sql logicalFilePath:pkg/osixinfo_osag_exceptions.sql 
--changeset sys:1 runOnChange:true endDelimiter:/ splitStatements:true
CREATE OR REPLACE PACKAGE OSIXINFO.OSAG_EXCEPTIONS AS
    /************************************************************
     *
     * Exceptions for the PL/SQL package OSAG_GUMA
     *
     ************************************************************/

    e_abort        EXCEPTION;    -- abort this procedure
    e_silentexit   EXCEPTION;    -- exit procedure silently (without exception)

END OSAG_EXCEPTIONS;
/


