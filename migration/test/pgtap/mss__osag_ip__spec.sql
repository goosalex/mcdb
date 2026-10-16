-- migration/test/pgtap/mss__osag_ip__spec.sql
--
-- pgTAP verification for migration/spec/mss.osag_ip.md. RED by construction: none of
-- mss.osag_ip_* exists when this file is first committed (the translation lands in a
-- later commit; provenance_lint.sh enforces the order). Every assertion's description
-- starts with the spec clause ID it verifies (HARN-05, trace_lint.py).
--
-- The 17 golden cases under S-IP-015 and S-IP-021 are copied verbatim from Oracle's own
-- unit-test package ddl/src/pkgb/mss_osag_ip_test.sql (test_ipv62nums lines 78-112,
-- test_num2ipv6 lines 17-47). Expected literals are cast to the live return type
-- (numeric for every numeric-returning routine -- IPv6 halves exceed bigint, S-IP-018).
--
-- Clauses marked CORRECTED in the spec (S-IP-008/009/014/020/023) assert the corrected
-- behaviour (NULL, no exception), not Oracle's defective one; each such group starts
-- with a lives_ok so a regression to "raises" is reported as its own failure instead of
-- aborting the transaction and cascading through every later assertion.

BEGIN;

SELECT plan(104);

-- ---------------------------------------------------------------------------------
-- S-IP-001: getbcast
-- ---------------------------------------------------------------------------------
SELECT is(mss.osag_ip_getbcast(mss.osag_ip_ip2num('10.1.2.3'), 24), 167838463::numeric,
    'S-IP-001: getbcast(ip2num(''10.1.2.3''), 24) is ip2num(''10.1.2.255'') = 167838463');
SELECT is(mss.osag_ip_getbcast(167838211, 32), 167838211::numeric,
    'S-IP-001: getbcast(x, 32) is x itself (a /32 network is a single host)');
SELECT is(mss.osag_ip_getbcast(167838211, 0), 4294967295::numeric,
    'S-IP-001: getbcast(x, 0) is 4294967295 for any x below 2^32');
SELECT is(mss.osag_ip_getbcast(NULL, 24), NULL::numeric,
    'S-IP-001: getbcast(NULL, 24) is NULL (plain NULL arithmetic, no exception)');

-- ---------------------------------------------------------------------------------
-- S-IP-002: getnet
-- ---------------------------------------------------------------------------------
SELECT is(mss.osag_ip_getnet(mss.osag_ip_ip2num('10.1.2.3'), 24), 167838208::numeric,
    'S-IP-002: getnet(ip2num(''10.1.2.3''), 24) is ip2num(''10.1.2.0'') = 167838208');
SELECT is(mss.osag_ip_getnet(167838211, 32), 167838211::numeric,
    'S-IP-002: getnet(x, 32) is x itself');
SELECT is(mss.osag_ip_getnet(167838211, 0), 0::numeric,
    'S-IP-002: getnet(x, 0) is 0 for any x below 2^32');
SELECT is(mss.osag_ip_getnet(167838211, NULL), NULL::numeric,
    'S-IP-002: getnet(x, NULL) is NULL (plain NULL arithmetic, no exception)');

-- ---------------------------------------------------------------------------------
-- S-IP-003: ip2num NULL / '' guard
-- ---------------------------------------------------------------------------------
SELECT is(mss.osag_ip_ip2num(NULL), NULL::numeric,
    'S-IP-003: ip2num(NULL) is NULL');
SELECT is(mss.osag_ip_ip2num(''), NULL::numeric,
    'S-IP-003: ip2num('''') is NULL (Oracle ''''/NULL collapsing)');

-- ---------------------------------------------------------------------------------
-- S-IP-004: ip2num well-formed dotted quads
-- ---------------------------------------------------------------------------------
SELECT is(mss.osag_ip_ip2num('10.0.0.1'), 167772161::numeric,
    'S-IP-004: ip2num(''10.0.0.1'') = 167772161');
SELECT is(mss.osag_ip_ip2num('0.0.0.0'), 0::numeric,
    'S-IP-004: ip2num(''0.0.0.0'') = 0');
SELECT is(mss.osag_ip_ip2num('255.255.255.255'), 4294967295::numeric,
    'S-IP-004: ip2num(''255.255.255.255'') = 4294967295');
SELECT is(mss.osag_ip_ip2num('192.168.1.1'), 3232235777::numeric,
    'S-IP-004: ip2num(''192.168.1.1'') = 3232235777');

