-- migration/pgsql/mss/osag_ip.sql
--
-- Translation of MSS.OSAG_IP (spec: migration/spec/mss.osag_ip.md; Oracle body:
-- ddl/src/pkgb/mss_osag_ip.sql, 323 lines). The 7 public names are copied verbatim from
-- migration/mapping/name-map.csv's 7 OSAG_IP rows; the 2 body-private helpers follow the
-- double-underscore private-routine convention (mss.osag_ip__<name>, REVOKE ALL FROM
-- PUBLIC) declared in migration/spec/tt.osag_notify.md and used by every pilot package.
--
-- Pure functions. Every public routine is DETERMINISTIC in Oracle and touches no table,
-- so all nine functions here are IMMUTABLE (S-IP-024). Oracle's ip2num/num2ip call
-- plog.debug on their invalid-input paths (body lines 62, 77, 87, 91, 120, 128, 136);
-- a table write inside an IMMUTABLE function is not acceptable, and DETERMINISTIC never
-- promised a side effect. Those calls are DROPPED -- the observable contract (NULL
-- return) is unchanged. No AuditUsage site exists in this package (0 deleted).
--
-- Types: NUMBER -> numeric throughout. The IPv6 halves are unsigned 64-bit quantities
-- (Oracle INTEGER = NUMBER(38)); 2^64-1 does not fit bigint, so ipv6left/ipv6right return
-- numeric and num2ipv6 takes numeric (S-IP-018). VARCHAR2 -> varchar.
--
-- Deviations from Oracle are marked at the site with `-- DEVIATION(...)` and listed in
-- osag_ip.FINDINGS.md. Summary: four ORACLE-BUG corrections (ip2num raises on a
-- non-numeric byte / yields a fraction for >3 dots; num2ip yields '0.0.0.1.5' for a
-- fraction; IPv6 parsing/formatting of malformed, NULL or out-of-range input yields
-- partial values, '::' for NULL, or raises) -- all corrected to "return NULL" -- and one
-- PLATFORM deviation (the dropped debug logging above).

-- ------------------------------------------------------------------------------------
-- getbcast (S-IP-001): ((TRUNC(ip / 2^(32-mask)) + 1) * 2^(32-mask)) - 1.
-- trim_scale() only strips the trailing zeros numeric power() leaves behind
-- (256.0000 -> 256); the value is unchanged.
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION mss.osag_ip_getbcast(p_ip numeric, p_mask numeric)
RETURNS numeric
LANGUAGE plpgsql
IMMUTABLE
AS $fn$
DECLARE
    v_maskrange numeric := 0;
BEGIN
    v_maskrange := power(2::numeric, 32 - p_mask);
    RETURN trim_scale(((trunc(p_ip / v_maskrange, 0) + 1) * v_maskrange) - 1);
END;
$fn$;

-- ------------------------------------------------------------------------------------
-- getnet (S-IP-002): ip - MOD(ip, 2^(32-mask)).
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION mss.osag_ip_getnet(p_ip numeric, p_mask numeric)
RETURNS numeric
LANGUAGE plpgsql
IMMUTABLE
AS $fn$
DECLARE
    v_maskrange numeric := 0;
    v_offset    numeric := 0;
BEGIN
    v_maskrange := power(2::numeric, 32 - p_mask);
    v_offset := mod(p_ip, v_maskrange);
    RETURN trim_scale(p_ip - v_offset);
END;
$fn$;

-- ------------------------------------------------------------------------------------
-- ip2num (S-IP-003..010, S-IP-024): dotted quad -> A*2^24 + B*2^16 + C*2^8 + D.
--
-- Oracle walks the string with INSTR/SUBSTR (body lines 55-98). The same contract is
-- expressed here by splitting on '.' and validating each byte: exactly four bytes
-- (S-IP-005 fewer dots -> NULL; S-IP-009 more dots -> NULL), each the canonical decimal
-- rendering of its value (S-IP-006: Oracle's TO_CHAR(TO_NUMBER(b)) != b rejects leading
-- zeros, signs and whitespace; S-IP-010: an empty byte is NULL in Oracle), each <= 255
-- (S-IP-007). NULL and '' -> NULL (S-IP-003; Oracle collapses the two).
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION mss.osag_ip_ip2num(p_string varchar)
RETURNS numeric
LANGUAGE plpgsql
IMMUTABLE
AS $fn$
DECLARE
    v_bytes  text[];
    v_byte   text;
    v_result numeric := 0;
