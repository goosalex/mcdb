---
oracle_schema: MSS
oracle_package: OSAG_IP
pg_schema: mss
pg_prefix: osag_ip
clause_prefix: IP
oracle_spec: ddl/src/pkg/mss_osag_ip.sql
oracle_body: ddl/src/pkgb/mss_osag_ip.sql
public_routines: 7
---

# MSS.OSAG_IP — PostgreSQL spec

Pure, deterministic IP-address conversion helpers. Per the package header comment
(`ddl/src/pkg/mss_osag_ip.sql:4-7`) the package converts IPv4 addresses between the dotted
string form `A.B.C.D` and the numeric form `A*256^3 + B*256^2 + C*256 + D`, derives network
and broadcast addresses from an address and a prefix length, and (lines 14-19) splits an
IPv6 address into its two 64-bit halves and formats them back. Every public routine is
declared `DETERMINISTIC` (`ddl/src/pkg/mss_osag_ip.sql:9-19`); none touches a table. Two
private helpers (`ipv6pad0`, `ipv6shorten`) live only in the body. Oracle ships its own
unit-test package for this package (`ddl/src/pkgb/mss_osag_ip_test.sql`), whose 17 golden
cases are adopted verbatim as clauses here.

## Routines

### getbcast

- **Oracle signature:** `GETBCAST(p_ip NUMBER, p_mask NUMBER) RETURN NUMBER DETERMINISTIC`
- **PostgreSQL name:** `mss.osag_ip_getbcast` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/mss_osag_ip.sql:9`
- **Defined:** `ddl/src/pkgb/mss_osag_ip.sql:9-18`
- Returns the broadcast address (highest address) of the network of prefix length `p_mask`
  that contains numeric IPv4 address `p_ip`. No side effects, no logging, no exceptions.

### getnet

- **Oracle signature:** `GETNET(p_ip NUMBER, p_mask NUMBER) RETURN NUMBER DETERMINISTIC`
- **PostgreSQL name:** `mss.osag_ip_getnet` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/mss_osag_ip.sql:10`
- **Defined:** `ddl/src/pkgb/mss_osag_ip.sql:24-35`
- Returns the network address (lowest address) of the network of prefix length `p_mask`
  that contains numeric IPv4 address `p_ip`. No side effects, no logging, no exceptions.

### ip2num

- **Oracle signature:** `IP2NUM(p_string VARCHAR2) RETURN NUMBER DETERMINISTIC`
- **PostgreSQL name:** `mss.osag_ip_ip2num` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/mss_osag_ip.sql:11`
- **Defined:** `ddl/src/pkgb/mss_osag_ip.sql:41-100`
- Parses a dotted-quad IPv4 string into its 32-bit numeric value; returns `NULL` for
  every malformed input it detects. Oracle logs a `plog.debug` line on each detected
  malformation (lines 62, 77, 87, 91) — see S-IP-024 for why that logging is dropped.

### num2ip

- **Oracle signature:** `NUM2IP(p_number NUMBER) RETURN VARCHAR2 DETERMINISTIC`
- **PostgreSQL name:** `mss.osag_ip_num2ip` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/mss_osag_ip.sql:12`
- **Defined:** `ddl/src/pkgb/mss_osag_ip.sql:106-142`
- Formats a 32-bit numeric IPv4 value as a dotted-quad string; returns `NULL` for `NULL`,
  negative or too-large input. Oracle logs `plog.debug` on the too-large path (line 120);
  dropped per S-IP-024. Called from `TT.OSAG_NOTIFY` (`ddl/src/pkgb/tt_osag_notify.sql:1460-1469`)
  and `NIDS.OSAG_NIDS` (`ddl/src/pkgb/nids_osag_nids.sql:166,171`).

### ipv6left