-- ---------------------------------------------------------------------------------
-- S-IP-005: fewer than three dots
-- ---------------------------------------------------------------------------------
SELECT is(mss.osag_ip_ip2num('1.2.3'), NULL::numeric,
    'S-IP-005: ip2num(''1.2.3'') is NULL (not enough dots)');
SELECT is(mss.osag_ip_ip2num('1'), NULL::numeric,
    'S-IP-005: ip2num(''1'') is NULL (no dots at all)');
SELECT is(mss.osag_ip_ip2num('10.0.0'), NULL::numeric,
    'S-IP-005: ip2num(''10.0.0'') is NULL (only two dots)');

-- ---------------------------------------------------------------------------------
-- S-IP-006: non-canonical byte text
-- ---------------------------------------------------------------------------------
SELECT is(mss.osag_ip_ip2num('10.0.0.01'), NULL::numeric,
    'S-IP-006: ip2num(''10.0.0.01'') is NULL (leading zero in last byte)');
SELECT is(mss.osag_ip_ip2num('010.0.0.1'), NULL::numeric,
    'S-IP-006: ip2num(''010.0.0.1'') is NULL (leading zero in first byte)');
SELECT is(mss.osag_ip_ip2num('10.0.0.+1'), NULL::numeric,
    'S-IP-006: ip2num(''10.0.0.+1'') is NULL (explicit sign)');
SELECT is(mss.osag_ip_ip2num('10.0.0.1 '), NULL::numeric,
    'S-IP-006: ip2num(''10.0.0.1 '') is NULL (trailing whitespace)');

-- ---------------------------------------------------------------------------------
-- S-IP-007: byte > 255
-- ---------------------------------------------------------------------------------
SELECT is(mss.osag_ip_ip2num('1.2.3.256'), NULL::numeric,
    'S-IP-007: ip2num(''1.2.3.256'') is NULL (byte > 255)');
SELECT is(mss.osag_ip_ip2num('256.0.0.1'), NULL::numeric,
    'S-IP-007: ip2num(''256.0.0.1'') is NULL (first byte > 255)');
SELECT is(mss.osag_ip_ip2num('1.2.3.1000'), NULL::numeric,
    'S-IP-007: ip2num(''1.2.3.1000'') is NULL (four-digit byte)');

-- ---------------------------------------------------------------------------------
-- S-IP-008 (CORRECTED): non-numeric byte returns NULL, never raises
-- ---------------------------------------------------------------------------------
SELECT lives_ok($$SELECT mss.osag_ip_ip2num('1.a.3.4')$$,
    'S-IP-008: ip2num(''1.a.3.4'') does not raise (Oracle raised ORA-06502 here)');
SELECT is(mss.osag_ip_ip2num('1.a.3.4'), NULL::numeric,
    'S-IP-008: ip2num(''1.a.3.4'') is NULL');
SELECT is(mss.osag_ip_ip2num('a.b.c.d'), NULL::numeric,
    'S-IP-008: ip2num(''a.b.c.d'') is NULL');
SELECT is(mss.osag_ip_ip2num('10.0.0.1x'), NULL::numeric,
    'S-IP-008: ip2num(''10.0.0.1x'') is NULL');

-- ---------------------------------------------------------------------------------
-- S-IP-009 (CORRECTED): more than three dots returns NULL
-- ---------------------------------------------------------------------------------
SELECT is(mss.osag_ip_ip2num('1.2.3.4.5'), NULL::numeric,
    'S-IP-009: ip2num(''1.2.3.4.5'') is NULL (Oracle returned the fractional 16909060.5)');
SELECT is(mss.osag_ip_ip2num('10.0.0.1.'), NULL::numeric,
    'S-IP-009: ip2num(''10.0.0.1.'') is NULL (trailing dot)');

-- ---------------------------------------------------------------------------------
-- S-IP-010: empty byte returns NULL
-- ---------------------------------------------------------------------------------
SELECT is(mss.osag_ip_ip2num('1..3.4'), NULL::numeric,
    'S-IP-010: ip2num(''1..3.4'') is NULL (empty second byte)');
SELECT is(mss.osag_ip_ip2num('1.2.3.'), NULL::numeric,
    'S-IP-010: ip2num(''1.2.3.'') is NULL (empty fourth byte)');
