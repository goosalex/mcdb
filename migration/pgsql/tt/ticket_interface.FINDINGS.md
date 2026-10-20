# TT.TICKET_INTERFACE -- FINDINGS

**Source:** `ddl/src/pkg/tt_ticket_interface.sql` (spec, ~650 lines), `ddl/src/pkgb/tt_ticket_interface.sql`
(body, 2,484 lines). **Spec:** `migration/spec/tt.ticket_interface.md`. **Target:**
`migration/pgsql/tt/ticket_interface.sql`.

This is the pilot's largest translation: 38 public routines (37 distinct PostgreSQL
names -- `change_label` is the corpus's only genuine overload pair), 3 private routines,
77 `SELECT ... INTO` sites, 13 `NO_DATA_FOUND` handlers, 0 `TOO_MANY_ROWS` handlers, 10
`WHEN OTHERS` handlers. It is the first real test of the spec-first method at scale, and
the mutual-recursion cycle with `TT.EVENT_INTERFACE`/`TT.OSAG_NOTIFY`/`TT.UTIL`.

## FUNCTION-vs-COMMIT verdict for both FUNCTIONs

This package declares exactly two `FUNCTION`s. Both are created as PostgreSQL
`FUNCTION`s (`prokind='f'`), matching `name-map.csv`'s `pg_kind=function` for both rows.

1. **`get_next_recent_ticket`** (`tt.ticket_interface_get_next_recent_ticket`). Full
   Oracle body traced (`ddl/src/pkgb/tt_ticket_interface.sql:1437-1465`, 29 lines): one
   `SELECT MIN(t.id) INTO ...` aggregate query, zero `INSERT`/`UPDATE`/`DELETE`, zero
   calls to any other routine. It cannot transitively reach a `COMMIT` because it does
   not call anything at all. Call chain: NONE (leaf routine for call-out purposes). Its
   only caller *into* this routine is `TT.EVENT_INTERFACE.newevent_new` (the cycle-group
   partner) -- an inbound edge, irrelevant to this routine's own COMMIT reachability.
2. **`replace_id_placeholders`** (`tt.ticket_interface_replace_id_placeholders`). Full
   Oracle body traced (`ddl/src/pkgb/tt_ticket_interface.sql:1647-1657`, 11 lines): pure
   `REPLACE`/`SUBSTRB` string manipulation, zero database access, zero calls to anything.
   Cannot transitively reach a `COMMIT` for the same reason.

**Verdict: no FUNCTION/PROCEDURE-COMMIT hazard exists for either routine.** This
package's own two current call sites into `TT.UTIL` (which DOES `COMMIT` per
`migration/spec/tt.util.md`) are both from `change_status_event_id_out`
(`tt.util_update_status_valid_until`, twice) -- a `PROCEDURE`, not either `FUNCTION`. No
cross-package collision is reachable through this package's `FUNCTION`s. Confirms
S-TICKET-046's conclusion live. `pg_kind` remains PROVISIONAL for all 38 routines
pending Phase 3's XCUT-04 (`migration/README.md`'s standing warning) -- this FINDINGS
entry only confirms no *within-package* hazard; it does not settle the final shape.

## STRICT verdict distribution across the 77 sites, as translated

Computed directly from `migration/spec/tt.ticket_interface.md`'s own 77-row strictness
table (`## Checklist` > `### SELECT INTO strictness`):

| Verdict | Count |
|---|---|
| `STRICT, unhandled` | 42 |
| `STRICT + handler` | 18 |
| `no STRICT` (aggregate/sequence) | 17 |
| **Total** | **77** |

Every one of the 77 rows carries its `-- S-TICKET-0NN` clause-ID comment in
`migration/pgsql/tt/ticket_interface.sql`, placed directly above the translated site (120
total `S-TICKET-0NN` occurrences in the file -- some clauses cover multiple sites, e.g.
S-TICKET-032 covers 5). Sequence pulls (`nextval`/`currval`) use `SELECT ... INTO STRICT`
even where the spec verdict is `no STRICT` (harmless -- a sequence call always returns
exactly one row; matches `migration/pgsql/tt/event_interface.sql`'s established
convention). `COUNT`/`MIN`/`MAX` aggregates use plain `SELECT INTO` without `STRICT`,
same convention.

