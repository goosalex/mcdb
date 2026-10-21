# TEST-AMENDMENTS.md

The anti-circularity contract (`migration/spec/provenance_lint.sh`) forbids a **translation**
commit from touching a test file. Tests are written from the Oracle-derived spec *before* the
translation exists; a translation that could edit its own tests would make this phase theatre.

This file is the audit trail for the sanctioned escape hatch. Every amendment to an already-committed
test file is recorded here, with evidence, so a reviewer can check that nothing was quietly weakened
to manufacture a green run.

**The bar:** an amendment must not change *what* is asserted. It may only correct a defect that
prevents the test from asserting what it already intended. A change that makes a failing test pass by
asserting *less* is not an amendment — it is a translation bug being covered up, and it is forbidden.

**Plan 02-13 correction — file relocated to its documented path.** This file previously lived at
`migration/test/TEST-AMENDMENTS.md`. `provenance_lint.sh` (`TEST_AMENDMENTS="$SPEC_DIR/TEST-AMENDMENTS.md"`,
`SPEC_DIR="migration/spec"`) and `migration/spec/README.md` ("The TEST-AMENDMENTS.md escape hatch")
both hard-code `migration/spec/TEST-AMENDMENTS.md` as the ledger's real location. None of A-001..A-008
below tripped this — every amendment commit touched only a test file, never the translation file in
the same commit, so `provenance_lint.sh`'s combined-commit check (the only place it reads this ledger)
never fired. But the gap was real: had a future amendment ever needed to land in the SAME commit as a
translation file (the documented, sanctioned escape-hatch shape `migration/spec/README.md` describes),
`provenance_lint.sh` would have found no ledger at its hard-coded path and rejected a properly-recorded
amendment outright — fail-closed, not a security hole, but a latent tooling break. Moved to the path
the tooling and documentation already specify (`git mv`, history preserved); see 02-13-SUMMARY.md.

---

## A-001 — `tt__osag_notify__selectinto.sql`: 7 × `throws_ok` 3-arg overload misuse

| | |
|---|---|
| **Date** | 2026-07-13 |
| **Amended by** | orchestrator (not a translation plan — this commit touches NO translation file) |
| **File** | `migration/test/pgtap/tt__osag_notify__selectinto.sql` |
| **Assertions affected** | 7 |
| **Surfaced by** | plan 02-10, which correctly REFUSED to fix it (a translation plan may not touch tests) and documented it in `migration/pgsql/tt/osag_notify.FINDINGS.md` |
| **User approved** | Yes — explicitly, before the edit was made |

### The defect

pgTAP's `throws_ok` has two 3-argument overloads and they are ambiguous by design:

```
throws_ok ( sql, errcode, errmsg )       -- arg3 = expected ERROR MESSAGE
throws_ok ( sql, errmsg, description )   -- arg3 = human label
```

When arg2 is a 5-character SQLSTATE, pgTAP resolves to the **first** form — so arg3 is treated as the
*expected error message*, not as a label. All 7 calls passed a long human sentence as arg3, so each
asserted "expect SQLSTATE X **whose message is literally this sentence**". No error can ever have that
message, so the assertions could never pass regardless of how correct the translation was.

### Independently reproduced (not taken on trust)

```sql
SELECT throws_ok($$ SELECT 1/0 $$, '22012', 'this is meant to be a human description');
-- not ok 1 - threw 22012: this is meant to be a human description
--       caught: 22012: division by zero
--       wanted: 22012: this is meant to be a human description
```

The SQLSTATE matched. The test still failed — on the description text.

### The amendment

Insert `NULL` as the message argument, promoting each call to the unambiguous 4-argument form
`throws_ok(sql, errcode, errmsg, description)`, where a NULL `errmsg` means "do not check the message":

```diff
 SELECT throws_ok(
     $$CALL tt.osag_notify_send_test_notification(...)$$,
     'P0002',
+    NULL,
     'S-NOTIFY-018: send_test_notification (SMS branch) propagates NO_DATA_FOUND unhandled ...'
 );
```

Affected: 6 × `'P0002'` (S-NOTIFY-018 ×2, 024, 025, 026, 028) and 1 × `'23502'` (S-NOTIFY-022).

### Why this is not a weakening

The asserted condition is **unchanged**: each test still requires that exact SQLSTATE to be raised.
Only the sentence's role changes — from "expected message" (never satisfiable) to "test label" (its
evident intent, matching every other test file in the suite).

**Proven still falsifiable** — the corrected form fails on a wrong SQLSTATE:

```sql
SELECT throws_ok($$ SELECT 1/0 $$, '23505', NULL, 'wrong code must fail');
-- not ok 2 - wrong code must fail
--       caught: 22012: division by zero
```

A test that cannot fail is worthless; this one can, and does.

### Effect

`tt.osag_notify`: **15/24 → 22/24** pgTAP assertions passing. No translation file was modified in the
amending commit. `provenance_lint.sh` passes.

---

## A-002 — the same `throws_ok` defect in 5 more test files (23 assertions)

| | |
|---|---|
| **Date** | 2026-07-13 |
| **Amended by** | orchestrator (touches NO translation file) |
| **Assertions affected** | 23 |
| **User approved** | Yes — same defect class as A-001, approved remedy applied to all identical instances |

### Why this exists

A-001 fixed 7 instances in one file. A sweep then found the **identical** pgTAP misuse in 5 more files —
every spec/test agent independently made the same mistake:

| File | Instances |
|---|---|
| `auth__osag_auth__spec.sql` | 1 |
| `tt__event_interface__spec.sql` | 4 |
| `tt__ticket_interface__changes.sql` | 5 |
| `tt__ticket_interface__lifecycle.sql` | 8 |
| `tt__ticket_interface__selectinto.sql` | 5 |

These were fixed **before** plans 02-11 and 02-12 run. Left in place, they would have made 23 assertions
unpassable no matter how correct those translations were — sending both agents to hunt phantom bugs in
correct code, and very likely provoking exactly the kind of "fix" that corrupts a translation to satisfy a
broken test.

### The amendment

Mechanically identical to A-001: insert `NULL` as the message argument, promoting each 3-arg call to the
unambiguous 4-arg `throws_ok(sql, errcode, errmsg, description)`. The asserted SQLSTATE is unchanged in
every case; only the sentence's role changes from "expected message" to "label". Still falsifiable — a
wrong SQLSTATE still fails (proven under A-001).

### Effect

`auth.osag_auth`: **8/10 → 9/10**. The `tt.event_interface` and `tt.ticket_interface` assertions remain red
only because their translations do not exist yet (plans 02-11 and 02-12) — which is correct, and is what
the RED baseline confirms: with no translation installed, those packages still report **0** passes.

### Standing warning for 02-13

The RED baseline (`run-tests.sh` with no `--install`) shows `tt.ticket_interface` at **6/129** — six
assertions pass with **no translation loaded at all**. A test that passes when the code under test does not
exist is not testing that code. These six are prime candidates for the mutation check to expose, and must
be examined before the phase can claim a clean red→green.

---

## A-003 — `tt__event_interface__spec.sql`: 2 × `is()` smallint/numeric overload mismatch

| | |
|---|---|
| **Date** | 2026-07-25 (commit b764d34, entry backfilled) |
| **Amended by** | orchestrator (touches NO translation file) |
| **File** | `migration/test/pgtap/tt__event_interface__spec.sql` |
| **Assertions affected** | 2 (S-EVENT-043, S-EVENT-044) — plus 12 more killed by the cascade |
| **User approved** | Yes — "Ok" to the adjudication pass that surfaced it |

### The defect