SELECT is(mss.osag_ip_ip2num('.1.2.3'), NULL::numeric,
    'S-IP-010: ip2num(''.1.2.3'') is NULL (empty first byte)');

-- ---------------------------------------------------------------------------------
-- S-IP-011: num2ip NULL / negative guard
-- ---------------------------------------------------------------------------------
SELECT is(mss.osag_ip_num2ip(NULL), NULL::varchar,
    'S-IP-011: num2ip(NULL) is NULL');
SELECT is(mss.osag_ip_num2ip(-1), NULL::varchar,
    'S-IP-011: num2ip(-1) is NULL');

-- ---------------------------------------------------------------------------------
-- S-IP-012: num2ip upper bound
-- ---------------------------------------------------------------------------------
SELECT is(mss.osag_ip_num2ip(4294967296), NULL::varchar,
    'S-IP-012: num2ip(2^32) is NULL (first byte would be 256)');
SELECT is(mss.osag_ip_num2ip(4294967295), '255.255.255.255'::varchar,
    'S-IP-012: num2ip(2^32-1) = ''255.255.255.255''');

-- ---------------------------------------------------------------------------------
-- S-IP-013: num2ip formatting
-- ---------------------------------------------------------------------------------
SELECT is(mss.osag_ip_num2ip(0), '0.0.0.0'::varchar,
    'S-IP-013: num2ip(0) = ''0.0.0.0''');
SELECT is(mss.osag_ip_num2ip(167772161), '10.0.0.1'::varchar,
    'S-IP-013: num2ip(167772161) = ''10.0.0.1''');
SELECT is(mss.osag_ip_num2ip(3232235777), '192.168.1.1'::varchar,
    'S-IP-013: num2ip(3232235777) = ''192.168.1.1''');
SELECT is(mss.osag_ip_num2ip(mss.osag_ip_ip2num('172.16.254.1')), '172.16.254.1'::varchar,
    'S-IP-013: num2ip(ip2num(s)) round-trips a well-formed s');

-- ---------------------------------------------------------------------------------
-- S-IP-014 (CORRECTED): non-integer input returns NULL
-- ---------------------------------------------------------------------------------
SELECT lives_ok($$SELECT mss.osag_ip_num2ip(1.5)$$,
    'S-IP-014: num2ip(1.5) does not raise');
SELECT is(mss.osag_ip_num2ip(1.5), NULL::varchar,
    'S-IP-014: num2ip(1.5) is NULL (Oracle returned ''0.0.0.1.5'')');

-- ---------------------------------------------------------------------------------
-- S-IP-015: the nine golden ipv6left/ipv6right cases from MSS.OSAG_IP_TEST
-- ---------------------------------------------------------------------------------
SELECT is(mss.osag_ip_ipv6left('::'), 0::numeric,
    'S-IP-015: golden case 1 left: ipv6left(''::'') = 0');
SELECT is(mss.osag_ip_ipv6right('::'), 0::numeric,
    'S-IP-015: golden case 1 right: ipv6right(''::'') = 0');
SELECT is(mss.osag_ip_ipv6left('::1'), 0::numeric,
    'S-IP-015: golden case 2 left: ipv6left(''::1'') = 0');
SELECT is(mss.osag_ip_ipv6right('::1'), 1::numeric,
    'S-IP-015: golden case 2 right: ipv6right(''::1'') = 1');
SELECT is(mss.osag_ip_ipv6left('1::'), 281474976710656::numeric,
    'S-IP-015: golden case 3 left: ipv6left(''1::'') = 281474976710656');
SELECT is(mss.osag_ip_ipv6right('1::'), 0::numeric,
    'S-IP-015: golden case 3 right: ipv6right(''1::'') = 0');
SELECT is(mss.osag_ip_ipv6left('0:0:0:0:0:0:0001'), 0::numeric,
    'S-IP-015: golden case 4 left: ipv6left(''0:0:0:0:0:0:0001'') = 0');
SELECT is(mss.osag_ip_ipv6right('0:0:0:0:0:0:0001'), 1::numeric,
    'S-IP-015: golden case 4 right: ipv6right(''0:0:0:0:0:0:0001'') = 1');
SELECT is(mss.osag_ip_ipv6left('::1:2:3:4:5:6:7'), 4295098371::numeric,
    'S-IP-015: golden case 5 left: ipv6left(''::1:2:3:4:5:6:7'') = 4295098371');
