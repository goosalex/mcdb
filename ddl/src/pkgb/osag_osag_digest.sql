--liquibase formatted sql logicalFilePath:pkgb/osag_osag_digest.sql 
--changeset sys:1 runOnChange:true endDelimiter:/ splitStatements:true
CREATE OR REPLACE PACKAGE BODY OSAG.OSAG_DIGEST IS

-------------------------------------------------------------------------------------------
-- FUNCTION md5
-------------------------------------------------------------------------------------------
    FUNCTION md5(p_string IN varchar2)
        return varchar2 IS

        digest varchar2(16);

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        return SYS.DBMS_CRYPTO.HASH (UTL_I18N.STRING_TO_RAW(p_string), SYS.DBMS_CRYPTO.HASH_MD5);
    END;

-------------------------------------------------------------------------------------------
-- FUNCTION sha256
-------------------------------------------------------------------------------------------
    FUNCTION sha256(p_string IN varchar2)
        return varchar2 IS
    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        return rawtohex(SYS.DBMS_CRYPTO.HASH (UTL_I18N.STRING_TO_RAW(p_string), SYS.DBMS_CRYPTO.HASH_SH256));
    END;

END OSAG_DIGEST;
/