BEGIN
    IF p_string IS NULL OR p_string = '' THEN
        RETURN NULL;
    END IF;

    v_bytes := string_to_array(p_string, '.');

    -- S-IP-005 (not enough dots -> NULL; Oracle: INSTR returns 0, start < 2, RETURN NULL).
    -- DEVIATION(ORACLE-BUG) S-IP-009: more than three dots -> NULL. Oracle (body line 74)
    -- took everything after the THIRD dot as the fourth byte, so '1.2.3.4.5' parsed the
    -- byte '4.5', passed TO_CHAR(TO_NUMBER('4.5')) = '4.5' at line 86, and returned the
    -- fractional 16909060.5.
    IF array_length(v_bytes, 1) IS DISTINCT FROM 4 THEN
        -- Oracle: plog.debug(c_prefix||'not enough dots in ip address [pos1]: '||p_string)
        -- DEVIATION(PLATFORM) S-IP-024: debug logging dropped (IMMUTABLE, no side effects).
        RETURN NULL;
    END IF;

    FOREACH v_byte IN ARRAY v_bytes LOOP
        -- S-IP-006 / S-IP-010: the byte must be the canonical decimal rendering of a
        -- non-negative integer -- Oracle's TO_CHAR(TO_NUMBER(b)) != b -> RETURN NULL
        -- (body line 86-89); an empty byte was NULL in Oracle and propagated to a NULL
        -- result (line 84/97).
        -- DEVIATION(ORACLE-BUG) S-IP-008: Oracle evaluated TO_NUMBER(b) BEFORE the
        -- comparison, so a non-numeric byte ('1.a.3.4') raised ORA-06502 instead of
        -- reaching the RETURN NULL the check intends. Corrected: any non-digit -> NULL.
        IF v_byte !~ '^(0|[1-9][0-9]*)$' THEN
            -- Oracle: plog.debug(c_prefix||'invalid byte 1 in ip address: '||p_string)
            -- DEVIATION(PLATFORM) S-IP-024: debug logging dropped.
            RETURN NULL;
        END IF;
        -- S-IP-007 (body lines 90-93)
        IF v_byte::numeric > 255 THEN
            -- Oracle: plog.debug(c_prefix||'number too big in byte '||...)
            -- DEVIATION(PLATFORM) S-IP-024: debug logging dropped.
            RETURN NULL;
        END IF;
        v_result := v_result * 256 + v_byte::numeric;        -- body line 97
    END LOOP;

    RETURN v_result;
END;
$fn$;

-- ------------------------------------------------------------------------------------
-- num2ip (S-IP-011..014, S-IP-024): 32-bit integer -> dotted quad.
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION mss.osag_ip_num2ip(p_number numeric)
RETURNS varchar
LANGUAGE plpgsql
IMMUTABLE
AS $fn$
DECLARE
    v_number   numeric;
    v_byte     numeric := NULL;
    v_reminder numeric := NULL;
    v_result   varchar(15) := NULL;