SELECT is(mss.osag_ip_ipv6right('::1:2:3:4:5:6:7'), 1125921382072327::numeric,
    'S-IP-015: golden case 5 right: ipv6right(''::1:2:3:4:5:6:7'') = 1125921382072327');
SELECT is(mss.osag_ip_ipv6left('1:2:3:4:5:6:7::'), 281483566841860::numeric,
    'S-IP-015: golden case 6 left: ipv6left(''1:2:3:4:5:6:7::'') = 281483566841860');
SELECT is(mss.osag_ip_ipv6right('1:2:3:4:5:6:7::'), 1407400653815808::numeric,
    'S-IP-015: golden case 6 right: ipv6right(''1:2:3:4:5:6:7::'') = 1407400653815808');
SELECT is(mss.osag_ip_ipv6left('1:2::6:7'), 281483566645248::numeric,
    'S-IP-015: golden case 7 left: ipv6left(''1:2::6:7'') = 281483566645248');
SELECT is(mss.osag_ip_ipv6right('1:2::6:7'), 393223::numeric,
    'S-IP-015: golden case 7 right: ipv6right(''1:2::6:7'') = 393223');
SELECT is(mss.osag_ip_ipv6left('1:0::7'), 281474976710656::numeric,
    'S-IP-015: golden case 8 left: ipv6left(''1:0::7'') = 281474976710656');
SELECT is(mss.osag_ip_ipv6right('1:0::7'), 7::numeric,
    'S-IP-015: golden case 8 right: ipv6right(''1:0::7'') = 7');
SELECT is(mss.osag_ip_ipv6left('1::0:7'), 281474976710656::numeric,
    'S-IP-015: golden case 9 left: ipv6left(''1::0:7'') = 281474976710656');
SELECT is(mss.osag_ip_ipv6right('1::0:7'), 7::numeric,
    'S-IP-015: golden case 9 right: ipv6right(''1::0:7'') = 7');

-- ---------------------------------------------------------------------------------
-- S-IP-016: '::' expansion edge rules
-- ---------------------------------------------------------------------------------
SELECT is(mss.osag_ip_ipv6left('1:1:1:1::1:1:1:1'), 281479271743489::numeric,
    'S-IP-016: eight groups plus a stray ''::'' are tolerated (''::'' acts as '':'')');
SELECT is(mss.osag_ip_ipv6left('::ffff:c000:201'), 0::numeric,
    'S-IP-016: ipv6left(''::ffff:c000:201'') = 0 (IPv4-mapped form, leading ''::'')');
SELECT is(mss.osag_ip_ipv6right('::ffff:c000:201'), 281473902969345::numeric,
    'S-IP-016: ipv6right(''::ffff:c000:201'') = 281473902969345');

-- ---------------------------------------------------------------------------------
-- S-IP-017: hex groups are case-insensitive and tolerate leading zeros
-- ---------------------------------------------------------------------------------
SELECT is(mss.osag_ip_ipv6left('FFFF::'), 18446462598732840960::numeric,
    'S-IP-017: ipv6left(''FFFF::'') = 18446462598732840960 (uppercase hex)');
SELECT is(mss.osag_ip_ipv6left('ffff::'), 18446462598732840960::numeric,
    'S-IP-017: ipv6left(''ffff::'') = 18446462598732840960 (lowercase hex)');
SELECT is(mss.osag_ip_ipv6right('::00Ff'), 255::numeric,
    'S-IP-017: ipv6right(''::00Ff'') = 255 (mixed case, leading zeros)');

-- ---------------------------------------------------------------------------------
-- S-IP-018: unsigned 64-bit halves need numeric, not bigint
-- ---------------------------------------------------------------------------------
SELECT is(mss.osag_ip_ipv6left('ffff:ffff:ffff:ffff::'), 18446744073709551615::numeric,
    'S-IP-018: ipv6left(''ffff:ffff:ffff:ffff::'') = 2^64-1, beyond bigint');
SELECT is(pg_typeof(mss.osag_ip_ipv6right('::'))::text, 'numeric',
    'S-IP-018: ipv6right returns numeric');

-- ---------------------------------------------------------------------------------
-- S-IP-019: NULL / '' input
-- ---------------------------------------------------------------------------------
SELECT is(mss.osag_ip_ipv6left(NULL), NULL::numeric,
    'S-IP-019: ipv6left(NULL) is NULL');
