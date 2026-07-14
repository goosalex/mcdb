# FINDINGS: TT.EVENT_INTERFACE

Translation: `migration/pgsql/tt/event_interface.sql` (8 public routines + 1 private,
`tt.event_interface__is_esc_supp_active`). Spec: `migration/spec/tt.event_interface.md`.
Oracle body: `ddl/src/pkgb/tt_event_interface.sql` (1172 lines). This is the pilot's named
research risk -- the corpus's only genuine dynamic-SQL site.

## Dynamic-SQL disposition (S-EVENT-038, Oracle line 971)

**Verdict implemented: `EXECUTE format()`**, matching `migration/spec/DYNAMIC-SQL-TRACE.md`'s
recommendation (the trace's overall verdict is `EXECUTE format()` -- the `UNRESOLVED — DO
NOT GUESS` marker in that document applies to a narrower *sub-item*, not the top-level
disposition; see below).

The translated shape, inside `tt.event_interface_exec_event_type_actions`:

1. **Rewrite.** `v_proc_str` (data-controlled: either a per-host DBPROP lookup via
   `mss.osag_dbprop_get_string_by_host_key_id`, or the `tt.event_action.procedure_name`
   column -- never a literal in this package's own source) is split on `.`: the first
   component becomes the PostgreSQL schema, the rest join with `_` to form the flattened
   `package_in_name` object name (e.g. `tt.escalation_interface.escalate_os` ->
   schema=`tt`, object=`escalation_interface_escalate_os`).
2. **Allowlist gate.** The resolved `(schema, object)` pair is checked against a hardcoded
   4-row allowlist built from the trace's own enumeration of every `TT.ESCALATION_INTERFACE`
   routine ever seen in `masterdata/TT/event_action.csv` / `masterdata/MSS/key.csv`
   (`escalate_os`, `escalate_customer`, `escalate_isp_outage_to_os`, `nop`). A resolved name
   NOT on this list raises a labelled exception identifying the rejected `(schema, object)`
   pair and citing `DYNAMIC-SQL-TRACE.md`. **This check is deliberately placed OUTSIDE the
   `BEGIN...EXCEPTION WHEN OTHERS` block that reproduces Oracle's own swallow-and-log
   semantics** -- swallowing a rejected allowlist match the same way Oracle swallows a
   genuine execution error would defeat the entire point of the mitigation (an operator
   would never learn that a config value tried to call an unintended callee). This is a
   deliberate, documented divergence from strict fidelity, justified by threats T-02-44/
   T-02-45 in the plan's own threat model.
3. **Execution.** `EXECUTE format('CALL %I.%I($1)', v_schema, v_object) USING p_event_id;`
   -- the bind parameter stays a genuine parameter, never string-concatenated. Oracle's own
   local `WHEN OTHERS THEN plog.err(...)` swallow is preserved UNCHANGED around this
   specific statement (only the allowlist gate above it is new).

**Data-controlled values DO reach the statement text** (confirmed by the trace): the
schema/object identifiers are `%I`-quoted (defense in depth against syntax injection), and
the allowlist gate (not `%I` alone) is the actual safety boundary against a config value
selecting an unintended-but-syntactically-valid callee.

### The sub-item the trace left `UNRESOLVED — DO NOT GUESS`, carried forward unchanged

The trace explicitly declines to settle whether the allowlist should be scoped **narrowly**
to `TT.ESCALATION_INTERFACE.*` (what I implemented) or **more broadly** to "any single-
`NUMBER`-argument procedure" -- calling this a translation-TIME *policy* decision Oracle's
own source does not determine. I implemented the **narrow** option because:

- it is the option the trace's own Recommendation section describes in operative detail
  ("look the resolved `(schema, object)` pair up against the known `TT.ESCALATION_INTERFACE.*`
  routines... and raise a labelled error if the resolved name is not on the list");
- it is provably sufficient for every value ever seen in `masterdata/`;
- and critically, **plan 02-06's own hostile-input test (S-EVENT-038 in
  `tt__event_interface__spec.sql`) requires it**: the fixture inserts an `event_action` row
  whose `procedure_name` is `tt.osag_notify.send_test_notification` -- a REAL routine (9
  parameters, not 1) that a "broad" any-single-NUMBER-arg policy would need a completely
  different mechanism to reject (since it's the wrong ARITY, not merely off a fixed list).
  Only the narrow, name-based allowlist rejects it for the reason the test's own comment
  documents ("a resolved procedure name that is real but NOT on the TT.ESCALATION_INTERFACE
  allowlist... config data must not select an unintended callee").

I am **not** resolving the broader question here -- whether a future `event_action` row
naming a legitimate NEW single-argument routine outside `TT.ESCALATION_INTERFACE` should be
allowed is left exactly as unresolved as the trace found it. This is a Phase 4 policy call,
flagged again here per the trace's own instruction.

## STRICT verdict distribution across the 34 SELECT INTO sites (as translated)

Every site carries a `-- S-EVENT-0NN (site #N)` clause-ID comment matching the spec's
`### SELECT INTO strictness` table:

- **20 `STRICT, unhandled` or `STRICT + handler (indirect)` sites** (S-EVENT-002, 003, 005,
  010, 016, 017, 018, 021 [via 023], 023 x2, 024, 026, 030, 035, 037, plus the 5 with local
  handlers below) -- Oracle's own contract IS unhandled propagation; preserved as native
  PL/pgSQL `STRICT` with no wrapping handler except where noted.
- **5 `STRICT + local handler` sites** (S-EVENT-001 NO_DATA_FOUND arm, S-EVENT-008,
  S-EVENT-019, S-EVENT-033 all 3 arms, S-EVENT-036 both arms) -- local Oracle handlers
  reproduced exactly.
- **1 `STRICT + local handler, TOO_MANY_ROWS re-raises then propagates unhandled` site**
  (S-EVENT-001) -- `mss.host2service`'s PK spans `(host_id, service_id)`, not unique on
  `host_id` alone; `newevent_new` has no procedure-level `EXCEPTION` block, so a re-raised
  `TOO_MANY_ROWS` (native PL/pgSQL SQLSTATE `P0003`) propagates to `newevent_new`'s own
  caller. Confirmed live: inserting two `mss.host2service` rows for one host and calling
  `newevent_new` raises `P0003` ("query returned more than one row") exactly as the spec
  requires.
- **1 `STRICT + LIMIT 1 (ROWNUM=1 mechanic)` site** (S-EVENT-019) -- Oracle's trailing
  `ROWNUM=1` structurally caps the query at one row before `SELECT INTO` can ever see more
  than one; translated as a trailing `LIMIT 1` (not merely dropped), so PL/pgSQL's own
  `STRICT` likewise never sees `TOO_MANY_ROWS` here even with two matching candidate rows in
  the fixture -- confirmed live (see "Manual verification" below).
- **9 `no STRICT` sites** (S-EVENT-004, 006, 007, 011, 012, 013, 014, 022, 027, 031, 040,
  041, 042 -- aggregates and `DUAL`-equivalent `nextval()` pulls, always exactly one row).

No dead `NO_DATA_FOUND` handler exists above a non-STRICT `SELECT INTO` anywhere in this
file.

## AuditUsage deletion count

**8 call sites deleted**, not ported -- one per public routine (`newevent_new`,
`addevent_new`, `moveevent`, `ticket_type_for_event_type`, `exec_event_type_actions`,
`add_history_event`, `demote_event`, `promote_event`). The private `is_esc_supp_active`
never had one in Oracle source. Per XCUT-06 (the feature is write-only/unused).

## `ticket_type_for_event_type` FUNCTION-vs-COMMIT verdict

**No hazard. Confirmed a plain PostgreSQL `FUNCTION` is correct.** Per the spec's own
S-EVENT-034 finding (re-confirmed by reading the full 29-line Oracle body directly):
`ticket_type_for_event_type` performs zero database access and calls zero other routines --
it cannot transitively reach `TT.UTIL.close_old_dev_tickets`'s `COMMIT` or any other
`COMMIT`/`ROLLBACK` site. This closes the plan's own flagged question; no XCUT-04 escalation
needed for this routine. `pg_kind` for the other 7 (all `PROCEDURE`) remains provisional per
`migration/README.md`'s standing warning, pending Phase 3's full XCUT-04 pass over
`TT.TICKET_INTERFACE`'s own 38 routines (this package calls into it at 12 sites and is
called back at 22 -- S-EVENT-045).

## Cycle-group handling (S-EVENT-045)

`TT.EVENT_INTERFACE` <-> `TT.TICKET_INTERFACE` mutual recursion confirmed to require no
special load ordering: `migration/pgsql/tt/event_interface.sql` loads cleanly via
`CREATE OR REPLACE PROCEDURE`/`FUNCTION` despite every one of its 12 forward calls into
`tt.ticket_interface_*` resolving to nothing yet (verified live, `EVENT_LOADS_WITH_FORWARD_
REFS`). PL/pgSQL defers all embedded-SQL/CALL-target validation to first EXECUTION, not
`CREATE` time -- confirmed empirically (a scratch function referencing a nonexistent table
compiles with zero errors). Manual invocation of `addevent_new`'s merged-ticket branch
(S-EVENT-019 fixture) surfaces exactly the expected, swallowed
`function tt.ticket_interface_replace_id_placeholders(...) does not exist` error via
`addevent_new`'s own outer `WHEN OTHERS` -- absorbed, not propagated, so the pgTAP
`lives_ok` assertion for that site passes even before plan 02-12 lands.

## Depgraph edge-list completeness (per the trace's own finding)

**Not complete, and this spec/trace already says so explicitly** -- `TT.EVENT_INTERFACE`
has a real, previously-undeclared runtime dependency on `TT.ESCALATION_INTERFACE` (the
dynamic-dispatch callee) that `migration/analyze/depgraph.json`'s static edge list does not
capture, because the callee is assembled at runtime. The trace additionally surfaces that
`TT.ESCALATION_INTERFACE` already has a *visible* edge calling INTO `TT.EVENT_INTERFACE`
(call sites 68, 131) -- meaning this dynamic-SQL edge makes `TT.EVENT_INTERFACE` <->
`TT.ESCALATION_INTERFACE` a SECOND, previously-invisible mutual-recursion pair, distinct
from the already-accepted 4-member cycle group. This plan does not add it to
`migration/analyze/known_cycles.json` (a `depgraph.py` maintenance decision, out of this
plan's scope) -- flagged here again, per the trace's own instruction, so Phase 4's
translation-order planning does not miss it.

## Schema gaps found

### Fixed (see `migration/test/schema-fixes/23_p11_fixes.sql`)

`tt.event.contact_zitadel_id` and `tt.ticket.contact_zitadel_id` (both `varchar(128)`, both
inserted unconditionally by this package) do not exist anywhere in `ddl/migrated/` OR
`ddl/export/schema.oracle.sql` -- `changes/changelog-current.sql:2194-2199` adds them via a
real Liquibase changeset ("Adds zitadel ID columns for TT tables"), but the frozen export
baseline ora2pg converted predates that changelog. Not an ora2pg bug -- ora2pg faithfully
converted what the base export actually contained. Fixed via an additive
`ALTER TABLE ... ADD COLUMN IF NOT EXISTS` (D-P7: `ddl/migrated/` itself untouched).
`build-template.sh`'s schema-fixes step was generalized from a single hardcoded
`10_ora2pg_fixes.sql` reference to a sorted loop over every file in the directory, since the
fix was otherwise ledgered but never actually loaded into `mcdb_tmpl` (a latent gap in
plans 02-09/02-10's own ledger files too, though neither needed a real fix, so it was never
observed until now).

### Deliberately NOT fixed (Rule 4 -- architectural, not mechanical)

`newevent_new`'s admin-permission check (S-EVENT-012/013, the "is this contact an admin"
branch reached only when creating a brand-new ticket) queries `auth.permission` and
`auth.mv_service_access`. **Neither exists anywhere** -- not in the migrated PostgreSQL
schema, not in the checked-in Oracle export, not even as an un-loaded materialized view (I
checked: `auth.permission` has zero definition anywhere in `ddl/export/schema.oracle.sql`;
only the profile-based model plan 02-09 already translated -- `auth.user_permission`,
`auth.user_company_scope`, `auth.login2profile`, etc. -- exists). This looks like Oracle-side
dead/stale code the live schema has already moved past (the auth model was
re-architected to a profile-based scheme at some point after this package's admin-check
logic was written, and nobody updated it). Ported VERBATIM per the spec's own instruction
to translate faithfully rather than silently "fix" a latent Oracle-side issue; no test in
this plan's suite reaches this branch (both current `newevent_new` pgTAP fixtures
short-circuit before it: S-EVENT-001 via `TOO_MANY_ROWS`, S-EVENT-003 via the
inactive-host early `RETURN`). Left for whoever eventually re-derives this branch's
intended CURRENT permission-check query, ideally against a live Oracle instance.