BEGIN
    -- S-IP-011 (body lines 115-117)
    IF p_number IS NULL OR p_number < 0 THEN
        RETURN NULL;
    END IF;

    -- DEVIATION(ORACLE-BUG) S-IP-014: a fractional input is not an IPv4 address. Oracle
    -- carried the fraction through every TRUNC into the last byte (body line 140) and
    -- returned '0.0.0.1.5' for 1.5. Corrected: NULL, consistent with lines 115-122.
    IF p_number <> trunc(p_number) THEN
        RETURN NULL;
    END IF;
    v_number := trim_scale(p_number);   -- 1.0 -> 1, so the last byte renders as '1' not '1.0'

    -- S-IP-012 (body lines 118-122): first byte > 255 <=> x >= 2^32.
    v_byte := trunc(v_number / 16777216);
    IF v_byte > 255 THEN
        -- Oracle: plog.debug(c_prefix||'invalid byte 1 in ip address: '||v_byte)
        -- DEVIATION(PLATFORM) S-IP-024: debug logging dropped.
        RETURN NULL;
    END IF;
    v_reminder := v_number - v_byte * 16777216;
    v_result := v_byte::text;

    -- S-IP-013 (body lines 126-141). Oracle's > 255 checks for bytes 2 and 3 (lines
    -- 127-130, 135-138) are unreachable -- each remainder is already below the next
    -- divisor -- and are kept only as a comment, not as code.
    v_byte := trunc(v_reminder / 65536);
    v_reminder := v_reminder - v_byte * 65536;
    v_result := v_result || '.' || v_byte::text;

    v_byte := trunc(v_reminder / 256);
    v_reminder := v_reminder - v_byte * 256;
    v_result := v_result || '.' || v_byte::text || '.' || v_reminder::text;
    RETURN v_result;
END;
$fn$;

-- ------------------------------------------------------------------------------------
-- PRIVATE ipv6pad0 (S-IP-016, S-IP-019): expands '::' to the full 8-group form.
-- Statement-for-statement port of body lines 147-189 (INSTR -> position, same LPAD
-- padding trick, same leading/trailing-colon trim). NULL/'' -> NULL (Oracle: every
-- INSTR/LENGTH/REPLACE on NULL is NULL and no branch fires; PostgreSQL needs the guard
-- explicitly because '' is not NULL here).
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION mss.osag_ip__ipv6pad0(p_ip varchar)
RETURNS varchar
LANGUAGE plpgsql
IMMUTABLE
AS $fn$
DECLARE
    v_colons_pos integer;
    v_groups     integer;
    v_pad        varchar(64);
    v_res        varchar(64);
BEGIN
    IF p_ip IS NULL OR p_ip = '' THEN
        RETURN NULL;
    END IF;

    v_colons_pos := position('::' in p_ip);
    IF v_colons_pos = 0 THEN
        RETURN p_ip;
    END IF;
    IF p_ip = '::' THEN
        RETURN '0:0:0:0:0:0:0:0';
    END IF;

    -- number of colons in the IP equals the number of 16 bit groups present
    v_groups := length(p_ip) - coalesce(length(replace(p_ip, ':', '')), 0);

    -- except if :: is at the beginning or at the end
    IF v_colons_pos = 1 OR v_colons_pos = length(p_ip) - 1 THEN
        v_groups := v_groups - 1;
    END IF;

    IF v_groups >= 8 THEN
        -- already complete, for example 1:1:1:1::1:1:1:1 -- tolerated although invalid
        -- per RFC 5952 (:: must stand for at least one zero group)
        RETURN replace(p_ip, '::', ':');
    END IF;

    -- the padding like :0:0:0:
    v_pad := lpad(':0', 2 * (8 - v_groups), ':0') || ':';
    v_res := replace(p_ip, '::', v_pad);

    -- remove extra : from begin/end
    IF v_res LIKE ':%' THEN
        v_res := substr(v_res, 2);
    END IF;
    IF v_res LIKE '%:' THEN
        v_res := substr(v_res, 1, length(v_res) - 1);
    END IF;
    RETURN v_res;
END;
$fn$;

REVOKE ALL ON FUNCTION mss.osag_ip__ipv6pad0(varchar) FROM PUBLIC;

