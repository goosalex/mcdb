# MSS.OSAG_IP -- FINDINGS

**Source:** `ddl/src/pkg/mss_osag_ip.sql` (spec, 25 lines), `ddl/src/pkgb/mss_osag_ip.sql`
(body, 323 lines), `ddl/src/pkgb/mss_osag_ip_test.sql` (Oracle's own unit tests, 131
lines). **Spec:** `migration/spec/mss.osag_ip.md`. **Target:**
`migration/pgsql/mss/osag_ip.sql`. **Tests:** `migration/test/pgtap/mss__osag_ip__spec.sql`
(108 assertions, 25/25 clauses cited).

## AuditUsage deletion count

**0 of 0.** This package never called `plog.AuditUsage` (`grep -c AuditUsage
ddl/src/pkgb/mss_osag_ip.sql` -> 0). Nothing to delete.

## Volatility: all nine functions IMMUTABLE, debug logging dropped

Every public routine is `DETERMINISTIC` in Oracle (`ddl/src/pkg/mss_osag_ip.sql:9-19`) and
reads no table. All seven public functions and both private helpers are created
`IMMUTABLE`; verified live via `pg_proc.provolatile = 'i'` (S-IP-024 asserts the count).

Oracle's `ip2num` and `num2ip` call `plog.debug(...)` on seven invalid-input paths (body
lines 62, 77, 87, 91, 120, 128, 136). Under the Phase 2 stub, `plog.debug` is a procedure
that INSERTs into `osag.plog_stub_log`; a `CALL` to it inside an `IMMUTABLE` function is
not acceptable (and PL/pgSQL would reject the `CALL` of a writing procedure from a
non-volatile context at runtime). Decision: **drop the debug calls, keep IMMUTABLE**. The
observable contract (a `NULL` return) is unchanged; S-IP-024's second assertion proves no
routine writes a plog row even on every invalid path the suite exercises. Each dropped
site is marked `-- DEVIATION(PLATFORM) S-IP-024` in the translation.

## Types

`NUMBER` -> `numeric`, `VARCHAR2` -> `varchar`. The IPv6 halves are unsigned 64-bit
values; Oracle's `INTEGER` return/parameter type is PL/SQL `NUMBER(38)`, and golden case
5 of `test_num2ipv6` passes `17293822569102704640` (`f000::`), which exceeds `bigint`.
`ipv6left`/`ipv6right` return `numeric`, `num2ipv6` takes `numeric` (S-IP-018). Hex
groups are parsed with `('x' || lpad(grp, 4, '0'))::bit(16)::int` (case-insensitive,
1-4 digits -- verified on PostgreSQL 17.10) instead of Oracle's `TO_NUMBER(grp, 'xxxx')`;
groups are rendered with `to_hex(bigint)` instead of `TRIM(TO_CHAR(grp, 'xxxx'))` --
both lowercase, both unpadded.

`getbcast`/`getnet` wrap their result in `trim_scale()` because `power(numeric, numeric)`
returns a scaled numeric (`256.0000000000000000`); the value is identical, only the
textual rendering is cleaned up so callers that concatenate the number see `256`.

## Deviations from Oracle

Every site is marked in the translation with `-- DEVIATION(KIND) S-IP-NNN`; the spec
states each corrected behaviour as the contract and cites the Oracle lines that show the
defect, so the tests assert the corrected behaviour.

