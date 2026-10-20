-- migration/pgsql/mss/osag_dbprop.sql
--
-- Translation of MSS.OSAG_DBPROP (spec: migration/spec/mss.osag_dbprop.md; Oracle body:
-- ddl/src/pkgb/mss_osag_dbprop.sql, 90 lines). Names copied verbatim from
-- migration/mapping/name-map.csv's 3 OSAG_DBPROP rows.
--
-- Oracle's usage-audit call (package-state tracking, XCUT-06): all 3 call sites DELETED,
-- not ported -- the feature is unused, ~177 corpus-wide sites; the audit table it wrote
-- is write-only. Count for this package: 3 (one per routine). See osag_dbprop.FINDINGS.md.
--
-- Parameter types: i_host_id is declared `integer` (not bigint/numeric) specifically so
-- that get_string_by_host's error CONTEXT line matches the pinned golden file
-- (migration/test/regress/expected/mss__osag_dbprop__errors.out --
-- "PL/pgSQL function mss.osag_dbprop_get_string_by_host(integer,character varying)").
-- i_property_name is `varchar` (unconstrained), matching that same golden signature
-- ("character varying"). See FINDINGS.md for the full formatting-parity note.

-- ------------------------------------------------------------------------------------
-- get_string_by_host_key_id (S-DBPROP-003/004/005): cursor FOR loop over
-- mss.v_host_key_value/mss.key, NOT a SELECT INTO -- zero matches is a normal, silent
-- no-op (NULL result), never NO_DATA_FOUND. Duplicate-agree -> plog.warning + return
-- common value. Duplicate-disagree -> plog.err + return first-seen value, keep looping.
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION mss.osag_dbprop_get_string_by_host_key_id(i_host_id integer, i_property_key_id integer)
RETURNS varchar
LANGUAGE plpgsql
AS $fn$
DECLARE
    c_prefix CONSTANT text := 'OSAG_DBPROP.get_string_by_host_key_id(): ';
    l_string mss.value.string_value%TYPE := NULL;
    r RECORD;
BEGIN
    FOR r IN
        SELECT hkv.key_name, hkv.scope, hkv.string_value
        FROM mss.v_host_key_value hkv
        JOIN mss.key k ON k.id = i_property_key_id AND hkv.key_name = k.name
        WHERE hkv.host_id = i_host_id
    LOOP
        IF l_string IS NULL THEN
            l_string := r.string_value;
        ELSIF l_string = r.string_value THEN
            CALL osag.osag_plog_warning(c_prefix || 'dbprop ' || r.key_name
                || ' for host_id=' || i_host_id || ', scope=' || r.scope
                || ' has multiple but consistent values: ' || l_string);
        ELSE
            CALL osag.osag_plog_err(c_prefix || 'dbprop ' || r.key_name
                || ' for host_id=' || i_host_id || ', scope=' || r.scope
                || ' has multiple inconsistently values: ' || l_string || ' vs. ' || r.string_value);
        END IF;
    END LOOP;

    RETURN l_string;
END;
$fn$;

-- ------------------------------------------------------------------------------------
-- get_number_by_host (S-DBPROP-001/002): SELECT ... INTO ... FROM DUAL is structurally
-- safe (always exactly one row) -- STRICT with no handler, matching the spec's verdict.
-- Collapses the underlying string to 1 (exact '1') or 0 (anything else, including NULL
-- -- IF l_string = '1' is unknown/false when l_string is NULL, so this falls through to
-- the ELSE branch for free, with no explicit NULL check needed).
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION mss.osag_dbprop_get_number_by_host(i_host_id integer, i_property_name varchar)
RETURNS numeric
LANGUAGE plpgsql
AS $fn$
DECLARE
    l_string mss.value.string_value%TYPE;
BEGIN
    SELECT mss.osag_dbprop_get_string_by_host(i_host_id, i_property_name) INTO STRICT l_string;
    IF l_string = '1' THEN
        RETURN 1;
    ELSE
        RETURN 0;
    END IF;
END;
$fn$;

-- ------------------------------------------------------------------------------------
-- get_string_by_host (S-DBPROP-006/007/008/009): resolves i_property_name to a
-- mss.key.id via a SELECT INTO STRICT with a NO_DATA_FOUND handler (unique index
-- u_key_name on mss.key.name makes TOO_MANY_ROWS structurally impossible -- no handler
-- needed for that arm). S-DBPROP-009: Oracle collapses '' and NULL for this comparison;
-- NULLIF(i_property_name, '') reproduces that collapse explicitly, since PostgreSQL does
-- not do it implicitly (Pitfall 2).
--
-- The NO_DATA_FOUND arm's `RAISE EXCEPTION` is deliberately placed on the SAME physical
-- source line as the function's own EXCEPTION/SELECT/BEGIN prelude (see the single long
-- line below) -- NOT a style choice, but the only way to reproduce the exact
-- "line 1 at RAISE" PL/pgSQL CONTEXT line pinned in the locked golden file
-- migration/test/regress/expected/mss__osag_dbprop__errors.out. PL/pgSQL's CONTEXT line
-- counter counts physical newlines inside the dollar-quoted body; verified empirically
-- against a live PostgreSQL 17.10 instance before committing this shape. See
-- osag_dbprop.FINDINGS.md for the full note (this is a formatting-parity decision, not a
-- behavioral one -- the WHEN OTHERS arm below it needed no such constraint and keeps
-- normal multi-line formatting).
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION mss.osag_dbprop_get_string_by_host(i_host_id integer, i_property_name varchar)
RETURNS varchar
LANGUAGE plpgsql
AS $fn$ DECLARE v_key_id integer; v_property_name varchar := NULLIF(i_property_name, ''); BEGIN BEGIN SELECT id INTO STRICT v_key_id FROM mss.key WHERE name = v_property_name; EXCEPTION WHEN NO_DATA_FOUND THEN CALL osag.osag_plog_err('OSAG_DBPROP.get_string_by_host(): unknown db property ' || coalesce(i_property_name, '')); RAISE EXCEPTION 'unknown db property ''%''', coalesce(i_property_name, '') USING ERRCODE = 'OS801'; /* -20801 -> OS801, migration/mapping/sqlstate-map.md */
    WHEN OTHERS THEN
        CALL osag.osag_plog_err('OSAG_DBPROP.get_string_by_host(): unexpected error while fetching key id for db property ' || coalesce(i_property_name, '') || ': ' || SQLERRM);
        RAISE;
    END;

    RETURN mss.osag_dbprop_get_string_by_host_key_id(i_host_id, v_key_id);
END;
$fn$;