`tt.event.demoted` is `smallint`. The two demote/promote value checks compared it against
`1::numeric` / `0::numeric`. pgTAP's `is(anyelement, anyelement)` requires both arguments to
resolve to the SAME type — `is(smallint, numeric)` resolves to **no function at all**, raising
`42883 function does not exist`, which aborts the transaction and cascades: every later assertion
in the file dies with `25P02 current transaction is aborted` (6/20 → the file's floor).

### The amendment

Changed the two expected literals to `1::smallint` / `0::smallint`. The asserted VALUE (1, 0) is
unchanged — only the cast is corrected so the comparison can execute at all. The three
S-EVENT-034 `is()` calls correctly keep `::numeric` (that function returns `numeric`).

### Effect

`tt.event_interface`: **6/20 → 20/20** pgTAP. No translation file touched; `provenance_lint.sh` passes.

---

## A-004 — `tt__osag_notify__spec.sql`: S-NOTIFY-021 fixture missing the `stop.contact` row

| | |
|---|---|
| **Date** | 2026-07-25 |
| **Amended by** | orchestrator (touches NO translation file) |
| **File** | `migration/test/pgtap/tt__osag_notify__spec.sql` |
| **Assertions affected** | 1 red (`ok(... 'deletion of notifications ... failed')`) + 1 vacuously green (`lives_ok`) |
| **User approved** | Yes — user adjudicated S-NOTIFY-021 "fix now"; diagnosis revised from translation to fixture (below) |

### The defect — and a corrected diagnosis

The S-NOTIFY-021 test inserts `auth.login (900105, contact_id => 900106, ...)` and an
`event_notification` referencing a nonexistent `event_notification_type_id`, intending the
delete-loop to hit private `get_notification_type_name`'s SELECT INTO (site #30), raise
NO_DATA_FOUND, and prove the outer `WHEN OTHERS` swallows + logs. But it never inserted
`stop.contact` row 900106 — and the cursor INNER-joins contact
(`c.id = l.contact_id`, Oracle `ddl/src/pkgb/tt_osag_notify.sql:885-890`). With no contact row
the loop iterates ZERO times, site #30 is never reached, nothing raises, nothing is logged —
**in Oracle exactly as in the translation**. This test could never pass against the Oracle
original either.

The initial adjudication evidence blamed a missing `STRICT` in the translation. That was wrong:
site #30 (`migration/pgsql/tt/osag_notify.sql`, `__get_notification_type_name`) already has
`SELECT ... INTO STRICT` per the spec's site #30 verdict ("STRICT + handler (indirect)").

### Independently reproduced (not taken on trust)

Probe against a fresh template clone with the translation installed:

- **Fixture as-is (no contact 900106):** loop empty — `0` matching plog rows, notification row untouched.
- **Fixture + `INSERT INTO stop.contact (id, ...) VALUES (900106, ...)`:** site #30 STRICT raises
  `no data found`, outer WHEN OTHERS fires, BOTH Oracle-parity warnings logged
  (`deletion of notifications for ticket 900103 failed` + `exception: query returned no rows`).

### The amendment

Add the missing fixture row `INSERT INTO stop.contact (id, lastname, firstname) VALUES (900106, ...)`
before the login insert. No assertion text, SQLSTATE, or expected value changed — the fixture now
constructs the scenario the test's own comment block describes.

### Effect

`tt__osag_notify__spec.sql`: **8/10 → 10/10**. No translation file touched.

---

## A-005 — `tt__osag_notify__selectinto.sql`: `plan(14)` off-by-one (13 actual assertions)

| | |
|---|---|
| **Date** | 2026-07-25 |
| **Amended by** | orchestrator (touches NO translation file) |
| **File** | `migration/test/pgtap/tt__osag_notify__selectinto.sql` |
| **Assertions affected** | 0 (plan line only) |
| **User approved** | Covered by the S-NOTIFY-021 "fix now" adjudication (surfaced by the same green run) |

### The defect

The file declares `SELECT plan(14)` but contains exactly **13** assertions (verified by grep and by
pg_prove: `ok 1..ok 13`, zero failures, then `Parse errors: Bad plan. You planned 14 tests but ran 13`).
Present since the original commit (f4fe690); masked while real failures existed, exposed the moment
all 13 assertions went green.

### The amendment

`plan(14)` → `plan(13)`. No assertion added, removed, or changed.

### Effect

`tt__osag_notify__selectinto.sql`: **13/14 (TAP plan failure) → 13/13 PASS**.

---

## A-006 — `tt__ticket_interface__*.sql`: 19 × `throws_ok` 3-arg overload misuse (third sweep)

| | |
|---|---|
| **Date** | 2026-07-25 |
| **Amended by** | orchestrator (touches NO translation file) |
| **Files** | `tt__ticket_interface__changes.sql` (6), `tt__ticket_interface__lifecycle.sql` (3), `tt__ticket_interface__selectinto.sql` (10) |
| **Assertions affected** | 19 |
| **Surfaced by** | plan 02-12, which correctly REFUSED to touch them and documented them in `ticket_interface.FINDINGS.md` |
| **User approved** | Yes — same defect class as A-001/A-002, approved remedy applied to all identical instances |

### Why a third sweep was needed

A-002 swept these same three files and fixed 18 instances. **19 more survived** — the earlier sweep's
pattern missed calls whose description argument contained embedded double quotes or spanned an
unusual line shape. The lesson for 02-13's method review: a text-pattern sweep for this defect class
is not reliable; the only sound detector is *running* the suite and looking for the
`threw <SQLSTATE>: <long sentence>` output shape.

### The defect and the amendment

Mechanically identical to A-001 (see there for the full reproduction). Each call passed a human
description as arg3, where pgTAP's SQLSTATE overload expects the *expected error message*, making the
assertion unsatisfiable. Fixed by inserting `NULL` as the message argument (4-arg form). The asserted
SQLSTATE is unchanged in all 19 cases.

**Verified still falsifiable and verified genuinely passing:** e.g. `changes.sql` test 16 previously
reported `caught: P0002: query returned no rows` / `wanted: P0002: <the description sentence>` — the
translation was raising the correct SQLSTATE with the correct Oracle-parity message all along.

---

## A-007 — `tt__ticket_interface__changes.sql`: `ROW()::record` column-type mismatch (cascade of 40)

| | |
|---|---|
| **Date** | 2026-07-25 |
| **Amended by** | orchestrator (touches NO translation file) |
| **File** | `migration/test/pgtap/tt__ticket_interface__changes.sql` |
| **Assertions affected** | 1 directly, **40 more by cascade** |
| **User approved** | Yes — same class as A-003 (expected-value type mismatch against real column types) |

### The defect

The S-TICKET-024 `change_company` assertion compared
`ROW(company_id, contact_id, mss_service_id, host_id)` against an all-`numeric` `ROW(...)::record`.
In the real ora2pg-migrated schema `tt.ticket.mss_service_id` and `host_id` are **bigint** (only
`company_id`/`contact_id` are numeric). PostgreSQL raises
`cannot compare dissimilar column types bigint and numeric at record column 3` — a hard ERROR that
aborts the transaction, so the file ran only 30 of its planned 70 assertions and pg_prove reported
`Bad plan`. **40 assertions were being lost to one wrong cast.**

### Independently verified as a test defect, not a translation defect

Probed `change_company` directly against the installed translation:

```
company_id=907099989 contact_id=NULL mss_service_id=NULL host_id=NULL
```

— exactly the values the assertion demands. The translation was correct; only the comparison's
column typing prevented it from executing.

### The amendment

`NULL::numeric` → `NULL::bigint` for the `mss_service_id` and `host_id` columns. The asserted VALUES
(new company id, and NULL for the three reset columns) are unchanged.

### Combined effect of A-006 + A-007

`tt.ticket_interface`: **57/129 → 111/129** pgTAP. No translation file touched by the amending commit;
`provenance_lint.sh` passes. No other package regressed.

---

## A-008 — `tt__ticket_interface__lifecycle.sql`: 7 ticket fixtures missing `last_status_change_date`

| | |
|---|---|
| **Date** | 2026-07-25 |
| **Amended by** | orchestrator (touches NO translation file) |
| **File** | `migration/test/pgtap/tt__ticket_interface__lifecycle.sql` |
| **Assertions affected** | 8 (tests 13, 14, 27–32 — the whole `merge_tickets` cluster) |
| **Surfaced by** | plan 02-12, which correctly refused to touch it |

### The defect

Every `tt.ticket` fixture row was inserted without `last_status_change_date` (nullable, no
default). Any status change then reaches the private `updateTicketTimeStats`, which computes
`v_status_time := TRUNC((sysdate - p_last_status_change_date) * 86400)` and applies
`UPDATE ... SET open_time = open_time + v_status_time`. With a NULL date the arithmetic yields
NULL and the NOT NULL column rejects it.

### Verified to be a fixture defect, not a translation defect

- The translation (`ticket_interface.sql`, `__updatetickettimestats`) is a **statement-for-statement
  port** of Oracle `ddl/src/pkgb/tt_ticket_interface.sql:2313-2358`, including the same unguarded
  arithmetic. Oracle would raise `ORA-01407 cannot update ... to NULL` on the same input.
- `newticket_new` **always** writes `last_status_change_date` (`ticket_interface.sql:417`), so a
  ticket with NULL there is a state the application itself never produces. The fixture was
  constructing an impossible row.

### The amendment

Added `last_status_change_date = now() - interval '1 hour'` to the 7 ticket fixture rows, with a
comment recording why. No assertion, expected value, or SQLSTATE changed.

### Effect

`tt__ticket_interface__lifecycle.sql`: **30/39 → 38/39**. The one remaining failure is the
`auth.permission` materialized-view gap (see PHASE2 findings — a harness/schema gap, not a
translation defect).

---

## A-009 — `tt__ticket_interface__selectinto.sql`: 5 ticket fixtures (last_status_change_date, misplaced orphan, status 4)
| **Amended by** | orchestrator, branch `phoenix/migrate_tt_only` (touches NO translation file) |
| **File** | `migration/test/pgtap/tt__ticket_interface__selectinto.sql` |
| **Assertions affected** | 4 (tests 3, 10, 15, 20) |
| **Surfaced by** | status report 2026-10-13, section 1 (Q1); answered yes on this branch |

### The defects

- Tickets 907011, 907012, 907025, 907030 inserted without `last_status_change_date`
  (same class as A-008): `change_status_event_id_out` reaches the private
  `updateTicketTimeStats` BEFORE sites #14/#15/#61/#73, and its
  `open_time = open_time + TRUNC((sysdate - p_last_status_change_date)*86400)` turns NULL
  into a NOT NULL violation (`23502`), so the asserted `P0002` was never reached.
  `newticket_new` always sets the column (`ticket_interface.sql:417`); the fixtures
  described a row the application never produces.
- Ticket 907018: the fixture's own comment says the orphan value belongs in
  `company_id` (site #39 is the OLD-company lookup), but `VALUES` put it in `status_id`.
- Ticket 907030: started at `status_id = 4`, which is not in the tracked-transition set
  `{2,11,12,60,61,101}` (`ddl/src/pkgb/tt_ticket_interface.sql`, updateTicketTimeStats),
  so no `ticket_time_statistic` row could ever be written; every sibling fixture uses 2.

### The amendment

Added `last_status_change_date = now() - interval '1 hour'` to the four rows, moved
907018's orphan to `company_id` (status 2), changed 907030's status 4 → 2. No assertion,
expected value or SQLSTATE changed. Effect: 16/20 → 20/20 (tt.ticket_interface 129/129).

`commit:1582555640b78a2a552c2bc3666490f54b16f13e file:migration/test/pgtap/tt__ticket_interface__selectinto.sql reason:A-009 fixture defects, test-only commit`

---

## A-010 — `tt__osag_notify__errors.sql`: mask the non-deterministic DETAIL line

| | |
|---|---|
| **Date** | 2026-10-16 |
| **Amended by** | orchestrator, branch `phoenix/migrate_tt_only` (touches NO translation file) |
| **File** | `migration/test/regress/sql/tt__osag_notify__errors.sql` |
| **Assertions affected** | the golden `expected/tt__osag_notify__errors.out` (1 of 2 statements) |
| **Surfaced by** | status report 2026-10-13 (Q2: "the osag_notify one additionally needs the non-deterministic DETAIL line masked") |

### The defect

The not-null-violation `DETAIL: Failing row contains (...)` prints the live
`nextval('tt.event_sequence')` and `statement_timestamp()` values; the golden pinned a
hand-written placeholder that could never match.

### The amendment

`\set VERBOSITY terse` / `\set VERBOSITY default` around that one `CALL`. psql's terse
verbosity drops DETAIL and CONTEXT for that statement only; the `ERROR:` text and
SQLSTATE — the substance this file pins — are unchanged. Golden regenerated in the
follow-up test-only commit `84c0c4b`.

`commit:1582555640b78a2a552c2bc3666490f54b16f13e file:migration/test/regress/sql/tt__osag_notify__errors.sql reason:A-010 mask non-deterministic DETAIL, test-only commit`

| | |
|---|---|
| **Date** | 2026-10-16 |

---

## A-015 — `mss__osag_ip__spec.sql`: Oracle golden case 4 of `test_ipv62nums` is a seven-group typo
| **Amended by** | the OSAG_IP translation agent, in a commit that touches NO translation file (test commit `670fc0a`, after spec commit `05832a1`) |
| **File** | `migration/test/pgtap/mss__osag_ip__spec.sql` |
| **Assertions affected** | 2 changed (S-IP-015 golden case 4 left/right), 2 added (S-IP-020) |
| **Surfaced by** | the first GREEN run of the then-uncommitted `migration/pgsql/mss/osag_ip.sql` (104/106) |

## A-019 — `mc__osag_maintsync__errors.out`: trailing spaces stripped from the golden's header line

| | |
|---|---|
| **Date** | 2026-10-20 |
| **Amended by** | plan 06-01's own agent, BEFORE its translation commit and in a commit touching no translation file (c214e17) |
| **File** | `migration/test/regress/expected/mc__osag_maintsync__errors.out` |
| **Assertions affected** | 1 regress golden (header line only) |
| **Surfaced by** | the first GREEN run of `run-tests.sh --package mc.osag_maintsync`: pgTAP 109/109, regress 0/1 with a diff on line 1 only |

### The defect

The golden was authored from the spec's values rendered through psql itself (a stand-in
`SELECT ... FROM (VALUES ...)` with the harness's exact flags), but the editor used to save it
stripped trailing whitespace. psql pads the LAST column's header to the column width
(`message` + 31 spaces) while leaving data rows unpadded, so the saved golden lost exactly
those 31 spaces and nothing else: `diff -w expected actual` is empty.

### The fix

The actual output file was copied over the golden (whitespace-only change, `1 insertion(+),
1 deletion(-)`). No asserted value changed: the two ERR lines, their order and their text are
byte-identical to the hand-authored version. Same class as the "header-whitespace drift" plan
02-13 recorded for four Phase 2 goldens.

commit:670fc0a0b362edd8c42c8782b1b288ec99da187c file:migration/test/pgtap/mss__osag_ip__spec.sql reason:Oracle golden case 4 input has seven groups; spec S-IP-015 amended first (05832a1) with Oracle-side evidence

### The defect

The RED suite copied `'0:0:0:0:0:0:0001' → (0, 1)` verbatim from
`ddl/src/pkgb/mss_osag_ip_test.sql:90-92`. That input has six colons — seven groups, no
`::`. Traced through Oracle's `ipv6right` (`ddl/src/pkgb/mss_osag_ip.sql:226-239`): the
fourth iteration finds no further colon, `SUBSTR` with a negative length is `NULL`, and
the function returns `NULL`, not `1`. The Oracle test package never notices because its
check `IF actual_left != expected_left OR actual_right != expected_right`
(`mss_osag_ip_test.sql:121`) is not true when `actual_right` is `NULL` — the golden
expectation was unattainable in Oracle itself and passed vacuously.

### The amendment

- S-IP-015 case 4 now asserts the evident eight-group intent `'0:0:0:0:0:0:0:0001' → (0, 1)`
  (a leading-zero group, the thing the case was clearly written to exercise).
- The literal seven-group string is asserted under S-IP-020 (malformed → `NULL`, `NULL`),
  where the spec already placed every "fewer than eight groups" input.

### Why this is not a weakening

No expected value was changed to match the translation's output: the translation returned
`NULL, NULL` for the typo, and the amended suite now asserts exactly that *under the clause
that already demanded it* (S-IP-020, written before the translation), while keeping the
original `(0, 1)` expectation alive on the input the Oracle author evidently meant. The
evidence is entirely in the Oracle sources cited above. Still falsifiable: a translation
that returned a partial `0` for `ipv6left` of the typo (Oracle's actual behaviour) fails
the new S-IP-020 assertion.

### Lesson for the corpus

Oracle's `OSAG_IP_TEST` style (`IF actual != expected THEN raise`) cannot detect a `NULL`
result at all. Golden cases lifted from Oracle unit-test packages must be re-derived by
hand against the Oracle body, not trusted because "the Oracle test passes".

---

## A-016 — `osag__osag_msg__spec.sql`: row-count bookkeeping literals off by one; `xmin` through a view

| | |
|---|---|
| **Date** | 2026-10-16 |
| **Amended by** | the OSAG_MSG translation agent, in a commit that touches NO translation file (`b471f1173139938c1942d21c02fe06cfa9583441`) |
| **File** | `migration/test/pgtap/osag__osag_msg__spec.sql` |
| **Assertions affected** | 6 (S-MSG-008 ×2, S-MSG-011 ×1, S-MSG-012 ×2, S-MSG-014 ×1) |
| **Surfaced by** | the first GREEN run of the then-uncommitted `migration/pgsql/osag/osag_msg.sql` (57/63) |

commit:b471f1173139938c1942d21c02fe06cfa9583441 file:migration/test/pgtap/osag__osag_msg__spec.sql reason:bookkeeping literals (rows queued so far) miscounted by one and xmin is not visible through a temp view; no asserted behaviour changed
commit:d982a159bb998b87f04010107a86b04bb9e4e3dc file:migration/test/pgtap/osag__osag_msg__spec.sql reason:S-MSG-014 xmin check must accept subtransaction xids (the INSERT runs inside an EXCEPTION-bearing block); no asserted behaviour changed

### The defect

The file tracks "rows queued so far" between groups. Six `send_mail` calls succeed before
the S-MSG-008 baseline and seven rows exist before the S-MSG-011 baseline; the literals
said five and six. Both the *before* and the *after* literal of each pair were wrong by the
same one, so the actual run showed `6 -> 6` and `7 -> 7`: the failing `send_mail` calls
and the swallowed `send_sms` calls queued nothing, exactly as asserted — only the
author's arithmetic was off (same class as A-005). Separately, the S-MSG-014 assertion
read `xmin` through the temp view `v_mine`; PostgreSQL does not expose system columns
through views (`column "xmin" does not exist`), and `txid_current()::text::xid` is the
wrong cast for an epoch-qualified id.

### The amendment

Literals 5/5/6/6/6 -> 6/6/7/7/7; the S-MSG-014 query reads `osag.msg_outbox` directly and
compares `xmin = pg_current_xact_id()::xid` (verified live: a row inserted in the current
transaction matches). No SQLSTATE, column expectation or clause changed.

### Second pass (commit `d982a159bb998b87f04010107a86b04bb9e4e3dc`)

The corrected S-MSG-014 query still failed (`have: 0, want: 7`): the outbox INSERT runs
inside `osag.osag_msg__enqueue`'s block, which has an `EXCEPTION` clause and is therefore
a **subtransaction** — the rows carry a subxid, not the top-level `pg_current_xact_id()`.
The assertion now reads "written by this transaction or one of its subtransactions":
`xmin::bigint >= (pg_current_xact_id()::xid)::bigint`.

### Why this is not a weakening

Every amended assertion still asserts the same thing (no row queued on failure; every
queued row written by the current transaction). A translation that queued a row on a
`NULL` recipient would still fail S-MSG-008/012; one that COMMITted autonomously would
fail the `lives_ok` calls outright (`CALL` cannot COMMIT inside the harness's open
transaction) and the S-MSG-014 `prosrc` check.

---

## A-017 — `ticketevolution__calculator__spec.sql`: ORDER BY tie-break in the S-TICKEV-007 lone-merge `results_eq`
| **Amended by** | the TICKETEVOLUTION.CALCULATOR translation agent, in a commit that touches ONLY the test file (`1f5d10145d707c03eb0be80afbf4159385459fb8`), landed BEFORE the translation commit |
| **File** | `migration/test/pgtap/ticketevolution__calculator__spec.sql` |
| **Assertions affected** | 1 (test 62) |
| **Surfaced by** | the first GREEN run of the translation: 61/62 pass, test 62 "have: (merged,...) want: (new,...)" — rows identical, order swapped |

### The defect

The assertion's query ended `ORDER BY date_to, ticket_status`. The two spec-derived rows for a
lone `100004` event (S-TICKEV-007 / S-TICKEV-009) share `date_to`, so the tie-break decided the
order — and `'merged' < 'new'` alphabetically, the reverse of the VALUES list. The assertion
could never pass regardless of translation correctness.

### The amendment

`ORDER BY date_to, ticket_status_id` (1 for `new`, 110 for `merged`) — the order the VALUES list
already had. No expected value, column, row count or cited clause changed.

### Why this is not a weakening

The same two rows with the same ten values are still required, in a deterministic order that now
matches what the spec says is emitted first (the pseudo `'new'` row is inserted before the real
row, S-TICKEV-009).

### Effect

`ticketevolution.calculator` pgTAP 61/62 → 62/62 with the unchanged translation.

---

---

## A-012 — `tt__event_interface__corrections.sql`: NEW file for the corrected `moveevent` (Q11 (a))

| | |
|---|---|
| **Date** | 2026-10-16 |
| **Amended by** | Q11 corrections agent, branch `phoenix/migrate_tt_only` (touches NO translation file) |
| **File** | `migration/test/pgtap/tt__event_interface__corrections.sql` (new, 10 assertions) |
| **Assertions affected** | 0 existing; 10 added |
| **Surfaced by** | status report 2026-10-13, Q11 (a): `moveevent` ignores `p_event_id` (Oracle header comment "FIXME / BROKEN") |

### Why a new file, not an edit

The project owner's instruction for this branch is not to mimic broken Oracle behaviour but
to annotate the correction. The locked `tt__event_interface__spec.sql` pins S-EVENT-033's
swallow/log path for a nonexistent new ticket, which the correction keeps — so that file
is untouched. The corrected semantics got their own clauses (S-EVENT-046/047, spec commit
`35a92fd`, written BEFORE this file) and their own file.

### RED evidence (against the pre-correction translation, `mcdb_test_q11`)

```
Failed test 3:  S-EVENT-046 ... left the OLD ticket's other event (910612) on 910601   have: 910602 want: 910601
Failed test 6:  S-EVENT-047 ... did NOT move event 910612 ... not attached to 910603    have: 910602 want: 910601
Failed test 9:  S-EVENT-047 ... nonexistent p_event_id modified nothing                 have: 910602 want: 910601
Failed test 10: S-EVENT-047 ... logged "...event does not exist"
Failed 4/10 subtests
```

Tests 6 and 9 fail as a consequence of test 3 (the bug had already re-parented 910612);
tests 3 and 10 are the two independent defects. GREEN 10/10 after `8ba4dce`.

`commit:0499bc80d45f09248a41c755be1b3c42b759dcc1 file:migration/test/pgtap/tt__event_interface__corrections.sql reason:A-012 new corrections suite for S-EVENT-046/047, test-only commit`

---

## A-013 — `tt__ticket_interface__corrections.sql`: NEW file for Q11 (b) and (d)
| **Amended by** | Q11 corrections agent, branch `phoenix/migrate_tt_only` (touches NO translation file) |
| **File** | `migration/test/pgtap/tt__ticket_interface__corrections.sql` (new, 15 assertions) |
| **Assertions affected** | 0 existing; 15 added (7 for S-TICKET-060, 8 for S-TICKET-059) |
| **Surfaced by** | status report 2026-10-13, Q11 (b) `add_status_change_event` never assigns `cust_id`; Q11 (d) `remove_related_file` lacks `add_related_file`'s same-company guard |

Spec first: S-TICKET-053 amended + S-TICKET-059 new (`26a7ef5`), S-TICKET-045 amended +
S-TICKET-060 new (`f3b1e24`). Q11 (c) was decided "behaviour kept" (`86aec61`) and needs
no test change — the locked S-TICKET-021 assertions remain its tests.

### RED evidence (against the pre-correction translation, `mcdb_test_q11`)

```
Failed test 2:  S-TICKET-060 ... did NOT delete the cross-company relation          have: 0    want: 1
Failed test 3:  S-TICKET-060 ... logged the mirrored "...different companies" message
Failed test 4:  S-TICKET-060 ... no 100019 history event for the refused detach      have: 1    want: 0
Failed test 7:  S-TICKET-060 ... exactly ONE 100019 history event                     have: 2    want: 1
Failed test 9:  S-TICKET-059 ... customer-reference audit event carries company_id   have: NULL want: 910001
Failed test 11: S-TICKET-059 ... partner-reference audit event carries company_id    have: NULL want: 910001
Failed test 13: S-TICKET-059 ... emergency audit event carries company_id            have: NULL want: 910001
Failed test 14: S-TICKET-059 ... raises NO_DATA_FOUND (P0002) for a nonexistent ticket   caught: no exception
Failed test 15: S-TICKET-059 ... no audit event written for the nonexistent ticket   have: 1    want: 0
Failed 9/15 subtests
```

GREEN 15/15 after `e51dcfb` (b) + `5210514` (d).

`commit:b8c18dd98ba76705c5075f93e9c05cd12171d3b4 file:migration/test/pgtap/tt__ticket_interface__corrections.sql reason:A-013 new corrections suite for S-TICKET-059/060, test-only commit`

---

## A-014 — `tt__ticket_interface__changes.sql`: "same-company" fixture 906028 had no release row (+ one label)

| | |
|---|---|
| **Date** | 2026-10-16 |
| **Amended by** | Q11 corrections agent, branch `phoenix/migrate_tt_only` (touches NO translation file) |
| **File** | `migration/test/pgtap/tt__ticket_interface__changes.sql` |
| **Assertions affected** | 0 changed; 1 fixture row added; 1 description text updated (S-TICKET-045 `lives_ok`) |
| **Surfaced by** | Q11 (d) — the corrected `remove_related_file` requires the same-company release the fixture's own comment always claimed |

### The defect

The fixture comment reads "A second, same-company file/relation for remove_related_file's
own fixture", but file 906028 was never released to any company — there was no
`mc.mc_file_release` row at all. Under Oracle's un-guarded lookup that was invisible.
S-TICKET-060 (spec commit `f3b1e24`, written first) makes "same-company" mean what the
comment says: a release of the file to the ticket's company.

### The amendment

Added `INSERT INTO mc.mc_file_release (id, company_id, mc_file_id) VALUES (906031, 906001, 906028)`
so the fixture constructs the scenario it describes, and reworded the S-TICKET-045
`lives_ok` description (which asserted, in words only, "no same-company guard at all").
The asserted conditions — the call succeeds, the relation row is deleted — are unchanged.
Verified: the file still passes 70/70 against the PRE-correction translation (the extra
release row is behaviour-neutral under Oracle's lookup) and 70/70 after.

`commit:b8c18dd98ba76705c5075f93e9c05cd12171d3b4 file:migration/test/pgtap/tt__ticket_interface__changes.sql reason:A-014 same-company fixture 906028 gains its mc_file_release row + S-TICKET-045 label, test-only commit`

---

## A-018 — `tt__ticket_interface__selectinto.sql`: S-TICKET-045 site #66 label only

| | |
|---|---|
| **Date** | 2026-10-16 |
| **Amended by** | Q11 corrections agent, branch `phoenix/migrate_tt_only` (touches NO translation file) |
| **File** | `migration/test/pgtap/tt__ticket_interface__selectinto.sql` |
| **Assertions affected** | 0 changed; 1 description text + its comment block updated |

The site #66 `lives_ok` description stated "swallowed by its whole-routine WHEN OTHERS, no
dedicated NO_DATA_FOUND arm". After Q11 (d) the orphaned-file case is swallowed by the
mirrored `NO_DATA_FOUND` arm instead; the assertion (`lives_ok`, nothing propagates) is
identical and passes before and after. Label corrected so it does not contradict the
amended S-TICKET-045.

`commit:b8c18dd98ba76705c5075f93e9c05cd12171d3b4 file:migration/test/pgtap/tt__ticket_interface__selectinto.sql reason:A-018 S-TICKET-045 site #66 label only, test-only commit`
commit:c214e1777859713824b265dbd6ed37dd475dce29 file:migration/test/regress/expected/mc__osag_maintsync__errors.out reason:psql header-line trailing spaces stripped by the editor; whitespace-only (diff -w empty), no asserted value changed

---

## A-020 — `tt__ticket_interface__changes.sql`, `tt__ticket_interface__selectinto.sql`: export commit reverted them to July content, restore commit re-applied them

| | |
|---|---|
| **Date** | 2026-10-20 |
| **Amended by** | orchestrator (ledger entry only; the two files are byte-identical to their e179c5a content) |
| **Files** | `migration/test/pgtap/tt__ticket_interface__changes.sql`, `migration/test/pgtap/tt__ticket_interface__selectinto.sql` |
| **Assertions affected** | none changed by the restore |

Commit `0e5c990` ("update to 20261020") carried the new Oracle export, master data and the
pg.sh container wiring, but also overwrote 27 branch files with their 2026-07 content, among
them these two test files (undoing A-009, A-014, A-018) together with the translation
`migration/pgsql/tt/ticket_interface.sql` in the same commit. Commit `b9ba1dd` ("intermediate
update of migration output") restored all 27 files from `e179c5a` in one commit, again test
files and translation together. Both are the shape `provenance_lint.sh` forbids; neither
changed what any test asserts. Verified: `git diff e179c5a HEAD -- <both test files>` is empty.

`commit:0e5c990bf11a416578f3498cfa71bb2ebe2defd2 file:migration/test/pgtap/tt__ticket_interface__changes.sql reason:A-020 accidental revert to July content in the export commit, restored verbatim from e179c5a`
`commit:0e5c990bf11a416578f3498cfa71bb2ebe2defd2 file:migration/test/pgtap/tt__ticket_interface__selectinto.sql reason:A-020 accidental revert to July content in the export commit, restored verbatim from e179c5a`
`commit:b9ba1ddb9055679c53aa3581593b243651daaa15 file:migration/test/pgtap/tt__ticket_interface__changes.sql reason:A-020 restore of the e179c5a content, no asserted behaviour changed`
`commit:b9ba1ddb9055679c53aa3581593b243651daaa15 file:migration/test/pgtap/tt__ticket_interface__selectinto.sql reason:A-020 restore of the e179c5a content, no asserted behaviour changed`

---

## A-021 — `osixinfo__osag_hardware__spec.sql`: S-HW-004 reason text read from the exception

| | |
|---|---|
| **Date** | 2026-10-20 |
| **Amended by** | plan 06-02 agent, branch `phoenix/migrate_tt_only` (touches NO translation file) |
| **File** | `migration/test/pgtap/osixinfo__osag_hardware__spec.sql` |
| **Assertions affected** | 1 replaced (`is(count(*) FROM osag.plog_stub_log ...) = 1` -> `throws_like(..., '%<same text>')`); count unchanged (78) |

The RED suite asserted, after a `throws_ok` on a DIRECT `replace_hardware` call, that the
S-HW-004 `plog.err` line (`dump_to_hw_history: hardware_disposal_reason_id is NULL while
replacing hw for host_id: 931130 hw_id: 931231`) exists in `osag.plog_stub_log`. That can
never be observed: the exception leaves the package, pgTAP rolls the statement back to its
savepoint, and the transactional plog stub's row goes with it (`osag_plog.FINDINGS.md`,
"Rollback limitation" -- Oracle's plog was autonomous). The spec was amended first
(`09b4ae2`, S-HW-011: the translated `e_abort` carries the log line as its message). The
assertion now pins the SAME text through `throws_like` on the exception message. What is
asserted (the reason text, and that the contact check passed first) is unchanged; the
sibling "contact message NOT logged" count-0 assertion is untouched.

`commit:7c15c784339fabecd30a207246933e3aa2a9d6e0 file:migration/test/pgtap/osixinfo__osag_hardware__spec.sql reason:A-021 S-HW-004 reason text pinned via throws_like instead of the transactional plog stub table, test-only commit`

## A-022 — `tt__ticket_interface__signoff.sql`: two auth.login fixtures need distinct `login` names

| | |
|---|---|
| **Date** | 2026-10-21 |
| **Amended by** | orchestrator (touches NO translation file) |
| **File** | `migration/test/pgtap/tt__ticket_interface__signoff.sql` |
| **Assertions affected** | 0 changed; fixtures and call notation only |

Three fixture/call defects surfaced while proving the file RED, none changing what is
asserted: (1) the two `auth.login` rows (908610, 908611) had no `login` value and
`u_login_login_company_nocase` treats two NULL logins in one company as duplicates -- they
now carry `sgn-servicenow` / `sgn-worker`; (2) the `CALL`s passed every optional argument
positionally, and a positional `statement_timestamp()` (timestamptz) does not resolve
against the `timestamp` parameter `p_eventdate` (42883) -- trailing optional arguments
are now passed by name and the defaults used; (3) the fixture host had no
`mss.host2service` row, so site #2 (STRICT) raised `P0002` before any clause under test
was reached -- an `mss.service` + `mss.host2service` pair was added; (4) `plan(22)` for 25
assertions, and `change_worker` was called with a sub-select as argument (`0A000`, not allowed
in `CALL`) -- now a `DO` block with a variable.

`commit:TEST-ONLY file:migration/test/pgtap/tt__ticket_interface__signoff.sql reason:A-022 fixture login names, named-notation calls, host2service row; test-only commit`

## A-301 — `tt__event_interface__spec.sql`: S-EVENT-001 asserted a path Oracle cannot take (two services per host)

| | |
|---|---|
| **Date** | 2026-10-21 |
| **Amended by** | differential-harness agent (TT.EVENT_INTERFACE / TT.ESCALATION_INTERFACE); touches NO translation file |
| **File** | `migration/test/pgtap/tt__event_interface__spec.sql` |
| **Assertions affected** | 1 replaced (the S-EVENT-001 `throws_ok` P0003), `plan(20)` unchanged |

The live Oracle run of scenario `tt__event_interface__newevent` refused the fixture that gave
one host two `mss.host2service` rows: `ORA-00001: unique constraint (MSS.IDX_H2S_HOST_UN)
violated`. The index is in the export (`ddl/generated/schema.oracle.sql:3700`, created by
`changes/changelog-2.archive.sql:1884`) but not in the ora2pg output, so the PostgreSQL
template accepted the second row and the old assertion ("newevent_new propagates
TOO_MANY_ROWS unhandled for a host mapped to two services", P0003) was green for a
situation that cannot exist in Oracle. Spec S-EVENT-001 was amended first (commit
`spec(tt.event_interface): S-EVENT-001 amended ...`, same day): TOO_MANY_ROWS is
structurally impossible. The test now asserts the schema fact the clause rests on -- the
second `host2service` row for one host raises `23505` -- which is RED until
`migration/test/schema-fixes/29_host2service_unique_fixes.sql` is in the template. The
`WHEN OTHERS THEN RAISE` arm of the translation is unchanged. This amendment changes WHAT is
asserted because the clause itself changed; it does not weaken a test to match a translation
(the translation is untouched by it).

`commit:TEST-ONLY file:migration/test/pgtap/tt__event_interface__spec.sql reason:A-301 S-EVENT-001 re-pointed at the unique-index fact (TOO_MANY_ROWS impossible); test-only commit`