| Clause | Kind | Oracle behaviour (cited) | Translated behaviour | Why |
|---|---|---|---|---|
| S-IP-008 | ORACLE-BUG | `ip2num('1.a.3.4')` raises ORA-06502: line 86 evaluates `TO_NUMBER(byte)` before the "is this numeric" comparison it feeds. | Returns `NULL`. | Lines 82-89 plainly intend `RETURN NULL` for a non-numeric byte; the raise is an ordering accident. |
| S-IP-009 | ORACLE-BUG | `ip2num('1.2.3.4.5')` returns `16909060.5`: line 74 takes everything after the third dot as byte 4, `'4.5'` survives the canonical check. | Returns `NULL`. | Not an IPv4 address; every other malformed shape yields `NULL`. |
| S-IP-014 | ORACLE-BUG | `num2ip(1.5)` returns `'0.0.0.1.5'`: the fraction survives every `TRUNC` and is concatenated at line 140. | Returns `NULL`. | Not an IPv4 address; would not round-trip through `ip2num`. |
| S-IP-020 | ORACLE-BUG | Malformed IPv6: non-hex / 5+ digit group raises ORA-01722 (lines 210, 238); `'1:2:3:4:5'` makes `ipv6left` return a partial value while `ipv6right` returns `NULL` (negative-length `SUBSTR`, line 235). | Both halves return `NULL`, never raise, unless the input expands to exactly eight groups of 1-4 hex digits. | Inconsistent partial results and unhandled raises are not a usable contract. |
| S-IP-023 | ORACLE-BUG | `num2ipv6(NULL, NULL)` returns `'::'` (`NULL || ':'` concatenation, lines 307/314); negative/fractional halves render `'####'` via `TO_CHAR`; halves >= 2^64 silently lose high bits in the four-iteration loop. | Returns `NULL` unless both halves are integers in `0 .. 2^64-1`. | `'::'` for `NULL` is indistinguishable from the real zero address. |
| S-IP-024 | PLATFORM | `plog.debug` on seven invalid-input paths. | Dropped. | Table write inside an `IMMUTABLE` function. |

### Oracle quirk deliberately preserved (not a deviation)

`ipv6shorten` (lines 257-275) only starts a zero-run scan at a colon, so the first group
never counts towards a run. Consequence: a leading run of exactly **two** zero groups is
not collapsed (`'0:0:1:1:1:1:1:1'` stays as is), while a leading run of three or more is
collapsed and its surviving `0` stripped by the `'0::%'` rule (lines 288-290). The output
is a valid (if non-canonical) IPv6 string, no caller depends on canonical form, and the
golden cases (`'::'`, `'::1'`, `'::f'`) all involve runs of 7-8 groups which the rule
handles; so it is ported statement-for-statement and pinned by two S-IP-022 assertions.

### Oracle's unit-test package cannot see NULL results (found, recorded as A-009)

`MSS.OSAG_IP_TEST` checks `IF actual != expected THEN raise` (`mss_osag_ip_test.sql:54,
121`). When `actual` is `NULL` the condition is not true and the case passes vacuously.
Golden case 4 of `test_ipv62nums` (`'0:0:0:0:0:0:0001'`, line 90) has only **seven**
groups; Oracle's `ipv6right` returns `NULL` for it, and the `(0, 1)` expectation was
never attainable in Oracle. The RED suite had copied the case verbatim; the first GREEN
run failed 2/106 on exactly those two assertions. Handled by the sanctioned route: spec
amended first (`05832a1`, S-IP-015 note with the Oracle evidence), test amended in a
commit touching no translation file (`670fc0a`), ledger entry
`migration/spec/TEST-AMENDMENTS.md` A-009. The suite now asserts the eight-group intent
under S-IP-015 and the literal typo under S-IP-020.

## Verification performed

- RED: `bootstrap.sh --db mcdb_test_ipmsg --template mcdb_tmpl`, then
  `run-tests.sh --db mcdb_test_ipmsg --install migration/pgsql --package mss.osag_ip`
  before this file existed: **0/104, exit 1**, first error
  `function mss.osag_ip_ip2num(unknown) does not exist` (recorded in the test commit
  message `27d3c61`).
- First GREEN run (translation on disk, uncommitted): 104/106 -- the two failures were
  the defective golden case 4 (above), not a translation defect.
- GREEN after A-009: `run-tests.sh --db mcdb_test_ipmsg --install migration/pgsql
  --package mss.osag_ip` -> **108/108 PASS**.
- `grep -nEi "dbms_|utl_|auditusage|plog"` over this file: matches only in comments
  documenting the dropped debug calls; no `CALL` of any plog procedure.
- `bash migration/spec/provenance_lint.sh`: spec commit `524499f` and first test commit
  `27d3c61` are ancestors of the translation commit; no commit touches both the
  translation and a test file.

## Open questions

- `getbcast`/`getnet` with a prefix length outside `0..32` or a non-integer one reproduce
  Oracle's arithmetic (`power(2, 32 - mask)` becomes fractional); no caller passes such
  values and the spec leaves them unconstrained.
- No caller of `ipv6left`/`ipv6right`/`num2ipv6` exists in `ddl/src/**` outside the Oracle
  unit-test package; the corrected `NULL`-for-invalid behaviour therefore has no known
  consumer to break, but client code outside this repo was not searched.
