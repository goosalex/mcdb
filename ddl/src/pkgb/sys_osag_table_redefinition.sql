--liquibase formatted sql logicalFilePath:pkgb/sys_osag_table_redefinition.sql
--changeset sys:1 runOnChange:true endDelimiter:/


CREATE OR REPLACE PACKAGE BODY SYS.OSAG_TABLE_REDEFINITION IS
    -- helper function to create interim table for redefinition
    -- with CLOB to VARCHAR2 column mapping
    -- NOT to be called directly, used by osag_prepare_redef_clob_to_varchar2
    PROCEDURE "_CREATE_REDEF_INTERIM"(
        p_schema IN VARCHAR2,
        p_table IN VARCHAR2,
        p_datalength IN PLS_INTEGER, -- target VARCHAR2 length for CLOB columns
        p_col_mapping OUT VARCHAR2
    ) AS
        v_sql            CLOB;
        v_col_map        VARCHAR2(32767);
        v_int_table      VARCHAR2(128);
        -- dummy change. Increment to force re-execution.
        v_ignore NUMBER := 1;


        -- Cursor to collect PK and unique constraint columns
        CURSOR cons_cur IS
            SELECT acc.column_name
            FROM ALL_CONS_COLUMNS acc
                     JOIN ALL_CONSTRAINTS ac
                          ON acc.owner = ac.owner
                              AND acc.constraint_name = ac.constraint_name
            WHERE ac.owner = UPPER(p_schema)
              AND ac.table_name = UPPER(p_table)
              AND ac.constraint_type IN ('P', 'U');
        TYPE colset IS TABLE OF VARCHAR2(128) INDEX BY VARCHAR2(128);
        notnull_excluded colset;
    BEGIN
        -- Build set of columns that should NOT get NOT NULL due to PK/unique constraint
        FOR rec IN cons_cur
            LOOP
                notnull_excluded(rec.column_name) := 1;
            END LOOP;

        v_int_table := p_table || '_INT';
        v_sql := 'CREATE TABLE ' || p_schema || '.' || v_int_table || ' (';
        v_col_map := '';
        FOR c IN (
            SELECT column_name,
                   data_type,
                   data_length,
                   data_precision,
                   data_scale,
                   nullable,
                   data_default
            FROM ALL_TAB_COLUMNS
            WHERE owner = UPPER(p_schema)
              AND table_name = UPPER(p_table)
            ORDER BY column_id
            )
            LOOP
                -- Data type and conversion mapping
                IF c.data_type = 'CLOB' THEN
                    v_sql := v_sql || c.column_name || ' VARCHAR2(' || p_datalength || ')';
                    v_col_map :=
                            v_col_map || 'dbms_lob.SUBSTR(' || c.column_name || ',' || p_datalength || ',1) ' || c.column_name;
                ELSIF c.data_type = 'VARCHAR2' THEN
                    v_sql := v_sql || c.column_name || ' VARCHAR2(' || c.data_length || ')';
                    v_col_map := v_col_map || c.column_name || ' ' || c.column_name;
                ELSIF c.data_type IN ('CHAR', 'NCHAR') THEN
                    v_sql := v_sql || c.column_name || ' ' || c.data_type || '(' || c.data_length || ')';
                    v_col_map := v_col_map || c.column_name || ' ' || c.column_name;
                ELSIF c.data_type IN ('NUMBER', 'FLOAT') THEN
                    IF c.data_precision IS NOT NULL AND c.data_scale IS NOT NULL THEN
                        v_sql := v_sql || c.column_name || ' ' || c.data_type || '(' || c.data_precision || ',' ||
                                 c.data_scale || ')';
                    ELSE
                        v_sql := v_sql || c.column_name || ' ' || c.data_type;
                    END IF;
                    v_col_map := v_col_map || c.column_name || ' ' || c.column_name;
                ELSIF c.data_type = 'DATE' THEN
                    v_sql := v_sql || c.column_name || ' DATE';
                    v_col_map := v_col_map || c.column_name || ' ' || c.column_name;
                ELSE
                    -- Replicate other types as-is
                    v_sql := v_sql || c.column_name || ' ' || c.data_type;
                    v_col_map := v_col_map || c.column_name || ' ' || c.column_name;
                END IF;

