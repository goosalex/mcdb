--liquibase formatted sql logicalFilePath:pkgb/guma2_osag_guma_state.sql 
--changeset sys:1 runOnChange:true endDelimiter:/ splitStatements:true
CREATE OR REPLACE PACKAGE BODY GUMA2.OSAG_GUMA_STATE IS
 -- no body, only constants
END OSAG_GUMA_STATE;
/
