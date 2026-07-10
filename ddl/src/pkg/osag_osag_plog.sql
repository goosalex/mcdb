--liquibase formatted sql logicalFilePath:pkg/osag_osag_plog.sql 
--changeset sys:1 runOnChange:true endDelimiter:/ splitStatements:true
CREATE OR REPLACE PACKAGE OSAG.OSAG_PLOG AS
--------------------------------------------------------------------------------
--  PUBLIC Logging Functions
--  Purpose: write message to syslog with the level used as procedure name
--  Input Arguments: message: the log string
--------------------------------------------------------------------------------

    PROCEDURE Emerg   (message IN VARCHAR2);
    PROCEDURE Alert   (message IN VARCHAR2);
    PROCEDURE Crit    (message IN VARCHAR2);
    PROCEDURE Err     (message IN VARCHAR2);
    PROCEDURE Warning (message IN VARCHAR2);
    PROCEDURE Notice  (message IN VARCHAR2);
    PROCEDURE Info    (message IN VARCHAR2);
    PROCEDURE Debug   (message IN VARCHAR2);

--------------------------------------------------------------------------------
--  PUBLIC Type Conversions
--  Purpose: convert loglevel representations between strings and numbers
--  Input Argument: level: the level you wish to convert
--  Output Argument: the converted level
--------------------------------------------------------------------------------

    FUNCTION  LevelAsString (loglevel IN NUMBER) return VARCHAR2;
    FUNCTION  LevelAsNum (loglevel IN VARCHAR2) return NUMBER;

--------------------------------------------------------------------------------
--  PUBLIC Generic Logging Function
--  Purpose: write message to syslog with the level used as argument
--  (facilitates generated calls e.g. in consistency checks)
--  Input Arguments: message: the log string
--------------------------------------------------------------------------------

    PROCEDURE Log(loglevel IN NUMBER, message IN VARCHAR2);
    -- LogRaw does not filter by level, does not modify the message and does not determine the caller.
    -- It also doesn't run in a separate transaction, so the message is not logged on rollback.
    PROCEDURE LogRaw(loglevel IN NUMBER, message IN VARCHAR2);

    -- always call as plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
    PROCEDURE AuditUsage(p_owner IN VARCHAR2, p_object_type VARCHAR2, p_object_name VARCHAR2);

END OSAG_PLOG;
/
--
CREATE OR REPLACE PUBLIC SYNONYM plog FOR OSAG.OSAG_PLOG
/