-- Preserve default values
                IF c.data_default IS NOT NULL THEN
                    v_sql := v_sql || ' DEFAULT ' || RTRIM(c.data_default);
                END IF;



                v_sql := v_sql || ', ';
                v_col_map := v_col_map || ', ';
            END LOOP;
-- Remove last comma and space
        v_sql := RTRIM(v_sql, ', ');
        v_sql := v_sql || ')';
        v_col_map := RTRIM(v_col_map, ', ');

        EXECUTE IMMEDIATE v_sql;
        p_col_mapping := v_col_map;
    END;

    -- Helper procedure to drop all foreign keys referencing a given table
    -- helpful if you don't know all FKs in advance. Redifinition generates new FK names for _INT tables
    -- and doesn't drop them after finalization. This cleans them up.
    PROCEDURE "_DROP_ALL_REFERENCINGFKS"(
        c_owner IN VARCHAR2 ,
        c_table_name IN  VARCHAR2
    ) AS
    BEGIN
        FOR r IN (
            SELECT
                fk.owner        AS fk_owner,
                fk.table_name   AS fk_table,
                fk.constraint_name
            FROM dba_constraints fk
                     JOIN dba_constraints pk
                          ON fk.r_constraint_name = pk.constraint_name
                              AND fk.r_owner           = pk.owner
            WHERE fk.constraint_type = 'R'
              AND pk.owner           = c_owner
              AND pk.table_name      = c_table_name
            )
            LOOP
                DBMS_OUTPUT.PUT_LINE(
                        'Dropping FK ' || r.fk_owner || '.' || r.constraint_name ||
                        ' on table ' || r.fk_owner || '.' || r.fk_table
                );

                EXECUTE IMMEDIATE
                    'ALTER TABLE ' || r.fk_owner || '.' || r.fk_table ||
                    ' DROP CONSTRAINT ' || r.constraint_name;
            END LOOP;
    END;

    PROCEDURE "REENABLE_TMP_REFERENCINGFKS"(
        c_owner IN VARCHAR2 ,
        c_table_name IN  VARCHAR2,
        c_fknumber IN NUMBER
    ) AS
    BEGIN
        FOR r IN (
            SELECT
                fk.owner        AS fk_owner,
                fk.table_name   AS fk_table,
                fk.constraint_name,
                fk.table_name || '_FK' || c_fknumber AS original_constraint_name
            FROM dba_constraints fk
                     JOIN dba_constraints pk
                          ON fk.r_constraint_name = pk.constraint_name
                              AND fk.r_owner = pk.owner
            WHERE fk.constraint_type = 'R'
              AND fk.owner = c_owner
              AND fk.table_name = c_table_name
              AND fk.constraint_name LIKE 'TMP$$\_%' ESCAPE '\'
                AND fk.constraint_name LIKE '%FK' || c_fknumber || '0'
            )
            LOOP
                DBMS_OUTPUT.PUT_LINE(
                        'Renaming FK ' || r.fk_owner || '.' || r.constraint_name ||
                        ' on table ' || r.fk_owner || '.' || r.fk_table || ' TO ' || r.original_constraint_name
                );
                EXECUTE IMMEDIATE
                    'ALTER TABLE ' || r.fk_owner || '.' || r.fk_table ||
                    ' RENAME CONSTRAINT ' || r.constraint_name || ' TO ' || r.original_constraint_name;
                DBMS_OUTPUT.PUT_LINE(
                        'Enabling FK ' || r.fk_owner || '.' || r.original_constraint_name ||
                        ' on table ' || r.fk_owner || '.' || r.fk_table || ' NOVALIDATE'
                );
                EXECUTE IMMEDIATE
                    'ALTER TABLE ' || r.fk_owner || '.' || r.fk_table ||
                    ' ENABLE NOVALIDATE CONSTRAINT ' || r.original_constraint_name;
                DBMS_OUTPUT.PUT_LINE(
                        'Enabling FK ' || r.fk_owner || '.' || r.original_constraint_name ||
                        ' on table ' || r.fk_owner || '.' || r.fk_table || ' VALIDATE'
                );
                EXECUTE IMMEDIATE
                    'ALTER TABLE ' || r.fk_owner || '.' || r.fk_table ||
                    ' ENABLE VALIDATE CONSTRAINT ' || r.original_constraint_name;
            END LOOP;
    END;

    PROCEDURE prepare_redef_clob_to_varchar2(
        p_schema IN VARCHAR2,
        p_table IN VARCHAR2,
        p_datalength PLS_INTEGER := 32767
    ) AS
        col_mapping VARCHAR2(32767);
        orig_ddl    CLOB;
        v_dummy NUMBER;
    BEGIN
        BEGIN
            -- Simple check to ensure table exists
            EXECUTE IMMEDIATE 'SELECT 1 FROM ' || UPPER(p_schema) || '.' || UPPER(p_table) || ' WHERE ROWNUM = 1' INTO v_dummy;
        EXCEPTION
            -- catch ORA-01403 on empty, but existing table
            WHEN NO_DATA_FOUND THEN
                NULL;
            WHEN OTHERS THEN
                RAISE_APPLICATION_ERROR(-20001, 'Table ' || p_schema || '.' || p_table || ' does not exist or is inaccessible.');
        END;

        EXECUTE IMMEDIATE 'DROP MATERIALIZED VIEW IF EXISTS ' || p_schema || '.' || p_table || '_INT';
        EXECUTE IMMEDIATE 'DROP TABLE IF EXISTS ' || p_schema || '.' || p_table || '_INT';

        -- select dbms_metadata.get_ddl('TABLE', p_table, p_schema) into orig_ddl from dual;
        -- DBMS_OUTPUT.PUT_LINE('Original DDL: ' || orig_ddl);