SELECT is(mss.osag_ip_ipv6right(NULL), NULL::numeric,
    'S-IP-019: ipv6right(NULL) is NULL');
SELECT is(mss.osag_ip_ipv6left(''), NULL::numeric,
    'S-IP-019: ipv6left('''') is NULL (Oracle ''''/NULL collapsing)');
SELECT is(mss.osag_ip_ipv6right(''), NULL::numeric,
    'S-IP-019: ipv6right('''') is NULL (Oracle ''''/NULL collapsing)');

-- ---------------------------------------------------------------------------------
-- S-IP-020 (CORRECTED): malformed IPv6 returns NULL from both halves, never raises
-- ---------------------------------------------------------------------------------
SELECT lives_ok($$SELECT mss.osag_ip_ipv6left('g::'), mss.osag_ip_ipv6right('::12345')$$,
    'S-IP-020: non-hex / over-long groups do not raise (Oracle raised ORA-01722)');
SELECT is(mss.osag_ip_ipv6left('1:2:3:4:5'), NULL::numeric,
    'S-IP-020: ipv6left(''1:2:3:4:5'') is NULL (Oracle returned a partial value)');
SELECT is(mss.osag_ip_ipv6right('1:2:3:4:5'), NULL::numeric,
    'S-IP-020: ipv6right(''1:2:3:4:5'') is NULL');
SELECT is(mss.osag_ip_ipv6left('1:2:3:4:5:6:7:8:9'), NULL::numeric,
    'S-IP-020: ipv6left(''1:2:3:4:5:6:7:8:9'') is NULL (nine groups)');
SELECT is(mss.osag_ip_ipv6left('g::'), NULL::numeric,
    'S-IP-020: ipv6left(''g::'') is NULL (non-hex group)');
SELECT is(mss.osag_ip_ipv6right('::12345'), NULL::numeric,
    'S-IP-020: ipv6right(''::12345'') is NULL (five-digit group)');

-- ---------------------------------------------------------------------------------
-- S-IP-021: the eight golden num2ipv6 cases from MSS.OSAG_IP_TEST
-- ---------------------------------------------------------------------------------
SELECT is(mss.osag_ip_num2ipv6(0, 0), '::'::varchar,
    'S-IP-021: golden case 1: num2ipv6(0, 0) = ''::''');
SELECT is(mss.osag_ip_num2ipv6(0, 1), '::1'::varchar,
    'S-IP-021: golden case 2: num2ipv6(0, 1) = ''::1''');
SELECT is(mss.osag_ip_num2ipv6(281474976710656, 0), '1::'::varchar,
    'S-IP-021: golden case 3: num2ipv6(281474976710656, 0) = ''1::''');
SELECT is(mss.osag_ip_num2ipv6(1152921504606846976, 0), '1000::'::varchar,
    'S-IP-021: golden case 4: num2ipv6(1152921504606846976, 0) = ''1000::''');
SELECT is(mss.osag_ip_num2ipv6(17293822569102704640, 0), 'f000::'::varchar,
    'S-IP-021: golden case 5: num2ipv6(17293822569102704640, 0) = ''f000::'' (beyond bigint)');
SELECT is(mss.osag_ip_num2ipv6(0, 15), '::f'::varchar,
    'S-IP-021: golden case 6: num2ipv6(0, 15) = ''::f''');
SELECT is(mss.osag_ip_num2ipv6(281479576813568, 1249835548673), '1:1:1230::123:1:1'::varchar,
    'S-IP-021: golden case 7: num2ipv6(281479576813568, 1249835548673) = ''1:1:1230::123:1:1''');
SELECT is(mss.osag_ip_num2ipv6(281479539064832, 17523466633217), '1:1:ff0::ff0:1:1'::varchar,
    'S-IP-021: golden case 8: num2ipv6(281479539064832, 17523466633217) = ''1:1:ff0::ff0:1:1''');

-- ---------------------------------------------------------------------------------
-- S-IP-022: formatting rules of ipv6shorten
-- ---------------------------------------------------------------------------------
SELECT is(mss.osag_ip_num2ipv6(12379550950711361536, 0), 'abcd::'::varchar,
    'S-IP-022: hex digits are rendered lowercase');
SELECT is(mss.osag_ip_num2ipv6(281474976776192, 4295032833), '1:0:1::1:1:1'::varchar,
    'S-IP-022: a single zero group is kept, a pair of zero groups is collapsed');
