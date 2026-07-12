-- migration/pgsql/osag/osag_plog.sql
--
-- STUB translation of OSAG.OSAG_PLOG (ddl/src/pkg/osag_osag_plog.sql,
-- ddl/src/pkgb/osag_osag_plog.sql). Locked decision (02-CONTEXT.md, D-P5a): plog is a
-- throwaway stub for Phase 2 -- "the simplest thing that works: write/print the log
-- line, and make it observable enough that a test can assert 'this error path logged
-- X'." The real UDP datagram shipper is Phase 3's XCUT-02. See osag_plog.FINDINGS.md
-- for the full list of what this deliberately does NOT do, and the exact contract
-- XCUT-02 must replace it with.
--
-- Names copied verbatim from migration/mapping/name-map.csv (the 13 OSAG_PLOG rows).
-- 12 of the 13 are implemented here; osag_plog_auditusage is deliberately absent
-- (XCUT-06 -- see FINDINGS.md).
--
-- THE SINGLE MOST IMPORTANT CONSTRAINT ON THIS FILE: none of these routines may perform
-- transaction control (COMMIT/ROLLBACK). The Oracle original's Log() and AuditUsage()
-- both run as PRAGMA AUTONOMOUS_TRANSACTION with an explicit COMMIT (see FINDINGS.md for
-- the exact line numbers) precisely so a log write survives the caller's rollback.
-- PostgreSQL has no autonomous transaction equivalent, and a PostgreSQL PROCEDURE that
-- COMMITs cannot be CALLed from inside a FUNCTION body -- every pilot package calls plog
-- from inside routines that may well be translated as FUNCTIONs (pg_kind is still
-- provisional per 02-CONTEXT.md). A COMMIT here would poison the entire pilot at runtime
-- with an error that looks like an unrelated translation bug. So: no COMMIT, no
-- ROLLBACK, anywhere below. The log row rides in the caller's own transaction and is
-- lost on rollback -- a real, deliberate limitation, not an oversight (FINDINGS.md).

CREATE TABLE IF NOT EXISTS osag.plog_stub_log (
    id        bigserial PRIMARY KEY,
    ts        timestamptz NOT NULL DEFAULT clock_timestamp(),
    loglevel  int NOT NULL,
    levelname text,
    caller    text,
    message   text
);

COMMENT ON TABLE osag.plog_stub_log IS
    'Phase 2 plog STUB observable log. Rows live in the caller''s own transaction and are '
    'lost on ROLLBACK -- see migration/pgsql/osag/osag_plog.FINDINGS.md. Replaced by the '
    'Phase 3 (XCUT-02) UDP shipper, which does not use this table.';

-- ----------------------------------------------------------------------------
-- PUBLIC Type Conversions
-- Levels and names copied verbatim from the Oracle body's LevelAsString/LevelAsNum
-- (ddl/src/pkgb/osag_osag_plog.sql lines 72-100) -- syslog-shaped 0..7, EMERG..DEBUG.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION osag.osag_plog_levelasstring(loglevel int)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
AS $fn$
BEGIN
    RETURN CASE loglevel
        WHEN 0 THEN 'EMERG'
        WHEN 1 THEN 'ALERT'
        WHEN 2 THEN 'CRIT'
        WHEN 3 THEN 'ERR'
        WHEN 4 THEN 'WARNING'
        WHEN 5 THEN 'NOTICE'
        WHEN 6 THEN 'INFO'
        WHEN 7 THEN 'DEBUG'
        ELSE NULL
    END;
END;
$fn$;

CREATE OR REPLACE FUNCTION osag.osag_plog_levelasnum(loglevel text)
RETURNS int
LANGUAGE plpgsql
IMMUTABLE
AS $fn$
BEGIN
    RETURN CASE upper(loglevel)
        WHEN 'EMERG' THEN 0
        WHEN 'ALERT' THEN 1
        WHEN 'CRIT' THEN 2
        WHEN 'ERR' THEN 3
        WHEN 'WARNING' THEN 4
        WHEN 'NOTICE' THEN 5
        WHEN 'INFO' THEN 6
        WHEN 'DEBUG' THEN 7
        ELSE NULL
    END;
END;
$fn$;