-- ===== 2. Create interim table with desired column type =====
        "_CREATE_REDEF_INTERIM"(p_schema, p_table, p_datalength, col_mapping);
        DBMS_OUTPUT.PUT_LINE('Column Mapping: ' || col_mapping);

        -- ===== 4. Start the redefinition (keeps table online) =====
        DBMS_REDEFINITION.START_REDEF_TABLE(
                uname => p_schema,
                orig_table => p_table,
                int_table => p_table || '_INT',
                col_mapping => col_mapping
        );

        -- ===== 5. Optionally, synchronize interim table (for large/active tables) =====
-- Can be run multiple times before finalization to catch up changes.
        BEGIN
            DBMS_REDEFINITION.SYNC_INTERIM_TABLE(
                    uname => p_schema,
                    orig_table => p_table,
                    int_table => p_table || '_INT');
        END;

-- ===== 6. Copy dependent objects (indexes, triggers, constraints, privileges) =====
        DECLARE
            v_num_errors NUMBER;
        BEGIN
            DBMS_REDEFINITION.COPY_TABLE_DEPENDENTS(
                    uname => p_schema,
                    orig_table => p_table,
                    int_table => p_table || '_INT',
                    copy_indexes => DBMS_REDEFINITION.CONS_ORIG_PARAMS,
                    copy_triggers => TRUE,
                    copy_constraints => TRUE,
                    copy_privileges => TRUE,
                    ignore_errors => FALSE,
                    NUM_ERRORS => v_num_errors,
                    copy_statistics => TRUE,
                    copy_mvlog => FALSE
            );
            IF v_num_errors > 0 THEN
                DBMS_OUTPUT.PUT_LINE('Warning: ' || v_num_errors || ' errors occurred while copying dependents.');
            END IF;
        END;


        BEGIN
            DBMS_REDEFINITION.SYNC_INTERIM_TABLE(
                    uname => p_schema,
                    orig_table => p_table,
                    int_table => p_table || '_INT');
        END;
    end;

--- ===== 6.5. (Optional) -- INTERIM SYNC =====
-- Can be run multiple times before finalization to catch up changes.
    PROCEDURE refresh_redef(
        p_schema IN VARCHAR2,
        p_table IN VARCHAR2
    ) AS
        v_dummy NUMBER;
    BEGIN
        BEGIN
            -- Simple check to ensure table exists
            EXECUTE IMMEDIATE 'SELECT 1 FROM ' || UPPER(p_schema) || '.' || UPPER(p_table) || ' WHERE ROWNUM = 1' INTO v_dummy;
        EXCEPTION
            -- catch ORA-01403 on empty, but existing table
            WHEN NO_DATA_FOUND THEN
                NULL;
            WHEN OTHERS THEN
                RAISE_APPLICATION_ERROR(-20001, 'Table ' || p_schema || '.' || p_table || ' does not exist or is inaccessible.');
        END;
        BEGIN
            DBMS_REDEFINITION.SYNC_INTERIM_TABLE(
                    uname => p_schema,
                    orig_table => p_table,
                    int_table => p_table || '_INT');
        END;
    end;

