--liquibase formatted sql logicalFilePath:types/mcdb_monitor_plog_message_type.sql 
--changeset sys:1 runOnChange:true endDelimiter:/ splitStatements:true
BEGIN
    EXECUTE IMMEDIATE
'CREATE OR REPLACE TYPE MCDB_MONITOR.plog_message_type authid definer AS OBJECT
(
    message VARCHAR2(4000),
    severity VARCHAR2(20),
    loglevel NUMBER,
    sender_user VARCHAR(128),
    sender_session NUMBER,
    sender_proc VARCHAR(260) -- 2*128 all_objects.object_name + all_objects_owner_name + margin
)
' ;
exception WHEN OTHERS THEN
    IF SQLCODE = -2303 THEN
        NULL; -- suppresses ORA-02303 exception
    ELSE
        RAISE;
    END IF;
end;
/