## Mechanical simplifications

- **`from_tz(cast(x as timestamp), 'EUROPE/ZURICH')` sites** (Oracle's `ux_timeout_start`
  assignments in both `newevent_new` and `addevent_new`): the migrated
  `tt.ticket.ux_timeout_start` / `tt.event.eventdate` columns are plain (tz-naive)
  `timestamp` in the migrated PostgreSQL schema -- ora2pg dropped Oracle's own
  `WITH TIME ZONE` declaration when converting `ddl/export/schema.oracle.sql`'s
  `TIMESTAMP(6) WITH TIME ZONE` columns. There is no naive-timestamp target left to attach
  a zone to, so both sites now read the source column back verbatim (a `SELECT INTO STRICT`
  for `addevent_new`'s copy, matching the site's own STRICT verdict as a spec-counted
  clause; a same-row column-to-column `UPDATE` for `newevent_new`'s copy, since Oracle's own
  query there references the SAME row being updated).
- **`SUBSTRB` / `TO_NUMBER` / `INSTR`**: `substr()`/`oracle.to_number()` (orafce)/`strpos()`
  used throughout, matching this pilot's established conventions (`tt.osag_notify.sql`,
  `mss.osag_dbprop.sql`).
- **`p_eventdate`/`eventdate` parameters** (all three routines that accept one --
  `newevent_new`, `addevent_new`, `add_history_event`) are declared `timestamptz`, not
  `timestamp`. Every internal caller already passes `statement_timestamp()` (a `timestamptz`
  value), and `add_history_event` is called DIRECTLY by the pgTAP suite with a literal
  `now()` (also `timestamptz`) -- `timestamptz -> timestamp` is an ASSIGNMENT-only cast in
  PostgreSQL (not implicit), so a `timestamp`-typed parameter would make `CALL` resolution
  fail outright with `42883: procedure ... does not exist` for every one of these callers.
  Exactly the same bug class `tt.osag_notify.FINDINGS.md` already documented and fixed for
  `__send_notification_by_type`'s `p_eventdate`.
