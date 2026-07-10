create schema if not exists plog;

SET search_path TO plog, public;

CREATE OR REPLACE PROCEDURE plog.LOG(
        level IN INTEGER,
        message IN VARCHAR
    ) AS $$
    DECLARE
        v_log_level VARCHAR;
    BEGIN
    END;
$$ LANGUAGE PLPGSQL
        SECURITY DEFINER;


    CREATE OR REPLACE PROCEDURE plog.Emerg   (message IN VARCHAR) AS 'BEGIN CALL plog.Log(0,message); END' LANGUAGE PLPGSQL
        SECURITY DEFINER;
    CREATE PROCEDURE Alert   (message IN VARCHAR) AS 'BEGIN CALL plog.Log(1,message); END' LANGUAGE PLPGSQL
        SECURITY DEFINER;
    CREATE PROCEDURE Crit    (message IN VARCHAR) AS 'BEGIN CALL plog.Log(2,message); END' LANGUAGE PLPGSQL
        SECURITY DEFINER;
    CREATE PROCEDURE Err     (message IN VARCHAR) AS 'BEGIN CALL plog.Log(3,message); END' LANGUAGE PLPGSQL
        SECURITY DEFINER;
    CREATE PROCEDURE Warning (message IN VARCHAR) AS 'BEGIN CALL plog.Log(4,message); END' LANGUAGE PLPGSQL
        SECURITY DEFINER;
    CREATE PROCEDURE Notice  (message IN VARCHAR) AS 'BEGIN CALL plog.Log(5,message); END' LANGUAGE PLPGSQL
        SECURITY DEFINER;
    CREATE PROCEDURE Info    (message IN VARCHAR) AS 'BEGIN CALL plog.Log(6,message); END' LANGUAGE PLPGSQL
        SECURITY DEFINER;
    CREATE PROCEDURE Debug   (message IN VARCHAR) AS 'BEGIN CALL plog.Log(7,message); END' LANGUAGE PLPGSQL
        SECURITY DEFINER;

CREATE EXTENSION pgcrypto;
create or replace function public.sha256(text text)
    returns text
as $$
BEGIN
    RETURN encode(digest(text, 'sha256'), 'hex');
END;
$$ language plpgsql;

-- Replacement for Event Queue

SET search_path = osag,public; CREATE OR REPLACE PROCEDURE osag.osag_plog_publishtomcdbqueue (username text, loglevel integer, message text, caller_info text DEFAULT '') AS $body$
DECLARE


    v_session_id bigint;

BEGIN

    select datid from  pg_stat_activity where state = 'active' into v_session_id;
    CALL pg_notify('plog', format('Session %i, Message %s',v_session_id,message));
END;
$body$
    LANGUAGE PLPGSQL
    SECURITY DEFINER;

create table public.dual (
                             a integer
);
insert into public.dual values (1);

create schema if not exists dbms_utility;
create or replace function dbms_utility.get_time() returns bigint AS $$
declare
    v_time bigint;
begin
    select round(extract(epoch from now()) * 100) into v_time;
    return v_time;
end;
$$ language plpgsql;


CREATE EXTENSION orafce;