SELECT is(mss.osag_ip_num2ipv6(281474976710657, 65537), '1::1:0:0:1:1'::varchar,
    'S-IP-022: on a tie the leftmost zero run is collapsed');
SELECT is(mss.osag_ip_num2ipv6(281479271743489, 281479271743489), '1:1:1:1:1:1:1:1'::varchar,
    'S-IP-022: no zero group means no ''::'' at all');
SELECT is(
    mss.osag_ip_num2ipv6(
        mss.osag_ip_ipv6left('2001:0DB8:0000:0000:0000:ff00:0042:8329'),
        mss.osag_ip_ipv6right('2001:0DB8:0000:0000:0000:ff00:0042:8329')),
    '2001:db8::ff00:42:8329'::varchar,
    'S-IP-022: num2ipv6(ipv6left(s), ipv6right(s)) is the canonical form of s');

-- ---------------------------------------------------------------------------------
-- S-IP-023 (CORRECTED): num2ipv6 with NULL / out-of-range halves returns NULL
-- ---------------------------------------------------------------------------------
SELECT lives_ok($$SELECT mss.osag_ip_num2ipv6(-1, 0), mss.osag_ip_num2ipv6(1.5, 0)$$,
    'S-IP-023: negative / fractional halves do not raise');
SELECT is(mss.osag_ip_num2ipv6(NULL, 0), NULL::varchar,
    'S-IP-023: num2ipv6(NULL, 0) is NULL (Oracle returned ''::'')');
SELECT is(mss.osag_ip_num2ipv6(0, NULL), NULL::varchar,
    'S-IP-023: num2ipv6(0, NULL) is NULL');
SELECT is(mss.osag_ip_num2ipv6(-1, 0), NULL::varchar,
    'S-IP-023: num2ipv6(-1, 0) is NULL');
SELECT is(mss.osag_ip_num2ipv6(1.5, 0), NULL::varchar,
    'S-IP-023: num2ipv6(1.5, 0) is NULL');
SELECT is(mss.osag_ip_num2ipv6(18446744073709551616, 0), NULL::varchar,
    'S-IP-023: num2ipv6(2^64, 0) is NULL (Oracle silently dropped the high bits)');

-- ---------------------------------------------------------------------------------
-- S-IP-024: IMMUTABLE, and no plog write from any routine (all of the above already
-- exercised every invalid-input path that Oracle logged on)
-- ---------------------------------------------------------------------------------
SELECT is(
    (SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'mss'
        AND p.proname IN ('osag_ip_getbcast', 'osag_ip_getnet', 'osag_ip_ip2num', 'osag_ip_num2ip',
                          'osag_ip_ipv6left', 'osag_ip_ipv6right', 'osag_ip_num2ipv6')
        AND p.provolatile = 'i'),
    7,
    'S-IP-024: all seven public routines are IMMUTABLE');
SELECT is(
    (SELECT count(*)::int FROM osag.plog_stub_log WHERE message LIKE '%OSAG_IP%'),
    0,
    'S-IP-024: no routine wrote a plog line, even on the invalid-input paths Oracle logged on');

-- ---------------------------------------------------------------------------------
-- S-IP-025: private helpers exist under the __ convention and are not PUBLIC
-- ---------------------------------------------------------------------------------
SELECT has_function('mss', 'osag_ip__ipv6pad0', ARRAY['character varying'],
    'S-IP-025: private helper mss.osag_ip__ipv6pad0(varchar) exists');
SELECT has_function('mss', 'osag_ip__ipv6shorten', ARRAY['character varying'],
    'S-IP-025: private helper mss.osag_ip__ipv6shorten(varchar) exists');
SELECT ok(
    NOT EXISTS (
        SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace,
             LATERAL aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
        WHERE n.nspname = 'mss' AND p.proname = 'osag_ip__ipv6pad0'
          AND a.grantee = 0 AND a.privilege_type = 'EXECUTE'),
    'S-IP-025: EXECUTE on mss.osag_ip__ipv6pad0 is revoked from PUBLIC');
SELECT ok(
    NOT EXISTS (
        SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace,
             LATERAL aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
        WHERE n.nspname = 'mss' AND p.proname = 'osag_ip__ipv6shorten'
          AND a.grantee = 0 AND a.privilege_type = 'EXECUTE'),
    'S-IP-025: EXECUTE on mss.osag_ip__ipv6shorten is revoked from PUBLIC');

SELECT * FROM finish();
ROLLBACK;
