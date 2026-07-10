--liquibase formatted sql logicalFilePath:pkgb/osixinfo_osag_exceptions.sql 
--changeset sys:1 runOnChange:true endDelimiter:/ splitStatements:true
CREATE OR REPLACE PACKAGE BODY OSIXINFO.OSAG_EXCEPTIONS IS
 -- no body, only constants
END OSAG_EXCEPTIONS;
/