-- ------------------------------------------------------------------------------------
-- ipv6left / ipv6right (S-IP-015..020): 64 most / least significant bits.
--
-- Oracle walks the padded string with INSTR and parses each group with
-- TO_NUMBER(grp, 'xxxx') (body lines 204-211, 229-239). Here the padded string is split
-- on ':' and each group is parsed as hex via a 16-bit bit-string literal
-- (('x' || lpad(grp, 4, '0'))::bit(16)::int -- case-insensitive, 1-4 digits, S-IP-017).
--
-- DEVIATION(ORACLE-BUG) S-IP-020: Oracle's handling of malformed input was inconsistent
-- -- a non-hex or 5+ digit group raised ORA-01722 unhandled, an address with fewer than
-- eight groups and no '::' made ipv6left return a PARTIAL value while ipv6right returned
-- NULL (negative-length SUBSTR). Corrected: anything that does not expand to exactly
-- eight groups of 1-4 hex digits returns NULL from BOTH routines, never raises.
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION mss.osag_ip_ipv6left(p_ip varchar)
RETURNS numeric
LANGUAGE plpgsql
IMMUTABLE
AS $fn$
DECLARE
    v_ip   varchar(64);
    v_grps text[];
    v_grp  text;
    v_left numeric := 0;
BEGIN
    v_ip := mss.osag_ip__ipv6pad0(p_ip);
    IF v_ip IS NULL THEN
        RETURN NULL;                                        -- S-IP-019
    END IF;
    v_grps := string_to_array(v_ip, ':');
    IF array_length(v_grps, 1) IS DISTINCT FROM 8 THEN
        RETURN NULL;                                        -- DEVIATION(ORACLE-BUG) S-IP-020
    END IF;

    -- 4 hex groups of 1-4 digits (16 bits), most significant first
    FOR v_i IN 1..4 LOOP
        v_grp := v_grps[v_i];
        IF v_grp !~ '^[0-9A-Fa-f]{1,4}$' THEN
            RETURN NULL;                                    -- DEVIATION(ORACLE-BUG) S-IP-020
        END IF;
        -- shift left by 16 bits, add the group
        v_left := v_left * 65536 + (('x' || lpad(v_grp, 4, '0'))::bit(16)::int);
    END LOOP;

    RETURN v_left;
END;
$fn$;

CREATE OR REPLACE FUNCTION mss.osag_ip_ipv6right(p_ip varchar)
RETURNS numeric
LANGUAGE plpgsql
IMMUTABLE
AS $fn$
DECLARE
    v_ip    varchar(64);
    v_grps  text[];
    v_grp   text;
    v_right numeric := 0;
BEGIN
    v_ip := mss.osag_ip__ipv6pad0(p_ip);
    IF v_ip IS NULL THEN
        RETURN NULL;                                        -- S-IP-019
    END IF;
    v_grps := string_to_array(v_ip, ':');
    IF array_length(v_grps, 1) IS DISTINCT FROM 8 THEN
        RETURN NULL;                                        -- DEVIATION(ORACLE-BUG) S-IP-020
    END IF;

    -- 4 hex groups of 1-4 digits (16 bits), groups 5..8
    FOR v_i IN 5..8 LOOP
        v_grp := v_grps[v_i];
        IF v_grp !~ '^[0-9A-Fa-f]{1,4}$' THEN
            RETURN NULL;                                    -- DEVIATION(ORACLE-BUG) S-IP-020
        END IF;
        v_right := v_right * 65536 + (('x' || lpad(v_grp, 4, '0'))::bit(16)::int);
    END LOOP;

    RETURN v_right;
END;
$fn$;

-- ------------------------------------------------------------------------------------
-- PRIVATE ipv6shorten (S-IP-022): collapses the longest run of zero groups with '::'.
-- Statement-for-statement port of body lines 245-293, including the quirk the spec
-- records: the scan starts only at a colon, so the FIRST group never counts towards a
-- run -- a leading run of exactly two zero groups is left uncollapsed ('0:0:1:...'),
-- a leading run of three or more is collapsed and its surviving '0' stripped by the
-- '0::%' rule at the end. Valid (if non-canonical) output; deliberately NOT corrected.
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION mss.osag_ip__ipv6shorten(p_ip varchar)
RETURNS varchar
LANGUAGE plpgsql
IMMUTABLE
AS $fn$
DECLARE
    v_start integer := 255;
    v_end   integer := 255;
    v_j     integer;
    v_len   integer;
    v_ip    varchar(64);
    v_res   varchar(64);