-- ===== 7. (Manual Step) -- FINALIZATION at chosen time =====
-- Stop application writes, if you need absolute zero data loss/change
-- Execute at your chosen downtime window (quick process, short lock)
-- This step locks DML (write operations) briefly.
    PROCEDURE finalize_redef_clob_to_varchar2(
        p_schema IN VARCHAR2,
        p_table IN VARCHAR2,
        p_drop_fks IN NUMBER DEFAULT 1 -- drop referencing FKs after finalization, as they will have new names and won't be automatically switched. Optional in case you want to manually fix/rename them instead.
    ) AS
        new_ddl CLOB;
        v_dummy NUMBER;
    BEGIN
        BEGIN
            -- Simple check to ensure table exists
            EXECUTE IMMEDIATE 'SELECT 1 FROM ' || UPPER(p_schema) || '.' || UPPER(p_table) || ' WHERE ROWNUM = 1' INTO v_dummy;
        EXCEPTION
            -- catch ORA-01403 on empty, but existing table
            WHEN NO_DATA_FOUND THEN
                NULL;
            WHEN OTHERS THEN
                RAISE_APPLICATION_ERROR(-20001, 'Table ' || p_schema || '.' || p_table || ' does not exist or is inaccessible.');
        END;
        BEGIN
            DBMS_REDEFINITION.SYNC_INTERIM_TABLE(
                    uname => p_schema,
                    orig_table => p_table,
                    int_table => p_table || '_INT');
        END;
        BEGIN
            DBMS_REDEFINITION.FINISH_REDEF_TABLE(
                    uname => p_schema,
                    orig_table => p_table,
                    int_table => p_table || '_INT');
        END;
        IF p_drop_fks = 1 THEN BEGIN
            DBMS_OUTPUT.PUT_LINE('Dropping referencing FKs with new names on interim table (if any)...');
            "_DROP_ALL_REFERENCINGFKS"(UPPER(p_schema), UPPER(p_table || '_INT'));
        END;
        END IF;
        -- ===== VERIFICATION =====
-- Check the definition
        BEGIN
            select dbms_metadata.get_ddl('TABLE', p_table, p_schema) into new_ddl from dual;
            DBMS_OUTPUT.PUT_LINE('New DDL: ' || new_ddl);
        END;
    END;

-- NOT HAPPY WITH RESULT, NEEDS TO ABORT REDEFINITION
    PROCEDURE abort_redef_clob_to_varchar2(
        p_schema IN VARCHAR2,
        p_table IN VARCHAR2
    ) AS
        v_dummy NUMBER;
    BEGIN
        EXECUTE IMMEDIATE 'SELECT 1 FROM ' || UPPER(p_schema) || '.' || UPPER(p_table) || ' WHERE ROWNUM = 1' INTO v_dummy;
        DBMS_REDEFINITION.ABORT_REDEF_TABLE(UNAME => p_schema, ORIG_TABLE => p_table, INT_TABLE => p_table || '_INT');
        EXECUTE IMMEDIATE 'DROP TABLE IF EXISTS ' || p_schema || '.' || p_table || '_INT';
    end;

    PROCEDURE CLEANUP_INTERIM(
        p_schema IN VARCHAR2,
        p_table IN VARCHAR2,
        p_drop_table IN NUMBER DEFAULT 0 -- drop interim table after finalization, as it will have new name and won't be automatically switched. Optional in case you want to keep it for manual inspection instead of dropping.
    ) AS
    BEGIN
        "_DROP_ALL_REFERENCINGFKS"(UPPER(p_schema), UPPER(p_table || '_INT'));
        IF p_drop_table = 1 THEN
            EXECUTE IMMEDIATE 'DROP TABLE IF EXISTS ' || p_schema || '.' || p_table || '_INT';
        END IF;
    END;
END OSAG_TABLE_REDEFINITION;
/