- **Oracle signature:** `IPV6LEFT(p_ip VARCHAR2) RETURN INTEGER DETERMINISTIC`
- **PostgreSQL name:** `mss.osag_ip_ipv6left` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/mss_osag_ip.sql:15`
- **Defined:** `ddl/src/pkgb/mss_osag_ip.sql:191-214`
- Returns the 64 most significant bits of an IPv6 address string (with `::` expanded by
  the private `ipv6pad0`, lines 147-189) as an unsigned integer in `0 .. 2^64-1`.

### ipv6right

- **Oracle signature:** `IPV6RIGHT(p_ip VARCHAR2) RETURN INTEGER DETERMINISTIC`
- **PostgreSQL name:** `mss.osag_ip_ipv6right` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/mss_osag_ip.sql:17`
- **Defined:** `ddl/src/pkgb/mss_osag_ip.sql:216-242`
- Returns the 64 least significant bits of an IPv6 address string as an unsigned integer
  in `0 .. 2^64-1`.

### num2ipv6

- **Oracle signature:** `NUM2IPV6(p_left INTEGER, p_right INTEGER) RETURN VARCHAR2 DETERMINISTIC`
- **PostgreSQL name:** `mss.osag_ip_num2ipv6` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/mss_osag_ip.sql:19`
- **Defined:** `ddl/src/pkgb/mss_osag_ip.sql:295-321`
- Formats the two 64-bit halves as an RFC 5952-style compressed IPv6 string (lowercase hex,
  no leading zeros per group, longest run of two or more zero groups collapsed to `::`,
  via the private `ipv6shorten`, lines 245-293).

### Private helpers (body only, no `name-map.csv` row)

- `ipv6pad0(p_ip VARCHAR2) RETURN VARCHAR2` — `ddl/src/pkgb/mss_osag_ip.sql:147-189`,
  expands `::` to the full 8-group form.
- `ipv6shorten(p_ip VARCHAR2) RETURN VARCHAR2` — `ddl/src/pkgb/mss_osag_ip.sql:245-293`,
  collapses the longest run of zero groups.

Following the convention `migration/spec/tt.osag_notify.md` ("Private routines — naming
convention") established, these become `mss.osag_ip__ipv6pad0` and
`mss.osag_ip__ipv6shorten` with `REVOKE ALL ... FROM PUBLIC`. Their behaviour is specified
only through the public routines that call them (S-IP-016, S-IP-022).

## Clauses

### S-IP-001

- **routines:** getbcast
- **claim:** `getbcast(p_ip, p_mask)` returns `((TRUNC(p_ip / 2^(32-p_mask)) + 1) * 2^(32-p_mask)) - 1`
  — the highest address of the `/p_mask` network containing `p_ip`. Consequently
  `getbcast(ip2num('10.1.2.3'), 24) = ip2num('10.1.2.255')`, `getbcast(x, 32) = x`, and
  `getbcast(x, 0) = 4294967295` for any `x` below `2^32`. A `NULL` in either argument
  yields `NULL` (plain arithmetic on `NULL`); no exception is ever raised.
- **source:** `ddl/src/pkgb/mss_osag_ip.sql:16-17`

### S-IP-002

- **routines:** getnet
- **claim:** `getnet(p_ip, p_mask)` returns `p_ip - MOD(p_ip, 2^(32-p_mask))` — the lowest
  address of the `/p_mask` network containing `p_ip`. Consequently
  `getnet(ip2num('10.1.2.3'), 24) = ip2num('10.1.2.0')`, `getnet(x, 32) = x`, and
  `getnet(x, 0) = 0` for any `x` below `2^32`. A `NULL` in either argument yields `NULL`;
  no exception is ever raised.
- **source:** `ddl/src/pkgb/mss_osag_ip.sql:32-34`

### S-IP-003

- **routines:** ip2num
- **claim:** `ip2num(NULL)` returns `NULL` (explicit guard before any parsing). Because
  Oracle collapses `''` to `NULL`, `ip2num('')` is the same call and also returns `NULL`.
- **source:** `ddl/src/pkgb/mss_osag_ip.sql:52-54`

### S-IP-004

- **routines:** ip2num
- **claim:** For a well-formed dotted quad `A.B.C.D` where each byte is a canonical decimal
  integer in `0..255`, `ip2num` returns `A*2^24 + B*2^16 + C*2^8 + D`, accumulated byte by
  byte as `v_result * 256 + byte`. Examples: `ip2num('10.0.0.1') = 167772161`,
  `ip2num('0.0.0.0') = 0`, `ip2num('255.255.255.255') = 4294967295`,
  `ip2num('192.168.1.1') = 3232235777`.
- **source:** `ddl/src/pkgb/mss_osag_ip.sql:55-99`

### S-IP-005

- **routines:** ip2num
- **claim:** An input with fewer than three dots returns `NULL`: for byte 2..4 the
  start position is `INSTR(p_string, '.', 1, n-1) + 1`, and when the `(n-1)`-th dot does not
  exist `INSTR` returns 0, the start is 1 (`< 2`), and the routine returns `NULL`.
  Examples: `ip2num('1.2.3')`, `ip2num('1')`, `ip2num('10.0.0')` all return `NULL`.
- **source:** `ddl/src/pkgb/mss_osag_ip.sql:59-64`

### S-IP-006

- **routines:** ip2num
- **claim:** A byte whose text is not the canonical rendering of its numeric value returns
  `NULL`: the check is `TO_CHAR(TO_NUMBER(byte)) != byte`, so leading zeros (`'01'`), an
  explicit sign (`'+1'`), or surrounding whitespace (`' 1'`) all fail it. Examples:
  `ip2num('10.0.0.01')`, `ip2num('010.0.0.1')`, `ip2num('10.0.0.+1')`,
  `ip2num('10.0.0.1 ')` all return `NULL`. `'0'` itself is canonical and accepted.
- **source:** `ddl/src/pkgb/mss_osag_ip.sql:86-89`

### S-IP-007

- **routines:** ip2num
- **claim:** A byte whose numeric value exceeds 255 returns `NULL`. Examples:
  `ip2num('1.2.3.256')`, `ip2num('256.0.0.1')`, `ip2num('1.2.3.1000')` all return `NULL`.
- **source:** `ddl/src/pkgb/mss_osag_ip.sql:90-93`

### S-IP-008

- **routines:** ip2num
- **claim (CORRECTED — DEVIATION(ORACLE-BUG)):** A byte containing any non-numeric
  character returns `NULL`. In Oracle the "verify we have a numeric byte" check at line 86
  calls `TO_NUMBER(v_byte_string)` *before* comparing, so a byte such as `'a'` in
  `'1.a.3.4'` raises an unhandled `VALUE_ERROR` (ORA-06502) instead of taking the
  `RETURN NULL` branch the surrounding code (lines 86-89, comment at line 82) plainly
  intends. The translation must return `NULL` for `ip2num('1.a.3.4')`,
  `ip2num('a.b.c.d')`, `ip2num('10.0.0.1x')` — the same outcome every other malformation
  in this routine produces — and must not raise.
- **source:** `ddl/src/pkgb/mss_osag_ip.sql:82-89`

### S-IP-009

- **routines:** ip2num
- **claim (CORRECTED — DEVIATION(ORACLE-BUG)):** An input with more than three dots returns
  `NULL`. In Oracle the fourth byte's length is computed as everything after the *third*
  dot (line 74), so for `'1.2.3.4.5'` the fourth byte string is `'4.5'`; `TO_NUMBER('4.5')`
  is `4.5`, `TO_CHAR(4.5) = '4.5'` passes the canonical check at line 86, `4.5 > 255` is
  false, and the routine returns the non-integer `16909060.5` — not an IPv4 address. The
  translation must return `NULL` for `ip2num('1.2.3.4.5')` and `ip2num('10.0.0.1.')`.
  (Rationale: an IPv4 address has exactly four bytes; every other malformed shape in this
  routine yields `NULL`.)
- **source:** `ddl/src/pkgb/mss_osag_ip.sql:71-75, 86-93`

### S-IP-010

- **routines:** ip2num
- **claim:** An empty byte returns `NULL`. In Oracle `SUBSTR(p_string, start, 0)` is `NULL`
  (line 84), `TO_NUMBER(NULL)` is `NULL`, both `IF` guards at lines 86 and 90 are skipped
  (a `NULL` condition is not true), and `v_result * 256 + NULL` makes `v_result` `NULL`
  for the rest of the loop (line 97), so the function returns `NULL`. Examples:
  `ip2num('1..3.4')`, `ip2num('1.2.3.')`, `ip2num('.1.2.3')` all return `NULL`. The
  translation must produce the same `NULL` (this is Oracle's actual result, reached by
  accident; the corrected parser reaches it by design).
- **source:** `ddl/src/pkgb/mss_osag_ip.sql:84, 86, 90, 97`

### S-IP-011

- **routines:** num2ip
- **claim:** `num2ip(NULL)` and `num2ip(x)` for any negative `x` return `NULL` (explicit
  guard before any computation). Example: `num2ip(-1) IS NULL`.
- **source:** `ddl/src/pkgb/mss_osag_ip.sql:115-117`

### S-IP-012

- **routines:** num2ip
- **claim:** `num2ip(x)` returns `NULL` when the first byte `TRUNC(x / 16777216)` exceeds
  255, i.e. for every `x >= 2^32 = 4294967296`. `num2ip(4294967295) = '255.255.255.255'`
  is the largest formattable value. The analogous `> 255` checks for bytes 2 and 3 (lines
  127-130, 135-138) are unreachable — each remainder is already below the next divisor —
  and impose no additional constraint.
- **source:** `ddl/src/pkgb/mss_osag_ip.sql:118-122`

### S-IP-013

- **routines:** num2ip
- **claim:** For an integer `x` in `0 .. 2^32-1`, `num2ip(x)` returns the dotted quad
  `TRUNC(x/2^24) || '.' || TRUNC(r1/2^16) || '.' || TRUNC(r2/2^8) || '.' || r3` where each
  `r` is the remainder after the previous byte, with no padding and no leading zeros.
  Examples: `num2ip(0) = '0.0.0.0'`, `num2ip(167772161) = '10.0.0.1'`,
  `num2ip(3232235777) = '192.168.1.1'`, and `num2ip(ip2num(s)) = s` for every well-formed
  `s`.
- **source:** `ddl/src/pkgb/mss_osag_ip.sql:118-141`

### S-IP-014

- **routines:** num2ip
- **claim (CORRECTED — DEVIATION(ORACLE-BUG)):** A non-integer input returns `NULL`. In
  Oracle the fractional part survives every `TRUNC` and is concatenated into the last
  byte at line 140: `num2ip(1.5)` yields `'0.0.0.1.5'`, which is not an IPv4 address and
  would not round-trip through `ip2num`. The translation must return `NULL` for
  `num2ip(1.5)` (consistent with the routine's `NULL`-for-invalid contract at S-IP-011/012).
- **source:** `ddl/src/pkgb/mss_osag_ip.sql:123, 131, 139-140`

### S-IP-015

- **routines:** ipv6left, ipv6right
- **claim:** The nine golden cases from Oracle's own unit-test package
  `MSS.OSAG_IP_TEST.test_ipv62nums` hold exactly, as `(input → left, right)`:
  `'::' → 0, 0`; `'::1' → 0, 1`; `'1::' → 281474976710656, 0`;
  `'0:0:0:0:0:0:0001' → 0, 1`; `'::1:2:3:4:5:6:7' → 4295098371, 1125921382072327`;
  `'1:2:3:4:5:6:7::' → 281483566841860, 1407400653815808`;
  `'1:2::6:7' → 281483566645248, 393223`; `'1:0::7' → 281474976710656, 7`;
  `'1::0:7' → 281474976710656, 7`.
- **source:** `ddl/src/pkgb/mss_osag_ip_test.sql:78-112`, `ddl/src/pkgb/mss_osag_ip.sql:199-213, 224-241`

### S-IP-016

- **routines:** ipv6left, ipv6right
- **claim:** `::` expansion (private `ipv6pad0`) follows these rules, observable through
  `ipv6left`/`ipv6right`: an address without `::` is used as-is (lines 154-157); `'::'`
  alone is all zero groups (158-160); otherwise the number of present groups is the number
  of colons, minus one when `::` is at the very start or very end (163-168), and `::`
  is replaced by enough `:0` groups to reach eight (178-188). An address that already has
  eight groups *and* a `::` (invalid per RFC 5952, but tolerated) has the `::` treated as a
  single `:` (170-175): `ipv6left('1:1:1:1::1:1:1:1') = ipv6right('1:1:1:1::1:1:1:1') = 281479271743489`.
  Example of the IPv4-mapped form: `ipv6left('::ffff:c000:201') = 0`,
  `ipv6right('::ffff:c000:201') = 281473902969345`.
- **source:** `ddl/src/pkgb/mss_osag_ip.sql:154-188`

### S-IP-017

- **routines:** ipv6left, ipv6right
- **claim:** Each group is parsed as 1-4 hexadecimal digits via `TO_NUMBER(grp, 'xxxx')`,
  which is case-insensitive and tolerates leading zeros: `ipv6left('FFFF::') =
  ipv6left('ffff::') = ipv6left('0FFF0::')`-style equivalence holds digit-for-digit, e.g.
  `ipv6left('FFFF::') = 18446462598732840960`, `ipv6right('::00Ff') = 255`.
- **source:** `ddl/src/pkgb/mss_osag_ip.sql:203-210, 228-238`

### S-IP-018

- **routines:** ipv6left, ipv6right, num2ipv6
- **claim:** The halves are unsigned 64-bit quantities: the Oracle return type `INTEGER`
  is PL/SQL's `NUMBER(38)` subtype, so values up to `2^64-1 = 18446744073709551615` are
  representable and are produced (`ipv6left('ffff:ffff:ffff:ffff::') = 18446744073709551615`;
  golden case 5 of `test_num2ipv6` passes `17293822569102704640` for `f000::`). These exceed
  PostgreSQL `bigint` (`2^63-1`); the translation must use `numeric` for both the return
  type of `ipv6left`/`ipv6right` and the parameters of `num2ipv6`.
- **source:** `ddl/src/pkg/mss_osag_ip.sql:15-19`, `ddl/src/pkgb/mss_osag_ip_test.sql:33-35`

### S-IP-019

- **routines:** ipv6left, ipv6right
- **claim:** `ipv6left(NULL)` and `ipv6right(NULL)` return `NULL`: `ipv6pad0(NULL)` returns
  `NULL` (every `INSTR`/`LENGTH`/`REPLACE` on `NULL` is `NULL`, no branch is taken), and
  `0 * 65536 + TO_NUMBER(NULL)` is `NULL`. `''` is the same input under Oracle.
- **source:** `ddl/src/pkgb/mss_osag_ip.sql:154-160, 199-210`

### S-IP-020

- **routines:** ipv6left, ipv6right
- **claim (CORRECTED — DEVIATION(ORACLE-BUG)):** A string that does not expand to exactly
  eight groups of 1-4 hexadecimal digits returns `NULL` from both routines. In Oracle,
  malformed input is handled inconsistently: a group with a non-hex character or more than
  four digits raises an unhandled ORA-01722 from `TO_NUMBER(grp, 'xxxx')` (lines 210, 238);
  an address with fewer than eight groups and no `::` (e.g. `'1:2:3:4:5'`) makes
  `ipv6left` return a partial value (`281483566841860`, the first four groups) while
  `ipv6right` returns `NULL` because `SUBSTR` with a negative length is `NULL` (lines
  231-235). The translation must return `NULL` for `ipv6left('1:2:3:4:5')`,
  `ipv6right('1:2:3:4:5')`, `ipv6left('1:2:3:4:5:6:7:8:9')`, `ipv6left('g::')`, and
  `ipv6right('::12345')`, and must not raise.
- **source:** `ddl/src/pkgb/mss_osag_ip.sql:204-210, 229-238`

### S-IP-021

- **routines:** num2ipv6
- **claim:** The eight golden cases from Oracle's own unit-test package
  `MSS.OSAG_IP_TEST.test_num2ipv6` hold exactly, as `(left, right → result)`:
  `0, 0 → '::'`; `0, 1 → '::1'`; `281474976710656, 0 → '1::'`;
  `1152921504606846976, 0 → '1000::'`; `17293822569102704640, 0 → 'f000::'`;
  `0, 15 → '::f'`; `281479576813568, 1249835548673 → '1:1:1230::123:1:1'`;
  `281479539064832, 17523466633217 → '1:1:ff0::ff0:1:1'`.
- **source:** `ddl/src/pkgb/mss_osag_ip_test.sql:17-47`, `ddl/src/pkgb/mss_osag_ip.sql:301-320`

### S-IP-022

- **routines:** num2ipv6
- **claim:** Formatting rules (private `ipv6shorten`): each group is rendered as lowercase
  hexadecimal with no leading zeros (`TRIM(TO_CHAR(grp, 'xxxx'))`, lines 307/314 — so
  `num2ipv6(12379550950711361536, 0) = 'abcd::'`); the longest run of **two or more**
  consecutive zero groups is collapsed to `::` (the run must span more than three
  characters including its colons, line 271, so a single `0` group is never collapsed);
  on a tie the first (leftmost) run wins (strict `>` at line 271). Examples:
  `num2ipv6(281474976776192, 4295032833) = '1:0:1::1:1:1'` (single zero kept, pair
  collapsed), `num2ipv6(281474976710657, 65537) = '1::1:0:0:1:1'` (first of two equal runs),
  `num2ipv6(281479271743489, 281479271743489) = '1:1:1:1:1:1:1:1'` (no zero group).
  `num2ipv6(ipv6left(s), ipv6right(s))` is the canonical form of any well-formed `s`.
  **Oracle quirk, preserved as-is (valid, merely non-canonical output):** the scan only
  starts at a colon (line 259), so the first group is never counted as part of a run; a
  run of exactly two zero groups at the very start of the address is therefore measured
  as one group and NOT collapsed — `num2ipv6(ipv6left('0:0:1:1:1:1:1:1'),
  ipv6right('0:0:1:1:1:1:1:1')) = '0:0:1:1:1:1:1:1'` — while a leading run of three or
  more is collapsed (the surviving leading `0` is stripped by the `'0::%'` rule at lines
  288-290, as golden case 2, `'::1'`, shows). A trailing two-group run is collapsed
  normally (`'1:1:1:1:1:1::'`).
- **source:** `ddl/src/pkgb/mss_osag_ip.sql:257-290, 307, 314`

### S-IP-023

- **routines:** num2ipv6
- **claim (CORRECTED — DEVIATION(ORACLE-BUG)):** `num2ipv6` returns `NULL` unless both
  arguments are integers in `0 .. 2^64-1`. In Oracle: a `NULL` half is concatenated as the
  empty string (`NULL || ':'`, lines 307/314), so `num2ipv6(NULL, NULL)` returns `'::'` and
  `num2ipv6(NULL, 1)` returns `'::1'`, indistinguishable from a genuine zero half; a
  negative or fractional half makes `TO_CHAR(grp, 'xxxx')` render `'####'`-style overflow
  markers; a half `>= 2^64` has its high bits silently discarded by the four-iteration
  loop (lines 304-308, 311-315). None of these is an IPv6 address. The translation must
  return `NULL` for `num2ipv6(NULL, 0)`, `num2ipv6(0, NULL)`, `num2ipv6(-1, 0)`,
  `num2ipv6(1.5, 0)` and `num2ipv6(18446744073709551616, 0)`, and must not raise.
- **source:** `ddl/src/pkgb/mss_osag_ip.sql:301-318`

### S-IP-024

- **routines:** getbcast, getnet, ip2num, num2ip, ipv6left, ipv6right, num2ipv6
- **claim (DEVIATION(PLATFORM) for the logging):** All seven public routines are declared
  `DETERMINISTIC` and read no table, sequence or session state, so the PostgreSQL
  translation declares all seven `IMMUTABLE`. Oracle's `ip2num` and `num2ip` additionally
  emit `plog.debug(...)` on their invalid-input paths (lines 62, 77, 87, 91, 120, 128,
  136) — a table write through the `plog` stub, which is incompatible with an `IMMUTABLE`
  function and with `DETERMINISTIC` itself. The translation drops those debug calls; the
  observable contract (the `NULL` return) is unchanged. No routine in this package may
  write to `osag.plog_stub_log`.
- **source:** `ddl/src/pkg/mss_osag_ip.sql:9-19`, `ddl/src/pkgb/mss_osag_ip.sql:62, 77, 87, 91, 120, 128, 136`

### S-IP-025

- **routines:** ipv6left, ipv6right, num2ipv6
- **claim:** `ipv6pad0` and `ipv6shorten` are body-private (declared only in the package
  body, absent from the package spec) and are therefore not callable by Oracle clients.
  The translation exposes them only as `mss.osag_ip__ipv6pad0(varchar)` /
  `mss.osag_ip__ipv6shorten(varchar)` with `EXECUTE` revoked from `PUBLIC`.
- **source:** `ddl/src/pkg/mss_osag_ip.sql:9-20`, `ddl/src/pkgb/mss_osag_ip.sql:147, 245`

## Checklist

### 1. Empty-string / NULL handling

Three `VARCHAR2` parameters exist: `ip2num.p_string`, `ipv6left.p_ip`, `ipv6right.p_ip`
(the latter two reach `ipv6pad0.p_ip`); `num2ipv6`'s locals `v_res` (line 301, assigned
`''`) and `ipv6shorten`'s `v_ip`/`v_res` are the only other string identifiers.

- `p_string IS NULL` (`ddl/src/pkgb/mss_osag_ip.sql:52`): `''` is reachable from a caller
  and in Oracle is the same as `NULL` → `NULL`. Translation: treat `''` exactly like `NULL`
  (S-IP-003); an explicit `p_string IS NULL OR p_string = ''` guard, since PostgreSQL's
  `'' IS NULL` is false.
- `v_byte_string` comparisons at line 86 (`!=`) and 90 (`>`): an empty byte is `NULL` in
  Oracle (`SUBSTR(..., 0)`), making both conditions unknown (S-IP-010). A naive PostgreSQL
  port would get `substr(..., 0) = ''`, `'' != ''` false, and `''::numeric` raising
  `22P02`. Translation: the corrected parser rejects empty bytes explicitly (S-IP-010).
- `ipv6pad0`: `p_ip = '::'` (line 158), `v_res LIKE ':%'` / `'%:'` (182, 185), and the
  `NVL(LENGTH(REPLACE(p_ip, ':', '')), 0)` at line 163 — the `NVL` exists precisely
  because `REPLACE('::', ':', '')` is `''` = `NULL` in Oracle, whose `LENGTH` is `NULL`;
  PostgreSQL's `length('')` is `0`, so the `NVL` is harmless there. `p_ip = ''`/`NULL`
  returns `NULL` (S-IP-019); translation guards `p_ip IS NULL OR p_ip = ''` explicitly.
- `ipv6shorten`: `v_res LIKE '%:'`, `NOT LIKE '%::'`, `LIKE '0::%'` (283, 288) operate on a
  string that is never empty (it is built from eight rendered groups); not reachable with
  `''`.
- `num2ipv6`'s `v_res := ''` (301) is `NULL` in Oracle and `''` in PostgreSQL; both
  concatenate identically with `||` on the next line (`NULL || ':'` is `':'` in Oracle,
  `'' || ':'` is `':'` in PostgreSQL) — no behavioural difference, no action needed.

### 2. SELECT INTO strictness

N/A — there is no `SELECT ... INTO` anywhere in the package: verified by reading all 323
lines of `ddl/src/pkgb/mss_osag_ip.sql`; the body contains no SQL statement of any kind
(no `SELECT`, `INSERT`, `UPDATE`, `DELETE`, cursor, or `DUAL` access), matching the Phase 1
inventory's empty `select_into_sites` for `MSS.OSAG_IP`.

### 3. Exception codes

No `RAISE_APPLICATION_ERROR`, no named exception, no `EXCEPTION` block exists anywhere in
the package (verified over the full body; inventory `raise_application_error: []`). The
only exceptions Oracle can raise are *implicit*: `VALUE_ERROR` (ORA-06502) from
`TO_NUMBER` on a non-numeric byte in `ip2num` (line 86) and ORA-01722 from
`TO_NUMBER(grp, 'xxxx')` on a non-hex group in `ipv6left`/`ipv6right` (lines 210, 238).
Both are classified as defects, not contracts — the surrounding code's own `RETURN NULL`
branches show the intent — and are corrected to `NULL` returns (S-IP-008, S-IP-020). After
correction, no routine in this package raises for any input; nothing needs a SQLSTATE
mapping and nothing is left PROVISIONAL for XCUT-01.

### 4. Package state

None. The package body (`ddl/src/pkgb/mss_osag_ip.sql`) opens with `FUNCTION getbcast` at
line 9 immediately after the `IS` at line 3 and the section-header comment (5-7); there is
no declare section between `IS` and the first routine, every `c_prefix` is a routine-local
`CONSTANT` (lines 14, 30, 50, 113), and the file ends with `END OSAG_ip;` at line 322 with
no trailing unnamed initialization block. Matches the inventory's `package_state: []` and
`has_init_block: false`.

### 5. FUNCTION vs PROCEDURE

No `COMMIT`, `ROLLBACK` or `PRAGMA AUTONOMOUS_TRANSACTION` anywhere in the package
(verified over the full body; inventory `has_commit: false`, `has_rollback: false`,
`autonomous_transaction: false`). All seven public routines are `FUNCTION`s declared
`DETERMINISTIC` (`ddl/src/pkg/mss_osag_ip.sql:9-19`), and `name-map.csv` carries
`pg_kind=function` for all seven. They translate to PostgreSQL `FUNCTION ... IMMUTABLE`
(S-IP-024); there is no transaction-control hazard, and the one incompatibility
(`plog.debug` table writes inside a would-be `IMMUTABLE` function) is resolved by dropping
the debug calls, not by demoting volatility.

## Assumptions / Unresolved

- `getbcast`/`getnet` with `p_mask` outside `0..32`, non-integer `p_mask`, or `p_ip`
  outside `0..2^32-1` produce arithmetically defined but meaningless values in Oracle
  (`POWER(2, 32-p_mask)` is fractional for `p_mask > 32`). No caller in `ddl/src/**`
  passes such values (`changes/changelog-current.sql:2521` is the only non-package
  reference and is a comment). The spec does not constrain these inputs and the tests do
  not exercise them; the translation reproduces the same arithmetic.
- Oracle `TO_NUMBER(grp, 'xxxx')` case handling: Oracle's `X` format element accepts both
  upper- and lower-case hex digits on input; this is Oracle documentation knowledge, not
  something the repo's source demonstrates (the golden cases use only lowercase and
  digits). S-IP-017 asserts case-insensitivity as the intended contract.
- Whether `TO_NUMBER('-1')` passing the canonical check at line 86 (so that Oracle's
  `ip2num('-1.2.3.4')` returns a negative "address") was ever relied upon cannot be
  determined statically; the corrected parser (S-IP-006/008, digits only) returns `NULL`
  for a signed byte. No caller passes literal strings; all call sites feed table columns.
- No caller of `ipv6left`/`ipv6right`/`num2ipv6` exists anywhere in `ddl/src/**` other
  than the unit-test package itself (grep over `ddl/src` for the three names); the
  corrected `NULL`-for-invalid behaviour (S-IP-020, S-IP-023) therefore has no known
  downstream consumer to break.
- Everything else was settled statically: every `IS NULL`/`=`/`!=`/`||`/`LIKE` site on a
  string, every `TO_NUMBER`/`TO_CHAR` site, the full declare section (none), and the
  absence of SQL, exceptions and transaction control were each reviewed against the full
  text of `ddl/src/pkg/mss_osag_ip.sql` and `ddl/src/pkgb/mss_osag_ip.sql`.
