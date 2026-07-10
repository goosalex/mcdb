--liquibase formatted sql logicalFilePath:pkg/osag_osag_ext.sql 
--changeset sys:1 runOnChange:true endDelimiter:/ splitStatements:true
CREATE OR REPLACE PACKAGE OSAG.OSAG_EXT IS
    -------------------------------------------------------------------------------
    -- written by ok@open.ch, January 2002;
    -- copyright 2002-2003 Open Systems AG, Switzerland
    --
    -- Manages the scheme auth - provides function for altering
    -- records - selects are done directly
    -------------------------------------------------------------------------------

    -----------------------------------------------------------------------------
    -- runOSCmd: Run an external command. Command output and exit code are
    -- discarded. Procedure is deprecated, use runOsCmdGetResult instead!
    -- input parameters:
    --   p_cmd:      command to execute
    -----------------------------------------------------------------------------
    PROCEDURE runOsCmd(p_cmd IN VARCHAR2);

    -----------------------------------------------------------------------------
    -- runOsCmdGetResult: Run an external command. Command output and exit code
    -- are returned in p_cmd_out and p_cmd_exit respectively. The maximum
    -- length of output returned is specified with p_length (max. value is
    -- 32767, larger values of p_length are truncated)
    -- input parameters:
    --   p_cmd:      command to execute
    --   p_length:   max. length of returned command output
    -- output parameters:
    --   p_cmd_out:  command output
    --   p_cmd_exit: exit code of executed command
    -----------------------------------------------------------------------------
    PROCEDURE runOsCmdGetResult(p_cmd IN VARCHAR2, p_length IN NUMBER,
                                p_cmd_out OUT VARCHAR2, p_cmd_exit OUT NUMBER);

    ----------------------------------------------------------------------------
    -- runOsCmdExt: External procedure to execute an OS command and capture its
    -- output and exit code. Don't ever call this procedure from outside this
    -- package, the API might change at any time!
    -- input parameters:
    --   p_cmd:      command to execute
    --   p_length:   max. length of returned command output
    -- output parameters:
    --   p_cmd_out:  command output
    --   p_cmd_exit: exit code of executed command
    -----------------------------------------------------------------------------
    --PROCEDURE runOsCmdExt(p_cmd IN VARCHAR2, p_length IN PLS_INTEGER,
    --	        p_cmd_out OUT VARCHAR2, p_cmd_exit OUT PLS_INTEGER);

END OSAG_EXT;
/

CREATE OR REPLACE PUBLIC SYNONYM OSAG_EXT FOR OSAG.OSAG_EXT
/

