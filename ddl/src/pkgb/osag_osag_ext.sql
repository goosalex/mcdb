--liquibase formatted sql logicalFilePath:pkgb/osag_osag_ext.sql 
--changeset sys:1 runOnChange:true endDelimiter:/ splitStatements:true
CREATE OR REPLACE PACKAGE BODY OSAG.OSAG_EXT IS
    -----------------------------------------------------------------------------
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
    PROCEDURE runOsCmdExt(p_cmd IN VARCHAR2, p_length IN PLS_INTEGER,
                          p_cmd_out OUT VARCHAR2, p_cmd_exit OUT PLS_INTEGER)
        IS EXTERNAL
    NAME "runOsCmd"
    LIBRARY sys.oscall_lib
    WITH CONTEXT
        PARAMETERS (CONTEXT,
                p_cmd STRING,
                p_cmd INDICATOR SHORT,
		p_cmd LENGTH INT,
		p_length INT,
		p_length INDICATOR SHORT,
                p_cmd_out STRING,
                p_cmd_out INDICATOR SHORT,
                p_cmd_out LENGTH INT,
                p_cmd_exit INT);

    -----------------------------------------------------------------------------
    -- runOSCmd: Run an external command. Command output and exit code are
    -- discarded. Procedure is deprecated, use runOsCmdGetResult instead!
    -- input parameters:
    --   p_cmd:      command to execute
    -----------------------------------------------------------------------------
    PROCEDURE runOsCmd(p_cmd IN VARCHAR2) IS

        S_PREFIX CONSTANT VARCHAR2(32) := 'runOsCmd(): ';

        v_cmd_out  VARCHAR2(32767);    -- output of OS command
        v_cmd_exit NUMBER;             -- exit code of OS command

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        -- call the external procedure
        runOsCmdExt(p_cmd, 0, v_cmd_out, v_cmd_exit);

        plog.debug(S_PREFIX||'command exit code: '||v_cmd_exit);

    EXCEPTION
        WHEN OTHERS THEN
            plog.err(S_PREFIX||'caught exception: "'||SQLERRM);
            RAISE;

    END runOsCmd;

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
                                p_cmd_out OUT VARCHAR2, p_cmd_exit OUT NUMBER) IS

        S_PREFIX CONSTANT VARCHAR2(32) := 'runOsCmdGetResult(): ';
        S_MAX_CMD_OUT_LENGTH CONSTANT NUMBER := 32767;

        v_length NUMBER := p_length;
        v_ell_length NUMBER;

        EXTERNAL_TIMEOUT EXCEPTION;
        PRAGMA EXCEPTION_INIT (
            EXTERNAL_TIMEOUT, -20103);
    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        IF (v_length > S_MAX_CMD_OUT_LENGTH) then
            plog.debug(S_PREFIX||'truncating command output length to '||S_MAX_CMD_OUT_length||' characters');
            v_length := S_MAX_CMD_OUT_LENGTH;
        END IF;

        runOsCmdExt(p_cmd, v_length, p_cmd_out, p_cmd_exit);

        plog.debug(S_PREFIX||'command exit code: '||p_cmd_exit);

        IF (p_cmd_out IS NULL) THEN
            plog.debug(S_PREFIX||'command output is null');
        ELSE
            v_ell_length := LENGTH(p_cmd_out) / 3;
            IF (v_ell_length > 35) THEN
                v_ell_length := 35;
            END IF;

            plog.debug(S_PREFIX||'command output: "'||substr(p_cmd_out, 1, v_ell_length)||'.........'||
                       substr(p_cmd_out, -v_ell_length)||'"');
        END IF;

    EXCEPTION
        WHEN EXTERNAL_TIMEOUT THEN
            -- error message will be generated only on last retry, by calling func
            RAISE;
        WHEN OTHERS THEN
            plog.err(S_PREFIX||'caught exception: "'||SQLERRM);
            RAISE;

    END runOsCmdGetResult;

END OSAG_EXT;
/
