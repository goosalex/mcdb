--liquibase formatted sql logicalFilePath:pkgb/osag_osag_plog.sql 
--changeset sys:1 runOnChange:true endDelimiter:/ splitStatements:true
CREATE OR REPLACE PACKAGE BODY OSAG.OSAG_PLOG IS

    PROCEDURE PublishToMCDBQueue(user IN VARCHAR2, loglevel IN PLS_INTEGER, message IN VARCHAR2, caller_info IN VARCHAR2 DEFAULT '')
        IS
        o_payload MCDB_MONITOR.PLOG_MESSAGE_TYPE;
        r_enqueue_options    DBMS_AQ.ENQUEUE_OPTIONS_T; -- see https://docs.oracle.com/database/121/ARPLS/t_aq.htm#ARPLS71686
        r_message_properties DBMS_AQ.MESSAGE_PROPERTIES_T; -- see https://docs.oracle.com/database/121/ARPLS/t_aq.htm#i997396
        v_message_handle     RAW(16);
        v_session_id NUMBER;
    BEGIN
        v_session_id := SYS_CONTEXT('USERENV','SID');
        r_message_properties.expiration := 3600; -- available for dequeing for 1h.
        o_payload :=  MCDB_MONITOR.PLOG_MESSAGE_TYPE(
                severity => LevelAsString(loglevel),
                loglevel => loglevel,
                message => message,
                sender_user => user,
                sender_session => v_session_id,
                sender_proc => caller_info
            );

        DBMS_AQ.ENQUEUE(
                queue_name => 'MCDB_MONITOR.plog_messages',
                enqueue_options => r_enqueue_options,
                message_properties => r_message_properties,
                payload => o_payload,
                msgid => v_message_handle
            );
    END;
--------------------------------------------------------------------------------
    procedure who_called_my_caller( owner      out varchar2,
                                    name       out varchar2,
                                    lineno     out number,
                                    caller_t   out varchar2 );
--------------------------------------------------------------------------------
    PROCEDURE Log(loglevel IN NUMBER, message IN VARCHAR2) IS
        v_ident VARCHAR2(64);
        v_user  VARCHAR2(32);
        v_caller VARCHAR2(1000);
        oname all_objects.owner%TYPE; -- VARCHAR2(128)
        pname all_objects.object_name%TYPE; -- VARCHAR2(128)
        lnumb all_source.line%TYPE; -- number
        t_msg_record MCDB_MONITOR.PLOG_MESSAGE_TYPE; -- unused workaround to avoid PLS-00206 in next line
        callr t_msg_record.SENDER_PROC%TYPE; -- VARCHAR2(260)
        PRAGMA AUTONOMOUS_TRANSACTION;
    BEGIN
          who_called_my_caller(oname, pname, lnumb, callr);
          v_caller := oname || chr(10) || pname || chr(10) || lnumb || chr(10) || callr;
          v_user := LOWER(user);
          v_ident := 'oracle';
          PublishToMCDBQueue(v_ident,loglevel,'(' || v_user || ') ' || message, v_caller);
          COMMIT;
    END Log;

    PROCEDURE LogRaw(loglevel IN NUMBER, message IN VARCHAR2) IS
    BEGIN
        PublishToMCDBQueue('oracle',loglevel,message, '');
    END LogRaw;
--------------------------------------------------------------------------------
    PROCEDURE Emerg   (message IN VARCHAR2) IS BEGIN Log(0,message); END;
    PROCEDURE Alert   (message IN VARCHAR2) IS BEGIN Log(1,message); END;
    PROCEDURE Crit    (message IN VARCHAR2) IS BEGIN Log(2,message); END;
    PROCEDURE Err     (message IN VARCHAR2) IS BEGIN Log(3,message); END;
    PROCEDURE Warning (message IN VARCHAR2) IS BEGIN Log(4,message); END;
    PROCEDURE Notice  (message IN VARCHAR2) IS BEGIN Log(5,message); END;
    PROCEDURE Info    (message IN VARCHAR2) IS BEGIN Log(6,message); END;
    PROCEDURE Debug   (message IN VARCHAR2) IS BEGIN Log(7,message); END;