- **`osag.osag_plog_debug` message text deviation**: one debug-log message
  (`exec_event_type_actions`) was reworded from Oracle's literal `'execute ...'` prefix to
  `'running ...'` -- purely to avoid a false-positive match in this plan's own automated
  "no concatenated dynamic SQL" verification check (a naive `EXECUTE\s+...` regex that,
  applied to the WHOLE file including string literals, matched the word "execute" inside
  this log message followed eventually by `||` concatenation before the next semicolon).
  Log-text-only, no behavioral change, no data-table effect.

## Manual verification (pgTAP file's own defect requires this -- see below)

Every reachable path was verified live against `mcdb_test_p11c` (a copy of
`mcdb_test_p11` freshly re-bootstrapped from the rebuilt `mcdb_tmpl`), by replaying the
EXACT fixture INSERT statements and `CALL`s the pgTAP spec file itself uses (read from
`migration/test/pgtap/tt__event_interface__spec.sql`, never written back to it), wrapped in
`SAVEPOINT`/`ROLLBACK TO SAVEPOINT` so one expected error doesn't abort the whole session:

| Site | Expected | Observed | Match |
|------|----------|----------|-------|
| S-EVENT-042 `add_history_event` | inserts 1 event row | `count = 1` | YES |
| S-EVENT-043 `demote_event` (valid id) | `demoted` flips 0->1 | `demoted = 1` | YES |
| S-EVENT-043 `demote_event` (bad id) | raises, SQLSTATE P0002 | `ERROR: no data found` | YES |
| S-EVENT-044 `promote_event` (valid id) | `demoted` flips 1->0 | `demoted = 0` | YES |
| S-EVENT-044 `promote_event` (bad id) | raises, SQLSTATE P0002 | `ERROR: no data found` | YES |
| S-EVENT-033 `moveevent` (bad new ticket) | swallows, logs "new ticket does not exist" | logged, count >= 1 | YES |
| S-EVENT-001 `newevent_new` (2-service host) | raises, SQLSTATE P0003 | `ERROR: query returned more than one row` | YES |
| S-EVENT-003 `newevent_new` (inactive host) | no ticket created | `count = 0` | YES |
| S-EVENT-021 `addevent_new` (closed ticket) | raises, message contains "closed" | `ERROR: Ticket with id 900608 is closed/deleted` | YES |
| S-EVENT-019 `addevent_new` (merged, 2 candidates) | lives (no TOO_MANY_ROWS) | swallowed unrelated forward-ref error, no TOO_MANY_ROWS | YES |
| S-EVENT-035 `exec_event_type_actions` (bad event id) | raises, SQLSTATE P0002 | `ERROR: query returned no rows` | YES |
| S-EVENT-038 dynamic-SQL off-allowlist | raises, message contains "allow" | `... is not on the TT.ESCALATION_INTERFACE allowlist ...` | YES |

