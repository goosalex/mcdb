--liquibase formatted sql logicalFilePath:pkg/auth_osag_implication.sql 
--changeset sys:1 runOnChange:true endDelimiter:/ splitStatements:true
CREATE OR REPLACE PACKAGE AUTH.OSAG_IMPLICATION AS
    PROCEDURE auth_update(
        i_logdate       IN passport_login.lastaccept%TYPE,
        i_data          IN VARCHAR2);

END OSAG_IMPLICATION;
/

create or replace public synonym OSAG_IMPLICATION for auth.osag_implication
/

