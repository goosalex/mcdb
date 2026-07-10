--liquibase formatted sql logicalFilePath:pkg/sys_table_redefinition.sql
--changeset sys:1 runOnChange:true endDelimiter:/

-- Description: Procedures to perform online table redefinition
--              to change CLOB columns to VARCHAR2 columns.
--              Uses DBMS_REDEFINITION package.
-- Note: This example assumes that the CLOB data fits within the VARCHAR2 limit (e.g. 32767 for CDB with extended data types).
--       Adjust the target VARCHAR2 length as needed.
--       Ensure to test in a non-production environment first.
-- Prerequisites:
--   - The table must have a primary key or unique index.
--   - Sufficient space in the tablespace for interim table.
--   - Appropriate privileges to execute DBMS_REDEFINITION. (SYS AS SYSDBA)
-- Usage:
-- Procedure:  sys.OSAG_TABLE_REDEFINITION.prepare_redef_clob_to_varchar2
--             sys.OSAG_TABLE_REDEFINITION.finalize_redef_clob_to_varchar2
--             sys.OSAG_TABLE_REDEFINITION.abort_redef_clob_to_varchar2

CREATE OR REPLACE PACKAGE SYS.OSAG_TABLE_REDEFINITION IS

    PROCEDURE prepare_redef_clob_to_varchar2(
        p_schema IN VARCHAR2,
        p_table IN VARCHAR2,
        p_datalength PLS_INTEGER := 32767
    );

    PROCEDURE finalize_redef_clob_to_varchar2(
        p_schema IN VARCHAR2,
        p_table IN VARCHAR2,
        p_drop_fks IN NUMBER DEFAULT 1 -- drop referencing FKs after finalization, as they will have new names and won't be automatically switched. Optional in case you want to manually fix/rename them instead.
    );

    PROCEDURE abort_redef_clob_to_varchar2(
        p_schema IN VARCHAR2,
        p_table IN VARCHAR2
    );

    PROCEDURE refresh_redef(
        p_schema IN VARCHAR2,
        p_table IN VARCHAR2
    );

    PROCEDURE CLEANUP_INTERIM(
        p_schema IN VARCHAR2,
        p_table IN VARCHAR2,
        p_drop_table IN NUMBER DEFAULT 0 -- drop interim table after cleanup, optional in case you want to inspect it for troubleshooting
    );
    PROCEDURE "REENABLE_TMP_REFERENCINGFKS"(
        c_owner IN VARCHAR2 ,
        c_table_name IN  VARCHAR2,
        c_fknumber IN NUMBER
    );
END OSAG_TABLE_REDEFINITION;
/