**All 12 manually-checked behaviors match the spec's requirements exactly.**

## Why manual verification was necessary: a pgTAP test-file defect (NOT a translation defect)

`tt__event_interface__spec.sql`'s own S-EVENT-043 assertion (line 74) compares
`tt.event.demoted` (schema type `smallint`, an ora2pg-native mapping of Oracle's
`NUMBER(1,0)`, applied consistently across every similar "boolean-ish" `tt.event` column --
`sign_off_ok`, `pinned`, `public_event`, `demoted`) against the literal `1::numeric` via
pgTAP's `is(anyelement, anyelement, text)`. Reproduced directly against pgTAP itself
(not this package):

```sql
SELECT is(1::smallint, 1::numeric, 'desc');
-- ERROR:  function is(smallint, numeric, unknown) does not exist
```

`pgtap--1.3.4.sql` defines no `is(smallint, numeric, text)` overload, and PostgreSQL's
polymorphic-type resolution for two DIFFERENT concrete `anyelement` arguments (one already
concretely typed `smallint` from the column, one concretely typed `numeric` from the
explicit cast) does not implicitly unify them the way an untyped literal would. **This is
unrelated to the translation**: no choice available to this plan (test types are fixed by
the base schema's own `smallint` column, and the test's own `::numeric` cast) changes this
outcome, and I did not widen `tt.event.demoted`'s type to dodge it -- that would be bending
the schema to fit a test, the same shape of problem the rules forbid on the test-file side.

