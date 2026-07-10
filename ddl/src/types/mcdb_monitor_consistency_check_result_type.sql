--liquibase formatted sql logicalFilePath:types/mcdb_monitor_consistency_check_result_type.sql 
--changeset sys:1 runOnChange:true endDelimiter:/ splitStatements:true

-- this will normally throw ORA-02303: cannot drop or replace a type with type or table dependents

BEGIN
    EXECUTE IMMEDIATE
'CREATE OR REPLACE TYPE MCDB_MONITOR.consistency_check_result_type authid definer AS OBJECT
(
    check_name VARCHAR2(200),
    message VARCHAR2(4000),
    xml_message CLOB,
    check_group VARCHAR2(200),
    severity VARCHAR2(20),
    run_ts TIMESTAMP
);
' ;
exception WHEN OTHERS THEN
    IF SQLCODE = -2303 THEN
        NULL; -- suppresses ORA-02303 exception
    ELSE
         RAISE;
    END IF;
end;
/