BEGIN
    v_ip := p_ip || ':';   -- adding trailing colon simplifies processing below
    FOR v_i IN 1..(length(v_ip) - 1) LOOP
        -- ensure v_i is aligned to a colon
        IF substr(v_ip, v_i, 1) <> ':' THEN
            CONTINUE;
        END IF;
        v_j := v_i + 1;
        WHILE v_j < length(v_ip) AND (substr(v_ip, v_j, 1) = '0' OR substr(v_ip, v_j, 1) = ':') LOOP
            v_j := v_j + 1;
        END LOOP;
        -- ensure v_j is aligned to a colon
        WHILE v_j >= v_i AND substr(v_ip, v_j, 1) <> ':' LOOP
            v_j := v_j - 1;
        END LOOP;
        v_len := v_j - v_i;
        IF v_len > 3 AND v_len > (v_end - v_start) THEN
            v_start := v_i;
            v_end := v_j;
        END IF;
    END LOOP;

    v_res := v_ip;
    IF (v_end - v_start) > 0 THEN
        v_res := substr(v_ip, 1, v_start) || substr(v_ip, v_end);
    END IF;

    -- remove trailing extra colon
    IF v_res LIKE '%:' AND v_res NOT LIKE '%::' THEN
        v_res := substr(v_res, 1, length(v_res) - 1);
    END IF;

    -- remove leading 0 from '0::...'
    IF v_res LIKE '0::%' THEN
        v_res := substr(v_res, 2);
    END IF;

    RETURN v_res;
END;
$fn$;

REVOKE ALL ON FUNCTION mss.osag_ip__ipv6shorten(varchar) FROM PUBLIC;

-- ------------------------------------------------------------------------------------
-- num2ipv6 (S-IP-021..023): two 64-bit halves -> compressed lowercase IPv6 string.
-- Oracle renders each group with TRIM(TO_CHAR(grp, 'xxxx')) (body lines 307, 314);
-- to_hex(bigint) is the same rendering (lowercase, no padding).
--
-- DEVIATION(ORACLE-BUG) S-IP-023: Oracle accepted anything -- NULL halves concatenated
-- as '' (num2ipv6(NULL, NULL) = '::', indistinguishable from a real zero address),
-- negative/fractional halves rendered as '####' overflow markers by TO_CHAR, and halves
-- >= 2^64 silently lost their high bits in the four-iteration loop. Corrected: both
-- halves must be integers in 0 .. 2^64-1, otherwise NULL; never raises.
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION mss.osag_ip_num2ipv6(p_left numeric, p_right numeric)
RETURNS varchar
LANGUAGE plpgsql
IMMUTABLE
AS $fn$
DECLARE
    v_n   numeric;
    v_grp numeric;
    v_res varchar(64) := '';
BEGIN
    IF p_left IS NULL OR p_right IS NULL
       OR p_left < 0 OR p_right < 0
       OR p_left <> trunc(p_left) OR p_right <> trunc(p_right)
       OR p_left > 18446744073709551615 OR p_right > 18446744073709551615 THEN
        RETURN NULL;                                        -- DEVIATION(ORACLE-BUG) S-IP-023
    END IF;

    v_n := p_right;
    FOR v_i IN 1..4 LOOP
        v_grp := mod(v_n, 65536);
        v_n := div(v_n, 65536);                             -- (v_n - v_grp) / 65536, exact
        v_res := to_hex(v_grp::bigint) || ':' || v_res;
    END LOOP;

    v_n := p_left;
    FOR v_i IN 1..4 LOOP
        v_grp := mod(v_n, 65536);
        v_n := div(v_n, 65536);
        v_res := to_hex(v_grp::bigint) || ':' || v_res;
    END LOOP;

    -- this left us with an extra colon at the end
    v_res := substr(v_res, 1, length(v_res) - 1);
    v_res := mss.osag_ip__ipv6shorten(v_res);
    RETURN v_res;
END;
$fn$;