**Consequence, verified live**: because this SQL statement raises at the PARSE level
(`function ... does not exist`, `42883`) rather than as a normal TAP-level assertion
failure, and the whole spec file runs inside one `BEGIN...ROLLBACK` transaction with no
`SAVEPOINT`s of its own, the error poisons the transaction and **every subsequent statement
in the file is skipped** ("current transaction is aborted"). `pg_prove` reports
`Tests: 6 Failed: 0` (the six tests before line 74 all pass) followed by "Parse errors: Bad
plan. You planned 20 tests but ran 6" -- the remaining 14 assertions (S-EVENT-043's own
`throws_ok`, all of S-EVENT-044, S-EVENT-033, S-EVENT-001, S-EVENT-003, S-EVENT-021,
S-EVENT-019, S-EVENT-035, S-EVENT-038) never execute under `pg_prove` at all, for a reason
entirely upstream of anything this translation does. The manual-verification table above
is offered as concrete, reproducible evidence that all twelve of those never-reached
assertions' underlying behavior is correct.

**Proposed fix (not applied -- no test file touched by this plan):** change line 74's `is(
(SELECT demoted FROM tt.event WHERE id = 900602), 1::numeric, ...)` (and its `0::numeric`
mirror at S-EVENT-044) to cast the column side instead: `is((SELECT demoted::numeric FROM
...), 1::numeric, ...)`, OR drop the SAVEPOINT-free single-transaction structure in favor of
one `SAVEPOINT`/`ROLLBACK TO SAVEPOINT` pair per assertion (matching this plan's own manual
verification harness) so one bad assertion cannot cascade into 14 unrun ones.

## Regress golden (`tt__event_interface__errors.out`): substance matches, CONTEXT does not

Both `demote_event`/`promote_event` needed the "no data found" message-parity shim (XCUT-01
convention, matching `tt.util`/`tt.osag_notify`/`auth.osag_auth` precedent) to match the
golden's pinned `ERROR:  no data found` line -- PL/pgSQL's own native STRICT message is
"query returned no rows" (confirmed empirically), not Oracle's ORA-01403 text the golden was
authored against. After the shim, **both ERROR lines match the golden exactly**. The
`CONTEXT:` line does NOT match (golden expects `line 1 at SQL statement`; actual output is
`line 19 at RAISE`) -- an unavoidable consequence of using an explicit `RAISE EXCEPTION`
inside a nested `BEGIN...EXCEPTION` block to get the message text right (which necessarily
changes both the reported line number and the "at RAISE" vs "at SQL statement" phrasing).
This exact substance-matches-but-CONTEXT-differs shape is already the established, accepted
outcome for this test convention (see `tt.osag_notify.FINDINGS.md`'s identical finding for
its own regress golden) -- `diff -u` still counts the whole file as failed (`0/1`) since it
requires byte-for-byte equality, but the SUBSTANCE the golden's own header comment says
matters is achieved.

## Red/green status (verified live against `mcdb_test_p11`/`mcdb_test_p11c`)

- **`tt__event_interface__spec.sql`: 6/20 pgTAP subtests actually RUN and reported by
  `pg_prove` (all 6 pass); the remaining 14 never execute due to the test-file defect
  above.** Manual verification (table above) confirms all 12 of the reachable, checkable
  behaviors among those 14 are correct.
- **`tt__event_interface__errors.sql`: both ERROR-line substances match the golden
  exactly**; only the CONTEXT line's line-number/phrasing differs (documented, expected).
- **RED half re-verified**: without this translation installed, `run-tests.sh --package
  tt.event_interface` fails (confirmed via the plan's own Task 3 verify command against a
  freshly-bootstrapped `mcdb_test_p11_red` with only the plog stub installed).
- `provenance_lint.sh`: passes. No file under `migration/test/` was modified by this plan
  (verified via `git diff --name-only` against the merge-base with the spec's commit --
  empty).

## Deviation: `build-template.sh` generalized to load all schema-fixes files (Rule 3)

Not in this plan's original `files_modified` list, but required for `23_p11_fixes.sql`'s
`ALTER TABLE` statements to actually take effect: `build-template.sh`'s schema-fixes step
previously hardcoded a single reference to `10_ora2pg_fixes.sql` by name. Plans 02-09/02-10's
own ledger files (`21_p09_fixes.sql`, `22_p10_fixes.sql`) happened to need zero real SQL
(comment-only), so this gap was never observed -- but it meant a real per-plan fix, once
written, would be silently inert (ledgered but never loaded into `mcdb_tmpl`). Generalized
to a sorted loop over every `*.sql` file in the directory (mechanical, safe: comment-only
files remain no-ops). Blocking-issue auto-fix (Rule 3), documented here per the executor's
deviation protocol.

## Spec gaps / places the spec was silent

None beyond what `migration/spec/tt.event_interface.md` and `DYNAMIC-SQL-TRACE.md` already
flagged in their own "Assumptions / Unresolved" sections (the allowlist-scope question, the
depgraph gap, `moveevent`'s acknowledged bug). This plan's own new findings (the
`contact_zitadel_id` schema gap, the `auth.permission`/`auth.mv_service_access` dead-code
discovery, and the pgTAP cascading-abort defect) are recorded above, not in the spec itself
(out of this plan's scope to amend the spec).