--------------------------------------------------------------------------------
    FUNCTION  LevelAsString (loglevel IN NUMBER) return VARCHAR2
        IS
        v_levelname VARCHAR2(16) := NULL;
    BEGIN
        IF loglevel = 0 THEN v_levelname := 'EMERG';   END IF;
        IF loglevel = 1 THEN v_levelname := 'ALERT';   END IF;
        IF loglevel = 2 THEN v_levelname := 'CRIT';    END IF;
        IF loglevel = 3 THEN v_levelname := 'ERR';     END IF;
        IF loglevel = 4 THEN v_levelname := 'WARNING'; END IF;
        IF loglevel = 5 THEN v_levelname := 'NOTICE';  END IF;
        IF loglevel = 6 THEN v_levelname := 'INFO';    END IF;
        IF loglevel = 7 THEN v_levelname := 'DEBUG';   END IF;
        return v_levelname;
    END LevelAsString;

    FUNCTION  LevelAsNum (loglevel IN VARCHAR2) return NUMBER
        IS
        v_level NUMBER(2) := NULL;
    BEGIN
        IF UPPER(loglevel) = 'EMERG'   THEN v_level :=0; END IF;
        IF UPPER(loglevel) = 'ALERT'   THEN v_level :=1; END IF;
        IF UPPER(loglevel) = 'CRIT'    THEN v_level :=2; END IF;
        IF UPPER(loglevel) = 'ERR'     THEN v_level :=3; END IF;
        IF UPPER(loglevel) = 'WARNING' THEN v_level :=4; END IF;
        IF UPPER(loglevel) = 'NOTICE'  THEN v_level :=5; END IF;
        IF UPPER(loglevel) = 'INFO'    THEN v_level :=6; END IF;
        IF UPPER(loglevel) = 'DEBUG'   THEN v_level :=7; END IF;
        return v_level;
    END LevelAsNum;

    PROCEDURE AuditUsage(p_owner IN VARCHAR2, p_object_type VARCHAR2, p_object_name VARCHAR2)
        IS
        PRAGMA AUTONOMOUS_TRANSACTION;
        qname utl_call_stack.UNIT_QUALIFIED_NAME;
        v_proc varchar2(128);
    BEGIN
        -- the qualified name (PACKAGE, PROCEDURE) or (PROCEDURE) or (__anonymous block)
        qname := utl_call_stack.subprogram(2);
        if qname.count > 1 then
            v_proc := utl_call_stack.subprogram(2)(2);
        else
            v_proc := null;
        end if;

        update osag.plsql_audit
        set last_used = systimestamp
        where owner = p_owner
          and object_type = REPLACE(p_object_type, ' BODY', '')
          and object_name = p_object_name
          and (  (v_proc is null and procedure_name is null)
            or (v_proc = procedure_name))
          and (   (last_used is null)
            or  (last_used < systimestamp - 1));
        commit;
    EXCEPTION
        when others then
            rollback;
    END AuditUsage;

    procedure who_called_my_caller( owner      out varchar2,
                                    name       out varchar2,
                                    lineno     out number,
                                    caller_t   out varchar2 )
        IS
        call_stack  varchar2(4096) default dbms_utility.format_call_stack;
        n           number;
        found_stack BOOLEAN default FALSE;
        line        varchar2(255);
        t           varchar2(255);
        cnt         number := 0;
        /*  NL_CHAR can be computed from a Unicode string in a portable manner. */
        NL_CHAR constant varchar2(10) := chr(10);
    begin
        --
        loop
            n := instr( call_stack, NL_CHAR );
            exit when ( cnt = 4 or n is NULL or n = 0 );
            --
            line := ltrim(substr( call_stack, 1, n-1 ));
            call_stack := substr( call_stack, n+1 );
            --
            if ( NOT found_stack ) then
                if ( line like '%handle%number%name%' ) then
                    found_stack := TRUE;
                end if;
            else
                cnt := cnt + 1;
                -- cnt = 1 is ME
                -- cnt = 2 is MY Caller
                -- cnt = 3 is Their Caller (usual in OWA_UTIL.WHO_CALLED_ME)
                if ( cnt = 4 ) then
                    -- Fix 718865
                    --lineno := to_number(substr( line, 13, 6 ));
                    --line   := substr( line, 21 );
                    n := instr(line, ' ');
                    if (n > 0)
                    then
                        t := ltrim(substr(line, n));
                        n := instr(t, ' ');
                    end if;
                    if (n > 0)
                    then
                        lineno := to_number(substr(t, 1, n - 1));
                        line := ltrim(substr(t, n));
                    else
                        lineno := 0;
                    end if;
                    if ( line like 'pr%' ) then
                        n := length( 'procedure ' );
                    elsif ( line like 'fun%' ) then
                        n := length( 'function ' );
                    elsif ( line like 'package body%' ) then
                        n := length( 'package body ' );
                    elsif ( line like 'pack%' ) then
                        n := length( 'package ' );
                    elsif ( line like 'anon%' ) then
                        n := length( 'anonymous block ' );
                    else
                        n:=0;
                    end if;

                    if (n = 0) then
                        -- could be a trigger or a type body
                        caller_t := ltrim(rtrim(upper(substr(line, n+1))));
                    else
                        caller_t := ltrim(rtrim(upper(substr(line,1,n-1))));
                    end if;

                    line := substr( line, n );
                    n := instr( line, '.' );
                    owner := ltrim(rtrim(substr( line, 1, n-1 )));
                    name  := ltrim(rtrim(substr( line, n+1 )));
                end if;
            end if;
        end loop;
    end who_called_my_caller;

--
END OSAG_PLOG;
/
