# FINDINGS: TT.OSAG_NOTIFY

Translation: `migration/pgsql/tt/osag_notify.sql` (6 public routines, 13 private routines
under the `tt.osag_notify__<name>` convention). Spec: `migration/spec/tt.osag_notify.md`.
Oracle body: `ddl/src/pkgb/tt_osag_notify.sql` (1844 lines).

This FINDINGS.md was started by a prior agent session that translated and committed the
package (commit `e05dc24`) but was killed before getting the suite green. This version
completes the plan: it records the fixes applied to reach green on everything the test
suite can actually verify, and documents — with reproduced evidence — the assertions that
remain red for reasons intrinsic to the test files themselves, not the translation.

## STRICT verdict distribution across the 30 SELECT INTO sites (as translated)

Per the spec's `### SELECT INTO strictness` table, applied site-by-site (no blanket
answer in either direction):

- **29 of 30 sites: `STRICT`.** Every one of these carries a `-- S-NOTIFY-0NN` clause-ID
  comment (verified: `grep -c 'S-NOTIFY-[0-9]{3}'` >= the SELECT-INTO count).
- **1 site (site #11, `is_notify_suppressor_active`'s `COUNT(*)` aggregate, S-NOTIFY-023):
  deliberately NOT STRICT** — a `COUNT(*)` always returns exactly one row; both
  `NO_DATA_FOUND` and `TOO_MANY_ROWS` are structurally impossible there. This is the
  package's one legitimate no-STRICT-concern site, exactly as the spec calls it.
- **The one `TOO_MANY_ROWS` handler** (site #22, `__get_isp_link_id_for_host_id`,
  S-NOTIFY-031) has `INTO STRICT` plus all three explicit handler arms
  (`NO_DATA_FOUND` / `TOO_MANY_ROWS` / `OTHERS`), all swallowing to `NULL` — verified live
  by the selectinto pgTAP file's three-way host fixture (none / one / many ISP links),
  which passes (see "Red/green status" below).
- No `NO_DATA_FOUND` handler guards a non-STRICT SELECT INTO anywhere (the dead-handler
  shape PITFALLS.md warns about) — confirmed by the plan's own automated dead-handler
  check, which passes clean.

## AuditUsage deletion count

**6 call sites deleted**, not ported (Oracle body lines 335, 784, 861, 901, 953, 984),
per XCUT-06 (the feature is write-only/unused — nothing reads `osag.plsql_audit`).

## "no data found" message-parity shim — added by THIS session

The spec is explicit (see the file's XCUT-01 discussion, quoting Oracle's `ORA-01403`):
"PL/pgSQL's default `NO_DATA_FOUND` SQLSTATE (`P0002`) ... must propagate to
[send_test_notification's reachable chain] exactly as Oracle's `ORA-01403` does today."
This is the SAME convention already established by `auth/osag_auth.sql` and `tt/util.sql`
(Phase 2 pilot precedent) — a transparent `BEGIN ... EXCEPTION WHEN NO_DATA_FOUND THEN
RAISE EXCEPTION 'no data found' USING ERRCODE = 'P0002'; END` wrapped tightly around the
SELECT INTO, re-raising the SAME SQLSTATE (still catchable by any further-out
`WHEN NO_DATA_FOUND`) with only the message text corrected.

The prior session's commit (`e05dc24`) had NOT added this shim anywhere — every
genuinely-unhandled site raised PL/pgSQL's native `query returned no rows` text. This
session added the shim at the 7 sites reachable, unswallowed, from an external caller:

| Site | Routine | Clause |
|------|---------|--------|
| #10 | `send_test_notification` (public) | S-NOTIFY-018 |
| #12 | `__send_notification_by_type` (SMS branch) | S-NOTIFY-024 |
| #13 | `__send_notification_by_type` (email branch) | S-NOTIFY-025 |
| #14 | `__compose_email_msg` (event-type lookup) | S-NOTIFY-026 |
| #15 | `__compose_email_msg` (template lookup) | S-NOTIFY-026 |
| #16 | `__compose_sms_msg` (event-type lookup) | S-NOTIFY-028 |
| #17 | `__compose_sms_msg` (template lookup) | S-NOTIFY-028 |

Sites #1, #2, #4-#8 (all inside `event_notify`, escalating only to `event_notify`'s own
top-level swallow, S-NOTIFY-001) were deliberately left un-shimmed: their SQLERRM text
is never externally observable (only the "failed"/"exception:" plog lines are asserted,
never their exact SQLERRM substring), so adding the shim there would be unverifiable
scope creep with no fidelity benefit. Site #30 (`__get_notification_type_name`) is
likewise always caught by `delete_ticket_notifications`'s own top-level `WHEN OTHERS`
before reaching any external caller — same reasoning.

Verified: after this shim, the regress golden file's exact `no data found` /
`null value ... violates not-null constraint` ERROR-line SUBSTANCE now matches (see the
diff below) — only volatile CONTEXT/DETAIL formatting differs (see "Known-red" section).

## Real bug found and fixed in this session: `__send_notification_by_type`'s `p_eventdate` type

The prior commit declared `__send_notification_by_type`'s `p_eventdate` parameter as
`timestamp` (matching most of this package's other private routines). But this is the
ONE private routine the test suite calls DIRECTLY, by its declared name, with a literal
`now()` (a `timestamptz` value) — and `timestamptz -> timestamp` is an **assignment-only**
cast in PostgreSQL (`pg_cast.castcontext = 'a'`), not an implicit one, so `CALL`
resolution failed outright with `42883: procedure ... does not exist`. Changed the
parameter to `timestamptz` (matching `send_test_notification`'s own public-routine
parameter, which already used `timestamptz` for the identical reason). `timestamp ->
timestamptz` IS implicit (`castcontext = 'i'`), so `event_notify`'s own `v_eventdate
timestamp` local still resolves fine when passed in — this is a pure widening fix, no
caller was broken.

## `%TYPE` anchors

All resolved cleanly against the migrated schema — the file loads with zero errors
(only informational `NOTICE: type reference ... converted to smallint` lines for the two
`tt.ticket.emergency%TYPE` anchors, which is ora2pg/psql's normal narrowing notice, not a
failure). **No schema fix was needed for this package** — see
`migration/test/schema-fixes/22_p10_fixes.sql` (created empty, with that finding
recorded).

## Spec gaps / places the spec was silent

None beyond what the prior session already found (the SMTP-header / `OSAG_MSG` deferral,
documented in the header comments). This session's work was entirely about closing the
gap between "translated" and "green," and every gap found was in the TEST FILES
themselves (below), not the spec.

## Known-red: test-file defects (NOT translation defects), reproduced and documented

Per this plan's `<execution_rules>`: "If a test fails, the default assumption is the
translation is wrong." Every one of the following was checked against that default FIRST
— and rejected only after producing reproducible, mechanical evidence that no
translation, however faithful to Oracle, could make it pass. None of these were touched
(no file under `migration/test/` was modified by this session — verified below).

### 1. `tt__osag_notify__selectinto.sql`: 7 `throws_ok(sql, code, description)` calls hit a documented pgTAP overload footgun

pgTAP's `throws_ok(text, text, text)` 3-argument form is **ambiguous by design** (see
`/usr/share/postgresql/17/extension/pgtap--1.3.4.sql:696-703`, its own doc comment):

```
-- throws_ok ( sql, errcode, errmsg )
-- throws_ok ( sql, errmsg, description )
```

It disambiguates via `octet_length($2) = 5`: a 2nd argument that is exactly 5 characters
(any real SQLSTATE code) is treated as `(sql, errcode, errmsg)` — **not**
`(sql, errcode, description)`. `'P0002'` and `'23502'` are both 5 characters, so every
call in this file of the shape `throws_ok($$...$$, 'P0002', '<long human sentence>')`
binds that long sentence as the **expected literal `SQLERRM`**, not as a test
description. Reproduced directly against pgTAP itself (not this package):

```sql
SELECT throws_ok(
    $$DO $x$ BEGIN RAISE EXCEPTION 'no data found' USING ERRCODE='P0002'; END $x$;$$,
    'P0002',
    'some long description text here that does not match errmsg'
);
-- not ok 1 - threw P0002: some long description text here that does not match errmsg
--   caught: P0002: no data found
--   wanted: P0002: some long description text here that does not match errmsg
```

This affects tests 1-7 of `tt__osag_notify__selectinto.sql` (sites #10, #12, #13, #14/15,
#16/17, and `add_notification_event`'s NOT NULL violation) — every one now raises the
CORRECT SQLSTATE and, where applicable, the CORRECT Oracle-parity message substance
(`no data found`), but none can ever equal the full human-readable description string
pgTAP is (mis)reading as the expected `SQLERRM`. The project's OWN established
convention for this exact situation — visible in `auth__osag_auth__spec.sql`,
`mss__osag_dbprop__spec.sql`, `tt__util__spec.sql` — is `throws_like(sql, '%pattern%',
description)`, which has no such ambiguity. This file uses `throws_ok` instead at these
7 sites; the same 5-char-SQLSTATE-with-throws_ok shape also appears, unexecuted so far,
in `auth__osag_auth__spec.sql:78` (S-AUTH-008, confirmed independently failing for the
identical reason) and repeatedly in `tt__ticket_interface__*.sql` (plan 02-12, not yet
executed) — this is a systemic authoring pattern from the test-writing plans (02-05/
02-06/02-08), not specific to this package.

**Proposed fix (not applied — no test file touched by this plan):** replace
`throws_ok($$...$$, 'P0002', '<description>')` with
`throws_like($$...$$, '%no data found%', '<description>')` (and `'%not-null constraint%'`
for the `23502` case) at the 7 affected assertions.

### 2. `tt__osag_notify__selectinto.sql`: `plan(14)` but only 13 assertions exist

`grep -c '^SELECT \(throws_ok\|throws_like\|is\|ok\|lives_ok\|results_eq\)('` against the
file returns 13; `SELECT plan(14);` at the top declares 14. TAP reports "planned 14 tests
but ran 13" regardless of translation correctness — an off-by-one in the file's own
`plan()` count, present since the file's first commit (`f4fe690`, RED-by-construction).

**Proposed fix (not applied):** `plan(14)` -> `plan(13)`.

### 3. `tt__osag_notify__spec.sql` test 10: missing `stop.contact` fixture row

S-NOTIFY-021's assertion needs `delete_ticket_notifications`'s cursor
(`FROM tt.event_notification en, auth.login l, stop.contact c, tt.ticket t ... AND
c.id = l.contact_id`, an INNER join, faithfully reproducing Oracle's own
`ddl/src/pkgb/tt_osag_notify.sql:885`) to match at least one row so the loop body runs
and reaches the private `__get_notification_type_name` call whose unhandled
`NO_DATA_FOUND` (site #30) the top-level `WHEN OTHERS` is supposed to catch. The fixture
inserts `auth.login (id=900105, contact_id=900106, company_id=900107)` but never inserts
a `stop.contact` row with `id=900106` — `SET CONSTRAINTS ALL DEFERRED` (line 20) defers
the FK check (letting the INSERT itself succeed) but does **not** make the subsequent
INNER JOIN match a row that doesn't exist. Confirmed via manual query against the live
fixture: the cursor's row count is 0, so the loop body (and the exception path it's
supposed to trigger) never executes at all — `lives_ok` (test 9) passes vacuously for
the wrong reason (nothing ran, not "ran and swallowed"), and test 10's plog-content
assertion correctly finds no matching row.

**Proposed fix (not applied):**
`INSERT INTO stop.contact (id, lastname, firstname) VALUES (900106, 'Pilot', 'Contact');`
before the `auth.login` insert at line 93.

### 4. `regress/expected/tt__osag_notify__errors.out`: CONTEXT/DETAIL formatting, not substance

The file's own header comment (present since its first commit, `f4fe690`, quoting the
02-04 convention) explicitly anticipates this: *"reconciling only the CONTEXT line's
internal function/line-number formatting (never the substance) is deferred to whichever
plan lands the real translation."* After this session's shim, the SUBSTANCE now matches
exactly:

```
 ERROR:  no data found                                                    (golden, unchanged)
 ERROR:  null value in column "type_id" of relation "event" violates not-null constraint  (golden, unchanged)
```

What still differs is exactly the anticipated formatting:
- The `CONTEXT:` line's function signature/line number (this translation's final
  parameter lists/line numbers, inevitably different from the pre-translation
  placeholder).
- The `DETAIL:` line for the NOT NULL violation: PostgreSQL's default (non-`terse`)
  verbosity always includes the full failing-row snapshot, which for `tt.event`
  necessarily includes `nextval('tt.event_sequence')` and `statement_timestamp()` values
  that differ **on every single run** — no literal golden text can ever pin this
  deterministically without `\set VERBOSITY terse` in the regress SQL script itself
  (which is a genuine test-file edit, out of scope for this plan; `run-tests.sh` sets no
  such option and is shared infra out of this plan's `files_modified`). The golden
  file's own placeholder text, `"(null value(s) redacted for golden-file stability)"`,
  confirms the original author anticipated needing exactly this kind of redaction but
  left the mechanism unresolved.

**Proposed fix (not applied):** add `\set VERBOSITY terse` before the second `CALL` in
`regress/sql/tt__osag_notify__errors.sql`, and update the golden's `CONTEXT`/`DETAIL`
lines to the resulting terse, deterministic one-line form.

## `AUTH.OSAG_AUTH` unblocking (per this plan's own success criteria)

Confirmed live: with a full `--install migration/pgsql` (osag_notify now present),
`auth.osag_auth`'s pgTAP suite goes from erroring on a missing
`tt.osag_notify_delete_notifications_for_login` to **8/10 passing** (`delete_login`'s own
S-AUTH-001/004/005 assertions, which call that routine, now succeed). The remaining 2
failures (`auth__osag_auth__spec.sql` tests 2 and 7) are **pre-existing, unrelated to
OSAG_NOTIFY**:
- Test 2 (S-AUTH-007, plog-visibility check): `throws_like`'s own internal
  `EXCEPTION WHEN OTHERS` catches `delete_login`'s re-raise, and PL/pgSQL's exception-block
  savepoint semantics roll back everything performed since the start of that block —
  including the plog INSERT that ran and committed successfully *inside* `delete_login`'s
  own handler before the re-raise. Reproduced directly: an inner
  `EXCEPTION WHEN OTHERS THEN INSERT ...; RAISE;` whose write is caught by a FURTHER-OUT
  `EXCEPTION WHEN OTHERS` loses the insert, even though the inner handler ran to
  completion. This is a general PL/pgSQL savepoint fact, not something `delete_login`
  (or this package) can control.
- Test 7 (S-AUTH-008): the same `throws_ok(sql, '22023', description)` footgun as above
  (`22023` is also 5 characters).

Both are owned by plan 02-09 (already committed); out of THIS plan's scope per the
scope-boundary rule ("only auto-fix issues directly caused by the current task's
changes"). Flagged here per this plan's own instruction to check whether OSAG_NOTIFY
unblocks `auth.osag_auth`'s tests.

## Red/green status (verified live against `mcdb_test_p10b`)

- **`tt__osag_notify__spec.sql`: 9/10 pgTAP green.** Only test 10 red (test-file fixture
  gap, see above).
- **`tt__osag_notify__selectinto.sql`: 6/13 assertions individually pass** (the
  `get_isp_link_id_for_host_id` three-way host fixture — none/one/many ISP links,
  including the pilot's one `TOO_MANY_ROWS` arm — and `event_notify`'s site #9
  `TOO_MANY_ROWS`-escalates-to-outer-swallow assertion, all pass). 7 fail for the
  pgTAP-footgun reason above; the file's own `plan(14)` vs 13-actual-assertions mismatch
  additionally marks the whole file `FAIL` regardless.
- **`regress/sql/tt__osag_notify__errors.sql`: both ERROR-line substances match the
  golden exactly**; only CONTEXT/DETAIL formatting differs, for the reasons above.
- **RED half re-verified:** without this translation installed, the suite still fails
  (confirmed live against a freshly-bootstrapped `mcdb_test_p10red` with only the plog
  stub installed).
- `provenance_lint.sh`: passes. No file under `migration/test/` was modified by this
  session (verified via `git diff --name-only` against the merge-base with the spec's
  commit — empty).

## Live finding (differential harness, 2026-10-21): empty Zurich abbreviation in composed messages (S-NOTIFY-038)

Scenario `tt__osag_notify__event_notify` (Oracle 23.7 container `mcdb-ora`) compared the
20003 "sms notification" event written through the local-contact path. Oracle:
`Ticket 958120 - connection down on diff-ev-host-sms at 20.10.2026 10:30 CEST - Open Systems
Mission Control`; translation: `... at 20.10.2026 10:30  - ...` (empty abbreviation). Oracle
appends `TO_CHAR(SYSTIMESTAMP AT TIME ZONE 'EUROPE/ZURICH', 'TZD')` -- the CURRENT Zurich
abbreviation -- after every rendered date (body lines 1178, 1183, 1196, 1269, 1272, 1398). The
translation's `to_char(clock_timestamp() AT TIME ZONE 'Europe/Zurich', 'TZ')` is empty: `AT TIME
ZONE` on a timestamptz yields a `timestamp without time zone`, and `TZ` renders nothing for that
type (its header comment claimed "same observable shape (CET/CEST)" -- it was never checked
against a live value). Fixed at the three sites (`__compose_local_contact_message`,
`__compose_email_msg`, `__compose_sms_msg`) with `(SELECT abbrev FROM pg_timezone_names WHERE
name = 'Europe/Zurich')`, the DST-aware current abbreviation of the named zone. Spec clause
S-NOTIFY-038 and test amendment A-401 (two `matches()` assertions, `CES?T`) were added first.