-- ----------------------------------------------------------------------------
-- PUBLIC Generic Logging Procedure
-- Oracle's Log() ran PublishToMCDBQueue (an AQ enqueue -- not ported, see FINDINGS.md)
-- inside an autonomous transaction with COMMIT, and resolved the calling procedure name
-- via who_called_my_caller() (a private helper that walks dbms_utility.format_call_stack
-- string output -- also not ported; there is no direct PostgreSQL equivalent, and
-- reconstructing one is explicitly out of scope for a throwaway stub). `caller` is left
-- NULL by this procedure; FINDINGS.md records this as a known stub limitation. Inserts
-- the observable row and emits RAISE NOTICE for humans. No transaction control (see
-- file header).
-- ----------------------------------------------------------------------------

CREATE OR REPLACE PROCEDURE osag.osag_plog_log(loglevel int, message text)
LANGUAGE plpgsql
AS $fn$
DECLARE
    v_levelname text := osag.osag_plog_levelasstring(loglevel);
BEGIN
    INSERT INTO osag.plog_stub_log (loglevel, levelname, caller, message)
    VALUES (loglevel, v_levelname, NULL, message);
    RAISE NOTICE '[plog stub %] %', coalesce(v_levelname, loglevel::text), message;
END;
$fn$;

-- LogRaw does not filter by level, does not modify the message, and does not determine
-- the caller (ddl/src/pkg/osag_osag_plog.sql lines 37-38, verbatim). Unlike Oracle's
-- LogRaw, which calls PublishToMCDBQueue directly (skipping Log()'s autonomous
-- transaction and caller resolution but NOT skipping the enqueue), this stub still
-- writes the same observable row -- there is no queue here to skip, and the pilot's
-- tests need LogRaw's output to be observable too.
CREATE OR REPLACE PROCEDURE osag.osag_plog_lograw(loglevel int, message text)
LANGUAGE plpgsql
AS $fn$
BEGIN
    INSERT INTO osag.plog_stub_log (loglevel, levelname, caller, message)
    VALUES (loglevel, NULL, NULL, message);
    RAISE NOTICE '[plog stub RAW %] %', loglevel, message;
END;
$fn$;

-- ----------------------------------------------------------------------------
-- PUBLIC Logging Procedures (level == procedure name)
-- ----------------------------------------------------------------------------

CREATE OR REPLACE PROCEDURE osag.osag_plog_emerg(message text)
LANGUAGE plpgsql AS $fn$ BEGIN CALL osag.osag_plog_log(0, message); END; $fn$;

CREATE OR REPLACE PROCEDURE osag.osag_plog_alert(message text)
LANGUAGE plpgsql AS $fn$ BEGIN CALL osag.osag_plog_log(1, message); END; $fn$;

CREATE OR REPLACE PROCEDURE osag.osag_plog_crit(message text)
LANGUAGE plpgsql AS $fn$ BEGIN CALL osag.osag_plog_log(2, message); END; $fn$;

CREATE OR REPLACE PROCEDURE osag.osag_plog_err(message text)
LANGUAGE plpgsql AS $fn$ BEGIN CALL osag.osag_plog_log(3, message); END; $fn$;

CREATE OR REPLACE PROCEDURE osag.osag_plog_warning(message text)
LANGUAGE plpgsql AS $fn$ BEGIN CALL osag.osag_plog_log(4, message); END; $fn$;

CREATE OR REPLACE PROCEDURE osag.osag_plog_notice(message text)
LANGUAGE plpgsql AS $fn$ BEGIN CALL osag.osag_plog_log(5, message); END; $fn$;

CREATE OR REPLACE PROCEDURE osag.osag_plog_info(message text)
LANGUAGE plpgsql AS $fn$ BEGIN CALL osag.osag_plog_log(6, message); END; $fn$;

CREATE OR REPLACE PROCEDURE osag.osag_plog_debug(message text)
LANGUAGE plpgsql AS $fn$ BEGIN CALL osag.osag_plog_log(7, message); END; $fn$;

-- osag_plog_auditusage is DELIBERATELY NOT CREATED. See osag_plog.FINDINGS.md and
-- XCUT-06 / PITFALLS.md Pitfall 4.3: the feature is unused (write-only -- nothing reads
-- osag.plsql_audit) and gets DELETED, not ported. Pilot translations delete their
-- AuditUsage call sites and record how many in their own spec/FINDINGS docs.