`ROWNUM = 1` -> `LIMIT 1` translation (S-TICKET-012, site #20,
`update_ux_timeout_for_ticket`'s service-window-end lookup): applied exactly per the
established mechanic (`migration/spec/tt.event_interface.md`'s S-EVENT-019 precedent) --
confirmed additionally structurally impossible to violate regardless, since
`tt.service_window` carries a genuine `UNIQUE INDEX` on `ticket_id`
(`ticket_id_uk1`, `ddl/migrated/tables/tables.pg.sql:1888`).

## AuditUsage deletion count

**36 of 36** `plog.AuditUsage(...)` call sites deleted outright (confirmed:
`grep -c AuditUsage ddl/src/pkgb/tt_ticket_interface.sql` -> 36; `awk`-cross-checked
against routine boundaries -- one call site per routine for 36 of the 38 public
routines). The 2 routines with NO `AuditUsage` call in Oracle source to begin with:
the 2-arg `change_label` overload and `deleteTicket` (neither has one in
`ddl/src/pkgb/tt_ticket_interface.sql`). The 3 private routines never had one either
(matches every sibling package's private-routine pattern). Per XCUT-06, deleted, not
stubbed -- `grep -c AuditUsage migration/pgsql/tt/ticket_interface.sql` -> 0 (the file's
own header comment is the only textual match, documenting the deletion, not code).

## Empty-string/NULL normalisations applied, parameter by parameter

Three distinct findings, matching the spec's own Checklist dimension 1 exactly (nothing
new discovered beyond what the spec already traced):

1. **`change_customer_reference.p_customer_reference`** (S-TICKET-018) and
   **`change_partner_reference.p_partner_reference`** (S-TICKET-022): boundary
   normalisation applied via `NULLIF(p_x, '') IS NOT NULL` on the audit-TEXT `IF` check
   ONLY. The `UPDATE` that writes the actual column stores `p_customer_reference`/
   `p_partner_reference` **verbatim** (unnormalised), exactly matching Oracle's own
   storage behavior (Oracle stores whatever was passed too -- only the *comparison*
   needed `''`-collapsing, not the write).
2. **`change_notification`'s `p_change_text_public`/`p_change_text_private`**
   (S-TICKET-027): NO normalisation needed or applied -- confirmed correctly handled by
   Oracle's own `IS NOT NULL`-guarded concatenation already (the prefix variable starts
   uninitialised/NULL and is only ever assigned inside the guard, so there is no
   `NULL||'x'`-collapsing-vs-not divergence to translate). PL/pgSQL variables likewise
   default to `NULL` on declaration, so this ports as a direct 1:1 translation.
3. **`add_status_change_event`'s "hide the event" check** (private routine, inherited by
   6 callers): NOT normalised -- Oracle's OWN inline comment flags this check as fragile
   ("if you ever decide to make this procedure public this has to be checked more
   carefully (whitespace-only strings...)"). Ported as-is, fragility included, per the
   spec's own instruction not to "fix" what Oracle's author explicitly left unfixed.

**One additional normalisation NOT flagged by the spec, found during translation** (see
"Places the spec left me guessing" below): `newticket_new`'s own call to
`replace_id_placeholders` needed `NULLIF(..., '')` wrapping that the spec's S-TICKET-037
clause (which only traces `replace_id_placeholders`' own body) did not call out for this
specific call site.

## GENUINE ORACLE BUG found during translation, not flagged anywhere in the spec

**Three call sites pass only 5 positional arguments to `add_status_change_event`'s
6-parameter signature** (`event_id OUT, p_ticket_id, p_public_change_text, p_contact_id,
p_private_change_text DEFAULT NULL, p_zitadel_contact_id DEFAULT NULL`):

| Call site | Oracle line | Args passed | What actually happens |
|---|---|---|---|
| `change_emergency` | `ddl/src/pkgb/tt_ticket_interface.sql:1217` | `(v_event_id, p_ticket_id, change_text, p_contact_id, p_zitadel_contact_id)` | `p_zitadel_contact_id` (this routine's own param) lands in `add_status_change_event`'s `p_private_change_text` slot (implicit Oracle `NUMBER`->`VARCHAR2` conversion) |
| `change_always_visible` | `ddl/src/pkgb/tt_ticket_interface.sql:1248` | same shape | same bug |
| `change_summary`, public-summary branch | `ddl/src/pkgb/tt_ticket_interface.sql:1323` | `(v_event_id, p_ticket_id, 'public summary changed to:'...,  p_contact_id, p_zitadel_contact_id)` | same bug -- the sibling private-summary branch (line 1310) IS the full 6-arg form and has no bug |

In all three cases, `add_status_change_event`'s own `p_zitadel_contact_id` parameter is
left at its `DEFAULT NULL` -- **the real zitadel contact id is never forwarded to the
audit event's `contact_zitadel_id` column at these 3 call sites**, and the
`details_private` column instead receives the stringified zitadel id (or stays `NULL`,
harmlessly, when the caller passed none).

**Ported faithfully, not fixed** -- per this project's translate-don't-fix methodology
(identical precedent to S-TICKET-053's `cust_id` bug and `TT.EVENT_INTERFACE.moveevent`'s
S-EVENT-033). Since PostgreSQL has **no cast at all** (not even assignment) from
`numeric` to `varchar` (confirmed: `SELECT castcontext FROM pg_cast WHERE
castsource='numeric'::regtype AND casttarget='varchar'::regtype` returns zero rows), an
explicit `::varchar` cast was required to make Oracle's *implicit* conversion happen at
all in PostgreSQL -- without it, the `CALL` would fail to resolve at CREATE/first-use
time rather than silently mis-route the value the way Oracle does. This is the specific
place a spec citing "structurally identical" bugs (S-TICKET-053 for `cust_id`) does NOT
by itself surface a *different* structural bug at 3 more call sites -- reading the actual
call-site argument counts against the private routine's signature was necessary, not
inferable from the spec text alone.

## Places the spec left me guessing (highest-value Phase 4 signal)

1. **The 3-call-site `add_status_change_event` positional-argument bug above.** The spec
   traces `add_status_change_event`'s own body thoroughly (S-TICKET-053, the `cust_id`
   bug) but does not cross-check every one of its 7 call sites' argument counts against
   its declared signature. Finding this required grepping every `add_status_change_event(`
   call site and counting arguments by hand -- a mechanical check the spec template could
   plausibly automate for Phase 4 (flag any call whose positional argument count doesn't
   match the callee's declared parameter count, cross-referenced against DEFAULTs).
2. **`replace_id_placeholders`'s `''`-vs-`NULL` boundary at its one call site.** S-TICKET-037
   fully traces the FUNCTION's own body (confirming no `SELECT`, no calls, no COMMIT
   hazard) but does not flag that its caller (`newticket_new`) needs `NULLIF(...)`
   wrapping to preserve Oracle's `SUBSTRB('',1,30000)`-collapses-to-NULL behavior --
   exactly the class of boundary-crossing fact `migration/spec/tt.event_interface.md`'s
   S-EVENT-015 already had to establish for the SAME function called from the OTHER
   package. The pattern (Pitfall 2, `NULLIF` at every FUNCTION-call boundary that
   ultimately feeds an `IS NOT NULL` check) is real and recurring, but the spec template
   traces it callee-side, not caller-side -- Phase 4's spec template should explicitly
   ask "does this FUNCTION's caller gate on the result with `IS NULL`/`IS NOT NULL`?" for
   every FUNCTION call site, not just every FUNCTION body.
3. **The private-routine naming convention's one arguable typo.** The spec's own
   recommended name for `updateTicketTimeStats` is written as
   `tt.ticket_interface__updateticketimestats` (missing a `t` -- Oracle's
   `updateTicketTimeStats` mechanically lowercases to `updatetickettimestats`, matching
   every other mechanical `package_in_name` lowercasing in this corpus, e.g.
   `updateTicketFlow` -> `ticket_interface_updateticketflow` in `name-map.csv` row 209).
   Used the corrected mechanical name (`tt.ticket_interface__updatetickettimestats`) --
   this convention lives outside `migration/mapping/name-map.csv` and remains
   unfinalized per every sibling spec's standing caveat, so this is a low-stakes
   correction, but worth flagging since Phase 4's name-map generator, if it ever absorbs
   private-routine naming, should not propagate this typo forward.
4. **`newticket_new`'s admin-permission check queries `auth.permission`**, which does not
   exist anywhere in `ddl/migrated/`, `ddl/export/`, or `changes/` -- identical situation
   to `TT.EVENT_INTERFACE.newevent_new`'s already-documented precedent
   (`migration/pgsql/tt/event_interface.FINDINGS.md`). Ported verbatim per spec (Rule 4 --
   architectural, not mechanical); no test reaches this branch (it requires
   `p_host_id IS NULL AND p_contact_id IS NOT NULL`, a company-wide-ticket path outside
   plan 02-08's test scope). Not independently re-flagged by this package's own spec
   (S-TICKET-003 mentions the query exists but does not flag the schema gap) -- decided
   here by following the sibling package's already-established disposition rather than
   re-deriving a new one.
5. **`tt.change_request.requester_zitadel_id`/`approver_zitadel_id`** -- referenced by
   `newticket_new`'s change-request-creation branch (`v_create_cr = 1`), these two
   columns exist **nowhere else in the entire repository** outside this one Oracle
   `INSERT` statement -- not in `ddl/export/`, not in `changes/changelog-current.sql`,
   not in `ddl/migrated/`. Unlike `tt.event.contact_zitadel_id`/`tt.ticket.contact_zitadel_id`
   (added by plan 02-11's schema-fix, traceable to a real, if not-yet-applied-to-snapshot,
   Liquibase changeset), there is no changelog entry to point to for these two -- the
   spec's own S-TICKET-005 clause mentions the sequence pull at this site but does not
   flag the column gap. Decided to add them via schema-fix anyway (varchar(128), matching
   `contact_zitadel_id`'s established type) rather than leave `newticket_new`'s CR-branch
   permanently broken at runtime -- see `migration/test/schema-fixes/24_p12_fixes.sql`.
6. **`fw.change` is missing from `ddl/migrated/` entirely** (not a partial-column gap
   like the two above -- the WHOLE TABLE), despite existing in the Oracle export
   (`ddl/generated/schema.oracle.sql:1579`, `CREATE TABLE FW.CHANGE (...)`). Referenced
   by `deleteTicket`'s next-to-last `DELETE` statement. A genuine ora2pg conversion gap
   (the table was silently dropped somewhere in the ora2pg pipeline, unlike the
   `contact_zitadel_id`/`requester_zitadel_id` cases which are Liquibase-changelog
   timing gaps). Added via schema-fix, matching the Oracle export's column list exactly.
   Not flagged by S-TICKET-052 (which enumerates the 31-statement cascade faithfully but,
   like every other clause in this spec, does not independently cross-check every
   referenced table's existence against `ddl/migrated/`).

## Deviations from the plan's own literal verify commands

`migration/test/bootstrap.sh`'s actual safe-name gate is
`^mcdb_(test|tmpl|harness)[a-z0-9_]*$` -- it does **not** accept `mcdb_p12` (the literal
database name this plan's own verify blocks specify). Every verify command in this
plan's Tasks 1-3 was run against `mcdb_test_p12`/`mcdb_test_p12_all`/`mcdb_test_p12_rg`
instead (Rule 3 -- auto-fix blocking issue; the substitution is purely a database-name
argument, the SQL/assertions themselves are unchanged). CLAUDE.md's own text ("Database
names must match the `mcdb_test_*`/`mcdb_p12*` safe-name pattern that bootstrap.sh
enforces") describes a broader pattern than what `bootstrap.sh` actually implements --
this is a documentation/implementation drift outside this plan's file-modification scope
to fix (bootstrap.sh lives under `migration/test/`, off-limits per the anti-circularity
wall).

## Task 3 cross-check: two real translation gaps found and fixed

Cross-checking every translated `SELECT INTO` against its clause ID and running the full
suite with the whole TT cycle group loaded surfaced two genuine translation gaps (Rule 1
-- auto-fix, both fixed in this file):

1. **`updateTicketFlow`'s `p_prev_status_change_date` needed `timestamptz`, not
   `timestamp`.** `migration/test/pgtap/tt__ticket_interface__lifecycle.sql:250` calls it
   with `now() - interval '1 hour'` (a `timestamptz` expression). PostgreSQL's
   `timestamptz`->`timestamp` cast is **assignment**-context only (confirmed:
   `SELECT castcontext FROM pg_cast WHERE castsource='timestamptz'::regtype AND
   casttarget='timestamp'::regtype` -> `'a'`), and `CALL`/function argument matching does
   NOT apply assignment casts -- only the reverse direction (`timestamp`->`timestamptz`)
   is `'i'` (implicit). Every OTHER date-ish parameter in this file stayed `timestamp`
   (matching `migration/pgsql/tt/util.sql`'s established convention and the actual naive
   `timestamp` column types throughout `tt.ticket`/`tt.ticket_flow`) -- confirmed by
   grepping every test call site against every date-ish parameter in this package for a
   `timestamptz`-typed argument; only this one parameter is ever called with one. Widened
   to `timestamptz`; internal comparisons (`GREATEST(v_flow_in_date,
   p_prev_status_change_date)`) cast it back to `::timestamp` explicitly.
2. **Two `SELECT INTO` sites needed the "no data found" message-parity shim** (XCUT-01,
   matching `tt.event_interface.demote_event`/`promote_event`'s established precedent):
   `update_ux_timeout_for_ticket` (site #18, S-TICKET-011) and `clear_todo_list` (site
   #68, S-TICKET-048) are the two sites `migration/test/regress/sql/tt__ticket_interface__errors.sql`
   pins the exact error text for -- its golden file
   (`migration/test/regress/expected/tt__ticket_interface__errors.out`) expects the
   literal string `no data found` (Oracle's `ORA-01403` text), not PL/pgSQL's native
   `query returned no rows`. Both sites now wrap the `SELECT INTO STRICT` in a local
   `BEGIN...EXCEPTION WHEN NO_DATA_FOUND THEN RAISE EXCEPTION 'no data found' USING
   ERRCODE = 'P0002'` block -- transparent, no control-flow change, matching every other
   site's `STRICT, unhandled` classification at the Oracle-behavior level (the PL/pgSQL
   syntax needs a local handler to intercept and re-raise with corrected text; Oracle
   itself never had a handler here). Only applied to these 2 specific sites, not
   corpus-wide -- matching `event_interface.sql`'s own established scope note ("required
   for regress golden parity"), not a blanket policy.

After both fixes: `run-tests.sh --install migration/pgsql --package tt.ticket_interface`
regress half now matches the golden's error TEXT exactly; the one remaining regress diff
is the `CONTEXT:` line's internal function/statement-line-number formatting (`line 1 at
SQL statement` in the golden vs. `line 25 at RAISE`/`line 29 at RAISE` in the actual
output) -- **explicitly deferred to plan 02-13 per this phase's own harness guidance**
("Regress CONTEXT-line goldens are deferred to 02-13 -- do not chase them"), not chased
further here.

## Task 3 suite results: 62/129 pgTAP, 0/1 regress (regress differs only on the deferred
## CONTEXT-line formatting above) -- full, honest breakdown of every remaining red

`bash migration/test/run-tests.sh --install migration/pgsql --package tt.ticket_interface`
(whole `migration/pgsql/` tree installed, so the full four-package TT cycle group --
`osag_plog`, `util`, `osag_notify`, `event_interface`, `ticket_interface` -- executes
together for the first time) reports **62/129 pgTAP assertions passing**. Every one of
the 67 non-passing assertions was individually triaged. **None is a translation bug.**
Every one is a pre-existing defect in an already-committed test file (written by plan
02-08, before this translation existed), falling into one of five categories below. Per
this plan's hard constraint, none of these files was touched -- `git diff --name-only
<this-plan's-first-commit>..HEAD -- migration/test/pgtap migration/test/regress` is
empty, confirmed.

### Category A -- pgTAP `throws_ok` 3-argument overload footgun (14 assertions)

**Identical defect class to `migration/test/TEST-AMENDMENTS.md`'s A-001/A-002**, which
already fixed 5 of 13 instances in `tt__ticket_interface__selectinto.sql` and 8 of ~11 in
`tt__ticket_interface__lifecycle.sql` (per A-002's own table) -- **but 14 instances
remain unfixed**, spread across all three of this package's pgTAP files. Root cause
(independently re-confirmed, matching A-001's own reproduction):
`public.throws_ok(text, text, text)`'s actual body --

```sql
IF octet_length($2) = 5 THEN
    RETURN throws_ok( $1, $2::char(5), $3, NULL );   -- $3 becomes throwmsg, NOT description!
ELSE
    RETURN throws_ok( $1, NULL, $2, $3 );
END IF;
```

-- means every 3-argument call `throws_ok(sql, 'P0002', '<long human sentence>')` (5-byte
SQLSTATE in position 2) silently promotes to the 4-arg form with the sentence in the
**message** slot, not the description slot. No error's message text is ever a
multi-clause English sentence, so these assertions can never pass regardless of
correctness. Confirmed test-by-test: every failure below shows `caught: P0002: query
returned no rows` / `wanted: P0002: <the test's own long description sentence>` --
exactly A-001's signature failure shape.

| File | Failing test # | Clause | Fix (same as A-001/A-002, NOT applied by this plan) |
|---|---|---|---|
| `tt__ticket_interface__lifecycle.sql` | 10 | S-TICKET-007 (site #12, via `change_status`) | insert `NULL,` before the description |
| `tt__ticket_interface__lifecycle.sql` | 11 | S-TICKET-008 (site #12, direct) | same |
| `tt__ticket_interface__lifecycle.sql` | 20 | S-TICKET-051 (site #77) | same |
| `tt__ticket_interface__selectinto.sql` | 2 | S-TICKET-008 (site #13) | same |
| `tt__ticket_interface__selectinto.sql` | 4 | S-TICKET-009 (site #15) | same |
| `tt__ticket_interface__selectinto.sql` | 6 | S-TICKET-020 (site #32) | same |
| `tt__ticket_interface__selectinto.sql` | 9 | S-TICKET-024 (site #38) | same |
| `tt__ticket_interface__selectinto.sql` | 11 | S-TICKET-030 (site #43) | same |
| `tt__ticket_interface__selectinto.sql` | 12 | S-TICKET-030 (site #44) | same |
| `tt__ticket_interface__selectinto.sql` | 13 | S-TICKET-034 (site #54) | same |
| `tt__ticket_interface__selectinto.sql` | 14 | S-TICKET-034 (site #56) | same |
| `tt__ticket_interface__selectinto.sql` | 17 | S-TICKET-050 (site #71) | same |
| `tt__ticket_interface__changes.sql` | 16 | S-TICKET-020 (site #31) | same |
| `tt__ticket_interface__changes.sql` | 29 | S-TICKET-024 (site #37) | same |

**Not fixed here** -- per this plan's hard constraint, only the orchestrator may amend a
test file (A-001/A-002's own precedent: "Amended by: orchestrator (touches NO translation
file)"). If amended identically to A-001/A-002 (insert `NULL,` before each description,
promoting to the unambiguous 4-arg form), all 14 would very likely flip from red to
green, since every one of these 14 `SELECT INTO` sites is, per direct code inspection
against the file committed in this plan, correctly translated with the exact
`S-TICKET-0NN` verdict the assertion's own description names.

### Category B -- test fixture defect: `last_status_change_date` left `NULL` (10 assertions)

`tt__ticket_interface__lifecycle.sql` and `tt__ticket_interface__selectinto.sql` insert
several `tt.ticket` fixture rows directly (bypassing `newticket_new`) without setting
`last_status_change_date` (e.g. `INSERT INTO tt.ticket (id, type_id, status_id,
company_id, contact_id, partner_reference) VALUES (905013, 1, 2, 905001, 905002,
'src-partner-ref');` -- no `last_status_change_date` column in the list, so it stays
`NULL`, its Oracle-and-PostgreSQL-identical default).

**This is unreachable in real production data.** `newticket_new` (this file, Task 1)
always sets `last_status_change_date` on ticket creation
(`ddl/src/pkgb/tt_ticket_interface.sql:175-184`'s `INSERT` includes it via
`SYSDATE`/`statement_timestamp()`), and `change_status_event_id_out` overwrites it on
**every** subsequent status change (`t.last_status_change_date = SYSDATE`, line 408 of
the Oracle source) -- so a ticket created through the application's own code path can
never reach `updateTicketTimeStats` with a `NULL` `p_last_status_change_date`. Only a
hand-crafted fixture that bypasses `newticket_new` entirely can construct this state.

When it IS constructed, `updateTicketTimeStats`'s `v_status_time := TRUNC((sysdate -
p_last_status_change_date) * 86400)` (Oracle) / `trunc(extract(epoch FROM
(statement_timestamp()::timestamp - p_last_status_change_date)))` (this translation) both
evaluate to `NULL` (NULL date arithmetic), and the subsequent `UPDATE
tt.ticket_time_statistic SET open_time = open_time + v_status_time` then tries to write
`NULL` into a column **both engines** declare `NOT NULL DEFAULT 0` -- confirmed against
`ddl/generated/schema.oracle.sql:594`: `OPEN_TIME NUMBER(11, 0) DEFAULT 0 NOT NULL`,
identical to the migrated PostgreSQL column. **Oracle would raise the identical class of
constraint violation (`ORA-01407`/`ORA-01400`) given this exact fixture.** This is not a
translation-introduced divergence -- it is Oracle-faithful behavior triggered by
unrealistic test data.

| File | Failing test # | Ticket | Root ticket state |
|---|---|---|---|
| `lifecycle.sql` | 13, 14 | 905010 | no `last_status_change_date` in its `INSERT` |
| `lifecycle.sql` | 27-32 (6 tests, all downstream of one `merge_tickets` call) | 905013/905014 | neither ticket's `INSERT` sets it |
| `selectinto.sql` | 3 | 907012 | no `last_status_change_date` in its `INSERT` |
| `selectinto.sql` | 15 | 907025 | no `last_status_change_date` in its `INSERT` |

**Not fixed here.** A fixture amendment would add `last_status_change_date =
statement_timestamp()` (or any non-NULL value) to each affected `INSERT`, matching what
every ticket in the real system always has by construction.

### Category C -- test fixture defect: wrong column populated (1 assertion)

`tt__ticket_interface__selectinto.sql:179`: `INSERT INTO tt.ticket (id, type_id,
status_id, company_id) VALUES (907018, 1, 907099992, NULL);` -- the fixture's own
preceding comment says this ticket's "CURRENT company_id is NOT NULL but orphaned", but
the VALUES list puts the orphaned id `907099992` into `status_id` (column 3) instead of
`company_id` (column 4), leaving `company_id` genuinely `NULL`. My translation's `IF
(v_old_company_id IS NOT NULL) THEN <lookup> ELSE v_old_company_short := '<empty>' END
IF` correctly takes the `ELSE` branch for a `NULL` `company_id` (no exception, matching
`change_company`'s S-TICKET-024 semantics exactly) -- the test (`throws_ok(...,
'P0002', ...)`, expecting an exception) was written for a value that never actually
reaches the column it names. Test 10 in `selectinto.sql` -- "caught: no exception,
wanted: P0002".

**Not fixed here.** A fixture amendment would move `907099992` from the `status_id`
position to the `company_id` position.

### Category D -- test assertion defect: `RECORD` type mismatch, cascades to 40 skipped assertions (1 direct + 40 downstream)

`tt__ticket_interface__changes.sql:299-301`:

```sql
SELECT is(
    (SELECT ROW(company_id, contact_id, mss_service_id, host_id) FROM tt.ticket WHERE id = 906013),
    ROW(906099989::numeric, NULL::numeric, NULL::numeric, NULL::numeric)::record,
    ...
);
```

Fails with `ERROR: cannot compare dissimilar column types bigint and numeric at record
column 3`. `tt.ticket.mss_service_id`/`host_id` are `bigint` in the live schema (widened
from `numeric` by `migration/test/schema-fixes/10_ora2pg_fixes.sql`'s Fix 3, an
already-committed FK-type-compatibility fix from a prior plan, well before this one --
confirmed live: `\d tt.ticket` shows `host_id bigint`, `mss_service_id bigint`,
`company_id numeric(22,0)`, `contact_id numeric(22,0)`), but the test casts **all four**
positions to `::numeric` uniformly. pgTAP's anonymous-`RECORD` `is()` comparison requires
exact type equality per column position -- this identical defect class is already
documented and amended once in this project (`TEST-AMENDMENTS.md`'s A-003, "2 x `is()`
smallint/numeric overload mismatch"). Because pgTAP scripts run inside one transaction,
this single unhandled `ERROR` aborts the **entire rest of the script** -- 40 of the
file's 70 planned assertions never execute at all (`Bad plan. You planned 70 tests but
ran 30`), none of them independently verifiable as red or green until this one line is
corrected.

**Not fixed here.** A fixture amendment would change `mss_service_id`/`host_id`'s two
`NULL::numeric` casts to `NULL::bigint` (columns 3 and 4 of the `ROW`), mirroring
A-003's exact remedy pattern for the identical defect class.

### Category E -- pre-existing architectural gap, now reachable by this package's own tests (1 assertion)

`lifecycle.sql` test 5 (`newticket_new` with `p_host_id = NULL, p_contact_id = 905002`)
dies with `relation "auth.permission" does not exist`. This is the SAME `auth.permission`
gap already documented as a deliberate, Rule-4 (architectural, not mechanical) decision
in `migration/pgsql/tt/event_interface.FINDINGS.md` for `newevent_new`'s identical query
shape -- reused disposition, not re-derived (see "Places the spec left me guessing" item
4 above). **Difference from that precedent, worth flagging explicitly:** event_interface's
equivalent branch was untested by 02-11's suite ("no test in this plan's suite reaches
this branch"); THIS package's own `lifecycle.sql` test 5 DOES reach it, because its
fixture supplies `p_host_id = NULL` with a non-NULL `p_contact_id` -- the exact condition
that triggers `newticket_new`'s company-wide-admin check. This is not a test defect (the
fixture is a completely reasonable "create a ticket with only a contact, no host" case) --
it is a real, live consequence of `auth.permission` not existing in the migrated schema,
and it means this specific pilot cannot reach fully GREEN without either (a) a schema fix
providing `auth.permission` (out of this plan's reach -- no live Oracle to derive its
current real query from, per the architectural-not-mechanical disposition already
recorded) or (b) a Phase 3/4 XCUT decision on how `newticket_new`'s admin-check should
resolve going forward.

### Category F -- test fixture/intent mismatch: wrong initial status for a "first write" test (1 assertion)

`selectinto.sql` test 20 (`S-TICKET-055: updateTicketTimeStats created a NEW
tt.ticket_time_statistic row...`) inserts ticket 907030 with `status_id = 4`
(acknowledged) then transitions it to `11` (waiting), expecting
`updateTicketTimeStats`'s first-write path to fire. `updateTicketTimeStats` only runs
when the ticket's **OLD** (pre-transition) status is in `{2, 11, 12, 60, 61, 101}`
(S-TICKET status list) -- `4` is not a member, so the routine is correctly never called,
and the assertion (`count(*) >= 1` on `tt.ticket_time_statistic`) fails because no row
was ever created. The fixture's initial `status_id` appears to be a typo for `2`
(open, which IS in the tracked set) -- consistent with every neighboring fixture in the
same file using `status_id = 2` as their "before" state for tracked-status transitions.

**Not fixed here.** A fixture amendment would change ticket 907030's initial `status_id`
from `4` to `2`.

### Summary table

| Category | Assertions affected | Root cause | Fixable by this plan? |
|---|---|---|---|
| A -- `throws_ok` footgun | 14 | pgTAP 3-arg overload ambiguity, same class as A-001/A-002 | No -- test file |
| B -- fixture NULL `last_status_change_date` | 10 | fixture omits a column every real ticket always has set | No -- test file |
| C -- fixture wrong column populated | 1 | value landed in `status_id` instead of `company_id` | No -- test file |
| D -- `RECORD` type mismatch, cascades | 1 direct + 40 skipped | `::numeric` cast vs. live `bigint` columns, same class as A-003 | No -- test file |
| E -- `auth.permission` missing (architectural) | 1 | pre-existing, already-adjudicated Rule-4 gap, now reachable | No -- architectural, out of Phase 2 scope |
| F -- fixture wrong initial status | 1 | likely typo (`4` instead of `2`) | No -- test file |
| **Total** | **67** | | |

**If categories A-D and F were amended** (all mechanically identical to already-approved
`TEST-AMENDMENTS.md` precedents, or trivial fixture-value corrections), this package
would very likely reach **127/129 pgTAP** (only category E's `auth.permission` gap would
remain red, an architectural decision genuinely outside this plan's reach) plus the
regress package's message-text match (with its `CONTEXT`-line formatting diff explicitly
deferred to plan 02-13). **Zero of these 67 red assertions indicate a defect in the
translated PL/pgSQL code itself** -- every one was traced to its root cause and
independently verified against the Oracle source, the live schema, or the pgTAP engine's
own documented dispatch behavior.

## Deviations from Oracle

Recorded per the branch owner's instruction for `phoenix/migrate_tt_only`: "Don't mimic
broken behaviour of oracle routines, but annotate/explain what changed with the
correction." Each deviation is marked `DEVIATION(ORACLE-BUG)` at the site in
`ticket_interface.sql`. Status report 2026-10-13, Q11 (b)/(c)/(d); Q11 (a) is in
`event_interface.FINDINGS.md`.

### Q11 (b) -- `add_status_change_event` resolves `company_id` from the ticket

| | |
|---|---|
| **Oracle** | `cust_id NUMBER;` declared (`ddl/src/pkgb/tt_ticket_interface.sql:1670`), inserted as `tt.event.company_id` (line 1688), never assigned. Every audit event written for `change_customer_reference`, `change_partner_reference`, `change_emergency`, `change_always_visible`, `change_notification`, `change_summary` had `company_id = NULL`. |
| **Why wrong** | Every other audit-event writer in the package resolves the company first -- `change_worker` (715), `change_service_host` (779), `change_subject` (873), `change_label` (955). The private helper simply forgot the lookup it was modelled on. |
| **Corrected** | `SELECT company_id INTO STRICT cust_id FROM tt.ticket WHERE id = p_ticket_id` before the `INSERT`, with the sibling sites' strictness profile (STRICT, unhandled) and the XCUT-01 `'no data found'` message-parity shim because the site is externally reachable through six public routines (S-TICKET-059). |
| **Changed failure mode** | A nonexistent `p_ticket_id` now raises `P0002` from the lookup. In Oracle the same call would have failed on the `tt.event -> tt.ticket` FK (`ORA-02291`) after writing nothing durable; in the pgTAP harness (constraints deferred) the pre-correction translation silently wrote an event row with a dangling `ticket_id` -- the RED run shows exactly that (test 15: `have: 1`). Never a success path either way. |
| **Spec** | S-TICKET-053 (amended), S-TICKET-059 (new), commit `26a7ef5`. |
| **Tests** | `tt__ticket_interface__corrections.sql` tests 8-15, commit `b8c18dd`, ledger A-013. RED before the fix: 9, 11, 13, 14, 15. |
| **Residual risk** | Any downstream consumer that selected these events by `company_id IS NULL` (not statically excludable, but implausible) would stop seeing them. |

### Q11 (c) -- `expire_status` and the documented `change_label` call: NO deviation

Decided "behaviour kept" (spec commit `86aec61`, S-TICKET-021 amended with the evidence).
The package-spec comment (`ddl/src/pkg/tt_ticket_interface.sql:191-202`) says
`expire_status` "calls change_label() and change_status()"; the body (`pkgb:999-1017`)
only calls `change_status`. The omission is stale documentation, not a lost feature:
the ONLY caller, `TT.UTIL.check_ticket_status` (`ddl/src/pkgb/tt_util.sql:50, 62-64`),
passes the ticket's own current `label_id` -- the parameter the doc itself calls
"current label id" -- so `change_label(p_ticket_id, p_label_id)` would write the value
already stored. Nothing in `ddl/src/` reads `label_id` in connection with status expiry;
`masterdata/TT/label.csv` holds four routing labels (Dispatch, Routine, Process, SOC)
with nothing an expiry could meaningfully apply; the body is unchanged since the base
import. The translation is untouched; the locked S-TICKET-021 assertions (label
untouched after `expire_status(..., p_label_id => 1)`) remain the pinned behaviour.

### Q11 (d) -- `remove_related_file` gets `add_related_file`'s same-company guard

| | |
|---|---|
| **Oracle** | `SELECT mcf.display_name INTO v_file_display_name FROM mc.mc_file mcf WHERE mcf.id = p_related_file_id` (`ddl/src/pkgb/tt_ticket_interface.sql:2051-2052`) inside `IF v_counter > 0`; handler `WHEN OTHERS` only. No company check anywhere in the routine. |
| **Why wrong** | `add_related_file`'s lookup joins `mc.mc_file_release` with `t.company_id = r.company_id` and its own comment (lines 2004-2006) calls that an authorization check ("make sure that ticket and mc file belong to the same company"). A guard that stops cross-company ATTACH but not cross-company DETACH protects nothing. |
| **Corrected** | The lookup additionally requires `EXISTS (SELECT 1 FROM mc.mc_file_release r, tt.ticket t WHERE t.id = p_ticket_id AND r.mc_file_id = mcf.id AND r.company_id = t.company_id)`; a dedicated `NO_DATA_FOUND` arm mirrors `add_related_file`'s (log `'MC File or ticket does not exist or they belong to different companies.'`, `RETURN`). Nothing deleted, no 100019 event, nothing raised on a refused detach (S-TICKET-060). `EXISTS` rather than a plain join because `mc.mc_file_release` has no unique key on `(mc_file_id, company_id)` -- a file released twice to one company must not turn into `TOO_MANY_ROWS` here. |
| **Unchanged** | Site #65 (`COUNT`), the `v_counter = 0` silent no-op, the same-company delete and its history event, the `WHEN OTHERS` swallow. The orphaned-file case of `tt__ticket_interface__selectinto.sql` (site #66) still succeeds -- now via the `NO_DATA_FOUND` arm. |
| **Spec** | S-TICKET-045 (amended), S-TICKET-060 (new), commit `f3b1e24`. |
| **Tests** | `tt__ticket_interface__corrections.sql` tests 1-7, commit `b8c18dd`, ledger A-013; RED before the fix: 2, 3, 4, 7. The locked `changes.sql` fixture 906028 was always labelled "same-company" but had no `mc_file_release` row -- added (A-014), plus two label-only edits (A-014/A-018 -- A-015 was renumbered at merge). |
| **Residual risk** | A relation whose file has NO release row at all (release withdrawn after attachment) can no longer be detached through this routine; Oracle allowed it. Flagged in the spec's Assumptions as an open operational question. |
